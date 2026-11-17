//
//  ExportDetailTests.swift
//  Storyboard3DWorkspaceTests
//

import AVFoundation
import CoreGraphics
import Foundation
import Metal
import RealityKit
import Testing
import UIKit
@testable import Storyboard3DWorkspace

@MainActor
struct LensSmoothingTests {
    /// A gray texture with a white square at `x`, like one render through the lens.
    private func frame(device: any MTLDevice, width: Int, height: Int, squareX: Int, sharpX: Int) -> any MTLTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
        descriptor.storageMode = .shared
        let texture = device.makeTexture(descriptor: descriptor)!
        var pixels = [UInt8](repeating: 60, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                // A far square, at a different place in every frame (out of focus), and a
                // near one that's in the same place in every frame (in focus).
                let far = x >= squareX && x < squareX + 20 && y >= 20 && y < 40
                let near = x >= sharpX && x < sharpX + 20 && y >= 20 && y < 40
                if far || near { for c in 0..<3 { pixels[(y * width + x) * 4 + c] = 255 } }
                pixels[(y * width + x) * 4 + 3] = 255
            }
        }
        texture.replace(region: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0, withBytes: pixels, bytesPerRow: width * 4)
        return texture
    }

    private func grays(_ image: CGImage) -> [UInt8] {
        let width = image.width, height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height)
        let context = CGContext(data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
                                space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return pixels
    }

    @Test func separateCopiesOfAFarBlurAreMergedButFocusStaysSharp() throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let width = 160, height = 60
        var accumulator = CompositionRenderer.Accumulator(width: width, height: height)
        accumulator.reset()
        // Four copies of the far square, 12 px apart: visible steps without smoothing.
        for shift in [0, 12, 24, 36] {
            accumulator.add(frame(device: device, width: width, height: height, squareX: 80 + shift, sharpX: 10))
        }
        let rough = grays(try accumulator.finish(smoothing: 0))
        let smooth = grays(try accumulator.finish(smoothing: 7))
        let row = 30 * width

        // Along the far blur, the biggest jump between neighboring pixels gets much smaller.
        func largestStep(_ pixels: [UInt8], from start: Int, to end: Int) -> Int {
            (start..<end).map { abs(Int(pixels[row + $0 + 1]) - Int(pixels[row + $0])) }.max() ?? 0
        }
        #expect(largestStep(smooth, from: 85, to: 130) < largestStep(rough, from: 85, to: 130) / 2)
        // The square in focus keeps its hard edge.
        #expect(abs(Int(smooth[row + 9]) - Int(smooth[row + 11])) > 150)
    }
}

