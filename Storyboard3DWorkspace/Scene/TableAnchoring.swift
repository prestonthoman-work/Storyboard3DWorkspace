//
//  TableAnchoring.swift
//  Storyboard3DWorkspace
//

import Foundation
import RealityKit

/// Puts the base on a real table in the room and keeps it there as ARKit refines its
/// understanding of the table. Falls back to floating the base in front of the viewer when
/// no table can be found or table detection isn't allowed.
@MainActor
@Observable
final class TableAnchoring {
    enum Placement: Equatable {
        case searching
        case onTable
        case floating(reason: String)
    }

    private(set) var placement: Placement = .searching

    /// The table the base sits on, and where the base is relative to that table's anchor.
    @ObservationIgnored private var anchoredTable: (id: UUID, anchorFromBase: simd_float4x4)?
    @ObservationIgnored private var searchTimeout: Task<Void, Never>?
    @ObservationIgnored private let workspace: WorkspaceScene

    init(workspace: WorkspaceScene) {
        self.workspace = workspace
    }

    private var tracking: SpatialTrackingService { .shared }

    /// Starts table detection and places the base on the nearest table once one is found.
    func start() async {
        placement = .searching
        await tracking.start()
        tracking.onTablesChanged = { [weak self] in self?.tablesChanged() }

        switch tracking.tableDetection {
        case .running:
            tablesChanged()
            searchTimeout = Task { [weak self] in
                try? await Task.sleep(for: .seconds(8))
                guard let self, !Task.isCancelled, self.placement == .searching else { return }
                self.placement = .floating(reason: "No table found yet. Look at a table, then choose Find Table.")
            }
        case .notAuthorized:
            workspace.placeBaseFloating()
            placement = .floating(reason: "Allow access to your surroundings in Settings to place the base on a table.")
        case .unavailable:
            workspace.placeBaseFloating()
            placement = .floating(reason: "Table detection isn't available here, so the base floats beside the panel.")
        }
    }

    func stop() {
        searchTimeout?.cancel()
        searchTimeout = nil
        anchoredTable = nil
        tracking.onTablesChanged = nil
        tracking.stop()
    }

    var canFindTable: Bool {
        tracking.tableDetection == .running
    }

    /// Moves the base onto the detected table closest to where the viewer is standing.
    func findTable() {
        guard tracking.tableDetection == .running else { return }
        if let table = tracking.nearestTable(to: tracking.viewerPosition) {
            anchor(to: table)
        } else {
            placement = .floating(reason: "No table found. Look around at a table and try again.")
        }
    }

    /// The size of the table the base sits on, in meters, or nil when it isn't on one.
    var anchoredTableSize: (width: Float, depth: Float)? {
        guard let anchored = anchoredTable, let table = tracking.tables[anchored.id] else { return nil }
        return (table.width, table.depth)
    }

    private func tablesChanged() {
        if let anchored = anchoredTable {
            // Follow the table's anchor as ARKit refines it, keeping the base where it was placed on the surface.
            if let table = tracking.tables[anchored.id] {
                workspace.placeBase(atSurface: table.originFromAnchor * anchored.anchorFromBase)
            }
            return
        }
        if placement == .searching, let table = tracking.nearestTable(to: tracking.viewerPosition) {
            anchor(to: table)
        }
    }

    /// Puts the base back on the table it's on, recomputing where it sits (for example after
    /// the base is resized, so a bigger base isn't left hanging off the far edge).
    func reseat() {
        guard let anchored = anchoredTable, let table = tracking.tables[anchored.id] else { return }
        anchor(to: table)
    }

    /// Keeps the base's rim this far inside the table's edges.
    private static let edgeMargin: Float = 0.03

    /// Where on the table the base goes: the spot nearest the table's center that's beside
    /// the main panel rather than behind or in front of it, preferring the left (the
    /// Timeline window opens to the panel's right). If the table has no such spot, the one
    /// that leaves the most of the panel clear.
    private func baseSurface(on table: SpatialTrackingService.Table) -> simd_float4x4 {
        let radius = workspace.baseRadius
        let tableX = SIMD3(table.originFromCenter.columns.0.x, table.originFromCenter.columns.0.y, table.originFromCenter.columns.0.z)
        let tableZ = SIMD3(table.originFromCenter.columns.2.x, table.originFromCenter.columns.2.y, table.originFromCenter.columns.2.z)
        let roomX = max(table.width / 2 - radius - Self.edgeMargin, 0)
        let roomZ = max(table.depth / 2 - radius - Self.edgeMargin, 0)

        struct Candidate { var offset: SIMD2<Float>; var gap: Float; var isLeft: Bool }
        var candidates: [Candidate] = []
        let steps = 12
        for i in -steps...steps {
            for j in -steps...steps {
                let offset = SIMD2(roomX * Float(i) / Float(steps), roomZ * Float(j) / Float(steps))
                let point = table.center + simd_normalize(tableX) * offset.x + simd_normalize(tableZ) * offset.y
                candidates.append(Candidate(offset: offset,
                                            gap: PanelClearance.gap(baseCenter: point, radius: radius),
                                            isLeft: point.x < 0))
            }
        }
        let clear = candidates.filter { $0.gap >= 0 }
        let nearest = { (a: Candidate, b: Candidate) in simd_length(a.offset) < simd_length(b.offset) }
        let best = clear.filter(\.isLeft).min(by: nearest)
            ?? clear.min(by: nearest)
            ?? candidates.max { $0.gap < $1.gap }
        guard let best, simd_length(best.offset) > 1e-4 else { return table.originFromCenter }

        var surface = table.originFromCenter
        let shift = simd_normalize(tableX) * best.offset.x + simd_normalize(tableZ) * best.offset.y
        surface.columns.3.x += shift.x
        surface.columns.3.z += shift.z
        return surface
    }

    private func anchor(to table: SpatialTrackingService.Table) {
        searchTimeout?.cancel()
        workspace.placeBase(atSurface: baseSurface(on: table))
        // Remember where the base sits relative to the table's stable anchor, not its
        // surface center, which drifts as more of the table is detected.
        let originFromBase = workspace.baseAnchor.transformMatrix(relativeTo: nil)
        anchoredTable = (table.id, table.originFromAnchor.inverse * originFromBase)
        placement = .onTable
    }
}

/// Where the main window is, roughly, so the base can be kept beside it. The window opens
/// as a utility panel, low and close, straight ahead of where the person stood; the
/// immersive space's origin is that same spot, looking down -Z.
enum PanelClearance {
    /// Half the panel's width as an angle from the viewer (560 pt wide at about 0.8 m),
    /// plus a little room.
    static let panelHalfAngle: Float = 24 * .pi / 180

    /// How far (in radians) the base's edge is from the panel's edge, as seen from where
    /// the person stood: negative when the base is behind or in front of the panel.
    static func gap(baseCenter: SIMD3<Float>, radius: Float) -> Float {
        let flat = SIMD2(baseCenter.x, -baseCenter.z)
        let distance = simd_length(flat)
        guard distance > radius else { return -.pi }
        let bearing = abs(atan2(flat.x, flat.y))
        return bearing - asin(radius / distance) - panelHalfAngle
    }

    /// Where the base floats without a table: at a comfortable reach and table height, just
    /// far enough left of straight ahead to clear the panel.
    static func floatingPosition(radius: Float) -> SIMD3<Float> {
        let distance: Float = 1.1
        let bearing = panelHalfAngle + asin(min(radius / distance, 0.95)) + 4 * .pi / 180
        return [-distance * sin(bearing), 0.85, -distance * cos(bearing)]
    }
}
