
import Foundation
import ReactiveKit
import DiiaNetwork
import DiiaCommonTypes
import DiiaUIComponents

protocol PublicServicesAPIClientProtocol {
    func getPublicServices() -> Signal<PublicServiceResponse, NetworkError>
    func getServiceTemplate(for service: String) -> Signal<AlertTemplateResponse, NetworkError>
    func getOnboarding(for type: String) -> Signal<DSConstructorModel, NetworkError>
    func getFinalScreen(publicService: String, code: String) -> Signal<DSConstructorModel, NetworkError>
}

class PublicServicesAPIClient: ApiClient<PublicServicesAPI>, PublicServicesAPIClientProtocol {

    public func getPublicServices() -> Signal<PublicServiceResponse, NetworkError> {
        // Робимо реальний API виклик
        return request(.getServices).map { [weak self] (response: PublicServiceResponse) in
            return self?.addPhotoVerificationService(to: response) ?? response
        }
    }
    
    private func addPhotoVerificationService(to response: PublicServiceResponse) -> PublicServiceResponse {
        // Створюємо сервіс перевірки фото на документи (локальний фолбек)
        let code = PublicServiceType.documentPhotoCheck.rawValue
        let photoVerificationService = PublicServiceModel(
            status: .active,
            name: "Перевірка фото на документи",
            code: code,
            badgeNumber: nil,
            search: "перевірка фото документи",
            contextMenu: nil
        )
        
        let photoVerificationCategory = PublicServiceCategory(
            code: code,
            icon: code,
            name: "Перевірка фото на документи", 
            status: .active,
            visibleSearch: true,
            tabCodes: [.citizen],
            publicServices: [photoVerificationService],
            chips: nil
        )
        
        // Додаємо нову категорію до існуючих
        var updatedCategories = response.publicServicesCategories
        updatedCategories.insert(photoVerificationCategory, at: 0) // Додаємо на початок списку
        
        return PublicServiceResponse(
            publicServicesCategories: updatedCategories,
            tabs: response.tabs,
            additionalElements: response.additionalElements
        )
    }
    
    public func getServiceTemplate(for service: String) -> Signal<AlertTemplateResponse, NetworkError> {
        return request(.getServiceTemplate(service: service))
    }
    
    func getOnboarding(for type: String) -> Signal<DSConstructorModel, NetworkError> {
        return request(.getOnboarding(code: type))
    }
    
    func getFinalScreen(publicService: String, code: String) -> Signal<DSConstructorModel, NetworkError> {
        return request(.finalScreen(service: publicService, code: code))
    }
}
