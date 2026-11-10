//
//  SlideCaption.swift
//  Storyboard3DWorkspace
//

import UIKit

/// Burns a storyboard caption ("SHOT 03 · WS · Car pulls in") into the lower left of a
/// frame, on a soft dark band so it reads over any photo.
enum SlideCaption {
    static func caption(number: Int, shotType: ShotType?, note: String) -> String {
        var parts = ["SHOT " + String(format: "%02d", number)]
        if let shotType { parts.append(shotType.abbreviation) }
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { parts.append(trimmed) }
        return parts.joined(separator: "  ·  ")
    }

    static func burn(_ text: String, into image: CGImage) -> CGImage {
        let size = CGSize(width: image.width, height: image.height)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let rendered = UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIImage(cgImage: image).draw(in: CGRect(origin: .zero, size: size))

            let bandHeight = size.height * 0.16
            let colors = [UIColor.black.withAlphaComponent(0).cgColor, UIColor.black.withAlphaComponent(0.6).cgColor]
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray,
                                         locations: [0, 1]) {
                context.cgContext.drawLinearGradient(gradient, start: CGPoint(x: 0, y: size.height - bandHeight),
                                                     end: CGPoint(x: 0, y: size.height), options: [])
            }

            let margin = size.height * 0.045
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineBreakMode = .byTruncatingTail
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: size.height * 0.032, weight: .semibold),
                .foregroundColor: UIColor.white,
                .kern: size.height * 0.0015,
                .paragraphStyle: paragraph,
            ]
            let line = size.height * 0.05
            (text as NSString).draw(with: CGRect(x: margin, y: size.height - margin - line,
                                                 width: size.width - margin * 2, height: line),
                                    options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
                                    attributes: attributes, context: nil)
        }
        return rendered.cgImage ?? image
    }
}
