//
//  DenoiseShader.metal
//  184FinalProject
//
//  Created by Brayton Lordianto on 5/2/25.
//

#include <metal_stdlib>
using namespace metal;

#include "ShaderTypes.h"

// Fast, lightweight denoising based on a spatially-varying blur
// Optimized for real-time performance on mobile hardware
kernel void fastDenoiseKernel(texture2d<float, access::read> inputTexture [[texture(0)]],
                             texture2d<float, access::write> outputTexture [[texture(1)]],
                             constant uint32_t &sampleCount [[buffer(0)]],
                             uint2 gid [[thread_position_in_grid]]) {
    
    // Get dimensions and check bounds
    const int width = inputTexture.get_width();
    const int height = inputTexture.get_height();
    
    if (gid.x >= width || gid.y >= height) {
        return;
    }
    
    // Define denoising parameters based on sample count
    const float denoiseStrength = max(0.1, min(1.0, 8.0 / float(sampleCount)));
    const float spatialVariance = 1.0; // Fixed small radius for performance
    const float colorThreshold = 0.1;  // Sensitivity to edges
    
    // Get center pixel color
    float4 centerColor = inputTexture.read(gid);
    
    // Use a small 3x3 kernel for efficiency on mobile hardware
    const int radius = 1;
    
    // Simple weighted sum with edge-awareness
    float4 sum = float4(0.0);
    float totalWeight = 0.0;
    
    // Small fixed-size loop for better performance
    for (int dy = -radius; dy <= radius; dy++) {
        for (int dx = -radius; dx <= radius; dx++) {
            // Skip center pixel (we'll handle it separately for better weighting)
            if (dx == 0 && dy == 0) continue;
            
            // Calculate sample position with clamping to texture edges
            uint2 samplePos = uint2(
                min(width - 1, max(0, int(gid.x) + dx)),
                min(height - 1, max(0, int(gid.y) + dy))
            );
            
            // Get sample color
            float4 sampleColor = inputTexture.read(samplePos);
            
            // Spatial weight (distance-based)
            float spatialDist = float(dx * dx + dy * dy);
            float spatialWeight = exp(-spatialDist / (2.0 * spatialVariance * spatialVariance));
            
            // Color similarity weight (edge-preserving)
            float3 colorDiff = abs(sampleColor.rgb - centerColor.rgb);
            // Use luminance-weighted difference for better perceptual results
            float colorDist = dot(colorDiff, float3(0.299, 0.587, 0.114));
            float colorWeight = exp(-colorDist / colorThreshold);
            
            // Combined weight
            float weight = spatialWeight * colorWeight;
            
            // Accumulate
            sum += sampleColor * weight;
            totalWeight += weight;
        }
    }
    
    // Add center pixel with high weight to preserve details
    const float centerWeight = 1.5;
    sum += centerColor * centerWeight;
    totalWeight += centerWeight;
    
    // Normalize
    float4 filteredColor = sum / max(totalWeight, 0.001);
    
    // Adaptive denoising strength based on sample count
    // Less aggressive denoising as sample count increases
    float adaptiveStrength = denoiseStrength * max(0.1, min(1.0, 10.0 / float(sampleCount)));
    
    // Blend between original and filtered based on adaptive strength
    float4 result = mix(centerColor, filteredColor, adaptiveStrength);
    
    // Write result
    outputTexture.write(result, gid);
}

// Enhanced version of our fastDenoiseKernel for higher quality denoising
// Implements a simple, mobile-friendly A-Trous wavelet filter
kernel void enhancedDenoiseKernel(texture2d<float, access::read> inputTexture [[texture(0)]],
                                 texture2d<float, access::write> outputTexture [[texture(1)]],
                                 constant uint32_t &sampleCount [[buffer(0)]],
                                 uint2 gid [[thread_position_in_grid]]) {
    
    // Get dimensions and check bounds
    const int width = inputTexture.get_width();
    const int height = inputTexture.get_height();
    
    if (gid.x >= width || gid.y >= height) {
        return;
    }
    
    // A-Trous filter with adaptive step size based on sample count
    // Fewer samples = larger filter for noise reduction
    const int maxStep = 4;  // Maximum step size
    const int step = max(1, min(maxStep, int(16.0 / sqrt(float(sampleCount)))));
    
    // Get center pixel color
    float4 centerColor = inputTexture.read(gid);
    
    // Use a 5x5 filter kernel for better quality
    const int radius = 2;
    
    // These weights approximate a Gaussian filter
    // 3x3 kernel: [1,2,1; 2,4,2; 1,2,1] / 16
    const float g_kernel[5][5] = {
        {1.0/256.0, 4.0/256.0,  6.0/256.0,  4.0/256.0, 1.0/256.0},
        {4.0/256.0, 16.0/256.0, 24.0/256.0, 16.0/256.0, 4.0/256.0},
        {6.0/256.0, 24.0/256.0, 36.0/256.0, 24.0/256.0, 6.0/256.0},
        {4.0/256.0, 16.0/256.0, 24.0/256.0, 16.0/256.0, 4.0/256.0},
        {1.0/256.0, 4.0/256.0,  6.0/256.0,  4.0/256.0, 1.0/256.0}
    };
    
    // Edge-stopping function parameters 
    const float colorSigma = 0.15;       // Color similarity threshold
    const float spatialSigma = 2.0;      // Spatial filter spread
    
    // Adaptive denoising strength that decreases with more samples
    const float denoiseStrength = max(0.1, min(0.9, 10.0 / sqrt(float(sampleCount))));
    
    float4 sum = float4(0.0);
    float totalWeight = 0.0;
    
    // Apply bilateral A-Trous wavelet filter
    for (int dy = -radius; dy <= radius; dy++) {
        for (int dx = -radius; dx <= radius; dx++) {
            // A-Trous pattern - sample with step size 
            int2 offset = int2(dx * step, dy * step);
            
            // Calculate sample position with clamping
            uint2 samplePos = uint2(
                min(width - 1, max(0, int(gid.x) + offset.x)),
                min(height - 1, max(0, int(gid.y) + offset.y))
            );
            
            // Get sample color
            float4 sampleColor = inputTexture.read(samplePos);
            
            // Get kernel weight at this position
            float kernelWeight = g_kernel[dy + radius][dx + radius];
            
            // Color similarity weight (edge-preserving)
            float3 colorDiff = abs(sampleColor.rgb - centerColor.rgb);
            float colorDist = length(colorDiff);
            float colorWeight = exp(-(colorDist * colorDist) / (2.0 * colorSigma * colorSigma));
            
            // Spatial weight
            float spatialDist = length(float2(offset));
            float spatialWeight = exp(-(spatialDist * spatialDist) / (2.0 * spatialSigma * spatialSigma));
            
            // Combined weight
            float weight = kernelWeight * colorWeight * spatialWeight;
            
            // Accumulate
            sum += sampleColor * weight;
            totalWeight += weight;
        }
    }
    
    // Normalize
    float4 filteredColor = sum / max(totalWeight, 0.00001);
    
    // Blend between original and filtered based on adaptive strength
    float4 result = mix(centerColor, filteredColor, denoiseStrength);
    
    // Write result
    outputTexture.write(result, gid);
}
