//
//  ModelPanel.swift
//  Storyboard3DWorkspace
//

import SwiftUI

struct ModelPanel: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        @Bindable var appModel = appModel

        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 12) {
                TextField("Describe a model", text: $appModel.modelPrompt)
                    .textFieldStyle(.roundedBorder)
                    .submitLabel(.go)
                    .onSubmit(generate)

                Button(action: generate) {
                    if appModel.isGenerating {
                        ProgressView()
                    } else {
                        Label("Generate", systemImage: "sparkles")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!appModel.canGenerate)

                if let error = appModel.generationError {
                    Text(error)
                        .font(.callout)
                        .foregroundStyle(.red)
                }
            }

            if let model = appModel.currentModel {
                Divider()
                CurrentModelRow(model: model)
            }

            Spacer(minLength: 0)

            if appModel.isSampleMode {
                Label("Sample mode: no generation service is set up, so Generate places a built-in low-poly town.",
                      systemImage: "info.circle")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func generate() {
        Task { await appModel.generateModel() }
    }
}

private struct CurrentModelRow: View {
    @Environment(AppModel.self) private var appModel
    let model: AppModel.ModelSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.name)
                        .font(.headline)
                    Text(appModel.isModelSelected ? "\(model.source.label) · Selected" : model.source.label)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if appModel.isModelSelected {
                    Button("Deselect") { appModel.setModelSelected(false) }
                        .buttonStyle(.bordered)
                }

                Button("Reset", systemImage: "arrow.counterclockwise") {
                    appModel.resetModelPlacement()
                }
                .buttonStyle(.bordered)
                .help("Return the model to its starting position, rotation, and size")
            }

            Text("Pinch and drag the model to move it. Turn your hand to rotate, or use both hands to scale.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }
}

#Preview(windowStyle: .automatic) {
    ModelPanel()
        .environment(AppModel())
        .padding()
        .frame(width: 460, height: 500)
}
