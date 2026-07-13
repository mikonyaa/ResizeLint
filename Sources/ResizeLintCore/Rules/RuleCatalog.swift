import Foundation

struct RuleMetadata: Sendable {
    let id: String
    let name: String
    let severity: Severity
    let message: String

    var helpURI: String {
        "https://github.com/mikonyaa/ResizeLint/blob/v1/Docs/Rules/\(id).md"
    }
}

enum RuleCatalog {
    static let all: [RuleMetadata] = [
        RuleMetadata(id: "RL001", name: "main-screen-bounds", severity: .error,
                     message: "UIScreen.main bounds do not describe the current scene's available space; use view bounds or scene-local geometry."),
        RuleMetadata(id: "RL002", name: "main-screen-scale", severity: .warning,
                     message: "Use traitCollection.displayScale or a scene-local screen instead of the main screen scale."),
        RuleMetadata(id: "RL003", name: "main-screen-reference", severity: .warning,
                     message: "Pass a scene-local screen or geometry context instead of using UIScreen.main."),
        RuleMetadata(id: "RL004", name: "global-window-access", severity: .error,
                     message: "Pass a window or scene-specific UI dependency instead of selecting a global window."),
        RuleMetadata(id: "RL005", name: "global-status-bar-geometry", severity: .error,
                     message: "Use scene-local status bar information and prefer the safe area for layout."),
        RuleMetadata(id: "RL006", name: "idiom-layout-decision", severity: .warning,
                     message: "Choose layout from size classes or the actual container size, not the device idiom."),
        RuleMetadata(id: "RL007", name: "orientation-layout-decision", severity: .warning,
                     message: "Choose layout from size classes and view bounds instead of interface orientation."),
        RuleMetadata(id: "RL008", name: "legacy-app-lifecycle", severity: .error,
                     message: "Adopt scene lifecycle so each resizable window owns its UI state."),
        RuleMetadata(id: "RL009", name: "fullscreen-requirement-review", severity: .info,
                     message: "Full-screen requirement enables discrete resizing on iOS 27; review rather than treating it as an opt-out."),
    ]

    static func metadata(for id: String) -> RuleMetadata {
        guard let metadata = all.first(where: { $0.id == id }) else {
            preconditionFailure("Unknown built-in rule \(id)")
        }
        return metadata
    }
}

public struct RuleDescriptor: Sendable {
    public let id: String
    public let name: String
    public let severity: Severity
    public let message: String
    public let helpURI: String
}

public enum ResizeLintRules {
    public static let all: [RuleDescriptor] = RuleCatalog.all.map {
        RuleDescriptor(id: $0.id, name: $0.name, severity: $0.severity, message: $0.message, helpURI: $0.helpURI)
    }
}
