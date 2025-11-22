import Foundation
import DiiaCommonTypes
import DiiaMVPModule

struct PSDocumentPhotoCheckRoute: RouterProtocol {
    private let contextMenuItems: [ContextMenuItem]
    
    init(contextMenuItems: [ContextMenuItem]) {
        self.contextMenuItems = contextMenuItems
    }
    
    func route(in view: BaseView) {
        let baseCMP = BaseContextMenuProvider(publicService: .documentPhotoCheck, items: contextMenuItems)
        view.open(module: DocumentPhotoOnboardingModule(contextMenuProvider: baseCMP))
    }
}
