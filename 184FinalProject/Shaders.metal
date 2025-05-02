//
//  Shaders.metal
//

// File for Metal kernel and shader functions

#include <metal_stdlib>
#include <simd/simd.h>

// Including header shared between this Metal shader code and Swift/C code executing Metal API commands
#import "ShaderTypes.h"

using namespace metal;

typedef struct
{
    float3 position [[attribute(VertexAttributePosition)]];
    float2 texCoord [[attribute(VertexAttributeTexcoord)]];
} Vertex;

typedef struct
{
    float4 position [[position]];
    float2 texCoord;
    uint2 screenPos;
} ColorInOut;

vertex ColorInOut vertexShader(Vertex in [[stage_in]],
                               ushort amp_id [[amplification_id]],
                               constant UniformsArray & uniformsArray [[ buffer(BufferIndexUniforms) ]],
                               uint vid [[vertex_id]])
{
    ColorInOut out;
    
    Uniforms uniforms = uniformsArray.uniforms[amp_id];
    
    float4 position = float4(in.position, 1.0);
    out.position = uniforms.projectionMatrix * uniforms.modelViewMatrix * position;
    out.texCoord = in.texCoord;
    
    // Calculate screen position for tile lookup
    float2 screenPos = out.position.xy / out.position.w;
    screenPos = screenPos * 0.5 + 0.5;
    screenPos.y = 1.0 - screenPos.y;
    
    // Convert to pixel coordinates
    uint2 res = uint2(2048, 2048); // Use a reasonable large resolution as fallback
    out.screenPos = uint2(screenPos * float2(res));
    
    return out;
}

// Fragment shader that can directly access tile data without intermediate textures
fragment float4 fragmentShader(ColorInOut in [[stage_in]],
                               texture2d<float> computeTexture [[ texture(TextureIndexCompute) ]],
                               texture2d<half> colorMap [[ texture(TextureIndexColor) ]],
                               device TileData *tileData [[ buffer(BufferIndexTileData) ]])
{
    // Fallback to texture sampling for debugging purposes
    float4 computeColor = computeTexture.sample(sampler(filter::linear), in.texCoord);
    
    // Calculate which tile this fragment belongs to
    uint tileX = in.screenPos.x / TILE_SIZE;
    uint tileY = in.screenPos.y / TILE_SIZE;
    uint tilesWide = (computeTexture.get_width() + TILE_SIZE - 1) / TILE_SIZE;
    uint tileIndex = tileY * tilesWide + tileX;
    
    // Get the pre-computed accumulated color for this tile
    float4 tileColor = tileData[tileIndex].accumulatedColor;
    uint tileSampleCount = tileData[tileIndex].sampleCount;
    
    // Decide which technique to use based on rendering state
    float4 finalColor;
    
    // If the tile has valid accumulated data, use it
    if (tileSampleCount > 0) {
        finalColor = tileColor;
    } else {
        // Fallback to direct compute texture sampling
        finalColor = computeColor;
    }
    
    // Discard black fragments (useful for rendering sphere)
    if (finalColor.r == 0.0 && finalColor.g == 0.0 && finalColor.b == 0.0) {
        discard_fragment();
    }
    
    return finalColor;
}
