//
//  ShaderTypes.h
//

//
//  Header containing types and enum constants shared between Metal shaders and Swift/ObjC source
//
#ifndef ShaderTypes_h
#define ShaderTypes_h

#ifdef __METAL_VERSION__
#define NS_ENUM(_type, _name) enum _name : _type _name; enum _name : _type
typedef metal::int32_t EnumBackingType;
#else
#import <Foundation/Foundation.h>
typedef NSInteger EnumBackingType;
#endif

#include <simd/simd.h>

// Constants for tile-based rendering
#define TILE_SIZE 16
#define MAX_TRIANGLES_IN_TILE 32
#define MAX_QUADS_IN_TILE 32
#define MAX_SAMPLES_PER_TILE 64

typedef NS_ENUM(EnumBackingType, BufferIndex)
{
    BufferIndexMeshPositions = 0,
    BufferIndexMeshGenerics  = 1,
    BufferIndexUniforms      = 2,
    BufferIndexTileData      = 3
};

typedef NS_ENUM(EnumBackingType, VertexAttribute)
{
    VertexAttributePosition  = 0,
    VertexAttributeTexcoord  = 1,
};

typedef NS_ENUM(EnumBackingType, TextureIndex)
{
    TextureIndexColor    = 0,
    TextureIndexCompute  = 1,
    TextureIndexTileData = 2,
};

typedef NS_ENUM(EnumBackingType, ThreadgroupIndex)
{
    ThreadgroupIndexTileData = 0,
    ThreadgroupIndexAccumData = 1
};

typedef struct
{
    matrix_float4x4 projectionMatrix;
    matrix_float4x4 modelViewMatrix;
} Uniforms;

typedef struct
{
    Uniforms uniforms[2];
} UniformsArray;

typedef struct {
    float time;
    simd_float2 resolution;
    uint32_t frameIndex;
    uint32_t sampleCount;
    simd_float3 cameraPosition;
    matrix_float4x4 viewMatrix;
    float fovY;
} ComputeParams;

// Tile-specific data structures
typedef struct TileData {
    // Per-tile accumulation data
    vector_float4 accumulatedColor;
    uint sampleCount;
    // Bounding box in world space
    vector_float3 minBounds;
    vector_float3 maxBounds;
    // Additional tile metadata
    uint tileIndex;
    bool needsReset;
} TileData;

// Structure for communicating between compute and fragment shaders
typedef struct {
    vector_float4 color;
    uint sampleCount;
} TileOutput;

#endif /* ShaderTypes_h */

