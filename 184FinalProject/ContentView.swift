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
    // store rotations globally
    var rotationX: Float = 0.0
    var rotationY: Float = 0.0
    var rotationZ: Float = 0.0
}


struct ContentView: View {
    @Environment(AppModel.self) private var appModel
    let rotationRange: ClosedRange<Float> = -90...90.0
    
    var body: some View {
        VStack {
            if appModel.immersiveSpaceState == .closed {
                Model3D(named: "rubiks_cube")
                .padding()
                // rotate by rotations in app model
                .rotation3DEffect(.init(degrees: Double(appModel.rotationX)), axis: (1, 0, 0))
                .rotation3DEffect(.init(degrees: Double(appModel.rotationY)), axis: (0, 1, 0))
                .rotation3DEffect(.init(degrees: Double(appModel.rotationZ)), axis: (0, 0, 1))
            }
            
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
            if appModel.immersiveSpaceState == .closed {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Model Rotation Controls")
                        .font(.headline)
                        .padding(.top, 20)
                    // X Rotation Slider
                    HStack {
                        Text("X Rotation:")
                        Slider(value: $bindableAppModel.rotationX, in: rotationRange, step: 1)
                        Text("\(Int(bindableAppModel.rotationX))°")
                            .frame(width: 40, alignment: .trailing)
                    }
                    // Y Rotation Slider
                    HStack {
                        Text("Y Rotation:")
                        Slider(value: $bindableAppModel.rotationY, in: rotationRange, step: 1)
                        Text("\(Int(bindableAppModel.rotationY))°")
                            .frame(width: 40, alignment: .trailing)
                    }
                    // Z Rotation Slider
                    HStack {
                        Text("Z Rotation:")
                        Slider(value: $bindableAppModel.rotationZ
                               , in: rotationRange, step: 1)
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
            .onChange(of: bindableAppModel.immersiveSpaceState) { _, _ in
                Globals.shared.rotationX = bindableAppModel.rotationX
                Globals.shared.rotationY = bindableAppModel.rotationY
                Globals.shared.rotationZ = bindableAppModel.rotationZ
            }
        }
        .padding()
    }
}

#Preview(windowStyle: .automatic) {
    ContentView()
        .environment(AppModel())
}
