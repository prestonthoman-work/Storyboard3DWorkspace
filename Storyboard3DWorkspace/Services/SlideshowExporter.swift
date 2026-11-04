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
    static func export(_ slides: [CGImage], secondsPerSlide: Double, crossfade: Bool, to url: URL) async throws {
        guard !slides.isEmpty else { throw ExportError.noSlides }
        try? FileManager.default.removeItem(at: url)

        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height
        ])
        let attributes = CVPixelBufferCreationAttributes(
            pixelFormatType: CVPixelFormatType(rawValue: kCVPixelFormatType_32BGRA),
            size: CVImageSize(width: width, height: height)
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
            let still = try makeFrame(pool: receiver.pixelBufferPool, attributes: attributes) { context in
                draw(slide, in: context, alpha: 1)
            }
            for _ in 0..<(next == nil ? holdFrames : holdFrames - fadeFrames) {
                try await append(still)
            }

            if let next {
                for step in 0..<fadeFrames {
                    let progress = CGFloat(step + 1) / CGFloat(fadeFrames + 1)
                    let frame = try makeFrame(pool: receiver.pixelBufferPool, attributes: attributes) { context in
                        draw(slide, in: context, alpha: 1)
                        draw(next, in: context, alpha: progress)
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
    private static func makeFrame(pool: CVMutablePixelBuffer.Pool?,
                                  attributes: CVPixelBufferCreationAttributes,
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
                width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
            ) else { return false }

            context.setFillColor(CGColor(gray: 0, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            draw(context)
            return true
        }
        guard didDraw else { throw ExportError.writerFailed }
        return CVReadOnlyPixelBuffer(frame)
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
