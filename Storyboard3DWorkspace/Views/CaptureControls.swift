//
//  CaptureControls.swift
//  Storyboard3DWorkspace
//

import SwiftUI

/// Lighting, camera (lens, format, film grade), and the shutter button, shared by the
/// Animate and Capture tabs.
/// While the self-timer runs, the shutter becomes a Cancel button showing the count.
struct CaptureControls: View {
    @Environment(AppModel.self) private var appModel
    var shutterTitle = "Capture"
    let shutter: () -> Void

    var body: some View {
        @Bindable var appModel = appModel

        HStack(spacing: 12) {
            Menu {
                Picker("Lighting", selection: $appModel.captureLighting) {
                    ForEach(LightingPreset.allCases) { preset in
                        Label(preset.name, systemImage: preset.symbol).tag(preset)
                    }
                }
                Toggle("Preview in Your Space", systemImage: "eye", isOn: $appModel.isLightingPreviewOn)
            } label: {
                Label(appModel.captureLighting.name, systemImage: appModel.captureLighting.symbol)
            }
            .disabled(appModel.captureCountdown != nil)
            .help("Lighting for the captured photo")

            Menu {
                Picker("Lens", selection: $appModel.captureLens) {
                    ForEach(CaptureLens.allCases) { lens in
                        Text(lens.label).tag(lens)
                    }
                }
                Picker("Format", selection: $appModel.captureLook.format) {
                    ForEach(FrameFormat.allCases) { format in
                        Text("\(format.name)  \(format.label)").tag(format)
                    }
                }
                Toggle("Film Grade", systemImage: "film", isOn: $appModel.captureLook.isFilmGraded)
            } label: {
                Label("\(appModel.captureLens.label) · \(appModel.captureLook.format.label)", systemImage: "camera.aperture")
                    .monospacedDigit()
            }
            .disabled(appModel.captureCountdown != nil)
            .help("Lens, frame format, and film grade")

            Spacer(minLength: 0)

            if let remaining = appModel.captureCountdown {
                Button("Cancel (\(remaining))", systemImage: "xmark") {
                    appModel.cancelCapture()
                }
                .buttonStyle(.bordered)
            } else {
                Button(action: shutter) {
                    Label(shutterTitle, systemImage: "camera.fill")
                        .symbolEffect(.bounce, value: appModel.photos.photos.count)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!appModel.canCapture)
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }
        }
        .animation(.snappy, value: appModel.captureCountdown == nil)
    }
}

/// The result of the last capture attempt, or an error.
struct CaptureStatusLine: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        ZStack(alignment: .leading) {
            status
                .id(appModel.captureStatus)
                .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity),
                                        removal: .opacity))
        }
        .animation(.snappy, value: appModel.captureStatus)
    }

    @ViewBuilder
    private var status: some View {
        switch appModel.captureStatus {
        case .attached(let number):
            Label("Added to keyframe \(number).", systemImage: "checkmark.circle.fill")
                .font(.callout)
                .foregroundStyle(.green)
        case .retaken(let number):
            Label("Retook the photo for keyframe \(number) from the same angle.", systemImage: "checkmark.circle.fill")
                .font(.callout)
                .foregroundStyle(.green)
        case .libraryOnly:
            Label("Saved to the library. It isn't attached to a keyframe.", systemImage: "photo.on.rectangle")
                .font(.callout)
                .foregroundStyle(.secondary)
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
