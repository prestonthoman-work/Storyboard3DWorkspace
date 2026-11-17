//
//  CharacterInteractionTests.swift
//  Storyboard3DWorkspaceTests
//

import Foundation
import RealityKit
import Testing
@testable import Storyboard3DWorkspace

@MainActor
struct HeadAimTests {
    private let layout = RigLayout(proportions: CharacterKind.mannequin.proportions)

    @Test func theFaceTurnsToATargetToTheSide() {
        let eyes = HeadAim.eyes(in: .neutral, layout: layout).position
        let target = eyes + SIMD3<Float>(1, 0.3, 1)        // ahead, to the character's left, a little up
        let aimed = HeadAim.aim(.neutral, at: target, layout: layout)
        #expect(HeadAim.angleOff(aimed, from: target, layout: layout) < 2)
        // Only the upper body turns.
        for joint in Joint.allCases where ![.chest, .neck, .head].contains(joint) {
            #expect(aimed[joint].isZero)
        }
        // The head and neck do most of it.
        #expect(abs(aimed[.chest].twist) < abs(aimed[.neck].twist))
    }

    @Test func aTargetBehindIsFacedAsFarAsTheBodyAllows() {
        let eyes = HeadAim.eyes(in: .neutral, layout: layout).position
        let target = eyes + SIMD3<Float>(0.05, 0, -1)       // almost straight behind
        let aimed = HeadAim.aim(.neutral, at: target, layout: layout)
        let off = HeadAim.angleOff(aimed, from: target, layout: layout)
        #expect(off > 20)                                   // can't turn all the way round
        #expect(off < HeadAim.angleOff(.neutral, from: target, layout: layout))
        for joint in [Joint.chest, .neck, .head] {
            #expect(joint.limits.clamp(aimed[joint]) == aimed[joint])
        }
    }

    @Test func seatedLegsPutTheHipsAtSeatHeight() {
        for seatHeight: Float in [0.35, 0.45, 0.6] {
            let pose = SeatedLegs.sit(PosePreset.sitting.pose, seatHeight: seatHeight, layout: layout)
            let frames = CharacterKinematics.frames(for: pose, layout: layout)
            let hip = frames[.leftHip]!.position.y
            let ankle = frames[.leftAnkle]!.position.y
            let expected = seatHeight + SeatedLegs.thighThickness - layout.ankleHeight
            #expect(abs((hip - ankle) - expected) < 0.01, "seat \(seatHeight)")
        }
    }
}

@MainActor
struct HandShapeTests {
    @Test func posesWithoutHandShapesSaveAsBefore() throws {
        let plain = PosePreset.crouching.pose
        let data = try JSONEncoder().encode(plain)
        // Still just the joint angles, so older versions of the app can read it.
        #expect(try JSONDecoder().decode([Joint: JointRotation].self, from: data) == plain.rotations)

        var pointing = PosePreset.pointing.pose
        #expect(pointing[.right] == .point)
        pointing[.left] = .fist
        let decoded = try JSONDecoder().decode(CharacterPose.self, from: JSONEncoder().encode(pointing))
        #expect(decoded == pointing)
        #expect(decoded[.left] == .fist && decoded[.right] == .point)
    }

    @Test func handsMirrorAndChangeHalfwayThroughABlend() {
        let pose = CharacterPose([:], hands: [.right: .point, .left: .open])
        #expect(pose.mirrored[.left] == .point && pose.mirrored[.right] == .open)
        let fist = CharacterPose([:], hands: [.right: .fist])
        #expect(pose.interpolated(to: fist, 0.4)[.right] == .point)
        #expect(pose.interpolated(to: fist, 0.6)[.right] == .fist)
        #expect(pose.interpolated(to: fist, 0.6)[.left] == .relaxed)
        #expect(!pose.matches(fist))
        #expect(!CharacterPose([:], hands: [.left: .grip]).isNeutral)
    }

