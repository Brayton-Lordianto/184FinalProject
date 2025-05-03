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
    float3 p1;           // 16 bytes
    float3 p2;           // 16 bytes
    float3 p3;           // 16 bytes
    half3 color;         // 8 bytes
    bool isLightSource;  // 1 byte + 3 bytes padding
    float intensity;     // 4 bytes
    int materialType;    // 4 bytes
    float roughness;     // 4 bytes
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
    bool useViewMatrix;          // Whether to use view matrix in shader
} ComputeParams;

typedef struct {
    float denoiseStrength;    // 0.0 to 1.0 (higher = more aggressive denoising)
    float spatialVariance;    // Controls filter spatial spread
    float colorThreshold;     // Threshold for color similarity
    uint32_t sampleCount;     // Current sample count
} DenoiseParams;


#endif /* ShaderTypes_h */

