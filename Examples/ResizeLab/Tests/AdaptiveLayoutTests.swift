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
}
