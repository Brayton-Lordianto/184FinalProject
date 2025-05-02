//
//  AccumulationShader.metal
//  184FinalProject
//
//  Created for path tracing accumulation.
//

#include <metal_stdlib>
#include "ShaderTypes.h"
using namespace metal;

// Kernel for accumulating path tracer samples with tile-based approach
kernel void accumulationKernel(texture2d<float, access::read> currentFrame [[texture(0)]],
                               texture2d<float, access::read> accumBuffer [[texture(1)]],
                               texture2d<float, access::write> outputTexture [[texture(2)]],
                               device TileData *tileData [[buffer(BufferIndexTileData)]],
                               constant uint& globalSampleCount [[buffer(0)]],
                               uint2 gid [[thread_position_in_grid]],
                               uint2 tid [[thread_position_in_threadgroup]],
                               uint2 blockIdx [[threadgroup_position_in_grid]],
                               threadgroup float4 *tileAccumColor [[threadgroup(ThreadgroupIndexAccumData)]]) {
    // Skip if out of bounds
    uint width = outputTexture.get_width();
    uint height = outputTexture.get_height();
    if (gid.x >= width || gid.y >= height) {
        return;
    }
    
    // Calculate tile index
    uint tileX = blockIdx.x;
    uint tileY = blockIdx.y;
    uint tilesWide = (width + TILE_SIZE - 1) / TILE_SIZE;
    uint tileIndex = tileY * tilesWide + tileX;
    
    // Initialize shared memory for this tile
    if (tid.x == 0 && tid.y == 0) {
        *tileAccumColor = tileData[tileIndex].accumulatedColor;
    }
    
    // Wait for initialization to complete
    threadgroup_barrier(mem_flags::mem_threadgroup);
    
    // Get the current sample count for this tile
    uint tileSampleCount = tileData[tileIndex].sampleCount;
    
    // Determine local position within the tile
    uint2 localPos = uint2(tileX * TILE_SIZE + tid.x, tileY * TILE_SIZE + tid.y);
    
    // If within image bounds, read current sample from the input texture
    float4 currentSample = float4(0);
    if (localPos.x < width && localPos.y < height) {
        currentSample = currentFrame.read(localPos);
    }
    
    // For the first sample, just write it directly to the output
    if (tileSampleCount <= 1) {
        if (localPos.x < width && localPos.y < height) {
            outputTexture.write(currentSample, localPos);
        }
        return;
    }
    
    // Using the accumulated color from the tile data
    float4 accumulatedColor = *tileAccumColor;
    
    // For tiles with multiple samples, apply the accumulated color
    if (localPos.x < width && localPos.y < height) {
        // Directly use accumulated tile color
        float4 blendedSample = accumulatedColor;
        
        // Write the result
        outputTexture.write(blendedSample, localPos);
    }
}

// New kernel specifically for tile-based accumulation - doesn't require intermediate textures
kernel void tileAccumulationKernel(device TileData *tileData [[buffer(BufferIndexTileData)]],
                                   texture2d<float, access::write> outputTexture [[texture(0)]],
                                   uint2 gid [[thread_position_in_grid]]) {
    // Skip if out of bounds
    uint width = outputTexture.get_width();
    uint height = outputTexture.get_height();
    if (gid.x >= width || gid.y >= height) {
        return;
    }
    
    // Calculate which tile this pixel belongs to
    uint tileX = gid.x / TILE_SIZE;
    uint tileY = gid.y / TILE_SIZE;
    uint tilesWide = (width + TILE_SIZE - 1) / TILE_SIZE;
    uint tileIndex = tileY * tilesWide + tileX;
    
    // Skip tiles without accumulated data
    if (tileData[tileIndex].sampleCount == 0) {
        return;
    }
    
    // Get the accumulated color for this tile
    float4 tileColor = tileData[tileIndex].accumulatedColor;
    
    // Write the accumulated color directly to the output
    outputTexture.write(tileColor, gid);
}
