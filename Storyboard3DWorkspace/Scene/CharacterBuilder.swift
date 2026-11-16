//
//  CharacterBuilder.swift
//  Storyboard3DWorkspace
//

import RealityKit
import UIKit

// MARK: Components

/// The pose of a placed character. Lives on the placed object, so it survives the
/// character's geometry being rebuilt (a new color or proportions) and is copied with it.
struct CharacterPoseComponent: Component {
    var pose: CharacterPose
}

/// Marks the root of a built-in character's geometry and the proportions it was built with.
struct CharacterRigComponent: Component {
    var proportions: CharacterProportions
}

/// Marks a rig joint: the entity that turns when the joint is posed.
struct JointComponent: Component {
    var joint: Joint
}

/// Marks a piece of a character's body, and the joint that moves it, so tapping it can
/// select that joint.
struct BodyPartComponent: Component {
    var joint: Joint
}

/// Editing aids (joint markers) that must never appear in photos, exports, or ghosts.
struct EditorOnlyComponent: Component {}

// MARK: Building

/// Builds the poseable characters: a mannequin of rounded segments and ball joints, laid out
/// at human size on a rig of jointed entities, then shrunk to the miniature's scale.
///
/// Hierarchy: content root (`CharacterRigComponent`) → scaler → pelvis joint → … Each joint
/// entity holds the segment that hangs from it and its child joints, so turning a shoulder
/// carries the arm and hand.
enum CharacterBuilder {
    static let scalerName = "CharacterScale"
    static let markerName = "JointMarker"

    static func defaultColor(for kind: CharacterKind) -> UIColor {
        switch kind {
        case .mannequin: UIColor(red: 0.86, green: 0.74, blue: 0.58, alpha: 1)
        case .child: UIColor(red: 0.70, green: 0.80, blue: 0.90, alpha: 1)
        case .stocky: UIColor(red: 0.66, green: 0.68, blue: 0.72, alpha: 1)
        }
    }

    static func make(_ kind: CharacterKind, proportions: CharacterProportions, tint: UIColor?) -> Entity {
        let proportions = proportions.clamped
        let layout = RigLayout(proportions: proportions)
        let body = tint ?? defaultColor(for: kind)
        let jointColor = shade(body, 0.72)

        let content = Entity()
        content.name = kind.name
        content.components.set(CharacterRigComponent(proportions: proportions))

        let scaler = Entity()
        scaler.name = scalerName
        scaler.scale = SIMD3(repeating: RigLayout.miniatureScale * proportions.height)
        content.addChild(scaler)

        var joints: [Joint: Entity] = [:]
        for joint in Joint.allCases {
            let entity = Entity()
            entity.name = "Joint." + joint.rawValue
            entity.position = layout.offset(of: joint)
            entity.components.set(JointComponent(joint: joint))
            if let parent = joint.parent, let parentEntity = joints[parent] {
                parentEntity.addChild(entity)
            } else {
                scaler.addChild(entity)
            }
            joints[joint] = entity
            for part in parts(for: joint, layout: layout, body: body, jointColor: jointColor) {
                part.components.set(BodyPartComponent(joint: joint))
                part.components.set(GroundingShadowComponent(castsShadow: true))
                entity.addChild(part)
            }
            entity.addChild(makeMarker())
        }
        apply(.neutral, to: content)
        return content
    }

    /// The segment that hangs from a joint, plus the ball joint itself.
    private static func parts(for joint: Joint, layout: RigLayout, body: UIColor, jointColor: UIColor) -> [ModelEntity] {
        let build = layout.proportions.build
        let head = layout.proportions.head
        func segment(_ size: SIMD3<Float>, at position: SIMD3<Float>, radius: Float) -> ModelEntity {
            LowPoly.box(size, body, at: position, cornerRadius: radius, finish: .satin)
        }
        func ball(_ radius: Float) -> ModelEntity {
            LowPoly.sphere(radius: radius, jointColor, at: .zero, finish: .satin)
        }

        switch joint {
        case .pelvis:
            return [segment([0.30 * build, 0.15, 0.18 * build], at: [0, -0.02, 0], radius: 0.05)]
        case .spine:
            return [ball(0.07 * build), segment([0.25 * build, 0.17, 0.15 * build], at: [0, 0.10, 0], radius: 0.05)]
        case .chest:
            return [segment([0.36 * build, 0.27, 0.20 * build], at: [0, 0.12, 0], radius: 0.07)]
        case .neck:
            return [LowPoly.cylinder(height: 0.09, radius: 0.045 * build, jointColor, at: [0, 0.04, 0], finish: .satin)]
        case .head:
            let skull = LowPoly.sphere(radius: 0.105 * head, body, at: [0, 0.11 * head, 0], finish: .satin)
            skull.scale = [1, 1.15, 1.05]
            // A small nose, so which way the character faces always reads, even in silhouette.
            let nose = LowPoly.box([0.03 * head, 0.045 * head, 0.04 * head], body, at: [0, 0.10 * head, 0.105 * head],
                                   cornerRadius: 0.008, finish: .satin)
            return [skull, nose]
        case .leftShoulder, .rightShoulder:
            let length = layout.upperArm
            return [ball(0.058 * build), segment([0.085 * build, length - 0.05, 0.085 * build], at: [0, -length / 2, 0], radius: 0.035)]
        case .leftElbow, .rightElbow:
            let length = layout.forearm
            return [ball(0.046 * build), segment([0.072 * build, length - 0.04, 0.072 * build], at: [0, -length / 2, 0], radius: 0.03)]
        case .leftWrist, .rightWrist:
            return [segment([0.04, 0.17, 0.09], at: [0, -0.09, 0.005], radius: 0.018)]
        case .leftHip, .rightHip:
            let length = layout.thigh
            return [ball(0.068 * build), segment([0.13 * build, length - 0.06, 0.13 * build], at: [0, -length / 2, 0], radius: 0.05)]
        case .leftKnee, .rightKnee:
            let length = layout.shin
            return [ball(0.055 * build), segment([0.10 * build, length - 0.05, 0.10 * build], at: [0, -length / 2, 0], radius: 0.04)]
        case .leftAnkle, .rightAnkle:
            let height = layout.ankleHeight
            return [segment([0.10 * build, height, 0.25], at: [0, -height / 2, 0.06], radius: 0.03)]
        }
    }

