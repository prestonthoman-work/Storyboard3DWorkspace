//
//  SetPanel.swift
//  Storyboard3DWorkspace
//

import PhotosUI
import SwiftUI

/// Everything that frames the scene: where the base sits, what it's made of, how big it
/// is, and the backdrop behind it.
struct SetPanel: View {
    var body: some View {
        PanelScroll {
            TableStatusCard()
            SurfaceSection()
            SizeSection()
            BackdropSection()
        }
    }
}

// MARK: - Table

/// Where the base is: on a table (green), searching, or floating, with a way to fix it.
private struct TableStatusCard: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(tint.opacity(0.18))
                    .frame(width: 40, height: 40)
                Image(systemName: symbol)
                    .font(.title3)
                    .foregroundStyle(tint)
                    .symbolEffect(.pulse, isActive: appModel.tablePlacement == .searching)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                if let detail {
                    Text(detail)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 8)

            if appModel.canFindTable {
                Button("Find Table", systemImage: "scope") { appModel.findTable() }
                    .buttonStyle(.bordered)
                    .help("Move the base to the table nearest you")
            }
        }
        .padding(UI.sectionPadding)
        .platter()
    }

    private var symbol: String {
        switch appModel.tablePlacement {
        case .searching: "magnifyingglass"
        case .onTable: "checkmark"
        case .floating: "rectangle.dashed"
        }
    }

    private var tint: Color {
        switch appModel.tablePlacement {
        case .onTable: .green
        case .searching: .blue
        case .floating: .orange
        }
    }

    private var title: String {
        switch appModel.tablePlacement {
        case .searching: "Looking for a table…"
        case .onTable: "On your table"
        case .floating: "Not on a table"
        }
    }

    private var detail: String? {
        switch appModel.tablePlacement {
        case .floating(let reason): reason
        default: nil
        }
    }
}

// MARK: - Surface

private struct SurfaceSection: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        @Bindable var appModel = appModel

        PanelSection("Surface", symbol: "square.3.layers.3d") {
            HStack(spacing: 10) {
                ForEach(BaseTemplate.allCases) { template in
                    TemplateTile(template: template,
                                 isSelected: appModel.base.origin == .template(template)) {
                        appModel.applyBaseTemplate(template)
                    }
                }
            }

            PromptField(placeholder: "Or describe one, like desert dunes",
                        text: $appModel.basePrompt,
                        isWorking: appModel.isGeneratingBase,
                        canSubmit: appModel.canGenerateBase) {
                Task { await appModel.generateBase() }
            }

            if let error = appModel.baseError {
                StatusMessage(error, kind: .error)
            } else if let note = appModel.baseNote {
                StatusMessage(note)
            }
        }
    }
}

private struct TemplateTile: View {
    let template: BaseTemplate
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                RoundedRectangle(cornerRadius: UI.smallCorner, style: .continuous)
                    .fill(template.swatch)
                    .frame(height: 64)
                    .overlay {
                        Image(systemName: template.symbol)
                            .font(.title3)
                            .foregroundStyle(.white.opacity(0.9))
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: UI.smallCorner, style: .continuous)
                            .strokeBorder(.white, lineWidth: isSelected ? 3 : 0)
                    }
                Text(template.name)
                    .font(.caption.weight(isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? .primary : .secondary)
            }
            .frame(maxWidth: .infinity)
            .contentShape(RoundedRectangle(cornerRadius: UI.smallCorner))
        }
        .buttonStyle(.plain)
        .hoverEffect()
        .accessibilityLabel("\(template.name) base")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Size

private struct SizeSection: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        @Bindable var appModel = appModel

        PanelSection("Size", symbol: "arrow.left.and.right.circle") {
            Text("\(Int(appModel.baseWidth)) cm across")
                .monospacedDigit()
                .foregroundStyle(.secondary)
        } content: {
            HStack(spacing: 14) {
                Slider(value: $appModel.baseWidth, in: BaseSizeLimits.range, step: BaseSizeLimits.step) {
                    Text("Base diameter")
                } minimumValueLabel: {
                    Image(systemName: "circle").font(.caption2)
                } maximumValueLabel: {
                    Image(systemName: "circle").font(.body)
                } onEditingChanged: { isEditing in
                    if isEditing { appModel.beginBaseResize() }
                }
                .foregroundStyle(.secondary)
                .accessibilityValue("\(Int(appModel.baseWidth)) centimeters across")

                if appModel.tablePlacement == .onTable {
                    Button("Fit Table") { appModel.fitBaseToTable() }
                        .buttonStyle(.bordered)
                        .help("Size the base to fit the table")
                }
            }
        }
    }
}

// MARK: - Backdrop

/// The image behind the scene: a preview, and where to get a new one.
private struct BackdropSection: View {
    @Environment(AppModel.self) private var appModel

    @State private var photoSelection: PhotosPickerItem?
    @State private var isImportingFile = false

    var body: some View {
        PanelSection("Backdrop", symbol: "photo") {
            preview

            HStack(spacing: 10) {
                Button {
                    Task { await appModel.useBuiltInSky() }
                } label: {
                    Label("Sky", systemImage: "cloud.sun")
                        .frame(maxWidth: .infinity)
                }

                PhotosPicker(selection: $photoSelection, matching: .images) {
                    Label("Photos", systemImage: "photo.on.rectangle")
                        .frame(maxWidth: .infinity)
                }

                Button {
                    isImportingFile = true
                } label: {
                    Label("Files", systemImage: "folder")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.bordered)
            .disabled(appModel.isLoadingBackground)

            if let error = appModel.backgroundError {
                StatusMessage(error, kind: .error)
            }
        }
        .onChange(of: photoSelection) { _, item in
            guard let item else { return }
            Task { await importPhoto(item) }
        }
        .fileImporter(isPresented: $isImportingFile, allowedContentTypes: [.image]) { result in
            switch result {
            case .success(let url):
                Task { await appModel.importBackground(fileAt: url) }
            case .failure(let error):
                appModel.reportBackgroundError(error.localizedDescription)
            }
        }
    }

    private var preview: some View {
        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: UI.smallCorner, style: .continuous)
                .fill(.quaternary)

            if let background = appModel.background {
                Image(uiImage: background.preview)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .transition(.opacity)

                LinearGradient(colors: [.clear, .black.opacity(0.6)], startPoint: .center, endPoint: .bottom)

                HStack(alignment: .firstTextBaseline) {
                    Text(background.name)
                        .font(.headline)
                        .lineLimit(1)
                    Spacer()
                    Text(background.source.label)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.75))
                }
                .foregroundStyle(.white)
                .padding(14)
            }

            if appModel.isLoadingBackground {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(height: 150)
        .clipShape(RoundedRectangle(cornerRadius: UI.smallCorner, style: .continuous))
        .animation(.smooth, value: appModel.background?.name)
    }

    private func importPhoto(_ item: PhotosPickerItem) async {
        defer { photoSelection = nil }
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                appModel.reportBackgroundError("That photo couldn't be loaded.")
                return
            }
            await appModel.importBackground(data: data, name: "Photo", source: .photos)
        } catch {
            appModel.reportBackgroundError("That photo couldn't be loaded.")
        }
    }
}

#Preview(windowStyle: .automatic) {
    SetPanel()
        .environment(AppModel())
        .padding()
        .frame(width: UI.panelSize.width, height: UI.panelSize.height)
}
