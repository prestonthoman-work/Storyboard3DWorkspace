//
//  DesignSystem.swift
//  Storyboard3DWorkspace
//

import SwiftUI

/// Shared measurements, so every panel lines up the same way.
enum UI {
    static let panelSize = CGSize(width: 560, height: 740)
    static let corner: CGFloat = 22
    static let smallCorner: CGFloat = 14
    static let sectionSpacing: CGFloat = 14
    static let sectionPadding: CGFloat = 16
    /// The soft platter behind a section.
    static let platter = Color.white.opacity(0.055)
    static let platterStroke = Color.white.opacity(0.08)
}

/// A titled group of controls on a soft platter. The accessory sits at the trailing end of
/// the title row, for a value or a small button.
struct PanelSection<Content: View, Accessory: View>: View {
    let title: String
    var symbol: String?
    @ViewBuilder var accessory: Accessory
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if let symbol {
                    Label(title, systemImage: symbol)
                } else {
                    Text(title)
                }
                Spacer(minLength: 8)
                accessory
                    .font(.callout)
            }
            .font(.headline)

            content
        }
        .padding(UI.sectionPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .platter()
    }
}

extension PanelSection where Accessory == EmptyView {
    init(_ title: String, symbol: String? = nil, @ViewBuilder content: () -> Content) {
        self.init(title: title, symbol: symbol, accessory: { EmptyView() }, content: content)
    }
}

extension PanelSection {
    init(_ title: String, symbol: String? = nil, @ViewBuilder accessory: () -> Accessory,
         @ViewBuilder content: () -> Content) {
        self.init(title: title, symbol: symbol, accessory: accessory, content: content)
    }
}

extension View {
    /// The soft rounded background used by sections and cards.
    func platter(cornerRadius: CGFloat = UI.corner) -> some View {
        background(UI.platter, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(UI.platterStroke, lineWidth: 1)
            }
    }
}

/// One consistent look for feedback: what happened, what went wrong, or what to expect.
struct StatusMessage: View {
    enum Kind {
        case info, success, warning, error

        var symbol: String {
            switch self {
            case .info: "info.circle"
            case .success: "checkmark.circle.fill"
            case .warning: "exclamationmark.triangle.fill"
            case .error: "xmark.octagon.fill"
            }
        }

        var tint: Color {
            switch self {
            case .info: .secondary
            case .success: .green
            case .warning: .orange
            case .error: .red
            }
        }
    }

    let text: String
    var kind: Kind = .info
    var symbol: String?

    init(_ text: String, kind: Kind = .info, symbol: String? = nil) {
        self.text = text
        self.kind = kind
        self.symbol = symbol
    }

    var body: some View {
        Label(text, systemImage: symbol ?? kind.symbol)
            .font(.callout)
            .foregroundStyle(kind.tint)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A text field with a Generate button at its end. Return also submits.
struct PromptField: View {
    let placeholder: String
    @Binding var text: String
    let isWorking: Bool
    let canSubmit: Bool
    var buttonTitle = "Generate"
    let submit: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            TextField(placeholder, text: $text)
                .textFieldStyle(.roundedBorder)
                .submitLabel(.go)
                .onSubmit { if canSubmit { submit() } }

            Button(action: submit) {
                if isWorking {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Label(buttonTitle, systemImage: "sparkles")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(!canSubmit)
            .animation(.snappy, value: isWorking)
        }
    }
}

/// A calm, centered message for a screen with nothing on it yet, with one way forward.
struct EmptyState<Action: View>: View {
    let symbol: String
    let title: String
    let message: String
    @ViewBuilder var action: Action

    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [.white.opacity(0.16), .white.opacity(0.03)],
                                         startPoint: .top, endPoint: .bottom))
                    .frame(width: 96, height: 96)
                Image(systemName: symbol)
                    .font(.system(size: 38, weight: .light))
            }
            Text(title)
                .font(.title3.weight(.semibold))
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
            action
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

extension EmptyState where Action == EmptyView {
    init(symbol: String, title: String, message: String) {
        self.init(symbol: symbol, title: title, message: message) { EmptyView() }
    }
}

/// Short how-to lines with a glyph each, kept quiet at the bottom of a panel.
struct HintRow: View {
    let hints: [(symbol: String, text: String)]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(hints, id: \.text) { hint in
                Label(hint.text, systemImage: hint.symbol)
            }
        }
        .font(.footnote)
        .foregroundStyle(.tertiary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A small rounded tag, for counts and modes.
struct Badge: View {
    let text: String
    var symbol: String?

    var body: some View {
        Group {
            if let symbol {
                Label(text, systemImage: symbol)
            } else {
                Text(text)
            }
        }
        .font(.caption.weight(.semibold))
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(.white.opacity(0.1), in: Capsule())
    }
}

/// The bar pinned under a panel's scrolling content, holding its main actions.
struct ActionBar<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            Divider()
                .opacity(0.5)
            HStack(spacing: 12) {
                content
            }
            .padding(.top, 14)
        }
    }
}

// MARK: - Scrolling

/// A panel's vertically scrolling body: its sections, evenly spaced, without indicators.
struct PanelScroll<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: UI.sectionSpacing) { content }
                .padding(.vertical, 2)
        }
        .scrollIndicators(.hidden)
    }
}

/// A horizontally scrolling row whose items can spill past the edges while scrolling.
struct HorizontalStrip<Content: View>: View {
    var spacing: CGFloat = 10
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: spacing) { content }
                .padding(.vertical, 4)
        }
        .scrollIndicators(.hidden)
        .scrollClipDisabled()
    }
}
