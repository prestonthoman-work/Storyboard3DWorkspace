//
//  SelectionHandles.swift
//  Storyboard3DWorkspace
//

import RealityKit
import UIKit

/// Marks a draggable handle on the selected object.
struct SelectionHandleComponent: Component {
    enum Kind {
        /// The flat ring around the object's foot: drag around it to turn the object about
        /// the vertical axis.
        case rotate
        /// The upright arc over the object: drag along it to tilt the object forward or
        /// backward, about its own side-to-side axis.
        case tilt
        /// The top corner: drag away from or toward the object to resize it.
        case scale
    }

    var kind: Kind
}

/// Keeps the handles and toolbar wrapped around the selected object as it moves, turns,
/// and resizes. Lives on the handles' root, which sits outside the staged scene so none
/// of it appears in captures.
struct SelectionFollowComponent: Component {
    var handles: SelectionHandles
}

/// Visible controls for the selected object: a cyan ring at its foot to turn it, a brass arc
/// over it to tilt it, a corner handle to resize it, and an anchor above it for the floating
/// toolbar.
///
/// Each ring's orientation shows its axis: the turn ring lies flat (turning about up), and
/// the tilt arc stands upright through the object's front and back (tilting about the
/// object's side-to-side axis). Hit targets are generous and invisible; the visible strokes
/// stay thin so they never crowd the set.
final class SelectionHandles {
    let root = Entity()
    /// The floating toolbar attachment goes here; it always turns to face the viewer.
    let toolbarAnchor = Entity()
    private let visuals = Entity()

    private let turnGrip = Entity()
    private let turnRing = ModelEntity()
    private let turnKnob = ModelEntity()
    private let tiltGroup = Entity()
    private let tiltGrip = Entity()
    private let tiltRing = ModelEntity()
    private let tiltKnob = ModelEntity()
    private let scaleKnob = ModelEntity()
    private let turnLabel = Entity()
    private let tiltLabel = Entity()

    /// The handle being dragged, if any, and the angle it has turned so far (radians).
    private var active: (kind: SelectionHandleComponent.Kind, angle: Float)?
    private var shownEmphasis: [ObjectIdentifier: InteractionStyle.Emphasis] = [:]
    /// Ring sizes the meshes were last built for, so they're rebuilt only when the object's size changes.
    private var builtTurnRadius: Float = 0
    private var builtTilt: (radius: Float, low: Float) = (0, 0)
    /// When the labels stop showing after a new selection.
    private var labelsUntil: Date = .distantPast
    private var shownLabelText: [ObjectIdentifier: String] = [:]

    /// Thickness of the visible ring strokes.
    private static let tube: Float = 0.0011
    /// Thickness of the invisible band you can grab a ring by.
    private static let gripBand: Float = 0.024

    init() {
        root.name = "SelectionHandles"
        visuals.isEnabled = false
        root.addChild(visuals)

        // Turn ring: flat at the foot.
        turnGrip.name = "TurnHandle"
        configureHandle(turnGrip, kind: .rotate)
        turnGrip.addChild(turnRing)
        turnKnob.model = ModelComponent(mesh: .generateSphere(radius: 0.0065), materials: [])
        turnGrip.addChild(turnKnob)
        visuals.addChild(turnGrip)

        // Tilt arc: upright, through the object's center.
        tiltGroup.name = "TiltRing"
        tiltGrip.name = "TiltHandle"
        configureHandle(tiltGrip, kind: .tilt)
        tiltGrip.addChild(tiltRing)
        tiltKnob.model = ModelComponent(mesh: .generateSphere(radius: 0.0065), materials: [])
        tiltGrip.addChild(tiltKnob)
        tiltGroup.addChild(tiltGrip)
        visuals.addChild(tiltGroup)

        scaleKnob.name = "ScaleHandle"
        scaleKnob.model = ModelComponent(mesh: .generateBox(size: 0.009, cornerRadius: 0.002), materials: [])
        configureHandle(scaleKnob, kind: .scale)
        scaleKnob.components.set(CollisionComponent(shapes: [.generateBox(size: [0.024, 0.024, 0.024])]))
        visuals.addChild(scaleKnob)

        for label in [turnLabel, tiltLabel] {
            label.components.set(BillboardComponent())
            label.isEnabled = false
            visuals.addChild(label)
        }

        toolbarAnchor.name = "ToolbarAnchor"
        toolbarAnchor.components.set(BillboardComponent())
        visuals.addChild(toolbarAnchor)

        applyEmphasis()
        root.components.set(SelectionFollowComponent(handles: self))
    }

