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

    // MARK: Timing

    @Test func insertingAfterAKeyframeKeepsLaterTiming() throws {
        var timeline = KeyframeTimeline()
        let first = timeline.append([:])
        timeline.append([:])
        timeline.retime(timeline.keyframes[1].id, to: 2.5)
        let maybeInserted = timeline.insert([house: at(0)], after: first.id)
        let inserted = try #require(maybeInserted)
        #expect(timeline.keyframes.map(\.time) == [0, 1, 3.5])
        #expect(timeline.keyframes[1].id == inserted.id)
    }

    @Test func insertingAtAMomentLeavesOthersInPlace() throws {
        var timeline = KeyframeTimeline()
        timeline.append([:])
        timeline.append([:])
        let maybeInserted = timeline.insert([:], at: 0.4)
        let inserted = try #require(maybeInserted)
        #expect(timeline.keyframes.map(\.time) == [0, 0.4, 1])
        #expect(timeline.keyframes[1].id == inserted.id)
        let tooClose = timeline.insert([:], at: 0.42)
        let pastEnd = timeline.insert([:], at: 5)
        #expect(tooClose == nil)
        #expect(pastEnd == nil)
    }

    @Test func retimingSnapsAndStaysBetweenNeighbors() {
        var timeline = KeyframeTimeline()
        let first = timeline.append([:])
        let second = timeline.append([:])
        let third = timeline.append([:])
        let movedFirst = timeline.retime(first.id, to: 0.5)
        #expect(!movedFirst)                                          // the first stays at 0
        timeline.retime(second.id, to: 1.33)
        #expect(abs(timeline.keyframe(second.id)!.time - 1.3) < 1e-9)  // snapped to 0.1 s
        timeline.retime(second.id, to: 9)
        #expect(abs(timeline.keyframe(second.id)!.time - (2 - KeyframeTimeline.minimumGap)) < 1e-9)
        timeline.retime(third.id, to: 4)
        #expect(timeline.duration == 4)
    }

    @Test func deletingClosesOnlyTheRemovedGap() {
        var timeline = KeyframeTimeline()
        timeline.append([:])
        let second = timeline.append([:])
        let third = timeline.append([:])
        timeline.append([:])
        timeline.retime(third.id, to: 2.5)            // times: 0, 1, 2.5, 3
        timeline.remove(second.id)                    // its 1.5 s gap closes
        #expect(timeline.keyframes.map(\.time) == [0, 1, 1.5])
    }

    @Test func reorderingKeepsTheMoments() {
        var timeline = KeyframeTimeline()
        let a = timeline.append([:])
        let b = timeline.append([:])
        timeline.retime(b.id, to: 3)
        timeline.move(b.id, to: 0)
        #expect(timeline.keyframes.map(\.id) == [b.id, a.id])
        #expect(timeline.keyframes.map(\.time) == [0, 3])
    }

    @Test func duplicateCopiesPosesAndNotes() throws {
        var timeline = KeyframeTimeline()
        let original = timeline.append([house: at(0.3)])
        timeline.setNote("Close-up", for: original.id)
        let maybeCopy = timeline.duplicate(original.id)
        let copy = try #require(maybeCopy)
        #expect(copy.id != original.id)
        #expect(copy.note == "Close-up")
        #expect(copy.poses[house]?.translation.x == 0.3)
        #expect(timeline.keyframes.map(\.time) == [0, 1])
    }

    @Test func steppingFindsNeighbors() {
        var timeline = KeyframeTimeline()
        let a = timeline.append([:])
        let b = timeline.append([:])
        #expect(timeline.keyframe(after: 0)?.id == b.id)
        #expect(timeline.keyframe(before: 0.5)?.id == a.id)
        #expect(timeline.keyframe(before: 0) == nil)
        #expect(timeline.keyframe(after: 1) == nil)
    }
}
