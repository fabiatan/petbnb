import SwiftUI

struct AddPetView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var species: Pet.Species = .dog
    @State private var breed = ""
    @State private var weightText = ""
    @State private var ageMonthsText = ""
    @State private var medicalNotes = ""

    @State private var isSubmitting = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Basics") {
                    TextField("Name", text: $name)
                    Picker("Species", selection: $species) {
                        ForEach(Pet.Species.allCases, id: \.self) { s in
                            Text(s.rawValue.capitalized).tag(s)
                        }
                    }
                    TextField("Breed (optional)", text: $breed)
                }
                Section("Details") {
                    TextField("Age in months", text: $ageMonthsText)
                        .keyboardType(.numberPad)
                    TextField("Weight in kg", text: $weightText)
                        .keyboardType(.decimalPad)
                }
                Section("Medical notes") {
                    TextEditor(text: $medicalNotes)
                        .frame(minHeight: 80)
                }
                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(.red) }
                }
            }
            .navigationTitle("Add pet")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button { Task { await submit() } } label: {
                        if isSubmitting { ProgressView() } else { Text("Save") }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || isSubmitting)
                }
            }
        }
    }

    private func submit() async {
        errorMessage = nil
        isSubmitting = true
        defer { isSubmitting = false }

        let input = NewPetInput(
            name: name.trimmingCharacters(in: .whitespaces),
            species: species,
            breed: breed.isEmpty ? nil : breed,
            age_months: Int(ageMonthsText),
            weight_kg: Double(weightText),
            medical_notes: medicalNotes.isEmpty ? nil : medicalNotes
        )
        do {
            _ = try await appState.petService.addPet(input)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
