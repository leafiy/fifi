import Foundation

public enum URLCleaner {
    /// Removes known tracking query parameters from an http(s) URL string.
    /// Returns nil when the string is not a parseable http(s) URL.
    /// Returns the original string when nothing was removed.
    public static func cleaned(_ urlString: String) -> String? {
        guard var components = httpComponents(from: urlString) else { return nil }
        guard let queryItems = components.percentEncodedQueryItems, !queryItems.isEmpty else {
            return urlString
        }

        let host = components.host ?? ""
        let keptItems = queryItems.filter { !isTrackingParameter(name: $0.name, host: host) }
        guard keptItems.count != queryItems.count else { return urlString }

        components.percentEncodedQueryItems = keptItems.isEmpty ? nil : keptItems
        return components.string
    }

    /// True when `cleaned` would remove at least one parameter.
    public static func hasTrackingParameters(_ urlString: String) -> Bool {
        guard let components = httpComponents(from: urlString) else { return false }
        guard let queryItems = components.percentEncodedQueryItems, !queryItems.isEmpty else { return false }

        let host = components.host ?? ""
        return queryItems.contains { isTrackingParameter(name: $0.name, host: host) }
    }

    // MARK: - Rules

    private static let trackingPrefixes: [String] = [
        "utm_", "pk_", "mtm_", "hsa_", "vero_", "oly_", "at_", "matomo_"
    ]

    private static let globalTrackingParameters: Set<String> = [
        "fbclid", "gclid", "gclsrc", "dclid", "gbraid", "wbraid", "msclkid", "mc_cid", "mc_eid",
        "igshid", "igsh", "ref_src", "ref_url", "twclid", "yclid", "_hsenc", "_hsmi", "hsctatracking",
        "mkt_tok", "ttclid", "li_fat_id", "epik", "s_kwcid", "sms_source", "sms_click", "wickedid",
        "irclickid", "sscid", "rtid", "cmpid", "spm", "scm", "share_id", "xhsshare"
    ]

    private static let youtubeHostSuffixes: [String] = ["youtube.com", "youtu.be"]
    private static let spotifyHostSuffixes: [String] = ["open.spotify.com"]

    private static func httpComponents(from urlString: String) -> URLComponents? {
        guard let components = URLComponents(string: urlString) else { return nil }
        guard let scheme = components.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            return nil
        }
        guard let host = components.host, !host.isEmpty else { return nil }
        return components
    }

    private static func isTrackingParameter(name: String, host: String) -> Bool {
        let lowercasedName = name.lowercased()

        if globalTrackingParameters.contains(lowercasedName) {
            return true
        }

        if trackingPrefixes.contains(where: { lowercasedName.hasPrefix($0) }) {
            return true
        }

        if lowercasedName == "si" {
            return hostMatches(host, suffixes: youtubeHostSuffixes) || hostMatches(host, suffixes: spotifyHostSuffixes)
        }

        if lowercasedName == "feature" || lowercasedName == "pp" {
            return hostMatches(host, suffixes: youtubeHostSuffixes)
        }

        return false
    }

    private static func hostMatches(_ host: String, suffixes: [String]) -> Bool {
        let normalizedHost = host.lowercased()
        return suffixes.contains { suffix in
            normalizedHost == suffix || normalizedHost.hasSuffix("." + suffix)
        }
    }
}
