//
//  SurfaceProbeTests.swift
//  Storyboard3DWorkspaceTests
//

import RealityKit
import Testing
import UIKit
@testable import Storyboard3DWorkspace

@MainActor
struct SurfaceProbeTests {
    private func ball(radius: Float, at position: SIMD3<Float>) -> (Entity, Entity) {
        let space = Entity()
        let object = Entity()
        object.addChild(ModelEntity(mesh: .generateSphere(radius: radius), materials: [SimpleMaterial()]))
        object.position = position
        space.addChild(object)
        return (space, object)
    }

    @Test func raysFindTheRealSurfaceNotTheBox() throws {
        let (space, object) = ball(radius: 0.05, at: [0, 0.05, 0])

        // Straight down the middle: the top of the ball.
        let top = try #require(SurfaceProbe.cast(from: [0, 1, 0], direction: [0, -1, 0], at: object, in: space))
        #expect(abs(top.point.y - 0.1) < 0.002)
        #expect(top.normal.y > 0.95)

        // Near the edge the ball is much lower than the top of its box.
        let edge = try #require(SurfaceProbe.cast(from: [0.04, 1, 0], direction: [0, -1, 0], at: object, in: space))
        #expect(edge.point.y < 0.085)
        #expect(edge.normal.x > 0.5)

        // Past it, nothing.
        #expect(SurfaceProbe.cast(from: [0.06, 1, 0], direction: [0, -1, 0], at: object, in: space) == nil)
        // Not beyond the distance asked for.
        #expect(SurfaceProbe.cast(from: [0, 1, 0], direction: [0, -1, 0], at: object, in: space, maxDistance: 0.5) == nil)
    }

    @Test func aSurfaceCastsManyRaysFromOneSetOfTriangles() throws {
        let (space, object) = ball(radius: 0.05, at: [0.2, 0.05, 0])
        let surface = SurfaceProbe.Surface(of: object, in: space)
        let bounds = try #require(surface.bounds)
        #expect(abs(bounds.center.x - 0.2) < 0.001)
        let hit = try #require(surface.cast(from: [0, 0.05, 0], direction: [1, 0, 0]))
        #expect(abs(hit.point.x - 0.15) < 0.002)
        #expect(hit.normal.x < -0.95)                     // faces back toward the ray
        #expect(SurfaceProbe.vertices(of: object, in: space).allSatisfy { abs(simd_length($0 - [0.2, 0.05, 0]) - 0.05) < 0.001 })
    }
}
