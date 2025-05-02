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

struct GPUTriangleAligned {
    var p1: SIMD3<Float>
    var _padding: SIMD3<Float>
    var p2: SIMD3<Float>
    var _padding2: SIMD2<Float>
    var p3: SIMD3<Float>
    var _padding3: Float
    var color: simd_half3
    var _padding4: Float
    var isLightSource: Bool
    var intensity: Float
    var materialType: Int32
    var roughness: Float
}

struct GPUTriangle {
    var p1: SIMD3<Float>
    var p2: SIMD3<Float>
    var p3: SIMD3<Float>
    var color: simd_half3
    var isLightSource: Bool
    var intensity: Float
    var materialType: Int32
    var roughness: Float
    
    init(from triangle: Triangle) {
        self.p1 = triangle.p1
        self.p2 = triangle.p2
        self.p3 = triangle.p3
        self.color = triangle.color
        self.isLightSource = triangle.isLightSource
        self.intensity = triangle.intensity
        self.materialType = Int32(triangle.material.rawValue)
        self.roughness = triangle.roughness
    }
}

func convertModelToShaderScene(model: Model) -> [Triangle] {
    var triangles = [Triangle]()
    
    print("🔄 Starting model conversion to shader scene")
    print("📊 Model has \(model.meshes.count) meshes")
    
    // Apply model transformation
    var modelMatrix = matrix_identity_float4x4
    translateMatrix(matrix: &modelMatrix, position: model.position)
    rotateMatrix(matrix: &modelMatrix, rotation: toRadians(from: model.rotation))
    scaleMatrix(matrix: &modelMatrix, scale: model.scale)
    
    for (meshIndex, mesh) in model.meshes.enumerated() {
        print("📐 Processing mesh #\(meshIndex)")
        
        // Note: Using buffer index 30 as specified in your vertex descriptor
        if mesh.mesh.vertexBuffers.count <= 0 {
            print("⚠️ No vertex buffers found for mesh #\(meshIndex)")
            continue
        }
        
        let vertexBuffer = mesh.mesh.vertexBuffers[0]
        print("🔢 Vertex buffer size: \(vertexBuffer.buffer.length), offset: \(vertexBuffer.offset)")
        
        // This is critical - the stride is the size of your Vertex struct
        let vertexStride = MemoryLayout<Vertex>.stride
        print("🔍 Vertex stride: \(vertexStride) bytes")
        
        // Get raw vertex data
        let vertexData = vertexBuffer.buffer.contents()
        
        print("🧩 Mesh has \(mesh.mesh.submeshes.count) submeshes")
        for (submeshIndex, submesh) in mesh.mesh.submeshes.enumerated() {
            print("   ⬢ Processing submesh #\(submeshIndex) with \(submesh.indexCount) indices")
            
            
            // Get material
            let material = mesh.materials[submeshIndex]
            print("   🎨 Material: \(material)")
            
            // Extract color from material - simplistic approach
            let color = simd_half3(0.7, 0.7, 0.7) // Default color
            
            // Get index buffer data
            let indexData = submesh.indexBuffer.buffer.contents()
            
            // Print submesh triangle count
            let triangleCount = submesh.indexCount / 3
            print("   📐 Submesh triangle count: \(triangleCount)")
            
            // Process triangles
            for i in stride(from: 0, to: submesh.indexCount, by: 3) {
                var indices = [UInt32](repeating: 0, count: 3)
                
                if submesh.indexType == .uint16 {
                    let indexPtr = indexData.bindMemory(to: UInt16.self, capacity: submesh.indexCount)
                    indices[0] = UInt32(indexPtr.advanced(by: i).pointee)
                    indices[1] = UInt32(indexPtr.advanced(by: i+1).pointee)
                    indices[2] = UInt32(indexPtr.advanced(by: i+2).pointee)
                } else {
                    let indexPtr = indexData.bindMemory(to: UInt32.self, capacity: submesh.indexCount)
                    indices[0] = indexPtr.advanced(by: i).pointee
                    indices[1] = indexPtr.advanced(by: i+1).pointee
                    indices[2] = indexPtr.advanced(by: i+2).pointee
                }
                
                // Extract vertices using the Vertex struct directly
                var vertices = [SIMD3<Float>](repeating: SIMD3<Float>(0, 0, 0), count: 3)
                for j in 0..<3 {
                    let vertexPtr = vertexData.advanced(by: Int(indices[j]) * vertexStride)
                    let vertex = vertexPtr.bindMemory(to: Vertex.self, capacity: 1).pointee
                    let position = vertex.position
                    let transformedPosition = applyTransform(position, modelMatrix: modelMatrix)
                    // Add z offset so it fits in front of the camera
                    vertices[j] = transformedPosition + SIMD3<Float>(0, 0, -5)
                }
                
                // Create triangle with randomly assigned materials for testing
                let materialType: MaterialType
                let roughness: Float
                
                // Randomly assign different materials for testing
                switch (triangles.count % 3) {
                case 0:
                    materialType = .diffuse
                    roughness = 0.1
                case 1:
                    materialType = .metal
                    roughness = 0.3
                case 2:
                    materialType = .dielectric
                    roughness = 0.0
                default:
                    materialType = .diffuse
                    roughness = 0.5
                }
                
                let triangle = Triangle(
                    p1: vertices[0],
                    p2: vertices[1],
                    p3: vertices[2],
                    color: color,
                    isLightSource: false,
                    intensity: 0.0,
                    material: materialType,
                    roughness: roughness
                )
                
                // Only print first and last triangle of each submesh to avoid log spam
                if i == 0 || i >= submesh.indexCount - 3 {
                    print("   🔺 Triangle \(i/3) - Vertices: \(triangle.p1), \(triangle.p2), \(triangle.p3)")
                    print("      💠 Material: \(materialType), Roughness: \(roughness)")
                }
                
                triangles.append(triangle)
            }
        }
    }
    
    print("✅ Conversion complete. Generated \(triangles.count) triangles for shader")
    return triangles
}

func applyTransform(_ position: SIMD3<Float>, modelMatrix: simd_float4x4) -> SIMD3<Float> {
    let positionVector = simd_float4(position.x, position.y, position.z, 1.0)
    let transformedPosition = modelMatrix * positionVector
    return SIMD3<Float>(transformedPosition.x, transformedPosition.y, transformedPosition.z)
}

func transformPosition(_ position: SIMD3<Float>, modelMatrix: simd_float4x4) -> SIMD3<Float> {
    let positionVector = simd_float4(position.x, position.y, position.z, 1.0)
    let transformedPosition = modelMatrix * positionVector
    return SIMD3<Float>(transformedPosition.x, transformedPosition.y, transformedPosition.z)
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
