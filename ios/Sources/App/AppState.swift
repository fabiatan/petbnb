import Foundation
import Observation
import Supabase

@Observable
@MainActor
final class AppState {
    enum Status {
        case bootstrapping
        case signedOut
        case signedIn(userId: UUID, displayName: String)
    }

    var status: Status = .bootstrapping
    let authService: AuthService
    let petService: PetService
    let listingRepository: ListingRepository
    let bookingService: BookingService

    init() {
        let client = SupabaseClientProvider.shared
        self.authService = AuthService(client: client)
        self.petService = PetService(client: client)
        self.listingRepository = ListingRepository(client: client)
        self.bookingService = BookingService(client: client)
    }

    func bootstrap() async {
        for await event in authService.authEvents() {
            switch event {
            case let .signedIn(userId, displayName):
                status = .signedIn(userId: userId, displayName: displayName)
            case .signedOut:
                status = .signedOut
            }
        }
    }
}
