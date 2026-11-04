//
//  ObjectsPanel.swift
//  Storyboard3DWorkspace
//

import SwiftUI

struct ObjectsPanel: View {
    @Environment(AppModel.self) private var appModel

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
                            Text(object.source.label)
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
        if appModel.selectedObject != nil {
            HStack(spacing: 12) {
                Button("Duplicate", systemImage: "plus.square.on.square") {
                    appModel.duplicateSelectedObject()
                }
                Button("Delete", systemImage: "trash", role: .destructive) {
                    appModel.deleteSelectedObject()
                }
            }
            .buttonStyle(.bordered)
        } else {
            Text("Select an object to duplicate or delete it.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private func generate() {
        Task { await appModel.generateObject() }
    }
}
