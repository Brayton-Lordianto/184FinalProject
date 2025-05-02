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

typedef NS_ENUM(EnumBackingType, BufferIndex)
{
    BufferIndexMeshPositions = 0,
    BufferIndexMeshGenerics  = 1,
    BufferIndexUniforms      = 2
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

#ifdef __METAL_VERSION__
// Material types matching those in Swift
typedef enum {
    DIFFUSE = 0,
    METAL = 1,
    DIELECTRIC = 2
} MaterialType;

// Triangle structure matching Swift side
typedef struct {
    packed_float3 p1;       // 12 bytes
    float _padding0;        // 4 bytes (padding to align to 16 bytes)
    packed_float3 p2;       // 12 bytes
    float _padding1;        // 4 bytes
    packed_float3 p3;       // 12 bytes
    float _padding2;        // 4 bytes
    packed_half3 color;     // 6 bytes
    float _padding3;        // 4 byttes
    bool isLightSource;     // 1 byte
    float intensity;        // 4 bytes
    int materialType;       // 4 bytes
    float roughness;        // 4 bytes
} GPUTriangle;
#endif

typedef struct {
    float time;
    simd_float2 resolution;
    uint32_t frameIndex;
    uint32_t sampleCount;
    simd_float3 cameraPosition;
    matrix_float4x4 viewMatrix;
    float fovY;
    uint32_t modelTriangleCount; // Number of active model triangles
} ComputeParams;


#endif /* ShaderTypes_h */

