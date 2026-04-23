import SwiftUI

struct BookingReviewView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    let destination: ListingDestination
    let kennel: KennelTypeSummary

    @State private var pets: [Pet] = []
    @State private var selectedPetID: UUID?
    @State private var specialInstructions: String = ""
    @State private var isLoadingPets = false
    @State private var errorMessage: String?
    @State private var isSubmitting = false
    @State private var submittedBookingID: UUID?
    @State private var goToBookings = false

    private var criteria: SearchCriteria { destination.criteria }
    private var nights: Int {
        max(1, Calendar.current.dateComponents([.day], from: criteria.checkIn, to: criteria.checkOut).day ?? 1)
    }
    private var subtotal: Double { Double(nights) * kennel.base_price_myr }

    private var selectedPet: Pet? {
        pets.first { $0.id == selectedPetID }
    }

    /// Does the chosen pet have a cert on file at all? (Phase 2a doesn't give us
    /// access to the cert expiry easily without another query — this is a
    /// soft check; the Phase 0 RPC will enforce the real precondition server-side.)
    private var canSubmit: Bool {
        selectedPet != nil && !isSubmitting
    }

    var body: some View {
        Form {
            Section("Stay") {
                LabeledContent("Business", value: destination.business.name)
                LabeledContent("Kennel", value: kennel.name)
                LabeledContent("Dates", value: "\(criteria.checkIn.formatted(date: .abbreviated, time: .omitted)) → \(criteria.checkOut.formatted(date: .abbreviated, time: .omitted))")
                LabeledContent("Nights", value: "\(nights)")
            }

            Section("Pet") {
                if isLoadingPets {
                    ProgressView()
                } else if pets.isEmpty {
                    Text("Add a pet in the Pets tab before booking.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    Picker("Pet", selection: $selectedPetID) {
                        ForEach(pets) { pet in
                            Text(pet.name).tag(Optional(pet.id))
                        }
                    }
                    .pickerStyle(.menu)
                }
            }

            Section("Notes for sitter (optional)") {
                TextEditor(text: $specialInstructions)
                    .frame(minHeight: 80)
            }

            Section("Price") {
                HStack {
                    Text("\(nights) × RM \(String(format: "%.0f", kennel.base_price_myr))")
                    Spacer()
                    Text("RM \(String(format: "%.0f", subtotal))")
                }
            }

            if let errorMessage {
                Section { Text(errorMessage).foregroundStyle(.red) }
            }

            Section {
                Button {
                    Task { await submit() }
                } label: {
                    HStack {
                        Spacer()
                        if isSubmitting {
                            ProgressView()
                        } else {
                            Text(kennel.instant_book ? "Book now" : "Send request")
                                .fontWeight(.semibold)
                        }
                        Spacer()
                    }
                }
                .disabled(!canSubmit)
            } footer: {
                if !kennel.instant_book {
                    Text("The sitter has 24 hours to respond. You'll be prompted to pay after acceptance.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Review")
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadPets() }
        .navigationDestination(isPresented: $goToBookings) {
            MyBookingsView()
        }
    }

    private func loadPets() async {
        isLoadingPets = true
        defer { isLoadingPets = false }
        do {
            pets = try await appState.petService.listPets()
            if selectedPetID == nil {
                selectedPetID = criteria.petID ?? pets.first?.id
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func submit() async {
        guard let petID = selectedPetID else { return }
        errorMessage = nil
        isSubmitting = true
        defer { isSubmitting = false }

        let input = BookingService.CreateBookingInput(
            kennelTypeID: kennel.id,
            petIDs: [petID],
            checkIn: criteria.checkIn,
            checkOut: criteria.checkOut,
            specialInstructions: specialInstructions.trimmingCharacters(in: .whitespaces).isEmpty ? nil : specialInstructions,
            isInstantBook: kennel.instant_book
        )

        do {
            let id = try await appState.bookingService.createBooking(input)
            submittedBookingID = id
            goToBookings = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
