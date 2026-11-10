//
//  WorkspaceScene.swift
//  Storyboard3DWorkspace
//

import RealityKit
import UIKit

/// Owns the RealityKit entities for the staged composition.
///
/// Hierarchy:
/// - `root`
///   - `baseAnchor`: sits on the table surface (or floats in front of the viewer)
///     - base content, scaled to the chosen size
///     - `objectsContainer`: raised to the base's top surface
///       - one entity per placed object, each independently movable
///   - `backdrop`: a viewer-facing image plane, positioned by `ViewerFacingBackdropSystem`
///
/// `viewfinder` is separate: it's anchored to the viewer's head, so it's added to the
/// RealityView content on its own rather than under `root`.
final class WorkspaceScene {
    static let selectionIndicatorName = "SelectionIndicator"
    /// Wide enough to feel unlimited, while preventing objects from collapsing to nothing.
    static let scaleRange: ClosedRange<Float> = 0.02...50

    /// Where the base floats when no table is available: about 1 m ahead, near table height.
    private static let floatingBasePosition = SIMD3<Float>(0, 0.85, -1.0)


    let root = Entity()
    let baseAnchor = Entity()
    let objectsContainer = Entity()
    /// Spins the base and everything on it, without disturbing where the base is placed.
    let turntable = Entity()
    private let turntableGrip = Turntable.makeGrip()
    private var turntableDrag: (pointerAngle: Float, time: Date)?
    let backdrop = ModelEntity()
    /// A head-locked frame outlining exactly what a capture will include.
    let viewfinder = AnchorEntity(.head)
    private let viewfinderFrame = Entity()
    /// A white sheet over the frame that blinks when the shutter fires.
    private let viewfinderFlash = ModelEntity()
    /// How far in front of the eyes the viewfinder frame is drawn.
    static let viewfinderDistance: Float = 0.5
    /// Ring, knobs, and toolbar anchor around the selected object.
    let handles = SelectionHandles()
    /// Lines shown while an object snaps into line with another.
    private let guideAlongX = ModelEntity()
    private let guideAlongZ = ModelEntity()
    private var handleDrag: HandleDrag?

    private struct HandleDrag {
        var kind: SelectionHandleComponent.Kind
        var object: Entity
        var startAngle: Float
        var startDistance: Float
        var startOrientation: simd_quatf
        var startYaw: Float
        var startScale: Float
        var lastSnappedStep: Int?
    }

    /// Virtual lights for previewing a capture's lighting on the real table.
    private let previewLights = Entity()
    private let previewEnvironment = Entity()
    private var previewGeneration = 0
    private(set) var isLightingPreviewOn = false
    /// Head-locked, non-spatial source for interface sounds like the shutter and timer.
    let earpiece = AnchorEntity(.head)
    private let earpieceSpeaker = Entity()

    private let baseHolder = Entity()
    private var baseContent: Entity?
    private var baseNominalBounds: BoundingBox?
    private let selectionIndicator = ModelEntity()
    private(set) var objects: [Entity] = []

    /// Keeps RealityView event subscriptions alive.
    var subscriptions: [EventSubscription] = []

    init() {
        root.name = "WorkspaceRoot"

        baseAnchor.name = "BaseAnchor"
        baseAnchor.position = Self.floatingBasePosition
        turntable.name = "Turntable"
        turntable.components.set(TurntableComponent())
        baseAnchor.addChild(turntable)
        baseAnchor.addChild(turntableGrip)
        turntable.addChild(baseHolder)
        objectsContainer.name = "Objects"
        turntable.addChild(objectsContainer)
        root.addChild(baseAnchor)

        selectionIndicator.name = Self.selectionIndicatorName
        var indicatorMaterial = UnlitMaterial(color: .white)
        indicatorMaterial.blending = .transparent(opacity: 0.4)
        selectionIndicator.model = ModelComponent(mesh: .generateCylinder(height: 0.0015, radius: 1),
                                                  materials: [indicatorMaterial])

        previewLights.name = "PreviewLights"
        previewEnvironment.name = "PreviewEnvironment"
        root.addChild(previewLights)
        root.addChild(previewEnvironment)
        root.addChild(handles.root)

        var guideMaterial = UnlitMaterial(color: UIColor(red: 0.45, green: 0.85, blue: 1, alpha: 1))
        guideMaterial.blending = .transparent(opacity: 0.9)
        for guide in [guideAlongX, guideAlongZ] {
            guide.name = "AlignmentGuide"
            guide.model = ModelComponent(mesh: .generateBox(size: 1), materials: [guideMaterial])
            guide.isEnabled = false
            root.addChild(guide)
        }

        backdrop.name = "Backdrop"
        backdrop.isEnabled = false
        backdrop.components.set(ViewerFacingBackdropComponent(target: baseAnchor))
        root.addChild(backdrop)

        viewfinder.name = "Viewfinder"
        viewfinder.isEnabled = false
        viewfinder.addChild(viewfinderFrame)
        viewfinderFlash.components.set(OpacityComponent(opacity: 0))
        viewfinder.addChild(viewfinderFlash)
        setViewfinder(lens: .standard, format: .widescreen)

        earpiece.name = "Earpiece"
        earpieceSpeaker.components.set(AmbientAudioComponent(gain: 0))
        earpiece.addChild(earpieceSpeaker)
    }

