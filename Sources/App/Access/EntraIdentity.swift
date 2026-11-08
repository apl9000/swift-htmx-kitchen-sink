import Foundation
import FoundationNetworking
import JWTKit

struct AuthenticationRejected: Error, Equatable {}

struct AccessDenied: Error, Equatable {}

struct AccessPrincipal: Equatable, Sendable {
    let subject: String
    let tenantID: String
    let audience: String
    let name: String?
    let identityProvider: String?
    /// Single-valued strings from the verified ID token. The default authorizer ignores them.
    let stringClaims: [String: String]
}

struct VerifiedIdentityToken: Equatable, Sendable {
    let subject: String
    let tenantID: String
    let audience: String
    let name: String?
    let stringClaims: [String: String]
}

protocol IDTokenVerifying: Sendable {
    func verify(compactToken: String, configuration: AccessConfiguration, now: Date) async throws -> VerifiedIdentityToken
}

struct PresentedIdentityHeaders: Equatable, Sendable {
    var principalID: String?
    var principalName: String?
    var identityProvider: String?
    var principalBlob: String?
}

enum PrincipalAgreement {
    static func agree(token: VerifiedIdentityToken, headers: PresentedIdentityHeaders) throws -> AccessPrincipal {
        if let principalID = headers.principalID, principalID != token.subject {
            throw AuthenticationRejected()
        }
        if let identityProvider = headers.identityProvider, identityProvider != "aad" {
            throw AuthenticationRejected()
        }
        if let blob = headers.principalBlob {
            try validate(blob: blob, tenantID: token.tenantID)
        }
        return AccessPrincipal(
            subject: token.subject,
            tenantID: token.tenantID,
            audience: token.audience,
            name: token.name,
            identityProvider: headers.identityProvider,
            stringClaims: token.stringClaims
        )
    }

    private static func validate(blob: String, tenantID: String) throws {
        guard blob.count <= 32_000, let data = decodeBase64(blob) else {
            throw AuthenticationRejected()
        }
        let document: ClientPrincipalDocument
        do {
            document = try JSONDecoder().decode(ClientPrincipalDocument.self, from: data)
        } catch {
            throw AuthenticationRejected()
        }
        if let authType = document.auth_typ, authType != "aad" {
            throw AuthenticationRejected()
        }
        for claim in document.claims ?? [] {
            let type = claim.typ.lowercased()
            let isTenant = type == "tid" || type.hasSuffix("/tenantid")
            if isTenant && claim.val.lowercased() != tenantID {
                throw AuthenticationRejected()
            }
        }
    }

    private static func decodeBase64(_ value: String) -> Data? {
        if let data = Data(base64Encoded: value) {
            return data
        }
        var converted = value.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        let remainder = converted.count % 4
        if remainder != 0 {
            converted.append(String(repeating: "=", count: 4 - remainder))
        }
        return Data(base64Encoded: converted)
    }
}

private struct ClientPrincipalDocument: Decodable {
    let auth_typ: String?
    let claims: [Claim]?

    struct Claim: Decodable {
        let typ: String
        let val: String
    }
}

enum EntraTokenPolicy {
    static let skew: TimeInterval = 60

    static func enforce(
        payload: EntraIDTokenPayload,
        configuration: AccessConfiguration,
        now: Date,
        stringClaims: [String: String]
    ) throws -> VerifiedIdentityToken {
        guard let tenantID = configuration.entraTenantID,
              let audience = configuration.entraAudience,
              payload.tid?.lowercased() == tenantID
        else {
            throw AuthenticationRejected()
        }
        let issuer = payload.iss.lowercased()
        guard configuration.acceptedIssuers.contains(where: { $0.lowercased() == issuer }) else {
            throw AuthenticationRejected()
        }
        guard payload.aud.values.contains(audience) else {
            throw AuthenticationRejected()
        }
        guard payload.exp.value.addingTimeInterval(Self.skew) >= now else {
            throw AuthenticationRejected()
        }
        if let notBefore = payload.nbf?.value, now.addingTimeInterval(Self.skew) < notBefore {
            throw AuthenticationRejected()
        }
        let subject = payload.oid ?? payload.sub?.value
        guard let subject, !subject.isEmpty, subject.count <= 256 else {
            throw AuthenticationRejected()
        }
        let name = payload.preferredUsername ?? payload.name
        return VerifiedIdentityToken(
            subject: subject,
            tenantID: tenantID,
            audience: audience,
            name: name,
            stringClaims: stringClaims
        )
    }
}

struct EntraIDTokenPayload: JWTPayload {
    var iss: String
    var aud: StringOrStrings
    var exp: ExpirationClaim
    var nbf: NotBeforeClaim?
    var sub: SubjectClaim?
    var oid: String?
    var tid: String?
    var name: String?
    var preferredUsername: String?

    enum CodingKeys: String, CodingKey {
        case iss
        case aud
        case exp
        case nbf
        case sub
        case oid
        case tid
        case name
        case preferredUsername = "preferred_username"
    }

    func verify(using _: some JWTAlgorithm) async throws {}
}

struct StringOrStrings: Codable, Equatable, Sendable {
    var values: [String]

