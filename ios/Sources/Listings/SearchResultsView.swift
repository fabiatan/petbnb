import SwiftUI

struct SearchResultsView: View {
    @Environment(AppState.self) private var appState
    let criteria: SearchCriteria

    @State private var results: [BusinessSummary] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    private var nights: Int {
        max(1, Calendar.current.dateComponents([.day], from: criteria.checkIn, to: criteria.checkOut).day ?? 1)
    }

    var body: some View {
        List {
            Section {
                if results.isEmpty && !isLoading {
                    ContentUnavailableView(
                        "No listings found",
                        systemImage: "magnifyingglass",
                        description: Text("Try a different city or dates.")
                    )
                }
                ForEach(results) { biz in
                    NavigationLink(value: ListingDestination(business: biz, criteria: criteria)) {
                        BusinessCardRow(business: biz)
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                Text("\(nights) night\(nights == 1 ? "" : "s") in \(criteria.city) · \(results.count) place\(results.count == 1 ? "" : "s")")
                    .textCase(nil)
            }
            if let errorMessage {
                Section { Text(errorMessage).foregroundStyle(.red) }
            }
        }
        .overlay {
            if isLoading && results.isEmpty { ProgressView() }
        }
        .navigationTitle("Results")
        .task { await search() }
    }

    private func search() async {
        isLoading = true
        defer { isLoading = false }
        do {
            results = try await appState.listingRepository.search(criteria: criteria)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct BusinessCardRow: View {
    let business: BusinessSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            heroImage
                .frame(height: 160)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 2) {
                Text(business.name)
                    .font(.headline)
                Text("\(business.city), \(business.state)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let desc = business.description, !desc.isEmpty {
                    Text(desc)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var heroImage: some View {
        if let urlString = business.cover_photo_url, let url = URL(string: urlString) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image): image.resizable().scaledToFill()
                default: placeholderGradient
                }
            }
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
}
