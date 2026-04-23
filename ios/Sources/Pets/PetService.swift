import Foundation
import Supabase

enum PetServiceError: LocalizedError {
    case notAuthenticated
    case fetchFailed(String)
    case createFailed(String)
    case upload(String)

    var errorDescription: String? {
        switch self {
        case .notAuthenticated: "Not signed in."
        case .fetchFailed(let m): "Couldn't load pets: \(m)"
        case .createFailed(let m): "Couldn't add pet: \(m)"
        case .upload(let m): "Upload failed: \(m)"
        }
    }
}

@MainActor
final class PetService {
    let client: SupabaseClient

    init(client: SupabaseClient) {
        self.client = client
    }

    func listPets() async throws -> [Pet] {
        do {
            let pets: [Pet] = try await client.from("pets")
                .select()
                .order("created_at", ascending: true)
                .execute()
                .value
            return pets
        } catch {
            throw PetServiceError.fetchFailed(error.localizedDescription)
        }
    }

    func addPet(_ input: NewPetInput) async throws -> Pet {
        guard let userId = try? await client.auth.user().id else {
            throw PetServiceError.notAuthenticated
        }

        struct Row: Encodable {
            let owner_id: String
            let name: String
            let species: String
            let breed: String?
            let age_months: Int?
            let weight_kg: Double?
            let medical_notes: String?
        }
        let row = Row(
            owner_id: userId.uuidString,
            name: input.name,
            species: input.species.rawValue,
            breed: input.breed,
            age_months: input.age_months,
            weight_kg: input.weight_kg,
            medical_notes: input.medical_notes
        )

        do {
            let pet: Pet = try await client.from("pets")
                .insert(row, returning: .representation)
                .select()
                .single()
                .execute()
                .value
            return pet
        } catch {
            throw PetServiceError.createFailed(error.localizedDescription)
        }
    }

    func listCerts(for petId: UUID) async throws -> [VaccinationCert] {
        let certs: [VaccinationCert] = try await client.from("vaccination_certs")
            .select()
            .eq("pet_id", value: petId.uuidString)
            .order("expires_on", ascending: false)
            .execute()
            .value
        return certs
    }

    /// Upload a cert file to Storage + insert a vaccination_certs row.
    /// Returns the inserted cert.
    func uploadCert(
        for petId: UUID,
        data: Data,
        filename: String,
        contentType: String,
        issuedOn: Date,
        expiresOn: Date
    ) async throws -> VaccinationCert {
        let safeName = filename
            .replacingOccurrences(of: "[^A-Za-z0-9._-]+", with: "_", options: .regularExpression)
            .prefix(120)
        let uniqueId = UUID().uuidString
        let path = "pets/\(petId.uuidString)/\(uniqueId)_\(safeName)"

        do {
            _ = try await client.storage
                .from("pet-vaccinations")
                .upload(
                    path,
                    data: data,
                    options: FileOptions(contentType: contentType, upsert: false)
                )
        } catch {
            throw PetServiceError.upload(error.localizedDescription)
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]

        struct Row: Encodable {
            let pet_id: String
            let file_url: String
            let vaccines_covered: [String]
            let issued_on: String
            let expires_on: String
        }
        let row = Row(
            pet_id: petId.uuidString,
            file_url: path,
            vaccines_covered: [],
            issued_on: formatter.string(from: issuedOn),
            expires_on: formatter.string(from: expiresOn)
        )
        let cert: VaccinationCert = try await client.from("vaccination_certs")
            .insert(row, returning: .representation)
            .select()
            .single()
            .execute()
            .value
        return cert
    }
}
