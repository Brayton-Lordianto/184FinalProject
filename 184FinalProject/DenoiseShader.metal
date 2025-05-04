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
    return; // do nothing.
}

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
    
    const int maxStep = 4;  // Maximum step size
    const int step = max(1, min(maxStep, int(16.0 / sqrt(float(sampleCount)))));
    float4 centerColor = inputTexture.read(gid);
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
    const float denoiseStrength = max(0.1, min(0.9, 10.0 / sqrt(float(sampleCount))));
    
    float4 sum = float4(0.0);
    float totalWeight = 0.0;
    
    // Apply bilateral A-Trous wavelet filter
    for (int dy = -radius; dy <= radius; dy++) {
        for (int dx = -radius; dx <= radius; dx++) {
            int2 offset = int2(dx * step, dy * step);
            uint2 samplePos = uint2(
                min(width - 1, max(0, int(gid.x) + offset.x)),
                min(height - 1, max(0, int(gid.y) + offset.y))
            );
            float4 sampleColor = inputTexture.read(samplePos);
            float kernelWeight = g_kernel[dy + radius][dx + radius];
            float3 colorDiff = abs(sampleColor.rgb - centerColor.rgb);
            float colorDist = length(colorDiff);
            float colorWeight = exp(-(colorDist * colorDist) / (2.0 * colorSigma * colorSigma));
            float spatialDist = length(float2(offset));
            float spatialWeight = exp(-(spatialDist * spatialDist) / (2.0 * spatialSigma * spatialSigma));
            float weight = kernelWeight * colorWeight * spatialWeight;
            sum += sampleColor * weight;
            totalWeight += weight;
        }
    }
    
    // Normalize
    float4 filteredColor = sum / max(totalWeight, 0.00001);
    float4 result = mix(centerColor, filteredColor, denoiseStrength);
    outputTexture.write(result, gid);
}
