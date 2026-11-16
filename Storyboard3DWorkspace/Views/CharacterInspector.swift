//
//  CharacterInspector.swift
//  Storyboard3DWorkspace
//

import SwiftUI

/// Edits for a selected character: staging it in the scene (Move), or posing its body (Pose).
struct CharacterInspector: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Picker("Edit", selection: Binding(get: { appModel.characterEditMode },
                                              set: { mode in withAnimation(.snappy) { appModel.setCharacterEditMode(mode) } })) {
                Label("Move Character", systemImage: "move.3d").tag(AppModel.CharacterEditMode.move)
                Label("Pose Character", systemImage: "figure.walk.motion").tag(AppModel.CharacterEditMode.pose)
            }
            .pickerStyle(.segmented)

            switch appModel.characterEditMode {
            case .move:
                CharacterShapeControls()
            case .pose:
                PoseControls()
            }
        }
    }
}

// MARK: Body shape

private struct CharacterShapeControls: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        if let proportions = appModel.selectedCharacterProportions {
            VStack(alignment: .leading, spacing: 8) {
                Text("Pinch and drag to place the character. Drag the ring's knob to turn it, or the corner to resize.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                proportionSlider("Height", value: proportions.height, range: CharacterProportions.heightRange) { $0.height = $1 }
                proportionSlider("Build", value: proportions.build, range: CharacterProportions.buildRange) { $0.build = $1 }
                proportionSlider("Head", value: proportions.head, range: CharacterProportions.headRange) { $0.head = $1 }
                proportionSlider("Legs", value: proportions.legs, range: CharacterProportions.legsRange) { $0.legs = $1 }
            }
        }
    }

    private func proportionSlider(_ title: String, value: Float, range: ClosedRange<Float>,
                                  update: @escaping (inout CharacterProportions, Float) -> Void) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.callout)
                .frame(width: 64, alignment: .leading)
            Slider(value: Binding(get: { Double(value) }, set: { newValue in
                guard var proportions = appModel.selectedCharacterProportions else { return }
                update(&proportions, Float(newValue))
                appModel.setSelectedCharacterProportions(proportions)
            }), in: Double(range.lowerBound)...Double(range.upperBound), step: 0.01) { editing in
                editing ? appModel.beginProportionsChange() : appModel.endProportionsChange()
            }
            Text("\(Int((value * 100).rounded()))%")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 40, alignment: .trailing)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: Posing

private struct PoseControls: View {
    @Environment(AppModel.self) private var appModel
    @State private var isNamingPose = false
    @State private var poseName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
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
                .help("Start from a ready-made pose, then adjust it")

                Button("Save Pose", systemImage: "square.and.arrow.down") {
                    poseName = ""
                    isNamingPose = true
                }
                .help("Keep this pose to use on any character, in any project")

                if !appModel.savedPoses.isEmpty {
                    Menu {
                        ForEach(appModel.savedPoses) { saved in
                            Button(saved.name, systemImage: "trash", role: .destructive) { appModel.deleteSavedPose(saved) }
                        }
                    } label: {
                        Label("Delete Saved Pose", systemImage: "trash")
                    }
                    .labelStyle(.iconOnly)
                    .help("Delete a saved pose")
                }

                Spacer(minLength: 0)

                Button("Reset Pose", systemImage: "arrow.counterclockwise") { appModel.resetPose() }
                    .disabled(appModel.selectedCharacterPose?.isNeutral ?? true)
                    .help("Stand straight again. The character stays where it is.")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            if let error = appModel.poseLibraryError {
                StatusMessage(error, kind: .error)
            }

            BodyPartPicker()

            if let joint = appModel.selectedJoint {
                JointEditor(joint: joint)
            }

            Button {
                withAnimation(.snappy) { appModel.setCharacterEditMode(.move) }
            } label: {
                Label("Done Posing", systemImage: "checkmark")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .help("Back to placing things in the scene")
        }
        .alert("Save Pose", isPresented: $isNamingPose) {
            TextField("Name", text: $poseName)
            Button("Save") { appModel.saveCurrentPose(named: poseName) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Saved poses can be used on any character, in any project.")
        }
    }
}

/// Every joint, grouped by body region, as large tap targets. Also selectable by tapping
/// the body itself in the scene.
private struct BodyPartPicker: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Tap a body part on the character, or choose one here.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            ForEach(Joint.Region.allCases) { region in
                HStack(spacing: 6) {
                    Text(region.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 82, alignment: .leading)
                    ForEach(region.joints) { joint in
                        let isSelected = joint == appModel.selectedJoint
                        Button {
                            appModel.selectJoint(joint)
                        } label: {
                            Text(shortName(joint))
                                .font(.caption.weight(isSelected ? .semibold : .regular))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(isSelected ? AnyShapeStyle(Color.accentColor.opacity(0.85)) : AnyShapeStyle(.white.opacity(0.08)),
                                            in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .hoverEffect()
                        .accessibilityLabel(joint.displayName)
                        .accessibilityAddTraits(isSelected ? .isSelected : [])
                        .overlay(alignment: .topTrailing) {
                            if !(appModel.selectedCharacterPose?[joint].isZero ?? true) {
                                Circle().fill(.white.opacity(0.7)).frame(width: 5, height: 5).offset(x: -3, y: 3)
                                    .accessibilityHidden(true)
                            }
                        }
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

/// Angles for the selected joint, or placing its hand or foot.
private struct JointEditor: View {
    @Environment(AppModel.self) private var appModel
    let joint: Joint

    var body: some View {
        @Bindable var appModel = appModel
        let limb = Limb(end: joint)

        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(joint.displayName)
                    .font(.headline)
                Spacer()
                Button("Reset", systemImage: "arrow.counterclockwise") { appModel.resetJoint(joint) }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(appModel.selectedCharacterPose?[joint].isZero ?? true)
                    .help("Straighten just this joint")
            }

            if let limb {
                Picker("Tool", selection: $appModel.poseTool) {
                    Text("Rotate Joint").tag(AppModel.PoseTool.rotate)
                    Text("Place \(limb.isArm ? "Hand" : "Foot")").tag(AppModel.PoseTool.reach)
                }
                .pickerStyle(.segmented)
            }

            if let limb, appModel.poseTool == .reach {
                ReachControls(limb: limb)
            } else {
                ForEach(joint.axes) { axis in
                    AngleRow(joint: joint, axis: axis)
                }
            }
        }
        .padding(12)
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
                Text(joint.label(for: axis))
                    .font(.callout)
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

/// Places a hand or foot relative to its shoulder or hip; the arm or leg bends to reach.
/// Distances are at life size, as if the figure were a real person.
private struct ReachControls: View {
    @Environment(AppModel.self) private var appModel
    let limb: Limb

    var body: some View {
        if let reach = appModel.reach(of: limb) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Drag the blue target in the scene, or set the position here. The \(limb.isArm ? "arm" : "leg") bends to reach.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                reachRow("Forward", value: reach.z, range: limb.isArm ? -0.45...0.6 : -0.6...0.8) { $0.z = $1 }
                reachRow("Up", value: reach.y, range: limb.isArm ? -0.6...0.6 : -0.95...0.1) { $0.y = $1 }
                reachRow("Out", value: reach.x, range: -0.3...0.6) { $0.x = $1 }

                let bend = appModel.bendDirection(of: limb) ?? 0
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text("\(limb.middleName) Direction").font(.callout)
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
            }
        }
    }

    private func reachRow(_ title: String, value: Float, range: ClosedRange<Float>,
                          update: @escaping (inout SIMD3<Float>, Float) -> Void) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.callout)
                .frame(width: 64, alignment: .leading)
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
