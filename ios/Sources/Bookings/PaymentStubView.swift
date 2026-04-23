import SwiftUI

struct PaymentStubView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    let summary: BookingSummary

    @State private var reference: String?
    @State private var isCreatingIntent = false
    @State private var errorMessage: String?
    @State private var refreshedBooking: Booking?

    private var effectiveBooking: Booking {
        refreshedBooking ?? summary.booking
    }

    var body: some View {
        Form {
            Section("Stay") {
                LabeledContent("Business", value: summary.businessName)
                LabeledContent("Kennel", value: summary.kennelName)
                LabeledContent("Dates", value: "\(summary.booking.check_in.formatted(date: .abbreviated, time: .omitted)) → \(summary.booking.check_out.formatted(date: .abbreviated, time: .omitted))")
                LabeledContent("Total", value: "RM \(String(format: "%.2f", summary.booking.subtotal_myr))")
            }

            Section {
                if let ref = reference ?? effectiveBooking.ipay88_reference {
                    LabeledContent("Reference", value: ref)
                    Text("iPay88 integration is stubbed for Phase 2c. To simulate a successful webhook, run:")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Text("psql \"postgresql://postgres:postgres@127.0.0.1:54322/postgres\" -c \"SELECT confirm_payment('\(ref)', \(String(format: "%.2f", summary.booking.subtotal_myr))::numeric);\"")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.primary)
                        .textSelection(.enabled)
                } else {
                    Button {
                        Task { await createIntent() }
                    } label: {
                        HStack {
                            Spacer()
                            if isCreatingIntent { ProgressView() } else { Text("Create payment intent").fontWeight(.semibold) }
                            Spacer()
                        }
                    }
                    .disabled(isCreatingIntent)
                }
            } header: { Text("Payment") }

            if let errorMessage {
                Section { Text(errorMessage).foregroundStyle(.red) }
            }

            Section {
                Button { Task { await refreshStatus() } } label: {
                    HStack { Spacer(); Text("Refresh status"); Spacer() }
                }
                LabeledContent("Status", value: effectiveBooking.status.label)
            }
        }
        .navigationTitle("Pay")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func createIntent() async {
        errorMessage = nil
        isCreatingIntent = true
        defer { isCreatingIntent = false }
        do {
            reference = try await appState.bookingService.createPaymentIntent(bookingID: summary.booking.id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func refreshStatus() async {
        do {
            if let fresh = try await appState.bookingService.getBookingSummary(id: summary.booking.id) {
                refreshedBooking = fresh.booking
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