    private static func makeMarker() -> ModelEntity {
        var material = UnlitMaterial(color: .white)
        material.blending = .transparent(opacity: 0.85)
        let marker = ModelEntity(mesh: .generateSphere(radius: 0.065), materials: [material])
        marker.name = markerName
        marker.components.set(EditorOnlyComponent())
        marker.isEnabled = false
        return marker
    }

    private static func shade(_ color: UIColor, _ amount: CGFloat) -> UIColor {
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return UIColor(hue: h, saturation: s, brightness: min(max(b * amount, 0), 1), alpha: a)
    }

    // MARK: Posing

    /// Every joint entity in a character's geometry.
    static func joints(in content: Entity) -> [Joint: Entity] {
        var result: [Joint: Entity] = [:]
        func visit(_ entity: Entity) {
            if let joint = entity.components[JointComponent.self]?.joint { result[joint] = entity }
            entity.children.forEach(visit)
        }
        visit(content)
        return result
    }

    /// The character geometry under a placed object (or a copy of it), if it has any.
    static func rig(in object: Entity) -> Entity? {
        if object.components.has(CharacterRigComponent.self) { return object }
        return object.children.first { $0.components.has(CharacterRigComponent.self) }
    }

    /// Turns every joint to match `pose`.
    /// - Parameter grounded: Shift the body so its lowest point rests at the content's
    ///   origin, the way every placed object rests on y = 0. Off while a hand or foot is
    ///   being dragged, so the body doesn't shift under the gesture.
    static func apply(_ pose: CharacterPose, to content: Entity, grounded: Bool = true) {
        guard let rig = content.components[CharacterRigComponent.self] else { return }
        let joints = joints(in: content)
        for (joint, entity) in joints {
            entity.orientation = CharacterKinematics.rotation(pose[joint], for: joint)
        }
        guard grounded, let pelvis = joints[.pelvis], let scaler = pelvis.parent else { return }
        pelvis.position = RigLayout(proportions: rig.proportions).offset(of: .pelvis)
        if let lowest = lowestPoint(of: content, in: scaler) {
            pelvis.position.y -= lowest
        }
    }

    /// The lowest point of the body's geometry in `space`, ignoring editing aids.
    private static func lowestPoint(of content: Entity, in space: Entity) -> Float? {
        var lowest: Float?
        func visit(_ entity: Entity) {
            if entity.components.has(BodyPartComponent.self) {
                let bounds = entity.visualBounds(relativeTo: space)
                if !bounds.isEmpty { lowest = min(lowest ?? .infinity, bounds.min.y) }
            }
            entity.children.forEach(visit)
        }
        visit(content)
        return lowest
    }

    /// Shows or hides the joint markers, highlighting the selected joint.
    static func showMarkers(_ isVisible: Bool, selected: Joint?, in content: Entity) {
        for (joint, entity) in joints(in: content) {
            guard let marker = entity.children.first(where: { $0.name == markerName }) as? ModelEntity else { continue }
            marker.isEnabled = isVisible
            let isSelected = joint == selected
            var material = UnlitMaterial(color: isSelected ? UIColor(red: 0.35, green: 0.85, blue: 1, alpha: 1) : .white)
            material.blending = .transparent(opacity: .init(floatLiteral: isSelected ? 1 : 0.7))
            marker.model?.materials = [material]
            marker.scale = SIMD3(repeating: isSelected ? 1.45 : 1)
        }
    }

    /// Body parts become tappable while posing, each with a target a little larger than the
    /// part so small limbs are easier to pick.
    static func setPartsTappable(_ isTappable: Bool, in content: Entity) {
        func visit(_ entity: Entity) {
            if entity.components.has(BodyPartComponent.self) {
                if isTappable, let model = entity as? ModelEntity, let mesh = model.model?.mesh {
                    let bounds = mesh.bounds
                    let size = simd_max(bounds.extents * 1.25, SIMD3(repeating: 0.11))
                    entity.components.set(CollisionComponent(shapes: [ShapeResource.generateBox(size: size).offsetBy(translation: bounds.center)]))
                    entity.components.set(InputTargetComponent())
                    entity.components.set(HoverEffectComponent())
                } else {
                    entity.components.remove(CollisionComponent.self)
                    entity.components.remove(InputTargetComponent.self)
                    entity.components.remove(HoverEffectComponent.self)
                }
            }
            entity.children.forEach(visit)
        }
        visit(content)
    }

    /// Removes every editing aid from a copy of the scene (photos, exports, onion skin ghosts).
    static func stripEditorOnly(from entity: Entity) {
        for child in Array(entity.children) {
            if child.components.has(EditorOnlyComponent.self) {
                child.removeFromParent()
            } else {
                stripEditorOnly(from: child)
            }
        }
    }
}
