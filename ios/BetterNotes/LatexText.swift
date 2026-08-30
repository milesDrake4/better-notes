import SwiftMath
import SwiftUI

struct LatexText: View {
    let content: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(LatexParser.blocks(in: normalizedContent).enumerated()), id: \.offset) { _, block in
                switch block {
                case .paragraph(let tokens):
                    InlineFlowLayout(spacing: 4) {
                        ForEach(Array(tokens.enumerated()), id: \.offset) { _, token in
                            switch token {
                            case .text(let text):
                                Text(text)
                                    .font(.body)
                                    .fixedSize(horizontal: false, vertical: true)
                            case .math(let equation):
                                MathFormula(equation: equation, style: .inline)
                            }
                        }
                    }
                case .displayMath(let equation):
                    ScrollView(.horizontal, showsIndicators: false) {
                        MathFormula(equation: equation, style: .display)
                            .padding(.horizontal, 4)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var normalizedContent: String {
        LatexParser.replacingEscapedNewlines(in: content)
            .replacingOccurrences(of: #"\\("#, with: #"\("#)
            .replacingOccurrences(of: #"\\)"#, with: #"\)"#)
            .replacingOccurrences(of: #"\\["#, with: #"\["#)
            .replacingOccurrences(of: #"\\]"#, with: #"\]"#)
    }
}

private struct InlineFlowLayout: Layout {
    let spacing: CGFloat

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let width = proposal.width ?? .infinity
        let result = layout(subviews: subviews, width: width)
        return CGSize(width: width.isFinite ? width : result.width, height: result.height)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        let result = layout(subviews: subviews, width: bounds.width)
        for (index, point) in result.positions.enumerated() {
            let size = result.sizes[index]
            subviews[index].place(
                at: CGPoint(x: bounds.minX + point.x, y: bounds.minY + point.y),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: size.width, height: size.height)
            )
        }
    }

    private func layout(subviews: Subviews, width: CGFloat) -> LayoutResult {
        var positions: [CGPoint] = []
        var sizes: [CGSize] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0
        var usedWidth: CGFloat = 0

        for subview in subviews {
            let proposedWidth = width.isFinite ? width : nil
            let size = subview.sizeThatFits(ProposedViewSize(width: proposedWidth, height: nil))
            if x > 0, x + size.width > width {
                x = 0
                y += lineHeight + spacing
                lineHeight = 0
            }

            positions.append(CGPoint(x: x, y: y))
            sizes.append(size)
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
            usedWidth = max(usedWidth, x)
        }

        return LayoutResult(
            positions: positions,
            sizes: sizes,
            width: max(0, usedWidth - spacing),
            height: y + lineHeight
        )
    }

    private struct LayoutResult {
        let positions: [CGPoint]
        let sizes: [CGSize]
        let width: CGFloat
        let height: CGFloat
    }
}

private struct MathFormula: View {
    let equation: String
    let style: MathLabel.Style

    var body: some View {
        if MathLabel.canRender(equation) {
            MathLabel(equation: equation, style: style)
                .frame(minWidth: minimumSize.width, minHeight: minimumSize.height)
        } else {
            Text(readableFallback)
                .font(style == .display ? .body.monospaced() : .callout.monospaced())
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var minimumSize: CGSize {
        style == .display
            ? CGSize(width: 48, height: 28)
            : CGSize(width: 18, height: 21)
    }

    private var readableFallback: String {
        equation
            .replacingOccurrences(of: #"\\ne"#, with: "!=")
            .replacingOccurrences(of: #"\ne"#, with: "!=")
            .replacingOccurrences(of: #"\\neq"#, with: "!=")
            .replacingOccurrences(of: #"\neq"#, with: "!=")
            .replacingOccurrences(of: #"\\le"#, with: "<=")
            .replacingOccurrences(of: #"\le"#, with: "<=")
            .replacingOccurrences(of: #"\\ge"#, with: ">=")
            .replacingOccurrences(of: #"\ge"#, with: ">=")
    }
}

private struct MathLabel: UIViewRepresentable {
    enum Style {
        case inline
        case display
    }

    let equation: String
    let style: Style

    static func canRender(_ equation: String) -> Bool {
        var error: NSError?
        let mathList = MTMathListBuilder.build(fromString: equation, error: &error)
        return mathList != nil && error == nil
    }

    func makeUIView(context: Context) -> MTMathUILabel {
        let label = MTMathUILabel()
        label.backgroundColor = .clear
        label.displayErrorInline = true
        label.setContentHuggingPriority(.required, for: .horizontal)
        label.setContentHuggingPriority(.required, for: .vertical)
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
        label.setContentCompressionResistancePriority(.required, for: .vertical)
        return label
    }

    func updateUIView(_ label: MTMathUILabel, context: Context) {
        configure(label)
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        uiView: MTMathUILabel,
        context: Context
    ) -> CGSize? {
        configure(uiView)
        uiView.layoutIfNeeded()
        let measuredSize = uiView.intrinsicContentSize
        let minimumHeight: CGFloat = style == .display ? 28 : 21
        let minimumWidth: CGFloat = style == .display ? 48 : 18
        let horizontalPadding: CGFloat = style == .display ? 18 : 10
        let verticalPadding: CGFloat = style == .display ? 8 : 4
        let measuredWidth = measuredSize.width + horizontalPadding
        let measuredHeight = measuredSize.height + verticalPadding
        return CGSize(
            width: max(measuredWidth, minimumWidth),
            height: max(measuredHeight, minimumHeight)
        )
    }

    private func configure(_ label: MTMathUILabel) {
        let fontSize: CGFloat = style == .display ? 20 : 17
        let mathFont = MTFontManager().font(
            withName: MathFont.latinModernFont.rawValue,
            size: fontSize
        )

        label.latex = equation
        label.font = mathFont
        label.fontSize = fontSize
        label.labelMode = style == .display ? .display : .text
        label.textAlignment = style == .display ? .center : .left
        label.textColor = .label
        label.invalidateIntrinsicContentSize()
    }
}

private enum LatexBlock {
    case paragraph([LatexToken])
    case displayMath(String)
}

private enum LatexToken {
    case text(String)
    case math(String)
}

private enum LatexParser {
    static func replacingEscapedNewlines(in content: String) -> String {
        var result = ""
        var index = content.startIndex

        while index < content.endIndex {
            if content[index] == "\\" {
                let firstBackslash = index
                let secondIndex = content.index(after: firstBackslash)
                let hasSecondBackslash = secondIndex < content.endIndex && content[secondIndex] == "\\"
                let nIndex = hasSecondBackslash ? content.index(after: secondIndex) : secondIndex

                if nIndex < content.endIndex, content[nIndex] == "n" {
                    let afterN = content.index(after: nIndex)
                    let isLatexCommand = afterN < content.endIndex && content[afterN].isLowercase
                    if !isLatexCommand {
                        result.append("\n")
                        index = afterN
                        continue
                    }
                }
            }

            result.append(content[index])
            index = content.index(after: index)
        }

        return result
    }

    static func blocks(in content: String) -> [LatexBlock] {
        let pattern = #"\\\[([\s\S]*?)\\\]|\$\$([\s\S]*?)\$\$"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return [.paragraph(paragraphTokens(in: content))]
        }

        let range = NSRange(content.startIndex..., in: content)
        var blocks: [LatexBlock] = []
        var cursor = content.startIndex

        for match in regex.matches(in: content, range: range) {
            guard
                let fullRange = Range(match.range(at: 0), in: content),
                let equationRange = firstMatchedRange(in: content, match: match, groupIndexes: [1, 2])
            else {
                continue
            }

            appendParagraphs(String(content[cursor..<fullRange.lowerBound]), to: &blocks)
            blocks.append(.displayMath(String(content[equationRange])))
            cursor = fullRange.upperBound
        }

        appendParagraphs(String(content[cursor...]), to: &blocks)
        return blocks.isEmpty ? [.paragraph(paragraphTokens(in: content))] : blocks
    }

    private static func appendParagraphs(_ text: String, to blocks: inout [LatexBlock]) {
        let paragraphs = text.components(separatedBy: "\n")
        for paragraph in paragraphs {
            let trimmed = paragraph.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                blocks.append(.paragraph(paragraphTokens(in: trimmed)))
            }
        }
    }

    private static func paragraphTokens(in paragraph: String) -> [LatexToken] {
        let pattern = #"\\\(([\s\S]*?)\\\)|(?<!\$)\$([^\$\n]+?)\$(?!\$)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return wordTokens(paragraph)
        }

        let range = NSRange(paragraph.startIndex..., in: paragraph)
        var tokens: [LatexToken] = []
        var cursor = paragraph.startIndex

        for match in regex.matches(in: paragraph, range: range) {
            guard
                let fullRange = Range(match.range(at: 0), in: paragraph),
                let equationRange = firstMatchedRange(in: paragraph, match: match, groupIndexes: [1, 2])
            else {
                continue
            }

            tokens.append(contentsOf: wordTokens(String(paragraph[cursor..<fullRange.lowerBound])))
            tokens.append(.math(String(paragraph[equationRange])))
            cursor = fullRange.upperBound
        }

        tokens.append(contentsOf: wordTokens(String(paragraph[cursor...])))
        return tokens
    }

    private static func wordTokens(_ text: String) -> [LatexToken] {
        var tokens: [LatexToken] = []
        let pattern = #"\S+\s*"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return text.isEmpty ? [] : [.text(text)]
        }

        let range = NSRange(text.startIndex..., in: text)
        for match in regex.matches(in: text, range: range) {
            guard let tokenRange = Range(match.range(at: 0), in: text) else {
                continue
            }
            tokens.append(.text(String(text[tokenRange])))
        }

        return tokens
    }

    private static func firstMatchedRange(
        in text: String,
        match: NSTextCheckingResult,
        groupIndexes: [Int]
    ) -> Range<String.Index>? {
        for index in groupIndexes where index < match.numberOfRanges {
            let range = match.range(at: index)
            if range.location != NSNotFound,
               let swiftRange = Range(range, in: text) {
                return swiftRange
            }
        }
        return nil
    }
}