    @Test func onlyTheChosenShapeShows() {
        let content = CharacterBuilder.make(.mannequin, proportions: CharacterKind.mannequin.proportions, tint: nil)
        CharacterBuilder.apply(CharacterPose([:], hands: [.right: .point]), to: content)
        let joints = CharacterBuilder.joints(in: content)
        func shown(_ hand: Hand) -> Set<HandShape> {
            Set(joints[hand.wrist]!.children.compactMap { part in
                part.isEnabled ? part.components[HandShapePartComponent.self]?.shape : nil
            })
        }
        #expect(shown(.right) == [.point])
        #expect(shown(.left) == [.relaxed])
    }
}

extension SharedStateTests {
    @MainActor
    @Suite(.serialized)
    struct CharacterInteractionTests {
        init() throws {
            let storage = FileManager.default.temporaryDirectory.appending(path: "CharacterInteractionTests-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: storage, withIntermediateDirectories: true)
            ProjectStore.storageOverride = storage
        }

        private func makeApp() async throws -> AppModel {
            let app = AppModel()
            await app.createProject()
            _ = try #require(app.currentProject)
            return app
        }

        private func addCharacter(to app: AppModel, at position: SIMD3<Float>) throws -> (ObjectID, Entity) {
            app.placeCharacter(.mannequin)
            let id = try #require(app.selectedObjectID)
            let object = try #require(app.workspace.object(withID: id))
            object.position = position
            object.orientation = simd_quatf(angle: 0, axis: [0, 1, 0])
            return (id, object)
        }

        private func addObject(_ kind: SampleObjectCatalog.Kind, to app: AppModel, at position: SIMD3<Float>) throws -> (ObjectID, Entity) {
            app.placeCatalogObject(kind)
            let id = try #require(app.selectedObjectID)
            let object = try #require(app.workspace.object(withID: id))
            object.position = position
            return (id, object)
        }

        private func eyes(of object: Entity, in app: AppModel) throws -> SIMD3<Float> {
            let head = try #require(app.workspace.jointEntity(.head, of: object))
            return head.convert(position: HeadAim.eyeOffset(layout: try #require(app.workspace.rigLayout(of: object))), to: nil)
        }

        /// Degrees between where the character's face points and the direction to `point`.
        private func lookError(of object: Entity, to point: SIMD3<Float>, in app: AppModel) throws -> Float {
            let head = try #require(app.workspace.jointEntity(.head, of: object))
            let facing = simd_normalize(head.convert(direction: [0, 0, 1], to: nil))
            let toPoint = simd_normalize(point - (try eyes(of: object, in: app)))
            return acos(min(max(simd_dot(facing, toPoint), -1), 1)) * 180 / .pi
        }

        private func palm(of object: Entity, hand: Hand, in app: AppModel) throws -> SIMD3<Float> {
            try #require(app.workspace.jointEntity(hand.wrist, of: object)).convert(position: [0, -0.09, 0], to: nil)
        }

        private func center(of object: Entity) throws -> SIMD3<Float> {
            object.convert(position: try #require(WorkspaceScene.geometryBounds(of: object)).center, to: nil)
        }

        // MARK: Look At

        @Test func aCharacterLooksAtAnotherAndCanAimAgain() async throws {
            let app = try await makeApp()
            let (speaker, speakerEntity) = try addCharacter(to: app, at: [-0.05, 0, 0])
            let (listener, listenerEntity) = try addCharacter(to: app, at: [0.05, 0, 0.06])
            app.selectObject(speaker)

            app.lookSelectedCharacter(at: listener)
            #expect(try lookError(of: speakerEntity, to: eyes(of: listenerEntity, in: app), in: app) < 3)
            #expect(app.selectedLookTarget?.id == listener)
            #expect(app.poseNote == nil)

            // One undo step back to standing straight.
            app.undo()
            #expect(app.selectedCharacterPose?.isNeutral == true)
            app.redo()

            // After the listener moves, the speaker's head follows (on the next frame, or any render).
            listenerEntity.position = [0.02, 0, 0.12]
            #expect(try lookError(of: speakerEntity, to: eyes(of: listenerEntity, in: app), in: app) > 5)
            _ = CompositionRenderer.snapshot(of: app.workspace.baseAnchor)
            #expect(try lookError(of: speakerEntity, to: eyes(of: listenerEntity, in: app), in: app) < 3)

            // It's saved, and comes back with the project.
            #expect(app.saveNow())
            let project = try #require(app.currentProject)
            let reopened = AppModel()
            #expect(await reopened.openProject(try #require(reopened.projects.first { $0.id == project.id })))
            #expect(reopened.lookTargets[speaker] == listener)

            // Posing the head by hand ends it.
            app.setJointAngle(10, axis: .twist, of: .head)
            #expect(app.selectedLookTarget == nil)
            #expect(speakerEntity.components[LookTargetComponent.self] == nil)
        }

        @Test func aTargetBehindGetsANote() async throws {
            let app = try await makeApp()
            let (_, _) = try addCharacter(to: app, at: [0, 0, -0.1])
            let target = try #require(app.selectedObjectID)
            let (character, _) = try addCharacter(to: app, at: [0, 0, 0.05])
            app.selectObject(character)
            app.lookSelectedCharacter(at: target)
            #expect(app.poseNote != nil)
        }

        // MARK: Sit On

        @Test func aCharacterSitsOnAnObjectWithItsFeetOnTheGround() async throws {
            let app = try await makeApp()
            let (rock, rockEntity) = try addObject(.rock, to: app, at: [0.06, 0, 0])
            // Squash the rock to chair height for a 1:35 figure (about 45 cm in life).
            let rockTop = try #require(WorkspaceScene.geometryBounds(of: rockEntity)).max.y
            rockEntity.scale = [1, 0.013 / rockTop, 1]
            let (character, characterEntity) = try addCharacter(to: app, at: [-0.06, 0, 0])
            let standingPosition = characterEntity.position

            app.selectObject(character)
            app.sitSelectedCharacter(on: rock)
            #expect(app.poseNote == nil)

            let container = app.workspace.objectsContainer
            let seatTop = rockEntity.convert(position: [0, try #require(WorkspaceScene.geometryBounds(of: rockEntity)).max.y, 0],
                                             to: container).y
            let hip = try #require(app.workspace.jointEntity(.leftHip, of: characterEntity))
            let hipPosition = hip.convert(position: .zero, to: container)
            let scale = RigLayout.miniatureScale * CharacterKind.mannequin.proportions.height
            #expect(abs(hipPosition.y - (seatTop + SeatedLegs.thighThickness * scale)) < 0.0015)

            // Over the seat, and the feet are still on the ground.
            let hips = (hipPosition + (try #require(app.workspace.jointEntity(.rightHip, of: characterEntity))
                .convert(position: .zero, to: container))) / 2
            #expect(simd_length(SIMD2(hips.x - 0.06, hips.z)) < 0.012)
            let body = try #require(WorkspaceScene.geometryBounds(of: characterEntity))
            #expect(abs(body.min.y) < 0.001)

            // One undo step puts it back, standing where it was.
            app.undo()
            #expect(simd_length(characterEntity.position - standingPosition) < 1e-5)
            #expect(app.selectedCharacterPose?.isNeutral == true)
        }

        @Test func aSeatTooHighIsReported() async throws {
            let app = try await makeApp()
            let (building, _) = try addObject(.building, to: app, at: [0.08, 0, 0])
            let (character, _) = try addCharacter(to: app, at: [-0.06, 0, 0])
            app.selectObject(character)
            app.sitSelectedCharacter(on: building)
            #expect(app.poseNote != nil)
        }

        // MARK: Lean On

        private func bounds(of object: Entity, in app: AppModel) throws -> BoundingBox {
            let container = app.workspace.objectsContainer
            let local = try #require(WorkspaceScene.geometryBounds(of: object))
            var result: BoundingBox?
            for corner in 0..<8 {
                let point = SIMD3(corner & 1 == 0 ? local.min.x : local.max.x, corner & 2 == 0 ? local.min.y : local.max.y,
                                  corner & 4 == 0 ? local.min.z : local.max.z)
                let converted = object.convert(position: point, to: container)
                result = result.map { $0.union(converted) } ?? BoundingBox(min: converted, max: converted)
            }
            return try #require(result)
        }

        @Test func aCharacterLeansItsBackOnAWall() async throws {
            let app = try await makeApp()
            let (building, buildingEntity) = try addObject(.building, to: app, at: [0, 0, 0])
            let (character, characterEntity) = try addCharacter(to: app, at: [0, 0, 0.09])   // in front of its +Z side
            let before = characterEntity.transform

            app.selectObject(character)
            app.leanSelectedCharacter(on: building, with: .back)
            #expect(app.poseNote == nil)

            // Facing away from the wall, tilted back, back touching it, feet on the ground.
            let forward = characterEntity.convert(direction: [0, 0, 1], to: app.workspace.objectsContainer)
            #expect(simd_dot(simd_normalize(forward), [0, 0, 1]) > 0.99)
            #expect((app.selectedCharacterPose?[.pelvis].bend ?? 0) < -5)
            // Against the wall itself (6 cm wide), not the base and roof cap that stick out past it.
            let wall = buildingEntity.position.z + 0.03
            #expect(try bounds(of: buildingEntity, in: app).max.z > wall + 0.002)
            let body = try bounds(of: characterEntity, in: app)
            #expect(abs(body.min.z - wall) < 0.0008)
            #expect(abs(body.min.y - characterEntity.position.y) < 0.001)

            app.undo()
            #expect(simd_length(characterEntity.transform.translation - before.translation) < 1e-5)
            #expect(app.selectedCharacterPose?.isNeutral == true)
        }

        @Test func aShoulderLeanTurnsThatSideToTheWall() async throws {
            let app = try await makeApp()
            let (building, buildingEntity) = try addObject(.building, to: app, at: [0, 0, 0])
            let (character, characterEntity) = try addCharacter(to: app, at: [0.1, 0, 0.01])  // off its +X side
            app.selectObject(character)

            app.leanSelectedCharacter(on: building, with: .rightShoulder)
            // The character's right (its -X) points at the wall, which is toward -X here.
            let right = characterEntity.convert(direction: [-1, 0, 0], to: app.workspace.objectsContainer)
            #expect(simd_dot(simd_normalize(right), [-1, 0, 0]) > 0.99)
            #expect(abs(try bounds(of: characterEntity, in: app).min.x - (buildingEntity.position.x + 0.03)) < 0.0008)
        }

        @Test func aLowObjectCantBeLeanedOnWithTheBack() async throws {
            let app = try await makeApp()
            let (rock, _) = try addObject(.rock, to: app, at: [0, 0, 0])
            let (character, characterEntity) = try addCharacter(to: app, at: [0, 0, 0.08])
            let before = characterEntity.transform
            app.selectObject(character)

            app.leanSelectedCharacter(on: rock, with: .back)
            #expect(app.poseNote?.contains("too low") == true)
            #expect(characterEntity.transform == before)
            #expect(app.selectedCharacterPose?.isNeutral == true)
        }

        @Test func aHandRestsOnACounterAndStepsCloserIfNeeded() async throws {
            let app = try await makeApp()
            let (counter, counterEntity) = try addObject(.rock, to: app, at: [0, 0, 0])
            // Counter height for a 1:35 figure: about 90 cm in life.
            let top = try #require(WorkspaceScene.geometryBounds(of: counterEntity)).max.y
            counterEntity.scale = [1, 0.026 / top, 1]
            let (character, characterEntity) = try addCharacter(to: app, at: [0, 0, 0.12])
            characterEntity.orientation = simd_quatf(angle: .pi, axis: [0, 1, 0])        // facing the counter
            app.selectObject(character)

            app.leanSelectedCharacter(on: counter, with: .rightHand)
            #expect(app.poseNote?.contains("Stepped closer") == true)
            let box = try bounds(of: counterEntity, in: app)
            let wrist = try #require(app.workspace.jointEntity(.rightWrist, of: characterEntity))
                .convert(position: .zero, to: app.workspace.objectsContainer)
            let scale = RigLayout.miniatureScale * CharacterKind.mannequin.proportions.height
            #expect(abs(wrist.y - (box.max.y + 0.035 * scale)) < 0.0015)
            #expect(wrist.x > box.min.x && wrist.x < box.max.x && wrist.z > box.min.z && wrist.z < box.max.z)
        }

        @Test func aCharacterHalfSitsOnAnEdgeAndLeansOnItsElbows() async throws {
            let app = try await makeApp()
            let (table, tableEntity) = try addObject(.building, to: app, at: [0, 0, 0])
            // Squash the building into a table about 80 cm high in life.
            let top = try #require(WorkspaceScene.geometryBounds(of: tableEntity)).max.y
            tableEntity.scale = [1, 0.023 / top, 1]
            let (character, characterEntity) = try addCharacter(to: app, at: [0, 0, 0.08])
            app.selectObject(character)
            let container = app.workspace.objectsContainer
            let scale = RigLayout.miniatureScale * CharacterKind.mannequin.proportions.height

            app.leanSelectedCharacter(on: table, with: .hip)
            #expect(app.poseNote == nil)
            // Back to the table, hips just over its edge at its height, feet on the ground.
            let forward = characterEntity.convert(direction: [0, 0, 1], to: container)
            #expect(simd_dot(simd_normalize(forward), [0, 0, 1]) > 0.99)
            let hip = try #require(app.workspace.jointEntity(.leftHip, of: characterEntity)).convert(position: .zero, to: container)
            let edge = try bounds(of: tableEntity, in: app).max.z
            #expect(hip.z < edge && hip.z > edge - 0.006)
            #expect(abs(hip.y - (0.023 + SeatedLegs.thighThickness * scale)) < 0.002)
            #expect(abs(try bounds(of: characterEntity, in: app).min.y - characterEntity.position.y) < 0.001)

            app.leanSelectedCharacter(on: table, with: .elbows)
            #expect(app.poseNote == nil)
            // Facing the table, leaning in, both wrists resting on top.
            let facing = characterEntity.convert(direction: [0, 0, 1], to: container)
            #expect(simd_dot(simd_normalize(facing), [0, 0, -1]) > 0.99)
            #expect((app.selectedCharacterPose?[.spine].bend ?? 0) > 10)
            for wrist in [Joint.leftWrist, .rightWrist] {
                let point = try #require(app.workspace.jointEntity(wrist, of: characterEntity)).convert(position: .zero, to: container)
                #expect(abs(point.y - (0.023 + 0.04 * scale)) < 0.003, "\(wrist)")
                #expect(point.z < edge)
            }
        }

        @Test func twoCharactersHoldHands() async throws {
            let app = try await makeApp()
            let (ana, anaEntity) = try addCharacter(to: app, at: [-0.03, 0, 0])
            let (ben, benEntity) = try addCharacter(to: app, at: [0.12, 0, 0])         // too far: Ben steps closer
            app.selectObject(ana)

            app.holdHands(with: ben)
            // Ana's left hand (her left is +X, toward Ben) meets Ben's right hand.
            let container = app.workspace.objectsContainer
            let anaHand = try #require(app.workspace.jointEntity(.leftWrist, of: anaEntity)).convert(position: .zero, to: container)
            let benHand = try #require(app.workspace.jointEntity(.rightWrist, of: benEntity)).convert(position: .zero, to: container)
            #expect(simd_length(anaHand - benHand) < 0.002)
            #expect(benEntity.position.x < 0.12)
            // One undo step for both.
            app.undo()
            #expect(app.workspace.characterPose(of: benEntity)?.isNeutral == true)
            #expect(abs(benEntity.position.x - 0.12) < 1e-5)
        }

        // MARK: Held objects

        @Test func aHeldObjectFollowsTheHandAndIsSaved() async throws {
            let app = try await makeApp()
            let (character, characterEntity) = try addCharacter(to: app, at: [0, 0, 0])
            let (lamp, lampEntity) = try addObject(.lamp, to: app, at: [0.1, 0, 0])

            app.putSelectedObject(in: .right, of: character)
            #expect(app.holderDescription(of: lamp) == "Mannequin's right hand")
            #expect(lampEntity.components[ObjectGravityComponent.self]?.isAttached == true)
            #expect(simd_length(try center(of: lampEntity) - palm(of: characterEntity, hand: .right, in: app)) < 1e-4)

            // Wave: the hand goes up, and a render takes the lamp with it.
            let before = try palm(of: characterEntity, hand: .right, in: app)
            app.selectObject(character)
            app.applyPreset(.waving)
            let after = try palm(of: characterEntity, hand: .right, in: app)
            #expect(simd_length(after - before) > 0.005)
            let snapshot = CompositionRenderer.snapshot(of: app.workspace.baseAnchor)
            #expect(snapshot.findEntity(named: WorkspaceScene.selectionIndicatorName) == nil)
            #expect(simd_length(try center(of: lampEntity) - after) < 1e-4)

            // Saved and reopened, it's still in the hand.
            #expect(app.saveNow())
            let project = try #require(app.currentProject)
            let reopened = AppModel()
            #expect(await reopened.openProject(try #require(reopened.projects.first { $0.id == project.id })))
            #expect(reopened.holds[lamp]?.hand == .right)
            let reopenedLamp = try #require(reopened.workspace.object(withID: lamp))
            let reopenedCharacter = try #require(reopened.workspace.object(withID: character))
            #expect(simd_length(try center(of: reopenedLamp) - palm(of: reopenedCharacter, hand: .right, in: reopened)) < 1e-4)
        }

        @Test func lettingGoAndDeletingTheHolderFreeTheObject() async throws {
            let app = try await makeApp()
            let (character, characterEntity) = try addCharacter(to: app, at: [0, 0, 0])
            let (lamp, lampEntity) = try addObject(.lamp, to: app, at: [0.1, 0, 0])
            app.putSelectedObject(in: .left, of: character)
            // The hand closes round it, and opens again when it lets go.
            #expect(app.workspace.characterPose(of: characterEntity)?[.left] == .grip)
            app.letGoOfSelectedObject()
            #expect(app.workspace.characterPose(of: characterEntity)?[.left] == .relaxed)
            app.undo()

            app.letGoOfSelectedObject()
            #expect(app.holds[lamp] == nil)
            #expect(lampEntity.components[HeldPropComponent.self] == nil)
            #expect(lampEntity.components[ObjectGravityComponent.self]?.isAttached == false)
            app.undo()
            #expect(app.holds[lamp]?.hand == .left)

            app.selectObject(character)
            app.deleteSelectedObject()
            #expect(app.holds[lamp] == nil)
            app.undo()
            #expect(app.holds[lamp]?.character == character)
        }

        @Test func movingAHeldObjectByHandChangesItsGrip() async throws {
            let app = try await makeApp()
            let (character, characterEntity) = try addCharacter(to: app, at: [0, 0, 0])
            let (lamp, lampEntity) = try addObject(.lamp, to: app, at: [0.1, 0, 0])
            app.putSelectedObject(in: .right, of: character)

            app.manipulationBegan(on: lampEntity)
            lampEntity.position.x += 0.01
            let moved = try center(of: lampEntity)
            app.manipulationEnded(on: lampEntity)
            HeldProps.attachAll(in: app.workspace.objectsContainer)
            #expect(simd_length(try center(of: lampEntity) - moved) < 1e-4)

            // And keeps that grip as the hand moves.
            app.selectObject(character)
            app.applyPreset(.pointing)
            HeldProps.attachAll(in: app.workspace.objectsContainer)
            let offset = try center(of: lampEntity) - palm(of: characterEntity, hand: .right, in: app)
            #expect(abs(simd_length(offset) - 0.01) < 0.002)
            #expect(app.holds[lamp] != nil)
        }

        @Test func anObjectIsPickedUpBetweenKeyframes() async throws {
            let app = try await makeApp()
            let (character, characterEntity) = try addCharacter(to: app, at: [0, 0, 0])
            let (lamp, lampEntity) = try addObject(.lamp, to: app, at: [0.1, 0, 0])
            app.addKeyframe()                                   // 1: lamp on the ground
            let resting = lampEntity.position
            app.addKeyframe()                                   // 2: lamp in hand
            app.selectObject(lamp)
            app.putSelectedObject(in: .right, of: character)
            app.finishSceneEdit()
            app.addKeyframe()                                   // 3: still in hand, hand raised
            app.selectObject(character)
            app.applyPreset(.waving)
            app.finishSceneEdit()

            let keyframes = app.animator.timeline.keyframes
            #expect(keyframes[0].heldProps.isEmpty)
            #expect(keyframes[1].heldProps[lamp]?.hand == .right)
            #expect(keyframes[2].heldProps[lamp]?.hand == .right)

            // Between 1 and 2 it's free (moving from the ground to the hand); between 2 and 3 it follows the hand.
            let timeline = app.animator.timeline
            #expect(timeline.heldProps(at: (keyframes[0].time + keyframes[1].time) / 2)[lamp] == .some(nil))
            #expect(timeline.heldProps(at: (keyframes[1].time + keyframes[2].time) / 2)[lamp]??.hand == .right)

            app.selectKeyframe(keyframes[0])
            #expect(app.holds[lamp] == nil)
            #expect(simd_length(lampEntity.position - resting) < 0.002)
            app.selectKeyframe(keyframes[2])
            #expect(app.holds[lamp]?.hand == .right)
            #expect(simd_length(try center(of: lampEntity) - palm(of: characterEntity, hand: .right, in: app)) < 1e-3)
        }

        @Test func aCharacterWalksBetweenKeyframes() async throws {
            let app = try await makeApp()
            let (character, characterEntity) = try addCharacter(to: app, at: [-0.08, 0, 0])
            app.addKeyframe()
            characterEntity.position = [0.08, 0, 0]
            app.addKeyframe()
            app.selectObject(character)
            app.selectedCharacterWalks = true

            let timeline = app.animator.timeline
            let middle = (timeline.keyframes[0].time + timeline.keyframes[1].time) / 2
            let walk = try #require(timeline.walk(of: character, at: middle))
            #expect(walk.weight == 1)
            #expect(simd_dot(walk.heading, [1, 0, 0]) > 0.99)
            // 16 cm at 1:35 is about 5.6 m of walking: a couple of strides by the middle.
            #expect(walk.phase > 2 * .pi)

            // Facing the way it goes, legs apart; exact poses again at the keyframes.
            let pose = try #require(timeline.characterPoses(at: middle, walkers: [character])[character])
            let facing = try #require(timeline.poses(at: middle, walkers: [character])[character]).rotation.act([0, 0, 1])
            #expect(simd_dot(facing, [1, 0, 0]) > 0.99)
            #expect(abs(pose[.leftHip].bend - pose[.rightHip].bend) > 1 || pose[.leftKnee].bend != pose[.rightKnee].bend)
            #expect(timeline.walk(of: character, at: timeline.keyframes[1].time) == nil)
            #expect(timeline.characterPoses(at: middle)[character]?.isNeutral ?? true)    // not walkers: no stride

            // Saved with the project.
            #expect(app.saveNow())
            let project = try #require(app.currentProject)
            let reopened = AppModel()
            #expect(await reopened.openProject(try #require(reopened.projects.first { $0.id == project.id })))
            #expect(reopened.animator.walkers == [character])
        }

        // MARK: Eyelines

        @Test func eyelinesFollowCharactersAndStayOutOfPhotos() async throws {
            let app = try await makeApp()
            let preference = app.showsEyelines
            defer { app.showsEyelines = preference }
            let (_, a) = try addCharacter(to: app, at: [-0.05, 0, 0])
            _ = try addCharacter(to: app, at: [0.05, 0, 0])
            _ = try addObject(.tree, to: app, at: [0, 0, -0.08])

            app.showsEyelines = true
            let root = app.workspace.eyelinesRoot
            EyelineSystem.refresh(root)
            let cones = root.children.filter { $0.name == "EyelineCone" && $0.isEnabled }
            #expect(cones.count == 2)
            #expect(root.children.contains { $0.name == "EyelineAxis" && $0.isEnabled })
            let firstCone = try #require(cones.first)
            #expect(simd_length(firstCone.position(relativeTo: nil) - (try eyes(of: a, in: app))) < 1e-4)
            #expect(CompositionRenderer.snapshot(of: app.workspace.baseAnchor).findEntity(named: "EyelineCone") == nil)

            app.showsEyelines = false
            EyelineSystem.refresh(root)
            #expect(!root.children.contains { $0.isEnabled })
        }
    }
}
