// MARK: adapted from and edited https://github.com/SamoZ256/MetalTutorial/blob/main/MetalTutorial7/MetalTutorial/Model.swift
import MetalKit

func getMaterial(_ mdlSubmesh: MDLSubmesh) -> Material {
    _ = mdlSubmesh.material?.name ?? "No Material"
    let baseColor = mdlSubmesh.material?.property(with: .baseColor)?.float3Value ?? SIMD3<Float>(repeating: 1.0)
    let roughness = mdlSubmesh.material?.property(with: .roughness)?.floatValue ?? 1.0
    let indexOfRefraction = mdlSubmesh.material?.property(with: .materialIndexOfRefraction)?.floatValue ?? 1.0
    let emission = mdlSubmesh.material?.property(with: .emission)?.float3Value ?? SIMD3<Float>(repeating: 0.0)
    let metallic = mdlSubmesh.material?.property(with: .metallic)?.floatValue ?? 0.0
    var material = Material()
    
    // determine type of material
    if indexOfRefraction > 1.2 {
        // IOR > 1.0, likely a dielectric (glass, water, etc.)
        material.materialType = MaterialType.dielectric.rawValue
    } else if metallic > 0.5 {
        // If it has high metalness value, classify as metal
        material.materialType = MaterialType.metal.rawValue
    } else {
        // Default to diffuse for all other materials
        material.materialType = MaterialType.diffuse.rawValue
    }
    
    // other properties
    material.color = simd_half3(Float16(baseColor.x), Float16(baseColor.y), Float16(baseColor.z))
    material.isLightSource = emission.x > 0.0 || emission.y > 0.0 || emission.z > 0.0
    material.intensity = max(emission.x, max(emission.y, emission.z))
    material.roughness = roughness
    print("base color is \(baseColor), roughness is \(roughness), metallic is \(metallic), IOR is \(indexOfRefraction)")
    return material
}

struct Material {
    var color: simd_half3 = simd_half3(0.7, 0.7, 0.7)
    var isLightSource: Bool = false
    var intensity: Float = 0.0
    var materialType: Int = 0
    var roughness: Float = 0.5
}

class Mesh {
    var mesh: MTKMesh
    var materials: [Material]
    
    init(mesh: MTKMesh, materials: [Material]) {
        self.mesh = mesh
        self.materials = materials
    }
}

class Model {
    var meshes = [Mesh]()
    
    var position = simd_float3(repeating: 0.0)
    var rotation = simd_float3(repeating: 0.0)
    var scale = simd_float3(repeating: 1.0)
    
    func loadModel(device: MTLDevice, url: URL, vertexDescriptor: MTLVertexDescriptor, textureLoader: MTKTextureLoader) {
        let modelVertexDescriptor = MTKModelIOVertexDescriptorFromMetal(vertexDescriptor)
        
        // Tell the model loader what the attributes represent
        let attrPosition = modelVertexDescriptor.attributes[0] as! MDLVertexAttribute
        attrPosition.name = MDLVertexAttributePosition
        modelVertexDescriptor.attributes[0] = attrPosition
        
        let attrTexCoord = modelVertexDescriptor.attributes[1] as! MDLVertexAttribute
        attrTexCoord.name = MDLVertexAttributeTextureCoordinate
        modelVertexDescriptor.attributes[1] = attrTexCoord
        
        let attrNormal = modelVertexDescriptor.attributes[2] as! MDLVertexAttribute
        attrNormal.name = MDLVertexAttributeNormal
        modelVertexDescriptor.attributes[2] = attrNormal
        
        // load the model
        let bufferAllocator = MTKMeshBufferAllocator(device: device)
        let asset = MDLAsset(url: url, vertexDescriptor: modelVertexDescriptor, bufferAllocator: bufferAllocator)
        
        // Load data for textures - - we won't support textures for now.
        // asset.loadTextures()
        
        // Retrieve the meshes
        guard let (mdlMeshes, mtkMeshes) = try? MTKMesh.newMeshes(asset: asset, device: device) else {
            print("Failed to create meshes")
            return
        }
        
        self.meshes.reserveCapacity(mdlMeshes.count)
        
        // Create our meshes
        for (mdlMesh, mtkMesh) in zip(mdlMeshes, mtkMeshes) {
            var materials = [Material]()
            for mdlSubmesh in mdlMesh.submeshes as! [MDLSubmesh] {
                let material = getMaterial(mdlSubmesh)
                materials.append(material)
            }
            let mesh = Mesh(mesh: mtkMesh, materials: materials)
            self.meshes.append(mesh)
        }
    }
    
    func render(renderEncoder: MTLRenderCommandEncoder) {
        // Create the model matrix
        var modelMatrix = matrix_identity_float4x4
        translateMatrix(matrix: &modelMatrix, position: self.position)
        rotateMatrix(matrix: &modelMatrix, rotation: toRadians(from: self.rotation))
        scaleMatrix(matrix: &modelMatrix, scale: self.scale)
        renderEncoder.setVertexBytes(&modelMatrix, length: MemoryLayout.stride(ofValue: modelMatrix), index: 2)
        
        for mesh in self.meshes {
            // Bind vertex buffer
            let vertexBuffer = mesh.mesh.vertexBuffers[0]
            renderEncoder.setVertexBuffer(vertexBuffer.buffer, offset: vertexBuffer.offset, index: 30)
            for (submesh, material) in zip(mesh.mesh.submeshes, mesh.materials) {
                // Draw
                let indexBuffer = submesh.indexBuffer
                renderEncoder.drawIndexedPrimitives(type: MTLPrimitiveType.triangle, indexCount: submesh.indexCount, indexType: submesh.indexType, indexBuffer: indexBuffer.buffer, indexBufferOffset: 0)
            }
        }
    }
}

