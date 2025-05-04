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
    
    var lensRadius: Float = 0.1
    var focalDistance: Float = 4
    var SPH: Float = 0
    var CYL: Float = 0
    var AXIS: Float =  45
    var dofJustChanged: Bool = false
    func changeDOF() {
        dofJustChanged.toggle()
    }
}
