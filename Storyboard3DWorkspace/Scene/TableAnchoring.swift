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

    private func anchor(to table: SpatialTrackingService.Table) {
        searchTimeout?.cancel()
        workspace.placeBase(atSurface: table.originFromCenter)
        // Remember where the base sits relative to the table's stable anchor, not its
        // surface center, which drifts as more of the table is detected.
        let originFromBase = workspace.baseAnchor.transformMatrix(relativeTo: nil)
        anchoredTable = (table.id, table.originFromAnchor.inverse * originFromBase)
        placement = .onTable
    }
}
