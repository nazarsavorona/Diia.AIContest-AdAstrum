import UIKit
import DiiaMVPModule

final class LiveCameraModule: BaseModule {
    private let view: LiveCameraViewController

    init() {
        view = LiveCameraViewController()
    }

    func viewController() -> UIViewController {
        return view
    }
}