    /// Plays an interface sound at the viewer's head.
    func playInterfaceSound(_ effect: SoundEffect, gain: Double = 0) {
        SoundEffects.play(effect, on: earpieceSpeaker, gain: gain, pitchVariation: 0)
    }

    // MARK: Viewfinder

    func setViewfinderVisible(_ isVisible: Bool) {
        viewfinder.isEnabled = isVisible
    }

    /// Half the frame's width and height, at `viewfinderDistance`.
    static func viewfinderHalfSize(for lens: CaptureLens) -> SIMD2<Float> {
        let distance = viewfinderDistance
        return [distance * tan(lens.horizontalFOV / 2), distance * tan(lens.verticalFOV / 2)]
    }

    /// Redraws the frame for the lens's field of view and the format's letterbox, like a
    /// cinema camera's monitor: a crisp outline with corner marks, shaded matte bars,
    /// rule-of-thirds guides inside the picture area, and a small center cross.
    func setViewfinder(lens: CaptureLens, format: FrameFormat) {
        viewfinderFrame.children.removeAll()
        let distance = Self.viewfinderDistance
        let half = Self.viewfinderHalfSize(for: lens)
        let width = half.x * 2
        let height = half.y * 2
        let matte = height * format.matteFraction
        let pictureHalfHeight = half.y - matte

        func material(_ color: UIColor, opacity: Float) -> UnlitMaterial {
            var material = UnlitMaterial(color: color)
            material.blending = .transparent(opacity: .init(floatLiteral: opacity))
            return material
        }
        func bar(_ size: SIMD2<Float>, at position: SIMD2<Float>, _ material: UnlitMaterial, depth: Float = 0) {
            let entity = ModelEntity(mesh: .generatePlane(width: size.x, height: size.y), materials: [material])
            entity.position = [position.x, position.y, -distance - depth]
            viewfinderFrame.addChild(entity)
        }

        // Outline.
        let outline = material(.white, opacity: 0.55)
        let line: Float = 0.0008
        bar([width + line, line], at: [0, half.y], outline)
        bar([width + line, line], at: [0, -half.y], outline)
        bar([line, height + line], at: [-half.x, 0], outline)
        bar([line, height + line], at: [half.x, 0], outline)

        // Corner marks, bolder than the outline so the frame reads at a glance.
        let corner = material(.white, opacity: 0.95)
        let thick: Float = 0.0022
        let reach = width * 0.06
        for sx: Float in [-1, 1] {
            for sy: Float in [-1, 1] {
                bar([reach, thick], at: [sx * (half.x - reach / 2), sy * half.y], corner)
                bar([thick, reach], at: [sx * half.x, sy * (half.y - reach / 2)], corner)
            }
        }

        // Letterbox bars, shaded so the picture area stands out without hiding the scene.
        if matte > 0 {
            let shade = material(.black, opacity: 0.45)
            bar([width, matte], at: [0, half.y - matte / 2], shade, depth: 0.0005)
            bar([width, matte], at: [0, -half.y + matte / 2], shade, depth: 0.0005)
            let edge = material(.white, opacity: 0.35)
            bar([width, line], at: [0, pictureHalfHeight], edge)
            bar([width, line], at: [0, -pictureHalfHeight], edge)
        }

        // Rule-of-thirds guides within the picture area.
        let guide = material(.white, opacity: 0.18)
        let hairline: Float = 0.0005
        for third: Float in [-1, 1] {
            bar([hairline, pictureHalfHeight * 2], at: [third * width / 6, 0], guide)
            bar([width, hairline], at: [0, third * pictureHalfHeight / 3], guide)
        }

        // Center cross.
        let cross = material(.white, opacity: 0.6)
        let arm = width * 0.018
        bar([arm, hairline * 2], at: [0, 0], cross)
        bar([hairline * 2, arm], at: [0, 0], cross)

        viewfinderFlash.model = ModelComponent(mesh: .generatePlane(width: width, height: height),
                                               materials: [UnlitMaterial(color: .white)])
        viewfinderFlash.position = [0, 0, -distance + 0.001]
    }

