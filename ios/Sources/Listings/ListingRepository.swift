import Foundation
import Supabase

enum ListingRepositoryError: LocalizedError {
    case searchFailed(String)
    case detailFailed(String)
    case notFound

    var errorDescription: String? {
        switch self {
        case .searchFailed(let m): "Couldn't search listings: \(m)"
        case .detailFailed(let m): "Couldn't load listing: \(m)"
        case .notFound: "Listing not found."
        }
    }
}

@MainActor
final class ListingRepository {
    let client: SupabaseClient

    init(client: SupabaseClient) {
        self.client = client
    }

    /// Case-insensitive substring match on city; returns verified + active
    /// businesses that have at least one listing row. Availability is not
    /// considered here (Phase 2c runs the real check at booking-intent time).
    func search(criteria: SearchCriteria) async throws -> [BusinessSummary] {
        let cityPattern = "%\(criteria.city.trimmingCharacters(in: .whitespaces))%"
        do {
            let rows: [BusinessSummary] = try await client.from("businesses")
                .select("id, name, slug, city, state, description, cover_photo_url")
                .eq("kyc_status", value: "verified")
                .eq("status", value: "active")
                .ilike("city", pattern: cityPattern)
                .order("name", ascending: true)
                .execute()
                .value
            return rows
        } catch {
            throw ListingRepositoryError.searchFailed(error.localizedDescription)
        }
    }

    /// Load the full listing detail for a given business.
    func detail(businessId: UUID) async throws -> Listing {
        struct BusinessRow: Decodable {
            let id: UUID
            let name: String
            let slug: String
            let city: String
            let state: String
            let description: String?
            let cover_photo_url: String?
        }
        struct ListingRow: Decodable {
            let id: UUID
            let photos: [String]
            let amenities: [String]
            let house_rules: String?
            let cancellation_policy: String
        }

        do {
            let business: BusinessRow = try await client.from("businesses")
                .select("id, name, slug, city, state, description, cover_photo_url")
                .eq("id", value: businessId.uuidString)
                .single()
                .execute()
                .value

            let listingRow: ListingRow = try await client.from("listings")
                .select("id, photos, amenities, house_rules, cancellation_policy")
                .eq("business_id", value: businessId.uuidString)
                .single()
                .execute()
                .value

            let kennels: [KennelTypeSummary] = try await client.from("kennel_types")
                .select("id, name, species_accepted, size_range, capacity, base_price_myr, peak_price_myr, instant_book, description")
                .eq("listing_id", value: listingRow.id.uuidString)
                .eq("active", value: true)
                .order("base_price_myr", ascending: true)
                .execute()
                .value

            let policy = Listing.CancellationPolicy(rawValue: listingRow.cancellation_policy) ?? .moderate
            return Listing(
                business: BusinessSummary(
                    id: business.id,
                    name: business.name,
                    slug: business.slug,
                    city: business.city,
                    state: business.state,
                    description: business.description,
                    cover_photo_url: business.cover_photo_url
                ),
                houseRules: listingRow.house_rules,
                amenities: listingRow.amenities,
                cancellationPolicy: policy,
                photoPaths: listingRow.photos,
                kennels: kennels
            )
        } catch {
            throw ListingRepositoryError.detailFailed(error.localizedDescription)
        }
    }

    /// Return the public URL for a listing-photos path. Sync call; the SDK
    /// just formats the URL, no network involved.
    func publicPhotoURL(for path: String) -> URL? {
        (try? client.storage.from("listing-photos").getPublicURL(path: path)) ?? nil
    }
}
