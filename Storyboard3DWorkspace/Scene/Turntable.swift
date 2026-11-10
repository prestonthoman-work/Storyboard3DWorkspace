//
//  Turntable.swift
//  Storyboard3DWorkspace
//

import RealityKit
import UIKit

/// Marks the grippable band around the base's plinth.
struct TurntableGripComponent: Component {}

/// The base's spin, like a lazy susan: dragged directly, then coasting to a stop.
struct TurntableComponent: Component {
    /// Current heading in radians; unbounded, so it can turn any number of times.
    var angle: Float = 0
    /// Radians per second while coasting after a flick.
    var velocity: Float = 0
    var isDragging = false
    /// The last 15° step passed, for detent ticks.
    var lastDetent = 0

    static let detent: Float = .pi / 12
    /// How quickly a coasting spin slows, per second.
    static let friction: Float = 3.5
    static let maxVelocity: Float = 8
}

struct TurntableSystem: System {
    private static let query = EntityQuery(where: .has(TurntableComponent.self))

    init(scene: Scene) {}

    func update(context: SceneUpdateContext) {
        let deltaTime = Float(min(context.deltaTime, 1.0 / 30))
        for entity in context.entities(matching: Self.query, updatingSystemWhen: .rendering) {
            guard var turntable = entity.components[TurntableComponent.self],
                  !turntable.isDragging, turntable.velocity != 0 else { continue }
            turntable.angle += turntable.velocity * deltaTime
            turntable.velocity *= exp(-TurntableComponent.friction * deltaTime)
            if abs(turntable.velocity) < 0.08 { turntable.velocity = 0 }
            Turntable.apply(&turntable, to: entity)
            entity.components.set(turntable)
        }
    }
}

enum Turntable {
    /// Orients the turntable to its angle and ticks when it crosses a 15° step.
    static func apply(_ turntable: inout TurntableComponent, to entity: Entity) {
        entity.orientation = simd_quatf(angle: turntable.angle, axis: [0, 1, 0])
        let detent = Int((turntable.angle / TurntableComponent.detent).rounded(.down))
        if detent != turntable.lastDetent {
            turntable.lastDetent = detent
            if let grip = entity.parent?.findEntity(named: gripName) {
                SoundEffects.play(.tick, on: grip, gain: -28, pitchVariation: 0.02)
            }
        }
    }

    static let gripName = "TurntableGrip"

    /// A slim brushed-brass band around the plinth, sized for a 1 m base (scaled with
    /// the base), with a generous invisible grab zone covering the plinth's whole edge.
    static func makeGrip() -> ModelEntity {
        let grip = ModelEntity()
        grip.name = gripName

        var band = MeshBuilder()
        band.addFrustum(bottomRadius: 0.5045, topRadius: 0.5025, bottomY: 0.011, topY: 0.023, capTop: false)
        if let mesh = band.makeMesh(named: "TurntableBand") {
            grip.model = ModelComponent(mesh: mesh, materials: [
                LowPoly.material(UIColor(red: 0.74, green: 0.6, blue: 0.38, alpha: 1), .metal)
            ])
        }

        // Boxes around the rim, from the table up to the base's surface.
        let segments = 28
        let shapes = (0..<segments).map { index -> ShapeResource in
            let angle = Float(index) / Float(segments) * 2 * .pi
            let rotation = simd_quatf(angle: -angle, axis: [0, 1, 0])
            return ShapeResource.generateBox(size: [0.075, 0.042, 0.13])
                .offsetBy(rotation: rotation, translation: [cos(angle) * 0.49, 0.021, sin(angle) * 0.49])
        }
        grip.components.set(TurntableGripComponent())
        grip.components.set(InputTargetComponent())
        grip.components.set(CollisionComponent(shapes: shapes))
        grip.components.set(HoverEffectComponent(.highlight(.init(color: .white, strength: 0.8))))
        return grip
    }
}
