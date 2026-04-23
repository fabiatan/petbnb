import Foundation

struct VaccinationCert: Identifiable, Codable, Equatable {
    let id: UUID
    let pet_id: UUID
    let file_url: String
    let vaccines_covered: [String]
    let issued_on: Date
    let expires_on: Date
    let verified_by_business_id: UUID?
    let created_at: Date?
}
