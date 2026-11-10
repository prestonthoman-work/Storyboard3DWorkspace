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
    private static let framingAttachmentID = "framing"
    private static let toolbarAttachmentID = "objectToolbar"

    var body: some View {
        RealityView { content, attachments in
            let workspace = appModel.workspace
            // These may still be parented to a previous session's content.
            workspace.root.removeFromParent()
            workspace.viewfinder.removeFromParent()
            workspace.earpiece.removeFromParent()
            content.add(workspace.root)
            content.add(workspace.viewfinder)
            content.add(workspace.earpiece)

            // The self-timer count floats in the middle of the viewfinder.
            if let countdown = attachments.entity(for: Self.countdownAttachmentID) {
                countdown.position = [0, 0, -WorkspaceScene.viewfinderDistance]
                workspace.viewfinder.addChild(countdown)
            }
            // Lens, format, and lighting sit just under the frame, like a camera's status line.
            if let framing = attachments.entity(for: Self.framingAttachmentID) {
                workspace.viewfinder.addChild(framing)
            }
            // Edits for the selected object float just above it.
            if let toolbar = attachments.entity(for: Self.toolbarAttachmentID) {
                workspace.handles.toolbarAnchor.addChild(toolbar)
            }

            workspace.subscriptions = [
                content.subscribe(to: ManipulationEvents.WillBegin.self) { event in
                    workspace.setHeld(true, for: event.entity)
                    if let object = workspace.object(containing: event.entity) {
                        SoundEffects.play(.grab, on: object, gain: -14)
                    }
                    appModel.manipulationBegan(on: event.entity)
                },
                content.subscribe(to: ManipulationEvents.DidUpdateTransform.self) { event in
                    workspace.clampScale(of: event.entity)
                    if appModel.isSnappingOn { workspace.applySnapping(to: event.entity) }
                    workspace.keepAboveSurface(event.entity)
                },
                // Letting go hands the object to gravity.
                content.subscribe(to: ManipulationEvents.WillRelease.self) { event in
                    workspace.setHeld(false, for: event.entity)
                },
                content.subscribe(to: ManipulationEvents.WillEnd.self) { event in
                    workspace.setHeld(false, for: event.entity)
                    workspace.hideGuides()
                    // Auto-save the new arrangement into the selected keyframe once it settles.
                    appModel.sceneEdited()
                }
            ]
        } update: { _, attachments in
            appModel.workspace.setViewfinderVisible(appModel.isViewfinderVisible)
            updateLabels(attachments)
            if let framing = attachments.entity(for: Self.framingAttachmentID) {
                let half = WorkspaceScene.viewfinderHalfSize(for: appModel.captureLens)
                framing.position = [0, -half.y - 0.014, -WorkspaceScene.viewfinderDistance]
            }
        } attachments: {
            Attachment(id: Self.countdownAttachmentID) {
                CountdownBadge()
            }
            Attachment(id: Self.framingAttachmentID) {
                FramingLabel()
            }
            Attachment(id: Self.toolbarAttachmentID) {
                ObjectToolbar()
            }
            ForEach(appModel.objects) { object in
                Attachment(id: object.id) {
                    ObjectNameTag(name: object.name)
                }
            }
        }
        // The base's edge: swipe to spin the whole set like a turntable.
        .gesture(
            DragGesture(minimumDistance: 0)
                .targetedToEntity(where: .has(TurntableGripComponent.self))
                .onChanged { value in
                    appModel.dragTurntable(to: value.convert(value.location3D, from: .local, to: .scene))
                }
                .onEnded { _ in appModel.endTurntableDrag() }
        )
        // Selection handles: turn or resize the selected object.
        .gesture(
            DragGesture(minimumDistance: 0)
                .targetedToEntity(where: .has(SelectionHandleComponent.self))
                .onChanged { value in
                    appModel.dragHandle(value.entity, to: value.convert(value.location3D, from: .local, to: .scene))
                }
                .onEnded { _ in appModel.endHandleDrag() }
        )
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

extension ImmersiveView {
    /// Hands each name tag its object and says whether it should show.
    private func updateLabels(_ attachments: RealityViewAttachments) {
        let workspace = appModel.workspace
        for object in appModel.objects {
            guard let tag = attachments.entity(for: object.id) else { continue }
            if tag.parent !== workspace.labelsRoot {
                workspace.labelsRoot.addChild(tag)
                tag.components.set(BillboardComponent())
            }
            tag.components.set(ObjectLabelComponent(
                target: workspace.object(withID: object.id),
                wantsVisible: appModel.showsObjectLabels && object.id != appModel.selectedObjectID
            ))
        }
    }
}

private struct CountdownBadge: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        ZStack {
            if let remaining = appModel.captureCountdown {
                Text("\(remaining)")
                    .font(.system(size: 56, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText(countsDown: true))
                    .frame(width: 96, height: 96)
                    .glassBackgroundEffect(in: Circle())
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.6), value: appModel.captureCountdown)
    }
}

/// "35 mm · 2.39:1 · Golden Hour" under the viewfinder.
private struct FramingLabel: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "record.circle")
                .foregroundStyle(appModel.isCapturing ? .red : .white.opacity(0.7))
            Text([appModel.captureLens.label, appModel.captureLook.format.label, appModel.captureLighting.name]
                    .joined(separator: "  ·  "))
                .monospacedDigit()
        }
        .font(.system(size: 13, weight: .medium, design: .rounded))
        .foregroundStyle(.white.opacity(0.85))
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(.black.opacity(0.35), in: Capsule())
        .animation(.easeInOut(duration: 0.2), value: appModel.isCapturing)
    }
}

#Preview(immersionStyle: .mixed) {
    ImmersiveView()
        .environment(AppModel())
}
