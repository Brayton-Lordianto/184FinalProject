//
//  PathTracerCompute.metal
//  184FinalProject
//
//  Created by Brayton Lordianto on 4/25/25.
//

#include <metal_stdlib>
using namespace metal;

#include "ShaderTypes.h"

// Ray Tracing constants
#define NUM_MONTE_CARLO_SAMPLES 4
#define MAX_BOUNCES 3
#define SHADOW_BIAS 0.001f
#define SUPER_FAR 1000000.0

// Scene constants - still needed for hardcoded elements
#define NUM_SPHERES 1
#define NUM_QUADS 15
#define NUM_LIGHTS 3

// Maximum model triangles - upper limit we'll support
#define MAX_MODEL_TRIANGLES 1

// Halton sequence primes for better sampling
constant unsigned int primes[] = {2, 3, 5, 7, 11, 13, 17, 19, 23, 29, 31, 37};

typedef struct RayHit {
    bool hit = false;
    float dist;
    float3 normal;
    float3 albedo = 0; // for diffuse surfaces
    float3 emission = 0; // for light sources
    MaterialType material = DIFFUSE;
    float roughness = 0.0;
} RayHit;

// Scene structs
typedef struct {
    float3 c;
    float r;
    half3 color;
    MaterialType material;
    float roughness;
} Sphere;

typedef struct {
    float3 p0, p1, p2, p3;
    half3 color;
    MaterialType material;
    float roughness;
} Quad;

typedef struct {
    float3 p1, p2, p3;
    half3 color;
    bool isLightSource;
    float intensity;
} Triangle;

typedef struct {
    Sphere spheres[NUM_SPHERES];
    Quad quads[NUM_QUADS];
    Triangle lights[NUM_LIGHTS];
    // The model triangles will be passed separately via a buffer
} Scene;

// RNG functions
uint wang_hash(uint seed) {
    seed = uint(seed ^ uint(61)) ^ uint(seed >> uint(16));
    seed *= uint(9);
    seed = seed ^ (seed >> 4);
    seed *= uint(0x27d4eb2d);
    seed = seed ^ (seed >> 15);
    return seed;
}

float RandomFloat01(thread uint& state) {
    state = wang_hash(state);
    return float(state) / 4294967296.0;
}

// this is a generator of random numbers on halton sequence. This was used also in a wwdc example of compute shader ray tracing in apple.
float halton(unsigned int i, unsigned int d) {
    unsigned int b = primes[d % 12];
    float f = 1.0f;
    float invB = 1.0f / b;
    float r = 0;
    
    while (i > 0) {
        f = f * invB;
        r = r + f * (i % b);
        i = i / b;
    }
    
    return r;
}

float3 RandomUnitVector(thread uint& state) {
    float z = RandomFloat01(state) * 2.0f - 1.0f;
    float a = RandomFloat01(state) * 2.0f * M_PI_F;
    float r = sqrt(1.0f - z * z);
    float x = r * cos(a);
    float y = r * sin(a);
    return float3(x, y, z);
}

float3 RandomInHemisphere(float3 normal, thread uint& state) {
    float3 inUnitSphere = RandomUnitVector(state);
    if (dot(inUnitSphere, normal) > 0.0) // In the same hemisphere as the normal
        return inUnitSphere;
    else
        return -inUnitSphere;
}

float3 RandomCosineDirection(thread uint& state, float3 normal) {
    float3 up = abs(normal.y) > 0.999 ? float3(1, 0, 0) : float3(0, 1, 0);
    float3 tangent = normalize(cross(up, normal));
    float3 bitangent = cross(normal, tangent);
    float r1 = RandomFloat01(state);
    float r2 = RandomFloat01(state);
    float phi = 2.0 * M_PI_F * r1;
    float cosTheta = sqrt(r2);
    float sinTheta = sqrt(1.0 - r2);
    float3 randomLocal = float3(cos(phi) * sinTheta, sin(phi) * sinTheta, cosTheta);
    
    // Transform to world space
    return tangent * randomLocal.x + bitangent * randomLocal.y + normal * randomLocal.z;
}