import Foundation
import simd

func toRadians(from angle: Float) -> Float {
    return angle * .pi / 180.0;
}

func toRadians(from rotation: simd_float3) -> simd_float3 {
    return simd_float3(toRadians(from: rotation.x), toRadians(from: rotation.y), toRadians(from: rotation.z));
}

func translateMatrix(matrix: inout simd_float4x4, position: simd_float3) {
    matrix[3] = matrix[0] * position.x + matrix[1] * position.y + matrix[2] * position.z + matrix[3];
}

func rotateMatrix(matrix: inout simd_float4x4, rotation: simd_float3) {
    //Create quaternion
    let c = cos(rotation * 0.5);
    let s = sin(rotation * 0.5);

    var quat = simd_float4(repeating: 1.0);

    quat.w = c.x * c.y * c.z + s.x * s.y * s.z;
    quat.x = s.x * c.y * c.z - c.x * s.y * s.z;
    quat.y = c.x * s.y * c.z + s.x * c.y * s.z;
    quat.z = c.x * c.y * s.z - s.x * s.y * c.z;

    //Create matrix
    var rotationMat = matrix_identity_float4x4;
    let qxx = quat.x * quat.x;
    let qyy = quat.y * quat.y;
    let qzz = quat.z * quat.z;
    let qxz = quat.x * quat.z;
    let qxy = quat.x * quat.y;
    let qyz = quat.y * quat.z;
    let qwx = quat.w * quat.x;
    let qwy = quat.w * quat.y;
    let qwz = quat.w * quat.z;

    rotationMat[0][0] = 1.0 - 2.0 * (qyy + qzz);
    rotationMat[0][1] = 2.0 * (qxy + qwz);
    rotationMat[0][2] = 2.0 * (qxz - qwy);

    rotationMat[1][0] = 2.0 * (qxy - qwz);
    rotationMat[1][1] = 1.0 - 2.0 * (qxx + qzz);
    rotationMat[1][2] = 2.0 * (qyz + qwx);

    rotationMat[2][0] = 2.0 * (qxz + qwy);
    rotationMat[2][1] = 2.0 * (qyz - qwx);
    rotationMat[2][2] = 1.0 - 2.0 * (qxx + qyy);

    matrix *= rotationMat;
}

func scaleMatrix(matrix: inout simd_float4x4, scale: simd_float3) {
    matrix[0] *= scale.x;
    matrix[1] *= scale.y;
    matrix[2] *= scale.z
}

func createViewMatrix(eyePosition: simd_float3, targetPosition: simd_float3, upVec: simd_float3) -> simd_float4x4 {
    let forward = normalize(targetPosition - eyePosition)
    let rightVec = normalize(simd_cross(upVec, forward))
    let up = simd_cross(forward, rightVec)
    
    var matrix = matrix_identity_float4x4;
    matrix[0][0] = rightVec.x;
    matrix[1][0] = rightVec.y;
    matrix[2][0] = rightVec.z;
    matrix[0][1] = up.x;
    matrix[1][1] = up.y;
    matrix[2][1] = up.z;
    matrix[0][2] = forward.x;
    matrix[1][2] = forward.y;
    matrix[2][2] = forward.z;
    matrix[3][0] = -dot(rightVec, eyePosition);
    matrix[3][1] = -dot(up, eyePosition);
    matrix[3][2] = -dot(forward, eyePosition);
    
    return matrix;
}

func createPerspectiveMatrix(fov: Float, aspectRatio: Float, nearPlane: Float, farPlane: Float) -> simd_float4x4 {
    let tanHalfFov = tan(fov / 2.0);

    var matrix = simd_float4x4(0.0);
    matrix[0][0] = 1.0 / (aspectRatio * tanHalfFov);
    matrix[1][1] = 1.0 / (tanHalfFov);
    matrix[2][2] = farPlane / (farPlane - nearPlane);
    matrix[2][3] = 1.0;
    matrix[3][2] = -(farPlane * nearPlane) / (farPlane - nearPlane);
    
    return matrix;
}

func rotateVectorAroundNormal(vec: simd_float3, angle: Float, normal: simd_float3) -> simd_float3 {
    let c = cos(angle)
    let s = sin(angle)

    let axis = normalize(normal)
    let tmp = (1.0 - c) * axis

    var rotationMat = simd_float3x3(1.0)
    rotationMat[0][0] = c + tmp[0] * axis[0]
    rotationMat[0][1] = tmp[0] * axis[1] + s * axis[2]
    rotationMat[0][2] = tmp[0] * axis[2] - s * axis[1]

    rotationMat[1][0] = tmp[1] * axis[0] - s * axis[2]
    rotationMat[1][1] = c + tmp[1] * axis[1]
    rotationMat[1][2] = tmp[1] * axis[2] + s * axis[0]

    rotationMat[2][0] = tmp[2] * axis[0] + s * axis[1]
    rotationMat[2][1] = tmp[2] * axis[1] - s * axis[0]
    rotationMat[2][2] = c + tmp[2] * axis[2]

    return rotationMat * vec
}
