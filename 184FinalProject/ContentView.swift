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

            Text("Path Tracer Demo")
                .font(.title)
                .padding(.bottom, 20)
                
            // Renderer mode picker
            Picker("Rendering Mode", selection: $appModel.rendererMode) {
                ForEach(AppModel.RendererMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .padding(.bottom, 20)
            
            Text("Current mode: \(appModel.rendererMode.rawValue)")
                .font(.caption)
                .padding(.bottom, 10)

            ToggleImmersiveSpaceButton()
        }
        .padding()
    }
}

#Preview(windowStyle: .automatic) {
    ContentView()
        .environment(AppModel())
}
