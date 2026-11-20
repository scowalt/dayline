import Foundation

enum EventDescription {
    static func plainText(_ description: String) -> String? {
        let text = description.contains(#/(?i)<\/?(a|b|br|div|em|font|h[1-6]|i|li|ol|p|span|strong|u|ul)\b/#) ? stripHTML(description) : description
        let trimmed = text
            .replacing(#/\r\n/#, with: "\n")
            .replacing(#/[ \t]+\n/#, with: "\n")
            .replacing(#/\n{3,}/#, with: "\n\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func stripHTML(_ html: String) -> String {
        let text = html
            .replacing(#/(?i)<a\b[^>]*?href\s*=\s*"([^"]*)"[^>]*>(.*?)<\/a\s*>/#) { match in
                let href = String(match.output.1)
                let label = String(match.output.2).replacing(tag, with: "")
                return label.isEmpty || label == href ? href : "\(label) (\(href))"
            }
            .replacing(#/(?i)<br\s*\/?>/#, with: "\n")
            .replacing(#/(?i)<li\b[^>]*>/#, with: "\n• ")
            .replacing(#/(?i)<\/(p|div|ul|ol|h[1-6])\s*>/#, with: "\n")
            .replacing(tag, with: "")
        return text.replacing(#/&(#[0-9]+|#[xX][0-9A-Fa-f]+|[A-Za-z]+);/#) { match in
            entity(String(match.output.1)) ?? String(match.output.0)
        }
    }

    private static var tag: Regex<(Substring, Substring?)> {
        #/<\/?[A-Za-z][A-Za-z0-9]*(\s[^>]*)?\/?>/#
    }

    private static func entity(_ name: String) -> String? {
        switch name {
        case "amp": "&"
        case "lt": "<"
        case "gt": ">"
        case "quot": "\""
        case "apos": "'"
        case "nbsp": " "
        default: numericEntity(name)
        }
    }

    private static func numericEntity(_ name: String) -> String? {
        guard name.hasPrefix("#") else { return nil }
        let digits = name.dropFirst()
        let scalar = digits.first == "x" || digits.first == "X" ? UInt32(digits.dropFirst(), radix: 16) : UInt32(digits)
        return scalar.flatMap(Unicode.Scalar.init).map { String(Character($0)) }
    }
}
