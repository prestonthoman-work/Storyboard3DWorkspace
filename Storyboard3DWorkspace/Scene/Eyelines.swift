//
//  Eyelines.swift
//  Storyboard3DWorkspace
//

import RealityKit
import UIKit

/// Turns on the eyeline guides. Lives on one root entity outside the staged scene, so the
/// guides never appear in photos or exports.
struct EyelineGuidesComponent: Component {
    var isOn = false
    /// The objects container whose characters get guides.
    var characters: Entity?
}

/// Draws a faint cone from each character's eyes along where it's looking, and, when the
/// scene has exactly two characters, the 180° line through them: the line the camera
/// stays on one side of so their screen directions don't flip between shots.
struct EyelineSystem: System {
    static let coneLength: Float = 0.09
    static let coneRadius: Float = 0.022
    /// How far the 180° line runs past each character.
    static let lineOverhang: Float = 0.12

    private static let query = EntityQuery(where: .has(EyelineGuidesComponent.self))

    init(scene: RealityKit.Scene) {}

    func update(context: SceneUpdateContext) {
        for root in context.entities(matching: Self.query, updatingSystemWhen: .rendering) {
            Self.refresh(root)
        }
    }

    /// Lays out the guides under `root` for the characters as they are now.
    static func refresh(_ root: Entity) {
        guard let guides = root.components[EyelineGuidesComponent.self] else { return }
        layOut(root, characters: guides.isOn ? visibleCharacters(in: guides.characters) : [])
    }

    /// Placed, visible characters with their rigs.
    private static func visibleCharacters(in container: Entity?) -> [(object: Entity, rig: Entity)] {
        guard let container else { return [] }
        return container.children.compactMap { object in
            guard object.isEnabledInHierarchy, object.components.has(PlacedObjectComponent.self),
                  let rig = CharacterBuilder.rig(in: object) else { return nil }
            return (object, rig)
        }
    }

    private static func layOut(_ root: Entity, characters: [(object: Entity, rig: Entity)]) {
        let cones = root.children.filter { $0.name == coneName }
        for (index, character) in characters.enumerated() {
            let cone = index < cones.count ? cones[index] : makeCone(in: root)
            cone.isEnabled = place(cone, at: character.rig)
        }
        for extra in cones.dropFirst(characters.count) { extra.isEnabled = false }

        let line = root.children.first { $0.name == lineName } ?? makeLine(in: root)
        line.isEnabled = characters.count == 2 && placeLine(line, between: characters[0].object, characters[1].object)
    }

    // MARK: Cones

    private static let coneName = "EyelineCone"
    private static let lineName = "EyelineAxis"

    private static func makeCone(in root: Entity) -> Entity {
        let holder = Entity()
        holder.name = coneName
        var material = UnlitMaterial(color: UIColor(red: 1, green: 0.84, blue: 0.3, alpha: 1))
        material.blending = .transparent(opacity: 0.28)
        // A cone's tip points up its +Y. Turn the tip back toward the eyes, opening forward (+Z).
        let cone = ModelEntity(mesh: .generateCone(height: coneLength, radius: coneRadius), materials: [material])
        cone.orientation = simd_quatf(angle: -.pi / 2, axis: [1, 0, 0])
        cone.position = [0, 0, coneLength / 2]
        holder.addChild(cone)
        // A brighter center line marks the exact direction.
        var lineMaterial = UnlitMaterial(color: UIColor(red: 1, green: 0.84, blue: 0.3, alpha: 1))
        lineMaterial.blending = .transparent(opacity: 0.8)
        let ray = ModelEntity(mesh: .generateBox(size: [0.0008, 0.0008, coneLength * 1.6]), materials: [lineMaterial])
        ray.position = [0, 0, coneLength * 0.8]
        holder.addChild(ray)
        root.addChild(holder)
        return holder
    }

    /// Puts the cone at the character's eyes, facing where its head faces, at a fixed size.
    private static func place(_ cone: Entity, at rig: Entity) -> Bool {
        guard let head = CharacterBuilder.joints(in: rig)[.head],
              let proportions = rig.components[CharacterRigComponent.self]?.proportions else { return false }
        let eyes = head.convert(position: HeadAim.eyeOffset(layout: RigLayout(proportions: proportions)), to: nil)
        let facing = head.convert(direction: [0, 0, 1], to: nil)
        guard simd_length(facing) > 1e-6 else { return false }
        cone.setPosition(eyes, relativeTo: nil)
        cone.setOrientation(simd_quatf(from: [0, 0, 1], to: simd_normalize(facing)), relativeTo: nil)
        cone.setScale([1, 1, 1], relativeTo: nil)
        return true
    }

    // MARK: 180° line

    private static func makeLine(in root: Entity) -> Entity {
        var material = UnlitMaterial(color: UIColor(red: 1, green: 0.45, blue: 0.35, alpha: 1))
        material.blending = .transparent(opacity: 0.7)
        let line = ModelEntity(mesh: .generateBox(size: [1, 0.0006, 0.0016]), materials: [material])
        line.name = lineName
        root.addChild(line)
        return line
    }

    /// Lays the line on the ground through both characters, running a little past each.
    private static func placeLine(_ line: Entity, between a: Entity, _ b: Entity) -> Bool {
        let start = a.position(relativeTo: nil)
        let end = b.position(relativeTo: nil)
        var direction = end - start
        direction.y = 0
        let length = simd_length(direction)
        guard length > 1e-4 else { return false }
        let middle = (start + end) / 2
        line.setPosition([middle.x, min(start.y, end.y) + 0.001, middle.z], relativeTo: nil)
        line.setOrientation(simd_quatf(from: [1, 0, 0], to: direction / length), relativeTo: nil)
        line.setScale([length + 2 * lineOverhang, 1, 1], relativeTo: nil)
        return true
    }
}
