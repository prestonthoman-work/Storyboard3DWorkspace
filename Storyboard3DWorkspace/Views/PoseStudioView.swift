//
//  PoseStudioView.swift
//  Storyboard3DWorkspace
//

import RealityKit
import SwiftUI

/// A volume showing the selected character at about half life size, for posing with your
/// hands. Pinch any body part and drag: arms, legs, torso, and head swing at their joints,
/// and a hand or foot follows your hand while its arm or leg bends. Drag the floor to look
/// from another side. Every edit goes straight to the character in the scene.
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
        .gesture(
            DragGesture(minimumDistance: 0)
                .targetedToEntity(where: .has(BodyPartComponent.self))
                .onChanged { value in
                    guard let joint = value.entity.components[BodyPartComponent.self]?.joint else { return }
                    let start = value.convert(value.startLocation3D, from: .local, to: .scene)
                    let now = value.convert(value.location3D, from: .local, to: .scene)
                    if let limb = Limb(end: joint) {
                        // Hands and feet go where you take them; the limb bends to follow.
                        guard let from = studio.limbSpacePoint(start, for: limb),
                              let to = studio.limbSpacePoint(now, for: limb) else { return }
                        appModel.dragHand(limb, from: from, to: to)
                    } else {
                        guard let from = studio.direction(from: joint, to: start),
                              let to = studio.direction(from: joint, to: now) else { return }
                        appModel.swingJoint(joint, from: from, to: to)
                    }
                }
                .onEnded { _ in appModel.endPoseDrag() }
        )
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
        .ornament(attachmentAnchor: .scene(.trailing), contentAlignment: .leading) {
            PoseStudioPanel()
                .padding(.leading, 20)
        }
        .onAppear {
            appModel.isPoseStudioOpen = true
            // Opening with nothing posable selected picks the first character in the scene.
            if !appModel.isSelectedObjectCharacter, let first = appModel.characters.first {
                appModel.selectObject(first.id)
            }
        }
        .onDisappear {
            appModel.endPoseDrag()
            appModel.isPoseStudioOpen = false
        }
    }
}

// MARK: Panel

/// Beside the studio: which character, undo, poses, the view, every body part, and exact
/// control of the selected one.
private struct PoseStudioPanel: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Title and the way back: poses are already in the scene, so Done just closes.
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Pose Studio")
                            .font(.title3.weight(.semibold))
                        Text("Changes go straight to the scene.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    Button {
                        appModel.selectedTab = .objects
                        dismissWindow(id: PoseStudioView.windowID)
                    } label: {
                        Label("Done", systemImage: "checkmark")
                    }
                    .buttonStyle(.borderedProminent)
                    .help("Close the Pose Studio and go back to the Objects tab")
                }

                HStack(spacing: 8) {
                    CharacterPicker()
                    Spacer(minLength: 0)
                    Button("Undo", systemImage: "arrow.uturn.backward") { appModel.undo() }
                        .disabled(!appModel.canUndo)
                        .help("Undo")
                    Button("Redo", systemImage: "arrow.uturn.forward") { appModel.redo() }
                        .disabled(!appModel.canRedo)
                        .help("Redo")
                }
                .labelStyle(.iconOnly)
                .buttonBorderShape(.circle)

                if appModel.isSelectedObjectCharacter {
                    HStack(spacing: 8) {
                        PosesMenu()
                        ViewAngleButtons()
                            .labelStyle(.iconOnly)
                            .buttonBorderShape(.circle)
                        Spacer(minLength: 0)
                        Button("Reset Whole Pose", systemImage: "arrow.counterclockwise") { appModel.resetPose() }
                            .tint(.red)
                            .disabled(appModel.selectedCharacterPose?.isNeutral ?? true)
                            .help("Straighten every joint. The character stays where it is in the scene.")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    SceneActions()
                    if let note = appModel.poseNote {
                        StatusMessage(note, kind: .warning)
                    }

                    Divider()

                    BodyPartPicker()
                    if let joint = appModel.selectedJoint {
                        JointEditor(joint: joint)
                    } else {
                        Label("Pinch any body part and drag it. Grab a hand or foot to place it; the arm or leg bends to follow.",
                              systemImage: "hand.pinch")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    if let error = appModel.poseLibraryError {
                        StatusMessage(error, kind: .error)
                    }
                    if let note = appModel.objectNote, PosePreset.allCases.contains(where: { $0.requirement == note }) {
                        StatusMessage(note, kind: .warning)
                    }
                }
            }
            .padding(20)
        }
        .frame(width: 460, height: 640)
        .glassBackgroundEffect(in: RoundedRectangle(cornerRadius: 28, style: .continuous))
    }
}

