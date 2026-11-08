@testable import App
import XCTVapor

final class AccessGateTests: XCTestCase {
    func testLocalModeIgnoresSpoofedPlatformHeaders() async throws {
        try await withApp([:]) { app in
            app.get("access-probe") { request -> String in
                request.accessContext.principal?.subject ?? "anonymous"
            }
            try await app.test(.GET, "access-probe", beforeRequest: { request async in
                self.productionHeaders(&request)
            }, afterResponse: { response async in
                XCTAssertEqual(response.status, .ok)
                XCTAssertEqual(response.body.string, "anonymous")
                XCTAssertNil(response.headers.first(name: "X-Robots-Tag"))
            })
        }
    }

    func testHealthIsTheOnlyAnonymousRoute() async throws {
        try await withApp(AccessFixtures.staging()) { app in
            try await app.test(.GET, "health", beforeRequest: { request async in
                request.headers.replaceOrAdd(name: .host, value: "evil.example.")
            }, afterResponse: { response async in
                XCTAssertEqual(response.status, .ok)
                XCTAssertEqual(response.body.string, "ok")
                XCTAssertEqual(response.headers.first(name: "X-Robots-Tag"), "noindex, nofollow")
                XCTAssertNil(response.headers.first(name: .cacheControl))
            })
            try await app.test(.HEAD, "health") { response async in
                XCTAssertEqual(response.status, .ok)
                XCTAssertEqual(response.body.string, "")
            }
            for path in ["health", "healthz", "hello", "css/styles.css"] {
                try await app.test(.POST, path, beforeRequest: { request async in
                    request.headers.replaceOrAdd(name: .host, value: "staging.example.com")
                }, afterResponse: { response async in
                    XCTAssertEqual(response.status, .unauthorized, path)
                })
            }
            try await app.test(.GET, "hello", beforeRequest: { request async in
                request.headers.replaceOrAdd(name: .host, value: "staging.example.com")
            }, afterResponse: { response async in
                XCTAssertEqual(response.status, .unauthorized)
                XCTAssertEqual(response.body.string, "unauthorized")
                XCTAssertEqual(response.headers.first(name: "X-Robots-Tag"), "noindex, nofollow")
            })
            try await app.test(.GET, "css/styles.css", beforeRequest: { request async in
                request.headers.replaceOrAdd(name: .host, value: "staging.example.com")
            }, afterResponse: { response async in
                XCTAssertEqual(response.status, .unauthorized)
            })
        }
    }

    func testStagingBrowserAccessTrustsOnlyAMatchingToken() async throws {
        try await withApp(AccessFixtures.staging()) { app in
            app.idTokenVerifier = self.verifier()
            app.get("access-probe") { request -> String in
                request.accessContext.principal?.subject ?? "anonymous"
            }

            try await app.test(.GET, "access-probe", beforeRequest: { request async in
                self.stagingHeaders(&request, host: "Staging.Example.com.")
            }, afterResponse: { response async in
                XCTAssertEqual(response.status, .ok)
                XCTAssertEqual(response.body.string, "user-1")
            })

            try await app.test(.GET, "/", beforeRequest: { request async in
                self.stagingHeaders(&request)
            }, afterResponse: { response async in
                XCTAssertEqual(response.status, .ok)
                XCTAssertEqual(response.headers.contentType?.subType, "html")
                XCTAssertEqual(response.headers.first(name: "X-Robots-Tag"), "noindex, nofollow")
                XCTAssertEqual(response.headers.first(name: .cacheControl), "private, no-store")
            })

            try await app.test(.GET, "css/styles.css", beforeRequest: { request async in
                self.stagingHeaders(&request)
            }, afterResponse: { response async in
                XCTAssertEqual(response.status, .ok)
                XCTAssertEqual(response.headers.first(name: .cacheControl), "private, no-store")
            })

            try await app.test(.GET, "access-probe", beforeRequest: { request async in
                self.stagingHeaders(&request, principalID: "someone-else")
            }, afterResponse: { response async in
                XCTAssertEqual(response.status, .unauthorized)
            })

            try await app.test(.GET, "access-probe", beforeRequest: { request async in
                self.stagingHeaders(&request, token: "bad-token")
            }, afterResponse: { response async in
                XCTAssertEqual(response.status, .unauthorized)
            })

            try await app.test(.GET, "access-probe", beforeRequest: { request async in
                self.stagingHeaders(&request, host: "staging.example.com.evil.net")
            }, afterResponse: { response async in
                XCTAssertEqual(response.status, .misdirectedRequest)
                XCTAssertEqual(response.body.string, "misdirected")
            })

            try await app.test(.GET, "access-probe", beforeRequest: { request async in
                self.stagingHeaders(&request, host: "staging.example.com..")
            }, afterResponse: { response async in
                XCTAssertEqual(response.status, .misdirectedRequest)
            })
        }
    }

