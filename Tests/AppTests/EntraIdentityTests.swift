@testable import App
import JWTKit
import XCTest
import _CryptoExtras

final class EntraIdentityTests: XCTestCase {
    func testStringAudienceDecodesAndEncodes() throws {
        let decoded = try JSONDecoder().decode(StringOrStrings.self, from: Data(#""api://client""#.utf8))
        XCTAssertEqual(decoded.values, ["api://client"])
        let encoded = try JSONEncoder().encode(StringOrStrings(["one"]))
        XCTAssertEqual(String(decoding: encoded, as: UTF8.self), #""one""#)
    }

    func testPolicyAcceptsEitherCommercialIssuerWithinSkew() throws {
        let configuration = try AccessFixtures.configuration(AccessFixtures.staging())
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let v1 = payload(
            iss: "https://sts.windows.net/\(AccessFixtures.tenant)/",
            exp: now.addingTimeInterval(-30)
        )
        let verified = try EntraTokenPolicy.enforce(payload: v1, configuration: configuration, now: now, stringClaims: [:])
        XCTAssertEqual(verified.subject, "user-1")
        XCTAssertEqual(verified.audience, AccessFixtures.client)

        let expired = payload(exp: now.addingTimeInterval(-120))
        XCTAssertThrowsError(
            try EntraTokenPolicy.enforce(payload: expired, configuration: configuration, now: now, stringClaims: [:])
        )
        let tooEarly = payload(exp: now.addingTimeInterval(600), nbf: now.addingTimeInterval(120))
        XCTAssertThrowsError(
            try EntraTokenPolicy.enforce(payload: tooEarly, configuration: configuration, now: now, stringClaims: [:])
        )
    }

    func testPolicyRejectsWrongTenantAudienceIssuerAndMissingSubject() throws {
        let configuration = try AccessFixtures.configuration(AccessFixtures.staging())
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let bad: [EntraIDTokenPayload] = [
            payload(exp: now.addingTimeInterval(60), tid: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"),
            payload(exp: now.addingTimeInterval(60), aud: ["other-audience"]),
            payload(iss: "https://attacker.example/\(AccessFixtures.tenant)/v2.0", exp: now.addingTimeInterval(60)),
            payload(exp: now.addingTimeInterval(60), oid: nil, sub: nil),
        ]
        for candidate in bad {
            XCTAssertThrowsError(
                try EntraTokenPolicy.enforce(payload: candidate, configuration: configuration, now: now, stringClaims: [:])
            )
        }
    }

    func testPrincipalHeadersAreCorroborationOnly() throws {
        let token = VerifiedIdentityToken(
            subject: "user-1",
            tenantID: AccessFixtures.tenant,
            audience: AccessFixtures.client,
            name: "User",
            stringClaims: ["oid": "user-1"]
        )
        let agreed = try PrincipalAgreement.agree(
            token: token,
            headers: PresentedIdentityHeaders(principalID: "user-1", identityProvider: "aad", principalBlob: nil)
        )
        XCTAssertEqual(agreed.subject, "user-1")
        XCTAssertEqual(agreed.identityProvider, "aad")

        XCTAssertThrowsError(
            try PrincipalAgreement.agree(
                token: token,
                headers: PresentedIdentityHeaders(principalID: "other-user", identityProvider: nil, principalBlob: nil)
            )
        )
        XCTAssertThrowsError(
            try PrincipalAgreement.agree(
                token: token,
                headers: PresentedIdentityHeaders(principalID: nil, identityProvider: "google", principalBlob: nil)
            )
        )

        let mismatchedTenant = #"{"auth_typ":"aad","claims":[{"typ":"tid","val":"other"}]}"#
        XCTAssertThrowsError(
            try PrincipalAgreement.agree(
                token: token,
                headers: PresentedIdentityHeaders(
                    principalID: nil,
                    identityProvider: nil,
                    principalBlob: Data(mismatchedTenant.utf8).base64EncodedString()
                )
            )
        )
        XCTAssertThrowsError(
            try PrincipalAgreement.agree(
                token: token,
                headers: PresentedIdentityHeaders(principalID: nil, identityProvider: nil, principalBlob: "%%%")
            )
        )
    }

    func testVerifierChecksRS256SignatureAndRejectsNoneAlgorithm() async throws {
        let configuration = try AccessFixtures.configuration(AccessFixtures.staging())
        let primary = try Insecure.RSA.PrivateKey(backing: _RSA.Signing.PrivateKey(keySize: .bits2048))
        let other = try Insecure.RSA.PrivateKey(backing: _RSA.Signing.PrivateKey(keySize: .bits2048))
        let keys = JWTKeyCollection()
        await keys.add(rsa: primary, digestAlgorithm: .sha256, kid: "test")
        let wrongKeys = JWTKeyCollection()
        await wrongKeys.add(rsa: other, digestAlgorithm: .sha256, kid: "test")

        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let claims = payload(exp: now.addingTimeInterval(3600))
        let token = try await keys.sign(claims, kid: "test")
        let verifier = EntraIDTokenVerifier(keys: StaticKeyProvider(collection: keys))
        let verified = try await verifier.verify(compactToken: token, configuration: configuration, now: now)
        XCTAssertEqual(verified.subject, "user-1")
        XCTAssertEqual(verified.stringClaims["tid"], AccessFixtures.tenant)

        let wrong = EntraIDTokenVerifier(keys: StaticKeyProvider(collection: wrongKeys))
        do {
            _ = try await wrong.verify(compactToken: token, configuration: configuration, now: now)
            XCTFail("signature from a different key was accepted")
        } catch is AuthenticationRejected {
        }

        let none = noneAlgorithmToken()
        do {
            _ = try await verifier.verify(compactToken: none, configuration: configuration, now: now)
            XCTFail("alg=none was accepted")
        } catch is AuthenticationRejected {
        }
    }

    func testJWKSCacheDoesNotRefetchInsideTTLAndFailsClosedOnBadJSON() async throws {
        let clock = MutableClock(date: Date(timeIntervalSince1970: 1_700_000_000))
        let cache = JWKSCache(ttl: 60, now: { clock.date })
        let fetcher = CountingFetcher(body: #"{"keys":[]}"#)
        let url = URL(string: "https://login.microsoftonline.com/\(AccessFixtures.tenant)/discovery/v2.0/keys")!
        _ = try await cache.json(for: url, fetcher: fetcher)
        _ = try await cache.json(for: url, fetcher: fetcher)
        XCTAssertEqual(fetcher.calls, 1)
        clock.date = clock.date.addingTimeInterval(61)
        _ = try await cache.json(for: url, fetcher: fetcher)
        XCTAssertEqual(fetcher.calls, 2)

        let configuration = try AccessFixtures.configuration(AccessFixtures.staging())
        let provider = EntraJWKSKeyProvider(fetcher: CountingFetcher(body: "not-json"), cache: JWKSCache())
        let verifier = EntraIDTokenVerifier(keys: provider)
        let header = Data(#"{"alg":"RS256"}"#.utf8).base64EncodedString()
        let body = Data("{}".utf8).base64EncodedString()
        do {
            _ = try await verifier.verify(compactToken: "\(header).\(body).sig", configuration: configuration, now: Date())
            XCTFail("invalid JWKS was accepted")
        } catch is AuthenticationRejected {
        }
    }

    private func payload(
        iss: String? = nil,
        exp: Date,
        nbf: Date? = nil,
        aud: [String]? = nil,
        tid: String? = AccessFixtures.tenant,
        oid: String? = "user-1",
        sub: String? = nil
    ) -> EntraIDTokenPayload {
        EntraIDTokenPayload(
            iss: iss ?? "https://login.microsoftonline.com/\(AccessFixtures.tenant)/v2.0",
            aud: StringOrStrings(aud ?? [AccessFixtures.client]),
            exp: ExpirationClaim(value: exp),
            nbf: nbf.map { NotBeforeClaim(value: $0) },
            sub: sub.map { SubjectClaim(value: $0) },
            oid: oid,
            tid: tid,
            name: "User",
            preferredUsername: "user@example.com"
        )
    }

    private func noneAlgorithmToken() -> String {
        func part(_ json: String) -> String {
            Data(json.utf8).base64EncodedString()
                .replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "=", with: "")
        }
        let payload = """
        {"iss":"https://login.microsoftonline.com/\(AccessFixtures.tenant)/v2.0","aud":"\(AccessFixtures.client)","exp":2000000000,"tid":"\(AccessFixtures.tenant)","oid":"user-1"}
        """
        return part(#"{"alg":"none","typ":"JWT"}"#) + "." + part(payload) + "."
    }
}

private final class MutableClock: @unchecked Sendable {
    var date: Date
    init(date: Date) { self.date = date }
}

private final class CountingFetcher: JWKSFetching, @unchecked Sendable {
    var calls = 0
    let body: String
    init(body: String) { self.body = body }
    func fetch(_ url: URL) async throws -> String {
        calls += 1
        return body
    }
}
