//
//  OrientationMath.swift
//  Storyboard3DWorkspace
//

import simd

extension simd_quatf {
    /// A rotation that points local +Z along `forward` while keeping local +Y as close
    /// to world up as possible, so the result never rolls.
    ///
    /// For a plane (front face +Z), pass the direction toward the viewer.
    /// For a camera (looks down -Z), pass the direction from the subject back to the camera.
    static func upright(facing forward: SIMD3<Float>) -> simd_quatf {
        // Free-function spellings avoid clashing with simd_quatf's own `length` and `normalized`.
        let zAxis = simd_normalize(forward)
        var xAxis = simd_cross(SIMD3<Float>(0, 1, 0), zAxis)
        if simd_length(xAxis) < 1e-4 { xAxis = [1, 0, 0] }
        xAxis = simd_normalize(xAxis)
        let yAxis = simd_cross(zAxis, xAxis)
        return simd_quatf(simd_float3x3(columns: (xAxis, yAxis, zAxis)))
    }
}