    func testProductionRequiresFrontDoorOriginAuthAndPublicHost() async throws {
        try await withApp(AccessFixtures.production()) { app in
            app.idTokenVerifier = self.verifier()
            app.get("access-probe") { request -> String in
                request.accessContext.principal?.subject ?? "anonymous"
            }

            try await app.test(.GET, "access-probe", beforeRequest: { request async in
                self.productionHeaders(&request, forwarded: "App.Example.com.")
            }, afterResponse: { response async in
                XCTAssertEqual(response.status, .ok)
                XCTAssertEqual(response.body.string, "user-1")
                XCTAssertNil(response.headers.first(name: "X-Robots-Tag"))
            })

            try await app.test(.GET, "/", beforeRequest: { request async in
                self.productionHeaders(&request)
            }, afterResponse: { response async in
                XCTAssertEqual(response.status, .ok)
                XCTAssertNil(response.headers.first(name: .cacheControl))
            })

            try await app.test(.GET, "health") { response async in
                XCTAssertEqual(response.status, .ok)
                XCTAssertEqual(response.body.string, "ok")
            }

            try await app.test(.GET, "access-probe", beforeRequest: { request async in
                self.productionHeaders(&request, includeOrigin: false)
            }, afterResponse: { response async in
                XCTAssertEqual(response.status, .unauthorized)
            })

            try await app.test(.GET, "access-probe", beforeRequest: { request async in
                self.productionHeaders(&request, forwarded: "app.example.com.evil.net.")
            }, afterResponse: { response async in
                XCTAssertEqual(response.status, .misdirectedRequest)
            })

            app.accessAuthorizer = DenyAll()
            try await app.test(.GET, "access-probe", beforeRequest: { request async in
                self.productionHeaders(&request)
            }, afterResponse: { response async in
                XCTAssertEqual(response.status, .forbidden)
                XCTAssertEqual(response.body.string, "forbidden")
            })
        }
    }

    func testBootRefusesImplicitProduction() async throws {
        let app = try await Application.make(.production)
        do {
            try await configure(app, accessEnvironment: [:])
            XCTFail("expected startup to fail closed")
        } catch {
            XCTAssertTrue(String(describing: error).contains("APP_RUNTIME_MODE"))
        }
        try await app.asyncShutdown()
    }

    private func withApp(
        _ environment: [String: String],
        _ body: (Application) async throws -> Void
    ) async throws {
        let app = try await Application.make(.testing)
        do {
            try await configure(app, accessEnvironment: environment)
            try await body(app)
            try await app.autoRevert()
            try await app.asyncShutdown()
        } catch {
            try? await app.asyncShutdown()
            throw error
        }
    }

    private func verifier() -> StaticIDTokenVerifier {
        StaticIDTokenVerifier(
            accepted: "good-token",
            identity: VerifiedIdentityToken(
                subject: "user-1",
                tenantID: AccessFixtures.tenant,
                audience: AccessFixtures.client,
                name: "User One",
                stringClaims: ["oid": "user-1"]
            )
        )
    }

    private func stagingHeaders(
        _ request: inout XCTHTTPRequest,
        host: String = "staging.example.com",
        token: String = "good-token",
        principalID: String? = "user-1"
    ) {
        request.headers.replaceOrAdd(name: .host, value: host)
        request.headers.replaceOrAdd(name: "X-MS-TOKEN-AAD-ID-TOKEN", value: token)
        if let principalID {
            request.headers.replaceOrAdd(name: "X-MS-CLIENT-PRINCIPAL-ID", value: principalID)
        }
    }

    private func productionHeaders(
        _ request: inout XCTHTTPRequest,
        forwarded: String = "app.example.com",
        includeOrigin: Bool = true
    ) {
        request.headers.replaceOrAdd(name: .host, value: "app.internal.azurecontainerapps.io")
        request.headers.replaceOrAdd(name: "X-Forwarded-Host", value: forwarded)
        if includeOrigin {
            request.headers.replaceOrAdd(name: "X-Azure-FDID", value: AccessFixtures.frontDoor)
            request.headers.replaceOrAdd(name: "X-App-Origin-Auth", value: AccessFixtures.originSecret)
        }
        request.headers.replaceOrAdd(name: "X-MS-TOKEN-AAD-ID-TOKEN", value: "good-token")
        request.headers.replaceOrAdd(name: "X-MS-CLIENT-PRINCIPAL-ID", value: "user-1")
        request.headers.replaceOrAdd(name: "X-MS-CLIENT-PRINCIPAL-NAME", value: "Spoofed Admin")
    }
}

private struct StaticIDTokenVerifier: IDTokenVerifying {
    let accepted: String
    let identity: VerifiedIdentityToken

    func verify(compactToken: String, configuration: AccessConfiguration, now: Date) async throws -> VerifiedIdentityToken {
        guard compactToken == accepted else { throw AuthenticationRejected() }
        return identity
    }
}

private struct DenyAll: AccessAuthorizer {
    func authorize(_ principal: AccessPrincipal, for request: Request) async throws {
        throw AccessDenied()
    }
}
