import SwiftUI
import UniformTypeIdentifiers

struct PetDetailView: View {
    @Environment(AppState.self) private var appState
    let pet: Pet

    @State private var certs: [VaccinationCert] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showImporter = false
    @State private var isUploading = false

    var body: some View {
        List {
            Section("Profile") {
                LabeledContent("Species", value: pet.species.rawValue.capitalized)
                if let breed = pet.breed { LabeledContent("Breed", value: breed) }
                if let w = pet.weight_kg { LabeledContent("Weight", value: String(format: "%.1f kg", w)) }
                if let m = pet.age_months { LabeledContent("Age", value: "\(m) months") }
                if let n = pet.medical_notes { Text(n).font(.footnote).foregroundStyle(.secondary) }
            }

            Section {
                if certs.isEmpty && !isLoading {
                    Text("No vaccination certificates uploaded yet.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                ForEach(certs) { cert in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(cert.file_url.split(separator: "/").last.map(String.init) ?? cert.file_url)
                            .font(.subheadline)
                        Text("Expires \(cert.expires_on.formatted(date: .abbreviated, time: .omitted))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                HStack {
                    Text("Vaccinations")
                    Spacer()
                    Button { showImporter = true } label: {
                        if isUploading { ProgressView() } else { Text("Upload") }
                    }
                    .disabled(isUploading)
                }
            }
            if let errorMessage { Section { Text(errorMessage).foregroundStyle(.red) } }
        }
        .navigationTitle(pet.name)
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [.pdf, .jpeg, .png],
            allowsMultipleSelection: false,
            onCompletion: handleFileSelection
        )
        .task { await reloadCerts() }
    }

    private func handleFileSelection(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            Task { await upload(fileURL: url) }
        case .failure(let e):
            errorMessage = e.localizedDescription
        }
    }

    private func upload(fileURL: URL) async {
        errorMessage = nil
        isUploading = true
        defer { isUploading = false }

        let gotAccess = fileURL.startAccessingSecurityScopedResource()
        defer { if gotAccess { fileURL.stopAccessingSecurityScopedResource() } }

        do {
            let data = try Data(contentsOf: fileURL)
            let ext = (fileURL.pathExtension).lowercased()
            let contentType: String = switch ext {
            case "pdf": "application/pdf"
            case "jpg", "jpeg": "image/jpeg"
            case "png": "image/png"
            default: "application/octet-stream"
            }
            // Default issued_on=today, expires_on=today+1yr. User can refine in a later slice.
            let today = Date()
            let oneYear = Calendar.current.date(byAdding: .year, value: 1, to: today) ?? today
            _ = try await appState.petService.uploadCert(
                for: pet.id,
                data: data,
                filename: fileURL.lastPathComponent,
                contentType: contentType,
                issuedOn: today,
                expiresOn: oneYear
            )
            await reloadCerts()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func reloadCerts() async {
        isLoading = true
        defer { isLoading = false }
        do {
            certs = try await appState.petService.listCerts(for: pet.id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
