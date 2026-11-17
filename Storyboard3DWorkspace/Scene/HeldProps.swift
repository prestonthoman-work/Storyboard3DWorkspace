//
//  HeldProps.swift
//  Storyboard3DWorkspace
//

import RealityKit
import simd

/// A character's hand.
enum Hand: String, Codable, CaseIterable, Identifiable {
    case left, right

    var id: String { rawValue }
    var wrist: Joint { self == .left ? .leftWrist : .rightWrist }
    var name: String { self == .left ? "Left Hand" : "Right Hand" }
}

/// An object held in a character's hand. It follows the hand through every pose change and
/// keyframe until it's let go.
struct Hold: Codable, Equatable {
    var character: ObjectID
    var hand: Hand
    /// Where the object sits relative to the wrist joint.
    var offset: CodableTransform
}

/// Marks a placed object as held. The object stays in the scene's object container (so
/// lists, selection, and saving treat it like any object); `HeldPropSystem` moves it to the
/// hand every frame.
struct HeldPropComponent: Component {
    var hold: Hold
}

/// Keeps held objects in their characters' hands. A held object that's being moved by hand
/// is left alone until it's let go, when its new grip is recorded.
struct HeldPropSystem: System {
    private static let query = EntityQuery(where: .has(HeldPropComponent.self))

    init(scene: RealityKit.Scene) {}

    func update(context: SceneUpdateContext) {
        for prop in context.entities(matching: Self.query, updatingSystemWhen: .rendering)
        where !(prop.components[ObjectGravityComponent.self]?.isHeld ?? false) {
            HeldProps.attach(prop)
        }
    }
}

enum HeldProps {
    /// Moves a held object to its character's hand. Returns false if the character or its
    /// hand can't be found, leaving the object where it is.
    @discardableResult
    static func attach(_ prop: Entity) -> Bool {
        guard let hold = prop.components[HeldPropComponent.self]?.hold,
              let wrist = wrist(for: hold, near: prop) else { return false }
        prop.setTransformMatrix(wrist.transformMatrix(relativeTo: nil) * hold.offset.transform.matrix, relativeTo: nil)
        return true
    }

    /// Puts every held object under `root` in its hand, such as right before a render.
    static func attachAll(in root: Entity) {
        if root.components.has(HeldPropComponent.self) { attach(root) }
        for child in root.children { attachAll(in: child) }
    }

    /// The wrist joint holding the object, found among the object's siblings.
    static func wrist(for hold: Hold, near prop: Entity) -> Entity? {
        guard let character = prop.parent?.children.first(where: {
            $0.components[PlacedObjectComponent.self]?.id == hold.character
        }), let rig = CharacterBuilder.rig(in: character) else { return nil }
        return CharacterBuilder.joints(in: rig)[hold.hand.wrist]
    }

    /// Where an object goes when first put in a hand: centered in the palm, keeping its own
    /// turn and size. Returns the hold's offset.
    static func grip(_ prop: Entity, in wrist: Entity) -> Transform {
        // The palm is a little past the wrist along the hand (which hangs down the wrist's -Y).
        let palm = wrist.convert(position: [0, -0.09, 0], to: nil)
        let bounds = WorkspaceScene.geometryBounds(of: prop) ?? BoundingBox()
        let center = prop.convert(position: bounds.center, to: nil)
        prop.setPosition(prop.position(relativeTo: nil) + (palm - center), relativeTo: nil)
        return offset(of: prop, from: wrist)
    }

    /// The offset that keeps the object exactly where it is now, relative to the wrist.
    static func offset(of prop: Entity, from wrist: Entity) -> Transform {
        Transform(matrix: wrist.transformMatrix(relativeTo: nil).inverse * prop.transformMatrix(relativeTo: nil))
    }
}
