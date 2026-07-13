import UIKit

@MainActor
final class AdaptiveGalleryViewController: GalleryBaseViewController {
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateLayout()
    }

    override func updateLayout() {
        let contentWidth = AdaptiveLayout.contentWidth(containerWidth: view.bounds.width, horizontalInsets: 14)
        let columns = AdaptiveLayout.columns(for: contentWidth)
        let localWindow = view.window
        let detail: String
        switch scenario {
        case .gallery: detail = "Tracks view bounds: \(Int(view.bounds.width)) pt"
        case .grid: detail = "\(columns) columns fit this container"
        case .orientation: detail = "Uses \(Int(view.bounds.width)) × \(Int(view.bounds.height)) pt"
        case .window: detail = localWindow == nil ? "Waiting for local window" : "Uses this view's window scene"
        }
        apply(columns: columns, contentWidth: contentWidth, note: detail)
    }
}
