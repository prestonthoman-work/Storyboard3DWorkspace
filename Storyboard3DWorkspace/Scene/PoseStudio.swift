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
///
/// The stage is a miniature of the set's own base: a walnut plinth on a dark metal foot with
/// a brass inlay, topped with a pale maple deck. A fine degree ring around the deck shows how
/// far the view has turned, with a cyan notch at the character's front. It sits on the floor
/// of the volume, so when the volume is set down on a table the plinth rests on the tabletop.
@MainActor
final class PoseStudioScene {
    /// How tall the default mannequin stands in the studio, in meters.
    static let figureHeight: Float = 0.55
    /// The deck's height above the bottom of the plinth.
    static let plinthHeight: Float = 0.03
    /// Where the bottom of the volume is, when its size isn't known yet (a 0.85 m tall volume).
    static let defaultVolumeFloor: Float = -0.425
    /// The plinth's outer radius.
    static let stageRadius: Float = 0.3

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
    /// A volume floor waiting until a drag ends, so the stage never shifts mid-pose.
    private var pendingFloor: Float?

    static let highlightColor = InteractionStyle.selection

    init() {
        root.name = "PoseStudio"
        root.position = [0, Self.defaultVolumeFloor + Self.plinthHeight, 0]
        root.addChild(stage)
        stage.addChild(holder)
        holder.scale = SIMD3(repeating: Self.figureHeight / (RigLayout.humanHeight * RigLayout.miniatureScale))
        Self.buildPlinth(on: stage)
    }

    /// Rests the plinth on the bottom of the volume (`floor`, in the volume's scene space).
    /// While a body part is being dragged, the move waits until the drag ends.
    func setVolumeFloor(_ floor: Float, isEditing: Bool) {
        let target = floor + Self.plinthHeight
        guard abs(target - root.position.y) > 0.0005 else {
            pendingFloor = nil
            return
        }
        if isEditing {
            pendingFloor = floor
        } else {
            root.position.y = target
            pendingFloor = nil
        }
    }

    /// Applies a floor change held back during a drag.
    func editingEnded() {
        if let pendingFloor { setVolumeFloor(pendingFloor, isEditing: false) }
    }

    // MARK: Stage

    private static let walnut = UIColor(red: 0.27, green: 0.18, blue: 0.12, alpha: 1)
    private static let walnutLight = UIColor(red: 0.36, green: 0.25, blue: 0.17, alpha: 1)
    private static let maple = UIColor(red: 0.80, green: 0.76, blue: 0.70, alpha: 1)
    private static let mapleInlay = UIColor(red: 0.70, green: 0.65, blue: 0.58, alpha: 1)
    private static let brass = UIColor(red: 0.74, green: 0.6, blue: 0.38, alpha: 1)

    /// Builds the plinth with its deck at y = 0.
    private static func buildPlinth(on stage: Entity) {
        let r = stageRadius
        let bottom = -plinthHeight
        func add(_ builder: MeshBuilder, _ name: String, _ material: any RealityKit.Material) {
            guard let entity = builder.makeEntity(named: name, material: material) else { return }
            // Shadows ground the plinth on a real table, and let the figure's shadow fall on the deck.
            entity.components.set(GroundingShadowComponent(castsShadow: true, receivesShadow: true))
            stage.addChild(entity)
        }

        var foot = MeshBuilder()
        foot.addFrustum(bottomRadius: r, topRadius: r, bottomY: bottom, topY: bottom + 0.005, capBottom: true)
        add(foot, "StudioFoot", LowPoly.material(UIColor(white: 0.11, alpha: 1), .metal))

        var body = MeshBuilder()
        body.addFrustum(bottomRadius: r - 0.004, topRadius: r - 0.011, bottomY: bottom + 0.005, topY: -0.0062, capTop: false)
        add(body, "StudioBody", LowPoly.material(walnut, .satin))

        var band = MeshBuilder()
        band.addFrustum(bottomRadius: r - 0.011, topRadius: r - 0.0115, bottomY: -0.0062, topY: -0.0042, capTop: false)
        add(band, "StudioBrass", LowPoly.material(brass, .metal))

        // The bevel catches the light along the top edge.
        var lip = MeshBuilder()
        lip.addFrustum(bottomRadius: r - 0.0115, topRadius: r - 0.018, bottomY: -0.0042, topY: -0.0012, capTop: false)
        add(lip, "StudioLip", LowPoly.material(walnutLight, .satin))

        var deck = MeshBuilder()
        deck.addFrustum(bottomRadius: r - 0.018, topRadius: r - 0.018, bottomY: -0.0012, topY: 0)
        if let entity = deck.makeEntity(named: "StudioFloor", material: LowPoly.material(maple, .satin)) {
            entity.components.set(GroundingShadowComponent(castsShadow: false, receivesShadow: true))
            // Drag the stage (deck or edge) to turn the view.
            entity.components.set(StudioTurntableComponent())
            entity.components.set(InputTargetComponent())
            entity.components.set(CollisionComponent(shapes: [
                ShapeResource.generateBox(size: [2 * r, plinthHeight + 0.01, 2 * r]).offsetBy(translation: [0, -plinthHeight / 2, 0])
            ]))
            entity.components.set(InteractionStyle.hover)
            stage.addChild(entity)
        }

        // Inlays, just proud of the deck: a fine degree ring with a tick every 15°, brass at
        // the quarters, and a faint circle where the figure stands.
        var ring = MeshBuilder()
        ring.addRing(innerRadius: r - 0.040, outerRadius: r - 0.0375, y: 0.0003, segments: 120)
        ring.addRing(innerRadius: 0.066, outerRadius: 0.0675, y: 0.0003, segments: 72)
        var ticks = MeshBuilder()
        var quarters = MeshBuilder()
        for step in 0..<24 where step % 6 != 0 {
            let angle = Float(step) / 24 * 2 * .pi
            ticks.addBox(center: [sin(angle) * (r - 0.046), 0.0004, cos(angle) * (r - 0.046)],
                         size: [0.0012, 0.0008, 0.008], yaw: angle)
        }
        // The quarters, except the front, which has the cyan notch.
        for quarter in 1..<4 {
            let angle = Float(quarter) / 4 * 2 * .pi
            quarters.addBox(center: [sin(angle) * (r - 0.048), 0.0005, cos(angle) * (r - 0.048)],
                            size: [0.002, 0.001, 0.013], yaw: angle)
        }
        add(ring, "StudioInlay", LowPoly.material(mapleInlay, .satin))
        add(ticks, "StudioTicks", LowPoly.material(mapleInlay, .satin))
        add(quarters, "StudioQuarters", LowPoly.material(brass, .metal))

        // The front notch, so it's clear which way the stage is turned.
        let notch = ModelEntity(mesh: .generateBox(size: [0.03, 0.0014, 0.01], cornerRadius: 0.0006),
                                materials: [UnlitMaterial(color: InteractionStyle.selection)])
        notch.name = "StudioFrontNotch"
        notch.position = [0, 0.0006, r - 0.028]
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
            Self.castShadows(in: content)
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

    /// The figure casts a soft shadow onto the deck.
    private static func castShadows(in entity: Entity) {
        if entity.components.has(ModelComponent.self) {
            entity.components.set(GroundingShadowComponent(castsShadow: true))
        }
        entity.children.forEach(castShadows)
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