// Ray intersection functions
RayHit raySphereIntersect(float3 rayOrigin, float3 rayDirection, Sphere sphere) {
    RayHit hit;
    hit.hit = false;

    // sphere equations
    float3 oc = rayOrigin - sphere.c;
    float a = dot(rayDirection, rayDirection);
    float b = 2.0 * dot(oc, rayDirection);
    float c = dot(oc, oc) - sphere.r * sphere.r;
    float discriminant = b * b - 4 * a * c;

    if (discriminant > 0) {
        hit.hit = true;
        hit.dist = (-b - sqrt(discriminant)) / (2.0 * a);
        if (hit.dist <= 0) { // Check for valid distance
            hit.dist = (-b + sqrt(discriminant)) / (2.0 * a);
            if (hit.dist <= 0) {
                hit.hit = false;
                return hit;
            }
        }
        hit.normal = normalize(rayOrigin + hit.dist * rayDirection - sphere.c);
        hit.albedo = float3(sphere.color);
        hit.material = sphere.material;
        hit.roughness = sphere.roughness;
    }

    return hit;
}

RayHit rayTriangleIntersect(float3 rayOrigin, float3 rayDirection, Triangle triangle) {
    // Use Muller-Trumbore algorithm
    RayHit hit;
    hit.hit = false;
    float3 v0 = triangle.p1;
    float3 v1 = triangle.p2;
    float3 v2 = triangle.p3;
    
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
    hit.albedo = float3(triangle.color);
    hit.material = DIFFUSE; // Triangles are diffuse by default
    hit.roughness = 0.0;
    
    if (triangle.isLightSource) {
        hit.emission = float3(triangle.color) * triangle.intensity;
    } else {
        hit.emission = 0;
    }
    
    return hit;
}

RayHit rayQuadIntersect(float3 rayOrigin, float3 rayDirection, Quad quad) {
    // Split quad into two triangles
    Triangle tri1 = {
        quad.p0, quad.p1, quad.p2,
        quad.color, false, 0.0
    };
    
    Triangle tri2 = {
        quad.p0, quad.p2, quad.p3,
        quad.color, false, 0.0
    };
    
    // Test intersection with both triangles
    RayHit hit1 = rayTriangleIntersect(rayOrigin, rayDirection, tri1);
    RayHit hit2 = rayTriangleIntersect(rayOrigin, rayDirection, tri2);
    
    // Return the closest hit
    if (hit1.hit && hit2.hit) {
        RayHit closest = (hit1.dist < hit2.dist) ? hit1 : hit2;
        closest.material = quad.material;
        closest.roughness = quad.roughness;
        return closest;
    } else if (hit1.hit) {
        hit1.material = quad.material;
        hit1.roughness = quad.roughness;
        return hit1;
    } else if (hit2.hit) {
        hit2.material = quad.material;
        hit2.roughness = quad.roughness;
        return hit2;
    }
    
    // No hit
    RayHit noHit;
    noHit.hit = false;
    return noHit;
}

// Convert GPUTriangle to a Triangle for internal use
Triangle convertGPUTriangle(GPUTriangle gpuTriangle) {
    Triangle tri;
    tri.p1 = gpuTriangle.p1;
    tri.p2 = gpuTriangle.p2;
    tri.p3 = gpuTriangle.p3;
    tri.color = gpuTriangle.color;
    tri.isLightSource = gpuTriangle.isLightSource;
    tri.intensity = gpuTriangle.intensity;
    return tri;
}

