import Foundation

/// Mirrors the Postgres enum from Phase 0 `001_enums.sql`.
enum BookingStatus: String, Codable, Equatable, CaseIterable {
    case requested
    case accepted
    case declined
    case pending_payment
    case expired
    case confirmed
    case completed
    case cancelled_by_owner
    case cancelled_by_business
}

extension BookingStatus {
    /// High-level grouping for the MyBookings list sections.
    enum Group: String, CaseIterable {
        case awaitingResponse
        case payNow
        case confirmed
        case completed
        case other
    }

    var group: Group {
        switch self {
        case .requested: .awaitingResponse
        case .accepted, .pending_payment: .payNow
        case .confirmed: .confirmed
        case .completed: .completed
        case .declined, .expired, .cancelled_by_owner, .cancelled_by_business: .other
        }
    }

    /// Short label for list rows and status pills.
    var label: String {
        switch self {
        case .requested: "Awaiting response"
        case .accepted: "Pay now"
        case .declined: "Declined"
        case .pending_payment: "Pay now"
        case .expired: "Expired"
        case .confirmed: "Confirmed"
        case .completed: "Completed"
        case .cancelled_by_owner: "Cancelled"
        case .cancelled_by_business: "Cancelled by sitter"
        }
    }
}

/// Full booking row as returned by the Phase 0 `bookings` table.
struct Booking: Identifiable, Codable, Equatable {
    let id: UUID
    let owner_id: UUID
    let business_id: UUID
    let listing_id: UUID
    let kennel_type_id: UUID
    let check_in: Date
    let check_out: Date
    let nights: Int
    let subtotal_myr: Double
    let platform_fee_myr: Double
    let business_payout_myr: Double
    let status: BookingStatus
    let requested_at: Date
    let acted_at: Date?
    let payment_deadline: Date?
    let special_instructions: String?
    let cancellation_reason: String?
    let ipay88_reference: String?
    let is_instant_book: Bool
    let created_at: Date?
    let updated_at: Date?
}

/// A flattened booking row with business + kennel names joined in for display.
struct BookingSummary: Identifiable, Equatable {
    let booking: Booking
    let businessName: String
    let kennelName: String

    var id: UUID { booking.id }
}
