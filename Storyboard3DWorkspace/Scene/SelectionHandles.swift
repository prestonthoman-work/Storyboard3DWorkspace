//
//  SelectionHandles.swift
//  Storyboard3DWorkspace
//

import RealityKit
import UIKit

/// Marks a draggable handle on the selected object.
struct SelectionHandleComponent: Component {
    enum Kind {
        /// The knob on the ring: drag around the object to turn it.
        case rotate
        /// The top corner: drag away from or toward the object to resize it.
        case scale
    }

    var kind: Kind
}

/// Keeps the handles and toolbar wrapped around the selected object as it moves, turns,
/// and resizes. Lives on the handles' root, which sits outside the staged scene so none
/// of it appears in captures.
struct SelectionFollowComponent: Component {
    var target: Entity?
    var visuals: Entity
    var ring: Entity
    var rotateKnob: Entity
    var scaleKnob: Entity
    var toolbar: Entity
}

/// Visible controls for the selected object: a ring with a knob to rotate it, a corner
/// handle to resize it, and an anchor above it for the floating toolbar.
final class SelectionHandles {
    let root = Entity()
    /// The floating toolbar attachment goes here; it always turns to face the viewer.
    let toolbarAnchor = Entity()
    private let visuals = Entity()
    private let ring = ModelEntity()
    private let rotateKnob = ModelEntity()
    private let scaleKnob = ModelEntity()

    init() {
        root.name = "SelectionHandles"
        visuals.isEnabled = false
        root.addChild(visuals)

        var ringMesh = MeshBuilder()
        ringMesh.addRing(innerRadius: 0.955, outerRadius: 1, y: 0.0015, segments: 96)
        var ringMaterial = UnlitMaterial(color: .white)
        ringMaterial.blending = .transparent(opacity: 0.55)
        if let mesh = ringMesh.makeMesh(named: "HandleRing") {
            ring.model = ModelComponent(mesh: mesh, materials: [ringMaterial])
        }
        visuals.addChild(ring)

        var knobMaterial = UnlitMaterial(color: .white)
        knobMaterial.blending = .transparent(opacity: 0.95)
        rotateKnob.name = "RotateHandle"
        rotateKnob.model = ModelComponent(mesh: .generateSphere(radius: 0.0062), materials: [knobMaterial])
        configureHandle(rotateKnob, kind: .rotate, shape: .generateSphere(radius: 0.015))
        visuals.addChild(rotateKnob)

        scaleKnob.name = "ScaleHandle"
        scaleKnob.model = ModelComponent(mesh: .generateBox(size: 0.009, cornerRadius: 0.002), materials: [knobMaterial])
        configureHandle(scaleKnob, kind: .scale, shape: .generateBox(size: [0.022, 0.022, 0.022]))
        visuals.addChild(scaleKnob)

        toolbarAnchor.name = "ToolbarAnchor"
        toolbarAnchor.components.set(BillboardComponent())
        visuals.addChild(toolbarAnchor)

        root.components.set(SelectionFollowComponent(target: nil, visuals: visuals, ring: ring, rotateKnob: rotateKnob,
                                                     scaleKnob: scaleKnob, toolbar: toolbarAnchor))
    }

    private func configureHandle(_ entity: Entity, kind: SelectionHandleComponent.Kind, shape: ShapeResource) {
        entity.components.set(SelectionHandleComponent(kind: kind))
        entity.components.set(InputTargetComponent())
        entity.components.set(CollisionComponent(shapes: [shape]))
        entity.components.set(HoverEffectComponent())
    }

    func setTarget(_ object: Entity?) {
        guard var follow = root.components[SelectionFollowComponent.self] else { return }
        follow.target = object
        root.components.set(follow)
        if object == nil { visuals.isEnabled = false }
    }

    var target: Entity? { root.components[SelectionFollowComponent.self]?.target }

    /// Where the handles are centered: the bottom center of the selected object, in world space.
    var pivot: SIMD3<Float> { root.position(relativeTo: nil) }
}

struct SelectionFollowSystem: System {
    private static let query = EntityQuery(where: .has(SelectionFollowComponent.self))

    init(scene: Scene) {}

    func update(context: SceneUpdateContext) {
        for entity in context.entities(matching: Self.query, updatingSystemWhen: .rendering) {
            guard let follow = entity.components[SelectionFollowComponent.self] else { continue }
            guard SceneFeedback.isEnabled, let target = follow.target, target.parent != nil, target.isEnabled else {
                follow.visuals.isEnabled = false
                continue
            }
            let isHeld = target.components[ObjectGravityComponent.self]?.isHeld ?? false
            follow.visuals.isEnabled = !isHeld && !ObjectGravitySystem.isFallingPaused
            guard follow.visuals.isEnabled else { continue }

            // The object's own bounds (unscaled, unaffected by pop-in animations), placed
            // using its current transform.
            let local = target.components[CollisionComponent.self]?.shapes.first?.bounds
                ?? target.visualBounds(relativeTo: target)
            let matrix = target.transformMatrix(relativeTo: entity.parent)
            let xAxis = SIMD3(matrix.columns.0.x, matrix.columns.0.y, matrix.columns.0.z)
            let scale = max(simd_length(xAxis), 1e-4)
            var flat = SIMD3(xAxis.x, 0, xAxis.z)
            if simd_length(flat) < 1e-4 { flat = [1, 0, 0] }
            flat = simd_normalize(flat)
            let yaw = atan2(-flat.z, flat.x)

            let bottom = matrix * SIMD4(local.center.x, local.min.y, local.center.z, 1)
            entity.position = SIMD3(bottom.x, bottom.y, bottom.z)
            entity.orientation = simd_quatf(angle: yaw, axis: [0, 1, 0])

            let radius = max(local.extents.x, local.extents.z) * 0.5 * scale * 1.3 + 0.014
            let height = local.extents.y * scale
            follow.ring.scale = [radius, 1, radius]
            follow.rotateKnob.position = [radius, 0.003, 0]
            follow.scaleKnob.position = [(local.max.x - local.center.x) * scale + 0.007, height + 0.007,
                                         (local.max.z - local.center.z) * scale + 0.007]
            follow.toolbar.position = [0, height + 0.05, 0]
        }
    }
}
