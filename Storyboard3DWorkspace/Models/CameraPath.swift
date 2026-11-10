//
//  CameraPath.swift
//  Storyboard3DWorkspace
//

import Foundation
import simd

/// A camera move through the keyframes: each keyframe's photo angle is a stop, and the
/// camera glides between them with the same easing the objects use. Keyframes without a
/// photo hold the camera where it was.
struct CameraPath {
    struct Stop {
        let time: TimeInterval
        let camera: CaptureCamera
    }

    /// One frame's camera. `verticalFOV` changes smoothly between lenses; `camera.lens` is the
    /// wider of the two neighboring lenses, so anything sized for it still covers the frame.
    struct Frame {
        let camera: CaptureCamera
        let verticalFOV: Float
    }

    let stops: [Stop]

    init(stops: [Stop]) {
        self.stops = stops.sorted { $0.time < $1.time }
    }

    var isEmpty: Bool { stops.isEmpty }

    func frame(at time: TimeInterval) -> Frame? {
        guard let first = stops.first, let last = stops.last else { return nil }
        if time <= first.time { return Frame(camera: first.camera, verticalFOV: first.camera.lens.verticalFOV) }
        if time >= last.time { return Frame(camera: last.camera, verticalFOV: last.camera.lens.verticalFOV) }
        guard let nextIndex = stops.firstIndex(where: { $0.time > time }), nextIndex > 0 else { return nil }

        let from = stops[nextIndex - 1]
        let to = stops[nextIndex]
        let linear = Float((time - from.time) / (to.time - from.time))
        let eased = linear * linear * (3 - 2 * linear)

        let wider = from.camera.lens.rawValue <= to.camera.lens.rawValue ? from.camera.lens : to.camera.lens
        let camera = CaptureCamera(
            position: mix(from.camera.position, to.camera.position, t: eased),
            orientation: simd_slerp(from.camera.orientation, to.camera.orientation, eased),
            lens: wider
        )
        let fov = from.camera.lens.verticalFOV + (to.camera.lens.verticalFOV - from.camera.lens.verticalFOV) * eased
        return Frame(camera: camera, verticalFOV: fov)
    }
}
