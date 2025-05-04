//
//  AppModel.swift
//  184FinalProject
//
//  Created by Brayton Lordianto on 4/14/25.
//

import SwiftUI

/// Maintains app-wide state
@MainActor
@Observable
class AppModel {
    let immersiveSpaceID = "ImmersiveSpace"
    enum ImmersiveSpaceState {
        case closed
        case inTransition
        case open
    }
    var immersiveSpaceState = ImmersiveSpaceState.closed
    
    enum ModelType: String, CaseIterable, Identifiable {
        case customCornellBox = "Custom Cornell Box"
        case bunny = "Bunny"
        case originalCornellBox = "Original Cornell Box"
        
        var id: String { self.rawValue }
        
        var filename: String {
            switch self {
            case .originalCornellBox:
                return "CornellTest"
            case .customCornellBox:
                return ""  // Uses fakeTriangles
            case .bunny:
                return "bunny"
            }
        }
        
        var useFakeTriangles: Bool {
            return self == .customCornellBox
        }
    }
    
    var selectedModel: ModelType = .customCornellBox
    
    
    // add rotations
    var rotationX: Float = 0.0
    var rotationY: Float = 0.0
    var rotationZ: Float = 0.0
    
    // shader options
    var useViewMatrix: Bool = false
    
    // Resolution options
    enum Resolution: Int, CaseIterable, Identifiable {
        case low = 720
        case medium = 1080
        case high = 1440
        case ultra = 2160
        
        var id: Int { self.rawValue }
        
        var displayName: String {
            switch self {
            case .low: return "Low (720p)"
            case .medium: return "Medium (1080p)"
            case .high: return "High (1440p)"
            case .ultra: return "Ultra (2160p)"
            }
        }
    }
    
    var selectedResolution: Resolution = .high
    
    // Camera options for simulating depth of field and lens effects
    var lensRadius: Float = 0.0
    var focalDistance: Float = 4
    var SPH: Float = 0
    var CYL: Float = 0
    var AXIS: Float =  45
    var dofJustChanged: Bool = false
    func changeDOF() {
        dofJustChanged.toggle()
    }
}