extension SharedStateTests {
    @MainActor
    @Suite(.serialized)
    struct ExportDetailTests {
        init() throws {
            let storage = FileManager.default.temporaryDirectory.appending(path: "ExportDetailTests-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: storage, withIntermediateDirectories: true)
            ProjectStore.storageOverride = storage
        }

        private func solidImage() -> CGImage {
            let context = CGContext(data: nil, width: 64, height: 36, bitsPerComponent: 8, bytesPerRow: 0,
                                    space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
            context.setFillColor(CGColor(gray: 0.5, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: 64, height: 36))
            return context.makeImage()!
        }

        @Test func theShotListHasARowPerShotWithItsCameraAndCast() async throws {
            let app = AppModel()
            await app.createProject()
            app.placeCharacter(.mannequin)
            app.renameObject(try #require(app.selectedObjectID), to: "Ana")
            app.placeCatalogObject(.car)
            app.addKeyframe()
            let first = try #require(app.animator.selectedKeyframeID)
            app.setNote("Ana walks in, says \"hi\", waves", forKeyframe: first)
            var look = CaptureLook(format: .scope)
            look.depthOfField = DepthOfField(fStop: 2)
            app.photos.add(solidImage(), lens: CaptureLens(40), keyframe: first, lighting: .goldenHour, look: look)
            app.addKeyframe()

            let csv = ExportController.shotListCSV(
                keyframes: app.animator.timeline.keyframes, photos: app.photos,
                objectNames: Dictionary(uniqueKeysWithValues: app.objects.map { ($0.id, $0.name) }),
                characterIDs: Set(app.characters.map(\.id)))
            let lines = csv.components(separatedBy: "\r\n").filter { !$0.isEmpty }
            #expect(lines.count == 3)
            #expect(lines[0].hasPrefix("Shot,Time (s),Shot Type,Notes,Lens,Aperture,Frame"))
            #expect(lines[1].contains(#""Ana walks in, says ""hi"", waves""#))      // quoted, quotes doubled
            #expect(lines[1].contains("40 mm,f/2,Scope 2.39:1"))
            #expect(lines[1].contains(",Ana,Car,Yes"))
            #expect(lines[2].hasSuffix(",No"))

            app.exportShotList()
            let file = try #require(app.exports.exportedFile)
            #expect(file.url.pathExtension == "csv")
            #expect(try String(contentsOf: file.url, encoding: .utf8).contains("Ana walks in"))
        }

        @Test func captionsAndTheSheetShowTheCameraSettings() async throws {
            let app = AppModel()
            await app.createProject()
            app.addKeyframe()
            var look = CaptureLook(format: .vertical)
            look.depthOfField = DepthOfField(fStop: 5.6)
            let photo = try #require(app.photos.add(solidImage(), lens: .portrait, keyframe: app.animator.selectedKeyframeID,
                                                     look: look))
            #expect(photo.cameraDetails == "85 mm · f/5.6 · 9:16")
            #expect(SlideCaption.caption(number: 3, shotType: .closeUp, note: "", camera: photo.cameraDetails)
                    == "SHOT 03  ·  CU  ·  85 mm · f/5.6 · 9:16")
            app.exportStoryboardSheet()
            #expect(app.exports.exportedFile?.url.pathExtension == "pdf")
        }

        @Test func videoSizesMatchTheFrameShape() {
            func size(_ format: FrameFormat) -> [Int] { [format.videoSize.width, format.videoSize.height] }
            #expect(size(.widescreen) == [1920, 1080])
            #expect(size(.vertical) == [810, 1440])
            #expect(size(.square) == [1440, 1440])
            #expect(size(.academy) == [1920, 1440])
            #expect(size(.scope) == [1920, 804])
        }

        @Test func aSlideshowCutToTheFrameShapeIsAVerticalVideo() async throws {
            let app = AppModel()
            await app.createProject()
            let preference = app.exports.cropsToFrameShape
            app.exports.cropsToFrameShape = true
            defer { app.exports.cropsToFrameShape = preference }
            app.captureLook.format = .vertical
            app.addKeyframe()
            let context = CGContext(data: nil, width: 2560, height: 1440, bitsPerComponent: 8, bytesPerRow: 0,
                                    space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
            context.setFillColor(CGColor(gray: 0.5, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: 2560, height: 1440))
            app.photos.add(context.makeImage()!, lens: .normal, keyframe: app.animator.selectedKeyframeID,
                           look: CaptureLook(format: .vertical))

            await app.exportSlideshow()
            let url = try #require(app.exports.exportedFile?.url)
            let track = try #require(try await AVURLAsset(url: url).loadTracks(withMediaType: .video).first)
            let size = try await track.load(.naturalSize)
            #expect(Int(size.width) == 810 && Int(size.height) == 1440)

            // The picture inside the bars, at the photo's full resolution.
            let picture = ExportController.picture(of: context.makeImage()!, format: .vertical)
            #expect(picture.width == 810 && picture.height == 1440)
        }

        @Test func theCameraPreviewIsASmallRenderOfTheShot() async throws {
            let app = AppModel()
            await app.createProject(from: .streetCorner)
            await app.useBuiltInSky()
            app.captureLook.depthOfField = DepthOfField(fStop: 2.8)
            let preview = try #require(await app.renderCameraPreview())
            #expect(Int(preview.size.width) == CompositionRenderer.previewWidth)
            #expect(Int(preview.size.height) == CompositionRenderer.previewHeight)
            #expect(!app.isRenderingPreview)
        }
    }
}
