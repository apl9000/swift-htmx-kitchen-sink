import Foundation

enum AppRuntimeMode: String, Equatable, Sendable {
    case local
    case staging
    case production
}

struct AccessConfigurationError: Error, Equatable, CustomStringConvertible {
    let description: String

    init(_ description: String) {
        self.description = description
    }
}

/// Fail-closed process configuration. Secrets are omitted from `description`.
struct AccessConfiguration: Equatable, Sendable, CustomStringConvertible {
    let mode: AppRuntimeMode
    let publicHost: String?
    let originHost: String?
    let entraTenantID: String?
    let entraClientID: String?
    let entraAudience: String?
    let acceptedIssuers: [String]
    let entraJWKSURL: URL?
    let originAuthHeader: String
    let originAuthSecret: String?
    let frontDoorID: String?

    var description: String {
        "mode=\(mode) publicHost=\(publicHost ?? "-") originHost=\(originHost ?? "-")"
    }

    static let originAuthHeaderDefault = "X-App-Origin-Auth"
    static let platformEnvironmentKeys = [
        "CONTAINER_APP_NAME",
        "CONTAINER_APP_REVISION",
        "WEBSITE_SITE_NAME",
        "WEBSITE_INSTANCE_ID",
    ]

    static func load(from environment: [String: String], vaporEnvironmentName: String) throws -> AccessConfiguration {
        let platformMarker = platformEnvironmentKeys.first { key in
            guard let value = environment[key]?.trimmingCharacters(in: .whitespacesAndNewlines) else {
                return false
            }
            return !value.isEmpty
        }

        let mode = try resolveMode(
            raw: environment["APP_RUNTIME_MODE"],
            vaporEnvironmentName: vaporEnvironmentName,
            platformMarker: platformMarker
        )

        switch mode {
        case .local:
            try rejectDeployedSettings(in: environment, platformMarker: platformMarker)
            return AccessConfiguration(
                mode: .local,
                publicHost: nil,
                originHost: nil,
                entraTenantID: nil,
                entraClientID: nil,
                entraAudience: nil,
                acceptedIssuers: [],
                entraJWKSURL: nil,
                originAuthHeader: originAuthHeaderDefault,
                originAuthSecret: nil,
                frontDoorID: nil
            )
        case .staging:
            return try deployed(
                mode: .staging,
                environment: environment,
                requiresFrontDoor: false
            )
        case .production:
            return try deployed(
                mode: .production,
                environment: environment,
                requiresFrontDoor: true
            )
        }
    }

    private static func resolveMode(
        raw: String?,
        vaporEnvironmentName: String,
        platformMarker: String?
    ) throws -> AppRuntimeMode {
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmed.isEmpty {
            if let platformMarker {
                throw AccessConfigurationError(
                    "APP_RUNTIME_MODE must be staging or production when \(platformMarker) is present"
                )
            }
            if vaporEnvironmentName == "production" {
                throw AccessConfigurationError(
                    "APP_RUNTIME_MODE must be set when the Vapor environment is production"
                )
            }
            return .local
        }
        guard let mode = AppRuntimeMode(rawValue: trimmed) else {
            throw AccessConfigurationError("APP_RUNTIME_MODE must be local, staging, or production")
        }
        if mode == .local, let platformMarker {
            throw AccessConfigurationError(
                "APP_RUNTIME_MODE=local is refused when \(platformMarker) is present"
            )
        }
        return mode
    }

    private static func rejectDeployedSettings(in environment: [String: String], platformMarker: String?) throws {
        if let platformMarker {
            throw AccessConfigurationError(
                "APP_RUNTIME_MODE=local is refused when \(platformMarker) is present"
            )
        }
        let deployedKeys = [
            "PUBLIC_HOST",
            "ORIGIN_HOST",
            "ENTRA_TENANT_ID",
            "ENTRA_CLIENT_ID",
            "ENTRA_AUDIENCE",
            "ENTRA_ISSUER",
            "ENTRA_JWKS_URL",
            "ORIGIN_AUTH_HEADER",
            "ORIGIN_AUTH_SECRET",
            "FRONTDOOR_ID",
        ]
        if let key = deployedKeys.first(where: { key in
            guard let value = environment[key]?.trimmingCharacters(in: .whitespacesAndNewlines) else {
                return false
            }
            return !value.isEmpty
        }) {
            throw AccessConfigurationError("\(key) must be unset when APP_RUNTIME_MODE is local")
        }
    }

