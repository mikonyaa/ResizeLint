import SwiftUI
import UIKit
import XCTest
@testable import ResizeLab

final class AdaptiveLayoutTests: XCTestCase {
    func testColumnsFollowAvailableWidth() {
        XCTAssertEqual(AdaptiveLayout.columns(for: 320), 2)
        XCTAssertEqual(AdaptiveLayout.columns(for: 700), 3)
        XCTAssertEqual(AdaptiveLayout.columns(for: 1_000), 4)
    }

    func testContentWidthNeverBecomesNegative() {
        XCTAssertEqual(AdaptiveLayout.contentWidth(containerWidth: 20, horizontalInsets: 24), 0)
        XCTAssertEqual(AdaptiveLayout.contentWidth(containerWidth: 400, horizontalInsets: 24), 352)
    }

    @MainActor
    func testContentViewRendersAtPreviewSizes() {
        let sizes: [(name: String, value: CGSize)] = [
            ("compact", CGSize(width: 320, height: 720)),
            ("square", CGSize(width: 700, height: 700)),
            ("wide", CGSize(width: 1_000, height: 700))
        ]

        for size in sizes {
            let controller = UIHostingController(rootView: ContentView())
            let window = UIWindow(frame: CGRect(origin: .zero, size: size.value))
            window.rootViewController = controller
            window.makeKeyAndVisible()
            controller.beginAppearanceTransition(true, animated: false)
            controller.endAppearanceTransition()
            controller.view.layoutIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.1))

            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            let renderer = UIGraphicsImageRenderer(size: size.value, format: format)
            let image = renderer.image { _ in
                controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
            }

            XCTAssertEqual(image.size, size.value)
            XCTAssertGreaterThan(image.pngData()?.count ?? 0, 10_000)
            let attachment = XCTAttachment(image: image)
            attachment.name = "preview-\(size.name)"
            attachment.lifetime = .keepAlways
            add(attachment)
            window.isHidden = true
        }
    }
}