    /// A quick white blink across the frame, like a camera's shutter.
    func flashViewfinder() {
        guard SceneFeedback.isEnabled else { return }
        let fade = FromToByAnimation<Float>(from: 0.65, to: 0, duration: 0.4, timing: .easeOut, bindTarget: .opacity)
        if let animation = try? AnimationResource.generate(with: fade) {
            viewfinderFlash.playAnimation(animation)
        }
    }

    // MARK: Lighting preview

    /// Lights the staged scene in the headset the way a capture will be lit: the preset's
    /// key, fill, and rim lights (aimed from `camera`) and its sky as ambient light,
    /// replacing the room's lighting on the diorama. Nil turns the preview off.
    func setLightingPreview(_ preset: LightingPreset?, camera: CaptureCamera) async {
        previewGeneration += 1
        let generation = previewGeneration
        guard let preset else {
            previewLights.children.removeAll()
            previewEnvironment.components.remove(ImageBasedLightComponent.self)
            isLightingPreviewOn = false
            refreshLightingReceivers()
            return
        }

        let resource = try? await EnvironmentResource(equirectangular: CompositionRenderer.makeEnvironment(for: preset))
        // A newer request arrived while this one was loading.
        guard generation == previewGeneration else { return }

        previewLights.children.removeAll()
        let center = baseAnchor.position(relativeTo: nil)
        for light in CompositionRenderer.lights(for: preset, camera: camera, center: center) {
            previewLights.addChild(light)
        }
        if let resource {
            previewEnvironment.components.set(ImageBasedLightComponent(source: .single(resource),
                                                                       intensityExponent: preset.environmentExposure))
        }
        isLightingPreviewOn = true
        refreshLightingReceivers()
    }

    /// Points every model in the staged scene at the preview's ambient light, or back to
    /// the room's. Called whenever content changes while the preview is on.
    func refreshLightingReceivers() {
        func apply(_ entity: Entity) {
            if entity.components.has(ModelComponent.self) {
                if isLightingPreviewOn {
                    entity.components.set(ImageBasedLightReceiverComponent(imageBasedLight: previewEnvironment))
                } else {
                    entity.components.remove(ImageBasedLightReceiverComponent.self)
                }
            }
            entity.children.forEach(apply)
        }
        apply(baseAnchor)
    }

    // MARK: Base placement

    /// Places the base on a table surface, turned to match the table's edges.
    func placeBase(atSurface originFromSurface: simd_float4x4) {
        let position = SIMD3(originFromSurface.columns.3.x, originFromSurface.columns.3.y, originFromSurface.columns.3.z)
        var edge = SIMD3(originFromSurface.columns.0.x, 0, originFromSurface.columns.0.z)
        if simd_length(edge) < 1e-4 { edge = [1, 0, 0] }
        let yaw = atan2(-edge.z, edge.x)
        baseAnchor.transform = Transform(scale: .one, rotation: simd_quatf(angle: yaw, axis: [0, 1, 0]), translation: position)
    }

    func placeBaseFloating() {
        baseAnchor.transform = Transform(scale: .one, rotation: simd_quatf(), translation: Self.floatingBasePosition)
    }

    // MARK: Base content

    /// Replaces the base platform. `content` may be any size; it's scaled so its widest
    /// extent matches `size` (the diameter), centered, and rested on the anchor.
    func setBase(_ content: Entity, size: Float) {
        baseContent?.removeFromParent()
        baseContent = content
        baseNominalBounds = content.visualBounds(relativeTo: nil)
        baseHolder.addChild(content)
        setBaseSize(size)
        if isLightingPreviewOn { refreshLightingReceivers() }
    }

