import Testing
@testable import ResizeLintCore

@Test("A specific main-screen rule suppresses the generic rule on the same expression")
func specificRuleWins() async {
    let result = await analyzeSwift("let bounds = UIScreen.main.bounds")
    #expect(result.diagnostics.map(\.ruleID) == ["RL001"])
}

@Test("Broadcast iteration over every connected scene is not global current-window selection")
func connectedSceneBroadcastIsAllowed() async {
    let result = await analyzeSwift("UIApplication.shared.connectedScenes.forEach { scene in notify(scene) }")
    #expect(result.diagnostics.contains { $0.ruleID == "RL004" } == false)
}

@Test("Broadcast iteration over every global window is not current-window selection")
func globalWindowBroadcastIsAllowed() async {
    let result = await analyzeSwift("UIApplication.shared.windows.forEach { window in update(window) }")
    #expect(result.diagnostics.contains { $0.ruleID == "RL004" } == false)
}

@Test("A named collection of connected scenes can be iterated without selecting one")
func namedSceneCollectionBroadcastIsAllowed() async {
    let result = await analyzeSwift("""
    let windowScenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    for windowScene in windowScenes {
        update(windowScene)
    }
    """)
    #expect(result.diagnostics.contains { $0.ruleID == "RL004" } == false)
}

@Test("Collecting every connected-scene window for a broadcast is allowed")
func flattenedWindowCollectionIsAllowed() async {
    let result = await analyzeSwift("""
    func allWindows() -> [UIWindow] {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\\.windows)
    }
    """)
    #expect(result.diagnostics.contains { $0.ruleID == "RL004" } == false)
}

@Test("Device-capability idiom checks do not trigger the layout rule")
func nonLayoutIdiomCheckIsAllowed() async {
    let result = await analyzeSwift("let supportsPencilCapability = UIDevice.current.userInterfaceIdiom == .pad")
    #expect(result.diagnostics.contains { $0.ruleID == "RL006" } == false)
}

@Test("Device identity used for protocol metadata is not a layout decision")
func userAgentIdiomCheckIsAllowed() async {
    let result = await analyzeSwift("if UIDevice.current.userInterfaceIdiom == .pad { osName = \"OS\" }")
    #expect(result.diagnostics.contains { $0.ruleID == "RL006" } == false)
}

@Test("Idiom-based presentation style remains a layout diagnostic")
func idiomPresentationStyleIsReported() async {
    let result = await analyzeSwift(
        "let alertStyle: UIAlertController.Style = UIDevice.current.userInterfaceIdiom == .pad ? .alert : .actionSheet"
    )
    #expect(result.diagnostics.contains { $0.ruleID == "RL006" })
}

@Test("Selecting web-preview content for a tablet is not an app layout decision")
func previewContentIdiomCheckIsAllowed() async {
    let result = await analyzeSwift(
        "let previewDevice = UIDevice.current.userInterfaceIdiom == .pad ? PreviewDevice.tablet : .mobile"
    )
    #expect(result.diagnostics.contains { $0.ruleID == "RL006" } == false)
}

@Test("Orientation passed to a camera API does not trigger the layout rule")
func cameraOrientationIsAllowed() async {
    let result = await analyzeSwift("captureConnection.videoOrientation = windowScene.interfaceOrientation")
    #expect(result.diagnostics.contains { $0.ruleID == "RL007" } == false)
}

@Test("An interface-orientation parameter declaration is not a layout decision")
func orientationParameterDeclarationIsAllowed() async {
    let result = await analyzeSwift("""
    protocol Orientable {
        func layout(forInterfaceOrientation interfaceOrientation: UIInterfaceOrientation)
    }
    """)
    #expect(result.diagnostics.contains { $0.ruleID == "RL007" } == false)
}

@Test("Malformed suppressions warn and do not hide findings")
func malformedSuppressionDoesNotHideFinding() async {
    let result = await analyzeSwift("""
    // resizelint:disable-next-line RL001 --
    let bounds = UIScreen.main.bounds
    """)
    #expect(result.diagnostics.contains { $0.ruleID == "RL001" && !$0.isSuppressed })
    #expect(result.notices.contains { $0.kind == .malformedSuppression })
}

