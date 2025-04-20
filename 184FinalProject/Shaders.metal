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

typedef struct
{
    bool hit;
    float dist;
    float3 normal;
} RayHit;



// spheres/quad/plane
#define NUM_SPHERES 2
#define NUM_QUADS 1
#define NUM_TRIANGLES 1
typedef struct { float3 c; float r; half3 color; } Sphere;
typedef struct { float3 p0, p1, p2, p3; half3 color; } Quad;
typedef struct { float3 p1, p2, p3; half3 color; } Triangle;
typedef struct
{
    Sphere spheres[NUM_SPHERES];
    Quad quads[NUM_QUADS];
    Triangle triangles[NUM_TRIANGLES];
} Scene;

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

RayHit raySphereIntersect(float3 rayOrigin, float3 rayDirection, Sphere sphere)
{
    RayHit hit;
    hit.hit = false;

    // sphere equations
    float3 oc = rayOrigin - sphere.c;
    float a = dot(rayDirection, rayDirection);
    float b = 2.0 * dot(oc, rayDirection);
    float c = dot(oc, oc) - sphere.r * sphere.r;
    float discriminant = b * b - 4 * a * c;

    if (discriminant > 0)
    {
        hit.hit = true;
        hit.dist = (-b - sqrt(discriminant)) / (2.0 * a);
        hit.normal = normalize(rayOrigin + hit.dist * rayDirection - sphere.c);
    }

    return hit;
}


RayHit rayTriangleIntersect(float3 rayOrigin, float3 rayDirection, Triangle triangle)
{
    // use Muller-Trumbore algorithm
    RayHit hit;
    hit.hit = false;
    float3 e1 = triangle.p2 - triangle.p1;
    float3 e2 = triangle.p3 - triangle.p1;
    float3 s = rayOrigin - triangle.p1;
    float3 s1 = cross(rayDirection, e2);
    float3 s2 = cross(s, e1);
    float d = dot(e1, s1);
    // No culling approach (works for triangles facing any direction)
    if (abs(d) < 1e-8) return hit;
    
    // barycentric
    float t = dot(e2, s2) / d;
    float b1 = dot(s1, s) / d;
    float b2 = dot(s2, rayDirection) / d;
    float b0 = 1.0 - b1 - b2;
    if (b1 < 0 || b1 > 1 || b2 < 0 || b2 > 1 || b0 < 0 || b0 > 1) return hit;

    // update the hit
    hit.hit = true;
    hit.normal = normalize(cross(e1, e2));
    hit.dist = t;
    return hit;
}

RayHit rayQuadIntersect(float3 rayOrigin, float3 rayDirection, Quad quad)
{
    // Create two triangles from the quad
    Triangle tri1 = { quad.p0, quad.p1, quad.p2, quad.color };
    Triangle tri2 = { quad.p0, quad.p2, quad.p3, quad.color };
    
    // Test intersection with both triangles
    RayHit hit1 = rayTriangleIntersect(rayOrigin, rayDirection, tri1);
    RayHit hit2 = rayTriangleIntersect(rayOrigin, rayDirection, tri2);
    
    // Return the closest hit
    if (hit1.hit && hit2.hit)
    {
        return (hit1.dist < hit2.dist) ? hit1 : hit2;
    }
    else if (hit1.hit)
    {
        return hit1;
    }
    else if (hit2.hit)
    {
        return hit2;
    }
    
    // No hit
    RayHit noHit;
    noHit.hit = false;
    return noHit;
}


float3 rayTrace(float3 rayPosition, float3 rayDirection, Scene scene)
{
    // Ray tracing logic here
    // Initialize hit info with a very far distance
    RayHit closestHit;
    closestHit.hit = false;
    closestHit.dist = 1000000.0; // A very large number (equivalent to c_superFar in the reference)
    
    float3 color = float3(0.0, 0.0, 0.0); // Default background color
    
    //     Check intersections with all spheres
    for (int i = 0; i < NUM_SPHERES; i++)
    {
        Sphere sphere = scene.spheres[i];
        // Skip empty spheres (those with radius 0)
        if (sphere.r <= 0.0) continue;
        
        RayHit hit = raySphereIntersect(rayPosition, rayDirection, sphere);
        if (hit.hit && hit.dist < closestHit.dist)
        {
            closestHit = hit;
            color = float3(sphere.color);
        }
    }
    
    // Check intersections with all quads
    for (int i = 0; i < NUM_QUADS; i++)
    {
        Quad quad = scene.quads[i];
        // Skip invalid quads (simple check - if all points are at origin)
        if (length(quad.p0) + length(quad.p1) + length(quad.p2) + length(quad.p3) <= 0.0) continue;
        
        RayHit hit = rayQuadIntersect(rayPosition, rayDirection, quad);
        if (hit.hit && hit.dist < closestHit.dist)
        {
            closestHit = hit;
            color = float3(quad.color);
        }
    }
    
    // Check intersections with all triangles
    for (int i = 0; i < NUM_TRIANGLES; i++)
    {
        Triangle triangle = scene.triangles[i];
        // Skip invalid triangles (simple check - if all points are at origin)
        if (length(triangle.p1) + length(triangle.p2) + length(triangle.p3) <= 0.0) continue;
        
        RayHit hit = rayTriangleIntersect(rayPosition, rayDirection, triangle);
        if (hit.hit && hit.dist < closestHit.dist)
        {
            closestHit = hit;
            color = float3(triangle.color);
        }
    }
    
    // If we didn't hit anything, return the background color
    if (!closestHit.hit)
    {
        // You could implement a background gradient or skybox here
        // For now, let's return a simple gradient based on ray direction
        return float3(0.5 + 0.5 * rayDirection.y, 0.7, 0.9 + 0.1 * rayDirection.y);
    }
    
    // Add some basic lighting
    float3 lightDir = normalize(float3(1.0, 1.0, -1.0));
    float diffuse = max(0.0, dot(closestHit.normal, -lightDir));
    float ambient = 0.2;
    
    return color * (ambient + diffuse);

}

fragment float4 fragmentShader(ColorInOut in [[stage_in]],
                               texture2d<half> colorMap     [[ texture(TextureIndexColor) ]])
{
    Scene scene = {
        .spheres = {
            { float3(0, 0, -5), 1.0, half3(1, 0, 0) },
            { float3(2, 0, -5), 1.0, half3(0, 1, 0) }
        },
        .quads = {
            { float3(-2, -2, -5), float3(2, -2, -5), float3(2, 2, -5), float3(-2, 2, -5), half3(1, 0, 0) }
        },
        .triangles = {
            { float3(2, 0, -6), float3(0, 0, -6), float3(0, 1, -6), half3(1, 1, 0) }
        }
    };
    
    float2 uv = in.texCoord;
    float2 normalizedUV = uv * 2 - 1; // -1 (top left) to +1 (bottom right)
    float3 rayPosition = float3(0);
    float3 rayTarget = float3(normalizedUV, 1.0);
//    float2 resolution = in.position.xy / in.texCoord;
//    rayTarget.y /= resolution.x / resolution.y; // aspect ratio messes things up. i think it's already accounted for in projection matrix in vertex shader.
    float3 rayDirection = normalize(rayTarget - rayPosition);
    float3 color = rayTrace(rayPosition, rayDirection, scene);
    return float4(color.xyz, 1);
}
