//
//  BackgroundPanel.swift
//  Storyboard3DWorkspace
//

import PhotosUI
import SwiftUI

struct BackgroundPanel: View {
    @Environment(AppModel.self) private var appModel

    @State private var photoSelection: PhotosPickerItem?
    @State private var isImportingFile = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            preview

            HStack(spacing: 12) {
                Button {
                    Task { await appModel.useBuiltInSky() }
                } label: {
                    Label("Sky", systemImage: "cloud.sun")
                }

                PhotosPicker(selection: $photoSelection, matching: .images) {
                    Label("Photos", systemImage: "photo.on.rectangle")
                }

                Button {
                    isImportingFile = true
                } label: {
                    Label("Files", systemImage: "folder")
                }
            }
            .buttonStyle(.bordered)
            .disabled(appModel.isLoadingBackground)

            if let error = appModel.backgroundError {
                Text(error)
                    .font(.callout)
                    .foregroundStyle(.red)
            }

            Spacer(minLength: 0)

            Text("The backdrop turns to face you and stays behind the model as you walk around it.")
                .font(.footnote)
                .foregroundStyle(.secondary)
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
        VStack(alignment: .leading, spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(.quaternary)

                if let background = appModel.background {
                    Image(uiImage: background.preview)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                }

                if appModel.isLoadingBackground {
                    ProgressView()
                }
            }
            .frame(height: 170)
            .clipShape(RoundedRectangle(cornerRadius: 16))

            if let background = appModel.background {
                HStack(alignment: .firstTextBaseline) {
                    Text(background.name)
                        .font(.headline)
                        .lineLimit(1)
                    Spacer()
                    Text(background.source.label)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
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
    BackgroundPanel()
        .environment(AppModel())
        .padding()
        .frame(width: 460, height: 500)
}
