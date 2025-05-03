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
            ToggleImmersiveSpaceButton()
        }
        .padding()
    }
}

#Preview(windowStyle: .automatic) {
    ContentView()
        .environment(AppModel())
}
