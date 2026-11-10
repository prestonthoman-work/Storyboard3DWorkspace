//
//  FilmFinisher.swift
//  Storyboard3DWorkspace
//

import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins

/// Finishes a raw render the way a colorist would: a filmic tone curve, a soft bloom on
/// highlights, a vignette, fine grain, and letterbox bars for the chosen format.
enum FilmFinisher {
    private static let context = CIContext(options: [.cacheIntermediates: false])

    static func finish(_ image: CGImage, look: CaptureLook, lighting: LightingPreset) -> CGImage {
        guard look.isFilmGraded || look.format != .widescreen else { return image }

        let source = CIImage(cgImage: image)
        let extent = source.extent
        var output = source

        if look.isFilmGraded {
            output = grade(output, lighting: lighting, extent: extent)
        }
        if look.format != .widescreen {
            output = letterbox(output, format: look.format, extent: extent)
        }

        let colorSpace = image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!
        return context.createCGImage(output, from: extent, format: .RGBA8, colorSpace: colorSpace) ?? image
    }

    // MARK: Grade

    private static func grade(_ input: CIImage, lighting: LightingPreset, extent: CGRect) -> CIImage {
        // Glow around bright areas, done in linear light like a real lens; stronger for
        // low sun and night lamps.
        let bloom = CIFilter.bloom()
        bloom.inputImage = input
        bloom.radius = Float(extent.height) * 0.01
        bloom.intensity = lighting.bloomIntensity
        var image = (bloom.outputImage ?? input).cropped(to: extent)

        // Core Image works in linear light, but the curve and grain are designed for how
        // tones look, so apply them in sRGB-encoded values and convert back afterward.
        image = image.applyingFilter("CILinearToSRGBToneCurve")

        // Gentle filmic S-curve: lifted blacks, a touch more midtone contrast, and
        // highlights that roll off instead of clipping. Midtones stay put.
        let curve = CIFilter.toneCurve()
        curve.inputImage = image
        curve.point0 = CGPoint(x: 0, y: 0.025)
        curve.point1 = CGPoint(x: 0.25, y: 0.225)
        curve.point2 = CGPoint(x: 0.5, y: 0.5)
        curve.point3 = CGPoint(x: 0.75, y: 0.77)
        curve.point4 = CGPoint(x: 1, y: 0.975)
        image = curve.outputImage ?? image

        let color = CIFilter.colorControls()
        color.inputImage = image
        color.saturation = 1.05
        image = color.outputImage ?? image

        let vignette = CIFilter.vignetteEffect()
        vignette.inputImage = image
        vignette.center = CGPoint(x: extent.midX, y: extent.midY)
        vignette.radius = Float(hypot(extent.width, extent.height)) * 0.42
        vignette.intensity = 0.38
        vignette.falloff = 0.65
        image = vignette.outputImage ?? image

        return addGrain(to: image, extent: extent).applyingFilter("CISRGBToneCurveToLinear")
    }

    /// Monochrome noise blended in with soft light, so it reads as film grain rather
    /// than colored digital noise.
    private static func addGrain(to image: CIImage, extent: CGRect) -> CIImage {
        guard let noise = CIFilter.randomGenerator().outputImage else { return image }

        let mono = CIFilter.colorMatrix()
        mono.inputImage = noise.cropped(to: extent)
        // Average the channels, then squash the range to a faint ±2.5% around mid-gray.
        let amount: CGFloat = 0.05 / 3
        let channel = CIVector(x: amount, y: amount, z: amount, w: 0)
        mono.rVector = channel
        mono.gVector = channel
        mono.bVector = channel
        mono.aVector = CIVector(x: 0, y: 0, z: 0, w: 0)
        mono.biasVector = CIVector(x: 0.475, y: 0.475, z: 0.475, w: 1)
        // The generator's raw values can spike well outside 0–1; clamp so no pixel sparkles.
        let clamp = CIFilter.colorClamp()
        clamp.inputImage = mono.outputImage
        clamp.minComponents = CIVector(x: 0.45, y: 0.45, z: 0.45, w: 1)
        clamp.maxComponents = CIVector(x: 0.55, y: 0.55, z: 0.55, w: 1)
        guard let grain = clamp.outputImage else { return image }

        let blend = CIFilter.softLightBlendMode()
        blend.inputImage = grain
        blend.backgroundImage = image
        return (blend.outputImage ?? image).cropped(to: extent)
    }

    // MARK: Letterbox

    private static func letterbox(_ input: CIImage, format: FrameFormat, extent: CGRect) -> CIImage {
        let barHeight = (extent.height * CGFloat(format.matteFraction)).rounded()
        guard barHeight > 0 else { return input }
        let black = CIImage(color: CIColor(red: 0, green: 0, blue: 0))
        let bottom = black.cropped(to: CGRect(x: extent.minX, y: extent.minY, width: extent.width, height: barHeight))
        let top = black.cropped(to: CGRect(x: extent.minX, y: extent.maxY - barHeight, width: extent.width, height: barHeight))
        return top.composited(over: bottom.composited(over: input))
    }
}

private extension LightingPreset {
    var bloomIntensity: Float {
        switch self {
        case .studio: 0.05
        case .goldenHour: 0.12
        case .overcast: 0.03
        case .night: 0.16
        }
    }
}
