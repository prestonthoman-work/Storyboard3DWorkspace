//
//  CharacterTests.swift
//  Storyboard3DWorkspaceTests
//

import CoreGraphics
import Foundation
import RealityKit
import Testing
@testable import Storyboard3DWorkspace

/// The mannequin's rig math: joint angles, inverse kinematics, and presets.
struct CharacterRigTests {
    let layout = RigLayout(proportions: CharacterProportions())

    private func frames(_ pose: CharacterPose) -> [Joint: CharacterKinematics.JointFrame] {
        CharacterKinematics.frames(for: pose, layout: layout)
    }

    @Test func anglesSurviveARoundTripThroughRotations() {
        for joint in Joint.allCases {
            let limits = joint.limits
            // A spread of in-range angles, kept away from the ±90° bend where angles become ambiguous.
            for fraction: Float in [0.15, 0.5, 0.85] {
                func pick(_ range: ClosedRange<Float>) -> Float {
                    min(max(range.lowerBound + (range.upperBound - range.lowerBound) * fraction, -80), 80)
                }
                let angles = limits.clamp(JointRotation(bend: pick(limits.bend), twist: pick(limits.twist), side: pick(limits.side)))
                let back = CharacterKinematics.angles(from: CharacterKinematics.rotation(angles, for: joint), for: joint)
                #expect(abs(back.bend - angles.bend) < 0.05 && abs(back.twist - angles.twist) < 0.05
                        && abs(back.side - angles.side) < 0.05, "\(joint) \(angles) → \(back)")
            }
        }
    }

    @Test func posesStayWithinJointLimits() {
        var pose = CharacterPose()
        pose[.leftKnee] = JointRotation(bend: -40, twist: 30)
        pose[.neck] = JointRotation(twist: 500)
        #expect(pose[.leftKnee] == JointRotation(bend: 0, twist: 0))
        #expect(pose[.neck].twist == Joint.neck.limits.twist.upperBound)
        #expect(pose.rotations[.leftKnee] == nil) // straight joints aren't stored
    }

    @Test func turningAShoulderCarriesTheWholeArm() {
        var pose = CharacterPose()
        pose[.rightShoulder] = JointRotation(bend: 90)
        let raised = frames(pose), resting = frames(.neutral)
        #expect(raised[.rightWrist]!.position.z > 0.45)                      // the hand swings forward
        #expect(simd_distance(raised[.leftWrist]!.position, resting[.leftWrist]!.position) < 1e-5)
    }

    @Test(arguments: Limb.allCases)
    func reachingPlacesTheHandOrFootOnTheTarget(limb: Limb) {
        let targets: [SIMD3<Float>] = limb.isArm
            ? [[0.1, -0.35, 0.3], [0.2, 0.1, 0.35], [0, -0.2, 0.15]]
            : [[0, -0.6, 0.35], [0.1, -0.7, 0.2], [0, -0.45, 0.45]]
        for target in targets {
            var aimed = target
            aimed.x *= limb.outward
            let pose = LimbIK.solve(limb, reaching: aimed, bendDirection: 0, pose: .neutral, layout: layout)
            let reached = LimbIK.effector(of: limb, in: pose, layout: layout)
            #expect(simd_distance(reached, aimed) < 0.01, "\(limb) aimed \(aimed), reached \(reached)")
        }
    }

    @Test func outOfReachTargetsStretchTowardThem() {
        let pose = LimbIK.solve(.leftArm, reaching: [0, 0, 2], bendDirection: 0, pose: .neutral, layout: layout)
        let reached = LimbIK.effector(of: .leftArm, in: pose, layout: layout)
        #expect(reached.z > 0.5)
        #expect(pose[.leftElbow].bend < 6)
    }

    @Test(arguments: Limb.allCases)
    func theBendDirectionTurnsTheElbowOrKneeOutward(limb: Limb) {
        let target: SIMD3<Float> = limb.isArm ? [0.05 * limb.outward, -0.3, 0.3] : [0.05 * limb.outward, -0.65, 0.3]
        let natural = LimbIK.solve(limb, reaching: target, bendDirection: 0, pose: .neutral, layout: layout)
        let turned = LimbIK.solve(limb, reaching: target, bendDirection: 40, pose: .neutral, layout: layout)
        let middle = { (pose: CharacterPose) in CharacterKinematics.frames(for: pose, layout: layout)[limb.middle]!.position }
        // Outward means away from the body's center line.
        #expect((middle(turned).x - middle(natural).x) * limb.outward > 0.02)
        #expect(abs(LimbIK.bendDirection(of: limb, in: turned, layout: layout) - 40) < 3,
                "\(limb) \(turned[limb.root]) \(LimbIK.bendDirection(of: limb, in: turned, layout: layout))")
        // The hand or foot stays on target either way.
        #expect(simd_distance(LimbIK.effector(of: limb, in: turned, layout: layout), target) < 0.01)
    }

    @Test func blendingPosesNeverTakesTheLongWayAround() {
        var a = CharacterPose(), b = CharacterPose()
        a[.rightShoulder] = JointRotation(bend: 170)
        b[.rightShoulder] = JointRotation(bend: -50)
        var previous = a[.rightShoulder].bend
        for step in 1...10 {
            let bend = a.interpolated(to: b, Float(step) / 10)[.rightShoulder].bend
            #expect(bend < previous)                      // steadily lowers the arm, no jumps
            previous = bend
        }
        #expect(abs(a.interpolated(to: b, 0.5)[.rightShoulder].bend - 60) < 0.01)
    }

    @Test func posesSaveAsReadableJSON() throws {
        let pose = PosePreset.running.pose
        let data = try JSONEncoder().encode(pose)
        #expect(String(decoding: data, as: UTF8.self).contains("leftKnee"))
        #expect(try JSONDecoder().decode(CharacterPose.self, from: data) == pose)
    }

    // MARK: Presets look like what they're called

    @Test func presetsReadAsTheirNames() {
        let up: SIMD3<Float> = [0, 1, 0], forward: SIMD3<Float> = [0, 0, 1]

        let pointing = frames(PosePreset.pointing.pose)
        #expect(pointing[.rightWrist]!.position.z - pointing[.rightShoulder]!.position.z > 0.45)

        let waving = frames(PosePreset.waving.pose)
        #expect(waving[.rightWrist]!.position.y > waving[.rightShoulder]!.position.y + 0.1)
        #expect(waving[.rightElbow]!.position.x < waving[.rightShoulder]!.position.x - 0.15) // arm out to the side

        let sitting = frames(PosePreset.sitting.pose)
        #expect(sitting[.leftKnee]!.position.z > 0.35)                                        // thighs forward
        #expect(abs(sitting[.leftKnee]!.position.y - sitting[.leftHip]!.position.y) < 0.08)    // and level
        #expect(simd_dot(sitting[.leftAnkle]!.orientation.act(forward), up) < 0.15)          // feet flat

        let crossed = frames(PosePreset.armsCrossed.pose)
        #expect(crossed[.leftWrist]!.position.x < 0.06 && crossed[.rightWrist]!.position.x > -0.06)
        #expect(crossed[.leftWrist]!.position.z > 0.12)

        let crouching = frames(PosePreset.crouching.pose)
        #expect(crouching[.pelvis]!.position.y - crouching[.leftAnkle]!.position.y < 0.6)
        #expect(abs(simd_dot(crouching[.leftAnkle]!.orientation.act(forward), up)) < 0.2)

        let looking = frames(PosePreset.lookingBack.pose)
        #expect(looking[.head]!.orientation.act(forward).x > 0.75)                           // facing well to the left

        for stride in [PosePreset.walking, .running] {
            let legs = frames(stride.pose)
            #expect(legs[.leftAnkle]!.position.z > legs[.rightAnkle]!.position.z + 0.2, "\(stride)")
        }

        let reaching = frames(PosePreset.reaching.pose)
        #expect(reaching[.leftWrist]!.position.y > reaching[.leftShoulder]!.position.y)
        #expect(reaching[.leftWrist]!.position.z > 0.2)

        #expect(PosePreset.sitting.requirement != nil)
        #expect(PosePreset.allCases.filter { $0.requirement != nil } == [.sitting])
    }

    // MARK: Timeline

    @Test func keyframesBlendOrHoldCharacterPoses() {
        let id = ObjectID()
        var timeline = KeyframeTimeline()
        var raised = CharacterPose()
        raised[.rightShoulder] = JointRotation(bend: 90)
        let first = timeline.append([id: Transform()], characters: [id: .neutral])
        timeline.append([id: Transform(translation: [0.1, 0, 0])], characters: [id: raised])

        #expect(abs((timeline.characterPoses(at: 0.5)[id]?[.rightShoulder].bend ?? 0) - 45) < 0.01)
        #expect(abs(timeline.poses(at: 0.5)[id]!.translation.x - 0.05) < 1e-5)

        timeline.setHolds(true, for: first.id)
        #expect(timeline.characterPoses(at: 0.9)[id]?[.rightShoulder].bend == 0)
        #expect(timeline.poses(at: 0.9)[id]!.translation.x == 0)
        #expect(timeline.characterPoses(at: 1)[id]?[.rightShoulder].bend == 90)

        let copy = timeline.duplicate(first.id)
        #expect(copy?.characterPoses[id] == .neutral && copy?.holds == true)
    }
}

