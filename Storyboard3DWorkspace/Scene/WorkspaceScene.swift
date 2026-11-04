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
///   - `stageModel`: the transform the user moves, rotates, and scales
///     - the current model content
///     - the selection indicator
///   - `backdrop`: a viewer-facing image plane, positioned by `ViewerFacingBackdropSystem`
final class WorkspaceScene {
    /// About 1.3 m ahead of where the immersive space opened, near seated eye level.
    static let defaultModelPosition = SIMD3<Float>(0, 1.0, -1.3)
    static let scaleRange: ClosedRange<Float> = 0.25...4
    static let selectionIndicatorName = "SelectionIndicator"

    private static let backdropHeight: Float = 1.9
    private static let backdropMaxWidth: Float = 4.5

    let root = Entity()
    let stageModel = Entity()
    let backdrop = ModelEntity()

    private let selectionIndicator = ModelEntity()
    private var modelContent: Entity?

    /// Keeps RealityView event subscriptions alive.
    var subscriptions: [EventSubscription] = []

    init() {
        root.name = "WorkspaceRoot"

        stageModel.name = "StageModel"
        stageModel.position = Self.defaultModelPosition
        root.addChild(stageModel)

        selectionIndicator.name = Self.selectionIndicatorName
        selectionIndicator.isEnabled = false
        stageModel.addChild(selectionIndicator)

        backdrop.name = "Backdrop"
        backdrop.isEnabled = false
        backdrop.components.set(ViewerFacingBackdropComponent(target: stageModel))
        root.addChild(backdrop)
    }

    // MARK: Model

    func setModelContent(_ content: Entity) {
        modelContent?.removeFromParent()
        stageModel.addChild(content)
        modelContent = content

        let bounds = content.visualBounds(relativeTo: stageModel)

        // One collision box around the whole model so the system manipulation
        // gestures treat it as a single object.
        let shape = ShapeResource.generateBox(size: bounds.extents).offsetBy(translation: bounds.center)
        ManipulationComponent.configureEntity(
            stageModel,
            hoverEffect: .spotlight(.default),
            allowedInputTypes: .all,
            collisionShapes: [shape]
        )
        if var manipulation = stageModel.components[ManipulationComponent.self] {
            manipulation.releaseBehavior = .stay
            stageModel.components.set(manipulation)
        }

        let radius = max(bounds.extents.x, bounds.extents.z) * 0.62
        var indicatorMaterial = UnlitMaterial(color: .white)
        indicatorMaterial.blending = .transparent(opacity: 0.35)
        selectionIndicator.model = ModelComponent(
            mesh: .generateCylinder(height: 0.002, radius: radius),
            materials: [indicatorMaterial]
        )
        selectionIndicator.position = [bounds.center.x, bounds.min.y - 0.004, bounds.center.z]

        resetModelPlacement()
    }

    func resetModelPlacement() {
        stageModel.transform = Transform(scale: .one, rotation: simd_quatf(), translation: Self.defaultModelPosition)
    }

    func setSelectionVisible(_ isVisible: Bool) {
        selectionIndicator.isEnabled = isVisible && modelContent != nil
    }

    /// Keeps two-handed scaling within a usable range.
    func clampModelScale() {
        let scale = stageModel.scale
        let uniform = min(max(scale.x, Self.scaleRange.lowerBound), Self.scaleRange.upperBound)
        if abs(uniform - scale.x) > .ulpOfOne {
            stageModel.scale = SIMD3(repeating: uniform)
        }
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
