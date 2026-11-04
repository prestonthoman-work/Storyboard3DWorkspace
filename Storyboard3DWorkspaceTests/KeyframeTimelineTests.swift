//
//  KeyframeTimelineTests.swift
//  Storyboard3DWorkspaceTests
//

import Foundation
import RealityKit
import Testing
@testable import Storyboard3DWorkspace

@MainActor
struct KeyframeTimelineTests {
    let house = ObjectID()
    let tree = ObjectID()

    private func at(_ x: Float) -> Transform { Transform(translation: [x, 0, 0]) }

    @Test func keyframesAreOneSecondApart() {
        var timeline = KeyframeTimeline()
        timeline.append([:])
        timeline.append([:])
        timeline.append([:])
        #expect(timeline.keyframes.map(\.time) == [0, 1, 2])
        #expect(timeline.duration == 2)
        #expect(timeline.canPlay)
    }

    @Test func deletingRetimesTheRest() {
        var timeline = KeyframeTimeline()
        let first = timeline.append([:])
        timeline.append([:])
        timeline.append([:])
        timeline.remove(first.id)
        #expect(timeline.keyframes.map(\.time) == [0, 1])
    }

    @Test func interpolationEasesBetweenPoses() throws {
        var timeline = KeyframeTimeline()
        timeline.append([house: at(0)])
        timeline.append([house: at(1)])
        let start = try #require(timeline.poses(at: 0)[house])
        let middle = try #require(timeline.poses(at: 0.5)[house])
        let early = try #require(timeline.poses(at: 0.25)[house])
        #expect(start.translation.x == 0)
        #expect(abs(middle.translation.x - 0.5) < 1e-5)
        // Smoothstep eases in: a quarter of the way through time is less than a quarter of the distance.
        #expect(early.translation.x < 0.25)
    }

    @Test func objectsAppearOnlyFromKeyframesThatIncludeThem() {
        var timeline = KeyframeTimeline()
        timeline.append([:])                                  // 1: empty
        timeline.append([house: at(0)])                       // 2: house appears
        timeline.append([house: at(0.1), tree: at(0.2)])      // 3: tree appears
        #expect(timeline.poses(at: 0).isEmpty)
        #expect(Set(timeline.poses(at: 1).keys) == [house])
        #expect(Set(timeline.poses(at: 1.5).keys) == [house])
        #expect(Set(timeline.poses(at: 2).keys) == [house, tree])
        #expect(timeline.keyframedObjectIDs == [house, tree])
    }

    @Test func removingAnObjectReportsTheKeyframesItWasIn() {
        var timeline = KeyframeTimeline()
        timeline.append([:])
        let second = timeline.append([house: at(0)])
        let third = timeline.append([house: at(0), tree: at(0)])
        #expect(Set(timeline.removeObject(house)) == [second.id, third.id])
        #expect(timeline.keyframedObjectIDs == [tree])
    }

    @Test func poseMatchingToleratesTinyDifferencesOnly() {
        #expect(KeyframeTimeline.posesMatch([:], [:]))
        #expect(KeyframeTimeline.posesMatch([house: at(0)], [house: at(0.001)]))
        #expect(!KeyframeTimeline.posesMatch([house: at(0)], [house: at(0.01)]))
        #expect(!KeyframeTimeline.posesMatch([house: at(0)], [house: at(0), tree: at(0)]))
        let turned = Transform(rotation: simd_quatf(angle: 0.1, axis: [0, 1, 0]))
        #expect(!KeyframeTimeline.posesMatch([house: Transform()], [house: turned]))
    }

    @Test func notesAreKeptPerKeyframe() {
        var timeline = KeyframeTimeline()
        let keyframe = timeline.append([:])
        timeline.setNote("Wide shot", for: keyframe.id)
        timeline.update(keyframe.id, with: [house: at(0)])
        #expect(timeline.keyframe(keyframe.id)?.note == "Wide shot")
    }
}
