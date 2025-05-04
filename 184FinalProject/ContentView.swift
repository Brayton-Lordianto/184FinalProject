//
//  ContentView.swift
//  184FinalProject
//
//  Created by Brayton Lordianto on 4/14/25.
//

import SwiftUI
import RealityKit
import RealityKitContent

struct ContentView: View {
    @Environment(AppModel.self) private var appModel
    var body: some View {
        VStack {
            Model3D(named: "Scene", bundle: realityKitContentBundle)
                .padding(.bottom, 50)

            Text("Hello, world!")

            ToggleImmersiveSpaceButton()
            
            // make sliders for lens radius, focal distance, SPH, CYL, and AXIS
            @Bindable var bindableAppModel = appModel
            HStack {
                Text("Lens Radius")
                Slider(value: $bindableAppModel.lensRadius, in: 0.0...1, step: 0.1) {
                    Text("Lens Radius")
                }
                // to 2 dp
                Text("\(String(format: "%.2f", bindableAppModel.lensRadius))")
                    .padding(.bottom, 20)
            }
            HStack {
                Text("Focal Distance")
                Slider(value: $bindableAppModel.focalDistance, in: 0.0...10.0, step: 0.1) {
                    Text("Focal Distance")
                }
                Text("\( String(format: "%.2f", bindableAppModel.focalDistance))")
                    .padding(.bottom, 20)
                .padding(.bottom, 20)
            }
            HStack {
                Text("SPH")
                Slider(value: $bindableAppModel.SPH, in: 0.0...4.0, step: 0.1) {
                    Text("SPH")
                }
                Text("\(String(format: "%.2f", bindableAppModel.SPH))")
                    .padding(.bottom, 20)
            }
            HStack {
                Text("CYL")
                Slider(value: $bindableAppModel.CYL, in: 0.0...4.0, step: 0.1) {
                    Text("CYL")
                }
                Text("\(String(format: "%.2f", bindableAppModel.CYL))")
                    .padding(.bottom, 20)
            }
            HStack {
                Text("ASTIGMATISM AXIS")
                Slider(value: $bindableAppModel.AXIS, in: 0.0...360.0, step: 1) {
                    Text("AXIS")
                }
                Text("\(Int(bindableAppModel.AXIS))")
                    .padding(.bottom, 20)
            }
            

            Button("Change DOF") {
                appModel.changeDOF()
            }
            
        }
        .padding()
    }
}

#Preview(windowStyle: .automatic) {
    ContentView()
        .environment(AppModel())
}
