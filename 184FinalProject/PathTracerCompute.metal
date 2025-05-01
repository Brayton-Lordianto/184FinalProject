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
#define NUM_MONTE_CARLO_SAMPLES 1
#define MAX_BOUNCES 3
#define SHADOW_BIAS 0.001f
#define SUPER_FAR 1000000.0

// Scene constants
#define NUM_SPHERES 1
#define NUM_QUADS 15
#define NUM_TRIANGLES 1

// Halton sequence primes for better sampling
constant unsigned int primes[] = {2, 3, 5, 7, 11, 13, 17, 19, 23, 29, 31, 37};

// Material properties
enum MaterialType {
    DIFFUSE = 0,
    METAL = 1,
    DIELECTRIC = 2
};

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
    Triangle triangles[NUM_TRIANGLES];
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

// Halton sequence for better-distributed random numbers
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

// Generate a random direction in the hemisphere around the normal
float3 RandomInHemisphere(float3 normal, thread uint& state) {
    float3 inUnitSphere = RandomUnitVector(state);
    if (dot(inUnitSphere, normal) > 0.0) // In the same hemisphere as the normal
        return inUnitSphere;
    else
        return -inUnitSphere;
}

// Generate a random direction weighted by cosine (better for diffuse materials)
float3 RandomCosineDirection(thread uint& state, float3 normal) {
    // Create a local coordinate system aligned with the normal
    float3 up = abs(normal.y) > 0.999 ? float3(1, 0, 0) : float3(0, 1, 0);
    float3 tangent = normalize(cross(up, normal));
    float3 bitangent = cross(normal, tangent);
    
    // Generate a random point on the unit hemisphere (cosine weighted)
    float r1 = RandomFloat01(state);
    float r2 = RandomFloat01(state);
    float phi = 2.0 * M_PI_F * r1;
    float cosTheta = sqrt(r2); // Cosine weighted
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

// Find the closest hit in the scene
RayHit rayTraceHit(float3 rayPosition, float3 rayDirection, Scene scene) {
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
    
    // Check intersections with all triangles (some may be light sources)
    for (int i = 0; i < NUM_TRIANGLES; i++) {
        Triangle triangle = scene.triangles[i];
        // Skip invalid triangles
        if (length(triangle.p1) + length(triangle.p2) + length(triangle.p3) <= 0.0) continue;
        
        RayHit hit = rayTriangleIntersect(rayPosition, rayDirection, triangle);
        if (hit.hit && hit.dist < closestHit.dist && hit.dist > 0) {
            closestHit = hit;
        }
    }
    
    return closestHit;
}

// Shadow test - returns true if point is in shadow
bool isInShadow(float3 point, float3 lightDir, float lightDistance, Scene scene) {
    // Add bias to avoid self-intersection
    float3 shadowRayOrigin = point + lightDir * SHADOW_BIAS;
    
    // Simple shadow check against all objects
    RayHit hit = rayTraceHit(shadowRayOrigin, lightDir, scene);
    return hit.hit && hit.dist < lightDistance;
}

// Sample a point on a triangle light source
float3 sampleLightSource(Triangle light, thread uint& rng) {
    float u = RandomFloat01(rng);
    float v = RandomFloat01(rng);
    
    // Ensure valid barycentric coordinates
    if (u + v > 1.0f) {
        u = 1.0f - u;
        v = 1.0f - v;
    }
    
    // Barycentric coordinates
    float w = 1.0f - u - v;
    return light.p1 * u + light.p2 * v + light.p3 * w;
}

// Material BRDF evaluation
float3 evaluateBRDF(float3 inDir, float3 outDir, float3 normal, float3 albedo, 
                    MaterialType materialType, float roughness) {
    if (materialType == DIFFUSE) {
        // Lambertian diffuse
        return albedo / M_PI_F;
    } 
    else if (materialType == METAL) {
        // Simple specular reflection with roughness
        float3 reflected = reflect(inDir, normal);
        float alignment = max(0.0, dot(normalize(reflected), normalize(outDir)));
        float specular = pow(alignment, (1.0/max(roughness, 0.01)) * 20.0);
        return albedo * (0.2 + 0.8 * specular);
    }
    else if (materialType == DIELECTRIC) {
        // Simple glass-like material (not physically accurate)
        float fresnel = 0.2 + 0.8 * pow(1.0 - abs(dot(normal, outDir)), 5.0);
        return albedo * fresnel;
    }
    
    return albedo; // Fallback
}

// Sample a direction based on material type
float3 sampleDirection(float3 inDir, float3 normal, MaterialType materialType, 
                       float roughness, thread uint& rng) {
    if (materialType == DIFFUSE) {
        // Cosine-weighted sampling for diffuse materials
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
            // Reflect
            return reflect(inDir, normal);
        } else {
            // Simple approximation of refraction
            return RandomInHemisphere(-normal, rng);
        }
    }
    
    // Default fallback
    return RandomInHemisphere(normal, rng);
}

