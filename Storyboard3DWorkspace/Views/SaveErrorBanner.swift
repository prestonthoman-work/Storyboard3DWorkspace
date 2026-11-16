//
//  SaveErrorBanner.swift
//  Storyboard3DWorkspace
//

import SwiftUI

/// Shown while the open project's latest changes couldn't be written to disk, with a way
/// to try again. Shows nothing once a save succeeds.
struct SaveErrorBanner: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        if let error = appModel.saveError {
            HStack(spacing: 12) {
                StatusMessage(error, kind: .error)
                Button("Try Again") { appModel.saveNow() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("Try saving the project again")
            }
            .padding(12)
            .background(.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}
