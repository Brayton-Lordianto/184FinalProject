//
//  ConvertModelToShaderScene.swift
//  184FinalProject
//
//  Created by Brayton Lordianto on 5/1/25.
//

import Foundation
import Metal
import MetalKit

// Material types matching those in the shader
enum MaterialType: Int {
    case diffuse = 0
    case metal = 1
    case dielectric = 2
}

struct Triangle {
    var p1: SIMD3<Float>
    var p2: SIMD3<Float>
    var p3: SIMD3<Float>
    var color: simd_half3
    var isLightSource: Bool
    var intensity: Float
    var material: MaterialType // Match shader's MaterialType enum
    var roughness: Float
}

func convertModelToShaderScene(model: Model) -> [Triangle] {
    var triangles: [Triangle] = []
    
    // Create the model matrix to transform vertices
    var modelMatrix = matrix_identity_float4x4
    translateMatrix(matrix: &modelMatrix, position: model.position)
    rotateMatrix(matrix: &modelMatrix, rotation: toRadians(from: model.rotation))
    scaleMatrix(matrix: &modelMatrix, scale: model.scale)
    
    // Process each mesh in the model
    for mesh in model.meshes {
        let vertexBuffer = mesh.mesh.vertexBuffers[0]
        let vertexData = vertexBuffer.buffer.contents()
        
        // Process each submesh
        for (submeshIndex, submesh) in mesh.mesh.submeshes.enumerated() {
            let material = mesh.materials[min(submeshIndex, mesh.materials.count - 1)]
            
            // Extract material properties
            var color = simd_half3(0.8, 0.8, 0.8) // Default color
            var materialType: MaterialType = .diffuse // Default material
            var roughness: Float = 0.2 // Default roughness
            
            if let texture = material.diffuseTexture {
                // For simplicity, use a representative color from the material
                color = simd_half3(0.9, 0.9, 0.9)
            }
            
            // Determine material type based on simple heuristics
            // In a more advanced implementation, this would be determined by actual material properties
            if let specTexture = material.specularTexture {
                // If it has a specular map, treat as metal
                materialType = .metal
                roughness = 0.1
            } else {
                // Simple heuristic: light colors with high values are more likely dielectric (glass/plastic)
                let brightness = (Float(color.x) + Float(color.y) + Float(color.z)) / 3.0
                if brightness > 0.85 {
                    materialType = .dielectric
                    roughness = 0.05
                } else if brightness > 0.6 {
                    materialType = .metal
                    roughness = 0.2
                } else {
                    materialType = .diffuse
                    roughness = 0.8
                }
            }
            
            // Get the index buffer
            let indexBuffer = submesh.indexBuffer
            let indexData = indexBuffer.buffer.contents()
            
            // Determine index type and create triangles
            if submesh.indexType == .uint16 {
                let indices = indexData.bindMemory(to: UInt16.self, capacity: submesh.indexCount)
                
                // Create triangles for each triplet of indices
                for i in stride(from: 0, to: submesh.indexCount, by: 3) {
                    if i + 2 < submesh.indexCount {
                        let i0 = Int(indices[i])
                        let i1 = Int(indices[i + 1])
                        let i2 = Int(indices[i + 2])
                        
                        // Extract vertex positions - adjust based on actual vertex layout
                        let layoutDescriptor = mesh.mesh.vertexDescriptor.layouts[0] as! MTLVertexBufferLayoutDescriptor
                        let stride = Int(layoutDescriptor.stride)
                        let vertexStride = Int(stride)
                        
                        let v0Ptr = vertexData.advanced(by: i0 * vertexStride)
                        let v1Ptr = vertexData.advanced(by: i1 * vertexStride)
                        let v2Ptr = vertexData.advanced(by: i2 * vertexStride)
                        
                        let v0 = v0Ptr.bindMemory(to: SIMD3<Float>.self, capacity: 1).pointee
                        let v1 = v1Ptr.bindMemory(to: SIMD3<Float>.self, capacity: 1).pointee
                        let v2 = v2Ptr.bindMemory(to: SIMD3<Float>.self, capacity: 1).pointee
                        
                        // Transform vertices by model matrix
                        let p1 = transformPoint(v0, modelMatrix)
                        let p2 = transformPoint(v1, modelMatrix)
                        let p3 = transformPoint(v2, modelMatrix)
                        
                        // Create and add the triangle
                        let triangle = Triangle(
                            p1: p1,
                            p2: p2,
                            p3: p3,
                            color: color,
                            isLightSource: false, // Assuming model doesn't contain light sources
                            intensity: 0.0,
                            material: materialType,
                            roughness: roughness
                        )
                        
                        triangles.append(triangle)
                    }
                }
            } else if submesh.indexType == .uint32 {
                let indices = indexData.bindMemory(to: UInt32.self, capacity: submesh.indexCount)
                
                // Create triangles for each triplet of indices
                for i in stride(from: 0, to: submesh.indexCount, by: 3) {
                    if i + 2 < submesh.indexCount {
                        let i0 = Int(indices[i])
                        let i1 = Int(indices[i + 1])
                        let i2 = Int(indices[i + 2])
                        
                        // Extract vertex positions - adjust based on actual vertex layout
                        let layoutDescriptor = mesh.mesh.vertexDescriptor.layouts[0] as! MTLVertexBufferLayoutDescriptor
                        let stride = Int(layoutDescriptor.stride)
                        let vertexStride = Int(stride)
                        
                        let v0Ptr = vertexData.advanced(by: i0 * vertexStride)
                        let v1Ptr = vertexData.advanced(by: i1 * vertexStride)
                        let v2Ptr = vertexData.advanced(by: i2 * vertexStride)
                        
                        let v0 = v0Ptr.bindMemory(to: SIMD3<Float>.self, capacity: 1).pointee
                        let v1 = v1Ptr.bindMemory(to: SIMD3<Float>.self, capacity: 1).pointee
                        let v2 = v2Ptr.bindMemory(to: SIMD3<Float>.self, capacity: 1).pointee
                        
                        // Transform vertices by model matrix
                        let p1 = transformPoint(v0, modelMatrix)
                        let p2 = transformPoint(v1, modelMatrix)
                        let p3 = transformPoint(v2, modelMatrix)
                        
                        // Create and add the triangle
                        let triangle = Triangle(
                            p1: p1,
                            p2: p2,
                            p3: p3,
                            color: color,
                            isLightSource: false, // Assuming model doesn't contain light sources
                            intensity: 0.0,
                            material: materialType,
                            roughness: roughness
                        )
                        
                        triangles.append(triangle)
                    }
                }
            }
        }
    }
    
    return triangles
}