    func setBaseSize(_ size: Float) {
        guard let content = baseContent, let bounds = baseNominalBounds else { return }
        let footprint = max(bounds.extents.x, bounds.extents.z, 1e-4)
        let scale = size / footprint
        content.scale = SIMD3(repeating: scale)
        content.position = [-bounds.center.x * scale, -bounds.min.y * scale, -bounds.center.z * scale]
        // Objects stand on the base's declared surface, not on its tallest detail.
        let surface = content.components[BaseSurfaceComponent.self]?.height ?? bounds.max.y
        let height = (surface - bounds.min.y) * scale
        objectsContainer.position = [0, height, 0]
        // The grip is modeled for a 1 m base; match its size and height to this one.
        turntableGrip.scale = [size, height / 0.04, size]
        objectsContainer.components.set(GravitySurfaceComponent(baseRadius: size / 2, baseHeight: height))
    }

    // MARK: Objects

    /// Adds a generated object to the base and returns the entity the user manipulates.
    @discardableResult
    func addObject(_ content: Entity, name: String, id: ObjectID = ObjectID()) -> Entity {
        let object = Entity()
        object.name = name
        object.components.set(PlacedObjectComponent(id: id))
        object.addChild(content)
        object.position = openSpot()
        objectsContainer.addChild(object)
        configureInteraction(for: object)
        objects.append(object)
        if isLightingPreviewOn { refreshLightingReceivers() }
        return object
    }

    @discardableResult
    func duplicate(_ object: Entity, id: ObjectID = ObjectID()) -> Entity {
        // Keep the selection ring out of the copy.
        let ringParent = selectionIndicator.parent
        selectionIndicator.removeFromParent()

        let copy = object.clone(recursive: true)
        copy.name = object.name
        copy.transform = object.transform
        // Offset sideways relative to the base, so the copy is visible next to the original.
        copy.position += SIMD3<Float>(0.05, 0, 0.03)
        copy.isEnabled = true
        copy.components.set(PlacedObjectComponent(id: id))
        objectsContainer.addChild(copy)
        configureInteraction(for: copy)
        objects.append(copy)

        ringParent?.addChild(selectionIndicator)
        if isLightingPreviewOn { refreshLightingReceivers() }
        return copy
    }

    /// Swaps an object's geometry (new color, or regenerated) while keeping its identity,
    /// pose, and keyframes.
    func replaceContent(of object: Entity, with content: Entity) {
        for child in object.children where child.name != Self.selectionIndicatorName {
            child.removeFromParent()
        }
        object.addChild(content)
        configureInteraction(for: object)
        if isLightingPreviewOn { refreshLightingReceivers() }
    }

    /// - Parameter animated: Shrink the object away instead of removing it instantly.
    func remove(_ object: Entity, animated: Bool = false) {
        if selectionIndicator.parent == object { selectionIndicator.removeFromParent() }
        if handles.target == object { handles.setTarget(nil) }
        if animated { SceneFeedback.vanish(object) }
        object.removeFromParent()
        objects.removeAll { $0 == object }
    }

    func object(withID id: ObjectID) -> Entity? {
        objects.first { objectID(of: $0) == id }
    }

    func objectID(of object: Entity) -> ObjectID? {
        object.components[PlacedObjectComponent.self]?.id
    }

    /// The placed object that `entity` belongs to, if any.
    func object(containing entity: Entity) -> Entity? {
        var current: Entity? = entity
        while let candidate = current {
            if objects.contains(candidate) { return candidate }
            current = candidate.parent
        }
        return nil
    }

    func showSelection(on object: Entity?) {
        selectionIndicator.removeFromParent()
        handles.setTarget(object)
        guard let object else { return }
        // The collision box reflects the object's resting size even while it's popping in.
        let bounds = object.components[CollisionComponent.self]?.shapes.first?.bounds
            ?? object.visualBounds(relativeTo: object, excludeInactive: true)
        let radius = max(bounds.extents.x, bounds.extents.z) * 0.65 + 0.006
        selectionIndicator.components.remove(ScaleSpringComponent.self)
        selectionIndicator.scale = [radius, 1, radius]
        selectionIndicator.position = [bounds.center.x, bounds.min.y + 0.001, bounds.center.z]
        object.addChild(selectionIndicator)
        SceneFeedback.spring(selectionIndicator, from: [0.7, 1, 0.7], stiffness: 300, damping: 18)
    }

