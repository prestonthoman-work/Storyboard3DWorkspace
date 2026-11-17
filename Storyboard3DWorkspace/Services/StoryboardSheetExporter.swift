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
        var shotType: ShotType?
        /// The photo's camera settings, such as "35 mm · f/2 · 2.39:1".
        var camera: String?
    }

    /// How many shots fit on a page.
    enum Layout: Int, CaseIterable, Identifiable {
        case two = 2
        case six = 6
        case twelve = 12

        var id: Int { rawValue }
        var label: String { "\(rawValue) per page" }

        fileprivate var columns: Int { self == .two ? 2 : self == .six ? 3 : 4 }
        fileprivate var rows: Int { self == .two ? 1 : self == .six ? 2 : 3 }
        fileprivate func captionHeight(includingNotes: Bool) -> CGFloat {
            includingNotes ? (self == .twelve ? 48 : 62) : 24
        }
    }

    private static let page = CGRect(x: 0, y: 0, width: 792, height: 612)
    private static let margin: CGFloat = 36
    private static let gutter: CGFloat = 18
    private static let headerHeight: CGFloat = 52

    /// - Parameter imageAspect: Width ÷ height of each panel's picture: 16:9, or the frame
    ///   shape when exports are cut to it.
    static func export(title: String, panels: [Panel], layout: Layout, includeNotes: Bool,
                       imageAspect: CGFloat = 16 / 9, to url: URL) throws {
        let perPage = layout.rawValue
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
                    draw(panel, in: cell(at: slot, layout: layout, includeNotes: includeNotes, imageAspect: imageAspect),
                         imageAspect: imageAspect, includeNotes: includeNotes, compact: layout == .twelve)
                }
            }
        }
    }

    private static func cell(at slot: Int, layout: Layout, includeNotes: Bool, imageAspect: CGFloat) -> CGRect {
        let width = (page.width - margin * 2 - gutter * CGFloat(layout.columns - 1)) / CGFloat(layout.columns)
        let imageHeight = imageSize(columnWidth: width, layout: layout, includeNotes: includeNotes, aspect: imageAspect).height
        let height = imageHeight + layout.captionHeight(includingNotes: includeNotes)
        let column = slot % layout.columns
        let row = slot / layout.columns
        return CGRect(x: margin + CGFloat(column) * (width + gutter),
                      y: margin + headerHeight + CGFloat(row) * (height + gutter),
                      width: width, height: height)
    }

    /// A panel's picture: as wide as its column, unless that makes the rows too tall for the
    /// page (tall frame shapes), in which case as tall as fits.
    private static func imageSize(columnWidth: CGFloat, layout: Layout, includeNotes: Bool, aspect: CGFloat) -> CGSize {
        let rowsHeight = page.height - margin * 2 - headerHeight - gutter * CGFloat(layout.rows - 1)
        let maxImageHeight = rowsHeight / CGFloat(layout.rows) - layout.captionHeight(includingNotes: includeNotes)
        let height = min(columnWidth / aspect, maxImageHeight)
        return CGSize(width: height * aspect, height: height)
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

    private static func draw(_ panel: Panel, in cell: CGRect, imageAspect: CGFloat, includeNotes: Bool, compact: Bool) {
        let imageHeight = min(cell.width / imageAspect, cell.height)
        let imageWidth = min(cell.width, imageHeight * imageAspect)
        let frame = CGRect(x: cell.minX + (cell.width - imageWidth) / 2, y: cell.minY,
                           width: imageWidth, height: imageWidth / imageAspect)
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

        let number = ("Shot \(panel.number)" + (panel.shotType.map { "  ·  \($0.abbreviation)" } ?? "")) as NSString
        number.draw(at: CGPoint(x: frame.minX, y: frame.maxY + 6), withAttributes: [
            .font: UIFont.systemFont(ofSize: compact ? 9 : 11, weight: .semibold), .foregroundColor: UIColor.black
        ])
        if let camera = panel.camera {
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.monospacedDigitSystemFont(ofSize: compact ? 8 : 9, weight: .regular),
                .foregroundColor: UIColor.darkGray
            ]
            let text = camera as NSString
            let size = text.size(withAttributes: attributes)
            text.draw(at: CGPoint(x: frame.maxX - size.width, y: frame.maxY + (compact ? 7 : 8)), withAttributes: attributes)
        }
        guard includeNotes else { return }

        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        let noteTop: CGFloat = compact ? 19 : 22
        let noteRect = CGRect(x: frame.minX, y: frame.maxY + noteTop, width: frame.width, height: cell.maxY - frame.maxY - noteTop)
        (panel.note as NSString).draw(with: noteRect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
                                      attributes: [.font: UIFont.systemFont(ofSize: compact ? 8 : 10),
                                                   .foregroundColor: UIColor.darkGray,
                                                   .paragraphStyle: paragraph],
                                      context: nil)
    }
}
