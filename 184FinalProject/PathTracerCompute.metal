//
//  PathTracerCompute.metal
//  184FinalProject
//
//  Created by Brayton Lordianto on 4/25/25.
//

#include <metal_stdlib>
using namespace metal;


//  PathTracerCompute.metal:

#include <metal_stdlib>
using namespace metal;

// Create a simple struct for compute shader data
struct ComputeParams {
    float time;
    float2 resolution;
};

// Create a simple compute shader that generates a gradient pattern
kernel void pathTracerCompute(texture2d<float, access::write> output
[[texture(0)]],
                             constant ComputeParams &params
[[buffer(0)]],
                             uint2 gid [[thread_position_in_grid]]) {
    // Get dimensions
    uint width = output.get_width();
    uint height = output.get_height();

    // Skip if out of bounds
    if (gid.x >= width || gid.y >= height) {
        return;
    }

    // Generate a simple animated pattern
    float2 uv = float2(gid) / float2(width, height);
    float3 color = float3(0.5 + 0.5 * sin(params.time + uv.x * 5.0),
                         0.5 + 0.5 * sin(params.time + uv.y * 5.0),
                         0.5 + 0.5 * sin(params.time + uv.x * uv.y *
10.0));

    // Write to output texture
    output.write(float4(color, 1.0), gid);
}
