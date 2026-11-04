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

            let stage = workspace.stageModel
            workspace.subscriptions = [
                content.subscribe(to: ManipulationEvents.WillBegin.self, on: stage) { _ in
                    appModel.modelManipulationBegan()
                },
                content.subscribe(to: ManipulationEvents.DidUpdateTransform.self, on: stage) { _ in
                    workspace.clampModelScale()
                }
            ]
        }
        .gesture(
            SpatialTapGesture()
                .targetedToEntity(appModel.workspace.stageModel)
                .onEnded { _ in appModel.setModelSelected(true) }
        )
        .task {
            await ViewerPoseProvider.shared.start()
        }
        .onDisappear {
            appModel.animator.pause()
            ViewerPoseProvider.shared.stop()
            appModel.workspace.subscriptions.removeAll()
        }
    }
}

#Preview(immersionStyle: .mixed) {
    ImmersiveView()
        .environment(AppModel())
}
