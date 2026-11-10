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

        HStack(spacing: 10) {
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
                Button {
                    appModel.cancelCapture()
                } label: {
                    Label("Cancel \(remaining)", systemImage: "xmark")
                        .monospacedDigit()
                        .contentTransition(.numericText(countsDown: true))
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
            StatusMessage("Added to keyframe \(number)", kind: .success)
        case .retaken(let number):
            StatusMessage("Retook keyframe \(number)'s photo from the same angle", kind: .success)
        case .libraryOnly:
            StatusMessage("Saved to the library", symbol: "photo.on.rectangle")
        case .saved:
            StatusMessage("Saved to Photos", kind: .success)
        case .failed(let message):
            StatusMessage(message, kind: .error)
        case nil:
            EmptyView()
        }
    }
}
