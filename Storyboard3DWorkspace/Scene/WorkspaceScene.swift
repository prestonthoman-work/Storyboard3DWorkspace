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
    static let onionSkinName = "OnionSkin"
    static let moveGripName = "BaseMoveGrip"
    /// Wide enough to feel unlimited, while preventing objects from collapsing to nothing.
    static let scaleRange: ClosedRange<Float> = 0.02...50



    let root = Entity()
    let baseAnchor = Entity()
    let objectsContainer = Entity()
    /// Spins the base and everything on it, without disturbing where the base is placed.
    let turntable = Entity()
    private let turntableGrip = Turntable.makeGrip()
    /// A brass pull at the base's edge, turned toward the viewer: drag it to slide the whole set.
    /// Never in photos.
    let moveGrip = WorkspaceScene.makeMoveGrip()
    private let moveGripPivot = Entity()
    private var baseDrag: (startPoint: SIMD3<Float>, startPosition: SIMD3<Float>, keepsHeight: Bool)?
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
    /// Floating name tags. Outside the base, so they're never in a capture.
    let labelsRoot = Entity()
    /// Eyeline guides for characters. Outside the staged scene, so they never appear in photos.
    let eyelinesRoot = Entity()
    /// Translucent ghosts of the previous keyframe. Inside the objects container so they
    /// share its space, but stripped from every capture.
    let onionRoot = Entity()
    /// What the ghosts currently show, so they're only rebuilt when it changes.
    var onionSkinKey: OnionSkinKey?
    /// Lines shown while an object snaps into line with another.
    private let guideAlongX = ModelEntity()
    private let guideAlongZ = ModelEntity()
    /// Where a moving object will land if let go now, when that's a snapped spot.
    private let snapFootprint = ModelEntity()
    private var handleDrag: HandleDrag?
    /// The object being moved by hand, and its position snapping.
    private var move: (object: Entity, snapper: AlignmentSnapper)?

    private struct HandleDrag {
        var kind: SelectionHandleComponent.Kind
        var object: Entity
        /// The pointer's angle around the ring when the drag began.
        var startAngle: Float
        var startDistance: Float
        /// The object's transform when the drag began; every update starts again from it,
        /// so nothing accumulates or drifts.
        var startTransform: Transform
        /// What the object turns about: its center (world space), and the ring's axis.
        var pivot: SIMD3<Float>
        /// The center of the ring being dragged (world space), which the pointer's angle is
        /// measured around, so the object follows the hand around the ring as drawn.
        var ringCenter: SIMD3<Float>
        var axis: SIMD3<Float>
        /// For the tilt ring: the ring's plane, as forward and up directions (world space).
        var planeForward: SIMD3<Float>
        var planeUp: SIMD3<Float>
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
        // Beside the main panel, not behind it (see `PanelClearance`).
        baseAnchor.position = PanelClearance.floatingPosition(radius: baseRadius)
        turntable.name = "Turntable"
        turntable.components.set(TurntableComponent())
        baseAnchor.addChild(turntable)
        baseAnchor.addChild(turntableGrip)
        moveGripPivot.name = "MoveGripPivot"
        moveGripPivot.addChild(moveGrip)
        baseAnchor.addChild(moveGripPivot)
        turntable.addChild(baseHolder)
        objectsContainer.name = "Objects"
        turntable.addChild(objectsContainer)
        root.addChild(baseAnchor)

        selectionIndicator.name = Self.selectionIndicatorName
        selectionIndicator.model = ModelComponent(
            mesh: .generateCylinder(height: 0.0015, radius: 1),
            materials: [InteractionStyle.unlit(InteractionStyle.selection,
                                               opacity: InteractionStyle.selectionDiscOpacity(isHeld: false))])

        previewLights.name = "PreviewLights"
        previewEnvironment.name = "PreviewEnvironment"
        root.addChild(previewLights)
        root.addChild(previewEnvironment)
        root.addChild(handles.root)
        labelsRoot.name = "ObjectLabels"
        root.addChild(labelsRoot)
        eyelinesRoot.name = "Eyelines"
        eyelinesRoot.components.set(EyelineGuidesComponent(isOn: false, characters: objectsContainer))
        root.addChild(eyelinesRoot)
        onionRoot.name = Self.onionSkinName
        objectsContainer.addChild(onionRoot)

        // Snap previews: a faint line through both centers, and a faint outline where the
        // object will land if let go now.
        let guideMaterial = InteractionStyle.unlit(InteractionStyle.selection, opacity: 0.6)
        for guide in [guideAlongX, guideAlongZ] {
            guide.name = "AlignmentGuide"
            guide.model = ModelComponent(mesh: .generateBox(size: 1), materials: [guideMaterial])
            guide.isEnabled = false
            root.addChild(guide)
        }
        var footprint = MeshBuilder()
        footprint.addRing(innerRadius: 0.92, outerRadius: 1, segments: 64)
        snapFootprint.name = "SnapFootprint"
        if let mesh = footprint.makeMesh(named: "SnapFootprint") {
            snapFootprint.model = ModelComponent(mesh: mesh, materials: [InteractionStyle.unlit(InteractionStyle.selection, opacity: 0.45)])
        }
        snapFootprint.isEnabled = false
        root.addChild(snapFootprint)

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

    // MARK: Eyelines

    func setEyelinesVisible(_ isVisible: Bool) {
        eyelinesRoot.components[EyelineGuidesComponent.self]?.isOn = isVisible
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

    /// Redraws the frame for the lens's field of view and the format's bars, like a
    /// cinema camera's monitor: a crisp outline with corner marks, shaded matte bars,
    /// rule-of-thirds guides inside the picture area, and a small center cross.
    func setViewfinder(lens: CaptureLens, format: FrameFormat) {
        viewfinderFrame.children.removeAll()
        let distance = Self.viewfinderDistance
        let half = Self.viewfinderHalfSize(for: lens)
        let width = half.x * 2
        let height = half.y * 2
        let matte = height * format.matteFraction
        let pillar = width * format.pillarFraction
        let pictureHalfHeight = half.y - matte
        let pictureHalfWidth = half.x - pillar

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
        // Pillarbox bars for formats narrower than 16:9.
        if pillar > 0 {
            let shade = material(.black, opacity: 0.45)
            bar([pillar, height], at: [half.x - pillar / 2, 0], shade, depth: 0.0005)
            bar([pillar, height], at: [-half.x + pillar / 2, 0], shade, depth: 0.0005)
            let edge = material(.white, opacity: 0.35)
            bar([line, height], at: [pictureHalfWidth, 0], edge)
            bar([line, height], at: [-pictureHalfWidth, 0], edge)
        }

        // Rule-of-thirds guides within the picture area.
        let guide = material(.white, opacity: 0.18)
        let hairline: Float = 0.0005
        for third: Float in [-1, 1] {
            bar([hairline, pictureHalfHeight * 2], at: [third * pictureHalfWidth / 3, 0], guide)
            bar([pictureHalfWidth * 2, hairline], at: [0, third * pictureHalfHeight / 3], guide)
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
        aimMoveGripAtViewer()
    }

    func placeBaseFloating() {
        baseAnchor.transform = Transform(scale: .one, rotation: simd_quatf(),
                                         translation: PanelClearance.floatingPosition(radius: baseRadius))
        aimMoveGripAtViewer()
    }

    // MARK: Moving the base

    /// Slides the base to follow a pinch on its move handle at `point` (world space). On a table
    /// it slides along the tabletop; floating, it moves freely.
    /// - Returns: True on the first update of a drag.
    @discardableResult
    func dragBase(to point: SIMD3<Float>, keepingHeight: Bool) -> Bool {
        guard let drag = baseDrag else {
            baseDrag = (point, baseAnchor.position(relativeTo: nil), keepingHeight)
            SoundEffects.play(.grab, on: moveGrip, gain: -16)
            return true
        }
        var offset = point - drag.startPoint
        if drag.keepsHeight { offset.y = 0 }
        baseAnchor.setPosition(drag.startPosition + offset, relativeTo: nil)
        return false
    }

    func endBaseDrag() {
        baseDrag = nil
        aimMoveGripAtViewer()
    }

    /// Turns the move handle to the side of the base nearest the viewer, so it's always in reach.
    func aimMoveGripAtViewer() {
        let viewer = SpatialTrackingService.shared.viewerPosition
        let local = baseAnchor.convert(position: viewer, from: nil)
        guard simd_length(SIMD2(local.x, local.z)) > 0.05 else { return }
        moveGripPivot.orientation = simd_quatf(angle: atan2(local.x, local.z), axis: [0, 1, 0])
    }

    private static func makeMoveGrip() -> ModelEntity {
        let grip = ModelEntity()
        grip.name = moveGripName
        let brass = LowPoly.material(UIColor(red: 0.74, green: 0.6, blue: 0.38, alpha: 1), .metal)
        // A drawer pull: a bar on two short posts, standing off the plinth's edge.
        let bar = ModelEntity(mesh: .generateBox(size: [0.06, 0.008, 0.008], cornerRadius: 0.0035), materials: [brass])
        bar.position = [0, 0, 0.012]
        grip.addChild(bar)
        for x: Float in [-0.024, 0.024] {
            let post = ModelEntity(mesh: .generateBox(size: [0.006, 0.006, 0.014], cornerRadius: 0.002), materials: [brass])
            post.position = [x, 0, 0.004]
            grip.addChild(post)
        }
        grip.components.set(BaseMoveGripComponent())
        grip.components.set(InputTargetComponent())
        grip.components.set(CollisionComponent(shapes: [ShapeResource.generateBox(size: [0.1, 0.05, 0.06])
            .offsetBy(translation: [0, 0, 0.01])]))
        grip.components.set(InteractionStyle.hover)
        return grip
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

    /// Half the base's current diameter, in meters.
    private(set) var baseRadius: Float = Float(BaseSizeLimits.defaultWidth) / 200

    func setBaseSize(_ size: Float) {
        baseRadius = size / 2
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
        // The backdrop keeps to the base itself, about where a figure's middle is.
        backdrop.components[ViewerFacingBackdropComponent.self]?.footprint = (size / 2, height + 0.08)
        moveGrip.position = [0, height * 0.5, size / 2 + 0.028]
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
            ?? Self.geometryBounds(of: object) ?? BoundingBox()
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
    /// hidden; objects that aren't in any keyframe are left alone. Characters with an entry
    /// in `characterPoses` also take that body pose.
    /// - Parameter holds: For objects the timeline decides, whether each is in a hand.
    func apply(_ poses: [ObjectID: Transform], characterPoses: [ObjectID: CharacterPose] = [:],
               keyframedObjects: Set<ObjectID>, holds: [ObjectID: Hold?] = [:]) {
        for object in objects {
            guard let id = objectID(of: object) else { continue }
            if let pose = poses[id] {
                object.transform = pose
                object.isEnabled = true
            } else if keyframedObjects.contains(id) {
                object.isEnabled = false
            }
            if let characterPose = characterPoses[id], isCharacter(object),
               !(self.characterPose(of: object)?.matches(characterPose, tolerance: 0.01) ?? false) {
                setCharacterPose(characterPose, on: object)
            }
        }
        // After every body is posed, so held objects go to where the hands are now.
        for object in objects {
            guard let id = objectID(of: object), let hold = holds[id], self.hold(of: object) != hold else { continue }
            setHold(hold, on: object)
        }
        HeldProps.attachAll(in: objectsContainer)
    }

    /// A render-ready copy of the scene posed at a keyframe. The live objects are posed,
    /// copied, and put back within the same moment, so nothing visibly moves.
    func snapshot(at poses: [ObjectID: Transform], characterPoses: [ObjectID: CharacterPose] = [:],
                  keyframedObjects: Set<ObjectID>, holds: [ObjectID: Hold?] = [:]) -> Entity {
        let saved = objects.map { ($0, $0.transform, $0.isEnabled, characterPose(of: $0), hold(of: $0)) }
        apply(poses, characterPoses: characterPoses, keyframedObjects: keyframedObjects, holds: holds)
        let snapshot = CompositionRenderer.snapshot(of: baseAnchor)
        for (object, transform, isEnabled, characterPose, hold) in saved {
            if self.hold(of: object) != hold { setHold(hold, on: object) }
            object.transform = transform
            object.isEnabled = isEnabled
            if let characterPose, characterPoses[objectID(of: object) ?? UUID()] != nil {
                setCharacterPose(characterPose, on: object)
            }
        }
        return snapshot
    }

    /// True when nothing is being held, falling, or spinning, so poses are final.
    var isSettled: Bool {
        let spin = turntable.components[TurntableComponent.self]
        guard spin.map({ !$0.isDragging && $0.velocity == 0 }) ?? true else { return false }
        return objects.filter(\.isEnabled).allSatisfy { object in
            guard let gravity = object.components[ObjectGravityComponent.self] else { return true }
            return !gravity.isHeld && !gravity.isTurning && gravity.fallSpeed == 0
        }
    }

    /// The bounds of an object's visible geometry in its own space, leaving out the selection ring.
    ///
    /// Works whether or not the workspace is on screen. (RealityKit counts every entity as
    /// inactive while it isn't in a scene, so measuring "active" geometry finds nothing for
    /// projects opened before the workspace.)
    static func geometryBounds(of object: Entity) -> BoundingBox? {
        var bounds: BoundingBox?
        func visit(_ entity: Entity) {
            guard entity.isEnabled, entity.name != selectionIndicatorName else { return }
            if entity.components.has(ModelComponent.self) {
                let own = entity.visualBounds(recursive: false, relativeTo: object, excludeInactive: false)
                if !own.isEmpty { bounds = bounds.map { $0.union(own) } ?? own }
            }
            entity.children.forEach(visit)
        }
        object.children.forEach(visit)
        return bounds
    }

    /// A box around the object's geometry, in its own space.
    private func interactionShape(for object: Entity) -> ShapeResource {
        let bounds = Self.geometryBounds(of: object) ?? BoundingBox(min: [-0.005, 0, -0.005], max: [0.005, 0.01, 0.005])
        let size = simd_max(bounds.extents, SIMD3(repeating: 0.01))
        return ShapeResource.generateBox(size: size).offsetBy(translation: bounds.center)
    }

    /// Refits the grab box after a character's pose changes its shape.
    func updateCollisionShape(of object: Entity) {
        object.components.set(CollisionComponent(shapes: [interactionShape(for: object)]))
    }

    /// One collision box around the whole object so the system's manipulation gestures
    /// (move, rotate, two-handed scale) treat it as a single piece.
    private func configureInteraction(for object: Entity) {
        let shape = interactionShape(for: object)
        ManipulationComponent.configureEntity(
            object,
            hoverEffect: .spotlight(.default),
            allowedInputTypes: .all,
            collisionShapes: [shape]
        )
        if var manipulation = object.components[ManipulationComponent.self] {
            manipulation.releaseBehavior = .stay
            // Grabbing moves; it never turns. A twist of the wrist mid-move used to tip objects
            // over, and a second hand could spin them on any axis. Turning and tilting now take
            // the rings, on purpose. A second hand still resizes.
            manipulation.dynamics.primaryRotationBehavior = .none
            manipulation.dynamics.secondaryRotationBehavior = .none
            // Placed objects stop where you let go (then settle under gravity) instead of sliding on.
            manipulation.dynamics.inertia = .zero
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

    /// Turns, tilts, or resizes the selected object as its handle is dragged to `point`
    /// (world space).
    ///
    /// Turning and tilting pivot about the object's center, so it spins in place instead of
    /// swinging around its origin. Axes are worked out in world space and converted into the
    /// base's space, so the rings behave the same after the base has been spun.
    /// - Parameter snapping: Rotation detents: click onto 15° steps when close to one.
    /// - Returns: The object, on the first update of a drag, so the caller can record undo.
    @discardableResult
    func dragHandle(_ handle: Entity, to point: SIMD3<Float>, snapping: Bool) -> Entity? {
        guard let kind = handle.components[SelectionHandleComponent.self]?.kind, let object = handles.target,
              let parent = object.parent else { return nil }

        // The first update only starts the drag, so undo records the pose before any change.
        guard var drag = handleDrag, drag.object == object else {
            let pivot = kind == .scale ? handles.pivot : Self.center(of: object)
            let up = SIMD3<Float>(0, 1, 0)
            let axis = kind == .tilt ? handles.tiltAxis : up
            // In the tilt ring's plane, turning about `axis` carries `forward` toward `up`.
            let forward = kind == .tilt ? simd_normalize(simd_cross(up, axis)) : SIMD3<Float>(1, 0, 0)
            var start = HandleDrag(kind: kind, object: object, startAngle: 0,
                                   startDistance: max(simd_length(point - handles.pivot), 0.005),
                                   startTransform: object.transform, pivot: pivot,
                                   ringCenter: kind == .tilt ? pivot : handles.pivot, axis: axis,
                                   planeForward: forward, planeUp: up, startScale: object.scale.x)
            start.startAngle = Self.pointerAngle(point, in: start)
            if kind != .scale {
                start.lastSnappedStep = RotationDetent.apply(Self.absoluteAngle(of: object, in: start)).step
            }
            handleDrag = start
            setTurning(true, object)
            handles.setActive(kind)
            SoundEffects.play(.grab, on: object, gain: -14)
            return object
        }

        switch drag.kind {
        case .rotate, .tilt:
            var delta = Self.pointerAngle(point, in: drag) - drag.startAngle
            delta = atan2(sin(delta), cos(delta))
            if snapping {
                // Detents on the absolute angle (heading on the base, or lean from upright), so
                // 0° and every 15° step are easy to hit and everything between stays reachable.
                let base = Self.absoluteAngle(of: object, in: drag)
                let detent = RotationDetent.apply(base + delta)
                delta = detent.angle - base
                // Tick when clicking onto a step (not on leaving one).
                if detent.step != drag.lastSnappedStep {
                    if detent.step != nil { SoundEffects.play(.tick, on: object, gain: -24, pitchVariation: 0) }
                    drag.lastSnappedStep = detent.step
                }
            }
            let axis = simd_normalize(parent.convert(direction: drag.axis, from: nil))
            let pivot = parent.convert(position: drag.pivot, from: nil)
            let turn = simd_quatf(angle: delta, axis: axis)
            object.orientation = turn * drag.startTransform.rotation
            object.position = pivot + turn.act(drag.startTransform.translation - pivot)
            handles.setActive(drag.kind, angle: delta)
        case .scale:
            let ratio = simd_length(point - handles.pivot) / drag.startDistance
            let scale = min(max(drag.startScale * ratio, Self.scaleRange.lowerBound), Self.scaleRange.upperBound)
            object.scale = SIMD3(repeating: scale)
        }
        ObjectGravitySystem.keepAboveSurface(object)
        handleDrag = drag
        return nil
    }

    func endHandleDrag() {
        if let drag = handleDrag { setTurning(false, drag.object) }
        handles.setActive(nil)
        handleDrag = nil
    }

    /// The pointer's angle around the ring being dragged, in the ring's own plane.
    private static func pointerAngle(_ point: SIMD3<Float>, in drag: HandleDrag) -> Float {
        let offset = point - drag.ringCenter
        switch drag.kind {
        case .tilt: return atan2(simd_dot(offset, drag.planeUp), simd_dot(offset, drag.planeForward))
        case .rotate, .scale: return atan2(-offset.z, offset.x)
        }
    }

    /// The object's angle when the drag began, about the ring's axis: its heading on the base
    /// for the turn ring, its lean from upright for the tilt ring.
    private static func absoluteAngle(of object: Entity, in drag: HandleDrag) -> Float {
        drag.kind == .tilt ? lean(of: object, startRotation: drag.startTransform.rotation, in: drag)
                           : yaw(of: drag.startTransform.rotation)
    }

    /// How far the object leans forward from upright about the tilt axis, in radians.
    private static func lean(of object: Entity, startRotation: simd_quatf, in drag: HandleDrag) -> Float {
        guard let parent = object.parent else { return 0 }
        let world = parent.convert(direction: startRotation.act([0, 1, 0]), to: nil)
        // Turning about the axis carries `up` toward `-forward`.
        return atan2(simd_dot(world, -drag.planeForward), simd_dot(world, drag.planeUp))
    }

    /// The center of an object's grab box, in world space.
    static func center(of object: Entity) -> SIMD3<Float> {
        let local = object.components[CollisionComponent.self]?.shapes.first?.bounds.center
            ?? geometryBounds(of: object)?.center ?? .zero
        return object.convert(position: local, to: nil)
    }

    /// Holds an object still against gravity while a ring or the corner handle moves it.
    private func setTurning(_ isTurning: Bool, _ object: Entity) {
        guard var gravity = object.components[ObjectGravityComponent.self] else { return }
        gravity.isTurning = isTurning
        gravity.fallSpeed = 0
        object.components.set(gravity)
    }

    // MARK: Moving by hand

    /// Position snapping for an object being moved: never touches its rotation, never pulls
    /// it while in the hand. A preview shows where it would line up, and letting go there
    /// takes it (see `AlignmentSnapper`).
    func beginMove(of entity: Entity) {
        guard let object = object(containing: entity) else { return }
        var snapper = AlignmentSnapper()
        if let center = flatCenter(of: object) {
            snapper.begin(at: center, neighbors: neighbors(of: object))
        }
        move = (object, snapper)
        setSelectionHeld(true)
    }

    /// Updates the snap preview as the object moves. `snapping` is false when snapping is
    /// off or bypassed for the moment.
    func updateMove(of entity: Entity, snapping: Bool) {
        guard let object = object(containing: entity), var current = move, current.object == object,
              let center = flatCenter(of: object) else { return }
        let isAttached = object.components[ObjectGravityComponent.self]?.isAttached ?? false
        let targets = current.snapper.update(position: center,
                                             neighbors: snapping && !isAttached ? neighbors(of: object) : [])
        move = current
        showSnapPreview(for: object, center: center, targets: targets)
    }

    /// The object was let go. Lands it on the previewed alignment, if any.
    /// - Returns: True if it snapped.
    @discardableResult
    func endMove(of entity: Entity, snapping: Bool) -> Bool {
        defer {
            move = nil
            hideGuides()
            setSelectionHeld(false)
        }
        guard let object = object(containing: entity), let current = move, current.object == object, snapping,
              !current.snapper.targets.isEmpty, let center = flatCenter(of: object) else { return false }
        let landing = current.snapper.snapped(center)
        object.position.x += landing.x - center.x
        object.position.z += landing.y - center.y
        ObjectGravitySystem.keepAboveSurface(object)
        SoundEffects.play(.tick, on: object, gain: -22, pitchVariation: 0)
        return true
    }

    /// The center of an object's grab box on the base, as (x, z) in the objects container.
    private func flatCenter(of object: Entity) -> SIMD2<Float>? {
        guard let local = object.components[CollisionComponent.self]?.shapes.first?.bounds.center else { return nil }
        let center = object.convert(position: local, to: objectsContainer)
        return SIMD2(center.x, center.z)
    }

    private func neighbors(of object: Entity) -> [AlignmentSnapper.Neighbor] {
        objects.compactMap { other in
            guard other != object, other.isEnabled,
                  !(other.components[ObjectGravityComponent.self]?.isAttached ?? false),
                  let id = objectID(of: other), let center = flatCenter(of: other) else { return nil }
            return (id, center)
        }
    }

    /// A faint line through both centers for each alignment on offer, and a faint outline
    /// where the object would land.
    private func showSnapPreview(for object: Entity, center: SIMD2<Float>, targets: [AlignmentSnapper.Axis: AlignmentSnapper.Target]) {
        guard !targets.isEmpty else {
            hideGuides()
            return
        }
        var landing = center
        if let x = targets[.x] { landing.x = x.value }
        if let z = targets[.z] { landing.y = z.value }
        let other = { (axis: AlignmentSnapper.Axis) -> SIMD2<Float>? in
            targets[axis].flatMap { target in self.object(withID: target.object) }.flatMap(self.flatCenter)
        }
        // Lining up x runs a guide along z, and the other way round.
        showGuide(guideAlongZ, from: landing, to: other(.x), axis: 2)
        showGuide(guideAlongX, from: landing, to: other(.z), axis: 0)

        let bounds = object.components[CollisionComponent.self]?.shapes.first?.bounds ?? BoundingBox()
        let scale = object.scale.x
        let radius = max(bounds.extents.x, bounds.extents.z) * 0.5 * scale + 0.004
        let bottom = object.convert(position: [bounds.center.x, bounds.min.y, bounds.center.z], to: objectsContainer).y
        snapFootprint.transform = Transform(matrix: objectsContainer.transformMatrix(relativeTo: nil))
        snapFootprint.position = objectsContainer.convert(position: [landing.x, bottom + 0.0012, landing.y], to: nil)
        snapFootprint.scale = [radius, 1, radius]
        snapFootprint.isEnabled = true
    }

    func hideGuides() {
        guideAlongX.isEnabled = false
        guideAlongZ.isEnabled = false
        snapFootprint.isEnabled = false
    }

    /// A thin line on the base surface through both centers, along the given container axis.
    private func showGuide(_ guide: ModelEntity, from point: SIMD2<Float>, to other: SIMD2<Float>?, axis: Int) {
        guard let other else {
            guide.isEnabled = false
            return
        }
        let a = SIMD3(point.x, 0.0012, point.y), b = SIMD3(other.x, 0.0012, other.y)
        let low = min(a[axis], b[axis]) - 0.03
        let high = max(a[axis], b[axis]) + 0.03
        var center = a
        center[axis] = (low + high) / 2
        var size = SIMD3<Float>(0.0011, 0.0006, 0.0011)
        size[axis] = high - low

        guide.transform = Transform(matrix: objectsContainer.transformMatrix(relativeTo: nil))
        guide.position = objectsContainer.convert(position: center, to: nil)
        guide.scale = size
        guide.isEnabled = true
    }

    /// The selection disc brightens while the object is in the hand.
    private func setSelectionHeld(_ isHeld: Bool) {
        selectionIndicator.model?.materials = [
            InteractionStyle.unlit(InteractionStyle.selection, opacity: InteractionStyle.selectionDiscOpacity(isHeld: isHeld))
        ]
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
        // Enabled means "has an image" (captures need it); whether it shows is its opacity.
        backdrop.components.set(OpacityComponent(opacity: isBackdropShown ? 1 : 0))
        backdrop.isEnabled = true
    }

    /// Whether the backdrop shows in the room. It stays enabled and keeps following the viewer
    /// while hidden, so photos, re-shoots, and exports still frame against it.
    private(set) var isBackdropShown = true

    func setBackdropShown(_ isShown: Bool, animated: Bool) {
        guard isShown != isBackdropShown else { return }
        isBackdropShown = isShown
        let target: Float = isShown ? 1 : 0
        let current = backdrop.components[OpacityComponent.self]?.opacity ?? (isShown ? 0 : 1)
        backdrop.components.set(OpacityComponent(opacity: target))
        guard animated, SceneFeedback.isEnabled, backdrop.isEnabled else { return }
        let fade = FromToByAnimation<Float>(from: current, to: target, duration: 0.25, timing: .easeInOut,
                                            bindTarget: .opacity)
        if let animation = try? AnimationResource.generate(with: fade) {
            backdrop.playAnimation(animation)
        }
    }
}

/// Marks the base's move handle.
struct BaseMoveGripComponent: Component {}