    private static func deployed(
        mode: AppRuntimeMode,
        environment: [String: String],
        requiresFrontDoor: Bool
    ) throws -> AccessConfiguration {
        let publicHost = try requiredHost("PUBLIC_HOST", environment)
        let originHost = try optionalHost("ORIGIN_HOST", environment)
        let tenantID = try requiredGUID("ENTRA_TENANT_ID", environment)
        let clientID = try requiredGUID("ENTRA_CLIENT_ID", environment)
        let audience = try audience(in: environment, clientID: clientID)
        let issuer = try optionalIssuer(in: environment, tenantID: tenantID)
        let jwksURL = try jwksURL(in: environment, tenantID: tenantID, issuer: issuer)
        let frontDoorID = try frontDoorID(in: environment, required: requiresFrontDoor)
        let originSecret = try originSecret(in: environment, required: requiresFrontDoor, frontDoorID: frontDoorID)
        let originHeader = try originHeader(in: environment, required: requiresFrontDoor)

        let acceptedIssuers: [String]
        if let issuer {
            acceptedIssuers = [issuer]
        } else {
            acceptedIssuers = [
                "https://login.microsoftonline.com/\(tenantID)/v2.0",
                "https://sts.windows.net/\(tenantID)/",
            ]
        }

        return AccessConfiguration(
            mode: mode,
            publicHost: publicHost,
            originHost: originHost,
            entraTenantID: tenantID,
            entraClientID: clientID,
            entraAudience: audience,
            acceptedIssuers: acceptedIssuers,
            entraJWKSURL: jwksURL,
            originAuthHeader: originHeader,
            originAuthSecret: originSecret,
            frontDoorID: frontDoorID
        )
    }

    private static func requiredHost(_ key: String, _ environment: [String: String]) throws -> String {
        guard let raw = nonempty(environment[key]) else {
            throw AccessConfigurationError("\(key) is required")
        }
        guard let normalized = HostName.normalize(raw) else {
            throw AccessConfigurationError("\(key) is not a valid hostname")
        }
        return normalized
    }

    private static func optionalHost(_ key: String, _ environment: [String: String]) throws -> String? {
        guard let raw = nonempty(environment[key]) else { return nil }
        guard let normalized = HostName.normalize(raw) else {
            throw AccessConfigurationError("\(key) is not a valid hostname")
        }
        return normalized
    }

    private static func requiredGUID(_ key: String, _ environment: [String: String]) throws -> String {
        guard let raw = nonempty(environment[key]) else {
            throw AccessConfigurationError("\(key) is required")
        }
        guard let guid = guid(raw) else {
            throw AccessConfigurationError("\(key) must be a non-nil GUID")
        }
        return guid
    }

    private static func audience(in environment: [String: String], clientID: String) throws -> String {
        let value = nonempty(environment["ENTRA_AUDIENCE"]) ?? clientID
        guard !value.isEmpty, value.count <= 200 else {
            throw AccessConfigurationError("ENTRA_AUDIENCE is invalid")
        }
        guard !value.contains(where: { $0.isWhitespace || $0 == "?" || $0 == "#" || $0 == "@" }) else {
            throw AccessConfigurationError("ENTRA_AUDIENCE is invalid")
        }
        return value
    }

    private static func optionalIssuer(in environment: [String: String], tenantID: String) throws -> String? {
        guard let value = nonempty(environment["ENTRA_ISSUER"]) else { return nil }
        guard let url = URL(string: value),
              url.scheme == "https",
              url.user == nil,
              url.password == nil,
              url.query == nil,
              url.fragment == nil,
              let host = url.host?.lowercased(),
              allowedIdentityHost(host),
              value.lowercased().contains(tenantID)
        else {
            throw AccessConfigurationError(
                "ENTRA_ISSUER must be an https Microsoft Entra issuer URL that contains ENTRA_TENANT_ID"
            )
        }
        return value
    }

