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
            sceneEdited()
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
        sceneEdited()
    }

    func deleteSelectedObject() {
        guard let id = selectedObjectID, let object = workspace.object(withID: id) else { return }
        animator.pause()
        workspace.remove(object)
        objects.removeAll { $0.id == id }
        selectObject(nil)
        // The object leaves every keyframe it was in, so those keyframes have changed.
        let changed = animator.removeObject(id)
        changed.forEach(detachPhotos(from:))
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
        case attached(keyframeNumber: Int)
        case libraryOnly
        case saved
        case failed(String)
    }

    /// Every photo taken this session.
    let photos = PhotoLibrary()
    /// The photo shown large in the Capture tab.
    var selectedLibraryPhotoID: CapturedPhoto.ID?
    private(set) var isCapturing = false
    private(set) var isSavingCapture = false
    private(set) var captureStatus: CaptureStatus?
    /// Seconds left on the self-timer, or nil when no countdown is running.
    private(set) var captureCountdown: Int?
    @ObservationIgnored private var countdownTask: Task<Void, Never>?

    var captureLens: CaptureLens = .standard {
        didSet { workspace.setViewfinderLens(captureLens) }
    }

    /// The viewfinder shows whenever a photo can be lined up: on the Capture tab, on the
    /// Animate tab while a keyframe is selected, and during any countdown.
    var isViewfinderVisible: Bool {
        guard immersiveSpaceState == .open else { return false }
        return selectedTab == .capture
            || (selectedTab == .animate && animator.selectedKeyframe != nil)
            || captureCountdown != nil
    }

    var canCapture: Bool {
        background != nil && !isCapturing && captureCountdown == nil
    }

    var selectedLibraryPhoto: CapturedPhoto? {
        photos.photo(selectedLibraryPhotoID) ?? photos.photos.last
    }

    /// The keyframe a photo taken right now would attach to, and its number: the selected
    /// keyframe, since edits auto-save into it. Nothing while playing or between keyframes.
    var captureTarget: (keyframe: Keyframe, number: Int)? {
        guard !animator.isPlaying,
              let keyframe = animator.selectedKeyframe,
              let number = animator.number(of: keyframe.id)
        else { return nil }
        return (keyframe, number)
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

    /// From the Animate tab: take a photo of the selected keyframe, staying on that tab.
    func takePhotoForSelectedKeyframe() {
        guard animator.selectedKeyframe != nil else { return }
        startCapture()
    }

    private func captureComposition() async {
        guard let background, !isCapturing else { return }
        isCapturing = true
        defer { isCapturing = false }

        // Decide the keyframe at the moment the shutter fires, and make sure it holds
        // exactly what's being photographed.
        let target = captureTarget
        if target != nil { autoSaveSelectedKeyframe() }

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
            guard let photo = photos.add(image, lens: captureLens, keyframe: target?.keyframe.id) else {
                captureStatus = .failed("The capture couldn't be saved.")
                return
            }
            selectedLibraryPhotoID = photo.id
            if let target {
                focusedKeyframePhotoID = photo.id
                captureStatus = .attached(keyframeNumber: target.number)
            } else {
                captureStatus = .libraryOnly
            }
            slideshowURL = nil
        } catch {
            captureStatus = .failed(error.localizedDescription)
        }
    }

    func saveSelectedPhotoToPhotos() async {
        guard let photo = selectedLibraryPhoto, let image = photos.image(for: photo), !isSavingCapture else { return }
        isSavingCapture = true
        defer { isSavingCapture = false }

        do {
            try await PhotoLibrarySaver.save(image)
            captureStatus = .saved
        } catch {
            captureStatus = .failed(error.localizedDescription)
        }
    }

    func deletePhoto(_ photo: CapturedPhoto) {
        photos.delete(photo)
        if selectedLibraryPhotoID == photo.id { selectedLibraryPhotoID = nil }
        if focusedKeyframePhotoID == photo.id { focusedKeyframePhotoID = nil }
        captureStatus = nil
        slideshowURL = nil
    }

    // MARK: Keyframes and their photos

    /// The photo shown large in the Animate tab for the selected keyframe.
    var focusedKeyframePhotoID: CapturedPhoto.ID?

    /// The selected keyframe's photo to show: the one the person tapped, else its primary.
    var focusedKeyframePhoto: CapturedPhoto? {
        guard let keyframe = animator.selectedKeyframe else { return nil }
        if let focused = photos.photo(focusedKeyframePhotoID), focused.keyframeID == keyframe.id {
            return focused
        }
        return photos.primaryPhoto(for: keyframe.id)
    }

    func addKeyframe() {
        // Finish saving edits into the current keyframe before starting a new one.
        autoSaveTask?.cancel()
        autoSaveSelectedKeyframe()
        keyframeNotice = nil
        animator.addKeyframe()
        focusedKeyframePhotoID = nil
        slideshowURL = nil
    }

    /// A short message after a keyframe's photos were detached by a change.
    private(set) var keyframeNotice: String?
    @ObservationIgnored private var autoSaveTask: Task<Void, Never>?

    /// Call after any edit to the scene. Once held or falling objects settle, the
    /// arrangement is saved into the selected keyframe.
    func sceneEdited() {
        autoSaveTask?.cancel()
        autoSaveTask = Task { [weak self] in
            // Let gravity finish so the saved pose is where things come to rest (at most ~2 s).
            var settledChecks = 0
            for _ in 0..<20 {
                try? await Task.sleep(for: .milliseconds(100))
                guard let self, !Task.isCancelled else { return }
                settledChecks = self.workspace.isSettled ? settledChecks + 1 : 0
                if settledChecks >= 2 { break }
            }
            guard !Task.isCancelled else { return }
            self?.autoSaveSelectedKeyframe()
            self?.autoSaveTask = nil
        }
    }

    /// Saves the scene into the selected keyframe. If its pose changed, its photos no
    /// longer show it, so they're detached (they stay in the library).
    private func autoSaveSelectedKeyframe() {
        if let changed = animator.saveSceneToSelectedKeyframe() {
            detachPhotos(from: changed)
        }
    }

    private func detachPhotos(from keyframe: Keyframe.ID) {
        let count = photos.photos(for: keyframe).count
        photos.detachPhotos(from: keyframe)
        if count > 0, let number = animator.number(of: keyframe) {
            keyframeNotice = "Keyframe \(number) changed, so its \(count == 1 ? "photo was" : "\(count) photos were") moved to the library."
        }
        if focusedKeyframePhotoID.flatMap({ photos.photo($0) })?.keyframeID == nil { focusedKeyframePhotoID = nil }
        slideshowURL = nil
    }

    func deleteSelectedKeyframe() {
        autoSaveTask?.cancel()
        if let deleted = animator.deleteSelectedKeyframe() {
            photos.detachPhotos(from: deleted)
            focusedKeyframePhotoID = nil
            keyframeNotice = nil
            slideshowURL = nil
        }
    }

    func selectKeyframe(_ keyframe: Keyframe) {
        autoSaveTask?.cancel()
        autoSaveSelectedKeyframe()
        keyframeNotice = nil
        animator.select(keyframe)
        focusedKeyframePhotoID = nil
        captureStatus = nil
    }

    func scrubTimeline(to time: TimeInterval) {
        if autoSaveTask != nil {
            autoSaveTask?.cancel()
            autoSaveTask = nil
            autoSaveSelectedKeyframe()
        }
        animator.scrub(to: time)
        focusedKeyframePhotoID = nil
    }

    func setPrimaryPhoto(_ photo: CapturedPhoto) {
        photos.setPrimary(photo)
        slideshowURL = nil
    }

    // MARK: Slideshow export

    private(set) var isExportingSlideshow = false
    private(set) var slideshowURL: URL?
    private(set) var slideshowError: String?

    /// How many keyframes have a primary photo, out of all keyframes.
    var slideshowCoverage: (withPhoto: Int, total: Int) {
        let keyframes = animator.timeline.keyframes
        return (keyframes.filter { photos.primaryPhoto(for: $0.id) != nil }.count, keyframes.count)
    }

    /// Exports an MP4 of each keyframe's primary photo, in timeline order. Keyframes
    /// without a photo are skipped; other photos taken at a keyframe aren't included.
    func exportSlideshow() async {
        guard !isExportingSlideshow else { return }
        let slides = animator.timeline.keyframes
            .compactMap { photos.primaryPhoto(for: $0.id) }
            .compactMap { photos.image(for: $0)?.cgImage }
        guard !slides.isEmpty else { return }

        isExportingSlideshow = true
        slideshowError = nil
        slideshowURL = nil
        defer { isExportingSlideshow = false }

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Storyboard Slideshow.mp4")
        do {
            try await Task.detached(priority: .userInitiated) {
                try await SlideshowExporter.export(slides, to: url)
            }.value
            slideshowURL = url
        } catch {
            slideshowError = error.localizedDescription
        }
    }
}