// Find the closest hit in the scene
RayHit rayTraceHit(float3 rayPosition, float3 rayDirection, Scene scene, 
                   constant GPUTriangle* modelTriangles, uint modelTriangleCount) {
    RayHit closestHit;
    closestHit.hit = false;
    closestHit.dist = SUPER_FAR;
    
    // Check intersections with all spheres
    for (int i = 0; i < NUM_SPHERES; i++) {
        Sphere sphere = scene.spheres[i];
        // Skip empty spheres (those with radius 0)
        if (sphere.r <= 0.0) continue;
        
        RayHit hit = raySphereIntersect(rayPosition, rayDirection, sphere);
        if (hit.hit && hit.dist < closestHit.dist && hit.dist > 0) {
            closestHit = hit;
        }
    }
    
    // Check intersections with all quads
    for (int i = 0; i < NUM_QUADS; i++) {
        Quad quad = scene.quads[i];
        // Skip invalid quads (simple check - if all points are at origin)
        if (length(quad.p0) + length(quad.p1) + length(quad.p2) + length(quad.p3) <= 0.0) continue;
        
        RayHit hit = rayQuadIntersect(rayPosition, rayDirection, quad);
        if (hit.hit && hit.dist < closestHit.dist && hit.dist > 0) {
            closestHit = hit;
        }
    }
    
    // Check intersections with all lights
    for (int i = 0; i < NUM_LIGHTS; i++) {
        Triangle triangle = scene.lights[i];
        // Skip invalid triangles
        if (length(triangle.p1) + length(triangle.p2) + length(triangle.p3) <= 0.0) continue;
        
        RayHit hit = rayTriangleIntersect(rayPosition, rayDirection, triangle);
        if (hit.hit && hit.dist < closestHit.dist && hit.dist > 0) {
            closestHit = hit;
        }
    }
    
    // Check intersections with model triangles
    for (uint i = 0; i < modelTriangleCount; i++) {
        GPUTriangle gpuTriangle = modelTriangles[i];
        
        // Skip degenerate triangles
        if (length(gpuTriangle.p1) + length(gpuTriangle.p2) + length(gpuTriangle.p3) <= 0.0) continue;
        
        // Convert to internal triangle for intersection
        Triangle triangle;
        triangle.p1 = gpuTriangle.p1;
        triangle.p2 = gpuTriangle.p2;
        triangle.p3 = gpuTriangle.p3;
        triangle.color = gpuTriangle.color;
        triangle.isLightSource = gpuTriangle.isLightSource;
        triangle.intensity = gpuTriangle.intensity;
        
        RayHit hit = rayTriangleIntersect(rayPosition, rayDirection, triangle);
        
        // If we hit, set properties based on GPU triangle
        if (hit.hit && hit.dist < closestHit.dist && hit.dist > 0) {
            // Update material properties based on model data
            hit.material = (MaterialType)gpuTriangle.materialType;
            hit.roughness = gpuTriangle.roughness;
            closestHit = hit;
        }
    }
    
    return closestHit;
}

// Shadow test - returns true if point is in shadow
bool isInShadow(float3 point, float3 lightDir, float lightDistance, Scene scene, 
               constant GPUTriangle* modelTriangles, uint modelTriangleCount) {
    // Add bias to avoid self-intersection
    float3 shadowRayOrigin = point + lightDir * SHADOW_BIAS;
    
    // Simple shadow check against all objects
    RayHit hit = rayTraceHit(shadowRayOrigin, lightDir, scene, modelTriangles, modelTriangleCount);
    // hit.emission trick so if its a light it should output false
    return (length(hit.emission) <= 0) * hit.hit;
}
    
// do it like this so no control flow needed.
float shadowFactor(float3 point, float3 lightDir, float lightDistance, Scene scene, 
                  constant GPUTriangle* modelTriangles, uint modelTriangleCount) {
    float3 shadowRayOrigin = point + lightDir * SHADOW_BIAS;
    RayHit hit = rayTraceHit(shadowRayOrigin, lightDir, scene, modelTriangles, modelTriangleCount);
    // Return 0.0 when in shadow, 1.0 when not in shadow
    return 1.0 - float(hit.hit && length(hit.emission) <= 0);
}


// Sample a point on a triangle light source
float3 sampleLightSource(Triangle light, thread uint& rng) {
    float u = RandomFloat01(rng);
    float v = RandomFloat01(rng);
    if (u + v > 1.0f) {
        u = 1.0f - u;
        v = 1.0f - v;
    }
    float w = 1.0f - u - v;
    return light.p1 * u + light.p2 * v + light.p3 * w;
}

float3 evaluateBRDF(float3 inDir, float3 outDir, float3 normal, float3 albedo,
                    MaterialType materialType, float roughness) {
    float3 diffuseComponent = albedo / M_PI_F;
    float3 reflected = reflect(inDir, normal);
    float alignment = max(0.0, dot(normalize(reflected), normalize(outDir)));
    float specular = pow(alignment, (1.0/max(roughness, 0.01)) * 20.0);
    float3 metalComponent = albedo * (0.2 + 0.8 * specular);
    float fresnel = 0.2 + 0.8 * pow(1.0 - abs(dot(normal, outDir)), 5.0);
    float3 dielectricComponent = albedo * fresnel;
    return diffuseComponent * float(materialType == DIFFUSE) +
           metalComponent * float(materialType == METAL) +
           dielectricComponent * float(materialType == DIELECTRIC);
}
    
