//
//  ProjectsView.swift
//  Storyboard3DWorkspace
//

import SwiftUI

/// Shown before the workspace opens: every project, with New, Open, Rename, and Delete.
struct ProjectsView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace

    @State private var covers: [UUID: UIImage] = [:]
    @State private var renaming: ProjectStore.Info?
    @State private var newName = ""
    @State private var deleting: ProjectStore.Info?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Storyboard 3D")
                        .font(.extraLargeTitle2)
                    Text("Build a scene on your table, set a backdrop, and frame it from any angle.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            Button {
                Task {
                    await appModel.createProject()
                    await enterWorkspace()
                }
            } label: {
                Label("New Project", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .disabled(appModel.immersiveSpaceState != .closed)

            if let error = appModel.projectError {
                Text(error).font(.callout).foregroundStyle(.red)
            }

            if appModel.projects.isEmpty {
                Text("Your projects will appear here.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                Text("Projects")
                    .font(.headline)
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(appModel.projects) { project in
                            row(for: project)
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task(id: appModel.projects) {
            covers = Dictionary(uniqueKeysWithValues: appModel.projects.compactMap { project in
                ProjectStore.coverThumbnail(for: project).map { (project.id, $0) }
            })
        }
        .alert("Rename Project", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $newName)
            Button("Rename") {
                if let renaming { appModel.renameProject(renaming.id, to: newName) }
                renaming = nil
            }
            Button("Cancel", role: .cancel) { renaming = nil }
        }
        .alert("Delete “\(deleting?.name ?? "")”?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("Delete", role: .destructive) {
                if let deleting { appModel.deleteProject(deleting.id) }
                deleting = nil
            }
            Button("Cancel", role: .cancel) { deleting = nil }
        } message: {
            Text("Its scene, keyframes, and photos will be removed. This can't be undone.")
        }
    }

    private func row(for project: ProjectStore.Info) -> some View {
        HStack(spacing: 12) {
            Button {
                Task {
                    await appModel.openProject(project)
                    await enterWorkspace()
                }
            } label: {
                HStack(spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(.quaternary)
                        if let cover = covers[project.id] {
                            Image(uiImage: cover)
                                .resizable()
                                .aspectRatio(16 / 9, contentMode: .fill)
                        } else {
                            Image(systemName: "cube.transparent")
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .frame(width: 96, height: 54)
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                    VStack(alignment: .leading, spacing: 3) {
                        Text(project.name)
                            .font(.headline)
                            .lineLimit(1)
                        Text("Edited \(project.modified.formatted(.relative(presentation: .named)))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .padding(8)
                .contentShape(RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)
            .hoverEffect()
            .disabled(appModel.immersiveSpaceState != .closed)

            Menu {
                Button("Rename", systemImage: "pencil") {
                    newName = project.name
                    renaming = project
                }
                Button("Delete", systemImage: "trash", role: .destructive) {
                    deleting = project
                }
            } label: {
                Label("More", systemImage: "ellipsis")
                    .labelStyle(.iconOnly)
            }
            .buttonBorderShape(.circle)
            .accessibilityLabel("Options for \(project.name)")
        }
    }

    /// Opens the immersive workspace for the project that was just loaded.
    private func enterWorkspace() async {
        guard appModel.currentProject != nil, appModel.immersiveSpaceState == .closed else { return }
        appModel.immersiveSpaceState = .inTransition
        switch await openImmersiveSpace(id: appModel.immersiveSpaceID) {
        case .opened:
            // `.open` is set by ImmersiveView.onAppear.
            break
        case .userCancelled, .error:
            appModel.immersiveSpaceState = .closed
        @unknown default:
            appModel.immersiveSpaceState = .closed
        }
    }
}

#Preview(windowStyle: .automatic) {
    ProjectsView()
        .environment(AppModel())
        .frame(width: 500, height: 680)
}
