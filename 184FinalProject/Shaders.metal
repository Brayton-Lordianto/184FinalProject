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

// Ray Tracing
#define NUM_MONTE_CARLO_SAMPLES 1
typedef struct RayHit
{
    bool hit = false;
    float dist;
    float3 normal;
    float3 albedo = 0; // for diffuse surfaces
    float3 emission = 0; // for light sources
} RayHit;

// spheres/quad/plane
#define SUPER_FAR 1000000.0
#define NUM_SPHERES 1
#define NUM_QUADS 15
#define NUM_TRIANGLES 1
typedef struct { float3 c; float r; half3 color; } Sphere;
typedef struct { float3 p0, p1, p2, p3; half3 color; } Quad;
typedef struct Triangle { float3 p1, p2, p3; half3 color; bool isLightSource=false; } Triangle;
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

// MARK: RNG :- taken online
// Wang hash function for random number generation
uint wang_hash(uint seed)
{
    seed = uint(seed ^ uint(61)) ^ uint(seed >> uint(16));
    seed *= uint(9);
    seed = seed ^ (seed >> 4);
    seed *= uint(0x27d4eb2d);
    seed = seed ^ (seed >> 15);
    return seed;
}

// Generate a random float between 0 and 1
float RandomFloat01(thread uint& state)
{
    state = wang_hash(state);
    return float(state) / 4294967296.0;
}

// Generate a random unit vector (for directions)
float3 RandomUnitVector(thread uint& state)
{
    float z = RandomFloat01(state) * 2.0f - 1.0f;
    float a = RandomFloat01(state) * 2.0f * M_PI_F;
    float r = sqrt(1.0f - z * z);
    float x = r * cos(a);
    float y = r * sin(a);
    return float3(x, y, z);
}
// MARK: END


// MARK: Basic Object Ray Tracing Equations
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
    hit.dist = -t;
    hit.emission = (triangle.isLightSource) ? float3(triangle.color) : float3(0);
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
// MARK: END


RayHit rayTraceHit(float3 rayPosition, float3 rayDirection, Scene scene)
{
    RayHit closestHit;
    closestHit.hit = false;
    closestHit.dist = SUPER_FAR; // A very large number (equivalent to c_superFar in the reference)
    float3 color = float3(0.5 + 0.5 * rayDirection.y, 0.7, 0.9 + 0.1 * rayDirection.y); // background
    
    // Check intersections with all spheres
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
    
    closestHit.albedo = color;
    return closestHit;
}

float3 pathTrace(float3 rayOrigin, float3 rayDirection, Scene scene, thread uint& rng)
{
    float3 ret = float3(0);
    float3 irradiance = float3(1);
    float3 rayPos = rayOrigin;
    float3 rayDir = rayDirection;
    
    int c_numBounces = 3;
    float c_rayPosNormalNudge = 0.001;
    for (int bounce = 0; bounce <= c_numBounces; ++bounce)
    {
        // Use the current ray position and direction
        RayHit hit = rayTraceHit(rayPos, rayDir, scene);
        if (!hit.hit || hit.dist >= SUPER_FAR) {
            // Add background contribution and break
            float3 backgroundColor = float3(0.5 + 0.5 * rayDir.y, 0.7, 0.9 + 0.1 * rayDir.y);
            ret += backgroundColor * irradiance;
            break;
        }
        // Compute the intersection point and update the ray
        float3 hitPoint = rayPos + rayDir * hit.dist;
        // Add emission contribution
        ret += hit.emission * irradiance;
        // Update for next bounce
        rayPos = hitPoint + hit.normal * c_rayPosNormalNudge; // Nudge to avoid self-intersection with the point you just intersected with.
        rayDir = normalize(hit.normal + RandomUnitVector(rng));
        // Update the throughput for next bounce
        irradiance *= hit.albedo;
    }
    return ret;
}

