//
//  CaptureLook.swift
//  Storyboard3DWorkspace
//

import CoreGraphics
import Foundation

/// Frame shapes. Captures always render at 16:9 so every export stays the same size:
/// wider formats are letterboxed with black bars above and below, narrower ones are
/// pillarboxed with bars at the sides, as on a storyboard frame.
nonisolated enum FrameFormat: String, Codable, CaseIterable, Identifiable {
    case widescreen
    case flat
    case scope
    case academy
    case square
    case vertical

    var id: String { rawValue }

    var aspect: Float {
        switch self {
        case .widescreen: CaptureLens.aspect
        case .flat: 1.85
        case .scope: 2.39
        case .academy: 4.0 / 3
        case .square: 1
        case .vertical: 9.0 / 16
        }
    }

    var label: String {
        switch self {
        case .widescreen: "16:9"
        case .flat: "1.85:1"
        case .scope: "2.39:1"
        case .academy: "4:3"
        case .square: "1:1"
        case .vertical: "9:16"
        }
    }

    var name: String {
        switch self {
        case .widescreen: "Widescreen"
        case .flat: "Flat"
        case .scope: "Scope"
        case .academy: "Academy"
        case .square: "Square"
        case .vertical: "Vertical"
        }
    }

    /// The fraction of the 16:9 frame's height covered by each letterbox bar (top and bottom).
    var matteFraction: Float {
        max(0, (1 - CaptureLens.aspect / aspect) / 2)
    }

    /// The fraction of the 16:9 frame's width covered by each pillarbox bar (left and right).
    var pillarFraction: Float {
        max(0, (1 - aspect / CaptureLens.aspect) / 2)
    }

    /// The size photos are rendered at (`CompositionRenderer.outputWidth` × `outputHeight`).
    static let captureWidth = 2560
    static let captureHeight = 1440

    /// The picture inside the bars of a 16:9 frame `width` × `height` pixels, in whole pixels.
    func pictureRect(width: Int, height: Int) -> CGRect {
        let barWidth = (CGFloat(width) * CGFloat(pillarFraction)).rounded()
        let barHeight = (CGFloat(height) * CGFloat(matteFraction)).rounded()
        return CGRect(x: barWidth, y: barHeight, width: CGFloat(width) - 2 * barWidth, height: CGFloat(height) - 2 * barHeight)
    }

    /// The video size for exports cut to this shape: the picture inside a photo's bars, at
    /// most 1920 pixels on its long side, in even numbers (as video encoders need).
    var videoSize: (width: Int, height: Int) {
        let picture = pictureRect(width: Self.captureWidth, height: Self.captureHeight)
        let scale = min(1, 1920 / max(picture.width, picture.height))
        func even(_ value: CGFloat) -> Int { Int((value * scale / 2).rounded()) * 2 }
        return (even(picture.width), even(picture.height))
    }
}

/// Lens blur for captures: everything at the focus distance is sharp, and things blur the
/// further they are in front of or behind it, as with a real lens at that f-stop.
nonisolated struct DepthOfField: Codable, Equatable {
    /// The aperture as an f-number. Smaller numbers blur more.
    var fStop: Float = 2.8
    /// The object to focus on. Nil focuses on whatever is at the center of the frame.
    var focusObject: ObjectID?

    /// The usual full stops, from very shallow to nearly everything sharp.
    static let fStops: [Float] = [1.4, 2, 2.8, 4, 5.6, 8, 11, 16]

    static func label(for fStop: Float) -> String {
        "f/" + (fStop.rounded() == fStop ? String(Int(fStop)) : String(format: "%.1f", fStop))
    }

    var label: String { Self.label(for: fStop) }

    /// The lens opening's radius in meters. The capture camera stands where the viewer
    /// does, so this is the real lens's opening: focal length ÷ f-number.
    func apertureRadius(for lens: CaptureLens) -> Float {
        Float(lens.focalLength) / 1000 / fStop / 2
    }
}

/// How a capture is finished: its frame format, lens blur, and whether it gets a film
/// grade (tone curve, gentle bloom, vignette, and grain).
nonisolated struct CaptureLook: Codable, Equatable {
    var format: FrameFormat = .widescreen
    var isFilmGraded = true
    /// Nil keeps everything sharp. Optional so photos saved before it existed still load.
    var depthOfField: DepthOfField?

    /// New projects start with the film grade on.
    static let standard = CaptureLook()
    /// The plain render, for photos taken before looks existed.
    static let plain = CaptureLook(format: .widescreen, isFilmGraded: false)
}
