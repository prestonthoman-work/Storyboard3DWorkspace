//
//  SpatialTrackingService.swift
//  Storyboard3DWorkspace
//

import ARKit
import QuartzCore

/// Runs ARKit while the immersive space is open: head tracking for the viewer-facing
/// backdrop and capture viewpoint, and horizontal plane detection to find tables.
///
/// ARKit only delivers data inside an open immersive space, and plane detection needs
/// the person's permission to sense their surroundings. When either is unavailable
/// (including in Simulator), the app falls back to fixed positions.
final class SpatialTrackingService {
    static let shared = SpatialTrackingService()

    static let fallbackViewerPosition = SIMD3<Float>(0, 1.4, 0)

    enum TableDetection {
        case unavailable
        case notAuthorized
        case running
    }

    struct Table {
        let id: UUID
        /// The plane anchor's own pose. Stable over time, so content locked to it doesn't slide.
        let originFromAnchor: simd_float4x4
        /// Center of the detected surface. Shifts as more of the table is seen.
        let originFromCenter: simd_float4x4
        let width: Float
        let depth: Float

        var center: SIMD3<Float> {
            SIMD3(originFromCenter.columns.3.x, originFromCenter.columns.3.y, originFromCenter.columns.3.z)
        }
    }

    private(set) var tableDetection: TableDetection = .unavailable
    private(set) var tables: [UUID: Table] = [:]

    /// Called whenever a table is added, refined, or removed.
    var onTablesChanged: (() -> Void)?

    private var session: ARKitSession?
    private var worldTracking: WorldTrackingProvider?
    private var planeDetection: PlaneDetectionProvider?
    private var planeUpdatesTask: Task<Void, Never>?

    func start() async {
        guard session == nil else { return }

        // ARKit data providers can't be rerun after stopping, so build fresh ones each time.
        let session = ARKitSession()
        self.session = session
        var providers: [any DataProvider] = []

        if WorldTrackingProvider.isSupported {
            let worldTracking = WorldTrackingProvider()
            self.worldTracking = worldTracking
            providers.append(worldTracking)
        }

        if PlaneDetectionProvider.isSupported {
            let authorization = await session.requestAuthorization(for: [.worldSensing])
            if authorization[.worldSensing] == .allowed {
                let planeDetection = PlaneDetectionProvider(alignments: [.horizontal])
                self.planeDetection = planeDetection
                providers.append(planeDetection)
                tableDetection = .running
            } else {
                tableDetection = .notAuthorized
            }
        } else {
            tableDetection = .unavailable
        }

        guard !providers.isEmpty else { return }
        do {
            try await session.run(providers)
        } catch {
            stop()
            return
        }

        if let planeDetection {
            planeUpdatesTask = Task { [weak self] in
                for await update in planeDetection.anchorUpdates {
                    self?.handle(update)
                }
            }
        }
    }

    func stop() {
        planeUpdatesTask?.cancel()
        planeUpdatesTask = nil
        session?.stop()
        session = nil
        worldTracking = nil
        planeDetection = nil
        tables.removeAll()
        tableDetection = .unavailable
    }

    var viewerPosition: SIMD3<Float> {
        guard let worldTracking, worldTracking.state == .running,
              let anchor = worldTracking.queryDeviceAnchor(atTimestamp: CACurrentMediaTime()),
              anchor.isTracked
        else { return Self.fallbackViewerPosition }

        let translation = anchor.originFromAnchorTransform.columns.3
        return SIMD3(translation.x, translation.y, translation.z)
    }

    /// The detected table whose center is closest to `point` horizontally.
    func nearestTable(to point: SIMD3<Float>) -> Table? {
        tables.values.min { a, b in
            horizontalDistance(a.center, point) < horizontalDistance(b.center, point)
        }
    }

    private func handle(_ update: AnchorUpdate<PlaneAnchor>) {
        let anchor = update.anchor
        switch update.event {
        case .added, .updated:
            if anchor.surfaceClassification == .table {
                let extent = anchor.geometry.extent
                tables[anchor.id] = Table(
                    id: anchor.id,
                    originFromAnchor: anchor.originFromAnchorTransform,
                    originFromCenter: anchor.originFromAnchorTransform * extent.anchorFromExtentTransform,
                    width: extent.width,
                    depth: extent.height
                )
            } else {
                tables[anchor.id] = nil
            }
        case .removed:
            tables[anchor.id] = nil
        @unknown default:
            return
        }
        onTablesChanged?()
    }

    private func horizontalDistance(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> Float {
        simd_length(SIMD2(a.x - b.x, a.z - b.z))
    }
}
