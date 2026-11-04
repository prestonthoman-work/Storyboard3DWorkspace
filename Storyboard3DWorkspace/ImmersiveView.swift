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

    private static let countdownAttachmentID = "countdown"

    var body: some View {
        RealityView { content, attachments in
            let workspace = appModel.workspace
            // These may still be parented to a previous session's content.
            workspace.root.removeFromParent()
            workspace.viewfinder.removeFromParent()
            content.add(workspace.root)
            content.add(workspace.viewfinder)

            // The self-timer count floats in the middle of the viewfinder.
            if let countdown = attachments.entity(for: Self.countdownAttachmentID) {
                countdown.position = [0, 0, -WorkspaceScene.viewfinderDistance]
                workspace.viewfinder.addChild(countdown)
            }

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
                    // Auto-save the new arrangement into the selected keyframe once it settles.
                    appModel.sceneEdited()
                }
            ]
        } update: { _, _ in
            appModel.workspace.setViewfinderVisible(appModel.isViewfinderVisible)
        } attachments: {
            Attachment(id: Self.countdownAttachmentID) {
                CountdownBadge()
            }
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

private struct CountdownBadge: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        if let remaining = appModel.captureCountdown {
            Text("\(remaining)")
                .font(.system(size: 56, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .frame(width: 96, height: 96)
                .glassBackgroundEffect(in: Circle())
        }
    }
}

#Preview(immersionStyle: .mixed) {
    ImmersiveView()
        .environment(AppModel())
}
