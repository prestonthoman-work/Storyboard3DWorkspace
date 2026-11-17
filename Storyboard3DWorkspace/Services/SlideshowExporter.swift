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
    static let crossfadeSeconds = 0.5

    /// - Parameters:
    ///   - secondsPerSlide: How long each image is on screen, including its crossfade.
    ///   - crossfade: Whether images dissolve into each other or cut.
    ///   - size: The video's size; 16:9 unless exports are cut to the frame shape.
    static func export(_ slides: [CGImage], secondsPerSlide: Double, crossfade: Bool,
                       size: (width: Int, height: Int) = (width, height), to url: URL) async throws {
        guard !slides.isEmpty else { throw ExportError.noSlides }
        try? FileManager.default.removeItem(at: url)

        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: size.width,
            AVVideoHeightKey: size.height
        ])
        let attributes = CVPixelBufferCreationAttributes(
            pixelFormatType: CVPixelFormatType(rawValue: kCVPixelFormatType_32BGRA),
            size: CVImageSize(width: size.width, height: size.height)
        )
        // The receiver adds the input to the writer; its `append` waits until the
        // writer is ready, so no polling is needed.
        let receiver = writer.inputPixelBufferReceiver(for: input, pixelBufferAttributes: attributes)
        try writer.start()
        writer.startSession(atSourceTime: .zero)

        let holdFrames = Int(secondsPerSlide * Double(framesPerSecond))
        let fadeFrames = crossfade && slides.count > 1
            ? min(Int(crossfadeSeconds * Double(framesPerSecond)), holdFrames / 2)
            : 0
        var frameIndex: Int64 = 0

        func append(_ frame: CVReadOnlyPixelBuffer) async throws {
            try await receiver.append(frame, with: CMTime(value: frameIndex, timescale: framesPerSecond))
            frameIndex += 1
        }

        for (index, slide) in slides.enumerated() {
            let next = index + 1 < slides.count ? slides[index + 1] : nil

            // The still frame is drawn once and reused for every held frame.
            let still = try makeFrame(pool: receiver.pixelBufferPool, attributes: attributes, size: size) { context in
                draw(slide, in: context, size: size, alpha: 1)
            }
            for _ in 0..<(next == nil ? holdFrames : holdFrames - fadeFrames) {
                try await append(still)
            }

            if let next {
                for step in 0..<fadeFrames {
                    let progress = CGFloat(step + 1) / CGFloat(fadeFrames + 1)
                    let frame = try makeFrame(pool: receiver.pixelBufferPool, attributes: attributes, size: size) { context in
                        draw(slide, in: context, size: size, alpha: 1)
                        draw(next, in: context, size: size, alpha: progress)
                    }
                    try await append(frame)
                }
            }
        }

        receiver.finish()
        await writer.finishWriting()
        guard writer.status == .completed else { throw ExportError.writerFailed }
    }

    /// Draws one video frame into a fresh pixel buffer and hands it back read-only.
    static func makeFrame(pool: CVMutablePixelBuffer.Pool?,
                                  attributes: CVPixelBufferCreationAttributes,
                                  size: (width: Int, height: Int),
                                  draw: (CGContext) -> Void) throws -> CVReadOnlyPixelBuffer {
        let frame: CVMutablePixelBuffer
        if let pool {
            frame = try pool.makeMutablePixelBuffer()
        } else {
            frame = try CVMutablePixelBuffer(attributes)
        }

        let didDraw = frame.withUnsafeBuffer { buffer -> Bool in
            CVPixelBufferLockBaseAddress(buffer, [])
            defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
            guard let context = CGContext(
                data: CVPixelBufferGetBaseAddress(buffer),
                width: size.width, height: size.height, bitsPerComponent: 8,
                bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
            ) else { return false }

            context.setFillColor(CGColor(gray: 0, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: size.width, height: size.height))
            draw(context)
            return true
        }
        guard didDraw else { throw ExportError.writerFailed }
        return CVReadOnlyPixelBuffer(frame)
    }

    /// Draws `image` to fill the frame, cropping any excess.
    static func draw(_ image: CGImage, in context: CGContext, size: (width: Int, height: Int), alpha: CGFloat) {
        let frame = CGSize(width: size.width, height: size.height)
        let scale = max(frame.width / CGFloat(image.width), frame.height / CGFloat(image.height))
        let size = CGSize(width: CGFloat(image.width) * scale, height: CGFloat(image.height) * scale)
        let origin = CGPoint(x: (frame.width - size.width) / 2, y: (frame.height - size.height) / 2)
        context.setAlpha(alpha)
        context.draw(image, in: CGRect(origin: origin, size: size))
        context.setAlpha(1)
    }
}

/// Writes a video one frame at a time, for frames that are rendered as they're needed
/// (the animatic) instead of all held in memory first. Same size and codec as the slideshow.
final class VideoStreamWriter {
    let framesPerSecond: Int32
    private let writer: AVAssetWriter
    private let receiver: AVAssetWriterInput.PixelBufferReceiver
    private let attributes: CVPixelBufferCreationAttributes
    private let size: (width: Int, height: Int)
    private var frameIndex: Int64 = 0

    init(url: URL, framesPerSecond: Int32,
         size: (width: Int, height: Int) = (SlideshowExporter.width, SlideshowExporter.height)) throws {
        self.framesPerSecond = framesPerSecond
        self.size = size
        try? FileManager.default.removeItem(at: url)
        writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: size.width,
            AVVideoHeightKey: size.height
        ])
        attributes = CVPixelBufferCreationAttributes(
            pixelFormatType: CVPixelFormatType(rawValue: kCVPixelFormatType_32BGRA),
            size: CVImageSize(width: size.width, height: size.height)
        )
        receiver = writer.inputPixelBufferReceiver(for: input, pixelBufferAttributes: attributes)
        try writer.start()
        writer.startSession(atSourceTime: .zero)
    }

    /// Appends `image` for `count` frames.
    func append(_ image: CGImage, count: Int = 1) async throws {
        let size = size
        let frame = try SlideshowExporter.makeFrame(pool: receiver.pixelBufferPool, attributes: attributes, size: size) { context in
            SlideshowExporter.draw(image, in: context, size: size, alpha: 1)
        }
        for _ in 0..<max(count, 1) {
            try await receiver.append(frame, with: CMTime(value: frameIndex, timescale: framesPerSecond))
            frameIndex += 1
        }
    }

    func finish() async throws {
        receiver.finish()
        await writer.finishWriting()
        guard writer.status == .completed else { throw SlideshowExporter.ExportError.writerFailed }
    }

    /// Stops without a usable file.
    func cancel() {
        writer.cancelWriting()
    }
}
