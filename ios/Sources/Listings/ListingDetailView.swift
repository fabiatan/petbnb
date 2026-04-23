import SwiftUI

struct ListingDetailView: View {
    @Environment(AppState.self) private var appState
    let business: BusinessSummary

    @State private var listing: Listing?
    @State private var selectedKennelID: UUID?
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                photoCarousel
                content
            }
            .padding(.vertical)
        }
        .navigationTitle(business.name)
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            if let kennel = selectedKennel {
                continueBar(for: kennel)
            }
        }
        .overlay {
            if isLoading && listing == nil { ProgressView() }
        }
        .task { await load() }
    }

    private var selectedKennel: KennelTypeSummary? {
        listing?.kennels.first { $0.id == selectedKennelID }
    }

    private var photoCarousel: some View {
        TabView {
            if let paths = listing?.photoPaths, !paths.isEmpty {
                ForEach(paths, id: \.self) { path in
                    photo(for: path)
                }
            } else {
                placeholderGradient
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .automatic))
        .frame(height: 260)
    }

    @ViewBuilder
    private func photo(for path: String) -> some View {
        if let url = appState.listingRepository.publicPhotoURL(for: path) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image): image.resizable().scaledToFill()
                default: placeholderGradient
                }
            }
            .clipped()
        } else {
            placeholderGradient
        }
    }

    private var placeholderGradient: some View {
        LinearGradient(
            colors: [Color(red: 0.99, green: 0.86, blue: 0.58), Color(red: 0.96, green: 0.61, blue: 0.15)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    @ViewBuilder
    private var content: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(business.name).font(.title2).fontWeight(.semibold)
            Text("\(business.city), \(business.state)").font(.subheadline).foregroundStyle(.secondary)

            if let desc = business.description, !desc.isEmpty {
                Text(desc)
            }

            if let amenities = listing?.amenities, !amenities.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Amenities").font(.subheadline).fontWeight(.semibold)
                    Text(amenities.joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let rules = listing?.houseRules, !rules.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("House rules").font(.subheadline).fontWeight(.semibold)
                    Text(rules).font(.footnote).foregroundStyle(.secondary)
                }
            }

            Divider().padding(.vertical, 4)

            Text("Choose a room").font(.headline)
            if let kennels = listing?.kennels, !kennels.isEmpty {
                ForEach(kennels) { kennel in
                    kennelRow(kennel)
                }
            } else if !isLoading {
                Text("No rooms available at the moment.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if let errorMessage {
                Text(errorMessage).foregroundStyle(.red)
            }
        }
        .padding(.horizontal)
    }

    private func kennelRow(_ kennel: KennelTypeSummary) -> some View {
        Button {
            selectedKennelID = kennel.id
        } label: {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(kennel.name).font(.subheadline).fontWeight(.semibold)
                    Text(kennel.species_accepted.rawValue.capitalized)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if kennel.instant_book {
                        Text("Instant book")
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .foregroundStyle(.green)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(String(format: "RM %.0f", kennel.base_price_myr))
                        .font(.subheadline).fontWeight(.semibold)
                    Text("/ night").font(.caption2).foregroundStyle(.secondary)
                }
            }
            .padding(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(selectedKennelID == kennel.id ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: selectedKennelID == kennel.id ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func continueBar(for kennel: KennelTypeSummary) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(kennel.name).font(.caption).foregroundStyle(.secondary)
                Text(String(format: "RM %.0f / night", kennel.base_price_myr))
                    .font(.subheadline).fontWeight(.semibold)
            }
            Spacer()
            NavigationLink {
                BookingPlaceholderView(
                    business: business,
                    kennel: kennel,
                    criteria: defaultCriteriaForContinue()
                )
            } label: {
                Text("Continue").fontWeight(.semibold).padding(.horizontal, 20).padding(.vertical, 10)
                    .background(Color.accentColor, in: Capsule())
                    .foregroundStyle(.white)
            }
        }
        .padding()
        .background(.ultraThinMaterial)
    }

    /// Placeholder criteria for the 2b Continue stub. 2c will thread through the
    /// real SearchCriteria from DiscoverView → ResultsView → this view.
    private func defaultCriteriaForContinue() -> SearchCriteria {
        let today = Date()
        let week = Calendar.current.date(byAdding: .day, value: 7, to: today) ?? today
        let weekPlusFive = Calendar.current.date(byAdding: .day, value: 5, to: week) ?? week
        return SearchCriteria(
            city: business.city,
            checkIn: week,
            checkOut: weekPlusFive,
            petID: nil
        )
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let detail = try await appState.listingRepository.detail(businessId: business.id)
            listing = detail
            selectedKennelID = detail.kennels.first?.id
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
