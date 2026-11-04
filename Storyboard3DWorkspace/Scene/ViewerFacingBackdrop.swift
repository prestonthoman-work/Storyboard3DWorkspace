//
//  ViewerFacingBackdrop.swift
//  Storyboard3DWorkspace
//

import RealityKit
import simd

/// Marks a plane that should stay behind `target` from the viewer's point of view.
struct ViewerFacingBackdropComponent: Component {
    /// The entity the backdrop sits behind. Only the backdrop moves; the target is never changed.
    var target: Entity?
    /// Gap between the far side of the target and the backdrop, in meters.
    var gapBehindTarget: Float = 0.9
    /// Higher values follow the viewer more tightly; lower values glide more.
    var responsiveness: Float = 6
    var hasBeenPlaced = false
}

/// Each frame, places the backdrop on the far side of its target along the line from
/// the viewer's head through the target's center, then turns the plane to face the
/// viewer. Walking around the model swings the backdrop around it, so the model
/// always reads against the image. The plane is kept upright, so it never rolls.
struct ViewerFacingBackdropSystem: System {
    private static let query = EntityQuery(where: .has(ViewerFacingBackdropComponent.self))

    init(scene: Scene) {}

    func update(context: SceneUpdateContext) {
        let viewer = SpatialTrackingService.shared.viewerPosition

        for backdrop in context.entities(matching: Self.query, updatingSystemWhen: .rendering) {
            guard var component = backdrop.components[ViewerFacingBackdropComponent.self],
                  let target = component.target
            else { continue }

            let bounds = target.visualBounds(relativeTo: nil, excludeInactive: true)
            let center = bounds.isEmpty ? target.position(relativeTo: nil) : bounds.center
            let radius = bounds.isEmpty ? 0 : length(bounds.extents) / 2

            var direction = center - viewer
            if length(direction) < 0.05 { direction = [0, 0, -1] }
            direction = normalize(direction)

            let goalPosition = center + direction * (radius + component.gapBehindTarget)
            let goalOrientation = simd_quatf.upright(facing: viewer - goalPosition)

            if component.hasBeenPlaced {
                let blend = 1 - exp(-component.responsiveness * Float(context.deltaTime))
                let position = mix(backdrop.position(relativeTo: nil), goalPosition, t: blend)
                let orientation = simd_slerp(backdrop.orientation(relativeTo: nil), goalOrientation, blend)
                backdrop.setPosition(position, relativeTo: nil)
                backdrop.setOrientation(orientation, relativeTo: nil)
            } else {
                backdrop.setPosition(goalPosition, relativeTo: nil)
                backdrop.setOrientation(goalOrientation, relativeTo: nil)
                component.hasBeenPlaced = true
                backdrop.components.set(component)
            }
        }
    }
}