    private func configureHandle(_ entity: Entity, kind: SelectionHandleComponent.Kind) {
        entity.components.set(SelectionHandleComponent(kind: kind))
        entity.components.set(InputTargetComponent())
        entity.components.set(InteractionStyle.hover)
    }

    func setTarget(_ object: Entity?) {
        let changed = object !== target
        target = object
        if object == nil { visuals.isEnabled = false }
        if changed, object != nil {
            // Name the rings briefly whenever something new is selected.
            labelsUntil = .now.addingTimeInterval(2.5)
            active = nil
            applyEmphasis()
        }
    }

    private(set) var target: Entity?

    /// Where the handles are centered: the bottom center of the selected object, in world space.
    var pivot: SIMD3<Float> { root.position(relativeTo: nil) }

    /// The tilt ring's axis (the object's side-to-side direction, kept level) in world space.
    var tiltAxis: SIMD3<Float> { root.orientation(relativeTo: nil).act([1, 0, 0]) }

    /// A ring is being dragged: brighten it, quiet the others, and show its angle.
    func setActive(_ kind: SelectionHandleComponent.Kind?, angle: Float = 0) {
        active = kind.map { ($0, angle) }
        applyEmphasis()
    }

    private func applyEmphasis() {
        func emphasis(for kind: SelectionHandleComponent.Kind) -> InteractionStyle.Emphasis {
            guard let active else { return .idle }
            return active.kind == kind ? .active : .dimmed
        }
        set(turnRing, InteractionStyle.selection, emphasis(for: .rotate))
        set(turnKnob, InteractionStyle.selection, emphasis(for: .rotate), boost: true)
        set(tiltRing, InteractionStyle.tilt, emphasis(for: .tilt))
        set(tiltKnob, InteractionStyle.tilt, emphasis(for: .tilt), boost: true)
        set(scaleKnob, InteractionStyle.neutral, emphasis(for: .scale), boost: true)
    }

    private func set(_ model: ModelEntity, _ color: UIColor, _ emphasis: InteractionStyle.Emphasis, boost: Bool = false) {
        let key = ObjectIdentifier(model)
        guard shownEmphasis[key] != emphasis || model.model?.materials.isEmpty ?? true else { return }
        shownEmphasis[key] = emphasis
        // Knobs read a touch stronger than their rings so the grab point is obvious.
        let opacity = boost && emphasis == .idle ? 0.9 : emphasis.opacity
        var material = InteractionStyle.unlit(color, opacity: opacity)
        material.faceCulling = .none
        model.model?.materials = [material]
    }

    // MARK: Following the object

