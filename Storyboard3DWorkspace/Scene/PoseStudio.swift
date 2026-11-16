//
//  PoseStudio.swift
//  Storyboard3DWorkspace
//

import RealityKit
import UIKit

/// Marks the Pose Studio's floor, which spins the view of the character when dragged.
struct StudioTurntableComponent: Component {}

/// The Pose Studio's content: a large copy of the selected character on a round stage, for
/// posing at a comfortable size. It mirrors the scene character and is never the source of
/// truth: every edit goes to the scene character, and the studio copy follows.
@MainActor
final class PoseStudioScene {
    /// How tall the default mannequin stands in the studio, in meters.
    static let figureHeight: Float = 0.55
    /// The studio floor sits this far below the volume's center.
    static let floorDepth: Float = 0.40

    let root = Entity()
    /// Turns to show the character from any side. Only the view turns; the character keeps
    /// its orientation in the scene.
    let stage = Entity()
    private let holder = Entity()
    private(set) var character: Entity?
    private var shownRecipe: ModelRecipe?
    private var shownJoint: Joint??
    /// Each body part's own materials, so a highlight can be taken off again.
    private var originalMaterials: [ObjectIdentifier: [any RealityKit.Material]] = [:]

    static let highlightColor = UIColor(red: 0.42, green: 0.80, blue: 1, alpha: 1)

    init() {
        root.name = "PoseStudio"
        root.position = [0, -Self.floorDepth, 0]
        root.addChild(stage)
        stage.addChild(holder)
        holder.scale = SIMD3(repeating: Self.figureHeight / (RigLayout.humanHeight * RigLayout.miniatureScale))

        let floor = ModelEntity(mesh: .generateCylinder(height: 0.008, radius: 0.3),
                                materials: [LowPoly.material(UIColor(white: 0.86, alpha: 1), .satin)])
        floor.name = "StudioFloor"
        floor.position = [0, -0.004, 0]
        floor.components.set(StudioTurntableComponent())
        floor.components.set(InputTargetComponent())
        floor.components.set(CollisionComponent(shapes: [.generateBox(size: [0.6, 0.02, 0.6])]))
        floor.components.set(HoverEffectComponent())
        stage.addChild(floor)

        // A notch at the front edge, so it's clear which way the stage is turned.
        let notch = ModelEntity(mesh: .generateBox(size: [0.04, 0.002, 0.012], cornerRadius: 0.001),
                                materials: [UnlitMaterial(color: UIColor(red: 0.35, green: 0.85, blue: 1, alpha: 1))])
        notch.position = [0, 0.001, 0.285]
        stage.addChild(notch)
    }

    /// Shows `recipe` in `pose`, rebuilding the figure only when the character itself
    /// changed (a new character, color, or proportions). Nil clears the stage.
    func show(recipe: ModelRecipe?, pose: CharacterPose?, grounded: Bool, selectedJoint: Joint?) {
        guard let recipe, recipe.characterKind != nil, let pose else {
            character?.removeFromParent()
            character = nil
            shownRecipe = nil
            shownJoint = nil
            return
        }
        if recipe != shownRecipe || character == nil, let content = recipe.makeEntity() {
            character?.removeFromParent()
            CharacterBuilder.setPartsTappable(true, in: content)
            holder.addChild(content)
            character = content
            shownRecipe = recipe
            shownJoint = nil
            originalMaterials = [:]
        }
        guard let character else { return }
        CharacterBuilder.apply(pose, to: character, grounded: grounded)
        if shownJoint != .some(selectedJoint) {
            shownJoint = .some(selectedJoint)
            highlight(selectedJoint, in: character)
        }
    }

    /// Tints the selected body part, including the ball joint it turns around.
    private func highlight(_ joint: Joint?, in character: Entity) {
        let tint = LowPoly.material(Self.highlightColor, .satin)
        func visit(_ entity: Entity) {
            if let part = entity.components[BodyPartComponent.self], let model = entity as? ModelEntity {
                let key = ObjectIdentifier(model)
                if originalMaterials[key] == nil { originalMaterials[key] = model.model?.materials ?? [] }
                model.model?.materials = part.joint == joint ? [tint] : originalMaterials[key] ?? []
            }
            entity.children.forEach(visit)
        }
        visit(character)
    }

    func jointEntity(_ joint: Joint) -> Entity? {
        character.flatMap { CharacterBuilder.joints(in: $0)[joint] }
    }

    /// The direction from a joint to a point (in the studio's scene space), in the joint's
    /// parent space: what `CharacterKinematics.swing` works with.
    func direction(from joint: Joint, to point: SIMD3<Float>) -> SIMD3<Float>? {
        guard let entity = jointEntity(joint), let parent = entity.parent else { return nil }
        return parent.convert(position: point, from: nil) - entity.position
    }

    /// Where a point (in the studio's scene space) is relative to a limb's shoulder or hip,
    /// in the space the IK solver uses.
    func limbSpacePoint(_ point: SIMD3<Float>, for limb: Limb) -> SIMD3<Float>? {
        guard let parentJoint = limb.root.parent, let parent = jointEntity(parentJoint),
              let root = jointEntity(limb.root) else { return nil }
        return parent.convert(position: point, from: nil) - root.position
    }

    // MARK: Turning the view

    /// The stage's turn, in radians. 0 shows the character's front.
    var viewAngle: Float {
        get { 2 * atan2(stage.orientation.imag.y, stage.orientation.real) }
        set { stage.orientation = simd_quatf(angle: newValue, axis: [0, 1, 0]) }
    }
}
