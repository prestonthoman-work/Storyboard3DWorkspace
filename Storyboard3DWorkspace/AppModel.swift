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

    var selectedTab: WorkspaceTab = .set

    /// The person closed the "next step" guide. Remembered across launches.
    var isGuideHidden: Bool = UserDefaults.standard.bool(forKey: "isGuideHidden") {
        didSet { UserDefaults.standard.set(isGuideHidden, forKey: "isGuideHidden") }
    }

    /// Faint ghosts of the previous keyframe while editing one. Remembered across launches.
    var showsOnionSkin: Bool = UserDefaults.standard.object(forKey: "showsOnionSkin") as? Bool ?? true {
        didSet { UserDefaults.standard.set(showsOnionSkin, forKey: "showsOnionSkin") }
    }

    /// Where objects were in the keyframe before the selected one, for those that have moved
    /// since. Nil when there's nothing to compare against.
    var onionSkinPoses: [ObjectID: Transform]? {
        guard showsOnionSkin, immersiveSpaceState == .open, !animator.isPlaying,
              let selected = animator.selectedKeyframe,
              let index = animator.timeline.index(of: selected.id), index > 0 else { return nil }
        let previous = animator.timeline.keyframes[index - 1]
        let moved = previous.poses.filter { id, pose in
            guard let now = selected.poses[id] else { return true }
            if let before = previous.characterPoses[id], let after = selected.characterPoses[id], !before.matches(after) {
                return true
            }
            return !KeyframeTimeline.posesMatch([id: pose], [id: now])
        }
        return moved.isEmpty ? nil : moved
    }

    /// The body poses for characters in the onion skin, from the previous keyframe.
    var onionSkinCharacterPoses: [ObjectID: CharacterPose] {
        guard let ghosts = onionSkinPoses, let selected = animator.selectedKeyframe,
              let index = animator.timeline.index(of: selected.id), index > 0 else { return [:] }
        return animator.timeline.keyframes[index - 1].characterPoses.filter { ghosts[$0.key] != nil }
    }

    /// Floating name tags above objects in the room. Remembered across launches.
    var showsObjectLabels: Bool = UserDefaults.standard.bool(forKey: "showsObjectLabels") {
        didSet { UserDefaults.standard.set(showsObjectLabels, forKey: "showsObjectLabels") }
    }

    /// The RealityKit entities for the staged composition.
    let workspace: WorkspaceScene
    let animator: KeyframeAnimator
    let generationService: any ModelGenerationService = ModelGenerationServiceProvider.makeService()

    var isSampleMode: Bool { generationService.source == .sample }

    init() {
        let workspace = WorkspaceScene()
        self.workspace = workspace
        self.animator = KeyframeAnimator(scene: workspace)
        self.tableAnchoring = TableAnchoring(workspace: workspace)
        self.poseEditor = PoseEditor(workspace: workspace)
        workspace.setBase(BaseTemplateBuilder.make(.grass), size: baseMeters)
        refreshProjects()
    }

    // MARK: Projects

    /// Every saved project, most recently edited first.
    private(set) var projects: [ProjectStore.Info] = []
    /// The project open in the workspace.
    private(set) var currentProject: ProjectStore.Info?
    /// What went wrong with the last project-list action (create, open, rename, and so on).
    private(set) var projectError: String?

    /// Something worth knowing about the open project, such as photos that couldn't be found.
    private(set) var projectNotice: String?

    func dismissProjectNotice() {
        projectNotice = nil
    }

    /// Photos the open project lists whose image files couldn't be read when it was opened.
    /// They aren't shown, but each save keeps them in the project file instead of erasing them.
    @ObservationIgnored private var missingPhotos: [ProjectState.Photo] = []

    var projectName: String { currentProject?.name ?? "Storyboard" }

    func refreshProjects() {
        do {
            try ProjectStore.migrateLegacyProjectIfNeeded()
        } catch {
            projectError = "Your earlier storyboard couldn't be moved into the project list. It's still stored and will be tried again next time."
        }
        projects = ProjectStore.list()
    }

    /// Creates and opens an empty project. Returns false, leaving the open project in place,
    /// if the open project's changes couldn't be saved first or the new one couldn't be made.
    @discardableResult
    func createProject() async -> Bool {
        projectError = nil
        guard saveNow() else { return false }
        let existing = Set(projects.map(\.name))
        var number = projects.count + 1
        while existing.contains("Storyboard \(number)") { number += 1 }
        do {
            let info = try ProjectStore.create(name: "Storyboard \(number)")
            return await load(info)
        } catch {
            projectError = "A new project couldn't be created."
            return false
        }
    }

    /// Starts a project from a ready-made set. Animated starters come with two keyframes.
    /// The set-up isn't undoable: undo starts from the finished starter.
    /// Returns false if the project couldn't be created.
    @discardableResult
    func createProject(from starter: StarterScene) async -> Bool {
        guard await createProject() else { return false }
        guard starter != .blank else { return true }

        applyBaseTemplate(starter.template)
        var placed: [(StarterScene.Placement, Entity)] = []
        for placement in starter.placements {
            placeCatalogObject(placement.kind, color: placement.color, name: placement.name)
            guard let id = selectedObjectID, let object = workspace.object(withID: id) else { continue }
            object.position = [placement.x, 0, placement.z]
            object.orientation = simd_quatf(angle: placement.yawDegrees * .pi / 180, axis: [0, 1, 0])
            ObjectGravitySystem.keepAboveSurface(object)
            placed.append((placement, object))
        }
        selectObject(nil)
        objectNote = nil

        if starter.isAnimated {
            animator.addKeyframe()
            animator.setShotType(.establishing, for: animator.selectedKeyframeID!)
            for (placement, object) in placed {
                guard let target = placement.movesTo else { continue }
                object.position = [target.x, object.position.y, target.y]
            }
            animator.addKeyframe()
            animator.setShotType(.wide, for: animator.selectedKeyframeID!)
        }
        autoSaveTask?.cancel()
        autoSaveTask = nil
        undoStack.removeAll()
        redoStack.removeAll()
        saveNow()
        refreshProjects()
        return true
    }

    /// Opens a saved project. Returns false if it couldn't be opened, either because the
    /// open project's changes couldn't be saved first or because its file can't be read.
    @discardableResult
    func openProject(_ info: ProjectStore.Info) async -> Bool {
        guard currentProject?.id != info.id else { return true }
        projectError = nil
        guard saveNow() else { return false }
        return await load(info)
    }

    func renameProject(_ id: UUID, to name: String) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        projectError = nil
        do {
            try ProjectStore.rename(id, to: name)
            if currentProject?.id == id { currentProject?.name = name }
        } catch {
            projectError = "That project couldn't be renamed."
        }
        refreshProjects()
    }

    /// Copies a project so a variation can be tried without changing the original.
    func duplicateProject(_ id: UUID) {
        projectError = nil
        if currentProject?.id == id { saveNow() }
        guard let original = projects.first(where: { $0.id == id }) else { return }
        let existing = Set(projects.map(\.name))
        var name = "\(original.name) Copy"
        var number = 2
        while existing.contains(name) {
            name = "\(original.name) Copy \(number)"
            number += 1
        }
        do {
            _ = try ProjectStore.duplicate(id, name: name)
        } catch {
            projectError = "That project couldn't be duplicated."
        }
        refreshProjects()
    }

    func deleteProject(_ id: UUID) {
        projectError = nil
        do {
            try ProjectStore.delete(id)
        } catch {
            projectError = "That project couldn't be deleted."
            refreshProjects()
            return
        }
        if currentProject?.id == id {
            currentProject = nil
            resetToEmptyProject()
            // Its unsaved changes went with it.
            hasUnsavedChanges = false
            saveError = nil
        }
        refreshProjects()
    }

    /// Clears everything, then loads a project's saved content (if it has any).
    ///
    /// If the saved file exists but can't be read, nothing is opened: opening it empty
    /// would let the next auto-save overwrite the project with a blank one.
    private func load(_ info: ProjectStore.Info) async -> Bool {
        let loaded: ProjectStore.LoadedProject?
        do {
            loaded = try ProjectStore.load(info.id)
        } catch {
            projectError = "“\(info.name)” couldn't be opened because its file can't be read."
            return false
        }

        resetToEmptyProject()
        currentProject = info
        selectedTab = .set
        saveError = nil

        var restoredBackdrop: BackdropImage?
        if let loaded {
            missingPhotos = loaded.missingPhotos
            if !missingPhotos.isEmpty {
                let count = missingPhotos.count
                projectNotice = count == 1
                    ? "1 photo in this project couldn't be found, so it isn't shown."
                    : "\(count) photos in this project couldn't be found, so they aren't shown."
            }
            isRestoring = true
            photos.load(loaded.photos, primaries: loaded.saved.state.primaryPhotoIDs)
            captureLens = loaded.saved.captureLens
            captureLighting = loaded.saved.captureLighting ?? .studio
            captureLook = loaded.saved.captureLook ?? .standard
            isRestoring = false
            restore(loaded.saved.state)
            if let backdrop = loaded.saved.backdrop, backdrop.source != .builtInSky, let image = loaded.backdropImage {
                restoredBackdrop = BackdropImage(name: backdrop.name, source: backdrop.source, image: image)
                backdropFileID = backdrop.fileID
            }
        }

        if let restoredBackdrop {
            await apply(restoredBackdrop, isRestoredFromDisk: true)
        } else if background?.source != .builtInSky {
            await useBuiltInSky()
        }
        hasUnsavedChanges = false
        refreshProjects()
        return true
    }

    private func resetToEmptyProject() {
        restore(.empty)
        photos.reset()
        undoStack.removeAll()
        redoStack.removeAll()
        selectedLibraryPhotoID = nil
        objectNote = nil
        baseNote = nil
        backdropFileID = nil
        missingPhotos = []
        projectNotice = nil
        isRestoring = true
        captureLens = .standard
        captureLighting = .studio
        captureLook = .standard
        isRestoring = false
    }

    // MARK: Table placement

    typealias TablePlacement = TableAnchoring.Placement

    /// Keeps the base on a real table in the room.
    let tableAnchoring: TableAnchoring

    var tablePlacement: TablePlacement { tableAnchoring.placement }

    func workspaceDidOpen() async {
        SceneFeedback.isEnabled = true
        SoundEffects.preload()
        updateLightingPreview()
        await tableAnchoring.start()
    }

    func workspaceDidClose() {
        SceneFeedback.isEnabled = false
        Task { await workspace.setLightingPreview(nil, camera: viewerCamera()) }
        cancelCapture()
        saveNow()
        refreshProjects()
        animator.pause()
        tableAnchoring.stop()
    }

    /// Moves the base onto the detected table closest to where the viewer is standing.
    func findTable() {
        tableAnchoring.findTable()
    }

    var canFindTable: Bool { tableAnchoring.canFindTable }

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
    /// How to rebuild the current base (undo, reopening the app).
    @ObservationIgnored private var baseRecipe: ModelRecipe = .baseTemplate(BaseTemplate.grass.rawValue)
    /// Diameter of the round base, in centimeters.
    var baseWidth: Double = BaseSizeLimits.defaultWidth {
        didSet {
            workspace.setBaseSize(baseMeters)
            documentChanged()
        }
    }

    /// Call when the size slider is first touched, so one drag is one undo step.
    func beginBaseResize() {
        checkpoint()
    }
    private var baseMeters: Float { Float(baseWidth) / 100 }

    /// Sizes the base to fit within the table's shorter side, leaving a margin at the edges.
    func fitBaseToTable() {
        guard let table = tableAnchoring.anchoredTableSize else { return }
        checkpoint()
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
        checkpoint()
        workspace.setBase(BaseTemplateBuilder.make(template), size: baseMeters)
        base = BaseSummary(name: template.name, origin: .template(template))
        baseRecipe = .baseTemplate(template.rawValue)
        baseNote = nil
        baseError = nil
        documentChanged()
    }

    func generateBase() async {
        guard canGenerateBase else { return }
        let prompt = basePrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        isGeneratingBase = true
        baseError = nil
        defer { isGeneratingBase = false }

        do {
            let model = try await generationService.generateBase(prompt: prompt)
            checkpoint()
            workspace.setBase(model.entity, size: baseMeters)
            base = BaseSummary(name: model.displayName, origin: .generated(model.source))
            baseRecipe = model.recipe
            baseNote = model.note
            documentChanged()
        } catch {
            baseError = error.localizedDescription
        }
    }

    // MARK: Objects

    struct ObjectSummary: Identifiable {
        let id: ObjectID
        let name: String
        let source: ModelSource
        let recipe: ModelRecipe
    }

    private(set) var objects: [ObjectSummary] = []
    private(set) var selectedObjectID: ObjectID?
    var objectPrompt = ""
    private(set) var isGeneratingObject = false
    private(set) var objectNote: String?
    private(set) var objectError: String?

    var hasObjects: Bool { !objects.isEmpty }

    /// Where an object appears in the animation, for the Objects list.
    func keyframeMembership(of id: ObjectID) -> String {
        let keyframes = animator.timeline.keyframes
        guard !keyframes.isEmpty else { return "" }
        let numbers = keyframes.enumerated().compactMap { index, keyframe in
            keyframe.poses[id] != nil ? index + 1 : nil
        }
        if numbers.isEmpty { return "No keyframes" }
        if numbers.count == keyframes.count && keyframes.count > 1 { return "All keyframes" }
        if numbers.count == 1 { return "Keyframe \(numbers[0])" }
        return "Keyframes " + numbers.map(String.init).joined(separator: ", ")
    }
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
            place(model)
            objectPrompt = ""
        } catch {
            objectError = error.localizedDescription
        }
    }

    /// Renders of each built-in object for the library tray.
    let catalogThumbnails = CatalogThumbnails()

    /// Places a built-in object straight from the library tray.
    func placeCatalogObject(_ kind: SampleObjectCatalog.Kind, color: String? = nil, name: String? = nil) {
        animator.pause()
        objectError = nil
        let recipe = ModelRecipe.sampleObject(kind: kind.rawValue, color: color)
        place(GeneratedModel(displayName: name ?? recipe.defaultName ?? kind.name, source: .sample,
                             recipe: recipe,
                             entity: SampleObjectCatalog.make(kind, tint: SampleObjectCatalog.color(named: color)),
                             note: nil))
    }

    // MARK: Characters

    /// Places a built-in poseable character.
    func placeCharacter(_ kind: CharacterKind) {
        animator.pause()
        objectError = nil
        let recipe = ModelRecipe.character(kind: kind.rawValue, color: nil, proportions: kind.proportions)
        place(GeneratedModel(displayName: kind.name, source: .sample, recipe: recipe,
                             entity: CharacterBuilder.make(kind, proportions: kind.proportions, tint: nil), note: nil))
    }

    /// Every character in the scene, for choosing one in the Pose Studio.
    var characters: [ObjectSummary] { objects.filter { $0.recipe.characterKind != nil } }

    /// Poses the selected character. Views go through the methods below, which add undo and saving.
    let poseEditor: PoseEditor

    /// The body part selected in the Pose Studio.
    var selectedJoint: Joint? { poseEditor.selectedJoint }
    /// Poses saved for reuse, shared by every project.
    var savedPoses: [SavedPose] { poseEditor.savedPoses }
    var poseLibraryError: String? { poseEditor.libraryError }
    /// True while a body part is being dragged in the Pose Studio.
    var isPoseDragging: Bool { poseEditor.isDragging }

    var isSelectedObjectCharacter: Bool { selectedObject?.recipe.characterKind != nil }

    private var selectedCharacterEntity: Entity? {
        guard isSelectedObjectCharacter, let id = selectedObjectID else { return nil }
        return workspace.object(withID: id)
    }

    /// Reading this makes a view refresh whenever a pose may have changed: an edit, undo or
    /// redo, scrubbing, or playback.
    private func observePoseChanges() {
        _ = poseEditor.revision
        _ = animator.playhead
        _ = undoStack.count
        _ = redoStack.count
    }

    /// The selected character's current pose.
    var selectedCharacterPose: CharacterPose? {
        observePoseChanges()
        return selectedCharacterEntity.flatMap { poseEditor.pose(of: $0) }
    }

    func selectJoint(_ joint: Joint?) {
        poseEditor.selectJoint(joint)
    }

    /// Call when a joint slider is first touched, so one drag is one undo step.
    func beginPoseChange() {
        animator.pause()
        checkpoint()
    }

    /// Call when a joint slider is let go: the pose is saved into the selected keyframe.
    func endPoseChange() {
        sceneEdited()
    }

    /// Runs a pose edit on the selected character; if it changed the pose, the latest export
    /// is out of date.
    private func editSelectedPose(_ edit: (Entity) -> Bool) {
        guard let object = selectedCharacterEntity, edit(object) else { return }
        exports.invalidate()
    }

    /// Sets one joint angle on the selected character, live (wrap in begin/endPoseChange).
    /// The part stops where it would sink into the body.
    func setJointAngle(_ value: Float, axis: JointAxis, of joint: Joint) {
        editSelectedPose { poseEditor.setJointAngle(value, axis: axis, of: joint, on: $0) }
    }

    /// Steps one joint angle by a fixed amount, as its own undo step.
    func nudgeJoint(_ joint: Joint, axis: JointAxis, by delta: Float) {
        guard let pose = selectedCharacterPose else { return }
        beginPoseChange()
        setJointAngle(pose[joint][axis] + delta, axis: axis, of: joint)
        endPoseChange()
    }

    func resetJoint(_ joint: Joint) {
        guard var pose = selectedCharacterPose, !pose[joint].isZero else { return }
        pose[joint] = .zero
        beginPoseChange()
        editSelectedPose { poseEditor.setPose(pose, on: $0) }
        endPoseChange()
    }

    /// Back to standing straight. Where the character stands and its size don't change.
    func resetPose() {
        applyPose(.neutral)
    }

    /// Swaps left and right, as if seen in a mirror.
    func mirrorPose() {
        guard let pose = selectedCharacterPose else { return }
        applyPose(pose.mirrored)
    }

    /// Replaces the selected character's pose, keeping its place in the scene and size.
    func applyPose(_ pose: CharacterPose) {
        guard let current = selectedCharacterPose, !current.matches(pose, tolerance: 0.01) else { return }
        beginPoseChange()
        editSelectedPose { poseEditor.setPose(pose, on: $0) }
        endPoseChange()
    }

    func applyPreset(_ preset: PosePreset) {
        applyPose(preset.pose)
        objectNote = preset.requirement
    }

    /// Saves the selected character's pose for reuse in any project. A pose with the same
    /// name is replaced.
    func saveCurrentPose(named name: String) {
        guard let pose = selectedCharacterPose else { return }
        poseEditor.savePose(pose, named: name)
    }

    func deleteSavedPose(_ saved: SavedPose) {
        poseEditor.deleteSavedPose(saved)
    }

    // Body shape

    var selectedCharacterProportions: CharacterProportions? { selectedObject?.recipe.characterProportions }

    /// Call when a proportion slider is first touched, so one drag is one undo step.
    func beginProportionsChange() {
        animator.pause()
        checkpoint()
    }

    /// Reshapes the selected character, live. Its pose, place, and keyframes are kept.
    func setSelectedCharacterProportions(_ proportions: CharacterProportions) {
        guard let summary = selectedObject, case .character(let kind, let color, let current) = summary.recipe,
              let object = workspace.object(withID: summary.id) else { return }
        let proportions = proportions.clamped
        guard proportions != current else { return }
        let recipe = ModelRecipe.character(kind: kind, color: color, proportions: proportions)
        guard let content = recipe.makeEntity() else { return }
        rebuildContent(of: object, with: content, recipe: recipe)
        updateSummary(summary.id) { ObjectSummary(id: $0.id, name: $0.name, source: $0.source, recipe: recipe) }
        workspace.showSelection(on: object)
        documentChanged()
    }

    func endProportionsChange() {
        sceneEdited()
    }

    // Hands and feet

    /// The selected limb's hand or foot position relative to its shoulder or hip, at human
    /// scale in meters: x outward from the body, y up, z forward.
    func reach(of limb: Limb) -> SIMD3<Float>? {
        observePoseChanges()
        return selectedCharacterEntity.flatMap { poseEditor.reach(of: limb, on: $0) }
    }

    func bendDirection(of limb: Limb) -> Float? {
        observePoseChanges()
        return selectedCharacterEntity.flatMap { poseEditor.bendDirection(of: limb, on: $0) }
    }

    /// Moves the hand or foot to `reach` (as from `reach(of:)`), live; wrap in begin/endPoseChange.
    func setReach(_ reach: SIMD3<Float>, of limb: Limb) {
        editSelectedPose { poseEditor.setReach(reach, of: limb, on: $0) }
    }

    /// Turns the elbow or knee around the line to the hand or foot, live.
    func setBendDirection(_ degrees: Float, of limb: Limb) {
        editSelectedPose { poseEditor.setBendDirection(degrees, of: limb, on: $0) }
    }

    // Dragging body parts (Pose Studio)

    /// Swings a joint to follow a drag: `from` and `to` are the drag's start and current
    /// directions from the joint, in its parent's space. End with `endPoseDrag()`.
    func swingJoint(_ joint: Joint, from: SIMD3<Float>, to: SIMD3<Float>) {
        editSelectedPose { poseEditor.swingJoint(joint, from: from, to: to, on: $0, beginning: beginPoseChange) }
    }

    /// Moves a hand or foot with a drag, bending the arm or leg to follow: `from` and `to`
    /// are the drag's start and current points relative to the shoulder or hip, in the
    /// solver's space. End with `endPoseDrag()`.
    func dragHand(_ limb: Limb, from: SIMD3<Float>, to: SIMD3<Float>) {
        editSelectedPose { poseEditor.dragHand(limb, from: from, to: to, on: $0, beginning: beginPoseChange) }
    }

    /// Finishes a drag: the body settles back onto its feet and the edit is saved.
    func endPoseDrag() {
        let object = selectedCharacterEntity
        guard poseEditor.endDrag(on: object) else { return }
        if object != nil { exports.invalidate() }
        endPoseChange()
    }

    /// Swaps an object's geometry, keeping a character's pose (or giving a new character one).
    private func rebuildContent(of object: Entity, with content: Entity, recipe: ModelRecipe, pose: CharacterPose? = nil) {
        let previousPose = workspace.characterPose(of: object)
        workspace.replaceContent(of: object, with: content)
        if recipe.characterKind != nil {
            workspace.setCharacterPose(pose ?? previousPose ?? .neutral, on: object)
        } else {
            object.components.remove(CharacterPoseComponent.self)
        }
        poseEditor.poseChanged()
    }

    // Pose Studio

    /// The large copy of the selected character shown in the Pose Studio window.
    var poseStudio: PoseStudioScene { poseEditor.studio }
    var isPoseStudioOpen: Bool {
        get { poseEditor.isStudioOpen }
        set { poseEditor.isStudioOpen = newValue }
    }

    /// Keeps the studio's figure matching the selected character.
    func updatePoseStudio() {
        poseEditor.updateStudio(recipe: isSelectedObjectCharacter ? selectedObject?.recipe : nil,
                                pose: selectedCharacterPose)
    }

    // MARK: Naming

    /// A name no other object has: "Tree", then "Tree 2", "Tree 3", so every object can be
    /// told apart in lists, labels, and keyframes.
    func uniqueObjectName(_ name: String, excluding id: ObjectID? = nil) -> String {
        let taken = Set(objects.filter { $0.id != id }.map(\.name))
        guard taken.contains(name) else { return name }
        let stem = Self.nameStem(name)
        var number = 2
        while taken.contains("\(stem) \(number)") { number += 1 }
        return "\(stem) \(number)"
    }

    /// "Tree 3" → "Tree". Names without a trailing number are returned unchanged.
    static func nameStem(_ name: String) -> String {
        guard let space = name.lastIndex(of: " "), Int(name[name.index(after: space)...]) != nil else { return name }
        return String(name[..<space])
    }

    /// True for names the app gave on its own, such as "Red House" or "Red House 2", which
    /// can follow the object when it's recolored. Custom names are kept.
    static func isAutomaticName(_ name: String, for defaultName: String?) -> Bool {
        guard let defaultName else { return false }
        return nameStem(name) == defaultName || name == defaultName
    }

    private func place(_ model: GeneratedModel) {
        checkpoint()
        let id = ObjectID()
        let name = uniqueObjectName(model.displayName)
        let object = workspace.addObject(model.entity, name: name, id: id)
        if model.recipe.characterKind != nil { workspace.setCharacterPose(.neutral, on: object) }
        SceneFeedback.appear(object)
        objects.append(ObjectSummary(id: id, name: name, source: model.source, recipe: model.recipe))
        selectObject(id)
        objectNote = model.note
        documentChanged()
        sceneEdited()
    }

    func duplicateSelectedObject() {
        guard let summary = selectedObject, let object = workspace.object(withID: summary.id) else { return }
        animator.pause()
        checkpoint()
        let id = ObjectID()
        let name = uniqueObjectName(summary.name)
        let copy = workspace.duplicate(object, id: id)
        copy.name = name
        SceneFeedback.appear(copy)
        objects.append(ObjectSummary(id: id, name: name, source: summary.source, recipe: summary.recipe))
        selectObject(id)
        documentChanged()
        sceneEdited()
    }

    func deleteSelectedObject() {
        guard let id = selectedObjectID, let object = workspace.object(withID: id) else { return }
        animator.pause()
        checkpoint()
        workspace.remove(object, animated: true)
        objects.removeAll { $0.id == id }
        selectObject(nil)
        // The object leaves every keyframe it was in, so those keyframes have changed.
        keyframesChanged(animator.removeObject(id))
        documentChanged()
    }

    var canRecolorSelectedObject: Bool { selectedObject?.recipe.canRecolor ?? false }

    /// Recolors the selected object in place. Its name follows if it still has the
    /// automatic name (such as "Red House"); a custom name is kept.
    func recolorSelectedObject(_ color: String?) {
        guard let summary = selectedObject, summary.recipe.canRecolor,
              summary.recipe.colorName != color,
              let object = workspace.object(withID: summary.id)
        else { return }
        let recipe = summary.recipe.recolored(color)
        guard let content = recipe.makeEntity() else { return }

        checkpoint()
        rebuildContent(of: object, with: content, recipe: recipe)
        SceneFeedback.appear(object)
        let name = Self.isAutomaticName(summary.name, for: summary.recipe.defaultName)
            ? uniqueObjectName(recipe.defaultName ?? summary.name, excluding: summary.id)
            : summary.name
        object.name = name
        updateSummary(summary.id) { ObjectSummary(id: $0.id, name: name, source: $0.source, recipe: recipe) }
        workspace.showSelection(on: object)
        documentChanged()
    }

    /// Replaces the selected object with whatever the prompt describes, keeping its
    /// position, size, rotation, and keyframes.
    func replaceSelectedObject() async {
        guard canGenerateObject, let summary = selectedObject else { return }
        let prompt = objectPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        animator.pause()
        isGeneratingObject = true
        objectError = nil
        defer { isGeneratingObject = false }

        do {
            let model = try await generationService.generateObject(prompt: prompt)
            guard let object = workspace.object(withID: summary.id) else { return }
            checkpoint()
            rebuildContent(of: object, with: model.entity, recipe: model.recipe)
            SceneFeedback.appear(object)
            let name = uniqueObjectName(model.displayName, excluding: summary.id)
            object.name = name
            updateSummary(summary.id) { ObjectSummary(id: $0.id, name: name, source: model.source, recipe: model.recipe) }
            workspace.showSelection(on: object)
            objectNote = model.note
            objectPrompt = ""
            documentChanged()
        } catch {
            objectError = error.localizedDescription
        }
    }

    func renameObject(_ id: ObjectID, to name: String) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, let summary = objects.first(where: { $0.id == id }), summary.name != name else { return }
        checkpoint()
        workspace.object(withID: id)?.name = name
        updateSummary(id) { ObjectSummary(id: $0.id, name: name, source: $0.source, recipe: $0.recipe) }
        documentChanged()
    }

    private func updateSummary(_ id: ObjectID, _ change: (ObjectSummary) -> ObjectSummary) {
        guard let index = objects.firstIndex(where: { $0.id == id }) else { return }
        objects[index] = change(objects[index])
    }

    func selectObject(_ id: ObjectID?) {
        if id != selectedObjectID {
            endPoseDrag()
            poseEditor.selectJoint(nil)
        }
        selectedObjectID = id
        workspace.showSelection(on: id.flatMap { workspace.object(withID: $0) })
    }

    func selectObject(containing entity: Entity) {
        if let object = workspace.object(containing: entity) {
            selectObject(workspace.objectID(of: object))
        }
    }

    /// Snap rotation to 15° steps and line objects up with each other while arranging.
    var isSnappingOn: Bool = UserDefaults.standard.object(forKey: "isSnappingOn") as? Bool ?? true {
        didSet { UserDefaults.standard.set(isSnappingOn, forKey: "isSnappingOn") }
    }

    /// A selection handle moved to `point` (world space).
    func dragHandle(_ handle: Entity, to point: SIMD3<Float>) {
        if workspace.dragHandle(handle, to: point, snapping: isSnappingOn) != nil {
            animator.pause()
            checkpoint()
        }
    }

    /// A pinch on the base's edge moved to `point` (world space): spin the base.
    func dragTurntable(to point: SIMD3<Float>) {
        if workspace.dragTurntable(to: point) {
            animator.pause()
            checkpoint()
        }
    }

    func endTurntableDrag() {
        workspace.endTurntableDrag()
        // Saves once any coasting stops.
        sceneEdited()
    }

    func endHandleDrag() {
        workspace.endHandleDrag()
        sceneEdited()
    }

    /// The user grabbed an object: stop playback so it doesn't fight their hands.
    func manipulationBegan(on entity: Entity) {
        animator.pause()
        checkpoint()
        selectObject(containing: entity)
    }

    // MARK: Background

    private(set) var background: BackdropImage?
    private(set) var isLoadingBackground = false
    private(set) var backgroundError: String?

    /// Identifies the stored copy of an imported backdrop; nil for the built-in sky.
    @ObservationIgnored private var backdropFileID: UUID?
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

    /// - Parameter isRestoredFromDisk: True when re-showing the saved backdrop, whose
    ///   stored copy already exists; a new import gets a new stored copy.
    private func apply(_ newBackground: BackdropImage, isRestoredFromDisk: Bool = false) async {
        do {
            try await workspace.setBackdropImage(newBackground.image)
            if newBackground.source == .builtInSky {
                backdropFileID = nil
            } else if !isRestoredFromDisk {
                backdropFileID = UUID()
            }
            background = newBackground
            backgroundError = nil
            documentChanged()
        } catch {
            backgroundError = "That image couldn't be shown as a backdrop."
        }
    }

    // MARK: Capture

    enum CaptureStatus: Hashable {
        case attached(keyframeNumber: Int)
        case libraryOnly
        case retaken(keyframeNumber: Int)
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

    var captureLighting: LightingPreset = .studio {
        didSet {
            documentChanged()
            if captureLighting != oldValue { updateLightingPreview() }
        }
    }

    /// Light the diorama in the headset with the capture lighting, instead of the room's.
    var isLightingPreviewOn: Bool = UserDefaults.standard.bool(forKey: "isLightingPreviewOn") {
        didSet {
            UserDefaults.standard.set(isLightingPreviewOn, forKey: "isLightingPreviewOn")
            updateLightingPreview()
        }
    }

    /// Applies (or removes) the in-headset lighting preview to match the current settings.
    func updateLightingPreview() {
        let preset = isLightingPreviewOn && immersiveSpaceState == .open ? captureLighting : nil
        let camera = viewerCamera()
        Task { await workspace.setLightingPreview(preset, camera: camera) }
    }

    /// A camera where the viewer is standing, looking where they look.
    func viewerCamera() -> CaptureCamera {
        if let head = SpatialTrackingService.shared.viewerTransform {
            return .level(fromHead: head, lens: captureLens)
        }
        // No head tracking (such as in Simulator): look at the base from a standing position.
        return .looking(from: SpatialTrackingService.fallbackViewerPosition,
                        at: workspace.baseAnchor.position(relativeTo: nil), lens: captureLens)
    }

    /// When a keyframe changes, re-render its photos from their saved angles instead of
    /// moving them to the library.
    var keepPhotosInSync: Bool = UserDefaults.standard.object(forKey: "keepPhotosInSync") as? Bool ?? true {
        didSet { UserDefaults.standard.set(keepPhotosInSync, forKey: "keepPhotosInSync") }
    }
    private(set) var isUpdatingPhotos = false

    var captureLens: CaptureLens = .standard {
        didSet {
            workspace.setViewfinder(lens: captureLens, format: captureLook.format)
            documentChanged()
        }
    }

    /// Frame format and film grade for new captures.
    var captureLook: CaptureLook = .standard {
        didSet {
            guard captureLook != oldValue else { return }
            workspace.setViewfinder(lens: captureLens, format: captureLook.format)
            documentChanged()
        }
    }

    /// The viewfinder shows whenever a photo can be lined up: on the Photos tab, on the
    /// Animate tab while a keyframe is selected, and during any countdown.
    var isViewfinderVisible: Bool {
        guard immersiveSpaceState == .open else { return false }
        return selectedTab == .photos
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
                self?.workspace.playInterfaceSound(.tick, gain: -12)
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

        checkpoint()
        // Decide the keyframe at the moment the shutter fires, and make sure it holds
        // exactly what's being photographed.
        let target = captureTarget
        if target != nil { autoSaveSelectedKeyframe() }

        let camera = viewerCamera()

        workspace.flashViewfinder()
        workspace.playInterfaceSound(.shutter, gain: -4)

        // Remember where the backdrop was, so this exact shot can be rendered again later.
        let backdropPose = CodableTransform(Transform(matrix: workspace.backdrop.transformMatrix(relativeTo: nil)))
        do {
            let image = try await CompositionRenderer().render(
                snapshot: CompositionRenderer.snapshot(of: workspace.baseAnchor),
                backdrop: workspace.backdrop,
                backdropPose: nil,
                background: background.image,
                camera: camera,
                lighting: captureLighting,
                look: captureLook
            )
            guard let photo = photos.add(image, lens: captureLens, keyframe: target?.keyframe.id, camera: camera,
                                         lighting: captureLighting, look: captureLook,
                                         backdropPose: backdropPose) else {
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
            exports.invalidate()
            documentChanged()
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
        checkpoint()
        photos.delete(photo)
        if selectedLibraryPhotoID == photo.id { selectedLibraryPhotoID = nil }
        if focusedKeyframePhotoID == photo.id { focusedKeyframePhotoID = nil }
        captureStatus = nil
        exports.invalidate()
        documentChanged()
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
        checkpoint()
        keyframeNotice = nil
        animator.addKeyframe()
        SoundEffects.play(.tick, on: workspace.baseAnchor, gain: -12, pitchVariation: 0)
        focusedKeyframePhotoID = nil
        exports.invalidate()
        documentChanged()
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
            self?.documentChanged()
        }
    }

    /// Saves the scene into the selected keyframe. If its pose changed, its photos no
    /// longer show it, so they're detached (they stay in the library).
    private func autoSaveSelectedKeyframe() {
        let wasOnKeyframe = animator.selectedKeyframeID != nil
        guard let changed = animator.saveSceneToSelectedKeyframe() else { return }
        if !wasOnKeyframe, let keyframe = animator.timeline.keyframe(changed),
           let number = animator.number(of: changed) {
            keyframeNotice = "Added keyframe \(number) at \(keyframe.time.formatted(.number.precision(.fractionLength(1)))) s to hold your change."
            exports.invalidate()
        }
        keyframesChanged([changed])
    }

    /// Keyframes whose content changed. Their photos no longer show them, so they're
    /// re-rendered from their saved angles, or, if that's off or impossible (photos taken
    /// before angles were saved), moved to the library.
    private func keyframesChanged(_ keyframeIDs: [Keyframe.ID]) {
        var jobs: [(photo: CapturedPhoto, snapshot: Entity)] = []
        for id in keyframeIDs {
            let affected = photos.photos(for: id)
            guard !affected.isEmpty else { continue }
            guard keepPhotosInSync, background != nil, let keyframe = animator.timeline.keyframe(id) else {
                detachPhotos(from: id)
                continue
            }
            // One snapshot per keyframe, taken now, before anything else can change.
            let snapshot = workspace.snapshot(at: keyframe.poses, characterPoses: keyframe.characterPoses,
                                              keyframedObjects: animator.timeline.keyframedObjectIDs)
            for photo in affected {
                if photo.camera != nil {
                    jobs.append((photo, snapshot))
                } else {
                    photos.detach(photo)
                }
            }
        }
        guard !jobs.isEmpty else { return }
        Task { await rerender(jobs) }
    }

    private func rerender(_ jobs: [(photo: CapturedPhoto, snapshot: Entity)]) async {
        guard let background else { return }
        isUpdatingPhotos = true
        defer { isUpdatingPhotos = false }

        var updated = 0
        for (photo, snapshot) in jobs {
            // Skip photos deleted or detached since the change.
            guard let camera = photo.camera, photos.photo(photo.id)?.keyframeID == photo.keyframeID else { continue }
            guard let image = try? await CompositionRenderer().render(
                snapshot: snapshot, backdrop: workspace.backdrop, backdropPose: photo.backdropPose?.transform,
                background: background.image, camera: camera, lighting: photo.lighting, look: photo.look),
                  let replacement = photos.replace(photo, with: image)
            else { continue }
            updated += 1
            if focusedKeyframePhotoID == photo.id { focusedKeyframePhotoID = replacement.id }
            if selectedLibraryPhotoID == photo.id { selectedLibraryPhotoID = replacement.id }
        }
        if updated > 0 {
            keyframeNotice = updated == 1 ? "Updated 1 photo to match the change." : "Updated \(updated) photos to match the change."
            exports.invalidate()
            documentChanged()
        }
    }

    var canRetakeFocusedPhoto: Bool {
        focusedKeyframePhoto?.camera != nil && background != nil && !isCapturing && captureCountdown == nil
    }

    /// Re-shoots the selected keyframe's shown photo from exactly the same spot, using the
    /// current lens and lighting. Replaces it in place (undo brings the old one back).
    func retakeFocusedPhoto() async {
        guard canRetakeFocusedPhoto, let background, let photo = focusedKeyframePhoto,
              var camera = photo.camera, let keyframeID = photo.keyframeID else { return }
        checkpoint()
        guard let keyframe = animator.timeline.keyframe(keyframeID),
              let number = animator.number(of: keyframeID) else { return }
        isCapturing = true
        defer { isCapturing = false }

        camera.lens = captureLens
        let snapshot = workspace.snapshot(at: keyframe.poses, characterPoses: keyframe.characterPoses,
                                          keyframedObjects: animator.timeline.keyframedObjectIDs)
        do {
            let image = try await CompositionRenderer().render(
                snapshot: snapshot, backdrop: workspace.backdrop, backdropPose: photo.backdropPose?.transform,
                background: background.image, camera: camera, lighting: captureLighting, look: captureLook)
            guard let replacement = photos.replace(photo, with: image, camera: camera, lighting: captureLighting,
                                                   look: captureLook) else { return }
            focusedKeyframePhotoID = replacement.id
            selectedLibraryPhotoID = replacement.id
            captureStatus = .retaken(keyframeNumber: number)
            exports.invalidate()
            documentChanged()
        } catch {
            captureStatus = .failed(error.localizedDescription)
        }
    }

    private func detachPhotos(from keyframe: Keyframe.ID) {
        let count = photos.photos(for: keyframe).count
        photos.detachPhotos(from: keyframe)
        if count > 0, let number = animator.number(of: keyframe) {
            keyframeNotice = "Keyframe \(number) changed, so its \(count == 1 ? "photo was" : "\(count) photos were") moved to the library."
        }
        if focusedKeyframePhotoID.flatMap({ photos.photo($0) })?.keyframeID == nil { focusedKeyframePhotoID = nil }
        exports.invalidate()
    }

    /// Reorders the shots. Photos stay with their keyframes.
    func moveKeyframe(_ id: Keyframe.ID, to index: Int) {
        let keyframes = animator.timeline.keyframes
        guard let current = keyframes.firstIndex(where: { $0.id == id }), keyframes.indices.contains(index),
              current != index else { return }
        checkpoint()
        animator.moveKeyframe(id, to: index)
        exports.invalidate()
        documentChanged()
    }

    func deleteSelectedKeyframe() {
        guard let id = animator.selectedKeyframeID else { return }
        deleteKeyframe(id)
    }

    /// Deletes a keyframe; its photos move to the library. Its neighbor becomes selected.
    func deleteKeyframe(_ id: Keyframe.ID) {
        checkpoint()
        guard animator.deleteKeyframe(id) else { return }
        photos.detachPhotos(from: id)
        focusedKeyframePhotoID = nil
        keyframeNotice = nil
        exports.invalidate()
        documentChanged()
    }

    /// Copies a keyframe's poses and notes into a new keyframe right after it. Photos stay
    /// with the original.
    func duplicateKeyframe(_ id: Keyframe.ID) {
        checkpoint()
        guard animator.duplicateKeyframe(id) != nil else { return }
        focusedKeyframePhotoID = nil
        keyframeNotice = nil
        exports.invalidate()
        documentChanged()
    }

    /// Call when a keyframe drag starts, so the whole drag undoes in one step.
    func beginRetimingKeyframe() {
        checkpoint()
    }

    /// Moves a keyframe along the timeline while it's dragged.
    func retimeKeyframe(_ id: Keyframe.ID, to time: TimeInterval) {
        if animator.selectedKeyframeID != id { focusedKeyframePhotoID = nil }
        if animator.retimeKeyframe(id, to: time) {
            exports.invalidate()
        }
    }

    func endRetimingKeyframe() {
        documentChanged()
    }

    /// Selects the previous or next keyframe.
    func stepKeyframe(forward: Bool) {
        flushAutoSave()
        keyframeNotice = nil
        animator.step(forward: forward)
        focusedKeyframePhotoID = nil
        captureStatus = nil
    }

    /// The timeline window is showing.
    var isTimelineWindowOpen = false

    func selectKeyframe(_ keyframe: Keyframe) {
        flushAutoSave()
        keyframeNotice = nil
        animator.select(keyframe)
        focusedKeyframePhotoID = nil
        captureStatus = nil
        documentChanged()
    }

    func scrubTimeline(to time: TimeInterval, snapTolerance: TimeInterval = 0.03) {
        flushAutoSave()
        let previous = animator.selectedKeyframeID
        animator.scrub(to: time, snapTolerance: snapTolerance)
        if animator.selectedKeyframeID != previous {
            focusedKeyframePhotoID = nil
            keyframeNotice = nil
        }
    }

    func setPrimaryPhoto(_ photo: CapturedPhoto) {
        checkpoint()
        photos.setPrimary(photo)
        exports.invalidate()
        documentChanged()
    }

    /// Saves a pending scene edit into the selected keyframe now, instead of waiting for
    /// objects to settle.
    func finishSceneEdit() {
        flushAutoSave()
    }

    /// Finishes a pending auto-save right away instead of waiting for objects to settle.
    private func flushAutoSave() {
        guard autoSaveTask != nil else { return }
        autoSaveTask?.cancel()
        autoSaveTask = nil
        autoSaveSelectedKeyframe()
        // The cancelled task would have marked the project changed; do it here instead.
        documentChanged()
    }

    // MARK: Export

    /// Export settings, progress, and the latest exported file.
    let exports = ExportController()

    /// How many keyframes have a primary photo, out of all keyframes.
    var slideshowCoverage: (withPhoto: Int, total: Int) {
        ExportController.coverage(of: animator.timeline.keyframes, photos: photos)
    }

    /// The animatic's camera move: each keyframe's primary photo angle, in timeline order.
    var animaticCameraPath: CameraPath {
        ExportController.cameraPath(for: animator.timeline.keyframes, photos: photos)
    }

    var canExportAnimatic: Bool {
        animator.timeline.canPlay && background != nil && !animaticCameraPath.isEmpty && !exports.isExporting
    }

    /// Exports an MP4 of each keyframe's primary photo, in timeline order.
    func exportSlideshow() async {
        flushAutoSave()
        await exports.exportSlideshow(keyframes: animator.timeline.keyframes, photos: photos, title: projectName)
    }

    /// Renders the animation as video: objects move between keyframes while the camera
    /// glides between each keyframe's photo angle, using the current lighting and look.
    func exportAnimatic() {
        guard canExportAnimatic, let background else { return }
        flushAutoSave()
        animator.pause()
        let timeline = animator.timeline
        // The first photographed keyframe decides where the backdrop sits.
        let backdropPose = timeline.keyframes.lazy
            .compactMap { self.photos.primaryPhoto(for: $0.id) }
            .first { $0.camera != nil }?.backdropPose?.transform
        exports.startAnimatic(.init(timeline: timeline, cameraPath: animaticCameraPath, backdropPose: backdropPose,
                                    background: background.image, lighting: captureLighting, look: captureLook,
                                    title: projectName),
                              workspace: workspace)
    }

    func cancelAnimatic() {
        exports.cancelAnimatic()
    }

    /// Exports a printable PDF with one numbered panel per keyframe.
    func exportStoryboardSheet() {
        flushAutoSave()
        exports.exportStoryboardSheet(keyframes: animator.timeline.keyframes, photos: photos, title: projectName)
    }

    // MARK: Notes

    /// Shot notes for a keyframe. Saved, but typing isn't an undo step.
    func setShotType(_ shotType: ShotType?, forKeyframe id: Keyframe.ID) {
        guard animator.timeline.keyframe(id)?.shotType != shotType else { return }
        checkpoint()
        animator.setShotType(shotType, for: id)
        exports.invalidate()
        documentChanged()
    }

    /// Hold a keyframe's poses until the next keyframe and cut, instead of easing between them.
    func setHolds(_ holds: Bool, forKeyframe id: Keyframe.ID) {
        guard let keyframe = animator.timeline.keyframe(id), keyframe.holds != holds else { return }
        checkpoint()
        animator.setHolds(holds, for: id)
        exports.invalidate()
        documentChanged()
    }

    func setNote(_ note: String, forKeyframe id: Keyframe.ID) {
        animator.setNote(note, for: id)
        exports.invalidate()
        documentChanged()
    }

    // MARK: Undo

    private(set) var undoStack: [ProjectState] = []
    private(set) var redoStack: [ProjectState] = []
    private static let undoLimit = 50
    /// True while a snapshot is being applied, so the changes it makes aren't recorded.
    @ObservationIgnored private var isRestoring = false

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    /// Records the project as it is now, just before an edit, so the edit can be undone.
    private func checkpoint() {
        guard !isRestoring else { return }
        // A pending auto-save belongs to the previous edit; finish it first.
        flushAutoSave()
        let state = currentState()
        if undoStack.last != state {
            undoStack.append(state)
            if undoStack.count > Self.undoLimit { undoStack.removeFirst() }
        }
        redoStack.removeAll()
    }

    func undo() {
        flushAutoSave()
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(currentState())
        restore(previous)
        documentChanged()
    }

    func redo() {
        flushAutoSave()
        guard let next = redoStack.popLast() else { return }
        undoStack.append(currentState())
        restore(next)
        documentChanged()
    }

    // MARK: Snapshots

    /// The project's editable content as a value.
    func currentState() -> ProjectState {
        let objectStates: [ProjectState.Object] = objects.compactMap { summary in
            guard let entity = workspace.object(withID: summary.id) else { return nil }
            return ProjectState.Object(id: summary.id, name: summary.name, source: summary.source,
                                       recipe: summary.recipe, transform: CodableTransform(entity.transform),
                                       isVisible: entity.isEnabled, characterPose: workspace.characterPose(of: entity))
        }
        let generatedBy: ModelSource? = if case .generated(let source) = base.origin { source } else { nil }

        return ProjectState(
            base: .init(name: base.name, recipe: baseRecipe, generatedBy: generatedBy, diameterCentimeters: baseWidth,
                        spinRadians: workspace.baseSpin),
            objects: objectStates,
            keyframes: animator.timeline.keyframes.map(ProjectState.KeyframeState.init),
            selectedKeyframeID: animator.selectedKeyframeID,
            photos: photos.photos.map {
                .init(id: $0.id, takenAt: $0.takenAt, lens: $0.lens, assignment: $0.assignment,
                      camera: $0.camera, lighting: $0.lighting, backdropPose: $0.backdropPose, look: $0.look)
            },
            primaryPhotoIDs: photos.primaryPhotoIDs
        )
    }

    /// Makes the scene, keyframes, and photo library match a snapshot.
    private func restore(_ state: ProjectState) {
        isRestoring = true
        defer { isRestoring = false }

        animator.pause()
        cancelCapture()
        autoSaveTask?.cancel()
        autoSaveTask = nil

        // Base
        if state.base.recipe != baseRecipe, let content = state.base.recipe.makeEntity() {
            workspace.setBase(content, size: Float(state.base.diameterCentimeters) / 100)
            baseRecipe = state.base.recipe
        }
        if let generatedBy = state.base.generatedBy {
            base = BaseSummary(name: state.base.name, origin: .generated(generatedBy))
        } else if case .baseTemplate(let name) = state.base.recipe, let template = BaseTemplate(rawValue: name) {
            base = BaseSummary(name: state.base.name, origin: .template(template))
        }
        baseWidth = state.base.diameterCentimeters
        workspace.setBaseSpin(state.base.spinRadians ?? 0)

        // Objects: remove ones that shouldn't exist, rebuild missing ones, then pose all.
        let wanted = Set(state.objects.map(\.id))
        for summary in objects where !wanted.contains(summary.id) {
            if let entity = workspace.object(withID: summary.id) { workspace.remove(entity) }
        }
        let currentRecipes = Dictionary(uniqueKeysWithValues: objects.map { ($0.id, $0.recipe) })
        var summaries: [ObjectSummary] = []
        for object in state.objects {
            let entity: Entity
            if let existing = workspace.object(withID: object.id) {
                entity = existing
                if currentRecipes[object.id] != object.recipe, let content = object.recipe.makeEntity() {
                    rebuildContent(of: existing, with: content, recipe: object.recipe, pose: object.characterPose)
                }
                existing.name = object.name
            } else if let content = object.recipe.makeEntity() {
                entity = workspace.addObject(content, name: object.name, id: object.id)
            } else {
                continue
            }
            entity.transform = object.transform.transform
            entity.isEnabled = object.isVisible
            if object.recipe.characterKind != nil {
                workspace.setCharacterPose(object.characterPose ?? .neutral, on: entity)
                poseEditor.poseChanged()
            }
            summaries.append(ObjectSummary(id: object.id, name: object.name, source: object.source, recipe: object.recipe))
        }
        objects = summaries
        let stillSelected = selectedObjectID.flatMap { workspace.object(withID: $0) } != nil
        selectObject(stillSelected ? selectedObjectID : nil)

        // Keyframes and photos
        animator.restore(state.keyframes.map(Keyframe.init), selecting: state.selectedKeyframeID)
        photos.restore(state.photos.map { (id: $0.id, assignment: $0.assignment) }, primaries: state.primaryPhotoIDs)

        focusedKeyframePhotoID = nil
        keyframeNotice = nil
        exports.invalidate()
        captureStatus = nil
        if photos.photo(selectedLibraryPhotoID) == nil { selectedLibraryPhotoID = nil }
    }

    // MARK: Saving

    @ObservationIgnored private var saveTask: Task<Void, Never>?

    @ObservationIgnored private var hasUnsavedChanges = false

    /// Set when the open project couldn't be written to disk, and cleared by the next
    /// successful save. The changes stay in memory and are retried on every edit.
    private(set) var saveError: String?

    /// Call after any change worth keeping. Saves shortly after edits stop.
    private func documentChanged() {
        guard !isRestoring else { return }
        hasUnsavedChanges = true
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    /// Writes the project to disk immediately (also used when the app goes to the background).
    /// Returns false if there were changes that couldn't be written; `saveError` says why.
    @discardableResult
    func saveNow() -> Bool {
        saveTask?.cancel()
        saveTask = nil
        flushAutoSave()
        guard hasUnsavedChanges, var info = currentProject else { return true }
        info.modified = .now
        // The list shows the first keyframe's primary photo, else the newest photo.
        info.coverPhotoID = animator.timeline.keyframes.lazy.compactMap { self.photos.primaryPhoto(for: $0.id)?.id }.first
            ?? photos.photos.last?.id
        info.shotCount = animator.timeline.keyframes.count
        let backdrop = background.map {
            ProjectStore.SavedProject.Backdrop(name: $0.name, source: $0.source, fileID: backdropFileID)
        }
        var state = currentState()
        state.photos += missingPhotos
        let project = ProjectStore.SavedProject(state: state, captureLens: captureLens,
                                                captureLighting: captureLighting, captureLook: captureLook,
                                                backdrop: backdrop)
        do {
            try ProjectStore.save(info, project: project, photos: photos.photos,
                                  backdropImage: backdropFileID == nil ? nil : background?.image)
            currentProject = info
            hasUnsavedChanges = false
            saveError = nil
            return true
        } catch {
            saveError = "Your latest changes couldn't be saved. \(error.localizedDescription)"
            return false
        }
    }

}
