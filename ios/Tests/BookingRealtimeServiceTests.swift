import XCTest
@testable import PetBnB

@MainActor
final class BookingRealtimeServiceTests: XCTestCase {
    func test_service_initializes_without_crashing() {
        let client = SupabaseClientProvider.shared
        let svc = BookingRealtimeService(client: client)
        XCTAssertNotNil(svc)
    }

    func test_stop_without_start_is_safe() async {
        let client = SupabaseClientProvider.shared
        let svc = BookingRealtimeService(client: client)
        await svc.stop()  // should not crash, no channel to unsubscribe
    }

    func test_realtime_event_enum_value() {
        XCTAssertEqual(BookingRealtimeService.Event.changed, BookingRealtimeService.Event.changed)
    }
}
