//
//  FilmFinisherTests.swift
//  Storyboard3DWorkspaceTests
//

import CoreGraphics
import Testing
@testable import Storyboard3DWorkspace

struct FilmFinisherTests {
    private func gray(width: Int = 320, height: Int = 180) -> CGImage {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        context.setFillColor(gray: 0.6, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }

    /// Red channel of the pixel at (x, y), with y = 0 at the top.
    private func red(_ image: CGImage, x: Int, y: Int) -> UInt8 {
        let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                                bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let bytes = context.data!.assumingMemoryBound(to: UInt8.self)
        return bytes[(y * image.width + x) * 4]
    }

    @Test func plainLookLeavesTheRenderUntouched() {
        let image = gray()
        #expect(FilmFinisher.finish(image, look: .plain, lighting: .studio) === image)
    }

    @Test func scopeAddsBlackBarsAndKeepsTheFrameSize() {
        let look = CaptureLook(format: .scope, isFilmGraded: false)
        let finished = FilmFinisher.finish(gray(), look: look, lighting: .studio)
        #expect(finished.width == 320 && finished.height == 180)

        // 2.39:1 inside 16:9 leaves bars of about 12.8% of the height top and bottom.
        #expect(abs(FrameFormat.scope.matteFraction - 0.128) < 0.002)
        #expect(red(finished, x: 160, y: 5) == 0)
        #expect(red(finished, x: 160, y: 174) == 0)
        #expect(red(finished, x: 160, y: 90) > 100)
    }

    @Test func widescreenHasNoMatte() {
        #expect(FrameFormat.widescreen.matteFraction == 0)
    }

    @Test func filmGradeKeepsTheFrameSizeAndDarkensCorners() {
        let finished = FilmFinisher.finish(gray(), look: .standard, lighting: .goldenHour)
        #expect(finished.width == 320 && finished.height == 180)
        #expect(red(finished, x: 2, y: 2) < red(finished, x: 160, y: 90))
    }
}
