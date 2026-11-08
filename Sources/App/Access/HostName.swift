import Foundation

/// DNS hostname checks for the public site and the optional container origin.
///
/// A single trailing dot is part of the DNS absolute form (`example.com.`) and is
/// removed before comparison. Any other unexpected form is rejected so a
/// lookalike cannot pass an equality check by changing spelling, port, or suffix.
enum HostName {
    static func normalize(_ raw: String) -> String? {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        guard value.unicodeScalars.allSatisfy(\.isASCII) else { return nil }
        guard !value.contains(where: isForbidden) else { return nil }
        guard !value.contains(":") else { return nil }
        guard !value.hasSuffix("..") else { return nil }
        if value.hasSuffix(".") {
            value.removeLast()
        }
        guard !value.hasSuffix(".") else { return nil }
        value = value.lowercased()
        guard !value.isEmpty, value.count <= 253 else { return nil }

        let labels = value.split(separator: ".", omittingEmptySubsequences: false)
        // A public or origin hostname is a dotted DNS name. Single-label names
        // such as "localhost" are not accepted as a deployed host.
        guard labels.count >= 2 else { return nil }
        for label in labels {
            guard !label.isEmpty, label.count <= 63 else { return nil }
            guard !label.hasPrefix("-"), !label.hasSuffix("-") else { return nil }
            guard label.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" }) else { return nil }
        }
        return value
    }

    /// Staging and production requests must name the configured public host.
    /// When `X-Forwarded-Host` is present it is the public host, and `Host`
    /// may additionally be the configured origin hostname.
    static func allows(hostHeader: String?, forwardedHost: String?, configuration: AccessConfiguration) -> Bool {
        guard let publicHost = configuration.publicHost else { return false }

        let host: String?
        if let hostHeader {
            guard let normalized = normalize(hostHeader) else { return false }
            host = normalized
        } else {
            host = nil
        }

        let forwarded: String?
        if let forwardedHost {
            guard let normalized = normalize(forwardedHost) else { return false }
            forwarded = normalized
        } else {
            forwarded = nil
        }

        if let forwarded {
            guard forwarded == publicHost, let host else { return false }
            var allowed = Set([publicHost])
            if let originHost = configuration.originHost {
                allowed.insert(originHost)
            }
            return allowed.contains(host)
        }

        guard let host else { return false }
        return host == publicHost
    }

    private static func isForbidden(_ character: Character) -> Bool {
        switch character {
        case "/", "\\", "@", "?", "#", "%", ",", " ", "\t", "[", "]":
            return true
        default:
            return false
        }
    }
}
