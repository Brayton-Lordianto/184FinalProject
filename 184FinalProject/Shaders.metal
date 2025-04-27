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
#define NUM_MONTE_CARLO_SAMPLES 4 // Increased from 1 to 4 for better quality
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
#define NUM_TRIANGLES 1 // Regular triangles (non-light)
#define NUM_LIGHTS 1 // Separate light sources
#define SHADOW_BIAS 0.001f // Bias to prevent self-intersection for shadow rays

typedef struct { float3 c; float r; half3 color; } Sphere;
typedef struct { float3 p0, p1, p2, p3; half3 color; } Quad;
typedef struct { float3 p1, p2, p3; half3 color; } Triangle;
typedef struct { float3 p1, p2, p3; half3 color; float intensity; } Light; // Light is now a separate type

typedef struct
{
    Sphere spheres[NUM_SPHERES];
    Quad quads[NUM_QUADS];
    Triangle triangles[NUM_TRIANGLES];
    Light lights[NUM_LIGHTS]; // Separate array for lights
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

// Generate a random direction in the hemisphere around the normal
float3 RandomInHemisphere(float3 normal, thread uint& state)
{
    float3 inUnitSphere = RandomUnitVector(state);
    if (dot(inUnitSphere, normal) > 0.0) // In the same hemisphere as the normal
        return inUnitSphere;
    else
        return -inUnitSphere;
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

RayHit rayTriangleIntersect(float3 rayOrigin, float3 rayDirection, float3 v0, float3 v1, float3 v2)
{
    // Use Muller-Trumbore algorithm
    RayHit hit;
    hit.hit = false;
    float3 e1 = v1 - v0;
    float3 e2 = v2 - v0;
    float3 s = rayOrigin - v0;
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
    // Test intersection with both triangles that make up the quad
    RayHit hit1 = rayTriangleIntersect(rayOrigin, rayDirection, quad.p0, quad.p1, quad.p2);
    RayHit hit2 = rayTriangleIntersect(rayOrigin, rayDirection, quad.p0, quad.p2, quad.p3);
    
    // Return the closest hit
    if (hit1.hit && hit2.hit)
    {
        RayHit closest = (hit1.dist < hit2.dist) ? hit1 : hit2;
        closest.albedo = float3(quad.color);
        return closest;
    }
    else if (hit1.hit)
    {
        hit1.albedo = float3(quad.color);
        return hit1;
    }
    else if (hit2.hit)
    {
        hit2.albedo = float3(quad.color);
        return hit2;
    }
    
    // No hit
    RayHit noHit;
    noHit.hit = false;
    return noHit;
}
// MARK: END

// Light intersection (for visibility/shadow tests only)
bool rayLightIntersect(float3 rayOrigin, float3 rayDirection, Light light, float maxDist)
{
    RayHit hit = rayTriangleIntersect(rayOrigin, rayDirection, light.p1, light.p2, light.p3);
    return hit.hit && hit.dist > 0 && hit.dist < maxDist;
}

RayHit rayTraceHit(float3 rayPosition, float3 rayDirection, Scene scene)
{
    RayHit closestHit;
    closestHit.hit = false;
    closestHit.dist = SUPER_FAR;
    float3 color = float3(0.5 + 0.5 * rayDirection.y, 0.7, 0.9 + 0.1 * rayDirection.y); // background
    
    // Check intersections with all spheres
    for (int i = 0; i < NUM_SPHERES; i++)
    {
        Sphere sphere = scene.spheres[i];
        // Skip empty spheres (those with radius 0)
        if (sphere.r <= 0.0) continue;
        
        RayHit hit = raySphereIntersect(rayPosition, rayDirection, sphere);
        if (hit.hit && hit.dist < closestHit.dist && hit.dist > 0)
        {
            closestHit = hit;
            closestHit.albedo = float3(sphere.color);
        }
    }
    
    // Check intersections with all quads
    for (int i = 0; i < NUM_QUADS; i++)
    {
        Quad quad = scene.quads[i];
        // Skip invalid quads (simple check - if all points are at origin)
        if (length(quad.p0) + length(quad.p1) + length(quad.p2) + length(quad.p3) <= 0.0) continue;
        
        RayHit hit = rayQuadIntersect(rayPosition, rayDirection, quad);
        if (hit.hit && hit.dist < closestHit.dist && hit.dist > 0)
        {
            closestHit = hit;
            closestHit.albedo = float3(quad.color);
        }
    }
    
    // Check intersections with all regular triangles
    for (int i = 0; i < NUM_TRIANGLES; i++)
    {
        Triangle triangle = scene.triangles[i];
        // Skip invalid triangles
        if (length(triangle.p1) + length(triangle.p2) + length(triangle.p3) <= 0.0) continue;
        
        RayHit hit = rayTriangleIntersect(rayPosition, rayDirection, triangle.p1, triangle.p2, triangle.p3);
        if (hit.hit && hit.dist < closestHit.dist && hit.dist > 0)
        {
            closestHit = hit;
            closestHit.albedo = float3(triangle.color);
        }
    }
    
    // Check intersections with all lights
    for (int i = 0; i < NUM_LIGHTS; i++)
    {
        Light light = scene.lights[i];
        // Skip invalid lights
        if (length(light.p1) + length(light.p2) + length(light.p3) <= 0.0) continue;
        
        RayHit hit = rayTriangleIntersect(rayPosition, rayDirection, light.p1, light.p2, light.p3);
        if (hit.hit && hit.dist < closestHit.dist && hit.dist > 0)
        {
            closestHit = hit;
            closestHit.albedo = float3(light.color);
            closestHit.emission = float3(light.color) * light.intensity;
        }
    }
    
    return closestHit;
}

// Shadow test - returns true if point is in shadow
bool isInShadow(float3 point, float3 lightDir, float lightDistance, Scene scene) 
{
    // Add bias to avoid self-intersection
    float3 shadowRayOrigin = point + lightDir * SHADOW_BIAS;
    
    // Check against all non-light objects
    for (int i = 0; i < NUM_SPHERES; i++) {
        Sphere sphere = scene.spheres[i];
        if (sphere.r <= 0.0) continue;
        
        RayHit hit = raySphereIntersect(shadowRayOrigin, lightDir, sphere);
        if (hit.hit && hit.dist > 0 && hit.dist < lightDistance) {
            return true; // In shadow
        }
    }
    
    for (int i = 0; i < NUM_QUADS; i++) {
        Quad quad = scene.quads[i];
        if (length(quad.p0) + length(quad.p1) + length(quad.p2) + length(quad.p3) <= 0.0) continue;
        
        RayHit hit = rayQuadIntersect(shadowRayOrigin, lightDir, quad);
        if (hit.hit && hit.dist > 0 && hit.dist < lightDistance) {
            return true; // In shadow
        }
    }
    
    for (int i = 0; i < NUM_TRIANGLES; i++) {
        Triangle triangle = scene.triangles[i];
        if (length(triangle.p1) + length(triangle.p2) + length(triangle.p3) <= 0.0) continue;
        
        RayHit hit = rayTriangleIntersect(shadowRayOrigin, lightDir, triangle.p1, triangle.p2, triangle.p3);
        if (hit.hit && hit.dist > 0 && hit.dist < lightDistance) {
            return true; // In shadow
        }
    }
    
    return false; // Not in shadow
}

// Get a random position on the light source
float3 sampleLightSource(Light light, thread uint& rng) 
{
    float u = RandomFloat01(rng);
    float v = RandomFloat01(rng);
    
    // WLOG
    if (u + v > 1.0f) {
        u = 1.0f - u;
        v = 1.0f - v;
    }
    
    // Barycentric coordinates to sample point on triangle
    float w = 1.0f - u - v;
    return light.p1 * u + light.p2 * v + light.p3 * w;
}

// Calculate direct lighting contribution
float3 calculateDirectLighting(float3 hitPoint, float3 normal, float3 albedo, Scene scene, thread uint& rng) 
{
    float3 directLight = float3(0.0);
    for (int i = 0; i < NUM_LIGHTS; i++) {
        Light light = scene.lights[i];
        // Sample a random point on the light
        float3 lightPoint = sampleLightSource(light, rng);
        float3 lightDir = normalize(lightPoint - hitPoint);
        float lightDistance = length(lightPoint - hitPoint);
        
        // Skip if light is behind the surface
        float NdotL = dot(normal, lightDir);
        if (NdotL <= 0.0) continue;
        
        // Shadow test
        if (!isInShadow(hitPoint, lightDir, lightDistance, scene)) {
            // Light is visible, calculate contribution
            // Calculate approximate area of light triangle
            float3 e1 = light.p2 - light.p1;
            float3 e2 = light.p3 - light.p1;
            float lightArea = length(cross(e1, e2)) * 0.5;
            
            float3 lightEmission = float3(light.color) * light.intensity;
            float attenuation = 1.0 / (lightDistance * lightDistance); // Inverse square falloff
            directLight += lightEmission * albedo * NdotL * attenuation * lightArea;
        }
    }
    
    return directLight;
}

float3 pathTrace(float3 rayOrigin, float3 rayDirection, Scene scene, thread uint& rng)
{
    float3 ret = float3(0);
    float3 irradiance = float3(1);
    float3 rayPos = rayOrigin;
    float3 rayDir = rayDirection;
    
    int c_numBounces = 3;
    
    for (int bounce = 0; bounce <= c_numBounces; ++bounce)
    {
        // Use the current ray position and direction
        RayHit hit = rayTraceHit(rayPos, rayDir, scene);
        
        if (!hit.hit || hit.dist >= SUPER_FAR) {
            // Add background contribution and break
            float3 backgroundColor = float3(0.5 + 0.5 * rayDir.y, 0.7, 0.9 + 0.1 * rayDir.y);
            ret += backgroundColor * irradiance * 0.3; // Reduced brightness for better contrast
            break;
        }
        
        // Compute the intersection point
        float3 hitPoint = rayPos + rayDir * hit.dist;
        
        // If we hit a light source directly, add emission and break
        if (length(hit.emission) > 0) {
            ret += hit.emission * irradiance;
            break;
        }
        
        // Add direct lighting contribution (explicit light sampling)
        float3 directLight = calculateDirectLighting(hitPoint, hit.normal, hit.albedo, scene, rng);
        ret += directLight * irradiance;
        
        // Update for next bounce - random hemisphere sampling for indirect lighting
        rayPos = hitPoint + hit.normal * SHADOW_BIAS; // Nudge to avoid self-intersection
        rayDir = normalize(RandomInHemisphere(hit.normal, rng));
        irradiance *= hit.albedo;
        // Russian roulette
        if (bounce > 1) {
            float p = max(max(irradiance.x, irradiance.y), irradiance.z);
            if (RandomFloat01(rng) > p) {
                break; // Terminate path with some probability
            }
            // Scale by 1/p to keep result unbiased
            irradiance /= p;
        }
    }
    
    return ret;
}

fragment float4 fragmentShader(ColorInOut in [[stage_in]],
                               texture2d<float> computeTexture [[ texture(TextureIndexCompute) ]],
                               texture2d<half> colorMap     [[ texture(TextureIndexColor) ]])
{
    // simple cornell box with separated lights
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
            // No regular triangles, only lights
        },
        .lights = {
            { float3(0, 1.9, -5), float3(-1, 1.9, -6.5), float3(1, 1.9, -6.5), half3(1, 1, 1), 5.0 }  // Light source with intensity
        }
    };
    
    // Initialize RNG with position and some temporal jitter
    uint rngState = uint(in.position.x * 1973 + in.position.y * 9277 + in.position.x * in.position.y * 73) | 1;
    float2 uv = in.texCoord;
    
    float theta = (uv.x) * 2.0 * M_PI_F; // longitude: 0 to 2π
    float phi   = (1.0 - uv.y) * M_PI_F; // latitude: 0 to π (flip y to match screen coords)
    float3 rayPosition = float3(0);
    float3 rayDirection;
    rayDirection.x = sin(phi) * cos(theta);
    rayDirection.y = -cos(phi);
    rayDirection.z = sin(phi) * sin(theta);
    
    // Apply tiny random jitter to ray direction for anti-aliasing
    rayDirection = normalize(rayDirection + RandomUnitVector(rngState) * 0.001);
    
    // Trace multiple samples per pixel
    float3 color = float3(0);
    for (int i = 0; i < NUM_MONTE_CARLO_SAMPLES; ++i) {
        color += pathTrace(rayPosition, rayDirection, scene, rngState);
    }
    color /= NUM_MONTE_CARLO_SAMPLES;
    
    color = pow(color, float3(1.0/2.2)); // Gamma correction
    return float4(color, 1.0);
}