private func transformPoint(_ point: SIMD3<Float>, _ matrix: matrix_float4x4) -> SIMD3<Float> {
    let homogeneousPoint = SIMD4<Float>(point.x, point.y, point.z, 1.0)
    let transformedPoint = matrix * homogeneousPoint
    return SIMD3<Float>(
        transformedPoint.x / transformedPoint.w,
        transformedPoint.y / transformedPoint.w,
        transformedPoint.z / transformedPoint.w
    )
}

// Function to update the shader scene with model triangles
func updateShaderSceneWithModelTriangles(scene: inout Scene, modelTriangles: [Triangle], maxTriangles: Int) {
    // Copy triangles up to the maximum allowed
    for i in 0..<min(modelTriangles.count, maxTriangles) {
        scene.triangles[i] = modelTriangles[i]
    }
    
    // Fill remaining triangles with empty placeholders if needed
    for i in modelTriangles.count..<maxTriangles {
        scene.triangles[i] = Triangle(
            p1: SIMD3<Float>(0, 0, 0),
            p2: SIMD3<Float>(0, 0, 0),
            p3: SIMD3<Float>(0, 0, 0),
            color: simd_half3(0, 0, 0),
            isLightSource: false,
            intensity: 0.0,
            material: .diffuse,
            roughness: 0.0
        )
    }
}

// Scene struct to match Metal shader
struct Scene {
    var spheres: [Sphere]
    var quads: [Quad]
    var triangles: [Triangle]
    var lights: [Triangle]
    
    init(spheres: [Sphere] = [], quads: [Quad] = [], triangles: [Triangle] = [], lights: [Triangle] = []) {
        self.spheres = spheres
        self.quads = quads
        self.triangles = triangles
        self.lights = lights
    }
}

// Matching shader structs
struct Sphere {
    var center: SIMD3<Float>
    var radius: Float
    var color: simd_half3
    var material: MaterialType
    var roughness: Float
}

struct Quad {
    var p0: SIMD3<Float>
    var p1: SIMD3<Float>
    var p2: SIMD3<Float>
    var p3: SIMD3<Float>
    var color: simd_half3
    var material: MaterialType
    var roughness: Float
}