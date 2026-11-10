//
//  OnionSkin.swift
//  Storyboard3DWorkspace
//

import RealityKit

/// Identifies what the onion skin shows: which objects, in which poses, under which names
/// (a name change means new geometry, such as a recolor).
struct OnionSkinKey: Equatable {
    var poses: [ObjectID: Transform]
    var names: [ObjectID: String]

    static func == (a: Self, b: Self) -> Bool {
        a.names == b.names && KeyframeTimeline.posesMatch(a.poses, b.poses)
    }
}

extension WorkspaceScene {
    static let onionSkinOpacity: Float = 0.28

    /// Shows faint copies of objects at `poses`, the way animators see the previous drawing
    /// under the current one. Nil or empty clears them.
    func setOnionSkin(_ poses: [ObjectID: Transform]?) {
        let poses = poses ?? [:]
        let names = Dictionary(uniqueKeysWithValues: poses.keys.compactMap { id in
            object(withID: id).map { (id, $0.name) }
        })
        let key = OnionSkinKey(poses: poses, names: names)
        guard key != onionSkinKey else { return }
        onionSkinKey = key

        onionRoot.children.removeAll()
        for (id, pose) in poses {
            guard let object = object(withID: id) else { continue }
            let ghost = Entity()
            ghost.transform = pose
            for child in object.children where child.name != Self.selectionIndicatorName {
                let copy = child.clone(recursive: true)
                Self.stripForGhost(copy)
                ghost.addChild(copy)
            }
            ghost.components.set(OpacityComponent(opacity: Self.onionSkinOpacity))
            onionRoot.addChild(ghost)
        }
    }

    /// Ghosts are look-only: nothing to grab, tap, or fall.
    private static func stripForGhost(_ entity: Entity) {
        entity.components.remove(ManipulationComponent.self)
        entity.components.remove(InputTargetComponent.self)
        entity.components.remove(HoverEffectComponent.self)
        entity.components.remove(CollisionComponent.self)
        entity.components.remove(ObjectGravityComponent.self)
        entity.components.remove(PlacedObjectComponent.self)
        entity.components.remove(ScaleSpringComponent.self)
        for child in entity.children { stripForGhost(child) }
    }
}
