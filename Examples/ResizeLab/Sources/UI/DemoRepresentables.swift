import SwiftUI
import UIKit

@MainActor
struct LegacyDemoView: UIViewControllerRepresentable {
    let scenario: ResizeScenario

    func makeUIViewController(context: Context) -> LegacyGalleryViewController {
        LegacyGalleryViewController(scenario: scenario)
    }

    func updateUIViewController(_ controller: LegacyGalleryViewController, context: Context) {
        controller.setScenario(scenario)
    }
}

@MainActor
struct AdaptiveDemoView: UIViewControllerRepresentable {
    let scenario: ResizeScenario

    func makeUIViewController(context: Context) -> AdaptiveGalleryViewController {
        AdaptiveGalleryViewController(scenario: scenario)
    }

    func updateUIViewController(_ controller: AdaptiveGalleryViewController, context: Context) {
        controller.setScenario(scenario)
    }
}
