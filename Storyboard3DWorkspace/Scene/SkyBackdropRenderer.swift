//
//  SkyBackdropRenderer.swift
//  Storyboard3DWorkspace
//

import CoreGraphics

/// Draws the built-in sky backdrop: a soft daytime gradient with a few hazy clouds.
nonisolated enum SkyBackdropRenderer {
    static func makeSkyImage(width: Int = 2048, height: Int = 1152) -> CGImage? {
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }

        let w = CGFloat(width)
        let h = CGFloat(height)

        // Core Graphics' origin is bottom-left: draw from the deep zenith down to a pale horizon.
        let skyColors = [
            CGColor(srgbRed: 0.24, green: 0.48, blue: 0.80, alpha: 1),
            CGColor(srgbRed: 0.52, green: 0.73, blue: 0.93, alpha: 1),
            CGColor(srgbRed: 0.88, green: 0.94, blue: 0.98, alpha: 1)
        ] as CFArray
        if let gradient = CGGradient(colorsSpace: colorSpace, colors: skyColors, locations: [0, 0.6, 1]) {
            context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: h), end: .zero, options: [])
        }

        // Gentle sun glow, upper right.
        drawGlow(in: context, colorSpace: colorSpace,
                 center: CGPoint(x: w * 0.8, y: h * 0.78), radius: h * 0.45, alpha: 0.35)

        // Cloud banks: clusters of soft white puffs, squashed vertically.
        var random = SeededRandom(seed: 11)
        let banks: [(x: CGFloat, y: CGFloat, size: CGFloat)] = [
            (0.16, 0.66, 1.0), (0.50, 0.50, 1.25), (0.84, 0.40, 0.9),
            (0.32, 0.30, 0.8), (0.70, 0.76, 0.65)
        ]
        for bank in banks {
            let baseRadius = h * 0.11 * bank.size
            for _ in 0..<8 {
                let center = CGPoint(
                    x: w * bank.x + CGFloat(random.next(in: -1.6...1.6)) * baseRadius,
                    y: h * bank.y + CGFloat(random.next(in: -0.25...0.25)) * baseRadius
                )
                let radius = baseRadius * CGFloat(random.next(in: 0.55...1.05))
                context.saveGState()
                context.translateBy(x: center.x, y: center.y)
                context.scaleBy(x: 1.6, y: 0.6)
                drawGlow(in: context, colorSpace: colorSpace, center: .zero, radius: radius,
                         alpha: CGFloat(random.next(in: 0.35...0.6)))
                context.restoreGState()
            }
        }

        return context.makeImage()
    }

    private static func drawGlow(in context: CGContext, colorSpace: CGColorSpace,
                                 center: CGPoint, radius: CGFloat, alpha: CGFloat) {
        let colors = [
            CGColor(srgbRed: 1, green: 1, blue: 1, alpha: alpha),
            CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0)
        ] as CFArray
        guard let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: [0, 1]) else { return }
        context.drawRadialGradient(gradient, startCenter: center, startRadius: 0,
                                   endCenter: center, endRadius: radius, options: [])
    }
}

/// Small deterministic generator so the sky looks the same on every launch.
private nonisolated struct SeededRandom {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next(in range: ClosedRange<Double>) -> Double {
        // SplitMix64
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        z ^= z >> 31
        let unit = Double(z >> 11) / Double(1 << 53)
        return range.lowerBound + unit * (range.upperBound - range.lowerBound)
    }
}
