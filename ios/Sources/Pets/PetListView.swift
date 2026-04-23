import SwiftUI

struct PetListView: View {
    @Environment(AppState.self) private var appState
    @State private var pets: [Pet] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showAddPet = false

    var body: some View {
        NavigationStack {
            List {
                if pets.isEmpty && !isLoading {
                    ContentUnavailableView(
                        "No pets yet",
                        systemImage: "pawprint",
                        description: Text("Add your first pet to get started.")
                    )
                }
                ForEach(pets) { pet in
                    NavigationLink(value: pet) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(pet.name).font(.headline)
                            Text([
                                pet.species.rawValue.capitalized,
                                pet.breed ?? "",
                                pet.weight_kg.map { "\(Int($0)) kg" } ?? ""
                            ].filter { !$0.isEmpty }.joined(separator: " · "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .overlay {
                if isLoading && pets.isEmpty {
                    ProgressView()
                }
            }
            .navigationTitle("Pets")
            .navigationDestination(for: Pet.self) { pet in
                PetDetailView(pet: pet)
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showAddPet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button("Sign out") {
                        Task { try? await appState.authService.signOut() }
                    }
                }
            }
            .sheet(isPresented: $showAddPet, onDismiss: { Task { await reload() } }) {
                AddPetView()
            }
            .alert("Error", isPresented: .constant(errorMessage != nil), actions: {
                Button("OK") { errorMessage = nil }
            }, message: { Text(errorMessage ?? "") })
            .task { await reload() }
            .refreshable { await reload() }
        }
    }

    private func reload() async {
        isLoading = true
        defer { isLoading = false }
        do {
            pets = try await appState.petService.listPets()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