// The main path tracing function
float3 pathTrace(float3 rayOrigin, float3 rayDirection, Scene scene, thread uint& rng, uint frameIndex) {
    float3 finalColor = float3(0.0);
    float3 throughput = float3(1.0);
    float3 rayPos = rayOrigin;
    float3 rayDir = rayDirection;
    
    // Loop for multiple bounces
    for (int bounce = 0; bounce <= MAX_BOUNCES; ++bounce) {
        // Trace ray and get intersection
        RayHit hit = rayTraceHit(rayPos, rayDir, scene);
        
        // If no hit, add background contribution and break
        if (!hit.hit || hit.dist >= SUPER_FAR) {
            float3 backgroundColor = float3(0.5 + 0.5 * rayDir.y, 0.7, 0.9 + 0.1 * rayDir.y);
            finalColor += backgroundColor * throughput * 0.3; // Reduced brightness for better contrast
            break;
        }
        
        // Compute intersection point
        float3 hitPoint = rayPos + rayDir * hit.dist;
        
        // If we hit a light directly, add emission and break
        if (length(hit.emission) > 0) {
            finalColor += hit.emission * throughput;
            break;
        }
        
        // Add direct lighting contribution via explicit light sampling
        // For each light source (currently just one triangle)
        for (int i = 0; i < NUM_TRIANGLES; i++) {
            Triangle light = scene.triangles[i];
            if (!light.isLightSource) continue;
            
            // Use a Halton sequence for light sampling (better distribution)
            float2 lightSample = float2(
                halton(frameIndex + i * 16 + bounce * 4, 2),
                halton(frameIndex + i * 16 + bounce * 4, 3)
            );
            
            // Map to barycentric coordinates
            if (lightSample.x + lightSample.y > 1.0) {
                lightSample.x = 1.0 - lightSample.x;
                lightSample.y = 1.0 - lightSample.y;
            }
            
            // Get point on light
            float3 lightPoint = light.p1 * (1.0 - lightSample.x - lightSample.y) +
                               light.p2 * lightSample.x +
                               light.p3 * lightSample.y;
            
            float3 lightDir = normalize(lightPoint - hitPoint);
            float lightDistance = length(lightPoint - hitPoint);
            
            // Skip if light is behind the surface
            float NdotL = dot(hit.normal, lightDir);
            if (NdotL > 0.0 && !isInShadow(hitPoint, lightDir, lightDistance, scene)) {
                // Calculate approximate area of light triangle
                float3 e1 = light.p2 - light.p1;
                float3 e2 = light.p3 - light.p1;
                float lightArea = length(cross(e1, e2)) * 0.5;
                
                // Evaluate material BRDF
                float3 brdf = evaluateBRDF(-rayDir, lightDir, hit.normal, hit.albedo, 
                                         hit.material, hit.roughness);
                
                float3 lightEmission = float3(light.color) * light.intensity;
                float attenuation = 1.0 / (lightDistance * lightDistance); // Inverse square falloff
                
                // Add direct lighting contribution
                float3 directLight = lightEmission * brdf * NdotL * attenuation * lightArea;
                finalColor += directLight * throughput;
            }
        }
        
        // Update for next bounce based on material properties
        float3 newRayDir = sampleDirection(rayDir, hit.normal, hit.material, hit.roughness, rng);
        rayPos = hitPoint + hit.normal * SHADOW_BIAS; // Nudge to avoid self-intersection
        rayDir = newRayDir;
        
        // Update throughput based on BRDF and probability
        float3 brdf = evaluateBRDF(-rayDir, newRayDir, hit.normal, hit.albedo, 
                                 hit.material, hit.roughness);
        throughput *= brdf * 2.0; // Simple scaling factor
        
        // Russian roulette for path termination (prevents excessive computation)
        if (bounce > 1) {
            float p = max(max(throughput.x, throughput.y), throughput.z);
            if (RandomFloat01(rng) > p) {
                break; // Terminate path with probability 1-p
            }
            throughput /= p; // Unbiased estimator correction
        }
    }
    
    return finalColor;
}

