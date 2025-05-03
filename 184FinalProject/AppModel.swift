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
            case .customCornellBox:
                return ""  // Uses fakeTriangles
            case .bunny:
                return "bunny"
            case .originalCornellBox:
                return "Cornell_Box_2"
            }
        }
        
        var useFakeTriangles: Bool {
            return self == .customCornellBox
        }
    }
    
    var selectedModel: ModelType = .bunny
}
