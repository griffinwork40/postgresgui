//
//  SyntaxHighlightedEditor.swift
//  Tarn
//
//  Created by ghazi on 11/29/25.
//

import SwiftUI
import AppKit

// MARK: - SQL Syntax Highlighter

/// Handles SQL syntax highlighting with regex-based pattern matching
private struct SQLSyntaxHighlighter {

    static let maxHighlightingLength = 50_000

    // Compiled regex patterns (created once)
    let patterns: Patterns

    struct Patterns {
        let keyword: NSRegularExpression
        let string: NSRegularExpression
        let number: NSRegularExpression
        let singleLineComment: NSRegularExpression
        let multiLineComment: NSRegularExpression
        let `operator`: NSRegularExpression
        let function: NSRegularExpression

        init() {
            do {
                // SQLite keywords — organized by category for maintainability
                // DML + DDL + clauses + expressions + types + transactions + SQLite-specific
                keyword = try NSRegularExpression(
                    pattern: """
                    \\b(SELECT|INSERT|UPDATE|DELETE|REPLACE|\
                    FROM|WHERE|JOIN|INNER|LEFT|RIGHT|FULL|OUTER|CROSS|NATURAL|ON|USING|\
                    AS|ORDER|BY|GROUP|HAVING|LIMIT|OFFSET|DISTINCT|ALL|\
                    UNION|INTERSECT|EXCEPT|\
                    CREATE|ALTER|DROP|TABLE|INDEX|VIEW|TRIGGER|VIRTUAL|TEMP|TEMPORARY|\
                    WITHOUT|ROWID|STRICT|IF|EXISTS|\
                    UNIQUE|PRIMARY|KEY|FOREIGN|REFERENCES|CHECK|DEFAULT|NOT|NULL|\
                    COLLATE|AUTOINCREMENT|CONSTRAINT|GENERATED|ALWAYS|STORED|\
                    CASE|WHEN|THEN|ELSE|END|CAST|COALESCE|NULLIF|\
                    AND|OR|IN|LIKE|GLOB|BETWEEN|IS|MATCH|REGEXP|ESCAPE|\
                    WITH|RECURSIVE|\
                    BEGIN|COMMIT|ROLLBACK|SAVEPOINT|RELEASE|TRANSACTION|\
                    DEFERRED|IMMEDIATE|EXCLUSIVE|\
                    PRAGMA|ATTACH|DETACH|EXPLAIN|QUERY|PLAN|VACUUM|REINDEX|ANALYZE|\
                    SET|INTO|VALUES|RETURNING|DO|NOTHING|CONFLICT|\
                    ABORT|FAIL|IGNORE|\
                    INTEGER|REAL|TEXT|BLOB|NUMERIC|TRUE|FALSE|\
                    OVER|PARTITION|ROWS|RANGE|GROUPS|UNBOUNDED|PRECEDING|FOLLOWING|\
                    CURRENT|ROW|EXCLUDE|TIES|OTHERS|NO|FILTER|\
                    INDEXED|TO|FOR|EACH|OF|RAISE|INSTEAD|BEFORE|AFTER|\
                    DEFERRABLE|INITIALLY|RESTRICT|CASCADE|ACTION)\\b
                    """.replacingOccurrences(of: "\n", with: ""),
                    options: [.caseInsensitive]
                )
                string = try NSRegularExpression(pattern: "'(?:[^'\\\\]|\\\\.)*'", options: [])
                number = try NSRegularExpression(pattern: "\\b\\d+\\.?\\d*\\b", options: [])
                singleLineComment = try NSRegularExpression(pattern: "--.*", options: [])
                multiLineComment = try NSRegularExpression(pattern: "/\\*[\\s\\S]*?\\*/", options: [.dotMatchesLineSeparators])
                // SQLite operators: || (concat), <<, >> (bitshift), standard comparison + arithmetic
                `operator` = try NSRegularExpression(pattern: "\\|\\||<=|>=|<>|!=|<<|>>|[=<>!+\\-*/%&|^~]", options: [])
                function = try NSRegularExpression(pattern: "\\b[A-Za-z_][A-Za-z0-9_]*\\s*\\(", options: [])
            } catch {
                fatalError("Failed to compile regex patterns: \(error)")
            }
        }
    }