    fileprivate func update() {
        guard SceneFeedback.isEnabled, let target, target.parent != nil, target.isEnabled else {
            visuals.isEnabled = false
            return
        }
        let isHeld = target.components[ObjectGravityComponent.self]?.isHeld ?? false
        visuals.isEnabled = !isHeld && !ObjectGravitySystem.isFallingPaused
        guard visuals.isEnabled else { return }

        // The object's own bounds (unscaled, unaffected by pop-in animations), placed
        // using its current transform.
        let local = target.components[CollisionComponent.self]?.shapes.first?.bounds
            ?? target.visualBounds(relativeTo: target)
        let matrix = target.transformMatrix(relativeTo: root.parent)
        let xAxis = SIMD3(matrix.columns.0.x, matrix.columns.0.y, matrix.columns.0.z)
        let scale = max(simd_length(xAxis), 1e-4)
        var flat = SIMD3(xAxis.x, 0, xAxis.z)
        if simd_length(flat) < 1e-4 { flat = [1, 0, 0] }
        flat = simd_normalize(flat)
        let yaw = atan2(-flat.z, flat.x)

        let bottom = matrix * SIMD4(local.center.x, local.min.y, local.center.z, 1)
        root.position = SIMD3(bottom.x, bottom.y, bottom.z)
        root.orientation = simd_quatf(angle: yaw, axis: [0, 1, 0])

        // Turn ring around the foot.
        let radius = max(local.extents.x, local.extents.z) * 0.5 * scale * 1.3 + 0.014
        let height = local.extents.y * scale
        if abs(radius - builtTurnRadius) > builtTurnRadius * 0.03 {
            builtTurnRadius = radius
            turnRing.model = Self.tubeArc(radius: radius, from: 0, to: 2 * .pi, plane: .horizontal).map {
                ModelComponent(mesh: $0, materials: turnRing.model?.materials ?? [])
            }
            // Hit shapes live on the grip itself, which carries the handle component.
            var shapes = Self.bandShapes(radius: radius, from: 0, to: 2 * .pi, plane: .horizontal)
            shapes.append(ShapeResource.generateSphere(radius: 0.018).offsetBy(translation: [radius, 0, 0]))
            turnGrip.components.set(CollisionComponent(shapes: shapes))
            shownEmphasis[ObjectIdentifier(turnRing)] = nil
            applyEmphasis()
        }
        turnGrip.position = [0, 0.0015, 0]
        turnKnob.position = [radius, 0, 0]

        // Tilt arc through the object's center, kept above the base so it never dives into it.
        let centerWorld = matrix * SIMD4(local.center.x, local.center.y, local.center.z, 1)
        let center = root.orientation.inverse.act(SIMD3(centerWorld.x, centerWorld.y, centerWorld.z) - root.position)
        let tiltRadius = 0.5 * simd_length(SIMD2(local.extents.y, local.extents.z)) * scale + 0.016
        let low = -asin(min(max((center.y - 0.004) / tiltRadius, 0), 1))
        if abs(tiltRadius - builtTilt.radius) > builtTilt.radius * 0.03 || abs(low - builtTilt.low) > 0.02 {
            builtTilt = (tiltRadius, low)
            tiltRing.model = Self.tubeArc(radius: tiltRadius, from: low, to: .pi - low, plane: .upright).map {
                ModelComponent(mesh: $0, materials: tiltRing.model?.materials ?? [])
            }
            // Grab it by its top, over the object, where it never covers the object itself.
            var shapes = Self.bandShapes(radius: tiltRadius, from: .pi * 0.3, to: .pi * 0.7, plane: .upright)
            shapes.append(ShapeResource.generateSphere(radius: 0.018).offsetBy(translation: [0, tiltRadius, 0]))
            tiltGrip.components.set(CollisionComponent(shapes: shapes))
            shownEmphasis[ObjectIdentifier(tiltRing)] = nil
            applyEmphasis()
        }
        tiltGroup.position = center
        tiltKnob.position = [0, tiltRadius, 0]

        scaleKnob.position = [(local.max.x - local.center.x) * scale + 0.007, height + 0.007,
                              (local.max.z - local.center.z) * scale + 0.007]
        let tiltTop = center.y + tiltRadius
        toolbarAnchor.position = [0, max(height + 0.05, tiltTop + 0.04), 0]

        updateLabels(turnAt: [radius + 0.02, 0.012, 0], tiltAt: center + [0, tiltRadius + 0.018, 0])
    }

    /// "Turn" and "Tilt" next to their knobs for a moment after selecting, and the angle on
    /// the ring being dragged.
    private func updateLabels(turnAt turnPosition: SIMD3<Float>, tiltAt tiltPosition: SIMD3<Float>) {
        let showNames = Date.now < labelsUntil && active == nil
        func text(for kind: SelectionHandleComponent.Kind, name: String) -> String? {
            if let active, active.kind == kind {
                let degrees = Int((active.angle * 180 / .pi).rounded())
                return "\(name) \(degrees > 0 ? "+" : "")\(degrees)°"
            }
            return showNames ? name : nil
        }
        show(turnLabel, text: text(for: .rotate, name: "Turn"), color: InteractionStyle.selection, at: turnPosition)
        show(tiltLabel, text: text(for: .tilt, name: "Tilt"), color: InteractionStyle.tilt, at: tiltPosition)
    }

