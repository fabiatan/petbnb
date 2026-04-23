import SwiftUI

struct DiscoverView: View {
    @Environment(AppState.self) private var appState
    @State private var criteria = SearchCriteria(
        city: "Kuala Lumpur",
        checkIn: Self.defaultCheckIn(),
        checkOut: Self.defaultCheckOut(),
        petID: nil
    )
    @State private var pets: [Pet] = []
    @State private var errorMessage: String?
    @State private var isLoadingPets = false
    @State private var navPath = NavigationPath()

    private static func defaultCheckIn() -> Date {
        Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()
    }
    private static func defaultCheckOut() -> Date {
        Calendar.current.date(byAdding: .day, value: 12, to: Date()) ?? Date()
    }

    var body: some View {
        NavigationStack(path: $navPath) {
            Form {
                Section {
                    TextField("City", text: $criteria.city)
                }
                Section {
                    DatePicker(
                        "Check-in",
                        selection: $criteria.checkIn,
                        in: Date()...,
                        displayedComponents: .date
                    )
                    DatePicker(
                        "Check-out",
                        selection: $criteria.checkOut,
                        in: (criteria.checkIn.addingTimeInterval(86_400))...,
                        displayedComponents: .date
                    )
                }
                Section("Pet") {
                    if isLoadingPets {
                        ProgressView()
                    } else if pets.isEmpty {
                        Text("You haven't added a pet yet. Tap the Pets tab to add one.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("Pet", selection: $criteria.petID) {
                            ForEach(pets) { pet in
                                Text(pet.name).tag(Optional(pet.id))
                            }
                        }
                        .pickerStyle(.menu)
                    }
                }
                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(.red) }
                }
                Section {
                    Button {
                        navPath.append(criteria)
                    } label: {
                        HStack {
                            Spacer()
                            Text("Search")
                                .fontWeight(.semibold)
                            Spacer()
                        }
                    }
                    .disabled(!criteria.isValid)
                }
            }
            .navigationTitle("Find boarding")
            .navigationDestination(for: SearchCriteria.self) { c in
                SearchResultsView(criteria: c)
            }
            .navigationDestination(for: ListingDestination.self) { dest in
                ListingDetailView(destination: dest)
            }
            .task { await loadPets() }
        }
    }

    private func loadPets() async {
        isLoadingPets = true
        defer { isLoadingPets = false }
        do {
            pets = try await appState.petService.listPets()
            if criteria.petID == nil { criteria.petID = pets.first?.id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

extension SearchCriteria: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(city)
        hasher.combine(checkIn)
        hasher.combine(checkOut)
        hasher.combine(petID)
    }
}
