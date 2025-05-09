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
    
    // first sample or reset
    if (sampleCount <= 1) {
        output.write(currentSample, gid);
        return;
    }
    
    
    // Calculate running average
    // Formula: new_avg = old_avg + (new_sample - old_avg) / sample_count
    // This is mathematically equivalent to: (old_avg * (n-1) + new_sample) / n
    // But has better numerical stability with high sample counts
    float4 accumulatedValue = accumulatedFrames.read(gid);
    float4 newAccumulatedValue = accumulatedValue + (currentSample - accumulatedValue) / float(sampleCount);
    output.write(newAccumulatedValue, gid);
}