    private static func jwksURL(
        in environment: [String: String],
        tenantID: String,
        issuer: String?
    ) throws -> URL? {
        if let raw = nonempty(environment["ENTRA_JWKS_URL"]) {
            guard let url = URL(string: raw),
                  url.scheme == "https",
                  url.user == nil,
                  url.password == nil,
                  url.query == nil,
                  url.fragment == nil,
                  let host = url.host?.lowercased(),
                  allowedIdentityHost(host),
                  raw.lowercased().contains(tenantID)
            else {
                throw AccessConfigurationError(
                    "ENTRA_JWKS_URL must be an https Microsoft JWKS URL that contains ENTRA_TENANT_ID"
                )
            }
            return url
        }

        if let issuer, let host = URL(string: issuer)?.host?.lowercased(), !commercialIssuerHost(host) {
            throw AccessConfigurationError("ENTRA_JWKS_URL is required when ENTRA_ISSUER is not the commercial Entra issuer")
        }
        return nil
    }

    private static func frontDoorID(in environment: [String: String], required: Bool) throws -> String? {
        let value = nonempty(environment["FRONTDOOR_ID"])
        if required {
            guard let value, let guid = guid(value) else {
                throw AccessConfigurationError("FRONTDOOR_ID must be the Front Door profile GUID in production")
            }
            return guid
        }
        if value != nil {
            throw AccessConfigurationError("FRONTDOOR_ID must be unset in staging; production mode owns Front Door origin auth")
        }
        return nil
    }

    private static func originSecret(
        in environment: [String: String],
        required: Bool,
        frontDoorID: String?
    ) throws -> String? {
        let value = environment["ORIGIN_AUTH_SECRET"]
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        if required {
            guard let value, let trimmed, value == trimmed, trimmed.count >= 32 else {
                throw AccessConfigurationError("ORIGIN_AUTH_SECRET must be an unpadded secret of at least 32 characters in production")
            }
            let lowered = trimmed.lowercased()
            if isPlaceholder(lowered) || Set(lowered).count < 8 {
                throw AccessConfigurationError("ORIGIN_AUTH_SECRET is a placeholder or has too little entropy")
            }
            if let frontDoorID, lowered.contains(frontDoorID) {
                throw AccessConfigurationError("ORIGIN_AUTH_SECRET must not contain FRONTDOOR_ID")
            }
            return value
        }
        if nonempty(trimmed) != nil {
            throw AccessConfigurationError("ORIGIN_AUTH_SECRET must be unset in staging")
        }
        return nil
    }

    private static func originHeader(in environment: [String: String], required: Bool) throws -> String {
        let value = nonempty(environment["ORIGIN_AUTH_HEADER"])
        if !required {
            if value != nil {
                throw AccessConfigurationError("ORIGIN_AUTH_HEADER must be unset in staging")
            }
            return originAuthHeaderDefault
        }
        let header = value ?? originAuthHeaderDefault
        guard header.count <= 64, header.range(of: #"^[Xx]-[A-Za-z0-9-]{1,62}$"#, options: .regularExpression) != nil else {
            throw AccessConfigurationError("ORIGIN_AUTH_HEADER must be a single X- header name")
        }
        let reserved = [
            "x-ms-client-principal",
            "x-ms-client-principal-id",
            "x-ms-client-principal-name",
            "x-ms-client-principal-idp",
            "x-ms-token-aad-id-token",
            "x-ms-token-aad-access-token",
            "x-azure-fdid",
            "authorization",
            "cookie",
            "host",
            "x-forwarded-host",
        ]
        if reserved.contains(header.lowercased()) {
            throw AccessConfigurationError("ORIGIN_AUTH_HEADER collides with a platform or hop header")
        }
        return header
    }

    private static func guid(_ raw: String) -> String? {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard value.range(
            of: #"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"#,
            options: .regularExpression
        ) != nil else {
            return nil
        }
        guard value != "00000000-0000-0000-0000-000000000000" else { return nil }
        return value
    }

    private static func isPlaceholder(_ value: String) -> Bool {
        let placeholders = ["changeme", "replace-me", "password", "secret", "example", "xxxx"]
        return placeholders.contains { placeholder in
            value.replacingOccurrences(of: placeholder, with: "").isEmpty
        }
    }

    private static func nonempty(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func commercialIssuerHost(_ host: String) -> Bool {
        host == "login.microsoftonline.com" || host == "sts.windows.net"
    }

    private static func allowedIdentityHost(_ host: String) -> Bool {
        switch host {
        case "login.microsoftonline.com",
             "login.microsoftonline.us",
             "login.partner.microsoftonline.cn",
             "sts.windows.net":
            return true
        default:
            return host.hasSuffix(".ciamlogin.com") && host != ".ciamlogin.com"
        }
    }
}
