import SwiftMath
import SwiftUI

struct LatexText: View {
    let content: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(LatexParser.blocks(in: content).enumerated()), id: \.offset) { _, block in
                switch block {
                case .paragraph(let tokens):
                    InlineFlowLayout(spacing: 4) {
                        ForEach(Array(tokens.enumerated()), id: \.offset) { _, token in
                            switch token {
                            case .text(let text):
                                Text(text)
                                    .font(.body)
                            case .math(let equation):
                                MathFormula(equation: equation, style: .inline)
                            }
                        }
                    }
                case .displayMath(let equation):
                    MathFormula(equation: equation, style: .display)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 4)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
            let size = subview.sizeThatFits(.unspecified)
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
            Text("\\(\(equation)\\)")
                .font(style == .display ? .body.monospaced() : .callout.monospaced())
                .foregroundStyle(.secondary)
        }
    }

    private var minimumSize: CGSize {
        style == .display
            ? CGSize(width: 48, height: 28)
            : CGSize(width: 18, height: 21)
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
        label.setContentCompressionResistancePriority(.required, for: .vertical)
        return label
    }

    func updateUIView(_ label: MTMathUILabel, context: Context) {
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

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        uiView: MTMathUILabel,
        context: Context
    ) -> CGSize? {
        let maximumWidth = proposal.width.flatMap { $0.isFinite ? $0 : nil }
            ?? UIScreen.main.bounds.width - 80
        let measuredSize = uiView.sizeThatFits(
            CGSize(width: maximumWidth, height: .greatestFiniteMagnitude)
        )
        let minimumHeight: CGFloat = style == .display ? 28 : 21
        let minimumWidth: CGFloat = style == .display ? 48 : 18
        return CGSize(
            width: max(min(measuredSize.width, maximumWidth), minimumWidth),
            height: max(measuredSize.height, minimumHeight)
        )
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
    static func blocks(in content: String) -> [LatexBlock] {
        let pattern = #"\\\[([\s\S]*?)\\\]"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return [.paragraph(paragraphTokens(in: content))]
        }

        let range = NSRange(content.startIndex..., in: content)
        var blocks: [LatexBlock] = []
        var cursor = content.startIndex

        for match in regex.matches(in: content, range: range) {
            guard
                let fullRange = Range(match.range(at: 0), in: content),
                let equationRange = Range(match.range(at: 1), in: content)
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
        let pattern = #"\\\(([\s\S]*?)\\\)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return wordTokens(paragraph)
        }

        let range = NSRange(paragraph.startIndex..., in: paragraph)
        var tokens: [LatexToken] = []
        var cursor = paragraph.startIndex

        for match in regex.matches(in: paragraph, range: range) {
            guard
                let fullRange = Range(match.range(at: 0), in: paragraph),
                let equationRange = Range(match.range(at: 1), in: paragraph)
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
        text.split(whereSeparator: \.isWhitespace).map { .text(String($0)) }
    }
}
