import Foundation
import DiiaCommonTypes

enum PublicServiceType: String, Codable, EnumDecodable, CaseIterable {
    static let defaultValue: PublicServiceType = .unknown
    
    case unknown
    case criminalRecordCertificate
    case documentPhotoCheck
    
    var endpoint: String {
        switch self {
        case .criminalRecordCertificate:
            return "criminal-cert"
        case .documentPhotoCheck:
            return "photo-check"
        default:
            return self.rawValue
        }
    }
}
