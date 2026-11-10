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

        VStack(alignment: .leading, spacing: UI.sectionSpacing) {
            PanelScroll {
                    PanelSection("Add", symbol: "plus.square.on.square") {
                        if appModel.isSampleMode {
                            Badge(text: "Sample objects", symbol: "shippingbox")
                                .help("No AI service is set up, so prompts are matched to built-in objects.")
                        }
                    } content: {
                        CatalogTray()
                        PromptField(placeholder: "Or describe one, like a red house",
                                    text: $appModel.objectPrompt,
                                    isWorking: appModel.isGeneratingObject,
                                    canSubmit: appModel.canGenerateObject) {
                            Task { await appModel.generateObject() }
                        }
                        if let error = appModel.objectError {
                            StatusMessage(error, kind: .error)
                        } else if let note = appModel.objectNote {
                            StatusMessage(note)
                        }
                    }

                    PanelSection("In Scene", symbol: "cube") {
                        if !appModel.objects.isEmpty {
                            Text("\(appModel.objects.count)").monospacedDigit().foregroundStyle(.secondary)
                        }
                    } content: {
                        if appModel.objects.isEmpty {
                            Text("Nothing here yet. Tap a card above to add your first object.")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        } else {
                            objectList
                        }
                    }
            }

            HintRow(hints: [
                ("hand.pinch", "Pinch and drag an object to move it"),
                ("arrow.trianglehead.clockwise", "Drag the ring's knob to turn it, or the corner to resize"),
            ])
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
        VStack(spacing: 6) {
            ForEach(appModel.objects) { object in
                let isSelected = object.id == appModel.selectedObjectID

                VStack(alignment: .leading, spacing: 0) {
                    Button {
                        withAnimation(.snappy) {
                            appModel.selectObject(isSelected ? nil : object.id)
                        }
                    } label: {
                        HStack(spacing: 12) {
                            ObjectThumbnail(object: object, isSelected: isSelected)
                            Text(object.name)
                                .lineLimit(1)
                            Spacer(minLength: 8)
                            Text(appModel.keyframeMembership(of: object.id))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            Image(systemName: "chevron.down")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                                .rotationEffect(.degrees(isSelected ? 180 : 0))
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 11)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .hoverEffect()
                    .accessibilityAddTraits(isSelected ? .isSelected : [])

                    if isSelected {
                        selectedActions(for: object)
                            .padding(.horizontal, 14)
                            .padding(.bottom, 14)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
                .background(isSelected ? AnyShapeStyle(.white.opacity(0.08)) : AnyShapeStyle(.clear),
                            in: RoundedRectangle(cornerRadius: UI.smallCorner, style: .continuous))
                .clipShape(RoundedRectangle(cornerRadius: UI.smallCorner, style: .continuous))
            }
        }
    }

    /// Edits for the selected object, right under its row.
    private func selectedActions(for object: AppModel.ObjectSummary) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if appModel.canRecolorSelectedObject {
                ColorSwatches(selected: object.recipe.colorName) { appModel.recolorSelectedObject($0) }
            }

            ViewThatFits(in: .horizontal) {
                actionButtons(for: object).labelStyle(.titleAndIcon)
                actionButtons(for: object).labelStyle(.iconOnly)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    private func actionButtons(for object: AppModel.ObjectSummary) -> some View {
        HStack(spacing: 8) {
            Button("Rename", systemImage: "pencil") {
                newName = object.name
                renaming = object
            }
            Button("Duplicate", systemImage: "plus.square.on.square") {
                appModel.duplicateSelectedObject()
            }
            Button("Replace", systemImage: "arrow.triangle.2.circlepath") {
                Task { await appModel.replaceSelectedObject() }
            }
            .disabled(!appModel.canGenerateObject)
            .help("Type a description above, then replace this object with it. It keeps its place and keyframes.")
            Spacer(minLength: 0)
            Button("Delete", systemImage: "trash", role: .destructive) {
                appModel.deleteSelectedObject()
            }
        }
    }
}

/// The object's library render, or a cube for generated ones.
private struct ObjectThumbnail: View {
    @Environment(AppModel.self) private var appModel
    let object: AppModel.ObjectSummary
    let isSelected: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(.white.opacity(isSelected ? 0.16 : 0.08))
            if let kind = object.recipe.catalogKind, let image = appModel.catalogThumbnails.images[kind] {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .padding(3)
            } else {
                Image(systemName: isSelected ? "cube.fill" : "cube")
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
            }
        }
        .frame(width: 34, height: 34)
        .onAppear { appModel.catalogThumbnails.loadIfNeeded() }
    }
}

/// A row of color choices for the selected object. The first swatch restores its
/// original colors.
private struct ColorSwatches: View {
    let selected: String?
    let choose: (String?) -> Void

    var body: some View {
        HorizontalStrip(spacing: 8) {
                swatch(nil, fill: AnyShapeStyle(.quaternary), label: "Original colors")
                    .overlay { Image(systemName: "arrow.uturn.backward").font(.caption2).allowsHitTesting(false) }
                ForEach(SampleObjectCatalog.colorNames, id: \.self) { name in
                    swatch(name, fill: AnyShapeStyle(Color(uiColor: SampleObjectCatalog.color(named: name) ?? .gray)),
                           label: name.capitalized)
                }
        }
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

/// Every built-in object as a card with a studio render. Tap one to place it.
private struct CatalogTray: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HorizontalStrip {
                ForEach(SampleObjectCatalog.Kind.allCases, id: \.self) { kind in
                    CatalogCard(kind: kind, image: appModel.catalogThumbnails.images[kind]) {
                        appModel.placeCatalogObject(kind)
                    }
                }
            }
        }
        .onAppear { appModel.catalogThumbnails.loadIfNeeded() }
    }
}

private struct CatalogCard: View {
    let kind: SampleObjectCatalog.Kind
    let image: UIImage?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: UI.smallCorner, style: .continuous)
                        .fill(LinearGradient(colors: [.white.opacity(0.12), .white.opacity(0.03)],
                                             startPoint: .top, endPoint: .bottom))
                    if let image {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .padding(6)
                            .transition(.opacity.combined(with: .scale(scale: 0.9)))
                    } else {
                        ProgressView()
                    }
                }
                .frame(width: 88, height: 88)
                .overlay {
                    RoundedRectangle(cornerRadius: UI.smallCorner, style: .continuous)
                        .strokeBorder(.white.opacity(0.12), lineWidth: 1)
                }
                .animation(.smooth, value: image != nil)

                Text(kind.name)
                    .font(.caption)
                    .lineLimit(1)
                    .frame(width: 88)
            }
            .contentShape(RoundedRectangle(cornerRadius: UI.smallCorner, style: .continuous))
        }
        .buttonStyle(.plain)
        .hoverEffect()
        .accessibilityLabel("Add \(kind.name)")
        .help("Add a \(kind.name.lowercased()) to the base")
    }
}
