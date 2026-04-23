import XCTest
@testable import PetBnB

final class PetBnBTests: XCTestCase {
    func test_pet_species_roundtrips_through_codable() throws {
        let pet = Pet(
            id: UUID(),
            owner_id: UUID(),
            name: "Mochi",
            species: .dog,
            breed: "Poodle",
            age_months: 24,
            weight_kg: 8.0,
            medical_notes: nil,
            avatar_url: nil,
            created_at: nil,
            updated_at: nil
        )
        let data = try JSONEncoder().encode(pet)
        let decoded = try JSONDecoder().decode(Pet.self, from: data)
        XCTAssertEqual(pet, decoded)
    }
}
