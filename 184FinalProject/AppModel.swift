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
    
    // Renderer mode settings
    enum RendererMode: String, CaseIterable, Identifiable {
        case standard = "Standard"
        case tileBased = "Tile-Based"
        
        var id: String { rawValue }
    }
    
    var rendererMode: RendererMode = .standard
}
