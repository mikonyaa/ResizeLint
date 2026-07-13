import XCTest

final class ResizeLabUITests: XCTestCase {
    @MainActor
    func testPrimaryComparisonFlow() throws {
        let app = XCUIApplication()
        app.launch()

        let modePicker = app.segmentedControls["mode-picker"]
        XCTAssertTrue(modePicker.waitForExistence(timeout: 5))
        XCTAssertTrue(app.otherElements["demo-surface"].exists)
        let windowScenario = app.buttons["scenario-window"]
        XCTAssertTrue(windowScenario.isHittable)
        XCTAssertTrue(app.windows.firstMatch.frame.contains(windowScenario.frame))
        XCTAssertTrue(app.staticTexts["finding-card"].label.hasPrefix("RL001"))
        addScreenshot(named: "01-legacy-gallery")

        modePicker.buttons["Adaptive"].tap()
        XCTAssertTrue(app.staticTexts["finding-card"].label.hasPrefix("PASS"))
        addScreenshot(named: "02-adaptive-gallery")

        app.buttons["scenario-grid"].tap()
        XCTAssertTrue(app.buttons["scenario-grid"].isSelected)
        addScreenshot(named: "03-adaptive-grid")
    }

    @MainActor
    func testLandscapeKeepsComparisonReachable() {
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.segmentedControls["mode-picker"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.otherElements["demo-surface"].exists)
        addScreenshot(named: "04-landscape")
        XCUIDevice.shared.orientation = .portrait
    }

    @MainActor
    func testControlsRemainReachableWithLargeText() throws {
        let app = XCUIApplication()
        app.launch()
        let adaptiveButton = app.buttons["mode-adaptive"]

        guard adaptiveButton.waitForExistence(timeout: 2) else {
            throw XCTSkip("Run with an accessibility content size to exercise the large-text layout")
        }

        for _ in 0..<6 where !adaptiveButton.isHittable {
            app.swipeUp()
        }

        XCTAssertTrue(adaptiveButton.isHittable)
        XCTAssertTrue(app.buttons["scenario-gallery"].exists)
        addScreenshot(named: "05-large-text-controls")
    }

    @MainActor
    private func addScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
