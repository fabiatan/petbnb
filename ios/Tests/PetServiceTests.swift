import XCTest
@testable import PetBnB

final class PetServiceTests: XCTestCase {
    func test_new_pet_input_defaults() {
        let input = NewPetInput(name: "Mochi", species: .dog, breed: nil, age_months: nil, weight_kg: nil, medical_notes: nil)
        XCTAssertEqual(input.name, "Mochi")
        XCTAssertNil(input.breed)
    }

    func test_pet_service_error_messages() {
        XCTAssertTrue((PetServiceError.notAuthenticated.errorDescription ?? "").contains("Not signed in"))
        XCTAssertTrue((PetServiceError.fetchFailed("boom").errorDescription ?? "").contains("boom"))
        XCTAssertTrue((PetServiceError.upload("oops").errorDescription ?? "").contains("Upload failed"))
    }
}