/// Characters in the live app: placing, posing, keyframes, saving, and captures.
@MainActor
@Suite(.serialized)
struct CharacterAppTests {
    let storage: URL

    init() throws {
        storage = FileManager.default.temporaryDirectory.appending(path: "CharacterAppTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: storage, withIntermediateDirectories: true)
        ProjectStore.storageOverride = storage
    }

    private func makeApp() async throws -> AppModel {
        let app = AppModel()
        await app.createProject()
        _ = try #require(app.currentProject)
        return app
    }

    private func addCharacter(_ kind: CharacterKind, to app: AppModel) throws -> (ObjectID, Entity) {
        app.placeCharacter(kind)
        let id = try #require(app.selectedObjectID)
        return (id, try #require(app.workspace.object(withID: id)))
    }

    private func joint(_ joint: Joint, of object: Entity, in app: AppModel) -> Entity? {
        app.workspace.jointEntity(joint, of: object)
    }

    /// The body's bounds in the placed object's space (editing aids excluded).
    private func bodyBounds(of object: Entity) -> BoundingBox {
        var bounds: BoundingBox?
        func visit(_ entity: Entity) {
            if entity.components.has(BodyPartComponent.self) {
                let part = entity.visualBounds(relativeTo: object)
                bounds = bounds.map { $0.union(part) } ?? part
            }
            entity.children.forEach(visit)
        }
        visit(object)
        return bounds ?? BoundingBox()
    }

    /// Counts entities in a tree that match a condition.
    private func count(in entity: Entity, where matches: (Entity) -> Bool) -> Int {
        (matches(entity) ? 1 : 0) + entity.children.reduce(0) { $0 + count(in: $1, where: matches) }
    }

    @Test func charactersArePlacedWithAFullRigAndStandOnTheBase() async throws {
        let app = try await makeApp()
        let (_, object) = try addCharacter(.mannequin, to: app)
        let rig = try #require(CharacterBuilder.rig(in: object))
        #expect(Set(CharacterBuilder.joints(in: rig).keys) == Set(Joint.allCases))
        #expect(app.isSelectedObjectCharacter)
        #expect(app.objects.map(\.name) == ["Mannequin"])

        // About 5 cm tall, with its feet at the object's origin.
        let bounds = bodyBounds(of: object)
        #expect(abs(bounds.min.y) < 0.001)
        #expect(bounds.extents.y > 0.045 && bounds.extents.y < 0.055)
    }

    @Test func twoCharactersPoseIndependently() async throws {
        let app = try await makeApp()
        let (first, firstEntity) = try addCharacter(.mannequin, to: app)
        let (second, secondEntity) = try addCharacter(.child, to: app)
        #expect(first != second)

        app.selectObject(first)
        app.applyPreset(.waving)
        app.selectObject(second)
        app.applyPreset(.sitting)

        #expect(app.workspace.characterPose(of: firstEntity) == PosePreset.waving.pose)
        #expect(app.workspace.characterPose(of: secondEntity) == PosePreset.sitting.pose)
        #expect(app.objectNote == PosePreset.sitting.requirement)
        #expect(app.objects.count == 2)
    }

    @Test func presetsKeepWhereTheCharacterStandsAndItsSize() async throws {
        let app = try await makeApp()
        let (_, object) = try addCharacter(.mannequin, to: app)
        object.position = [0.05, 0, -0.03]
        object.scale = [1.6, 1.6, 1.6]
        object.orientation = simd_quatf(angle: 0.7, axis: [0, 1, 0])
        let before = object.transform
        app.applyPreset(.crouching)
        #expect(object.transform == before)
        // Crouching is shorter, but the feet stay on the ground.
        let bounds = bodyBounds(of: object)
        #expect(abs(bounds.min.y) < 0.001 && bounds.extents.y < 0.04)
    }

    @Test func jointEditsUndoAndRedo() async throws {
        let app = try await makeApp()
        let (_, object) = try addCharacter(.mannequin, to: app)
        app.setCharacterEditMode(.pose)
        app.selectJoint(.leftElbow)

        app.beginPoseChange()
        app.setJointAngle(40, axis: .bend, of: .leftElbow)
        app.setJointAngle(80, axis: .bend, of: .leftElbow)
        app.endPoseChange()
        app.nudgeJoint(.head, axis: .twist, by: 15)
        #expect(app.workspace.characterPose(of: object)?[.leftElbow].bend == 80)
        #expect(app.workspace.characterPose(of: object)?[.head].twist == 15)

        app.undo()
        #expect(app.workspace.characterPose(of: object)?[.head].twist == 0)
        #expect(app.workspace.characterPose(of: object)?[.leftElbow].bend == 80)
        app.undo()
        #expect(app.workspace.characterPose(of: object)?.isNeutral == true)
        app.redo()
        #expect(app.workspace.characterPose(of: object)?[.leftElbow].bend == 80)

        app.resetJoint(.leftElbow)
        #expect(app.workspace.characterPose(of: object)?.isNeutral == true)
    }

    @Test func posingModeSwapsMovingForPickingBodyParts() async throws {
        let app = try await makeApp()
        let (_, object) = try addCharacter(.mannequin, to: app)
        #expect(object.components.has(ManipulationComponent.self))

        app.setCharacterEditMode(.pose)
        #expect(!object.components.has(ManipulationComponent.self))
        let rightHand = try #require(joint(.rightWrist, of: object, in: app))
        let handPart = try #require(rightHand.children.first { $0.components.has(BodyPartComponent.self) })
        #expect(handPart.components.has(CollisionComponent.self))

        // Tapping a body part selects its joint instead of another object.
        app.handleTap(on: handPart)
        #expect(app.selectedJoint == .rightWrist)

        app.selectObject(nil)
        #expect(app.characterEditMode == .move)
        #expect(object.components.has(ManipulationComponent.self))
        #expect(!handPart.components.has(CollisionComponent.self))
    }

    @Test func reachingWithAHandBendsTheArm() async throws {
        let app = try await makeApp()
        let (_, object) = try addCharacter(.mannequin, to: app)
        app.setCharacterEditMode(.pose)
        app.selectJoint(.rightWrist)
        app.poseTool = .reach

        app.beginPoseChange()
        app.setReach([0.15, -0.1, 0.35], of: .rightArm)
        app.endPoseChange()
        let reach = try #require(app.reach(of: .rightArm))
        #expect(simd_distance(reach, [0.15, -0.1, 0.35]) < 0.01)
        let pose = try #require(app.workspace.characterPose(of: object))
        #expect(pose[.rightElbow].bend > 30)

        app.beginPoseChange()
        app.setBendDirection(35, of: .rightArm)
        app.endPoseChange()
        #expect(abs((app.bendDirection(of: .rightArm) ?? 0) - 35) < 3)
        #expect(simd_distance(try #require(app.reach(of: .rightArm)), reach) < 0.01)
    }

    @Test func keyframesAnimateCharactersInTheBasesOwnSpace() async throws {
        let app = try await makeApp()
        let (first, firstEntity) = try addCharacter(.mannequin, to: app)
        let (second, secondEntity) = try addCharacter(.stocky, to: app)

        app.addKeyframe()
        // Second keyframe: both move and change pose.
        app.addKeyframe()
        app.selectObject(first)
        app.applyPreset(.pointing)
        firstEntity.position.x += 0.04
        app.selectObject(second)
        app.applyPreset(.crouching)
        app.sceneEdited()
        try await Task.sleep(for: .milliseconds(600))

        let keyframes = app.animator.timeline.keyframes
        #expect(keyframes.count == 2)
        #expect(keyframes[1].characterPoses[first] == PosePreset.pointing.pose)
        #expect(keyframes[1].characterPoses[second] == PosePreset.crouching.pose)
        #expect(keyframes[0].characterPoses[first]?.isNeutral == true)

        // Spinning the base doesn't change anything relative to it.
        app.workspace.setBaseSpin(1.2)
        app.scrubTimeline(to: 0.5, snapTolerance: 0)
        let halfway = try #require(app.workspace.characterPose(of: firstEntity))
        #expect(abs(halfway[.rightShoulder].bend - PosePreset.pointing.pose[.rightShoulder].bend / 2) < 0.5)
        app.selectKeyframe(keyframes[1])
        #expect(app.workspace.characterPose(of: secondEntity) == PosePreset.crouching.pose)
        app.selectKeyframe(keyframes[0])
        #expect(app.workspace.characterPose(of: secondEntity)?.isNeutral == true)
    }

    @Test func charactersSaveAndReopenWithTheirPosesAndKeyframes() async throws {
        let app = try await makeApp()
        let (id, _) = try addCharacter(.child, to: app)
        app.recolorSelectedObject("red")
        app.beginProportionsChange()
        app.setSelectedCharacterProportions(CharacterProportions(height: 0.7, build: 1.2, head: 1.3, legs: 0.9))
        app.endProportionsChange()
        app.addKeyframe()
        app.applyPreset(.lookingBack)
        app.sceneEdited()
        try await Task.sleep(for: .milliseconds(600))
        let keyframe = try #require(app.animator.selectedKeyframeID)
        app.setHolds(true, forKeyframe: keyframe)
        app.saveNow()
        let project = try #require(app.currentProject)

        let reopened = AppModel()
        #expect(await reopened.openProject(try #require(reopened.projects.first { $0.id == project.id })))
        let entity = try #require(reopened.workspace.object(withID: id))
        #expect(reopened.workspace.characterPose(of: entity) == PosePreset.lookingBack.pose)
        let summary = try #require(reopened.objects.first)
        #expect(summary.recipe.colorName == "red")
        #expect(summary.recipe.characterProportions?.head == 1.3)
        let saved = try #require(reopened.animator.timeline.keyframes.first)
        #expect(saved.characterPoses[id] == PosePreset.lookingBack.pose && saved.holds)

        // A duplicated project keeps them too.
        reopened.duplicateProject(project.id)
        let copy = try #require(reopened.projects.first { $0.name.hasSuffix("Copy") })
        #expect(await reopened.openProject(copy))
        #expect(reopened.workspace.object(withID: id).flatMap { reopened.workspace.characterPose(of: $0) } == PosePreset.lookingBack.pose)
    }

    @Test func duplicatingACharacterCopiesItsPose() async throws {
        let app = try await makeApp()
        _ = try addCharacter(.mannequin, to: app)
        app.applyPreset(.armsCrossed)
        app.duplicateSelectedObject()
        let copy = try #require(app.selectedObjectID.flatMap { app.workspace.object(withID: $0) })
        #expect(app.workspace.characterPose(of: copy) == PosePreset.armsCrossed.pose)
        #expect(app.objects.map(\.name) == ["Mannequin", "Mannequin 2"])
        // Each has its own pose from here on.
        app.applyPreset(.standing)
        #expect(app.workspace.characterPose(of: try #require(app.workspace.object(withID: app.objects[0].id))) == PosePreset.armsCrossed.pose)
    }

    @Test func capturesShowTheKeyframePoseAndNoEditingAids() async throws {
        let app = try await makeApp()
        let (id, object) = try addCharacter(.mannequin, to: app)
        app.addKeyframe()
        app.applyPreset(.reaching)
        app.sceneEdited()
        try await Task.sleep(for: .milliseconds(600))
        let keyframe = try #require(app.animator.selectedKeyframe)

        // Posing, with the joint markers out and the pose changed after the keyframe.
        app.immersiveSpaceState = .open
        app.setCharacterEditMode(.pose)
        app.selectJoint(.rightWrist)
        app.workspace.setPoseOverlay(app.poseOverlay)
        app.workspace.setCharacterPose(.neutral, on: object)
        let rig = try #require(CharacterBuilder.rig(in: object))
        #expect(count(in: rig) { $0.name == CharacterBuilder.markerName && $0.isEnabled } == Joint.allCases.count)

        let snapshot = app.workspace.snapshot(at: keyframe.poses, characterPoses: keyframe.characterPoses,
                                              keyframedObjects: app.animator.timeline.keyframedObjectIDs)
        #expect(count(in: snapshot) { $0.components.has(EditorOnlyComponent.self) } == 0)
        #expect(count(in: snapshot) { $0.name == WorkspaceScene.ikHandleName } == 0)
        // The snapshot shows the keyframe's pose; the live character is left as it was.
        let snappedHand = try #require(snapshot.findEntity(named: "Joint.rightShoulder"))
        #expect(abs(snappedHand.orientation.angle - CharacterKinematics.rotation(PosePreset.reaching.pose[.rightShoulder], for: .rightShoulder).angle) < 0.01)
        #expect(app.workspace.characterPose(of: object)?.isNeutral == true)

        // Playback hides the markers.
        app.workspace.setCharacterPose(PosePreset.reaching.pose, on: object)
        app.addKeyframe()
        app.animator.play()
        #expect(app.poseOverlay == nil)
        app.animator.pause()
        _ = id
    }

    @Test func savedPosesAreKeptForEveryProject() async throws {
        let app = try await makeApp()
        _ = try addCharacter(.mannequin, to: app)
        app.applyPreset(.waving)
        app.nudgeJoint(.head, axis: .side, by: 10)
        app.saveCurrentPose(named: "Hello there")
        #expect(app.savedPoses.map(\.name) == ["Hello there"])

        let other = AppModel()
        await other.createProject()
        other.placeCharacter(.child)
        let saved = try #require(other.savedPoses.first)
        other.applyPose(saved.pose)
        let child = try #require(other.selectedObjectID.flatMap { other.workspace.object(withID: $0) })
        #expect(other.workspace.characterPose(of: child)?[.head].side == PosePreset.waving.pose[.head].side + 10)

        other.deleteSavedPose(saved)
        #expect(AppModel().savedPoses.isEmpty)
    }

    @Test func promptsNamingPeopleGivePoseableCharacters() async throws {
        let service = SampleModelGenerationService()
        #expect(try await service.generateObject(prompt: "a blue kid").recipe.characterKind == .child)
        #expect(try await service.generateObject(prompt: "a man by a tree").recipe.characterKind == .mannequin)
        #expect(try await service.generateObject(prompt: "a tree by a man").recipe.characterKind == nil)
    }
}

/// The Pose Studio: a large copy of the selected character, posed with drags.
@MainActor
@Suite(.serialized)
struct PoseStudioTests {
    init() throws {
        let storage = FileManager.default.temporaryDirectory.appending(path: "PoseStudioTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: storage, withIntermediateDirectories: true)
        ProjectStore.storageOverride = storage
    }

    @Test func swingingFollowsTheDragFromWhereItStarted() {
        // Dragging the hanging right arm from straight down to straight forward raises it forward.
        let raised = CharacterKinematics.swing(.rightShoulder, startingAt: .zero, from: [0, -1, 0], to: [0, 0, 1])
        #expect(abs(raised.bend - 90) < 0.5 && abs(raised.side) < 0.5)
        // The same motion starting partway through only adds the difference.
        let start = JointRotation(bend: 30)
        let more = CharacterKinematics.swing(.rightShoulder, startingAt: start, from: [0, -1, 0], to: [0, -0.7071, 0.7071])
        #expect(abs(more.bend - 75) < 0.5)
        // A hinge only bends, and only within its limits.
        let elbow = CharacterKinematics.swing(.leftElbow, startingAt: .zero, from: [0, -1, 0], to: [1, 0, -1])
        #expect(elbow.twist == 0 && elbow.side == 0 && elbow.bend >= 0)
        #expect(CharacterKinematics.swing(.leftKnee, startingAt: .zero, from: [0, -1, 0], to: [0, -1, 0]) == .zero)
    }

    @Test func theStudioMirrorsTheSelectedCharacterAtALargeSize() async throws {
        let app = AppModel()
        await app.createProject()
        app.placeCharacter(.mannequin)
        app.applyPreset(.waving)
        app.isPoseStudioOpen = true
        app.setCharacterEditMode(.pose)
        app.updatePoseStudio()

        let figure = try #require(app.poseStudio.character)
        let shoulder = try #require(app.poseStudio.jointEntity(.rightShoulder))
        #expect(shoulder.orientation == CharacterKinematics.rotation(PosePreset.waving.pose[.rightShoulder], for: .rightShoulder))
        // About 55 cm tall, standing on the studio floor.
        var bounds: BoundingBox?
        func visit(_ entity: Entity) {
            if entity.components.has(BodyPartComponent.self) {
                let part = entity.visualBounds(relativeTo: app.poseStudio.root)
                bounds = bounds.map { $0.union(part) } ?? part
            }
            entity.children.forEach(visit)
        }
        visit(figure)
        let size = try #require(bounds)
        #expect(size.extents.y > 0.55 && size.extents.y < 0.72) // a little taller than standing, with the hand raised
        #expect(abs(size.min.y) < 0.005)

        // Recoloring rebuilds the studio figure; deselecting clears it.
        app.recolorSelectedObject("blue")
        app.updatePoseStudio()
        #expect(app.poseStudio.character !== figure)
        app.selectObject(nil)
        app.updatePoseStudio()
        #expect(app.poseStudio.character == nil)
    }

    @Test func draggingInTheStudioPosesTheSceneCharacterAsOneUndoStep() async throws {
        let app = AppModel()
        await app.createProject()
        app.placeCharacter(.mannequin)
        let object = try #require(app.selectedObjectID.flatMap { app.workspace.object(withID: $0) })
        app.isPoseStudioOpen = true
        app.setCharacterEditMode(.pose)
        app.updatePoseStudio()

        // Grab the left forearm area and drag it forward, in several steps.
        let studio = app.poseStudio
        let elbow = try #require(studio.jointEntity(.leftElbow))
        let start = elbow.position(relativeTo: nil) + [0, -0.06, 0]
        for step in 1...5 {
            let now = start + [0, Float(step) * 0.012, Float(step) * 0.012]
            let from = try #require(studio.direction(from: .leftShoulder, to: start))
            let to = try #require(studio.direction(from: .leftShoulder, to: now))
            app.swingJoint(.leftShoulder, from: from, to: to)
            app.updatePoseStudio()
        }
        app.endPoseDrag()
        let pose = try #require(app.workspace.characterPose(of: object))
        #expect(pose[.leftShoulder].bend > 10)
        #expect(app.selectedJoint == .leftShoulder)
        #expect(!app.isPoseDragging)

        // Place the right hand with the reach target.
        app.selectJoint(.rightWrist)
        app.poseTool = .reach
        app.dragReach(.rightArm, to: [-0.1, -0.2, 0.3])
        app.endPoseDrag()
        #expect(simd_distance(try #require(app.reach(of: .rightArm)), [0.1, -0.2, 0.3]) < 0.01)

        app.undo()
        #expect(app.workspace.characterPose(of: object)?[.rightElbow].bend == 0)
        app.undo()
        #expect(app.workspace.characterPose(of: object)?.isNeutral == true)
    }
}
