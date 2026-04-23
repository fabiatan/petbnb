import Foundation
import Supabase

/// App-wide access to the configured `SupabaseClient`. Fails fast at launch
/// if `Shared.local.xcconfig` wasn't filled in — better a clear startup error
/// than mysterious network failures later.
enum SupabaseClientProvider {
    static let shared: SupabaseClient = {
        do {
            let env = try SupabaseEnv.loadFromBundle()
            return SupabaseClient(supabaseURL: env.url, supabaseKey: env.anonKey)
        } catch {
            fatalError(
                "Supabase env not configured: \(error).\n" +
                "Run `supabase status` and paste the URL + Publishable key into " +
                "ios/Config/Shared.local.xcconfig."
            )
        }
    }()
}
