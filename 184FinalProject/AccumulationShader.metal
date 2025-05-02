//
//  AccumulationShader.metal
//  184FinalProject
//
//  Created by Brayton Lordianto on 5/1/25.
//

#include <metal_stdlib>
using namespace metal;

#include "ShaderTypes.h"

// Accumulation kernel that blends multiple frames for progressive path tracing
kernel void accumulationKernel(texture2d<float, access::read> currentFrame [[texture(0)]],
                              texture2d<float, access::read> accumulatedFrames [[texture(1)]],
                              texture2d<float, access::write> output [[texture(2)]],
                              constant uint32_t &sampleCount [[buffer(0)]],
                              uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= output.get_width() || gid.y >= output.get_height()) {
        return;
    }
    float4 currentSample = currentFrame.read(gid);
    
    // Special case for first sample or reset
    if (sampleCount <= 1) {
        output.write(currentSample, gid);
        return;
    }
    
    // Read accumulated value
    float4 accumulatedValue = accumulatedFrames.read(gid);
    
    // Calculate running average
    // Formula: new_avg = old_avg + (new_sample - old_avg) / sample_count
    // This is mathematically equivalent to: (old_avg * (n-1) + new_sample) / n
    // But has better numerical stability with high sample counts
    float4 newAccumulatedValue = accumulatedValue + (currentSample - accumulatedValue) / float(sampleCount);
    
    // Store the result
    output.write(newAccumulatedValue, gid);
}

// Adaptive accumulation kernel that handles camera movement
// When camera is moving, we rely more on current sample
// When camera is stable, we accumulate more samples for better quality
kernel void adaptiveAccumulationKernel(texture2d<float, access::read> currentFrame [[texture(0)]],
                                      texture2d<float, access::read> accumulatedFrames [[texture(1)]],
                                      texture2d<float, access::write> output [[texture(2)]],
                                      constant uint32_t &sampleCount [[buffer(0)]],
                                      constant float &cameraMovement [[buffer(1)]],
                                      uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= output.get_width() || gid.y >= output.get_height()) {
        return;
    }
    
    // Read current sample
    float4 currentSample = currentFrame.read(gid);
    if (sampleCount <= 1) {
        output.write(currentSample, gid);
        return;
    }
    float4 accumulatedValue = accumulatedFrames.read(gid);
    float movementFactor = clamp(cameraMovement, 0.0f, 1.0f);
    
    // When moving: higher weight to current frame
    // When stable: lower weight to current frame as sample count increases
    float baseFactor = 1.0f / float(sampleCount);
    float blendFactor = mix(baseFactor, 0.5f, movementFactor);
    
    float4 newValue = mix(accumulatedValue, currentSample, blendFactor);
    output.write(newValue, gid);
}
