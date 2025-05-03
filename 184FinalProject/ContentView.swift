//
//  ContentView.swift
//  184FinalProject
//
//  Created by Brayton Lordianto on 4/14/25.
//

import SwiftUI
import RealityKit
import RealityKitContent

// make static singleton global variable for name
class Globals {
    private init() {}
    public static let shared = Globals()
    var name: String = AppModel.ModelType.customCornellBox.rawValue
    // we center the models differently for rotation around that axis
    let modelCenter: SIMD3<Float> = SIMD3<Float>(0, -0.5, 0)
}


struct ContentView: View {
    @Environment(AppModel.self) private var appModel
    
    var body: some View {
        VStack {
            Text("Select Model for Path Tracing")
                .font(.headline)
                .padding(.bottom, 8)
            
            @Bindable var bindableAppModel = appModel
                       
            Picker("Model", selection: $bindableAppModel.selectedModel) {
                ForEach(AppModel.ModelType.allCases) { modelType in
                    Text(modelType.rawValue).tag(modelType)
                }
            }
            .pickerStyle(.menu)
            .disabled(appModel.immersiveSpaceState == .open ||
                      appModel.immersiveSpaceState == .inTransition)
            .padding(.bottom, 20)
            
            // MARK: rotations of the model
            if appModel.immersiveSpaceState == .open {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Model Rotation Controls")
                        .font(.headline)
                        .padding(.top, 20)
                    // X Rotation Slider
                    HStack {
                        Text("X Rotation:")
                        Slider(value: $bindableAppModel.rotationX, in: 0...360, step: 1)
                        Text("\(Int(bindableAppModel.rotationX))°")
                            .frame(width: 40, alignment: .trailing)
                    }
                    // Y Rotation Slider
                    HStack {
                        Text("Y Rotation:")
                        Slider(value: $bindableAppModel.rotationY, in: 0...360, step: 1)
                        Text("\(Int(bindableAppModel.rotationY))°")
                            .frame(width: 40, alignment: .trailing)
                    }
                    // Z Rotation Slider
                    HStack {
                        Text("Z Rotation:")
                        Slider(value: $bindableAppModel.rotationZ
                               , in: 0...360, step: 1)
                        Text("\(Int(bindableAppModel.rotationZ))°")
                            .frame(width: 40, alignment: .trailing)
                    }
                    // Reset button
                    Button("Reset Rotation") {
                        bindableAppModel.rotationX = 0
                        bindableAppModel.rotationY = 0
                        bindableAppModel.rotationZ = 0
                    }
                    .buttonStyle(.bordered)
                    .padding(.top, 8)
                }
            }

            
            
            
            ToggleImmersiveSpaceButton()
            
            .onChange(of: bindableAppModel.selectedModel) { _, newValue in
                Globals.shared.name = newValue.filename
            }
        }
        .padding()
    }
}

#Preview(windowStyle: .automatic) {
    ContentView()
        .environment(AppModel())
}
