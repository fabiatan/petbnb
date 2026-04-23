import Foundation

/// Minimal business payload used by search results. City/state for display;
/// slug for deep-linking; cover_photo_url for the hero tile.
struct BusinessSummary: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    var name: String
    var slug: String
    var city: String
    var state: String
    var description: String?
    var cover_photo_url: String?
}

/// A kennel-type row surfaced on the listing detail page.
struct KennelTypeSummary: Identifiable, Codable, Equatable, Hashable {
    enum SpeciesAccepted: String, Codable, CaseIterable {
        case dog, cat, both
    }
    enum SizeRange: String, Codable, CaseIterable {
        case small, medium, large
    }

    let id: UUID
    var name: String
    var species_accepted: SpeciesAccepted
    var size_range: SizeRange
    var capacity: Int
    var base_price_myr: Double
    var peak_price_myr: Double
    var instant_book: Bool
    var description: String?
}

/// Full listing payload: the business joined with its listing row (description,
/// amenities, house rules, cancellation policy, photos) + the active kennels.
struct Listing: Equatable {
    let business: BusinessSummary
    let houseRules: String?
    let amenities: [String]
    let cancellationPolicy: CancellationPolicy
    let photoPaths: [String]
    let kennels: [KennelTypeSummary]

    enum CancellationPolicy: String, Codable {
        case flexible, moderate, strict
    }
}

/// Search criteria collected by DiscoverView.
struct SearchCriteria: Equatable {
    var city: String
    var checkIn: Date
    var checkOut: Date
    var petID: UUID?

    var isValid: Bool {
        !city.trimmingCharacters(in: .whitespaces).isEmpty
            && checkOut > checkIn
    }
}

/// Nav destination for the listing detail — carries both the business to show
/// and the search criteria so the booking flow can reuse dates/pet.
struct ListingDestination: Hashable {
    let business: BusinessSummary
    let criteria: SearchCriteria
}
