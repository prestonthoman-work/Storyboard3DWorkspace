//
//  ViewerFacingBackdrop.swift
//  Storyboard3DWorkspace
//

import RealityKit
import simd

/// Shared measurements for the backdrop, used by the live scene and by capture so both
/// show the same part of the image behind the scene.
enum BackdropLayout {
    static let height: Float = 1.9
    static let maxWidth: Float = 4.5
    /// Gap between the far side of the scene and the backdrop, in meters.
    static let gapBehindTarget: Float = 0.9
    /// How far the backdrop is raised along its own up direction, in meters. Lifts most
    /// of the image above the scene instead of hanging down toward the floor.
    static let preferredLift: Float = 0.6

    /// The lift for a plane of the given height, capped so the image always extends at
    /// least 15 cm below the scene's center (matters for short, wide panoramas).
    static func lift(forHeight height: Float) -> Float {
        max(min(preferredLift, height / 2 - 0.15), 0)
    }

    /// Plane size for an image of the given aspect ratio (width / height).
    static func size(forAspect aspect: Float) -> SIMD2<Float> {
        var height = Self.height
        var width = height * aspect
        if width > maxWidth {
            width = maxWidth
            height = width / aspect
        }
        return [width, height]
    }
}

/// Marks a plane that should stay behind `target` from the viewer's point of view.
struct ViewerFacingBackdropComponent: Component {
    /// The entity the backdrop sits behind. Only the backdrop moves; the target is never changed.
    var target: Entity?
    /// Set from `BackdropLayout.lift(forHeight:)` whenever the image changes.
    var lift: Float = BackdropLayout.preferredLift
    /// Higher values follow the viewer more tightly; lower values glide more.
    var responsiveness: Float = 6
    var hasBeenPlaced = false
}

/// Each frame, places the backdrop on the far side of its target along the line from
/// the viewer's head through the target's center, then turns the plane to face the
/// viewer. Walking around the model swings the backdrop around it, so the model
/// always reads against the image. The plane is kept upright, so it never rolls, and is
/// raised by its `lift` so it rises above the scene.
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

            let behind = center + direction * (radius + BackdropLayout.gapBehindTarget)
            let goalOrientation = simd_quatf.upright(facing: viewer - behind)
            let goalPosition = behind + goalOrientation.act([0, component.lift, 0])

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
