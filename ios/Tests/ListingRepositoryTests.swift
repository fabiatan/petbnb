import XCTest
@testable import PetBnB

final class ListingRepositoryTests: XCTestCase {
    func test_search_criteria_validity() {
        let valid = SearchCriteria(
            city: "KL",
            checkIn: Date(),
            checkOut: Date().addingTimeInterval(86_400),
            petID: nil
        )
        XCTAssertTrue(valid.isValid)

        let noCity = SearchCriteria(
            city: "",
            checkIn: Date(),
            checkOut: Date().addingTimeInterval(86_400),
            petID: nil
        )
        XCTAssertFalse(noCity.isValid)

        let invertedDates = SearchCriteria(
            city: "KL",
            checkIn: Date().addingTimeInterval(86_400),
            checkOut: Date(),
            petID: nil
        )
        XCTAssertFalse(invertedDates.isValid)
    }

    func test_listing_cancellation_policy_raw() {
        XCTAssertEqual(Listing.CancellationPolicy.flexible.rawValue, "flexible")
        XCTAssertEqual(Listing.CancellationPolicy.moderate.rawValue, "moderate")
        XCTAssertEqual(Listing.CancellationPolicy.strict.rawValue, "strict")
    }

    func test_business_summary_codable_roundtrip() throws {
        let biz = BusinessSummary(
            id: UUID(),
            name: "Test",
            slug: "test",
            city: "KL",
            state: "WP",
            description: "desc",
            cover_photo_url: nil
        )
        let data = try JSONEncoder().encode(biz)
        let decoded = try JSONDecoder().decode(BusinessSummary.self, from: data)
        XCTAssertEqual(biz, decoded)
    }
}