    init(_ values: [String]) {
        self.values = values
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(String.self) {
            self.values = [value]
        } else {
            self.values = try container.decode([String].self)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        if values.count == 1, let only = values.first {
            try container.encode(only)
        } else {
            try container.encode(values)
        }
    }
}

protocol JWTKeyCollectionProviding: Sendable {
    func keyCollection(for configuration: AccessConfiguration) async throws -> JWTKeyCollection
}

struct EntraIDTokenVerifier: IDTokenVerifying {
    let keys: any JWTKeyCollectionProviding

    init(keys: any JWTKeyCollectionProviding = EntraJWKSKeyProvider()) {
        self.keys = keys
    }

    func verify(compactToken: String, configuration: AccessConfiguration, now: Date) async throws -> VerifiedIdentityToken {
        guard compactToken.count <= 16_000 else { throw AuthenticationRejected() }
        guard JWTCompact.algorithm(compactToken) == "RS256" else { throw AuthenticationRejected() }
        let payload: EntraIDTokenPayload
        do {
            let collection = try await keys.keyCollection(for: configuration)
            payload = try await collection.verify(compactToken, as: EntraIDTokenPayload.self)
        } catch {
            throw AuthenticationRejected()
        }
        let claims = JWTCompact.stringClaims(compactToken)
        return try EntraTokenPolicy.enforce(
            payload: payload,
            configuration: configuration,
            now: now,
            stringClaims: claims
        )
    }
}

enum JWTCompact {
    static func algorithm(_ compactToken: String) -> String? {
        let parts = compactToken.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3, let header = decodePart(String(parts[0])) else { return nil }
        guard let object = try? JSONSerialization.jsonObject(with: header) as? [String: Any] else { return nil }
        return object["alg"] as? String
    }

    static func stringClaims(_ compactToken: String) -> [String: String] {
        let parts = compactToken.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3, let payload = decodePart(String(parts[1])) else { return [:] }
        guard let object = try? JSONSerialization.jsonObject(with: payload) as? [String: Any] else { return [:] }
        var claims: [String: String] = [:]
        for (key, value) in object.sorted(by: { $0.key < $1.key }) {
            guard claims.count < 40, key.count <= 128, let text = value as? String, text.count <= 512 else {
                continue
            }
            claims[key] = text
        }
        return claims
    }

    private static func decodePart(_ value: String) -> Data? {
        var converted = value.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        let remainder = converted.count % 4
        if remainder != 0 {
            converted.append(String(repeating: "=", count: 4 - remainder))
        }
        return Data(base64Encoded: converted)
    }
}

protocol JWKSFetching: Sendable {
    func fetch(_ url: URL) async throws -> String
}

struct URLSessionJWKSFetcher: JWKSFetching {
    func fetch(_ url: URL) async throws -> String {
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw AuthenticationRejected()
        }
        guard data.count <= 1_000_000, let body = String(data: data, encoding: .utf8), !body.isEmpty else {
            throw AuthenticationRejected()
        }
        return body
    }
}

actor JWKSCache {
    struct Entry {
        let json: String
        let fetchedAt: Date
    }

    private var entries: [String: Entry] = [:]
    private let ttl: TimeInterval
    private let now: @Sendable () -> Date

    init(ttl: TimeInterval = 3600, now: @escaping @Sendable () -> Date = { Date() }) {
        self.ttl = ttl
        self.now = now
    }

    func json(for url: URL, fetcher: any JWKSFetching) async throws -> String {
        let key = url.absoluteString
        if let entry = entries[key], now().timeIntervalSince(entry.fetchedAt) < ttl {
            return entry.json
        }
        let json = try await fetcher.fetch(url)
        guard json.utf8.count <= 1_000_000 else { throw AuthenticationRejected() }
        entries[key] = Entry(json: json, fetchedAt: now())
        return json
    }
}

enum JWKSLocation {
    static func url(for configuration: AccessConfiguration) throws -> URL {
        if let configured = configuration.entraJWKSURL {
            return configured
        }
        guard let tenantID = configuration.entraTenantID,
              let url = URL(string: "https://login.microsoftonline.com/\(tenantID)/discovery/v2.0/keys")
        else {
            throw AuthenticationRejected()
        }
        return url
    }
}

struct EntraJWKSKeyProvider: JWTKeyCollectionProviding {
    let fetcher: any JWKSFetching
    let cache: JWKSCache

    init(fetcher: any JWKSFetching = URLSessionJWKSFetcher(), cache: JWKSCache = JWKSCache()) {
        self.fetcher = fetcher
        self.cache = cache
    }

    func keyCollection(for configuration: AccessConfiguration) async throws -> JWTKeyCollection {
        do {
            let url = try JWKSLocation.url(for: configuration)
            let json = try await cache.json(for: url, fetcher: fetcher)
            return try await JWTKeyCollection().add(jwksJSON: json)
        } catch {
            throw AuthenticationRejected()
        }
    }
}

struct StaticKeyProvider: JWTKeyCollectionProviding {
    let collection: JWTKeyCollection

    func keyCollection(for configuration: AccessConfiguration) async throws -> JWTKeyCollection {
        collection
    }
}
