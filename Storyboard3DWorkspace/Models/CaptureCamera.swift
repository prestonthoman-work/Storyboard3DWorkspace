//
//  CaptureCamera.swift
//  Storyboard3DWorkspace
//

import Foundation
import simd

/// Lens choices for captures, named by full-frame focal length like a Blender camera.
enum CaptureLens: Int, Codable, CaseIterable, Identifiable {
    case wide = 24
    case standard = 35
    case normal = 50
    case portrait = 85

    var id: Int { rawValue }
    var label: String { "\(rawValue) mm" }

    /// Output frame aspect ratio (16:9).
    static let aspect: Float = 16 / 9

    /// Vertical field of view in radians, for a 36 mm-wide sensor cropped to 16:9.
    var verticalFOV: Float {
        let sensorHeight: Float = 36 / Self.aspect
        return 2 * atan(sensorHeight / 2 / Float(rawValue))
    }

    var horizontalFOV: Float {
        2 * atan(tan(verticalFOV / 2) * Self.aspect)
    }
}

/// Where the capture camera is and which way it looks.
struct CaptureCamera {
    var position: SIMD3<Float>
    /// Camera looks down local -Z with +Y up.
    var orientation: simd_quatf
    var lens: CaptureLens

    /// A camera at the viewer's head, facing where they face, with the roll removed so
    /// the horizon stays level, like a camera on a tripod.
    static func level(fromHead head: simd_float4x4, lens: CaptureLens) -> CaptureCamera {
        let position = SIMD3(head.columns.3.x, head.columns.3.y, head.columns.3.z)
        let forward = -SIMD3(head.columns.2.x, head.columns.2.y, head.columns.2.z)
        return CaptureCamera(position: position, orientation: .upright(facing: -forward), lens: lens)
    }

    /// Used when head tracking isn't available (such as in Simulator): stand at `position`
    /// and look straight at `target`.
    static func looking(from position: SIMD3<Float>, at target: SIMD3<Float>, lens: CaptureLens) -> CaptureCamera {
        CaptureCamera(position: position, orientation: .upright(facing: position - target), lens: lens)
    }
}
