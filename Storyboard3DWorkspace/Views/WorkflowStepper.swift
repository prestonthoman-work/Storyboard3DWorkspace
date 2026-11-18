//
//  WorkflowStepper.swift
//  Storyboard3DWorkspace
//

import SwiftUI

/// The four steps of the workflow as a numbered strip at the top of every tab: where you
/// are, what's done, and a tap away from any other step. The tab bar does the same, but
/// it's a strip of icons at the panel's side; this spells the order out.
struct WorkflowStepper: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                ForEach(WorkspaceTab.allCases) { tab in
                    if tab != .base {
                        Capsule()
                            .fill(appModel.isStepDone(tab.previous) ? Color.accentColor.opacity(0.7) : .white.opacity(0.14))
                            .frame(width: 10, height: 2)
                    }
                    StepButton(tab: tab,
                               isCurrent: appModel.selectedTab == tab,
                               isDone: appModel.isStepDone(tab),
                               badge: badge(for: tab)) {
                        withAnimation(.snappy) { appModel.selectedTab = tab }
                    }
                }
            }

            Text(appModel.selectedTab.purpose)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .contentTransition(.opacity)
                .animation(.smooth, value: appModel.selectedTab)
        }
    }

    /// A small count next to a step's name, where one helps.
    private func badge(for tab: WorkspaceTab) -> String? {
        switch tab {
        case .base: nil
        case .objects: appModel.objects.isEmpty ? nil : "\(appModel.objects.count)"
        case .animate:
            appModel.animator.timeline.keyframes.isEmpty ? nil : "\(appModel.animator.timeline.keyframes.count)"
        case .photos: appModel.photos.photos.isEmpty ? nil : "\(appModel.photos.photos.count)"
        }
    }
}

private struct StepButton: View {
    let tab: WorkspaceTab
    let isCurrent: Bool
    let isDone: Bool
    let badge: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                ZStack {
                    Circle()
                        .fill(isCurrent ? Color.accentColor : isDone ? Color.accentColor.opacity(0.3) : .white.opacity(0.1))
                    if isDone && !isCurrent {
                        Image(systemName: "checkmark")
                            .font(.caption2.weight(.bold))
                    } else {
                        Text("\(tab.number)")
                            .font(.caption.weight(.bold).monospacedDigit())
                    }
                }
                .frame(width: 22, height: 22)

                Text(tab.title)
                    .font(.callout.weight(isCurrent ? .semibold : .regular))
                    .lineLimit(1)
                    .foregroundStyle(isCurrent ? .primary : .secondary)

                if let badge {
                    Text(badge)
                        .font(.caption2.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.leading, 5)
            .padding(.trailing, 10)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity)
            .background(isCurrent ? AnyShapeStyle(.white.opacity(0.12)) : AnyShapeStyle(.clear), in: Capsule())
            .contentShape(.hoverEffect, Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .hoverEffect()
        .accessibilityLabel("Step \(tab.number), \(tab.title)" + (isDone ? ", done" : ""))
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
        .help(tab.purpose)
    }
}

extension WorkspaceTab {
    /// The step before this one (the base for the first).
    var previous: WorkspaceTab { WorkspaceTab(rawValue: rawValue - 1) ?? .base }
}

extension AppModel {
    /// Whether a step has what it needs. Photos never finishes; it's for extra shots.
    func isStepDone(_ tab: WorkspaceTab) -> Bool {
        switch tab {
        case .base: isBaseReady || !objects.isEmpty
        case .objects: !objects.isEmpty
        case .animate: workflowStep == .share
        case .photos: false
        }
    }
}
