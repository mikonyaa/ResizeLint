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

@Test("Device-capability idiom checks do not trigger the layout rule")
func nonLayoutIdiomCheckIsAllowed() async {
    let result = await analyzeSwift("let supportsPencilCapability = UIDevice.current.userInterfaceIdiom == .pad")
    #expect(result.diagnostics.contains { $0.ruleID == "RL006" } == false)
}

@Test("Orientation passed to a camera API does not trigger the layout rule")
func cameraOrientationIsAllowed() async {
    let result = await analyzeSwift("captureConnection.videoOrientation = windowScene.interfaceOrientation")
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

private func analyzeSwift(_ source: String) async -> AnalysisResult {
    await ResizeAnalyzer().analyze(AnalysisRequest(files: [
        SourceInput(path: "Sources/Sample.swift", contents: source),
    ]))
}
