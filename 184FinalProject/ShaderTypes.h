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

typedef struct {
    float time;
    simd_float2 resolution;
    uint32_t frameIndex;
    uint32_t sampleCount;
    simd_float3 cameraPosition;
    matrix_float4x4 viewMatrix;
    matrix_float4x4 inverseViewMatrix;
    matrix_float4x4 projectionMatrix;
    float fovY;
    float fovX;
    uint32_t modelTriangleCount;

    //for aberration simulation
    float lensRadius;
    float focalDistance;
    float SPH;
    float CYL;
    float AXIS;
} ComputeParams;



#endif /* ShaderTypes_h */