/// Posing against the rest of the scene: look at something, aim again after things move,
/// or sit on an object.
private struct SceneActions: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        let others = appModel.objects.filter { $0.id != appModel.selectedObjectID }
        VStack(alignment: .leading, spacing: 8) {
        HStack(spacing: 8) {
            Menu {
                ForEach(others) { object in
                    Button(object.name, systemImage: object.recipe.characterKind?.symbol ?? "cube") {
                        appModel.lookSelectedCharacter(at: object.id)
                    }
                }
            } label: {
                Label("Look At", systemImage: "eye")
            }
            .disabled(others.isEmpty)
            .help("Keep the head, neck, and chest turned toward another object or character, even as you both move")

            if let target = appModel.selectedLookTarget {
                Text("Looking at \(target.name)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Button("Stop Looking", systemImage: "eye.slash") { appModel.stopLookingSelectedCharacter() }
                    .labelStyle(.iconOnly)
                    .buttonBorderShape(.circle)
                    .help("Stop following \(target.name); the head stays where it is")
            }

            Spacer(minLength: 0)
        }
        HStack(spacing: 8) {
            Menu {
                ForEach(appModel.seats) { seat in
                    Button(seat.name) { appModel.sitSelectedCharacter(on: seat.id) }
                }
            } label: {
                Label("Sit On", systemImage: "figure.seated.side")
            }
            .disabled(appModel.seats.isEmpty)
            .help("Sit on an object: the legs bend to its height and the character moves on top of it")

            Menu {
                ForEach(appModel.seats) { support in
                    Menu(support.name) {
                        ForEach(LeanPart.allCases) { part in
                            Button(part.name) { appModel.leanSelectedCharacter(on: support.id, with: part) }
                        }
                    }
                }
            } label: {
                Label("Lean On", systemImage: "figure.stand.line.dotted.figure.stand")
            }
            .disabled(appModel.seats.isEmpty)
            .help("Lean on an object with the back, a shoulder, a hand, the hip, or the elbows")

            Menu {
                ForEach(appModel.handHoldPartners) { partner in
                    Button(partner.name, systemImage: partner.recipe.characterKind?.symbol ?? "figure.stand") {
                        appModel.holdHands(with: partner.id)
                    }
                }
            } label: {
                Label("Hold Hands", systemImage: "figure.2")
            }
            .disabled(appModel.handHoldPartners.isEmpty)
            .help("Hold hands with another character: the nearest hands meet between you")
            Spacer(minLength: 0)
        }
        Toggle("Walk Between Keyframes", systemImage: "figure.walk", isOn: Binding(
            get: { appModel.selectedCharacterWalks }, set: { appModel.selectedCharacterWalks = $0 }))
            .font(.callout)
            .help("When this character moves from one keyframe's spot to the next, it walks there, facing the way it goes")
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }
}

/// Presets, saved poses, mirroring, and saving the current pose.
private struct PosesMenu: View {
    @Environment(AppModel.self) private var appModel
    @State private var isNamingPose = false
    @State private var poseName = ""

