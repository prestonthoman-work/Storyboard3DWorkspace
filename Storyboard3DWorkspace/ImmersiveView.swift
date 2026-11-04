//
//  ImmersiveView.swift
//  Storyboard3DWorkspace
//
//  Created by Preston Thoman on 11/4/26.
//

import SwiftUI
import RealityKit

struct ImmersiveView: View {

    @Environment(AppModel.self) private var appModel

    var body: some View {
        RealityView { content in
            let workspace = appModel.workspace
            // The root may still be parented to a previous session's content.
            workspace.root.removeFromParent()
            content.add(workspace.root)

            workspace.subscriptions = [
                content.subscribe(to: ManipulationEvents.WillBegin.self) { event in
                    workspace.setHeld(true, for: event.entity)
                    appModel.manipulationBegan(on: event.entity)
                },
                content.subscribe(to: ManipulationEvents.DidUpdateTransform.self) { event in
                    workspace.clampScale(of: event.entity)
                    workspace.keepAboveSurface(event.entity)
                },
                // Letting go hands the object to gravity.
                content.subscribe(to: ManipulationEvents.WillRelease.self) { event in
                    workspace.setHeld(false, for: event.entity)
                },
                content.subscribe(to: ManipulationEvents.WillEnd.self) { event in
                    workspace.setHeld(false, for: event.entity)
                }
            ]
        }
        .gesture(
            SpatialTapGesture()
                .targetedToAnyEntity()
                .onEnded { value in appModel.selectObject(containing: value.entity) }
        )
        .task {
            await appModel.workspaceDidOpen()
        }
        .onDisappear {
            appModel.workspaceDidClose()
            appModel.workspace.subscriptions.removeAll()
        }
    }
}

#Preview(immersionStyle: .mixed) {
    ImmersiveView()
        .environment(AppModel())
}
