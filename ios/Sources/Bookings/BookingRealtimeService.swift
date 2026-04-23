import Foundation
import Supabase

/// Subscribes to `public.bookings` Postgres changes filtered by the caller's
/// owner_id. Emits an event whenever any of the caller's bookings UPDATE,
/// INSERT, or DELETE. The consumer (MyBookingsView) re-fetches its list on
/// receipt.
@MainActor
final class BookingRealtimeService {
    enum Event {
        case changed         // some booking of the caller changed — refetch
    }

    private let client: SupabaseClient
    private var channel: RealtimeChannelV2?
    private var task: Task<Void, Never>?

    init(client: SupabaseClient) {
        self.client = client
    }

    /// Start a subscription. Caller holds the returned AsyncStream and iterates
    /// for events. Call `stop()` to tear down.
    func start() async -> AsyncStream<Event> {
        AsyncStream { continuation in
            let startTask = Task { [client] in
                guard let userId = try? await client.auth.user().id else { return }
                let channel = client.channel("owner-bookings-\(userId.uuidString)")

                // Postgres changes emit on each UPDATE; we map to the generic
                // `changed` event rather than trying to diff incrementally.
                let changes = channel.postgresChange(
                    AnyAction.self,
                    schema: "public",
                    table: "bookings",
                    filter: "owner_id=eq.\(userId.uuidString)"
                )

                do {
                    try await channel.subscribeWithError()
                } catch {
                    continuation.finish()
                    return
                }

                self.channel = channel

                for await _ in changes {
                    continuation.yield(.changed)
                }
                continuation.finish()
            }
            self.task = startTask

            continuation.onTermination = { [weak self] _ in
                Task { [weak self] in await self?.stop() }
            }
        }
    }

    func stop() async {
        task?.cancel()
        task = nil
        if let channel {
            await channel.unsubscribe()
        }
        channel = nil
    }
}