    private func show(_ label: Entity, text: String?, color: UIColor, at position: SIMD3<Float>) {
        label.isEnabled = text != nil
        guard let text else { return }
        label.position = position
        let key = ObjectIdentifier(label)
        guard shownLabelText[key] != text else { return }
        shownLabelText[key] = text
        label.children.removeAll()
        let mesh = MeshResource.generateText(text, extrusionDepth: 0,
                                             font: .systemFont(ofSize: 0.0105, weight: .semibold))
        let glyphs = ModelEntity(mesh: mesh, materials: [InteractionStyle.unlit(color, opacity: 0.95)])
        // Center the text on its anchor.
        glyphs.position = -mesh.bounds.center
        label.addChild(glyphs)
    }

    // MARK: Geometry

    private enum Plane {
        /// Lying flat: angle 0 points along +X, turning toward -Z.
        case horizontal
        /// Standing in the object's front-to-back plane: angle 0 points forward (+Z), π/2 up.
        case upright

        func point(_ angle: Float, radius: Float) -> SIMD3<Float> {
            switch self {
            case .horizontal: [cos(angle) * radius, 0, -sin(angle) * radius]
            case .upright: [0, sin(angle) * radius, cos(angle) * radius]
            }
        }

        /// The ring's axis.
        var normal: SIMD3<Float> {
            switch self {
            case .horizontal: [0, 1, 0]
            case .upright: [1, 0, 0]
            }
        }
    }

    /// A thin round tube along an arc, visible from any side.
    private static func tubeArc(radius: Float, from start: Float, to end: Float, plane: Plane) -> MeshResource? {
        let segments = max(Int(abs(end - start) / (2 * .pi) * 120), 8)
        let sides = 6
        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var indices: [UInt32] = []
        for i in 0...segments {
            let angle = start + (end - start) * Float(i) / Float(segments)
            let center = plane.point(angle, radius: radius)
            let outward = simd_normalize(center)
            for j in 0..<sides {
                let around = Float(j) / Float(sides) * 2 * .pi
                let normal = outward * cos(around) + plane.normal * sin(around)
                positions.append(center + normal * tube)
                normals.append(normal)
            }
        }
        for i in 0..<segments {
            for j in 0..<sides {
                let a = UInt32(i * sides + j), b = UInt32(i * sides + (j + 1) % sides)
                let c = UInt32((i + 1) * sides + (j + 1) % sides), d = UInt32((i + 1) * sides + j)
                indices += [a, b, c, a, c, d]
            }
        }
        var descriptor = MeshDescriptor(name: "HandleRing")
        descriptor.positions = MeshBuffer(positions)
        descriptor.normals = MeshBuffer(normals)
        descriptor.primitives = .triangles(indices)
        return try? MeshResource.generate(from: [descriptor])
    }

    /// Invisible boxes along an arc, so the ring can be grabbed anywhere along it.
    private static func bandShapes(radius: Float, from start: Float, to end: Float, plane: Plane) -> [ShapeResource] {
        let length = abs(end - start) * radius
        let count = max(Int((length / 0.02).rounded(.up)), 3)
        return (0..<count).map { index in
            let angle = start + (end - start) * (Float(index) + 0.5) / Float(count)
            let center = plane.point(angle, radius: radius)
            let tangent = simd_normalize(plane.point(angle + 0.01, radius: radius) - center)
            let outward = simd_normalize(center)
            let rotation = simd_quatf(simd_float3x3(columns: (tangent, outward, simd_cross(tangent, outward))))
            return ShapeResource.generateBox(size: [length / Float(count) * 1.15, gripBand, gripBand])
                .offsetBy(rotation: rotation, translation: center)
        }
    }
}

struct SelectionFollowSystem: System {
    private static let query = EntityQuery(where: .has(SelectionFollowComponent.self))

    init(scene: Scene) {}

    func update(context: SceneUpdateContext) {
        for entity in context.entities(matching: Self.query, updatingSystemWhen: .rendering) {
            entity.components[SelectionFollowComponent.self]?.handles.update()
        }
    }
}