    func clampScale(of entity: Entity) {
        let scale = entity.scale.x
        let clamped = min(max(scale, Self.scaleRange.lowerBound), Self.scaleRange.upperBound)
        if abs(clamped - scale) > .ulpOfOne {
            entity.scale = SIMD3(repeating: clamped)
        }
    }

    /// Current poses of every visible placed object, relative to the base.
    func currentPoses() -> [ObjectID: Transform] {
        Dictionary(uniqueKeysWithValues: objects.filter(\.isEnabled).compactMap { object in
            objectID(of: object).map { ($0, object.transform) }
        })
    }

    /// Poses objects for a moment in the animation. Keyframed objects without a pose are
    /// hidden; objects that aren't in any keyframe are left alone.
    func apply(_ poses: [ObjectID: Transform], keyframedObjects: Set<ObjectID>) {
        for object in objects {
            guard let id = objectID(of: object) else { continue }
            if let pose = poses[id] {
                object.transform = pose
                object.isEnabled = true
            } else if keyframedObjects.contains(id) {
                object.isEnabled = false
            }
        }
    }

    /// A render-ready copy of the scene posed at a keyframe. The live objects are posed,
    /// copied, and put back within the same moment, so nothing visibly moves.
    func snapshot(at poses: [ObjectID: Transform], keyframedObjects: Set<ObjectID>) -> Entity {
        let saved = objects.map { ($0, $0.transform, $0.isEnabled) }
        apply(poses, keyframedObjects: keyframedObjects)
        let snapshot = CompositionRenderer.snapshot(of: baseAnchor)
        for (object, transform, isEnabled) in saved {
            object.transform = transform
            object.isEnabled = isEnabled
        }
        return snapshot
    }

    /// True when nothing is being held, falling, or spinning, so poses are final.
    var isSettled: Bool {
        let spin = turntable.components[TurntableComponent.self]
        guard spin.map({ !$0.isDragging && $0.velocity == 0 }) ?? true else { return false }
        return objects.filter(\.isEnabled).allSatisfy { object in
            guard let gravity = object.components[ObjectGravityComponent.self] else { return true }
            return !gravity.isHeld && gravity.fallSpeed == 0
        }
    }

    /// One collision box around the whole object so the system's manipulation gestures
    /// (move, rotate, two-handed scale) treat it as a single piece.
    private func configureInteraction(for object: Entity) {
        // Measure the geometry only, never the selection ring.
        let bounds = SceneFeedback.content(of: object)
            .map { $0.visualBounds(relativeTo: object, excludeInactive: true) }
            .filter { !$0.isEmpty }
            .reduce(nil as BoundingBox?) { total, next in total.map { $0.union(next) } ?? next }
            ?? object.visualBounds(relativeTo: object, excludeInactive: true)
        let size = simd_max(bounds.extents, SIMD3(repeating: 0.01))
        let shape = ShapeResource.generateBox(size: size).offsetBy(translation: bounds.center)
        ManipulationComponent.configureEntity(
            object,
            hoverEffect: .spotlight(.default),
            allowedInputTypes: .all,
            collisionShapes: [shape]
        )
        if var manipulation = object.components[ManipulationComponent.self] {
            manipulation.releaseBehavior = .stay
            object.components.set(manipulation)
        }
        object.components.set(ObjectGravityComponent())
    }

    func setHeld(_ isHeld: Bool, for entity: Entity) {
        guard let object = object(containing: entity),
              var gravity = object.components[ObjectGravityComponent.self]
        else { return }
        gravity.isHeld = isHeld
        gravity.fallSpeed = 0
        object.components.set(gravity)
    }

    func keepAboveSurface(_ entity: Entity) {
        guard let object = object(containing: entity) else { return }
        ObjectGravitySystem.keepAboveSurface(object)
    }

