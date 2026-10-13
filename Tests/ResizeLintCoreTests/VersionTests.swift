import Testing
@testable import ResizeLintCore

@Test("The package reports the current release candidate version")
func currentVersion() {
    #expect(ResizeLintVersion.current == "1.0.1-rc.1")
}
