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
    @State private var isChoosingStarter = false
    @State private var showsWelcome = !UserDefaults.standard.bool(forKey: "hasSeenWelcome")

    var body: some View {
        if showsWelcome {
            WelcomeView(start: { starter in
                finishWelcome()
                begin(starter)
            }, dismiss: finishWelcome)
            .transition(.opacity)
        } else {
            projectList
        }
    }

    private func finishWelcome() {
        UserDefaults.standard.set(true, forKey: "hasSeenWelcome")
        withAnimation(.smooth) { showsWelcome = false }
    }

    /// Creates a project from a starter and steps into it.
    private func begin(_ starter: StarterScene) {
        isChoosingStarter = false
        Task {
            await appModel.createProject(from: starter)
            await enterWorkspace()
        }
    }

    private var projectList: some View {
        VStack(alignment: .leading, spacing: 18) {
            header

            if let error = appModel.projectError {
                StatusMessage(error, kind: .error)
            }

            if appModel.projects.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 14)], spacing: 14) {
                        ForEach(appModel.projects) { project in
                            card(for: project)
                                .transition(.scale(scale: 0.96).combined(with: .opacity))
                        }
                    }
                    .padding(.vertical, 4)
                    .animation(.snappy, value: appModel.projects.map(\.id))
                }
                .scrollIndicators(.hidden)
                .scrollClipDisabled()
            }
        }
        .padding(26)
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
        .sheet(isPresented: $isChoosingStarter) {
            NavigationStack {
                StarterPicker(action: begin)
                    .padding(26)
                    .navigationTitle("New Project")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { isChoosingStarter = false }
                        }
                    }
            }
            .frame(width: 520, height: 460)
        }
    }

    private var header: some View {
        HStack(alignment: .bottom, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Storyboard 3D")
                    .font(.largeTitle.weight(.bold))
                Text("Stage scenes on your table. Frame every shot.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Button("Tour", systemImage: "questionmark") {
                appModel.isGuideHidden = false
                withAnimation(.smooth) { showsWelcome = true }
            }
            .labelStyle(.iconOnly)
            .buttonBorderShape(.circle)
            .help("Replay the welcome tour and turn the step-by-step guide back on")
            Button {
                isChoosingStarter = true
            } label: {
                Label("New Project", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(appModel.immersiveSpaceState != .closed)
            .help("Start a new project, blank or from a ready-made set")
        }
    }

    private var emptyState: some View {
        EmptyState(symbol: "film.stack",
                   title: "Your first storyboard",
                   message: "Build a small set on a real table, light it, and photograph each shot from any angle.") {
            Button {
                isChoosingStarter = true
            } label: {
                Label("Start a Project", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(appModel.immersiveSpaceState != .closed)
        }
    }

    /// A large cover card: the project's best photo, its name over a soft shadow, and
    /// how many shots it has.
    private func card(for project: ProjectStore.Info) -> some View {
        Button {
            Task {
                await appModel.openProject(project)
                await enterWorkspace()
            }
        } label: {
            ZStack(alignment: .bottomLeading) {
                cover(for: project)
                    .frame(maxWidth: .infinity)
                    .aspectRatio(16 / 9, contentMode: .fit)

                LinearGradient(colors: [.clear, .black.opacity(0.15), .black.opacity(0.72)],
                               startPoint: .center, endPoint: .bottom)

                VStack(alignment: .leading, spacing: 4) {
                    Text(project.name)
                        .font(.headline)
                        .lineLimit(1)
                    Text(subtitle(for: project))
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.75))
                }
                .foregroundStyle(.white)
                .padding(14)
            }
            .clipShape(RoundedRectangle(cornerRadius: UI.corner, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: UI.corner, style: .continuous)
                    .strokeBorder(.white.opacity(0.12), lineWidth: 1)
            }
            .contentShape(.hoverEffect, RoundedRectangle(cornerRadius: UI.corner, style: .continuous))
        }
        .buttonStyle(.plain)
        .hoverEffect()
        .disabled(appModel.immersiveSpaceState != .closed)
        .overlay(alignment: .topTrailing) {
            Menu {
                Button("Rename", systemImage: "pencil") {
                    newName = project.name
                    renaming = project
                }
                Button("Duplicate", systemImage: "plus.square.on.square") {
                    appModel.duplicateProject(project.id)
                }
                Button("Delete", systemImage: "trash", role: .destructive) {
                    deleting = project
                }
            } label: {
                Label("More", systemImage: "ellipsis")
                    .labelStyle(.iconOnly)
            }
            .buttonBorderShape(.circle)
            .controlSize(.small)
            .padding(8)
            .accessibilityLabel("Options for \(project.name)")
        }
    }

    @ViewBuilder
    private func cover(for project: ProjectStore.Info) -> some View {
        if let cover = covers[project.id] {
            Image(uiImage: cover)
                .resizable()
                .aspectRatio(16 / 9, contentMode: .fill)
        } else {
            // No photos yet: a calm gradient tinted per project, with a diorama glyph.
            let hue = Double(project.id.uuid.0) / 255
            ZStack {
                LinearGradient(colors: [Color(hue: hue, saturation: 0.35, brightness: 0.42),
                                        Color(hue: (hue + 0.08).truncatingRemainder(dividingBy: 1),
                                              saturation: 0.45, brightness: 0.22)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                Image(systemName: "cube.transparent")
                    .font(.system(size: 44, weight: .ultraLight))
                    .foregroundStyle(.white.opacity(0.35))
                    .offset(y: -14)
            }
        }
    }

    private func subtitle(for project: ProjectStore.Info) -> String {
        let edited = "Edited \(project.modified.formatted(.relative(presentation: .named)))"
        guard let shots = project.shotCount, shots > 0 else { return edited }
        return "\(shots) shot\(shots == 1 ? "" : "s") · \(edited)"
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
        .frame(width: UI.panelSize.width, height: UI.panelSize.height)
}
