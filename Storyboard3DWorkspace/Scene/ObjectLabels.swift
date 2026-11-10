//
//  ObjectLabels.swift
//  Storyboard3DWorkspace
//

import RealityKit
import SwiftUI

/// A floating name tag that follows one placed object. Tags live outside the staged scene,
/// so they never appear in photos.
struct ObjectLabelComponent: Component {
    var target: Entity?
    /// Set by the view: labels are on and this object isn't selected (its toolbar shows the name).
    var wantsVisible = false
}

/// Keeps each tag hovering just above its object, and hides it while the object is hidden
/// by the animation, held, or gone.
struct ObjectLabelSystem: System {
    private static let query = EntityQuery(where: .has(ObjectLabelComponent.self))

    init(scene: RealityKit.Scene) {}

    func update(context: SceneUpdateContext) {
        for entity in context.entities(matching: Self.query, updatingSystemWhen: .rendering) {
            guard let label = entity.components[ObjectLabelComponent.self] else { continue }
            guard label.wantsVisible, SceneFeedback.isEnabled, let target = label.target,
                  target.parent != nil, target.isEnabledInHierarchy,
                  !(target.components[ObjectGravityComponent.self]?.isHeld ?? false)
            else {
                entity.isEnabled = false
                continue
            }
            let bounds = target.visualBounds(relativeTo: nil)
            guard !bounds.isEmpty else { entity.isEnabled = false; continue }
            entity.isEnabled = true
            let top = SIMD3(bounds.center.x, bounds.max.y + 0.03, bounds.center.z)
            entity.setPosition(top, relativeTo: nil)
        }
    }
}

/// The tag itself: the object's name on a small glass capsule.
struct ObjectNameTag: View {
    let name: String

    var body: some View {
        Text(name)
            .font(.system(size: 15, weight: .semibold, design: .rounded))
            .lineLimit(1)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .glassBackgroundEffect(in: Capsule())
    }
}
