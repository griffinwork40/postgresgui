//
//  LineNumberRulerView.swift
//  Tarn
//
//  Created by ghazi on 11/29/25.
//

import AppKit

/// A ruler view that displays line numbers for a text view
class LineNumberRulerView: NSRulerView {
    weak var textView: NSTextView?

    // Cached line start offsets for O(log n) line number lookup
    private var lineStartOffsets: [Int] = [0]
    private var cachedTextHash: Int = 0

    // Cached drawing attributes - created once, reused for all draws
    private lazy var textAttributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular),
        .foregroundColor: NSColor.secondaryLabelColor
    ]

    // Cache digit width for right-alignment calculation (monospace so all digits same width)
    private lazy var digitWidth: CGFloat = {
        ("0" as NSString).size(withAttributes: textAttributes).width
    }()

    // Throttle scroll updates using CVDisplayLink timing
    private var lastDrawTime: CFTimeInterval = 0
    private let minDrawInterval: CFTimeInterval = 1.0 / 120.0  // Cap at 120fps

    init(scrollView: NSScrollView, textView: NSTextView) {
        self.textView = textView
        super.init(scrollView: scrollView, orientation: .verticalRuler)
        self.clientView = textView.enclosingScrollView?.documentView
        self.ruleThickness = 40

        // Observe scroll events to redraw line numbers during scrolling
        let contentView = scrollView.contentView
        contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(scrollViewBoundsDidChange),
            name: NSView.boundsDidChangeNotification,
            object: contentView
        )
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func scrollViewBoundsDidChange(_ notification: Notification) {
        // Throttle redraws to reduce CPU usage during fast scrolling
        let currentTime = CACurrentMediaTime()
        guard currentTime - lastDrawTime >= minDrawInterval else { return }
        lastDrawTime = currentTime
        needsDisplay = true
    }

    /// Rebuild line offset cache - O(n) but only when text changes
    private func rebuildLineCache(for text: String) {
        let textHash = text.hashValue
        guard textHash != cachedTextHash else { return }

        cachedTextHash = textHash
        lineStartOffsets = [0]

        // Build array of line start positions using UTF-16 for NSRange compatibility
        var index = text.startIndex
        var utf16Offset = 0
        while index < text.endIndex {
            let char = text[index]
            let charUTF16Length = String(char).utf16.count
            if char == "\n" {
                lineStartOffsets.append(utf16Offset + charUTF16Length)
            }
            utf16Offset += charUTF16Length
            index = text.index(after: index)
        }
    }

    /// Binary search to find line number at character offset - O(log m) where m = line count
    private func lineNumber(at characterOffset: Int) -> Int {
        var low = 0
        var high = lineStartOffsets.count - 1

        while low < high {
            let mid = (low + high + 1) / 2
            if lineStartOffsets[mid] <= characterOffset {
                low = mid
            } else {
                high = mid - 1
            }
        }

        return low + 1  // 1-indexed line numbers
    }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let textView = textView,
              let context = NSGraphicsContext.current?.cgContext else { return }

        // Background color
        NSColor.controlBackgroundColor.setFill()
        context.fill(bounds)

        // Draw separator line
        NSColor.tertiaryLabelColor.setStroke()
        context.setLineWidth(0.5)
        context.move(to: CGPoint(x: bounds.maxX - 0.5, y: bounds.minY))
        context.addLine(to: CGPoint(x: bounds.maxX - 0.5, y: bounds.maxY))
        context.strokePath()

        guard let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else { return }

        let text = textView.string

        // Handle empty text case
        if text.isEmpty {
            drawEmptyTextLineNumbers(layoutManager: layoutManager, textView: textView)
            return
        }

        // Get visible rect from scroll view
        let visibleRect = textView.enclosingScrollView?.contentView.bounds ?? .zero

        // Rebuild line cache if text changed - O(n) but only when needed
        rebuildLineCache(for: text)

        // Get visible glyph range - this is optimized by NSLayoutManager
        let visibleGlyphRange = layoutManager.glyphRange(forBoundingRect: visibleRect, in: textContainer)

        // Use enumerateLineFragments for efficient line iteration - O(visible lines)
        // This is much faster than manual glyph/character range calculations
        var drawnLineNumbers = Set<Int>()
        let containerInsetY = textView.textContainerInset.height
        let scrollOffsetY = visibleRect.minY
        let rightMargin = bounds.width - 8

        layoutManager.enumerateLineFragments(forGlyphRange: visibleGlyphRange) { [self] (lineRect, _, _, glyphRange, _) in
            // Get character index for this line fragment
            let charIndex = layoutManager.characterIndexForGlyph(at: glyphRange.location)

            // Use binary search to find line number - O(log m)
            let lineNum = self.lineNumber(at: charIndex)

            // Skip if we already drew this line number (handles wrapped lines)
            guard !drawnLineNumbers.contains(lineNum) else { return }
            drawnLineNumbers.insert(lineNum)

            // Calculate Y position
            let yPosition = lineRect.minY + containerInsetY - scrollOffsetY

            // Draw line number - calculate x position based on digit count
            let lineNumString = "\(lineNum)" as NSString
            let digitCount = CGFloat(lineNumString.length)
            let xPosition = rightMargin - (digitCount * self.digitWidth)

            lineNumString.draw(at: NSPoint(x: xPosition, y: yPosition), withAttributes: self.textAttributes)
        }

        // Draw one more line number after the last visible line
        if let lastLineNum = drawnLineNumbers.max() {
            let nextLineNum = lastLineNum + 1
            let font = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
            let lineHeight = layoutManager.defaultLineHeight(for: font)

            // Get the rect for the last visible line to calculate next position
            let lastCharIndex = lineStartOffsets[min(lastLineNum - 1, lineStartOffsets.count - 1)]
            let lastGlyphIndex = layoutManager.glyphIndexForCharacter(at: min(lastCharIndex, layoutManager.numberOfGlyphs > 0 ? layoutManager.numberOfGlyphs - 1 : 0))
            let lastLineRect = layoutManager.lineFragmentRect(forGlyphAt: lastGlyphIndex, effectiveRange: nil)

            let yPosition = lastLineRect.minY + lineHeight + containerInsetY - scrollOffsetY

            let nextLineNumString = "\(nextLineNum)" as NSString
            let digitCount = CGFloat(nextLineNumString.length)
            let xPosition = rightMargin - (digitCount * digitWidth)

            nextLineNumString.draw(at: NSPoint(x: xPosition, y: yPosition), withAttributes: textAttributes)
        }
    }

    // MARK: - Private Helpers

    private func drawEmptyTextLineNumbers(layoutManager: NSLayoutManager, textView: NSTextView) {
        let font = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        let lineHeight = layoutManager.defaultLineHeight(for: font)
        let xPosition = bounds.width - digitWidth - 8
        let baseY = textView.textContainerInset.height

        ("1" as NSString).draw(at: NSPoint(x: xPosition, y: baseY), withAttributes: textAttributes)
        ("2" as NSString).draw(at: NSPoint(x: xPosition, y: baseY + lineHeight), withAttributes: textAttributes)
    }
}