    struct Colors {
        let keyword: NSColor
        let string: NSColor
        let number: NSColor
        let comment: NSColor
        let `operator`: NSColor
        let function: NSColor
        let `default`: NSColor

        init(isDark: Bool) {
            if isDark {
                keyword = .systemBlue
                string = .systemGreen
                number = .systemOrange
                comment = .systemGray
                `operator` = .systemPink
                function = .systemCyan
            } else {
                keyword = NSColor(red: 0.0, green: 0.0, blue: 0.8, alpha: 1.0)
                string = NSColor(red: 0.0, green: 0.6, blue: 0.0, alpha: 1.0)
                number = NSColor(red: 0.8, green: 0.4, blue: 0.0, alpha: 1.0)
                comment = NSColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1.0)
                `operator` = NSColor(red: 0.8, green: 0.0, blue: 0.4, alpha: 1.0)
                function = NSColor(red: 0.0, green: 0.5, blue: 0.8, alpha: 1.0)
            }
            `default` = .textColor
        }
    }

    init() {
        self.patterns = Patterns()
    }

    /// Apply syntax highlighting to text storage (incremental, for user typing)
    func highlightIncremental(_ textStorage: NSTextStorage, isDark: Bool) {
        let text = textStorage.string
        guard !text.isEmpty, text.count <= Self.maxHighlightingLength else { return }

        let colors = Colors(isDark: isDark)
        let fullRange = NSRange(location: 0, length: text.utf16.count)
        let font = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)

        textStorage.beginEditing()
        textStorage.addAttribute(.font, value: font, range: fullRange)
        textStorage.addAttribute(.foregroundColor, value: colors.default, range: fullRange)
        applyPatterns(to: text, colors: colors) { range, color in
            textStorage.addAttribute(.foregroundColor, value: color, range: range)
        }
        textStorage.endEditing()
    }

    /// Apply syntax highlighting and return attributed string (for external text updates)
    func highlight(_ text: String, isDark: Bool) -> NSAttributedString? {
        guard !text.isEmpty, text.count <= Self.maxHighlightingLength else { return nil }

        let colors = Colors(isDark: isDark)
        let attributed = NSMutableAttributedString(string: text)
        let fullRange = NSRange(location: 0, length: text.utf16.count)
        let font = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)

        attributed.addAttribute(.font, value: font, range: fullRange)
        attributed.addAttribute(.foregroundColor, value: colors.default, range: fullRange)
        applyPatterns(to: text, colors: colors) { range, color in
            attributed.addAttribute(.foregroundColor, value: color, range: range)
        }

        return attributed
    }

    /// Core pattern matching logic - shared between both highlighting methods
    private func applyPatterns(to text: String, colors: Colors, apply: (NSRange, NSColor) -> Void) {
        let fullRange = NSRange(location: 0, length: text.utf16.count)
        var protected = IndexSet()

        func isProtected(_ range: NSRange) -> Bool {
            range.length > 0 && protected.contains(integersIn: range.location..<(range.location + range.length))
        }

        func protect(_ range: NSRange) {
            if range.length > 0 {
                protected.insert(integersIn: range.location..<(range.location + range.length))
            }
        }

        // Order matters: comments > strings > numbers/keywords/functions/operators
        let orderedPatterns: [(NSRegularExpression, NSColor, Bool)] = [
            (patterns.multiLineComment, colors.comment, true),
            (patterns.singleLineComment, colors.comment, true),
            (patterns.string, colors.string, true),
            (patterns.number, colors.number, false),
            (patterns.keyword, colors.keyword, false),
            (patterns.function, colors.function, false),
            (patterns.operator, colors.operator, false),
        ]

        for (pattern, color, shouldProtect) in orderedPatterns {
            pattern.enumerateMatches(in: text, options: [], range: fullRange) { match, _, _ in
                guard let match = match else { return }
                var range = match.range

                // For functions, exclude the opening paren
                if pattern === patterns.function {
                    range = NSRange(location: range.location, length: range.length - 1)
                }

                if !isProtected(range) {
                    apply(range, color)
                    if shouldProtect { protect(range) }
                }
            }
        }
    }
}