float3 sampleDirection(float3 inDir, float3 normal, MaterialType materialType,
                       float roughness, thread uint& rng) {
    if (materialType == DIFFUSE) {
        return RandomCosineDirection(rng, normal);
    }
    else if (materialType == METAL) {
        // Reflection with some roughness-based scattering
        float3 reflected = reflect(inDir, normal);
        float3 randomVec = RandomUnitVector(rng) * roughness;
        return normalize(reflected + randomVec);
    }
    else if (materialType == DIELECTRIC) {
        // Simple refraction/reflection based on fresnel
        float cosTheta = dot(-inDir, normal);
        float fresnel = 0.2 + 0.8 * pow(1.0 - cosTheta, 5.0); // Schlick's approximation
        
        if (RandomFloat01(rng) < fresnel) {
            return reflect(inDir, normal);
        } else {
            return RandomInHemisphere(-normal, rng);
        }
    }
    
    return RandomInHemisphere(normal, rng);
}

// The main path tracing function
float3 pathTrace(float3 rayOrigin, float3 rayDirection, Scene scene, 
                constant GPUTriangle* modelTriangles, uint modelTriangleCount,
                thread uint& rng, uint frameIndex) {
    float3 finalColor = float3(0.0);
    float3 throughput = float3(1.0);
    float3 rayPos = rayOrigin;
    float3 rayDir = rayDirection;
    
    // Loop for multiple bounces
    for (int bounce = 0; bounce <= MAX_BOUNCES; ++bounce) {
        RayHit hit = rayTraceHit(rayPos, rayDir, scene, modelTriangles, modelTriangleCount);
        // If no hit, add background contribution and break
        if (!hit.hit || hit.dist >= SUPER_FAR) {
            break;
        }
        
        float3 hitPoint = rayPos + rayDir * hit.dist;
//        return hit.albedo;
        // If we hit a light directly, add emission and break
        if (length(hit.emission) > 0) {
            finalColor += hit.emission * throughput;
            break;
        }
        
        // DIRECT LIGHTING AT POINT WE HIT
        // IMPORTANCE SAMPLE
        for (int lightI = 0; lightI < NUM_LIGHTS; ++lightI) {
            Triangle light = scene.lights[lightI];
            if (!light.isLightSource) continue;
            
            int num_light_samples = NUM_MONTE_CARLO_SAMPLES;
            for (int i = 0; i < num_light_samples; ++i) {
                float3 lightPos = sampleLightSource(light, rng);
                float3 lightDir = normalize(lightPos - hitPoint);
                float lightDistance = length(lightPos - hitPoint);
                float shadow = shadowFactor(hitPoint, lightDir, lightDistance, scene, modelTriangles, modelTriangleCount);
                float3 brdf = evaluateBRDF(-rayDir, lightDir, hit.normal, hit.albedo,
                                           hit.material, hit.roughness);
                float cos_theta = abs(dot(hit.normal, lightDir));
                float inverseSquareLawFactor = 1 / (lightDistance * lightDistance);
                finalColor += shadow * brdf * throughput * cos_theta * inverseSquareLawFactor;
            }
        }
        
        // UPDATE FOR NEXT BOUNCE
        float3 newRayDir = sampleDirection(rayDir, hit.normal, hit.material, hit.roughness, rng);
        rayPos = hitPoint + hit.normal * SHADOW_BIAS; // Nudge to avoid self-intersection
        rayDir = newRayDir;
        
        // GET NEXT BOUNCE'S CONTRIBUTION
        float3 brdf = evaluateBRDF(-rayDir, newRayDir, hit.normal, hit.albedo,
                                 hit.material, hit.roughness);
        throughput *= brdf * 2.0;
        if (bounce > 1) {
            float p = max(max(throughput.x, throughput.y), throughput.z);
            if (RandomFloat01(rng) > p) {
                break;
            }
            throughput /= p; // basically how much in the next ray shot it will contribute.
        }
    }
     
    return finalColor;
}