// Compute shader to perform path tracing
kernel void pathTracerCompute(texture2d<float, access::write> output [[texture(0)]],
                             constant ComputeParams &params [[buffer(0)]],
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
    uint sampleCount = params.sampleCount;

    // Initialize Cornell box scene
    Scene scene = {
//        .spheres = {
//            { float3(0, 0, -5), 1.0, half3(0.7, 0.7, 0.7), METAL, 0.1 } // Metallic sphere
//        },
        .quads = {
            // Room walls, floor, ceiling
            { float3(-2, -2, -8), float3(2, -2, -8), float3(2, 2, -8), float3(-2, 2, -8), half3(0.5, 0.5, 0.8), DIFFUSE, 0.0 },  // Back wall (blue)
            { float3(-2, -2, -8), float3(-2, 2, -8), float3(-2, 2, -3), float3(-2, -2, -3), half3(0.8, 0.2, 0.2), DIFFUSE, 0.0 },  // Left wall (red)
            { float3(2, -2, -8), float3(2, -2, -3), float3(2, 2, -3), float3(2, 2, -8), half3(0.2, 0.8, 0.2), DIFFUSE, 0.0 },  // Right wall (green)
            { float3(-2, -2, -8), float3(2, -2, -8), float3(2, -2, -3), float3(-2, -2, -3), half3(0.7, 0.7, 0.7), DIFFUSE, 0.0 },  // Floor (light gray)
            { float3(-2, 2, -8), float3(-2, 2, -3), float3(2, 2, -3), float3(2, 2, -8), half3(0.7, 0.7, 0.7), DIFFUSE, 0.0 },  // Ceiling (light gray)
            
            // Tall box (metallic)
            { float3(-1.0, -2.0, -6.5), float3(-0.2, -2.0, -6.5), float3(-0.2, 0.3, -6.5), float3(-1.0, 0.3, -6.5), half3(0.9, 0.7, 0.3), METAL, 0.1 },  // Front face
            { float3(-1.0, -2.0, -7.5), float3(-1.0, -2.0, -6.5), float3(-1.0, 0.3, -6.5), float3(-1.0, 0.3, -7.5), half3(0.9, 0.7, 0.3), METAL, 0.1 },  // Left face
            { float3(-0.2, -2.0, -7.5), float3(-0.2, -2.0, -6.5), float3(-0.2, 0.3, -6.5), float3(-0.2, 0.3, -7.5), half3(0.9, 0.7, 0.3), METAL, 0.1 },  // Right face
            { float3(-1.0, -2.0, -7.5), float3(-0.2, -2.0, -7.5), float3(-0.2, 0.3, -7.5), float3(-1.0, 0.3, -7.5), half3(0.9, 0.7, 0.3), METAL, 0.1 },  // Back face
            { float3(-1.0, 0.3, -7.5), float3(-0.2, 0.3, -7.5), float3(-0.2, 0.3, -6.5), float3(-1.0, 0.3, -6.5), half3(0.9, 0.7, 0.3), METAL, 0.1 },  // Top face
            
            // Short box (glass-like)
            { float3(0.2, -2.0, -5.5), float3(1.0, -2.0, -5.5), float3(1.0, -1.0, -5.5), float3(0.2, -1.0, -5.5), half3(0.9, 0.9, 0.9), DIELECTRIC, 0.0 },  // Front face
            { float3(0.2, -2.0, -6.5), float3(0.2, -2.0, -5.5), float3(0.2, -1.0, -5.5), float3(0.2, -1.0, -6.5), half3(0.9, 0.9, 0.9), DIELECTRIC, 0.0 },  // Left face
            { float3(1.0, -2.0, -6.5), float3(1.0, -2.0, -5.5), float3(1.0, -1.0, -5.5), float3(1.0, -1.0, -6.5), half3(0.9, 0.9, 0.9), DIELECTRIC, 0.0 },  // Right face
            { float3(0.2, -2.0, -6.5), float3(1.0, -2.0, -6.5), float3(1.0, -1.0, -6.5), float3(0.2, -1.0, -6.5), half3(0.9, 0.9, 0.9), DIELECTRIC, 0.0 },  // Back face
            { float3(0.2, -1.0, -6.5), float3(1.0, -1.0, -6.5), float3(1.0, -1.0, -5.5), float3(0.2, -1.0, -5.5), half3(0.9, 0.9, 0.9), DIELECTRIC, 0.0 },  // Top face
        },
        .triangles = {
            { float3(0, 1.9, -5), float3(-1, 1.9, -6.5), float3(1, 1.9, -6.5), half3(1, 1, 1), true, 5.0 }  // Light source with intensity
        }
    };

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
    
    // Use the camera position from params
    float3 rayPosition = params.cameraPosition;
    
    // Calculate screen position in normalized device coordinates [-1,1]
    float2 ndc = float2(uv.x * 2.0 - 1.0, uv.y * 2.0 - 1.0);
    
    // Use the field of view passed from Swift
    float fov = params.fovY;
    float aspectRatio = params.resolution.x / params.resolution.y;
    
    // Create ray direction in camera space
    float3 cameraSpaceDir;
    cameraSpaceDir.x = ndc.x * tan(fov/2.0) * aspectRatio;
    cameraSpaceDir.y = ndc.y * tan(fov/2.0);
    cameraSpaceDir.z = -1.0; // Looking down the negative Z axis
    
    // Transform camera-space direction to world-space using the view matrix
    // Extract the rotation part of the view matrix (upper 3x3)
    float3x3 viewRotation = float3x3(
        params.viewMatrix.columns[0].xyz,
        params.viewMatrix.columns[1].xyz,
        params.viewMatrix.columns[2].xy
    );
    
    // Apply the rotation to the camera-space direction
    float theta = (uv.x) * 2.0 * M_PI_F; // longitude: 0 to 2π
    float phi = (uv.y) * M_PI_F;   // latitude: 0 to π 540

    float3 rayDirection = normalize(cameraSpaceDir);
    rayDirection.x = sin(phi) * cos(theta);
    rayDirection.y = cos(phi);
    rayDirection.z = sin(phi) * sin(theta);
    rayDirection = viewRotation *rayDirection;

    
    // Trace path
    float3 color = pathTrace(rayPosition, rayDirection, scene, rngState, frameIndex);
    
    // Apply gamma correction for display
    color = pow(color, float3(1.0/2.2));
    
    // Write to output texture
    output.write(float4(color, 1.0), gid);
}
