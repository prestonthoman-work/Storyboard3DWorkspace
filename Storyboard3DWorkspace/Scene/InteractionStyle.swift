//
//  InteractionStyle.swift
//  Storyboard3DWorkspace
//

import RealityKit
import UIKit

/// One look for everything you can grab, in the workspace and in the Pose Studio: what's
/// selected, what you're looking at, what you're holding, and which way a handle turns.
///
/// Colors follow the app's theme: the cool cyan already used for selection and the stage's
/// front notch, and the warm brass of the base's turntable band.
enum InteractionStyle {
    /// Selected objects and body parts, the turn ring, snap guides.
    static let selection = UIColor(red: 0.42, green: 0.80, blue: 1, alpha: 1)
    /// The tilt ring: brass, like the base's band, so the two rings never read as one.
    static let tilt = UIColor(red: 0.96, green: 0.74, blue: 0.40, alpha: 1)
    /// Resize handle and neutral marks.
    static let neutral = UIColor.white

    /// How strongly handles show. Idle handles stay quiet so they never compete with the set.
    enum Emphasis {
        case idle, active, dimmed

        var opacity: Float {
            switch self {
            case .idle: 0.55
            case .active: 0.95
            case .dimmed: 0.14
            }
        }
    }

    /// The selection disc under an object: brighter while it's in your hand.
    static func selectionDiscOpacity(isHeld: Bool) -> Float { isHeld ? 0.62 : 0.34 }

    static func unlit(_ color: UIColor, opacity: Float) -> UnlitMaterial {
        var material = UnlitMaterial(color: color)
        material.blending = .transparent(opacity: .init(floatLiteral: opacity))
        return material
    }

    /// The gaze highlight for anything grabbable: a soft wash of the selection color.
    static var hover: HoverEffectComponent {
        HoverEffectComponent(.highlight(.init(color: selection, strength: 0.7)))
    }
}
