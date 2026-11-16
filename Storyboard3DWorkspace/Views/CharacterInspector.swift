//
//  CharacterInspector.swift
//  Storyboard3DWorkspace
//

import SwiftUI

/// Under a selected character in the Objects list: its body shape, and the way into the
/// Pose Studio. In the scene a character moves like any object; it's posed in the studio.
struct CharacterInspector: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                openWindow(id: PoseStudioView.windowID)
            } label: {
                Label(appModel.isPoseStudioOpen ? "Posing in Pose Studio" : "Pose in Pose Studio",
                      systemImage: "figure.walk.motion")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(appModel.isPoseStudioOpen)
            .help("Pose this character at a large size in its own window, with your hands")

            if let proportions = appModel.selectedCharacterProportions {
                VStack(alignment: .leading, spacing: 6) {
                    proportionSlider("Height", value: proportions.height, range: CharacterProportions.heightRange) { $0.height = $1 }
                    proportionSlider("Build", value: proportions.build, range: CharacterProportions.buildRange) { $0.build = $1 }
                    proportionSlider("Head", value: proportions.head, range: CharacterProportions.headRange) { $0.head = $1 }
                    proportionSlider("Legs", value: proportions.legs, range: CharacterProportions.legsRange) { $0.legs = $1 }
                }
            }
        }
    }

    private func proportionSlider(_ title: String, value: Float, range: ClosedRange<Float>,
                                  update: @escaping (inout CharacterProportions, Float) -> Void) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.callout)
                .frame(width: 64, alignment: .leading)
            Slider(value: Binding(get: { Double(value) }, set: { newValue in
                guard var proportions = appModel.selectedCharacterProportions else { return }
                update(&proportions, Float(newValue))
                appModel.setSelectedCharacterProportions(proportions)
            }), in: Double(range.lowerBound)...Double(range.upperBound), step: 0.01) { editing in
                editing ? appModel.beginProportionsChange() : appModel.endProportionsChange()
            }
            .accessibilityLabel(title)
            Text("\(Int((value * 100).rounded()))%")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 40, alignment: .trailing)
        }
    }
}
