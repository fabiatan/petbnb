import SwiftUI

struct BookingDetailView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    let summary: BookingSummary

    @State private var refreshed: BookingSummary?
    @State private var errorMessage: String?
    @State private var isCancelling = false
    @State private var goToPayment = false

    private var effective: BookingSummary { refreshed ?? summary }

    var body: some View {
        Form {
            Section {
                LabeledContent("Business", value: effective.businessName)
                LabeledContent("Kennel", value: effective.kennelName)
                LabeledContent("Status", value: effective.booking.status.label)
            }
            Section {
                LabeledContent("Check-in", value: effective.booking.check_in.formatted(date: .long, time: .omitted))
                LabeledContent("Check-out", value: effective.booking.check_out.formatted(date: .long, time: .omitted))
                LabeledContent("Nights", value: "\(effective.booking.nights)")
                LabeledContent("Subtotal", value: "RM \(String(format: "%.2f", effective.booking.subtotal_myr))")
            }
            if let notes = effective.booking.special_instructions, !notes.isEmpty {
                Section("Notes") { Text(notes) }
            }
            if let reason = effective.booking.cancellation_reason, !reason.isEmpty {
                Section("Cancellation reason") { Text(reason).font(.footnote).foregroundStyle(.secondary) }
            }

            if effective.booking.status == .accepted || effective.booking.status == .pending_payment {
                Section {
                    Button { goToPayment = true } label: {
                        HStack { Spacer(); Text("Pay now").fontWeight(.semibold); Spacer() }
                    }
                }
            }

            if effective.booking.status == .confirmed {
                Section {
                    Button(role: .destructive) {
                        Task { await cancel() }
                    } label: {
                        HStack {
                            Spacer()
                            if isCancelling { ProgressView() } else { Text("Cancel booking") }
                            Spacer()
                        }
                    }
                    .disabled(isCancelling)
                }
            }

            if let errorMessage {
                Section { Text(errorMessage).foregroundStyle(.red) }
            }
        }
        .navigationTitle("Booking")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $goToPayment) {
            PaymentStubView(summary: effective)
        }
        .refreshable { await refresh() }
        .task { await refresh() }
    }

    private func refresh() async {
        do {
            if let fresh = try await appState.bookingService.getBookingSummary(id: summary.booking.id) {
                refreshed = fresh
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func cancel() async {
        errorMessage = nil
        isCancelling = true
        defer { isCancelling = false }
        do {
            try await appState.bookingService.cancelBookingByOwner(bookingID: summary.booking.id)
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
