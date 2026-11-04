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

    var selectedTab: WorkspaceTab = .base

    /// The RealityKit entities for the staged composition.
    let workspace: WorkspaceScene
    let animator: KeyframeAnimator
    let generationService: any ModelGenerationService = ModelGenerationServiceProvider.makeService()

    var isSampleMode: Bool { generationService.source == .sample }

    init() {
        let workspace = WorkspaceScene()
        self.workspace = workspace
        self.animator = KeyframeAnimator(scene: workspace)
        workspace.setBase(BaseTemplateBuilder.make(.grass), size: baseMeters)
    }

    // MARK: Table placement

    enum TablePlacement: Equatable {
        case searching
        case onTable
        case floating(reason: String)
    }

    private(set) var tablePlacement: TablePlacement = .searching
    @ObservationIgnored private var anchoredTable: (id: UUID, anchorFromBase: simd_float4x4)?
    @ObservationIgnored private var searchTimeout: Task<Void, Never>?

    func workspaceDidOpen() async {
        let tracking = SpatialTrackingService.shared
        tablePlacement = .searching
        await tracking.start()
        tracking.onTablesChanged = { [weak self] in self?.tablesChanged() }

        switch tracking.tableDetection {
        case .running:
            tablesChanged()
            searchTimeout = Task { [weak self] in
                try? await Task.sleep(for: .seconds(8))
                guard let self, !Task.isCancelled, self.tablePlacement == .searching else { return }
                self.tablePlacement = .floating(reason: "No table found yet. Look at a table, then choose Find Table.")
            }
        case .notAuthorized:
            workspace.placeBaseFloating()
            tablePlacement = .floating(reason: "Allow access to your surroundings in Settings to place the base on a table.")
        case .unavailable:
            workspace.placeBaseFloating()
            tablePlacement = .floating(reason: "Table detection isn't available here, so the base floats in front of you.")
        }
    }

    func workspaceDidClose() {
        cancelCapture()
        searchTimeout?.cancel()
        searchTimeout = nil
        anchoredTable = nil
        animator.pause()
        SpatialTrackingService.shared.onTablesChanged = nil
        SpatialTrackingService.shared.stop()
    }

    /// Moves the base onto the detected table closest to where the viewer is standing.
    func findTable() {
        let tracking = SpatialTrackingService.shared
        guard tracking.tableDetection == .running else { return }
        if let table = tracking.nearestTable(to: tracking.viewerPosition) {
            anchor(to: table)
        } else {
            tablePlacement = .floating(reason: "No table found. Look around at a table and try again.")
        }
    }

    var canFindTable: Bool {
        SpatialTrackingService.shared.tableDetection == .running
    }

    private func tablesChanged() {
        let tracking = SpatialTrackingService.shared
        if let anchored = anchoredTable {
            // Follow the table's anchor as ARKit refines it, keeping the base where it was placed on the surface.
            if let table = tracking.tables[anchored.id] {
                workspace.placeBase(atSurface: table.originFromAnchor * anchored.anchorFromBase)
            }
            return
        }
        if tablePlacement == .searching, let table = tracking.nearestTable(to: tracking.viewerPosition) {
            anchor(to: table)
        }
    }

    private func anchor(to table: SpatialTrackingService.Table) {
        searchTimeout?.cancel()
        workspace.placeBase(atSurface: table.originFromCenter)
        // Remember where the base sits relative to the table's stable anchor, not its
        // surface center, which drifts as more of the table is detected.
        let originFromBase = workspace.baseAnchor.transformMatrix(relativeTo: nil)
        anchoredTable = (table.id, table.originFromAnchor.inverse * originFromBase)
        tablePlacement = .onTable
    }

    // MARK: Base

    enum BaseOrigin: Equatable {
        case template(BaseTemplate)
        case generated(ModelSource)
    }

    struct BaseSummary {
        let name: String
        let origin: BaseOrigin
    }

    private(set) var base = BaseSummary(name: BaseTemplate.grass.name, origin: .template(.grass))
    /// Diameter of the round base, in centimeters.
    var baseWidth: Double = BaseSizeLimits.defaultWidth {
        didSet { workspace.setBaseSize(baseMeters) }
    }
    private var baseMeters: Float { Float(baseWidth) / 100 }

    /// Sizes the base to fit within the table's shorter side, leaving a margin at the edges.
    func fitBaseToTable() {
        guard let anchored = anchoredTable,
              let table = SpatialTrackingService.shared.tables[anchored.id]
        else { return }
        let fitted = Double(min(table.width, table.depth)) * 100 * 0.9
        let stepped = (fitted / BaseSizeLimits.step).rounded(.down) * BaseSizeLimits.step
        baseWidth = min(max(stepped, BaseSizeLimits.range.lowerBound), BaseSizeLimits.range.upperBound)
    }
    var basePrompt = ""
    private(set) var isGeneratingBase = false
    private(set) var baseNote: String?
    private(set) var baseError: String?

    var canGenerateBase: Bool {
        !isGeneratingBase && !basePrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func applyBaseTemplate(_ template: BaseTemplate) {
        workspace.setBase(BaseTemplateBuilder.make(template), size: baseMeters)
        base = BaseSummary(name: template.name, origin: .template(template))
        baseNote = nil
        baseError = nil
    }

    func generateBase() async {
        guard canGenerateBase else { return }
        let prompt = basePrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        isGeneratingBase = true
        baseError = nil
        defer { isGeneratingBase = false }

        do {
            let model = try await generationService.generateBase(prompt: prompt)
            workspace.setBase(model.entity, size: baseMeters)
            base = BaseSummary(name: model.displayName, origin: .generated(model.source))
            baseNote = model.note
        } catch {
            baseError = error.localizedDescription
        }
    }

    // MARK: Objects

    struct ObjectSummary: Identifiable {
        let id: Entity.ID
        let name: String
        let source: ModelSource
    }

    private(set) var objects: [ObjectSummary] = []
    private(set) var selectedObjectID: Entity.ID?
    var objectPrompt = ""
    private(set) var isGeneratingObject = false
    private(set) var objectNote: String?
    private(set) var objectError: String?

    var hasObjects: Bool { !objects.isEmpty }
    var selectedObject: ObjectSummary? { objects.first { $0.id == selectedObjectID } }

    var canGenerateObject: Bool {
        !isGeneratingObject && !objectPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func generateObject() async {
        guard canGenerateObject else { return }
        let prompt = objectPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        animator.pause()
        isGeneratingObject = true
        objectError = nil
        defer { isGeneratingObject = false }

        do {
            let model = try await generationService.generateObject(prompt: prompt)
            let object = workspace.addObject(model.entity, name: model.displayName)
            objects.append(ObjectSummary(id: object.id, name: model.displayName, source: model.source))
            selectObject(object.id)
            objectNote = model.note
            objectPrompt = ""
        } catch {
            objectError = error.localizedDescription
        }
    }

    func duplicateSelectedObject() {
        guard let summary = selectedObject, let object = workspace.object(withID: summary.id) else { return }
        animator.pause()
        let copy = workspace.duplicate(object)
        objects.append(ObjectSummary(id: copy.id, name: summary.name, source: summary.source))
        selectObject(copy.id)
    }

    func deleteSelectedObject() {
        guard let id = selectedObjectID, let object = workspace.object(withID: id) else { return }
        animator.pause()
        workspace.remove(object)
        objects.removeAll { $0.id == id }
        selectObject(nil)
    }

    func selectObject(_ id: Entity.ID?) {
        selectedObjectID = id
        workspace.showSelection(on: id.flatMap { workspace.object(withID: $0) })
    }

    func selectObject(containing entity: Entity) {
        if let object = workspace.object(containing: entity) {
            selectObject(object.id)
        }
    }

    /// The user grabbed an object: stop playback so it doesn't fight their hands.
    func manipulationBegan(on entity: Entity) {
        animator.pause()
        selectObject(containing: entity)
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

    private func apply(_ newBackground: BackdropImage) async {
        do {
            try await workspace.setBackdropImage(newBackground.image)
            background = newBackground
            backgroundError = nil
        } catch {
            backgroundError = "That image couldn't be shown as a backdrop."
        }
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
    /// Seconds left on the self-timer, or nil when no countdown is running.
    private(set) var captureCountdown: Int?
    @ObservationIgnored private var countdownTask: Task<Void, Never>?

    var captureLens: CaptureLens = .standard {
        didSet { workspace.setViewfinderLens(captureLens) }
    }

    /// The viewfinder shows only while the Capture tab is open in the workspace.
    var isViewfinderVisible: Bool {
        immersiveSpaceState == .open && selectedTab == .capture
    }

    var canCapture: Bool {
        background != nil && !isCapturing && captureCountdown == nil
    }

    /// Starts a 3-second self-timer, then captures from wherever the viewer is looking.
    /// The timer gives them time to look away from this panel and back at their scene.
    func startCapture() {
        guard canCapture else { return }
        captureStatus = nil
        countdownTask = Task { [weak self] in
            for remaining in [3, 2, 1] {
                self?.captureCountdown = remaining
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { return }
            }
            self?.captureCountdown = nil
            await self?.captureComposition()
        }
    }

    func cancelCapture() {
        countdownTask?.cancel()
        countdownTask = nil
        captureCountdown = nil
    }

    private func captureComposition() async {
        guard let background, !isCapturing else { return }
        isCapturing = true
        defer { isCapturing = false }

        let tracking = SpatialTrackingService.shared
        let camera: CaptureCamera
        if let head = tracking.viewerTransform {
            camera = .level(fromHead: head, lens: captureLens)
        } else {
            // No head tracking (such as in Simulator): look at the base from a standing position.
            camera = .looking(from: SpatialTrackingService.fallbackViewerPosition,
                              at: workspace.baseAnchor.position(relativeTo: nil), lens: captureLens)
        }

        do {
            let image = try await CompositionRenderer().render(
                scene: workspace.baseAnchor,
                backdrop: workspace.backdrop,
                background: background.image,
                camera: camera
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
}
