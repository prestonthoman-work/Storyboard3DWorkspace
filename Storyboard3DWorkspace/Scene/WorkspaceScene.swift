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
    let backdrop = ModelEntity()
    /// A head-locked frame outlining exactly what a capture will include.
    let viewfinder = AnchorEntity(.head)
    private let viewfinderFrame = Entity()
    /// How far in front of the eyes the viewfinder frame is drawn.
    static let viewfinderDistance: Float = 0.5

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
        baseAnchor.addChild(baseHolder)
        objectsContainer.name = "Objects"
        baseAnchor.addChild(objectsContainer)
        root.addChild(baseAnchor)

        selectionIndicator.name = Self.selectionIndicatorName
        var indicatorMaterial = UnlitMaterial(color: .white)
        indicatorMaterial.blending = .transparent(opacity: 0.4)
        selectionIndicator.model = ModelComponent(mesh: .generateCylinder(height: 0.0015, radius: 1),
                                                  materials: [indicatorMaterial])

        backdrop.name = "Backdrop"
        backdrop.isEnabled = false
        backdrop.components.set(ViewerFacingBackdropComponent(target: baseAnchor))
        root.addChild(backdrop)

        viewfinder.name = "Viewfinder"
        viewfinder.isEnabled = false
        viewfinder.addChild(viewfinderFrame)
        setViewfinderLens(.standard)
    }

    // MARK: Viewfinder

    func setViewfinderVisible(_ isVisible: Bool) {
        viewfinder.isEnabled = isVisible
    }

    /// Redraws the frame to match the lens's field of view.
    func setViewfinderLens(_ lens: CaptureLens) {
        viewfinderFrame.children.removeAll()
        let distance = Self.viewfinderDistance
        let halfWidth = distance * tan(lens.horizontalFOV / 2)
        let halfHeight = distance * tan(lens.verticalFOV / 2)
        let line: Float = 0.0012

        var material = UnlitMaterial(color: .white)
        material.blending = .transparent(opacity: 0.75)
        let edges: [(size: SIMD3<Float>, position: SIMD3<Float>)] = [
            ([halfWidth * 2 + line, line, line], [0, halfHeight, -distance]),
            ([halfWidth * 2 + line, line, line], [0, -halfHeight, -distance]),
            ([line, halfHeight * 2 + line, line], [-halfWidth, 0, -distance]),
            ([line, halfHeight * 2 + line, line], [halfWidth, 0, -distance])
        ]
        for edge in edges {
            let entity = ModelEntity(mesh: .generateBox(size: edge.size), materials: [material])
            entity.position = edge.position
            viewfinderFrame.addChild(entity)
        }
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
    }

    func setBaseSize(_ size: Float) {
        guard let content = baseContent, let bounds = baseNominalBounds else { return }
        let footprint = max(bounds.extents.x, bounds.extents.z, 1e-4)
        let scale = size / footprint
        content.scale = SIMD3(repeating: scale)
        content.position = [-bounds.center.x * scale, -bounds.min.y * scale, -bounds.center.z * scale]
        let height = bounds.extents.y * scale
        objectsContainer.position = [0, height, 0]
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
    }

    func remove(_ object: Entity) {
        if selectionIndicator.parent == object { selectionIndicator.removeFromParent() }
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
        guard let object else { return }
        let bounds = object.visualBounds(relativeTo: object, excludeInactive: true)
        let radius = max(bounds.extents.x, bounds.extents.z) * 0.65 + 0.006
        selectionIndicator.scale = [radius, 1, radius]
        selectionIndicator.position = [bounds.center.x, bounds.min.y + 0.001, bounds.center.z]
        object.addChild(selectionIndicator)
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

    /// True when nothing is being held or is still falling, so poses are final.
    var isSettled: Bool {
        objects.filter(\.isEnabled).allSatisfy { object in
            guard let gravity = object.components[ObjectGravityComponent.self] else { return true }
            return !gravity.isHeld && gravity.fallSpeed == 0
        }
    }

    /// One collision box around the whole object so the system's manipulation gestures
    /// (move, rotate, two-handed scale) treat it as a single piece.
    private func configureInteraction(for object: Entity) {
        let bounds = object.visualBounds(relativeTo: object, excludeInactive: true)
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
