import SwiftUI

struct MyBookingsView: View {
    @Environment(AppState.self) private var appState
    @State private var bookings: [BookingSummary] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    private var grouped: [(BookingStatus.Group, [BookingSummary])] {
        let all = bookings
        let sections: [BookingStatus.Group] = [.payNow, .awaitingResponse, .confirmed, .completed, .other]
        return sections.compactMap { group in
            let items = all.filter { $0.booking.status.group == group }
            return items.isEmpty ? nil : (group, items)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if bookings.isEmpty && !isLoading {
                    ContentUnavailableView(
                        "No bookings yet",
                        systemImage: "calendar",
                        description: Text("Your booking requests will show up here.")
                    )
                }
                ForEach(grouped, id: \.0) { (group, items) in
                    Section(group.label) {
                        ForEach(items) { item in
                            NavigationLink(value: item) {
                                BookingRow(summary: item)
                            }
                        }
                    }
                }
                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(.red) }
                }
            }
            .navigationTitle("Bookings")
            .navigationDestination(for: BookingSummary.self) { item in
                BookingDetailView(summary: item)
            }
            .overlay {
                if isLoading && bookings.isEmpty { ProgressView() }
            }
            .task {
                await reload()
                // Keep the subscription running while this view is on screen.
                let events = await appState.bookingRealtimeService.start()
                for await _ in events {
                    await reload()
                }
            }
            .refreshable { await reload() }
            .onDisappear {
                Task { await appState.bookingRealtimeService.stop() }
            }
        }
    }

    private func reload() async {
        isLoading = true
        defer { isLoading = false }
        do {
            bookings = try await appState.bookingService.listMyBookings()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private extension BookingStatus.Group {
    var label: String {
        switch self {
        case .awaitingResponse: "Awaiting response"
        case .payNow: "Pay now"
        case .confirmed: "Upcoming"
        case .completed: "Completed"
        case .other: "Other"
        }
    }
}

extension BookingSummary: Hashable {
    func hash(into hasher: inout Hasher) { hasher.combine(booking.id) }
    static func == (lhs: BookingSummary, rhs: BookingSummary) -> Bool {
        lhs.booking.id == rhs.booking.id
    }
}

private struct BookingRow: View {
    let summary: BookingSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(summary.businessName).font(.headline)
                Spacer()
                Text(summary.booking.status.label)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(tint)
            }
            Text("\(summary.kennelName) · \(summary.booking.nights) night\(summary.booking.nights == 1 ? "" : "s")")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("\(summary.booking.check_in.formatted(date: .abbreviated, time: .omitted)) → \(summary.booking.check_out.formatted(date: .abbreviated, time: .omitted))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private var tint: Color {
        switch summary.booking.status.group {
        case .payNow: .orange
        case .awaitingResponse: .blue
        case .confirmed: .green
        case .completed: .secondary
        case .other: .gray
        }
    }
}
