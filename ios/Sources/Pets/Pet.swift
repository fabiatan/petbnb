import Foundation

struct Pet: Identifiable, Codable, Equatable, Hashable {
    enum Species: String, Codable, CaseIterable {
        case dog
        case cat
    }

    let id: UUID
    var owner_id: UUID
    var name: String
    var species: Species
    var breed: String?
    var age_months: Int?
    var weight_kg: Double?
    var medical_notes: String?
    var avatar_url: String?
    let created_at: Date?
    var updated_at: Date?
}

struct NewPetInput {
    var name: String
    var species: Pet.Species
    var breed: String?
    var age_months: Int?
    var weight_kg: Double?
    var medical_notes: String?
}
