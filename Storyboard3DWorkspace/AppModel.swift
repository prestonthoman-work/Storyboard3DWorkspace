//
//  AppModel.swift
//  Storyboard3DWorkspace
//
//  Created by Preston Thoman on 11/4/26.
//

import SwiftUI
import RealityKit
import UIKit

/// Maintains app-wide state
@MainActor
@Observable
class AppModel {
    let immersiveSpaceID = "ImmersiveSpace"
    enum ImmersiveSpaceState {
        case closed
        case inTransition
        case open
    }
    var immersiveSpaceState = ImmersiveSpaceState.closed

    var selectedTab: WorkspaceTab = .model

    /// The RealityKit entities for the staged composition.
    let workspace: WorkspaceScene
    let animator: KeyframeAnimator

    init() {
        let workspace = WorkspaceScene()
        self.workspace = workspace
        self.animator = KeyframeAnimator(target: workspace.stageModel)
    }

    var hasModel: Bool { currentModel != nil }

    // MARK: Model

    struct ModelSummary {
        let name: String
        let source: ModelSource
    }

    let generationService: any ModelGenerationService = ModelGenerationServiceProvider.makeService()
    var modelPrompt = ""
    private(set) var isGenerating = false
    private(set) var currentModel: ModelSummary?
    private(set) var generationError: String?
    private(set) var isModelSelected = false

    var isSampleMode: Bool { generationService.source == .sample }

    var canGenerate: Bool {
        !isGenerating && !modelPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func generateModel() async {
        guard canGenerate else { return }
        let prompt = modelPrompt.trimmingCharacters(in: .whitespacesAndNewlines)

        animator.pause()
        isGenerating = true
        generationError = nil
        defer { isGenerating = false }

        do {
            let model = try await generationService.generateModel(prompt: prompt)
            workspace.setModelContent(model.entity)
            currentModel = ModelSummary(name: model.displayName, source: model.source)
            setModelSelected(false)
        } catch {
            generationError = error.localizedDescription
        }
    }

    func resetModelPlacement() {
        animator.pause()
        workspace.resetModelPlacement()
    }

    /// The user grabbed the model: hand control back to them.
    func modelManipulationBegan() {
        animator.pause()
        setModelSelected(true)
    }

    func setModelSelected(_ isSelected: Bool) {
        isModelSelected = isSelected && currentModel != nil
        workspace.setSelectionVisible(isModelSelected)
    }

    // MARK: Background

    private(set) var background: BackdropImage?
    private(set) var isLoadingBackground = false
    private(set) var backgroundError: String?

    func loadDefaultBackgroundIfNeeded() async {
        guard background == nil, !isLoadingBackground else { return }
        await useBuiltInSky()
    }

    func useBuiltInSky() async {
        isLoadingBackground = true
        defer { isLoadingBackground = false }

        let image = await Task.detached(priority: .userInitiated) {
            SkyBackdropRenderer.makeSkyImage()
        }.value

        guard let image else {
            backgroundError = "The built-in sky couldn't be created."
            return
        }
        await apply(BackdropImage(name: "Sky", source: .builtInSky, image: image))
    }

    func importBackground(data: Data, name: String, source: BackdropImage.Source) async {
        isLoadingBackground = true
        defer { isLoadingBackground = false }

        do {
            let image = try await Task.detached(priority: .userInitiated) {
                try BackdropImageLoader.prepare(data)
            }.value
            await apply(BackdropImage(name: name, source: source, image: image))
        } catch {
            backgroundError = error.localizedDescription
        }
    }

    func importBackground(fileAt url: URL) async {
        isLoadingBackground = true
        defer { isLoadingBackground = false }

        do {
            let image = try await Task.detached(priority: .userInitiated) {
                try BackdropImageLoader.prepare(fileAt: url)
            }.value
            let name = url.deletingPathExtension().lastPathComponent
            await apply(BackdropImage(name: name, source: .files, image: image))
        } catch {
            backgroundError = error.localizedDescription
        }
    }

    func reportBackgroundError(_ message: String) {
        backgroundError = message
    }

    // MARK: Capture

    enum CaptureStatus: Equatable {
        case saved
        case failed(String)
    }

    private(set) var lastCapture: UIImage?
    private(set) var isCapturing = false
    private(set) var isSavingCapture = false
    private(set) var captureStatus: CaptureStatus?

    func captureComposition() async {
        guard hasModel, let background, !isCapturing else { return }
        isCapturing = true
        captureStatus = nil
        defer { isCapturing = false }

        do {
            let image = try await CompositionRenderer().render(
                model: workspace.stageModel,
                background: background.image,
                viewerPosition: ViewerPoseProvider.shared.viewerPosition
            )
            lastCapture = UIImage(cgImage: image)
        } catch {
            captureStatus = .failed(error.localizedDescription)
        }
    }

    func saveCaptureToPhotos() async {
        guard let lastCapture, !isSavingCapture else { return }
        isSavingCapture = true
        defer { isSavingCapture = false }

        do {
            try await PhotoLibrarySaver.save(lastCapture)
            captureStatus = .saved
        } catch {
            captureStatus = .failed(error.localizedDescription)
        }
    }

    private func apply(_ newBackground: BackdropImage) async {
        do {
            try await workspace.setBackdropImage(newBackground.image)
            background = newBackground
            backgroundError = nil
        } catch {
            backgroundError = "That image couldn't be shown as a backdrop."
        }
    }
}
