//
//  StoryboardSheetExporter.swift
//  Storyboard3DWorkspace
//

import UIKit

/// Lays out keyframes as a printable storyboard: landscape US Letter pages with a grid
/// of numbered shot panels, each with its photo and notes.
enum StoryboardSheetExporter {
    struct Panel {
        let number: Int
        /// The keyframe's primary photo, or nil to draw an empty frame.
        let image: UIImage?
        let note: String
    }

    private static let page = CGRect(x: 0, y: 0, width: 792, height: 612)
    private static let margin: CGFloat = 36
    private static let columns = 3
    private static let rows = 2
    private static let gutter: CGFloat = 18
    private static let headerHeight: CGFloat = 52
    private static let captionHeight: CGFloat = 62

    static func export(title: String, panels: [Panel], to url: URL) throws {
        let perPage = columns * rows
        let pageCount = max(1, Int((Double(panels.count) / Double(perPage)).rounded(.up)))
        let date = Date.now.formatted(date: .abbreviated, time: .omitted)
        let shots = panels.count == 1 ? "1 shot" : "\(panels.count) shots"

        let renderer = UIGraphicsPDFRenderer(bounds: page)
        try renderer.writePDF(to: url) { context in
            for pageIndex in 0..<pageCount {
                context.beginPage()
                drawHeader(title: title, detail: "\(date) · \(shots)", page: pageIndex + 1, of: pageCount)
                let pagePanels = panels.dropFirst(pageIndex * perPage).prefix(perPage)
                for (slot, panel) in pagePanels.enumerated() {
                    draw(panel, in: cell(at: slot))
                }
            }
        }
    }

    private static func cell(at slot: Int) -> CGRect {
        let width = (page.width - margin * 2 - gutter * CGFloat(columns - 1)) / CGFloat(columns)
        let imageHeight = width * 9 / 16
        let height = imageHeight + captionHeight
        let column = slot % columns
        let row = slot / columns
        return CGRect(x: margin + CGFloat(column) * (width + gutter),
                      y: margin + headerHeight + CGFloat(row) * (height + gutter),
                      width: width, height: height)
    }

    private static func drawHeader(title: String, detail: String, page pageNumber: Int, of pageCount: Int) {
        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 20, weight: .semibold),
            .foregroundColor: UIColor.black
        ]
        let detailAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 10),
            .foregroundColor: UIColor.darkGray
        ]
        title.draw(at: CGPoint(x: margin, y: margin), withAttributes: titleAttributes)
        detail.draw(at: CGPoint(x: margin, y: margin + 27), withAttributes: detailAttributes)

        let pageLabel = "Page \(pageNumber) of \(pageCount)" as NSString
        let size = pageLabel.size(withAttributes: detailAttributes)
        pageLabel.draw(at: CGPoint(x: page.width - margin - size.width, y: margin + 27), withAttributes: detailAttributes)
    }

    private static func draw(_ panel: Panel, in cell: CGRect) {
        let frame = CGRect(x: cell.minX, y: cell.minY, width: cell.width, height: cell.width * 9 / 16)
        let context = UIGraphicsGetCurrentContext()

        if let image = panel.image {
            context?.saveGState()
            context?.clip(to: frame)
            // Fill the frame, cropping any excess.
            let scale = max(frame.width / image.size.width, frame.height / image.size.height)
            let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            image.draw(in: CGRect(x: frame.midX - size.width / 2, y: frame.midY - size.height / 2,
                                  width: size.width, height: size.height))
            context?.restoreGState()
        } else {
            UIColor(white: 0.94, alpha: 1).setFill()
            UIRectFill(frame)
            let empty = "No photo" as NSString
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 10), .foregroundColor: UIColor.gray
            ]
            let size = empty.size(withAttributes: attributes)
            empty.draw(at: CGPoint(x: frame.midX - size.width / 2, y: frame.midY - size.height / 2), withAttributes: attributes)
        }
        UIColor(white: 0.75, alpha: 1).setStroke()
        let border = UIBezierPath(rect: frame)
        border.lineWidth = 0.5
        border.stroke()

        let number = "Shot \(panel.number)" as NSString
        number.draw(at: CGPoint(x: frame.minX, y: frame.maxY + 6), withAttributes: [
            .font: UIFont.systemFont(ofSize: 11, weight: .semibold), .foregroundColor: UIColor.black
        ])

        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        let noteRect = CGRect(x: frame.minX, y: frame.maxY + 22, width: frame.width, height: captionHeight - 24)
        (panel.note as NSString).draw(with: noteRect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
                                      attributes: [.font: UIFont.systemFont(ofSize: 10),
                                                   .foregroundColor: UIColor.darkGray,
                                                   .paragraphStyle: paragraph],
                                      context: nil)
    }
}
