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
final class WorkspaceScene {
    static let selectionIndicatorName = "SelectionIndicator"
    /// Wide enough to feel unlimited, while preventing objects from collapsing to nothing.
    static let scaleRange: ClosedRange<Float> = 0.02...50

    /// Where the base floats when no table is available: about 1 m ahead, near table height.
    private static let floatingBasePosition = SIMD3<Float>(0, 0.85, -1.0)

    private static let backdropHeight: Float = 1.9
    private static let backdropMaxWidth: Float = 4.5

    let root = Entity()
    let baseAnchor = Entity()
    let objectsContainer = Entity()
    let backdrop = ModelEntity()

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
    /// side matches `size`, centered, and rested on the anchor.
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
        objectsContainer.components.set(GravitySurfaceComponent(baseHalfWidth: size / 2, baseHeight: height))
    }

    // MARK: Objects

    /// Adds a generated object to the base and returns the entity the user manipulates.
    @discardableResult
    func addObject(_ content: Entity, name: String) -> Entity {
        let object = Entity()
        object.name = name
        object.addChild(content)
        object.position = openSpot()
        objectsContainer.addChild(object)
        configureInteraction(for: object)
        objects.append(object)
        return object
    }

    @discardableResult
    func duplicate(_ object: Entity) -> Entity {
        // Keep the selection ring out of the copy.
        let ringParent = selectionIndicator.parent
        selectionIndicator.removeFromParent()

        let copy = object.clone(recursive: true)
        copy.name = object.name
        copy.transform = object.transform
        // Offset sideways relative to the base, so the copy is visible next to the original.
        copy.position += SIMD3<Float>(0.05, 0, 0.03)
        objectsContainer.addChild(copy)
        configureInteraction(for: copy)
        objects.append(copy)

        ringParent?.addChild(selectionIndicator)
        return copy
    }

    func remove(_ object: Entity) {
        if selectionIndicator.parent == object { selectionIndicator.removeFromParent() }
        object.removeFromParent()
        objects.removeAll { $0 == object }
    }

    func object(withID id: Entity.ID) -> Entity? {
        objects.first { $0.id == id }
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

    /// Current poses of every placed object, relative to the base.
    func currentPoses() -> [Entity.ID: Transform] {
        Dictionary(uniqueKeysWithValues: objects.map { ($0.id, $0.transform) })
    }

    func apply(_ poses: [Entity.ID: Transform]) {
        for object in objects {
            if let pose = poses[object.id] { object.transform = pose }
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
        let taken = objects.map { SIMD2($0.position.x, $0.position.z) }
        let spot = candidates.first { candidate in
            taken.allSatisfy { simd_distance($0, candidate) > spacing * 0.7 }
        } ?? [0, 0]
        return [spot.x, 0, spot.y]
    }

    // MARK: Backdrop

    func setBackdropImage(_ image: CGImage) async throws {
        let texture = try await TextureResource(image: image, withName: nil, options: .init(semantic: .color))

        // Unlit and not tone-mapped, so the image shows its true colors like a printed backdrop.
        var material = UnlitMaterial(applyPostProcessToneMap: false)
        material.color = .init(texture: .init(texture))

        let aspect = Float(image.width) / Float(max(image.height, 1))
        var height = Self.backdropHeight
        var width = height * aspect
        if width > Self.backdropMaxWidth {
            width = Self.backdropMaxWidth
            height = width / aspect
        }

        backdrop.model = ModelComponent(mesh: .generatePlane(width: width, height: height), materials: [material])
        backdrop.isEnabled = true
    }
}
