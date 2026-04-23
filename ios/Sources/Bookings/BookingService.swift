import Foundation
import Supabase

enum BookingServiceError: LocalizedError {
    case notAuthenticated
    case invalidInput(String)
    case rpcFailed(String)
    case fetchFailed(String)

    var errorDescription: String? {
        switch self {
        case .notAuthenticated: "Not signed in."
        case .invalidInput(let m): "Invalid input: \(m)"
        case .rpcFailed(let m): "Server error: \(m)"
        case .fetchFailed(let m): "Couldn't load: \(m)"
        }
    }
}

@MainActor
final class BookingService {
    let client: SupabaseClient

    init(client: SupabaseClient) {
        self.client = client
    }

    struct CreateBookingInput {
        let kennelTypeID: UUID
        let petIDs: [UUID]
        let checkIn: Date
        let checkOut: Date
        let specialInstructions: String?
        let isInstantBook: Bool
    }

    /// Route to the right Phase 0 RPC based on the kennel's `instant_book` flag.
    /// Returns the new booking id.
    func createBooking(_ input: CreateBookingInput) async throws -> UUID {
        guard !input.petIDs.isEmpty else {
            throw BookingServiceError.invalidInput("Pick at least one pet")
        }
        guard input.checkOut > input.checkIn else {
            throw BookingServiceError.invalidInput("Check-out must be after check-in")
        }

        let fn = input.isInstantBook ? "create_instant_booking" : "create_booking_request"
        let dateFmt = DateFormatter()
        dateFmt.dateFormat = "yyyy-MM-dd"
        dateFmt.timeZone = TimeZone(identifier: "UTC")
        let params: [String: AnyJSON] = [
            "p_kennel_type_id": .string(input.kennelTypeID.uuidString),
            "p_pet_ids": .array(input.petIDs.map { .string($0.uuidString) }),
            "p_check_in": .string(dateFmt.string(from: input.checkIn)),
            "p_check_out": .string(dateFmt.string(from: input.checkOut)),
            "p_special_instructions": input.specialInstructions.map { .string($0) } ?? .null,
        ]
        do {
            let id: UUID = try await client.rpc(fn, params: params).execute().value
            return id
        } catch {
            throw BookingServiceError.rpcFailed(error.localizedDescription)
        }
    }

    /// Ask Phase 0's `create_payment_intent` RPC for an iPay88 reference to use.
    /// Booking must already be `accepted` (request-to-book path) or
    /// `pending_payment` (instant-book path).
    func createPaymentIntent(bookingID: UUID) async throws -> String {
        let params: [String: AnyJSON] = [
            "p_booking_id": .string(bookingID.uuidString),
        ]
        do {
            let ref: String = try await client.rpc("create_payment_intent", params: params).execute().value
            return ref
        } catch {
            throw BookingServiceError.rpcFailed(error.localizedDescription)
        }
    }

    func cancelBookingByOwner(bookingID: UUID) async throws {
        let params: [String: AnyJSON] = [
            "p_booking_id": .string(bookingID.uuidString),
        ]
        do {
            _ = try await client.rpc("cancel_booking_by_owner", params: params).execute()
        } catch {
            throw BookingServiceError.rpcFailed(error.localizedDescription)
        }
    }

    /// Fetch the caller's bookings + join business + kennel names client-side.
    func listMyBookings() async throws -> [BookingSummary] {
        do {
            let bookings: [Booking] = try await client.from("bookings")
                .select()
                .order("check_in", ascending: false)
                .execute()
                .value

            guard !bookings.isEmpty else { return [] }

            let businessIDs = Set(bookings.map(\.business_id)).map(\.uuidString)
            let kennelIDs = Set(bookings.map(\.kennel_type_id)).map(\.uuidString)

            struct BizRow: Decodable { let id: UUID; let name: String }
            struct KennelRow: Decodable { let id: UUID; let name: String }

            async let businesses: [BizRow] = client.from("businesses")
                .select("id, name")
                .in("id", values: businessIDs)
                .execute()
                .value
            async let kennels: [KennelRow] = client.from("kennel_types")
                .select("id, name")
                .in("id", values: kennelIDs)
                .execute()
                .value

            let (bizList, kennelList) = try await (businesses, kennels)
            let bizByID = Dictionary(uniqueKeysWithValues: bizList.map { ($0.id, $0.name) })
            let kennelByID = Dictionary(uniqueKeysWithValues: kennelList.map { ($0.id, $0.name) })

            return bookings.map {
                BookingSummary(
                    booking: $0,
                    businessName: bizByID[$0.business_id] ?? "Unknown",
                    kennelName: kennelByID[$0.kennel_type_id] ?? "Unknown"
                )
            }
        } catch {
            throw BookingServiceError.fetchFailed(error.localizedDescription)
        }
    }

    func getBookingSummary(id: UUID) async throws -> BookingSummary? {
        let all = try await listMyBookings()
        return all.first { $0.id == id }
    }
}
