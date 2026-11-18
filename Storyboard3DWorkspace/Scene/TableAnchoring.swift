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
            placement = .floating(reason: "Table detection isn't available here, so the base floats in front of you.")
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

    /// How far the base's near edge should be from the viewer, horizontally. The main window
    /// opens as a utility panel, low and roughly 0.7–1 m out; a base nearer than this covers it.
    private static let panelClearance: Float = 1.1
    /// Keeps the base's rim this far inside the table's edges.
    private static let edgeMargin: Float = 0.03

    /// Where on the table the base goes: the center, unless that puts it in the main panel's
    /// spot, in which case it slides away from the viewer toward the far side of the table,
    /// as far as needed (or as far as the table allows).
    private func baseSurface(on table: SpatialTrackingService.Table) -> simd_float4x4 {
        let center = table.center
        let viewer = tracking.viewerPosition
        var away = SIMD2(center.x - viewer.x, center.z - viewer.z)
        let distance = simd_length(away)
        if distance > 1e-3 {
            away /= distance
        } else if let head = tracking.viewerTransform {
            // Standing over the middle of the table: push it the way the viewer is facing.
            away = SIMD2(-head.columns.2.x, -head.columns.2.z)
            guard simd_length(away) > 1e-3 else { return table.originFromCenter }
            away = simd_normalize(away)
        } else {
            return table.originFromCenter
        }

        let radius = workspace.baseRadius
        let wanted = Self.panelClearance - (distance - radius)
        guard wanted > 0 else { return table.originFromCenter }

        // The slide direction in the table's own axes (x along its width, z along its depth).
        let tableX = simd_normalize(SIMD2(table.originFromCenter.columns.0.x, table.originFromCenter.columns.0.z))
        let tableZ = simd_normalize(SIMD2(table.originFromCenter.columns.2.x, table.originFromCenter.columns.2.z))
        let alongX = abs(simd_dot(away, tableX))
        let alongZ = abs(simd_dot(away, tableZ))
        let roomX = max(table.width / 2 - radius - Self.edgeMargin, 0)
        let roomZ = max(table.depth / 2 - radius - Self.edgeMargin, 0)
        var allowed = Float.greatestFiniteMagnitude
        if alongX > 1e-4 { allowed = min(allowed, roomX / alongX) }
        if alongZ > 1e-4 { allowed = min(allowed, roomZ / alongZ) }

        let shift = min(wanted, allowed)
        guard shift > 0 else { return table.originFromCenter }
        var surface = table.originFromCenter
        surface.columns.3.x += away.x * shift
        surface.columns.3.z += away.y * shift
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
