import CI_Contract

extension CI.Workflow.YAML {
    /// Literal (`|`) and folded (`>`) block scalars, with the three
    /// chomping modes.
    ///
    /// Workflow documents carry `run: |` bodies on nearly every step, so
    /// this is not an optional corner. Comments are content inside a
    /// block scalar, which is why the reader keeps each line's raw text.
    enum BlockScalar {
        enum Indicator: Sendable, Equatable {
            case literal(Chomping)
            case folded(Chomping)

            /// Recognise a block-scalar header, or return `nil` when the
            /// value is an ordinary scalar. An explicit indentation
            /// indicator (`|2`) is not part of the recognised set.
            init?(_ value: String) {
                guard let style = value.first, style == "|" || style == ">" else { return nil }
                let chomping: Chomping
                switch value.dropFirst() {
                case "": chomping = .clip
                case "-": chomping = .strip
                case "+": chomping = .keep
                default: return nil
                }
                self = style == "|" ? .literal(chomping) : .folded(chomping)
            }

            var chomping: Chomping {
                switch self {
                case .literal(let chomping), .folded(let chomping): chomping
                }
            }
        }

        enum Chomping: Sendable, Equatable {
            case clip
            case strip
            case keep
        }

        /// Render the gathered body lines, stripping the block's own
        /// indentation — set by the first non-empty line.
        static func render(_ lines: [Line], indicator: Indicator) -> String {
            guard let first = lines.first(where: { !$0.isEmpty }) else { return "" }
            let margin = first.indent
            let bodies = lines.map { line -> String in
                let raw = line.raw
                guard raw.count > margin else { return "" }
                return String(raw.dropFirst(margin))
            }

            var text: String
            switch indicator {
            case .literal:
                text = bodies.joined(separator: "\n")
            case .folded:
                text = fold(bodies)
            }

            switch indicator.chomping {
            case .strip:
                while text.hasSuffix("\n") { text.removeLast() }
            case .clip:
                while text.hasSuffix("\n") { text.removeLast() }
                if !text.isEmpty { text.append("\n") }
            case .keep:
                text.append("\n")
            }
            return text
        }

        /// Folding joins consecutive non-empty, non-indented lines with a
        /// space; a blank line becomes a newline, and a more-indented
        /// line keeps its break.
        private static func fold(_ bodies: [String]) -> String {
            var result = ""
            var previousWasFoldable = false
            for body in bodies {
                let foldable = !body.isEmpty && !body.hasPrefix(" ")
                if result.isEmpty {
                    result = body
                } else if foldable, previousWasFoldable {
                    result.append(" ")
                    result.append(body)
                } else {
                    result.append("\n")
                    result.append(body)
                }
                previousWasFoldable = foldable
            }
            return result
        }
    }
}
