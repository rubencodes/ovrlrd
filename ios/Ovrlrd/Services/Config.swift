import Foundation

/// Legacy configuration from xcconfig/Info.plist
/// Used as optional fallback for DEBUG builds when ServerConfigService is not configured
enum Config {
    /// API base URL - configured via Local.xcconfig -> Info.plist
    /// Returns nil if not configured (no longer fatal)
    static let apiBaseURL: URL? = {
        guard let urlString = Bundle.main.object(forInfoDictionaryKey: "API_BASE_URL") as? String,
              !urlString.isEmpty,
              let url = URL(string: urlString) else {
            return nil
        }

        #if !DEBUG
        assert(url.scheme == "https", "Production builds must use HTTPS")
        #endif

        return url
    }()

    /// API key for server authentication - configured via Local.xcconfig -> Info.plist
    /// Returns nil if not configured (no longer fatal)
    static let apiKey: String? = {
        guard let key = Bundle.main.object(forInfoDictionaryKey: "API_KEY") as? String,
              !key.isEmpty else {
            return nil
        }
        return key
    }()
}
