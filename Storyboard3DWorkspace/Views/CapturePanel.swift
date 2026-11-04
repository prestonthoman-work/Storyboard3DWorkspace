//
//  CapturePanel.swift
//  Storyboard3DWorkspace
//

import SwiftUI

struct CapturePanel: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        @Bindable var appModel = appModel

        VStack(alignment: .leading, spacing: 16) {
            preview

            Picker("Lens", selection: $appModel.captureLens) {
                ForEach(CaptureLens.allCases) { lens in
                    Text(lens.label).tag(lens)
                }
            }
            .pickerStyle(.segmented)
            .disabled(appModel.captureCountdown != nil)

            HStack(spacing: 12) {
                if let remaining = appModel.captureCountdown {
                    Button("Cancel (\(remaining))", systemImage: "xmark") {
                        appModel.cancelCapture()
                    }
                } else {
                    Button {
                        appModel.startCapture()
                    } label: {
                        Label("Capture", systemImage: "camera.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!appModel.canCapture)
                }

                if let capture = appModel.lastCapture, appModel.captureCountdown == nil {
                    Button {
                        Task { await appModel.saveCaptureToPhotos() }
                    } label: {
                        Label("Save to Photos", systemImage: "square.and.arrow.down")
                    }
                    .disabled(appModel.isSavingCapture)

                    let image = Image(uiImage: capture)
                    ShareLink(item: image, preview: SharePreview("Storyboard frame", image: image)) {
                        Label("Share", systemImage: "square.and.arrow.up")
                            .labelStyle(.iconOnly)
                    }
                }
            }
            .buttonStyle(.bordered)

            status

            Spacer(minLength: 0)

            Text("Line up your shot inside the frame in your view. Capture starts a 3-second timer so you can look back at your scene; it renders exactly what's in the frame, without your room or these controls.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var preview: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16)
                .fill(.quaternary)

            if let capture = appModel.lastCapture {
                Image(uiImage: capture)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else if !appModel.isCapturing {
                Text("Walk to the angle you like and line it up in the frame.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding()
            }

            if appModel.isCapturing {
                ProgressView()
            }
        }
        .aspectRatio(16 / 9, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    @ViewBuilder
    private var status: some View {
        switch appModel.captureStatus {
        case .saved:
            Label("Saved to Photos", systemImage: "checkmark.circle.fill")
                .font(.callout)
                .foregroundStyle(.green)
        case .failed(let message):
            Text(message)
                .font(.callout)
                .foregroundStyle(.red)
        case nil:
            EmptyView()
        }
    }
}