    /// A spot near the middle of the base that isn't already taken.
    private func openSpot() -> SIMD3<Float> {
        let spacing: Float = 0.07
        var candidates: [SIMD2<Float>] = [[0, 0]]
        // Square rings of grid spots, working outward from the center.
        for ring in 1...4 {
            for x in -ring...ring {
                for z in -ring...ring where max(abs(x), abs(z)) == ring {
                    candidates.append([Float(x) * spacing, Float(z) * spacing])
                }
            }
        }
        // Stay inside the base, whatever size it currently is.
        let radius = objectsContainer.components[GravitySurfaceComponent.self]?.baseRadius ?? 0.3
        let reach = max(radius - 0.04, 0)
        let taken = objects.map { SIMD2($0.position.x, $0.position.z) }
        let spot = candidates.first { candidate in
            simd_length(candidate) <= reach
                && taken.allSatisfy { simd_distance($0, candidate) > spacing * 0.7 }
        } ?? [0, 0]
        return [spot.x, 0, spot.y]
    }

    // MARK: Turntable

    /// The base's spin in radians.
    var baseSpin: Float { turntable.components[TurntableComponent.self]?.angle ?? 0 }

    /// Sets the spin directly (restoring a project or undo), stopping any coasting.
    func setBaseSpin(_ angle: Float) {
        var spin = turntable.components[TurntableComponent.self] ?? TurntableComponent()
        spin.angle = angle
        spin.velocity = 0
        spin.isDragging = false
        spin.lastDetent = Int((angle / TurntableComponent.detent).rounded(.down))
        turntable.orientation = simd_quatf(angle: angle, axis: [0, 1, 0])
        turntable.components.set(spin)
        turntableDrag = nil
    }

    /// Spins the base to follow a pinch on its edge at `point` (world space).
    /// - Returns: True on the first update of a drag, so the caller can record undo.
    @discardableResult
    func dragTurntable(to point: SIMD3<Float>) -> Bool {
        guard var spin = turntable.components[TurntableComponent.self] else { return false }
        let center = baseAnchor.position(relativeTo: nil)
        let offset = point - center
        let pointerAngle = atan2(-offset.z, offset.x)
        let now = Date.now

        guard let last = turntableDrag else {
            spin.isDragging = true
            spin.velocity = 0
            turntable.components.set(spin)
            turntableDrag = (pointerAngle, now)
            SoundEffects.play(.grab, on: turntableGrip, gain: -16)
            return true
        }

        var delta = pointerAngle - last.pointerAngle
        delta = atan2(sin(delta), cos(delta))
        spin.angle += delta
        // Track recent speed so letting go mid-swipe keeps the spin going.
        let elapsed = Float(now.timeIntervalSince(last.time))
        if elapsed > 0.001 {
            let instant = min(max(delta / elapsed, -TurntableComponent.maxVelocity), TurntableComponent.maxVelocity)
            spin.velocity = spin.velocity * 0.6 + instant * 0.4
        }
        Turntable.apply(&spin, to: turntable)
        turntable.components.set(spin)
        turntableDrag = (pointerAngle, now)
        return false
    }

    /// Lets go of the base; a quick swipe coasts to a stop.
    func endTurntableDrag() {
        guard var spin = turntable.components[TurntableComponent.self] else { return }
        // A slow release, or one after holding still, just stops.
        let heldStill = turntableDrag.map { Date.now.timeIntervalSince($0.time) > 0.12 } ?? true
        if heldStill || abs(spin.velocity) < 0.4 || !SceneFeedback.isEnabled { spin.velocity = 0 }
        spin.isDragging = false
        turntable.components.set(spin)
        turntableDrag = nil
    }

    // MARK: Handles

    /// Turns or resizes the selected object as its handle is dragged to `point` (world space).
    /// - Returns: The object, on the first update of a drag, so the caller can record undo.
    @discardableResult
    func dragHandle(_ handle: Entity, to point: SIMD3<Float>, snapping: Bool) -> Entity? {
        guard let kind = handle.components[SelectionHandleComponent.self]?.kind, let object = handles.target else { return nil }
        let pivot = handles.pivot
        let offset = point - pivot
        let angle = atan2(-offset.z, offset.x)

        // The first update only starts the drag, so undo records the pose before any change.
        guard var drag = handleDrag, drag.object == object else {
            handleDrag = HandleDrag(kind: kind, object: object, startAngle: angle,
                                    startDistance: max(simd_length(offset), 0.005),
                                    startOrientation: object.orientation, startYaw: Self.yaw(of: object.orientation),
                                    startScale: object.scale.x)
            SoundEffects.play(.grab, on: object, gain: -14)
            return object
        }

        switch drag.kind {
        case .rotate:
            var delta = angle - drag.startAngle
            delta = atan2(sin(delta), cos(delta))
            if snapping {
                // Snap the absolute heading (relative to the base) to 15° steps, ticking on each step.
                let step = Float.pi / 12
                let steps = Int(((drag.startYaw + delta) / step).rounded())
                delta = Float(steps) * step - drag.startYaw
                if drag.lastSnappedStep != steps {
                    if drag.lastSnappedStep != nil { SoundEffects.play(.tick, on: object, gain: -24, pitchVariation: 0) }
                    drag.lastSnappedStep = steps
                }
            }
            object.orientation = simd_quatf(angle: delta, axis: [0, 1, 0]) * drag.startOrientation
        case .scale:
            let ratio = simd_length(offset) / drag.startDistance
            let scale = min(max(drag.startScale * ratio, Self.scaleRange.lowerBound), Self.scaleRange.upperBound)
            object.scale = SIMD3(repeating: scale)
        }
        ObjectGravitySystem.keepAboveSurface(object)
        handleDrag = drag
        return nil
    }