// Standard compute shader path tracing implementation (original)
kernel void pathTracerCompute(texture2d<float, access::write> output [[texture(0)]],
                             constant ComputeParams &params [[buffer(0)]],
                             constant GPUTriangle* modelTriangles [[buffer(1)]],
                             uint2 gid [[thread_position_in_grid]]) {    
    
    // Get dimensions
    uint width = output.get_width();
    uint height = output.get_height();

    // Skip if out of bounds
    if (gid.x >= width || gid.y >= height) {
        return;
    }
    
    // Use the frameIndex parameter that's now passed from Swift
    uint frameIndex = params.frameIndex;
    uint modelTriangleCount = params.modelTriangleCount;

    // Initialize Cornell box scene
    // now we'll rely on model triangles passed from Swift
    Scene scene = {
        .lights = {
            { float3(-1, 1.9, -2), float3(-1, 1.9, -4.5), float3(1, 1.9, -4.5), half3(1, 1, 1), true, 100.0 }
        }
    };
    
    // for each triangle, if it is a light, add to scene lights
    uint j = 0;
    for (uint i = 0; i < modelTriangleCount; i++) {
        GPUTriangle gpuTriangle = modelTriangles[i];
        if (gpuTriangle.isLightSource) {
            scene.lights[j++] = convertGPUTriangle(gpuTriangle);
        }
    }

    // Initialize RNG seed - add spatial and temporal variation
    uint rngState = uint(gid.x * 1973 + gid.y * 9277 + params.time * 10000) | 1;
    // Convert pixel coordinates to UV coordinates [0,1]
    float2 uv = float2(gid) / float2(width, height);
    // Add jitter for anti-aliasing - use halton sequence for better distribution
    float2 jitter = float2(
        halton((frameIndex * width * height + gid.y * width + gid.x) % 1000, 0) - 0.5,
        halton((frameIndex * width * height + gid.y * width + gid.x) % 1000, 1) - 0.5
    ) / float2(width, height);
    uv += jitter;
    
    // initialize ray direction
    
//    float3 rayPosition = params.cameraPosition;
    float3 rayPosition = float3(0);
    float theta = (uv.x) * 2.0 * M_PI_F; // longitude: 0 to 2π
    float phi = (uv.y) * M_PI_F;   // latitude: 0 to π 540
    float3 rayDirection;
    rayDirection.x = sin(phi) * cos(theta);
    rayDirection.y = cos(phi);
    rayDirection.z = sin(phi) * sin(theta);
    
    // MARK: SIMULATE ABERRATIONS HERE
    //     Convert to camera space
        float3 camRayOrigin = (float4(rayPosition, 1.0)).xyz;
        float3 camRayDirection = normalize((float4(rayDirection, 0.0)).xyz);
        
        float3 pSensorCam = camRayOrigin + 1 * camRayDirection;
        
        // === Sample lens point
        float rndR = halton(frameIndex, 2);
        float rndTheta = halton(frameIndex, 3) * 2.0f * M_PI_F;
        
        float lensX = params.lensRadius * sqrt(rndR) * cos(rndTheta);
        float lensY = params.lensRadius * sqrt(rndR) * sin(rndTheta);
        float3 lensPosCam = float3(lensX, lensY, 0.0);
        
        // === Astigmatism: modulate focus per meridian
        float axisRad = params.AXIS * M_PI_F / 180.0;
        float t = fmod(rndTheta + axisRad, M_PI_F);
        float phase = (t < M_PI_F / 2.0) ? (t / (M_PI_F / 2.0)) : ((M_PI_F - t) / (M_PI_F / 2.0));
        float eyePower = params.SPH + params.CYL * phase;
        // float adjustedFocalDist = params.focalDistance + 1.0 / eyePower;
        float adjustedFocalDist = 1 / (1 / params.focalDistance + eyePower);
        
        // === Compute focal point in camera space and transform
        float3 focusPosCam = pSensorCam * adjustedFocalDist;
        
        // === Convert camera space to world space
        float3 lensPosWorld = (float4(lensPosCam, 1.0)).xyz;
        float3 focusPosWorld = (float4(focusPosCam, 1.0)).xyz;
        
        rayPosition = lensPosWorld;
        rayDirection = normalize(focusPosWorld - lensPosWorld);
    // MARK: END ======
    
    // Use math to conditionally apply view matrix transformation
    // When params.useViewMatrix is true, use transformed direction
    // When params.useViewMatrix is false, use original direction
    float3 transformedDir = (params.viewMatrix * float4(rayDirection, 0)).xyz;
    rayDirection = mix(rayDirection, transformedDir, float(params.useViewMatrix));
    
    // Trace path with model triangles
    float3 color = pathTrace(rayPosition, rayDirection, scene, modelTriangles, modelTriangleCount, rngState, frameIndex);
    // Apply gamma correction for display
    color = pow(color, float3(1.0/2.2));
    if (length(color - float3(0)) > 0.01)
        output.write(float4(color, 1.0), gid);
}

