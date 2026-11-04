//
//  SlideshowExporter.swift
//  Storyboard3DWorkspace
//

import AVFoundation
import CoreGraphics
import CoreVideo

/// Writes a sequence of images to an MP4 slideshow: each image is held on screen, then
/// crossfades into the next.
nonisolated enum SlideshowExporter {
    enum ExportError: LocalizedError {
        case noSlides
        case writerFailed

        var errorDescription: String? {
            switch self {
            case .noSlides: "There are no primary photos to export."
            case .writerFailed: "The slideshow couldn't be written."
            }
        }
    }

    static let width = 1920
    static let height = 1080
    static let framesPerSecond: Int32 = 30
    static let secondsPerSlide = 2.0
    static let crossfadeSeconds = 0.5

    static func export(_ slides: [CGImage], to url: URL) async throws {
        guard !slides.isEmpty else { throw ExportError.noSlides }
        try? FileManager.default.removeItem(at: url)

        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height
        ])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height
        ])
        writer.add(input)
        guard writer.startWriting() else { throw ExportError.writerFailed }
        writer.startSession(atSourceTime: .zero)

        let holdFrames = Int(secondsPerSlide * Double(framesPerSecond))
        let fadeFrames = slides.count > 1 ? Int(crossfadeSeconds * Double(framesPerSecond)) : 0
        var frameIndex: Int64 = 0

        func append(_ buffer: CVPixelBuffer) async throws {
            while !input.isReadyForMoreMediaData {
                try await Task.sleep(for: .milliseconds(5))
            }
            let time = CMTime(value: frameIndex, timescale: framesPerSecond)
            guard adaptor.append(buffer, withPresentationTime: time) else { throw ExportError.writerFailed }
            frameIndex += 1
        }

        for (index, slide) in slides.enumerated() {
            let next = index + 1 < slides.count ? slides[index + 1] : nil

            // The still frame is drawn once and reused for every held frame.
            let still = try makeFrame(adaptor: adaptor) { context in
                draw(slide, in: context, alpha: 1)
            }
            for _ in 0..<(next == nil ? holdFrames : holdFrames - fadeFrames) {
                try await append(still)
            }

            if let next {
                for step in 0..<fadeFrames {
                    let progress = CGFloat(step + 1) / CGFloat(fadeFrames + 1)
                    let frame = try makeFrame(adaptor: adaptor) { context in
                        draw(slide, in: context, alpha: 1)
                        draw(next, in: context, alpha: progress)
                    }
                    try await append(frame)
                }
            }
        }

        input.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else { throw ExportError.writerFailed }
    }

    private static func makeFrame(adaptor: AVAssetWriterInputPixelBufferAdaptor,
                                  draw: (CGContext) -> Void) throws -> CVPixelBuffer {
        guard let pool = adaptor.pixelBufferPool else { throw ExportError.writerFailed }
        var buffer: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
        guard let buffer else { throw ExportError.writerFailed }

        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { throw ExportError.writerFailed }

        context.setFillColor(CGColor(gray: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        draw(context)
        return buffer
    }

    /// Draws `image` to fill the frame, cropping any excess.
    private static func draw(_ image: CGImage, in context: CGContext, alpha: CGFloat) {
        let frame = CGSize(width: width, height: height)
        let scale = max(frame.width / CGFloat(image.width), frame.height / CGFloat(image.height))
        let size = CGSize(width: CGFloat(image.width) * scale, height: CGFloat(image.height) * scale)
        let origin = CGPoint(x: (frame.width - size.width) / 2, y: (frame.height - size.height) / 2)
        context.setAlpha(alpha)
        context.draw(image, in: CGRect(origin: origin, size: size))
        context.setAlpha(1)
    }
}
