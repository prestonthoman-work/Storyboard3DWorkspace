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

            // After the listener moves, aiming again follows.
            listenerEntity.position = [0.02, 0, 0.12]
            #expect(try lookError(of: speakerEntity, to: eyes(of: listenerEntity, in: app), in: app) > 5)
            app.reaimSelectedCharacter()
            #expect(try lookError(of: speakerEntity, to: eyes(of: listenerEntity, in: app), in: app) < 3)
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
            let (character, _) = try addCharacter(to: app, at: [0, 0, 0])
            let (lamp, lampEntity) = try addObject(.lamp, to: app, at: [0.1, 0, 0])
            app.putSelectedObject(in: .left, of: character)

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
