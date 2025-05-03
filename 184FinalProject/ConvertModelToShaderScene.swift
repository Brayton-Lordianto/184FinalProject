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
        
        print("created triangle with parameters \(triangle.p1), \(triangle.p2), \(triangle.p3), \(triangle.color), \(triangle.isLightSource), \(triangle.intensity), \(triangle.material.rawValue), \(triangle.roughness)")
    }
}

func additionalVertexPositionProcessing(_ position: SIMD3<Float>) -> SIMD3<Float> {
    // Apply additional processing to the vertex position if needed
    // Add z offset so it fits in front of the camera
    var p = position + SIMD3<Float>(0, 0, -5)
    return p
}

func convertModelToShaderScene(model: Model) -> [Triangle] {
    // MARK: CORRECTION FROM PARSING ISSUE
    if Globals.shared.name == AppModel.ModelType.originalCornellBox.filename {
        model.rotation = SIMD3<Float>(-90, 0, 0)
    }
//     later make the custom cornell box really big and enclosing you.
    if Globals.shared.name != AppModel.ModelType.customCornellBox.filename {
        model.position += Globals.shared.modelCenter
    }
    let rotationFromUser = -1 * SIMD3<Float>(Globals.shared.rotationX, Globals.shared.rotationY, Globals.shared.rotationZ)
    
    var triangles = [Triangle]()
    var modelMatrix = matrix_identity_float4x4
    rotateMatrix(matrix: &modelMatrix, rotation: toRadians(from: rotationFromUser))
    rotateMatrix(matrix: &modelMatrix, rotation: toRadians(from: model.rotation))
    scaleMatrix(matrix: &modelMatrix, scale: model.scale)
    translateMatrix(matrix: &modelMatrix, position: model.position)
    
    
    for (meshIndex, mesh) in model.meshes.enumerated() {
        // Note: Using buffer index 30 as specified in vertex descriptor
        if mesh.mesh.vertexBuffers.count <= 0 {
            print("⚠️ No vertex buffers found for mesh #\(meshIndex)")
            continue
        }
        let vertexBuffer = mesh.mesh.vertexBuffers[0]
        // This is critical - the stride is the size of your Vertex struct
        let vertexStride = MemoryLayout<Vertex>.stride
        // Get raw vertex data
        let vertexData = vertexBuffer.buffer.contents()
        
        for (submeshIndex, submesh) in mesh.mesh.submeshes.enumerated() {
            let material = mesh.materials[submeshIndex]
            let indexData = submesh.indexBuffer.buffer.contents()
            
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
                    vertices[j] = additionalVertexPositionProcessing(transformedPosition)
                }
                
                let triangle = Triangle(
                    p1: vertices[0],
                    p2: vertices[1],
                    p3: vertices[2],
                    color: material.color,
                    isLightSource: material.isLightSource,
                    intensity: material.intensity,
                    material: MaterialType(rawValue: material.materialType) ?? .dielectric,
                    roughness: material.roughness
                )
                
                triangles.append(triangle)
            }
        }
    }
    
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