    var body: some View {
        Menu {
            Section("Start From") {
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
            Section {
                Button("Mirror Pose", systemImage: "arrow.left.and.right.righttriangle.left.righttriangle.right") {
                    appModel.mirrorPose()
                }
                Button("Save Pose…", systemImage: "square.and.arrow.down") {
                    poseName = ""
                    isNamingPose = true
                }
                if !appModel.savedPoses.isEmpty {
                    Menu("Delete Saved Pose", systemImage: "trash") {
                        ForEach(appModel.savedPoses) { saved in
                            Button(saved.name, role: .destructive) { appModel.deleteSavedPose(saved) }
                        }
                    }
                }
            }
        } label: {
            Label("Poses", systemImage: "figure.dance")
        }
        .help("Presets, your saved poses, mirror, and save")
        .alert("Save Pose", isPresented: $isNamingPose) {
            TextField("Name", text: $poseName)
            Button("Save") { appModel.saveCurrentPose(named: poseName) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Saved poses can be used on any character, in any project.")
        }
    }
}

/// The character being posed, with a menu to switch to another one in the scene.
private struct CharacterPicker: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        let characters = appModel.characters
        Menu {
            ForEach(characters) { character in
                Button(character.name, systemImage: character.recipe.characterKind?.symbol ?? "figure.stand") {
                    appModel.selectObject(character.id)
                }
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: appModel.selectedObject?.recipe.characterKind?.symbol ?? "figure.stand")
                VStack(alignment: .leading, spacing: 1) {
                    if appModel.isSelectedObjectCharacter, let character = appModel.selectedObject {
                        Text(character.name).font(.callout.weight(.semibold))
                        Text(appModel.selectedJoint?.displayName ?? "Drag any body part")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if characters.isEmpty {
                        Text("No characters yet").font(.callout.weight(.semibold))
                        Text("Add one from the Objects tab").font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text("Choose a character").font(.callout.weight(.semibold))
                    }
                }
                .lineLimit(1)
                if characters.count > 1 || !appModel.isSelectedObjectCharacter && !characters.isEmpty {
                    Image(systemName: "chevron.up.chevron.down").font(.caption2).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 8)
            .frame(minWidth: 170, alignment: .leading)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .disabled(characters.isEmpty)
        .labelStyle(.titleAndIcon)
    }
}

/// Look at the figure from the front, side, or back. Only the view turns.
private struct ViewAngleButtons: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        HStack(spacing: 4) {
            Button("Front", systemImage: "person.fill") { appModel.poseStudio.viewAngle = 0 }
                .help("Front view")
            Button("Side", systemImage: "person.fill.turn.right") { appModel.poseStudio.viewAngle = -.pi / 2 }
                .help("Side view")
            Button("Back", systemImage: "person.fill.turn.down") { appModel.poseStudio.viewAngle = .pi }
                .help("Back view")
        }
    }
}

/// Every joint grouped by body region, as large tap targets.
private struct BodyPartPicker: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Joint.Region.allCases) { region in
                Text(region.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, region == .body ? 0 : 2)
                HStack(spacing: 6) {
                    ForEach(region.joints) { joint in
                        let isSelected = joint == appModel.selectedJoint
                        let isPosed = !(appModel.selectedCharacterPose?[joint].isZero ?? true)
                        Button {
                            appModel.selectJoint(isSelected ? nil : joint)
                        } label: {
                            Text(shortName(joint))
                                .font(.callout.weight(isSelected || isPosed ? .semibold : .regular))
                                .lineLimit(1)
                                .fixedSize()
                                .foregroundStyle(isSelected ? AnyShapeStyle(.white) : isPosed ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(isSelected ? AnyShapeStyle(Color(uiColor: PoseStudioScene.highlightColor).opacity(0.75))
                                                       : AnyShapeStyle(.white.opacity(isPosed ? 0.14 : 0.06)),
                                            in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .hoverEffect()
                        .accessibilityLabel(joint.displayName)
                        .accessibilityValue(isPosed ? "Posed" : "Straight")
                        .accessibilityAddTraits(isSelected ? .isSelected : [])
                    }
                }
            }
        }
    }

    /// The joint's name without its side, since the row already says which side.
    private func shortName(_ joint: Joint) -> String {
        joint.displayName.replacingOccurrences(of: "Left ", with: "").replacingOccurrences(of: "Right ", with: "")
    }
}

/// Exact angles for the selected joint; for a hand or foot, also where it is and which way
/// the elbow or knee points.
private struct JointEditor: View {
    @Environment(AppModel.self) private var appModel
    let joint: Joint

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(joint.displayName)
                    .font(.headline)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Button("Reset \(joint.displayName)", systemImage: "arrow.counterclockwise") { appModel.resetJoint(joint) }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(.orange)
                    .lineLimit(1)
                    .disabled(appModel.selectedCharacterPose?[joint].isZero ?? true)
                    .help("Straighten just this body part")
            }

            ForEach(joint.axes) { axis in
                AngleRow(joint: joint, axis: axis)
            }

            if let hand = Hand.allCases.first(where: { $0.wrist == joint }) {
                Picker("Hand Shape", selection: Binding(
                    get: { appModel.selectedCharacterPose?[hand] ?? .relaxed },
                    set: { appModel.setHandShape($0, for: hand) })) {
                    ForEach(HandShape.allCases) { shape in
                        Label(shape.name, systemImage: shape.symbol).tag(shape)
                    }
                }
                .pickerStyle(.menu)
            }

            if let limb = Limb(end: joint) {
                Divider()
                LimbControls(limb: limb)
            }
        }
        .padding(14)
        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: UI.smallCorner, style: .continuous))
    }
}

