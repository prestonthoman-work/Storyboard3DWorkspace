//
//  NextStepCard.swift
//  Storyboard3DWorkspace
//

import SwiftUI

/// A slim card at the top of every tab: how far along the storyboard is, and the one thing
/// to do next, with a button that does it (or goes where it's done).
struct NextStepCard: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let step = appModel.workflowStep

        HStack(alignment: .center, spacing: 14) {
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [.accentColor.opacity(0.55), .accentColor.opacity(0.2)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                Image(systemName: step.symbol)
                    .font(.title3.weight(.semibold))
                    .contentTransition(.symbolEffect(.replace))
            }
            .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 4) {
                Text(step.title)
                    .font(.headline)
                Text(step.detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            action(for: step)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

            Button("Hide Guide", systemImage: "xmark") {
                withAnimation(.snappy) { appModel.isGuideHidden = true }
            }
            .labelStyle(.iconOnly)
            .buttonBorderShape(.circle)
            .buttonStyle(.borderless)
            .controlSize(.mini)
            .foregroundStyle(.tertiary)
            .help("Hide the guide. Show Guide at the top of the panel brings it back.")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background {
            RoundedRectangle(cornerRadius: UI.corner, style: .continuous)
                .fill(LinearGradient(colors: [.accentColor.opacity(0.16), .white.opacity(0.04)],
                                     startPoint: .leading, endPoint: .trailing))
        }
        .overlay {
            RoundedRectangle(cornerRadius: UI.corner, style: .continuous)
                .strokeBorder(.white.opacity(0.1), lineWidth: 1)
        }
        .animation(.smooth, value: step)
    }

    @ViewBuilder
    private func action(for step: WorkflowStep) -> some View {
        if appModel.selectedTab != step.tab {
            Button("Go to \(step.tab.title)", systemImage: "arrow.right") {
                withAnimation(.snappy) { appModel.selectedTab = step.tab }
            }
            .help("Open step \(step.tab.number), \(step.tab.title)")
        } else {
            switch step {
            case .placeBase:
                Button("Looks Good", systemImage: "checkmark") {
                    withAnimation(.snappy) {
                        appModel.confirmBase()
                        appModel.selectedTab = .objects
                    }
                }
                .help("Keep the base where it is and move on to adding objects")
            case .addObjects:
                EmptyView()
            case .firstKeyframe, .secondKeyframe:
                Button("Add Keyframe", systemImage: "plus") {
                    withAnimation(.snappy) { appModel.addKeyframe() }
                }
                .labelStyle(.iconOnly)
                .buttonBorderShape(.circle)
                .help("Add a keyframe")
            case .takePhotos:
                if let target = appModel.firstKeyframeWithoutPhoto,
                   target.id != appModel.animator.selectedKeyframeID,
                   let number = appModel.animator.number(of: target.id) {
                    Button("Keyframe \(number)", systemImage: "arrow.right") { appModel.selectKeyframe(target) }
                        .help("Select keyframe \(number), which still needs a photo")
                } else {
                    Button("Take Photo", systemImage: "camera.fill") { appModel.takePhotoForSelectedKeyframe() }
                        .labelStyle(.iconOnly)
                        .buttonBorderShape(.circle)
                        .disabled(!appModel.canCapture)
                }
            case .share:
                Button("Screen", systemImage: "play.rectangle.fill") {
                    openWindow(id: StoryboardViewer.windowID)
                }
                .help("Watch the storyboard full size")
            }
        }
    }
}
