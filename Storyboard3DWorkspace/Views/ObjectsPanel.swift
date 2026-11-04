//
//  ObjectsPanel.swift
//  Storyboard3DWorkspace
//

import SwiftUI

struct ObjectsPanel: View {
    @Environment(AppModel.self) private var appModel
    @State private var renaming: AppModel.ObjectSummary?
    @State private var newName = ""

    var body: some View {
        @Bindable var appModel = appModel

        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    TextField("Describe an object, e.g. red house", text: $appModel.objectPrompt)
                        .textFieldStyle(.roundedBorder)
                        .submitLabel(.go)
                        .onSubmit(generate)
                    Button(action: generate) {
                        if appModel.isGeneratingObject {
                            ProgressView()
                        } else {
                            Label("Generate", systemImage: "sparkles")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!appModel.canGenerateObject)
                    .help("Add a new object to the base")

                    if appModel.selectedObject != nil {
                        Button("Replace") {
                            Task { await appModel.replaceSelectedObject() }
                        }
                        .buttonStyle(.bordered)
                        .disabled(!appModel.canGenerateObject)
                        .help("Replace the selected object with this prompt, keeping its place and keyframes")
                    }
                }
                if let error = appModel.objectError {
                    Text(error).font(.callout).foregroundStyle(.red)
                } else if let note = appModel.objectNote {
                    Text(note).font(.callout).foregroundStyle(.secondary)
                }
            }

            if appModel.objects.isEmpty {
                Text("Generate objects one at a time, like houses, trees, and shrubs, and arrange them on the base.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                objectList
                selectionActions
            }

            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 6) {
                Text("Pinch and drag an object to move it. Turn your hand to rotate. Use both hands to resize.")
                if appModel.isSampleMode {
                    Label("Sample mode: no AI service is set up, so prompts are matched to built-in objects.",
                          systemImage: "info.circle")
                }
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        .alert("Rename Object", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $newName)
            Button("Rename") {
                if let renaming { appModel.renameObject(renaming.id, to: newName) }
                renaming = nil
            }
            Button("Cancel", role: .cancel) { renaming = nil }
        }
    }

    private var objectList: some View {
        ScrollView {
            VStack(spacing: 4) {
                ForEach(appModel.objects) { object in
                    let isSelected = object.id == appModel.selectedObjectID
                    Button {
                        appModel.selectObject(object.id)
                    } label: {
                        HStack {
                            Text(object.name)
                            Spacer()
                            Text(appModel.keyframeMembership(of: object.id))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(isSelected ? AnyShapeStyle(.selection) : AnyShapeStyle(.clear),
                                    in: RoundedRectangle(cornerRadius: 12))
                        .contentShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                    .hoverEffect()
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
        }
        .frame(maxHeight: 150)
    }

    @ViewBuilder
    private var selectionActions: some View {
        if let selected = appModel.selectedObject {
            VStack(alignment: .leading, spacing: 12) {
                if appModel.canRecolorSelectedObject {
                    ColorSwatches(selected: selected.recipe.colorName) { appModel.recolorSelectedObject($0) }
                }
                HStack(spacing: 12) {
                    Button("Rename", systemImage: "pencil") {
                        newName = selected.name
                        renaming = selected
                    }
                    Button("Duplicate", systemImage: "plus.square.on.square") {
                        appModel.duplicateSelectedObject()
                    }
                    Button("Delete", systemImage: "trash", role: .destructive) {
                        appModel.deleteSelectedObject()
                    }
                }
                .buttonStyle(.bordered)
            }
        } else {
            Text("Select an object to recolor, replace, rename, duplicate, or delete it.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private func generate() {
        Task { await appModel.generateObject() }
    }
}

/// A row of color choices for the selected object. The first swatch restores its
/// original colors.
private struct ColorSwatches: View {
    let selected: String?
    let choose: (String?) -> Void

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                swatch(nil, fill: AnyShapeStyle(.quaternary), label: "Original colors")
                    .overlay { Image(systemName: "arrow.uturn.backward").font(.caption2).allowsHitTesting(false) }
                ForEach(SampleObjectCatalog.colorNames, id: \.self) { name in
                    swatch(name, fill: AnyShapeStyle(Color(uiColor: SampleObjectCatalog.color(named: name) ?? .gray)),
                           label: name.capitalized)
                }
            }
            .padding(4)
        }
        .scrollIndicators(.hidden)
    }

    private func swatch(_ name: String?, fill: AnyShapeStyle, label: String) -> some View {
        Button {
            choose(name)
        } label: {
            Circle()
                .fill(fill)
                .frame(width: 30, height: 30)
                .overlay {
                    Circle().strokeBorder(.white, lineWidth: selected == name ? 3 : 0)
                }
        }
        .buttonStyle(.plain)
        .hoverEffect()
        .accessibilityLabel(label)
        .accessibilityAddTraits(selected == name ? .isSelected : [])
        .help(label)
    }
}
