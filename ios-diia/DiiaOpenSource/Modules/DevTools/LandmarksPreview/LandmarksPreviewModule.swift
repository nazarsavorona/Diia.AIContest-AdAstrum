import UIKit
import DiiaMVPModule

final class LandmarksPreviewModule: BaseModule {
    private let view: LandmarksPreviewViewController
    private let presenter: LandmarksPreviewPresenter

    init(loader: LandmarkSampleLoader = LandmarkSampleLoader()) {
        let viewController = LandmarksPreviewViewController()
        let presenter = LandmarksPreviewPresenter(view: viewController, loader: loader)
        self.view = viewController
        self.presenter = presenter
        viewController.presenter = presenter
    }

    func viewController() -> UIViewController {
        return view
    }
}
