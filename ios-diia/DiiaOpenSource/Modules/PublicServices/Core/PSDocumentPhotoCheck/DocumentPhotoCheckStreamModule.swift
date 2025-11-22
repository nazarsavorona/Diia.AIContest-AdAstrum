import UIKit
import DiiaMVPModule

final class DocumentPhotoCheckStreamModule: BaseModule {
    private let view: DocumentPhotoCheckStreamViewController
    
    init() {
        view = DocumentPhotoCheckStreamViewController()
    }
    
    func viewController() -> UIViewController {
        return view
    }
}
