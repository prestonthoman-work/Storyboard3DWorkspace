//
//  BasePanel.swift
//  Storyboard3DWorkspace
//

import SwiftUI

struct BasePanel: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        @Bindable var appModel = appModel

        VStack(alignment: .leading, spacing: 20) {
            TableStatusRow()

            VStack(alignment: .leading, spacing: 10) {
                Text("Templates")
                    .font(.headline)
                HStack(spacing: 12) {
                    ForEach(BaseTemplate.allCases) { template in
                        TemplateButton(template: template,
                                       isSelected: appModel.base.origin == .template(template)) {
                            appModel.applyBaseTemplate(template)
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Generate a Base")
                    .font(.headline)
                HStack(spacing: 10) {
                    TextField("Describe a base, e.g. desert", text: $appModel.basePrompt)
                        .textFieldStyle(.roundedBorder)
                        .submitLabel(.go)
                        .onSubmit(generate)
                    Button(action: generate) {
                        if appModel.isGeneratingBase {
                            ProgressView()
                        } else {
                            Text("Generate")
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(!appModel.canGenerateBase)
                }
                if let error = appModel.baseError {
                    Text(error).font(.callout).foregroundStyle(.red)
                } else if let note = appModel.baseNote {
                    Text(note).font(.callout).foregroundStyle(.secondary)
                }
            }

            BaseSizeControl()

            Spacer(minLength: 0)
        }
    }

    private func generate() {
        Task { await appModel.generateBase() }
    }
}

private struct BaseSizeControl: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        @Bindable var appModel = appModel

        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Size")
                    .font(.headline)
                Text("\(Int(appModel.baseWidth)) cm")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
                Spacer()
                if appModel.tablePlacement == .onTable {
                    Button("Fit to Table") { appModel.fitBaseToTable() }
                        .buttonStyle(.bordered)
                        .help("Size the base to fit the table")
                }
            }

            Slider(value: $appModel.baseWidth, in: BaseSizeLimits.range, step: BaseSizeLimits.step) {
                Text("Base diameter")
            } minimumValueLabel: {
                Text("\(Int(BaseSizeLimits.range.lowerBound))")
            } maximumValueLabel: {
                Text("\(Int(BaseSizeLimits.range.upperBound))")
            } onEditingChanged: { isEditing in
                if isEditing { appModel.beginBaseResize() }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .accessibilityValue("\(Int(appModel.baseWidth)) centimeters across")
        }
    }
}

private struct TableStatusRow: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(appModel.tablePlacement == .onTable ? .green : .secondary)
                .frame(width: 28)

            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 8)

            if appModel.canFindTable {
                Button("Find Table") { appModel.findTable() }
                    .buttonStyle(.bordered)
                    .help("Move the base to the table nearest you")
            }
        }
    }

    private var symbol: String {
        switch appModel.tablePlacement {
        case .searching: "magnifyingglass"
        case .onTable: "checkmark.circle.fill"
        case .floating: "rectangle.dashed"
        }
    }

    private var message: String {
        switch appModel.tablePlacement {
        case .searching: "Looking for a table…"
        case .onTable: "Placed on a table."
        case .floating(let reason): reason
        }
    }
}

private struct TemplateButton: View {
    let template: BaseTemplate
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Circle()
                    .fill(template.swatch)
                    .frame(width: 56, height: 56)
                    .overlay {
                        Image(systemName: template.symbol)
                            .foregroundStyle(.white.opacity(0.9))
                    }
                    .overlay {
                        Circle()
                            .strokeBorder(.white, lineWidth: isSelected ? 3 : 0)
                    }
                Text(template.name)
                    .font(.caption)
            }
            .padding(6)
        }
        .buttonStyle(.plain)
        .hoverEffect()
        .accessibilityLabel("\(template.name) base")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
