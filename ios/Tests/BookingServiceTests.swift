import XCTest
@testable import PetBnB

final class BookingServiceTests: XCTestCase {
    func test_booking_status_groups() {
        XCTAssertEqual(BookingStatus.requested.group, .awaitingResponse)
        XCTAssertEqual(BookingStatus.accepted.group, .payNow)
        XCTAssertEqual(BookingStatus.pending_payment.group, .payNow)
        XCTAssertEqual(BookingStatus.confirmed.group, .confirmed)
        XCTAssertEqual(BookingStatus.completed.group, .completed)
        XCTAssertEqual(BookingStatus.declined.group, .other)
        XCTAssertEqual(BookingStatus.expired.group, .other)
        XCTAssertEqual(BookingStatus.cancelled_by_owner.group, .other)
        XCTAssertEqual(BookingStatus.cancelled_by_business.group, .other)
    }

    func test_booking_status_labels_non_empty() {
        for status in BookingStatus.allCases {
            XCTAssertFalse(status.label.isEmpty, "Label missing for \(status.rawValue)")
        }
    }

    func test_booking_service_error_messages() {
        XCTAssertTrue((BookingServiceError.notAuthenticated.errorDescription ?? "").contains("Not signed in"))
        XCTAssertTrue((BookingServiceError.invalidInput("Pick at least one pet").errorDescription ?? "").contains("Pick"))
        XCTAssertTrue((BookingServiceError.rpcFailed("boom").errorDescription ?? "").contains("Server error"))
    }
}
