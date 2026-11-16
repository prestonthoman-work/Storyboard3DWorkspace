//
//  ObjectToolbar.swift
//  Storyboard3DWorkspace
//

import SwiftUI

/// Floats above the selected object in the scene, so common edits don't need a trip
/// back to the panel: duplicate, recolor, delete, and deselect.
struct ObjectToolbar: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.openWindow) private var openWindow
    @State private var isShowingColors = false

    var body: some View {
        if let selected = appModel.selectedObject {
            VStack(spacing: 8) {
                if isShowingColors {
                    colorRow(selected: selected.recipe.colorName)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                HStack(spacing: 4) {
                    Text(selected.name)
                        .font(.callout.weight(.semibold))
                        .lineLimit(1)
                        .padding(.horizontal, 10)

                    if appModel.isSelectedObjectCharacter {
                        let isPosing = appModel.characterEditMode == .pose
                        Button(isPosing ? "Done Posing" : "Pose", systemImage: isPosing ? "checkmark" : "figure.walk.motion") {
                            withAnimation(.snappy) { appModel.setCharacterEditMode(isPosing ? .move : .pose) }
                        }
                        .help(isPosing ? "Back to moving the whole character" : "Pose this character's body")
                        if isPosing && !appModel.isPoseStudioOpen {
                            Button("Pose Studio", systemImage: "rectangle.3.group.bubble") {
                                openWindow(id: PoseStudioView.windowID)
                            }
                            .help("Pose this character at a large size in its own window")
                        }
                        if isPosing, let joint = appModel.selectedJoint {
                            Text(joint.displayName)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .padding(.horizontal, 6)
                        }
                    }
                    Button("Duplicate", systemImage: "plus.square.on.square") {
                        appModel.duplicateSelectedObject()
                    }
                    if appModel.canRecolorSelectedObject && appModel.characterEditMode == .move {
                        Button("Color", systemImage: "paintpalette") {
                            withAnimation(.snappy) { isShowingColors.toggle() }
                        }
                        .symbolVariant(isShowingColors ? .fill : .none)
                    }
                    Button("Delete", systemImage: "trash", role: .destructive) {
                        appModel.deleteSelectedObject()
                    }
                    Button("Done", systemImage: "xmark") {
                        appModel.selectObject(nil)
                    }
                }
                .labelStyle(.iconOnly)
                .buttonBorderShape(.circle)
                .padding(6)
                .glassBackgroundEffect(in: Capsule())
            }
            .onChange(of: appModel.selectedObjectID) { isShowingColors = false }
        }
    }

    private func colorRow(selected: String?) -> some View {
        HStack(spacing: 6) {
            swatch(nil, color: nil, isSelected: selected == nil)
            ForEach(SampleObjectCatalog.colorNames, id: \.self) { name in
                swatch(name, color: SampleObjectCatalog.color(named: name).map(Color.init(uiColor:)), isSelected: selected == name)
            }
        }
        .padding(8)
        .glassBackgroundEffect(in: Capsule())
    }

    private func swatch(_ name: String?, color: Color?, isSelected: Bool) -> some View {
        Button {
            appModel.recolorSelectedObject(name)
        } label: {
            Circle()
                .fill(color.map(AnyShapeStyle.init) ?? AnyShapeStyle(.quaternary))
                .frame(width: 26, height: 26)
                .overlay {
                    if name == nil { Image(systemName: "arrow.uturn.backward").font(.caption2) }
                }
                .overlay { Circle().strokeBorder(.white, lineWidth: isSelected ? 2.5 : 0) }
        }
        .buttonStyle(.plain)
        .hoverEffect()
        .accessibilityLabel(name?.capitalized ?? "Original colors")
    }
}
