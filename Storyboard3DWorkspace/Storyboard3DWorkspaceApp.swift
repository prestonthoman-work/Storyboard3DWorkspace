//
//  Storyboard3DWorkspaceApp.swift
//  Storyboard3DWorkspace
//
//  Created by Preston Thoman on 11/4/26.
//

import SwiftUI
import RealityKit

@main
struct Storyboard3DWorkspaceApp: App {

    @State private var appModel = AppModel()

    init() {
        ViewerFacingBackdropComponent.registerComponent()
        ViewerFacingBackdropSystem.registerSystem()
    }

    var body: some SwiftUI.Scene {
        WindowGroup {
            ContentView()
                .environment(appModel)
        }
        .windowResizability(.contentSize)
        // A utility panel sits low and close to the viewer, keeping the model's sight line clear.
        .defaultWindowPlacement { _, _ in
            WindowPlacement(.utilityPanel)
        }

        ImmersiveSpace(id: appModel.immersiveSpaceID) {
            ImmersiveView()
                .environment(appModel)
                .onAppear {
                    appModel.immersiveSpaceState = .open
                }
                .onDisappear {
                    appModel.immersiveSpaceState = .closed
                }
        }
        .immersionStyle(selection: .constant(.mixed), in: .mixed)
     }
}
