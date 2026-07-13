import Testing
@testable import ResizeLintCore

@Test("The package reports the 1.0 release version")
func currentVersion() {
    #expect(ResizeLintVersion.current == "1.0.0")
}
