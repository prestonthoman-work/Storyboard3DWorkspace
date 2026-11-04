//
//  ViewerPoseProvider.swift
//  Storyboard3DWorkspace
//

import ARKit
import QuartzCore

/// Supplies the viewer's head position in immersive-space coordinates.
///
/// ARKit world tracking only delivers poses while an immersive space is open. When
/// tracking isn't available, a fixed standing eye position at the space's origin is
/// used instead, so the backdrop still sits behind the model, just without
/// following the viewer.
final class ViewerPoseProvider {
    static let shared = ViewerPoseProvider()

    static let fallbackPosition = SIMD3<Float>(0, 1.4, 0)

    private var session: ARKitSession?
    private var worldTracking: WorldTrackingProvider?

    func start() async {
        guard session == nil, WorldTrackingProvider.isSupported else { return }

        // ARKit data providers can't be rerun after stopping, so build fresh ones each time.
        let session = ARKitSession()
        let worldTracking = WorldTrackingProvider()
        self.session = session
        self.worldTracking = worldTracking

        do {
            try await session.run([worldTracking])
        } catch {
            stop()
        }
    }

    func stop() {
        session?.stop()
        session = nil
        worldTracking = nil
    }

    var viewerPosition: SIMD3<Float> {
        guard let worldTracking, worldTracking.state == .running,
              let anchor = worldTracking.queryDeviceAnchor(atTimestamp: CACurrentMediaTime()),
              anchor.isTracked
        else { return Self.fallbackPosition }

        let translation = anchor.originFromAnchorTransform.columns.3
        return SIMD3(translation.x, translation.y, translation.z)
    }
}