/// One rotation axis: a slider within the joint's limits, the exact angle, and fine steps.
private struct AngleRow: View {
    @Environment(AppModel.self) private var appModel
    let joint: Joint
    let axis: JointAxis

    var body: some View {
        let value = appModel.selectedCharacterPose?[joint][axis] ?? 0
        let range = joint.limits.range(for: axis)

        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(joint.label(for: axis)).font(.callout)
                Spacer()
                Text("\(Int(value.rounded()))°")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                Button("Less", systemImage: "minus") { appModel.nudgeJoint(joint, axis: axis, by: -5) }
                    .disabled(value <= range.lowerBound)
                Slider(value: Binding(get: { Double(value) },
                                      set: { appModel.setJointAngle(Float($0), axis: axis, of: joint) }),
                       in: Double(range.lowerBound)...Double(range.upperBound), step: 1) { editing in
                    editing ? appModel.beginPoseChange() : appModel.endPoseChange()
                }
                .accessibilityLabel("\(joint.displayName) \(joint.label(for: axis))")
                .accessibilityValue("\(Int(value.rounded())) degrees")
                Button("More", systemImage: "plus") { appModel.nudgeJoint(joint, axis: axis, by: 5) }
                    .disabled(value >= range.upperBound)
            }
            .labelStyle(.iconOnly)
            .buttonBorderShape(.circle)
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }
}

/// Where the hand or foot is, relative to its shoulder or hip, at life size, and which way
/// the elbow or knee points. Changing either bends the limb to match.
private struct LimbControls: View {
    @Environment(AppModel.self) private var appModel
    let limb: Limb

    var body: some View {
        if let reach = appModel.reach(of: limb) {
            VStack(alignment: .leading, spacing: 8) {
                let bend = appModel.bendDirection(of: limb) ?? 0
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text("\(limb.middleName) Points").font(.callout)
                        Spacer()
                        Text(bend > 1 ? "\(Int(bend.rounded()))° out" : bend < -1 ? "\(Int(-bend.rounded()))° in" : "Natural")
                            .font(.callout.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: Binding(get: { Double(bend) }, set: { appModel.setBendDirection(Float($0), of: limb) }),
                           in: -90...90, step: 1) { editing in
                        editing ? appModel.beginPoseChange() : appModel.endPoseChange()
                    }
                    .accessibilityLabel("\(limb.middleName) direction")
                }

                Text("\(limb.isArm ? "Hand" : "Foot") Position").font(.callout)
                reachRow("Forward", value: reach.z, range: limb.isArm ? -0.45...0.6 : -0.6...0.8) { $0.z = $1 }
                reachRow("Up", value: reach.y, range: limb.isArm ? -0.6...0.6 : -0.95...0.1) { $0.y = $1 }
                reachRow("Out", value: reach.x, range: -0.3...0.6) { $0.x = $1 }
            }
        }
    }

    private func reachRow(_ title: String, value: Float, range: ClosedRange<Float>,
                          update: @escaping (inout SIMD3<Float>, Float) -> Void) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 56, alignment: .leading)
            Slider(value: Binding(get: { Double(value) }, set: { newValue in
                guard var reach = appModel.reach(of: limb) else { return }
                update(&reach, Float(newValue))
                appModel.setReach(reach, of: limb)
            }), in: Double(range.lowerBound)...Double(range.upperBound), step: 0.01) { editing in
                editing ? appModel.beginPoseChange() : appModel.endPoseChange()
            }
            .accessibilityLabel("\(limb.isArm ? "Hand" : "Foot") \(title.lowercased())")
            Text("\(Int((value * 100).rounded())) cm")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 50, alignment: .trailing)
        }
    }
}
