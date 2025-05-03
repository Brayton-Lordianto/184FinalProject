//
//  File.swift
//  184FinalProject
//
//  Created by Brayton Lordianto on 5/2/25.
//

import Foundation

let fakeTriangles: [Triangle] = [
    // Light
    Triangle(
        p1: SIMD3<Float>(-1, 1.9, -2),
        p2: SIMD3<Float>(-1, 1.9, -4.5),
        p3: SIMD3<Float>(1, 1.9, -4.5),
        color: simd_half3(1, 1, 1),
        isLightSource: true,
        intensity: 100.0,
        material: .dielectric,
        roughness: 0.0
    ),

    // Back wall (blue) - split into 2 triangles
    Triangle(
        p1: SIMD3<Float>(-2, -2-3, -8),
        p2: SIMD3<Float>(2, -2-3, -8),
        p3: SIMD3<Float>(2, 2, -8),
        color: simd_half3(0.5, 0.5, 0.8),
        isLightSource: false,
        intensity: 2.0,
        material: .dielectric,
        roughness: 1.0
    ),
    Triangle(
        p1: SIMD3<Float>(-2, -2-3, -8),
        p2: SIMD3<Float>(2, 2, -8),
        p3: SIMD3<Float>(-2, 2, -8),
        color: simd_half3(0.5, 0.5, 0.8),
        isLightSource: false,
        intensity: 0.0,
        material: .dielectric,
        roughness: 0.0
    ),
    
    // Left wall (red) - split into 2 triangles
    Triangle(
        p1: SIMD3<Float>(-2, -2-3, -8),
        p2: SIMD3<Float>(-2, 2, -8),
        p3: SIMD3<Float>(-2, 2, -3),
        color: simd_half3(0.8, 0.2, 0.2),
        isLightSource: false,
        intensity: 0.0,
        material: .dielectric,
        roughness: 0.0
    ),
    Triangle(
        p1: SIMD3<Float>(-2, -2-3, -8),
        p2: SIMD3<Float>(-2, 2, -3),
        p3: SIMD3<Float>(-2, -2-3, -3),
        color: simd_half3(0.8, 0.2, 0.2),
        isLightSource: false,
        intensity: 0.0,
        material: .dielectric,
        roughness: 0.0
    ),
    
    // Right wall (green) - split into 2 triangles
    Triangle(
        p1: SIMD3<Float>(2, -2-3, -8),
        p2: SIMD3<Float>(2, -2-3, -3),
        p3: SIMD3<Float>(2, 2, -3),
        color: simd_half3(0.2, 0.8, 0.2),
        isLightSource: false,
        intensity: 0.0,
        material: .dielectric,
        roughness: 0.0
    ),
    Triangle(
        p1: SIMD3<Float>(2, -2-3, -8),
        p2: SIMD3<Float>(2, 2, -3),
        p3: SIMD3<Float>(2, 2, -8),
        color: simd_half3(0.2, 0.8, 0.2),
        isLightSource: false,
        intensity: 0.0,
        material: .dielectric,
        roughness: 0.0
    ),
    
    // Floor (light gray) - split into 2 triangles
    Triangle(
//        p1: SIMD3<Float>(-2, -2, -8),
//        p2: SIMD3<Float>(2, -2, -8),
//        p3: SIMD3<Float>(2, -2, -3),
        p1: SIMD3<Float>(-2, -5, -8),
        p2: SIMD3<Float>(2, -5, -8),
        p3: SIMD3<Float>(2, -5, 3),
        color: simd_half3(0.7, 0.7, 0.7),
        isLightSource: false,
        intensity: 0.0,
        material: .metal,
        roughness: 0.0
    ),
    Triangle(
//        p1: SIMD3<Float>(-2, -2, -8),
//        p2: SIMD3<Float>(2, -2, -3),
//        p3: SIMD3<Float>(-2, -2, -3),
        p1: SIMD3<Float>(-2, -5, -8),
        p2: SIMD3<Float>(2, -5, 3),
        p3: SIMD3<Float>(-2, -5, 3),
        color: simd_half3(0.7, 0.7, 0.7),
        isLightSource: false,
        intensity: 0.0,
        material: .metal,
        roughness: 0.0
    ),

    // Ceiling (light gray) - split into 2 triangles
    Triangle(
        p1: SIMD3<Float>(-2, 2, -8),
        p2: SIMD3<Float>(-2, 2, -3),
        p3: SIMD3<Float>(2, 2, -3),
        color: simd_half3(0.7, 0.7, 0.7),
        isLightSource: false,
        intensity: 0.0,
        material: .metal,
        roughness: 0.0
    ),
    Triangle(
        p1: SIMD3<Float>(-2, 2, -8),
        p2: SIMD3<Float>(2, 2, -3),
        p3: SIMD3<Float>(2, 2, -8),
        color: simd_half3(0.7, 0.7, 0.7),
        isLightSource: false,
        intensity: 0.0,
        material: .metal,
        roughness: 0.0
    ),
    
    // Tall box (metallic)
    // Front face
    Triangle(
        p1: SIMD3<Float>(-1.0, -2.0-3, -6.5),
        p2: SIMD3<Float>(-0.2, -2.0-3, -6.5),
        p3: SIMD3<Float>(-0.2, 0.3-3, -6.5),
//        p1: SIMD3<Float>(-1.0, -2.0, -6.5),
//        p2: SIMD3<Float>(-0.2, -2.0, -6.5),
//        p3: SIMD3<Float>(-0.2, 0.3, -6.5),
        color: simd_half3(0.9, 0.7, 0.3),
        isLightSource: false,
        intensity: 0.0,
        material: .dielectric,
        roughness: 0.1
    ),
    Triangle(
        p1: SIMD3<Float>(-1.0, -2.0-3, -6.5),
        p2: SIMD3<Float>(-0.2, 0.3-3, -6.5),
        p3: SIMD3<Float>(-1.0, 0.3-3, -6.5),
        color: simd_half3(0.9, 0.7, 0.3),
        isLightSource: false,
        intensity: 0.0,
        material: .dielectric,
        roughness: 0.1
    ),
    
    // Left face
    Triangle(
        p1: SIMD3<Float>(-1.0, -2.0-3, -7.5),
        p2: SIMD3<Float>(-1.0, -2.0-3, -6.5),
        p3: SIMD3<Float>(-1.0, 0.3-3, -6.5),
        color: simd_half3(0.9, 0.7, 0.3),
        isLightSource: false,
        intensity: 0.0,
        material: .dielectric,
        roughness: 0.1
    ),
    Triangle(
        p1: SIMD3<Float>(-1.0, -2.0-3, -7.5),
        p2: SIMD3<Float>(-1.0, 0.3-3, -6.5),
        p3: SIMD3<Float>(-1.0, 0.3-3, -7.5),
        color: simd_half3(0.9, 0.7, 0.3),
        isLightSource: false,
        intensity: 0.0,
        material: .dielectric,
        roughness: 0.1
    ),
    
    // Right face
    Triangle(
        p1: SIMD3<Float>(-0.2, -2.0-3, -7.5),
        p2: SIMD3<Float>(-0.2, -2.0-3, -6.5),
        p3: SIMD3<Float>(-0.2, 0.3-3, -6.5),
        color: simd_half3(0.9, 0.7, 0.3),
        isLightSource: false,
        intensity: 0.0,
        material: .dielectric,
        roughness: 0.1
    ),
    Triangle(
        p1: SIMD3<Float>(-0.2, -2.0-3, -7.5),
        p2: SIMD3<Float>(-0.2, 0.3-3, -6.5),
        p3: SIMD3<Float>(-0.2, 0.3-3, -7.5),
        color: simd_half3(0.9, 0.7, 0.3),
        isLightSource: false,
        intensity: 0.0,
        material: .dielectric,
        roughness: 0.1
    ),
    
    // Back face
    Triangle(
        p1: SIMD3<Float>(-1.0, -2.0-3, -7.5),
        p2: SIMD3<Float>(-0.2, -2.0-3, -7.5),
        p3: SIMD3<Float>(-0.2, 0.3-3, -7.5),
        color: simd_half3(0.9, 0.7, 0.3),
        isLightSource: false,
        intensity: 0.0,
        material: .dielectric,
        roughness: 0.1
    ),
    Triangle(
        p1: SIMD3<Float>(-1.0, -2.0-3, -7.5),
        p2: SIMD3<Float>(-0.2, 0.3-3, -7.5),
        p3: SIMD3<Float>(-1.0, 0.3-3, -7.5),
        color: simd_half3(0.9, 0.7-3, 0.3),
        isLightSource: false,
        intensity: 0.0,
        material: .dielectric,
        roughness: 0.1
    ),
    
    // Top face
    Triangle(
        p1: SIMD3<Float>(-1.0, 0.3-3, -7.5),
        p2: SIMD3<Float>(-0.2, 0.3-3, -7.5),
        p3: SIMD3<Float>(-0.2, 0.3-3, -6.5),
        color: simd_half3(0.9, 0.7, 0.3),
        isLightSource: false,
        intensity: 0.0,
        material: .dielectric,
        roughness: 0.1
    ),
    Triangle(
        p1: SIMD3<Float>(-1.0, 0.3-3, -7.5),
        p2: SIMD3<Float>(-0.2, 0.3-3, -6.5),
        p3: SIMD3<Float>(-1.0, 0.3-3, -6.5),
        color: simd_half3(0.9, 0.7, 0.3),
        isLightSource: false,
        intensity: 0.0,
        material: .dielectric,
        roughness: 0.1
    ),
    
    // Short box (glass-like)
    // Left face
    Triangle(
        p1: SIMD3<Float>(0.2, -2.0-3, -6.5),
        p2: SIMD3<Float>(0.2, -2.0-3, -5.5),
        p3: SIMD3<Float>(0.2, -1.0-3, -5.5),
        color: simd_half3(0.9, 0.9, 0.9),
        isLightSource: false,
        intensity: 0.0,
        material: .dielectric,
        roughness: 0.0
    ),
    Triangle(
        p1: SIMD3<Float>(0.2, -2.0-3, -6.5),
        p2: SIMD3<Float>(0.2, -1.0-3, -5.5),
        p3: SIMD3<Float>(0.2, -1.0-3, -6.5),
        color: simd_half3(0.9, 0.9, 0.9),
        isLightSource: false,
        intensity: 0.0,
        material: .dielectric,
        roughness: 0.0
    ),
    
    // Right face
    Triangle(
        p1: SIMD3<Float>(1.0, -2.0-3, -6.5),
        p2: SIMD3<Float>(1.0, -2.0-3, -5.5),
        p3: SIMD3<Float>(1.0, -1.0-3, -5.5),
        color: simd_half3(0.9, 0.9, 0.9),
        isLightSource: false,
        intensity: 0.0,
        material: .dielectric,
        roughness: 0.0
    ),
    Triangle(
        p1: SIMD3<Float>(1.0, -2.0-3, -6.5),
        p2: SIMD3<Float>(1.0, -1.0-3, -5.5),
        p3: SIMD3<Float>(1.0, -1.0-3, -6.5),
        color: simd_half3(0.9, 0.9, 0.9),
        isLightSource: false,
        intensity: 0.0,
        material: .dielectric,
        roughness: 0.0
    ),
    
    // Back face
    Triangle(
        p1: SIMD3<Float>(0.2, -2.0-3, -6.5),
        p2: SIMD3<Float>(1.0, -2.0-3, -6.5),
        p3: SIMD3<Float>(1.0, -1.0-3, -6.5),
        color: simd_half3(0.9, 0.9, 0.9),
        isLightSource: false,
        intensity: 0.0,
        material: .dielectric,
        roughness: 0.0
    ),
    Triangle(
        p1: SIMD3<Float>(0.2, -2.0-3, -6.5),
        p2: SIMD3<Float>(1.0, -1.0-3, -6.5),
        p3: SIMD3<Float>(0.2, -1.0-3, -6.5),
        color: simd_half3(0.9, 0.9, 0.9),
        isLightSource: false,
        intensity: 0.0,
        material: .dielectric,
        roughness: 0.0
    ),
    
    // Top face
    Triangle(
        p1: SIMD3<Float>(0.2, -1.0-3, -6.5),
        p2: SIMD3<Float>(1.0, -1.0-3, -6.5),
        p3: SIMD3<Float>(1.0, -1.0-3, -5.5),
        color: simd_half3(0.0, 0.9, 0.9), // Fixed the DIELECTRIC value to a proper color
        isLightSource: false,
        intensity: 0.0,
        material: .diffuse,
        roughness: 0.0
    ),
    Triangle(
        p1: SIMD3<Float>(0.2, -1.0-3, -6.5),
        p2: SIMD3<Float>(1.0, -1.0-3, -5.5),
        p3: SIMD3<Float>(0.2, -1.0-3, -5.5),
        color: simd_half3(0.0, 0.9, 0.9), // Fixed the DIELECTRIC value to a proper color
        isLightSource: false,
        intensity: 0.0,
        material: .diffuse,
        roughness: 0.0
    ),
    
    // Bottom face (front face of short box)
    Triangle(
        p1: SIMD3<Float>(0.2, -2.0-3, -5.5),
        p2: SIMD3<Float>(1.0, -2.0-3, -5.5),
        p3: SIMD3<Float>(1.0, -1.0-3, -5.5),
        color: simd_half3(0.9, 0.9, 0.9),
        isLightSource: false,
        intensity: 0.0,
        material: .dielectric,
        roughness: 0.0
    ),
    Triangle(
        p1: SIMD3<Float>(0.2, -2.0-3, -5.5),
        p2: SIMD3<Float>(1.0, -1.0-3, -5.5),
        p3: SIMD3<Float>(0.2, -1.0-3, -5.5),
        color: simd_half3(0.9, 0.9, 0.9),
        isLightSource: false,
        intensity: 0.0,
        material: .dielectric,
        roughness: 0.0
    )
]
