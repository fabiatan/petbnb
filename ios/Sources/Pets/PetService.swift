import Foundation
import Supabase

@MainActor
final class PetService {
    let client: SupabaseClient
    init(client: SupabaseClient) {
        self.client = client
    }
}
