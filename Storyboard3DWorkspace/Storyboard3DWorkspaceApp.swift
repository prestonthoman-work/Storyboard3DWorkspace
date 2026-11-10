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

    static let mainWindowID = "main"

    @State private var appModel = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        ViewerFacingBackdropComponent.registerComponent()
        ViewerFacingBackdropSystem.registerSystem()
        ObjectGravityComponent.registerComponent()
        GravitySurfaceComponent.registerComponent()
        ObjectGravitySystem.registerSystem()
        PlacedObjectComponent.registerComponent()
        ScaleSpringComponent.registerComponent()
        ScaleSpringSystem.registerSystem()
        BaseSurfaceComponent.registerComponent()
        SelectionHandleComponent.registerComponent()
        SelectionFollowComponent.registerComponent()
        SelectionFollowSystem.registerSystem()
        TurntableGripComponent.registerComponent()
        TurntableComponent.registerComponent()
        TurntableSystem.registerSystem()
        ObjectLabelComponent.registerComponent()
        ObjectLabelSystem.registerSystem()
    }

    var body: some SwiftUI.Scene {
        WindowGroup(id: Self.mainWindowID) {
            ContentView()
                .environment(appModel)
                .onChange(of: scenePhase) { _, phase in
                    if phase != .active { appModel.saveNow() }
                }
        }
        .windowResizability(.contentSize)
        // A utility panel sits low and close to the viewer, keeping the model's sight line clear.
        .defaultWindowPlacement { _, _ in
            WindowPlacement(.utilityPanel)
        }

        // A wide keyframe editor beside the control panel.
        WindowGroup(id: TimelineWindow.windowID) {
            TimelineWindow()
                .environment(appModel)
        }
        .defaultSize(width: 1100, height: 460)
        .windowResizability(.contentMinSize)
        .defaultWindowPlacement { _, context in
            if let main = context.windows.first(where: { $0.id == Self.mainWindowID }) {
                WindowPlacement(.trailing(main))
            } else {
                WindowPlacement(.utilityPanel)
            }
        }

        // A large screening window for the storyboard.
        WindowGroup(id: StoryboardViewer.windowID) {
            StoryboardViewer()
                .environment(appModel)
        }
        .windowStyle(.plain)
        .defaultSize(width: 1280, height: 720)

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
