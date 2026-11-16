//
//  PoseStudioView.swift
//  Storyboard3DWorkspace
//

import RealityKit
import SwiftUI

/// A volume showing the selected character at about half life size, for posing with your
/// hands: pinch a body part and drag to swing it, tap to pick it, drag the blue target to
/// place a hand or foot, and drag the floor to look from any side. Edits go straight to the
/// character in the scene.
struct PoseStudioView: View {
    static let windowID = "poseStudio"

    @Environment(AppModel.self) private var appModel
    @State private var turnStart: Float?

    private var studio: PoseStudioScene { appModel.poseStudio }

    var body: some View {
        RealityView { content in
            studio.root.removeFromParent()
            content.add(studio.root)
        } update: { _ in
            appModel.updatePoseStudio()
        }
        // Pinch a body part and drag: its joint swings to follow.
        .gesture(
            DragGesture(minimumDistance: 0)
                .targetedToEntity(where: .has(BodyPartComponent.self))
                .onChanged { value in
                    guard let joint = value.entity.components[BodyPartComponent.self]?.joint else { return }
                    let start = value.convert(value.startLocation3D, from: .local, to: .scene)
                    let now = value.convert(value.location3D, from: .local, to: .scene)
                    guard let from = studio.direction(from: joint, to: start),
                          let to = studio.direction(from: joint, to: now) else { return }
                    appModel.swingJoint(joint, from: from, to: to)
                }
                .onEnded { _ in appModel.endPoseDrag() }
        )
        // The blue target: place the selected hand or foot; the limb bends to reach.
        .gesture(
            DragGesture(minimumDistance: 0)
                .targetedToEntity(where: .has(IKHandleComponent.self))
                .onChanged { value in
                    guard let joint = appModel.selectedJoint, let limb = Limb(end: joint) else { return }
                    let point = value.convert(value.location3D, from: .local, to: .scene)
                    studio.moveReachTarget(to: point, isDragging: true)
                    if let target = studio.limbSpacePoint(point, for: limb) {
                        appModel.dragReach(limb, to: target)
                    }
                }
                .onEnded { _ in appModel.endPoseDrag() }
        )
        // Drag the floor sideways to look from another side.
        .gesture(
            DragGesture(minimumDistance: 0.005)
                .targetedToEntity(where: .has(StudioTurntableComponent.self))
                .onChanged { value in
                    if turnStart == nil { turnStart = studio.viewAngle }
                    let travel = Float(value.convert(value.translation3D, from: .local, to: .scene).x)
                    studio.viewAngle = (turnStart ?? 0) + travel / 0.25 * .pi / 2
                }
                .onEnded { _ in turnStart = nil }
        )
        .ornament(attachmentAnchor: .scene(.bottomFront), contentAlignment: .top) {
            PoseStudioToolbar()
                .padding(.top, 16)
        }
        .ornament(attachmentAnchor: .scene(.trailing), contentAlignment: .leading) {
            if appModel.isSelectedObjectCharacter {
                PoseStudioInspector()
                    .padding(.leading, 20)
            }
        }
        .onAppear {
            appModel.isPoseStudioOpen = true
            appModel.setCharacterEditMode(.pose)
        }
        .onDisappear {
            appModel.endPoseDrag()
            appModel.isPoseStudioOpen = false
        }
    }
}

/// Under the studio: what's selected, poses, the tool, view angle, and undo.
private struct PoseStudioToolbar: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        @Bindable var appModel = appModel

        Group {
            if let character = appModel.selectedObject, appModel.isSelectedObjectCharacter {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(character.name)
                            .font(.callout.weight(.semibold))
                            .lineLimit(1)
                        Text(appModel.selectedJoint?.displayName ?? "Tap a body part")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .frame(minWidth: 110, alignment: .leading)
                    .padding(.horizontal, 6)

                    if let joint = appModel.selectedJoint, let limb = Limb(end: joint) {
                        Picker("Tool", selection: $appModel.poseTool) {
                            Text("Rotate").tag(AppModel.PoseTool.rotate)
                            Text("Place \(limb.isArm ? "Hand" : "Foot")").tag(AppModel.PoseTool.reach)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 210)
                    }

                    Menu {
                        Section("Presets") {
                            ForEach(PosePreset.allCases) { preset in
                                Button(preset.name, systemImage: preset.symbol) { appModel.applyPreset(preset) }
                            }
                        }
                        if !appModel.savedPoses.isEmpty {
                            Section("My Poses") {
                                ForEach(appModel.savedPoses) { saved in
                                    Button(saved.name, systemImage: "person.crop.circle") { appModel.applyPose(saved.pose) }
                                }
                            }
                        }
                    } label: {
                        Label("Poses", systemImage: "figure.dance")
                    }

                    Button("Reset Pose", systemImage: "arrow.counterclockwise") { appModel.resetPose() }
                        .disabled(appModel.selectedCharacterPose?.isNeutral ?? true)

                    Divider().frame(height: 28)

                    ViewAngleButtons()

                    Divider().frame(height: 28)

                    Button("Undo", systemImage: "arrow.uturn.backward") { appModel.undo() }
                        .disabled(!appModel.canUndo)
                    Button("Redo", systemImage: "arrow.uturn.forward") { appModel.redo() }
                        .disabled(!appModel.canRedo)
                }
                .labelStyle(.iconOnly)
                .buttonBorderShape(.circle)
            } else {
                Label("Select a character in the scene or the Objects list to pose it here.", systemImage: "figure.stand")
                    .font(.callout)
                    .padding(.horizontal, 12)
            }
        }
        .padding(10)
        .glassBackgroundEffect(in: Capsule())
    }
}

/// Look at the figure from the front, side, or back. Only the view turns.
private struct ViewAngleButtons: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        HStack(spacing: 4) {
            Button("Front View", systemImage: "person.fill") { turn(to: 0) }
            Button("Side View", systemImage: "person.fill.turn.right") { turn(to: -.pi / 2) }
            Button("Back View", systemImage: "person.fill.turn.down") { turn(to: .pi) }
        }
    }

    private func turn(to angle: Float) {
        appModel.poseStudio.viewAngle = angle
    }
}

/// Beside the studio: every body part, and exact angles for the selected one.
private struct PoseStudioInspector: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Pinch a body part and drag to swing it. Tap to select it.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                BodyPartPicker()
                if let joint = appModel.selectedJoint {
                    JointEditor(joint: joint)
                }
            }
            .padding(20)
        }
        .frame(width: 400, height: 560)
        .glassBackgroundEffect(in: RoundedRectangle(cornerRadius: 28, style: .continuous))
    }
}