// MARK: - Syntax Highlighted Editor

struct SyntaxHighlightedEditor: NSViewRepresentable {
    @Binding var text: String
    @Environment(\.colorScheme) var colorScheme

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        let textView = NSTextView()

        // Configure text view
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.isRichText = false
        textView.importsGraphics = false
        textView.font = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        textView.textContainerInset = NSSize(width: 4, height: 4)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]

        // Disable automatic text substitutions for code editing
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticTextCompletionEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false

        // Set up scroll view
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.documentView = textView

        // Line numbers
        scrollView.rulersVisible = true
        scrollView.hasVerticalRuler = true
        let lineNumberRuler = LineNumberRulerView(scrollView: scrollView, textView: textView)
        scrollView.verticalRulerView = lineNumberRuler

        // Set delegate and store references
        textView.delegate = context.coordinator
        context.coordinator.textView = textView
        context.coordinator.lineNumberRuler = lineNumberRuler

        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }

        let isDark = colorScheme == .dark
        let colorSchemeChanged = context.coordinator.lastIsDark != isDark
        context.coordinator.lastIsDark = isDark

        if textView.string != text && !context.coordinator.isUpdatingFromUserInput {
            let selectedRange = textView.selectedRange()
            textView.string = text
            textView.setSelectedRange(selectedRange)
            context.coordinator.applyHighlighting(to: textView, isDark: isDark)
            context.coordinator.lineNumberRuler?.needsDisplay = true
        } else if colorSchemeChanged {
            context.coordinator.applyHighlighting(to: textView, isDark: isDark)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        private let parent: SyntaxHighlightedEditor
        private let highlighter = SQLSyntaxHighlighter()
        private var highlightingWorkItem: DispatchWorkItem?

        weak var textView: NSTextView?
        weak var lineNumberRuler: LineNumberRulerView?
        var isUpdatingFromUserInput = false
        var lastIsDark = false

        init(parent: SyntaxHighlightedEditor) {
            self.parent = parent
            self.lastIsDark = parent.colorScheme == .dark
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = textView else { return }

            isUpdatingFromUserInput = true
            parent.text = textView.string
            lineNumberRuler?.needsDisplay = true

            // Debounce highlighting
            highlightingWorkItem?.cancel()
            let isDark = lastIsDark
            let workItem = DispatchWorkItem { [weak self] in
                guard let self, let textView = self.textView, let storage = textView.textStorage else { return }
                self.highlighter.highlightIncremental(storage, isDark: isDark)
                self.isUpdatingFromUserInput = false
            }
            highlightingWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: workItem)
        }

        func applyHighlighting(to textView: NSTextView, isDark: Bool) {
            guard let attributed = highlighter.highlight(textView.string, isDark: isDark),
                  let textStorage = textView.textStorage else { return }

            let selectedRange = textView.selectedRange()
            let wasFirstResponder = textView.window?.firstResponder === textView

            textStorage.beginEditing()
            textStorage.setAttributedString(attributed)
            textStorage.endEditing()

            // Restore selection
            let maxLocation = textView.string.utf16.count
            let validLocation = min(selectedRange.location, maxLocation)
            let validLength = min(selectedRange.length, maxLocation - validLocation)

            DispatchQueue.main.async {
                textView.setSelectedRange(NSRange(location: validLocation, length: validLength))
                if wasFirstResponder {
                    textView.window?.makeFirstResponder(textView)
                }
            }
        }
    }
}
