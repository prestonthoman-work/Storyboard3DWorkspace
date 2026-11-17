//
//  CaptureControls.swift
//  Storyboard3DWorkspace
//

import SwiftUI

/// Lighting, camera (lens, format, depth of field, film grade), and the shutter button, shared by the
/// Animate and Capture tabs.
/// While the self-timer runs, the shutter becomes a Cancel button showing the count.
struct CaptureControls: View {
    @Environment(AppModel.self) private var appModel
    var shutterTitle = "Capture"
    let shutter: () -> Void
    @State private var isShowingCameraSettings = false

    private var cameraSummary: String {
        var parts = [appModel.captureLens.label, appModel.captureLook.format.label]
        if let depthOfField = appModel.captureLook.depthOfField { parts.append(depthOfField.label) }
        return parts.joined(separator: " · ")
    }

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

            Button {
                isShowingCameraSettings = true
            } label: {
                Label(cameraSummary, systemImage: "camera.aperture")
                    .monospacedDigit()
            }
            .disabled(appModel.captureCountdown != nil)
            .help("Lens, frame shape, depth of field, and film grade")
            .popover(isPresented: $isShowingCameraSettings, arrowEdge: .bottom) {
                CameraSettings()
                    .environment(appModel)
            }

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

/// The capture camera's settings: focal length, frame shape, depth of field, and film grade.
private struct CameraSettings: View {
    @Environment(AppModel.self) private var appModel

    /// The focal-length slider moves on a log scale, so wide lenses (where a few millimeters
    /// matter a lot) get as much room as telephoto ones.
    private var logFocalLength: Binding<Double> {
        Binding {
            log(Double(appModel.captureLens.focalLength))
        } set: { value in
            let lens = CaptureLens(Int(exp(value).rounded()))
            if lens != appModel.captureLens { appModel.captureLens = lens }
        }
    }

    private var isDepthOfFieldOn: Binding<Bool> {
        Binding {
            appModel.captureLook.depthOfField != nil
        } set: { isOn in
            appModel.captureLook.depthOfField = isOn ? DepthOfField() : nil
        }
    }

    var body: some View {
        @Bindable var appModel = appModel

        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Focal Length").font(.headline)
                    Spacer()
                    Text(appModel.captureLens.label)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                }
                Slider(value: logFocalLength,
                       in: log(Double(CaptureLens.range.lowerBound))...log(Double(CaptureLens.range.upperBound)))
                    .accessibilityLabel("Focal length")
                    .accessibilityValue(appModel.captureLens.label)
                HStack(spacing: 6) {
                    ForEach(CaptureLens.presets) { lens in
                        Button("\(lens.focalLength)") { appModel.captureLens = lens }
                            .buttonStyle(.bordered)
                            .tint(lens == appModel.captureLens ? .accentColor : nil)
                            .controlSize(.small)
                            .accessibilityLabel(lens.label)
                    }
                }
            }

            Picker("Frame", selection: $appModel.captureLook.format) {
                ForEach(FrameFormat.allCases) { format in
                    Text("\(format.name)  \(format.label)").tag(format)
                }
            }
            .pickerStyle(.menu)

            VStack(alignment: .leading, spacing: 10) {
                Toggle("Depth of Field", systemImage: "camera.filters", isOn: isDepthOfFieldOn)
                    .font(.headline)
                if let depthOfField = appModel.captureLook.depthOfField {
                    Picker("Aperture", selection: Binding(
                        get: { depthOfField.fStop },
                        set: { appModel.captureLook.depthOfField?.fStop = $0 })) {
                        ForEach(DepthOfField.fStops, id: \.self) { stop in
                            Text(DepthOfField.label(for: stop)).tag(stop)
                        }
                    }
                    .pickerStyle(.menu)
                    Picker("Focus On", selection: Binding(
                        get: { depthOfField.focusObject },
                        set: { appModel.captureLook.depthOfField?.focusObject = $0 })) {
                        Text("Center of Frame").tag(ObjectID?.none)
                        ForEach(appModel.objects) { object in
                            Text(object.name).tag(ObjectID?.some(object.id))
                        }
                    }
                    .pickerStyle(.menu)
                    Text("Shows in photos and slideshows, not in the viewfinder. The animatic stays sharp so it exports quickly.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Toggle("Film Grade", systemImage: "film", isOn: $appModel.captureLook.isFilmGraded)
        }
        .padding(24)
        .frame(width: 400)
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