fragment float4 fragmentShader(ColorInOut in [[stage_in]],
                               texture2d<float> computeTexture [[ texture(TextureIndexCompute) ]],
                               texture2d<half> colorMap     [[ texture(TextureIndexColor) ]])
{
    // MARK: test compute shader
//    float4 computeColor = computeTexture.sample(sampler(filter::linear),
//      in.texCoord);
//    return computeColor; 
    // MARK: end test compute shader
//    Scene scene;
//    scene = {
//        .spheres = {
//            { float3(0, 0, -5), 1.0, half3(0, 0, 1) },
//            { float3(2, 0, -5), 1.0, half3(0, 1, 0) }
//        },
//        .quads = {
//            { float3(-2, -2, -5), float3(2, -2, -5), float3(2, 2, -5), float3(-2, 2, -5), half3(1, 0, 0) }
//        },
//        .triangles = { // more negative means closer to you.
//            { float3(2, 0, -6), float3(0, 0, -6), float3(0, 1, -6), half3(1, 1, 0) }
//        }
//    };
    
    // simple cornell box.
    Scene scene = {
        .spheres = {
        },
        .quads = {
            // Room walls, floor, ceiling
            { float3(-2, -2, -8), float3(2, -2, -8), float3(2, 2, -8), float3(-2, 2, -8), half3(0.5, 0.5, 0.8) },  // Back wall (blue)
            { float3(-2, -2, -8), float3(-2, 2, -8), float3(-2, 2, -3), float3(-2, -2, -3), half3(0.8, 0.2, 0.2) },  // Left wall (red)
            { float3(2, -2, -8), float3(2, -2, -3), float3(2, 2, -3), float3(2, 2, -8), half3(0.2, 0.8, 0.2) },  // Right wall (green)
            { float3(-2, -2, -8), float3(2, -2, -8), float3(2, -2, -3), float3(-2, -2, -3), half3(0.7, 0.7, 0.7) },  // Floor (light gray)
            { float3(-2, 2, -8), float3(-2, 2, -3), float3(2, 2, -3), float3(2, 2, -8), half3(0.7, 0.7, 0.7) },  // Ceiling (light gray)
            
            // Tall box
            { float3(-1.0, -2.0, -6.5), float3(-0.2, -2.0, -6.5), float3(-0.2, 0.3, -6.5), float3(-1.0, 0.3, -6.5), half3(0.9, 0.7, 0.3) },  // Front face (orange)
            { float3(-1.0, -2.0, -7.5), float3(-1.0, -2.0, -6.5), float3(-1.0, 0.3, -6.5), float3(-1.0, 0.3, -7.5), half3(0.9, 0.7, 0.3) },  // Left face
            { float3(-0.2, -2.0, -7.5), float3(-0.2, -2.0, -6.5), float3(-0.2, 0.3, -6.5), float3(-0.2, 0.3, -7.5), half3(0.9, 0.7, 0.3) },  // Right face
            { float3(-1.0, -2.0, -7.5), float3(-0.2, -2.0, -7.5), float3(-0.2, 0.3, -7.5), float3(-1.0, 0.3, -7.5), half3(0.9, 0.7, 0.3) },  // Back face
            { float3(-1.0, 0.3, -7.5), float3(-0.2, 0.3, -7.5), float3(-0.2, 0.3, -6.5), float3(-1.0, 0.3, -6.5), half3(0.9, 0.7, 0.3) },  // Top face
            
            // Short box
            { float3(0.2, -2.0, -5.5), float3(1.0, -2.0, -5.5), float3(1.0, -1.0, -5.5), float3(0.2, -1.0, -5.5), half3(0.3, 0.6, 0.9) },  // Front face (blue-ish)
            { float3(0.2, -2.0, -6.5), float3(0.2, -2.0, -5.5), float3(0.2, -1.0, -5.5), float3(0.2, -1.0, -6.5), half3(0.3, 0.6, 0.9) },  // Left face
            { float3(1.0, -2.0, -6.5), float3(1.0, -2.0, -5.5), float3(1.0, -1.0, -5.5), float3(1.0, -1.0, -6.5), half3(0.3, 0.6, 0.9) },  // Right face
            { float3(0.2, -2.0, -6.5), float3(1.0, -2.0, -6.5), float3(1.0, -1.0, -6.5), float3(0.2, -1.0, -6.5), half3(0.3, 0.6, 0.9) },  // Back face
            { float3(0.2, -1.0, -6.5), float3(1.0, -1.0, -6.5), float3(1.0, -1.0, -5.5), float3(0.2, -1.0, -5.5), half3(0.3, 0.6, 0.9) },  // Top face
        },
        .triangles = {
            { float3(0, 1.9, -5), float3(-1, 1.9, -6.5), float3(1, 1.9, -6.5), half3(1, 1, 1), true }  // Light source 
//            { float3(-2, 2, -8), float3(-2, 2, -3), float3(2, 2, -3), half3(1,1,0),true},
//            { float3(-2, 2, -8), float3(2, 2, -3), float3(2, 2, -8), half3(1,1,0),true}, // Light source (yellow triangle)
        }
    };
    
    uint rngState = uint(in.position.x * 1973 + in.position.y * 9277) | 1;
    float2 uv = in.texCoord;
    float theta = (uv.x) * 2.0 * M_PI_F; // longitude: 0 to 2π
    float phi   = (1.0 - uv.y) * M_PI_F; // latitude: 0 to π (flip y to match screen coords)
    float3 rayPosition = float3(0);
    float3 rayDirection;
    rayDirection.x = sin(phi) * cos(theta);
    rayDirection.y = cos(phi);
    rayDirection.z = sin(phi) * sin(theta);
    
    // Apply tiny random jitter to ray direction for anti-aliasing
    rayDirection = normalize(rayDirection + RandomUnitVector(rngState) * 0.001);
    float3 color = float3(0);
    for (int i = 0; i < NUM_MONTE_CARLO_SAMPLES; ++i)
        color += pathTrace(rayPosition, rayDirection, scene, rngState);
    color /= NUM_MONTE_CARLO_SAMPLES;
//    float3 color = rayTraceHit(rayPosition, rayDirection, scene).albedo;
    return float4(color.xyz, 1);
}