    func endHandleDrag() {
        handleDrag = nil
    }

    // MARK: Snapping

    /// While an object is moved: turns it to the nearest 15° (when upright) and lines its
    /// center up with any other object it's close to on either axis, showing a guide line.
    func applySnapping(to entity: Entity) {
        guard let object = object(containing: entity) else { return }

        let up = object.orientation.act([0, 1, 0])
        if up.y > 0.985 {
            let step = Float.pi / 12
            let snapped = (Self.yaw(of: object.orientation) / step).rounded() * step
            object.orientation = simd_quatf(angle: snapped, axis: [0, 1, 0])
        }

        let threshold: Float = 0.008
        var alignX: (Entity, Float)?
        var alignZ: (Entity, Float)?
        for other in objects where other != object && other.isEnabled {
            let dx = abs(other.position.x - object.position.x)
            let dz = abs(other.position.z - object.position.z)
            if dx < threshold, dx < (alignX?.1 ?? .infinity) { alignX = (other, dx) }
            if dz < threshold, dz < (alignZ?.1 ?? .infinity) { alignZ = (other, dz) }
        }
        if let (other, _) = alignX { object.position.x = other.position.x }
        if let (other, _) = alignZ { object.position.z = other.position.z }

        showGuide(guideAlongZ, from: object, to: alignX?.0, axis: 2)
        showGuide(guideAlongX, from: object, to: alignZ?.0, axis: 0)
    }

    func hideGuides() {
        guideAlongX.isEnabled = false
        guideAlongZ.isEnabled = false
    }

    /// A thin line on the base surface through both objects, along the given container axis.
    private func showGuide(_ guide: ModelEntity, from object: Entity, to other: Entity?, axis: Int) {
        guard let other else {
            guide.isEnabled = false
            return
        }
        let a = object.position, b = other.position
        let low = min(a[axis], b[axis]) - 0.03
        let high = max(a[axis], b[axis]) + 0.03
        var center = a
        center[axis] = (low + high) / 2
        center.y = 0.0012
        var size = SIMD3<Float>(0.0014, 0.0008, 0.0014)
        size[axis] = high - low

        guide.transform = Transform(matrix: objectsContainer.transformMatrix(relativeTo: nil))
        guide.position = objectsContainer.convert(position: center, to: nil)
        guide.scale = size
        guide.isEnabled = true
    }

    /// Heading about the vertical axis, in radians.
    private static func yaw(of orientation: simd_quatf) -> Float {
        let x = orientation.act([1, 0, 0])
        return atan2(-x.z, x.x)
    }

    // MARK: Backdrop

    func setBackdropImage(_ image: CGImage) async throws {
        let texture = try await TextureResource(image: image, withName: nil, options: .init(semantic: .color))

        // Unlit and not tone-mapped, so the image shows its true colors like a printed backdrop.
        var material = UnlitMaterial(applyPostProcessToneMap: false)
        material.color = .init(texture: .init(texture))

        let size = BackdropLayout.size(forAspect: Float(image.width) / Float(max(image.height, 1)))
        backdrop.model = ModelComponent(mesh: .generatePlane(width: size.x, height: size.y), materials: [material])
        if var layout = backdrop.components[ViewerFacingBackdropComponent.self] {
            layout.lift = BackdropLayout.lift(forHeight: size.y)
            backdrop.components.set(layout)
        }
        backdrop.isEnabled = true
    }
}
