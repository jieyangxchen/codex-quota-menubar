import AppKit
import CodexQuotaCore

final class StatusGridView: NSView {
    private let style = QuotaStatusGridStyle.default

    var columns: [QuotaDisplayColumn] = [] {
        didSet {
            invalidateIntrinsicContentSize()
            needsDisplay = true
        }
    }

    override var intrinsicContentSize: NSSize {
        NSSize(
            width: CGFloat(max(columns.count, 2) * style.columnWidth),
            height: CGFloat(style.itemHeight)
        )
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let activeColumns = columns.isEmpty
            ? [QuotaDisplayColumn(label: "Codex", value: "--")]
            : columns
        let columnWidth = bounds.width / CGFloat(activeColumns.count)
        let labelFont = NSFont.systemFont(ofSize: CGFloat(style.labelFontSize), weight: .regular)
        let valueFont = NSFont.monospacedDigitSystemFont(
            ofSize: CGFloat(style.valueFontSize),
            weight: .regular
        )
        let labelY = CGFloat(style.labelOriginY)
        let valueY = CGFloat(style.valueOriginY)

        for (index, column) in activeColumns.enumerated() {
            let rect = NSRect(
                x: CGFloat(index) * columnWidth,
                y: 0,
                width: columnWidth,
                height: bounds.height
            )
            draw(column.label, in: rect, y: labelY, font: labelFont)
            draw(QuotaFormatter.stableStatusValue(column.value), in: rect, y: valueY, font: valueFont)
        }
    }

    private func draw(
        _ text: String,
        in columnRect: NSRect,
        y: CGFloat,
        font: NSFont
    ) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.labelColor
        ]
        let attributed = NSAttributedString(string: text, attributes: attributes)
        let textSize = attributed.size()
        let x: CGFloat
        switch style.horizontalAlignment {
        case .leading:
            x = columnRect.minX + CGFloat(style.horizontalPadding)
        case .center:
            x = columnRect.midX - textSize.width / 2
        }
        let origin = NSPoint(
            x: x,
            y: y
        )
        attributed.draw(at: origin)
    }

}
