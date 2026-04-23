import Foundation

enum SupabaseEnvError: Error {
    case missing(String)
    case invalidURL(String)
}

struct SupabaseEnv {
    let url: URL
    let anonKey: String

    static func loadFromBundle() throws -> SupabaseEnv {
        let bundle = Bundle.main
        guard let urlString = bundle.object(forInfoDictionaryKey: "SUPABASE_URL") as? String,
              !urlString.isEmpty else {
            throw SupabaseEnvError.missing("SUPABASE_URL")
        }
        guard let key = bundle.object(forInfoDictionaryKey: "SUPABASE_ANON_KEY") as? String,
              !key.isEmpty, key != "REPLACE_WITH_PUBLISHABLE_KEY" else {
            throw SupabaseEnvError.missing("SUPABASE_ANON_KEY")
        }
        guard let url = URL(string: urlString) else {
            throw SupabaseEnvError.invalidURL(urlString)
        }
        return SupabaseEnv(url: url, anonKey: key)
    }
}