@Test("Suppressions with unknown rule IDs are malformed")
func unknownSuppressionRuleIsMalformed() async {
    let result = await analyzeSwift("""
    // resizelint:disable-next-line RL999 -- This rule does not exist.
    let bounds = UIScreen.main.bounds
    """)
    #expect(result.diagnostics.contains { $0.ruleID == "RL001" && !$0.isSuppressed })
    #expect(result.notices.contains { $0.kind == .malformedSuppression })
}

@Test("File suppressions after a declaration are malformed")
func lateFileSuppressionDoesNotHideFinding() async {
    let result = await analyzeSwift("""
    let marker = true
    // resizelint:disable-file RL001 -- Too late to suppress this file.
    let bounds = UIScreen.main.bounds
    """)
    #expect(result.diagnostics.contains { $0.ruleID == "RL001" && !$0.isSuppressed })
    #expect(result.notices.contains { $0.kind == .malformedSuppression })
}

@Test("Legacy lifecycle is not diagnosed without an unambiguous app target")
func ambiguousLegacyLifecycleIsAuditOnly() async {
    let result = await ResizeAnalyzer().analyze(AnalysisRequest(files: [
        SourceInput(path: "AppDelegate.swift", contents: "final class AppDelegate: UIResponder, UIApplicationDelegate { var window: UIWindow? }"),
    ]))
    #expect(result.diagnostics.contains { $0.ruleID == "RL008" } == false)
    #expect(result.notices.contains { $0.kind == .ambiguousProject })
}

@Test("A scene manifest prevents the legacy lifecycle diagnostic")
func sceneManifestIsAdaptive() async {
    let result = await ResizeAnalyzer().analyze(AnalysisRequest(files: [
        SourceInput(path: "AppDelegate.swift", contents: "final class AppDelegate: UIResponder, UIApplicationDelegate { var window: UIWindow? }"),
        SourceInput(path: "Info.plist", contents: "<plist><dict><key>UIApplicationSceneManifest</key><dict/></dict></plist>"),
        SourceInput(path: "project.pbxproj", contents: "PRODUCT_TYPE = com.apple.product-type.application;"),
    ]))
    #expect(result.diagnostics.contains { $0.ruleID == "RL008" } == false)
}

@Test("Fullscreen settings in XML comments are ignored")
func plistCommentsAreIgnored() async {
    let result = await ResizeAnalyzer().analyze(AnalysisRequest(files: [
        SourceInput(path: "Info.plist", contents: "<!-- <key>UIRequiresFullScreen</key><true/> -->"),
    ]))
    #expect(result.diagnostics.contains { $0.ruleID == "RL009" } == false)
}

@Test("Malformed Swift produces an audit notice without crashing")
func malformedSwiftIsTolerated() async {
    let result = await analyzeSwift("func broken( { let bounds = UIScreen.main.bounds")
    #expect(result.notices.contains { $0.kind == .syntaxError })
    #expect(result.diagnostics.contains { $0.ruleID == "RL001" })
}

@Test("Columns are reported as UTF-8 byte columns")
func utf8Columns() async {
    let result = await analyzeSwift("let café = 1; let bounds = UIScreen.main.bounds")
    let diagnostic = result.diagnostics.first { $0.ruleID == "RL001" }
    #expect(diagnostic?.range.start.column == 29)
}

@Test("A generic variable named orientation is not a UIKit orientation decision")
func genericOrientationVariableIsAllowed() async {
    let result = await analyzeSwift("func layout(orientation: Int) { let width = orientation > 0 ? 320 : 640 }")
    #expect(result.diagnostics.contains { $0.ruleID == "RL007" } == false)
}

@Test("Suppression-like text inside a string is inert")
func suppressionTextInsideStringIsIgnored() async {
    let result = await analyzeSwift("""
    let example = "// resizelint:disable-next-line RL001 -- Documentation text."
    let bounds = UIScreen.main.bounds
    """)
    #expect(result.notices.contains { $0.kind == .malformedSuppression } == false)
    #expect(result.diagnostics.contains { $0.ruleID == "RL001" && !$0.isSuppressed })
}

private func analyzeSwift(_ source: String) async -> AnalysisResult {
    await ResizeAnalyzer().analyze(AnalysisRequest(files: [
        SourceInput(path: "Sources/Sample.swift", contents: source),
    ]))
}
