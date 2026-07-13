import SwiftUI

enum DemoMode: String, CaseIterable, Identifiable {
    case legacy
    case adaptive

    var id: Self { self }
    var title: String { rawValue.capitalized }
    var color: Color { self == .legacy ? ResizeLabPalette.legacy : ResizeLabPalette.adaptive }
}

enum ResizeScenario: String, CaseIterable, Identifiable {
    case gallery
    case grid
    case orientation
    case window

    var id: Self { self }

    var title: String {
        switch self {
        case .gallery: "Gallery"
        case .grid: "Grid"
        case .orientation: "Orientation"
        case .window: "Window"
        }
    }

    var symbol: String {
        switch self {
        case .gallery: "rectangle.grid.2x2"
        case .grid: "square.grid.3x3"
        case .orientation: "rectangle.landscape.rotate"
        case .window: "macwindow"
        }
    }

    var ruleID: String {
        switch self {
        case .gallery: "RL001"
        case .grid: "RL006"
        case .orientation: "RL007"
        case .window: "RL004"
        }
    }

    var legacyExplanation: String {
        switch self {
        case .gallery: "Captures one screen-sized width and keeps it after the container changes."
        case .grid: "Chooses columns from phone versus tablet instead of available width."
        case .orientation: "Treats orientation as layout geometry, so square windows have no good answer."
        case .window: "Selects the first global scene instead of using this view's window."
        }
    }

    var adaptiveExplanation: String {
        switch self {
        case .gallery: "Recomputes item width from the current view bounds."
        case .grid: "Adds columns only when the current container has room."
        case .orientation: "Compares the actual width and height every layout pass."
        case .window: "Reads scene context from the current view hierarchy."
        }
    }
}

enum ResizeLabPalette {
    static let ink = Color(red: 0.03, green: 0.07, blue: 0.12)
    static let paper = Color(red: 0.97, green: 0.98, blue: 0.99)
    static let adaptive = Color(red: 0.12, green: 0.72, blue: 0.62)
    static let legacy = Color(red: 0.96, green: 0.48, blue: 0.28)
    static let signal = Color(red: 0.31, green: 0.63, blue: 0.96)
}
