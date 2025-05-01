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
} ColorInOut;

vertex ColorInOut vertexShader(Vertex in [[stage_in]],
                               ushort amp_id [[amplification_id]],
                               constant UniformsArray & uniformsArray [[ buffer(BufferIndexUniforms) ]])
{
    ColorInOut out;
    
    Uniforms uniforms = uniformsArray.uniforms[amp_id];
    
    float4 position = float4(in.position, 1.0);
    out.position = uniforms.projectionMatrix * uniforms.modelViewMatrix * position;
    out.texCoord = in.texCoord;
    
    return out;
}

fragment float4 fragmentShader(ColorInOut in [[stage_in]],
                               texture2d<float> computeTexture [[ texture(TextureIndexCompute) ]],
                               texture2d<half> colorMap     [[ texture(TextureIndexColor) ]])
{
    // MARK: test compute shader
    float4 computeColor = computeTexture.sample(sampler(filter::linear),
      in.texCoord);
//    return computeColor;
    // if color is black,
    if (computeColor.r == 0.0 && computeColor.g == 0.0 && computeColor.b == 0.0)
    {
        discard_fragment();
    }
    return computeColor;
    // MARK: end test compute shader
}
