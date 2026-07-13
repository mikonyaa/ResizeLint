import UIKit

@MainActor
final class LegacyGalleryViewController: GalleryBaseViewController {
    private var capturedWidth: CGFloat = 0

    override func viewDidLoad() {
        super.viewDidLoad()
        capturedWidth = view.bounds.width
        updateLayout()
    }

    override func updateLayout() {
        let contentWidth = max(0, capturedWidth - 28)
        switch scenario {
        case .gallery:
            #if RESIZELINT_DOCUMENTATION
            let mainScreenWidth = UIScreen.main.bounds.width
            capturedWidth = mainScreenWidth
            #endif
            apply(columns: 2, contentWidth: contentWidth, note: "Captured once: \(Int(capturedWidth)) pt")
        case .grid:
            let columns = UIDevice.current.userInterfaceIdiom == .pad ? 4 : 2
            apply(columns: columns, contentWidth: contentWidth, note: "Columns selected from device idiom")
        case .orientation:
            let columns = view.window?.windowScene?.interfaceOrientation.isLandscape == true ? 4 : 2
            apply(columns: columns, contentWidth: contentWidth, note: "Columns selected from orientation")
        case .window:
            let selectedWindow = UIApplication.shared.connectedScenes.first
                .flatMap { ($0 as? UIWindowScene)?.windows.first }
            apply(columns: 2, contentWidth: contentWidth, note: selectedWindow == nil ? "No global window found" : "Selected first global scene")
        }
    }
}
