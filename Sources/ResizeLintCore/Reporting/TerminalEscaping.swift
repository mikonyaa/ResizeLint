import Foundation

public enum TerminalEscaping {
    public static func escape(_ value: String) -> String {
        var output = ""
        for scalar in value.unicodeScalars {
            switch scalar.value {
            case 0x0A: output += "\\n"
            case 0x0D: output += "\\r"
            case 0x09: output += "\\t"
            case 0x00...0x1F, 0x7F...0x9F:
                output += String(format: "\\u{%04X}", scalar.value)
            default:
                output.unicodeScalars.append(scalar)
            }
        }
        return output
    }
}
