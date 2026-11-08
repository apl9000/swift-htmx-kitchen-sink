import Vapor

protocol AccessAuthorizer: Sendable {
    func authorize(_ principal: AccessPrincipal, for request: Request) async throws
}

struct AnyAuthenticatedPrincipal: AccessAuthorizer {
    func authorize(_ principal: AccessPrincipal, for request: Request) async throws {}
}

struct AccessContext: Equatable, Sendable {
    var mode: AppRuntimeMode
    var principal: AccessPrincipal?
}

private struct AccessContextKey: StorageKey {
    typealias Value = AccessContext
}

private struct AccessConfigurationKey: StorageKey {
    typealias Value = AccessConfiguration
}

final class IDTokenVerifierBox: Sendable {
    let verifier: any IDTokenVerifying

    init(_ verifier: any IDTokenVerifying) {
        self.verifier = verifier
    }
}

private struct IDTokenVerifierKey: StorageKey {
    typealias Value = IDTokenVerifierBox
}

final class AccessAuthorizerBox: Sendable {
    let authorizer: any AccessAuthorizer

    init(_ authorizer: any AccessAuthorizer) {
        self.authorizer = authorizer
    }
}

private struct AccessAuthorizerKey: StorageKey {
    typealias Value = AccessAuthorizerBox
}

extension Application {
    var accessConfiguration: AccessConfiguration? {
        get { storage[AccessConfigurationKey.self] }
        set { storage[AccessConfigurationKey.self] = newValue }
    }

    var idTokenVerifier: (any IDTokenVerifying)? {
        get { storage[IDTokenVerifierKey.self]?.verifier }
        set {
            if let newValue {
                storage[IDTokenVerifierKey.self] = IDTokenVerifierBox(newValue)
            } else {
                storage[IDTokenVerifierKey.self] = nil
            }
        }
    }

    var accessAuthorizer: any AccessAuthorizer {
        get { storage[AccessAuthorizerKey.self]?.authorizer ?? AnyAuthenticatedPrincipal() }
        set { storage[AccessAuthorizerKey.self] = AccessAuthorizerBox(newValue) }
    }
}

extension Request {
    var accessContext: AccessContext {
        get {
            storage[AccessContextKey.self]
                ?? AccessContext(mode: application.accessConfiguration?.mode ?? .local, principal: nil)
        }
        set { storage[AccessContextKey.self] = newValue }
    }
}

enum AccessEnvironment {
    static func current() -> [String: String] {
        let keys = [
            "APP_RUNTIME_MODE",
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
        ] + AccessConfiguration.platformEnvironmentKeys
        var values: [String: String] = [:]
        for key in keys {
            if let value = Environment.get(key) {
                values[key] = value
            }
        }
        return values
    }
}

private enum GateFailure: Error {
    case misdirected
    case unauthorized(String)
    case forbidden

    var logName: String {
        switch self {
        case .misdirected:
            return "host"
        case .unauthorized(let reason):
            return reason
        case .forbidden:
            return "authorizer"
        }
    }

    var response: Response {
        switch self {
        case .misdirected:
            return Self.text(.misdirectedRequest, "misdirected")
        case .unauthorized:
            return Self.text(.unauthorized, "unauthorized")
        case .forbidden:
            return Self.text(.forbidden, "forbidden")
        }
    }

    private static func text(_ status: HTTPResponseStatus, _ body: String) -> Response {
        let response = Response(status: status)
        response.headers.contentType = .plainText
        response.body = .init(string: body)
        return response
    }
}

struct AccessGateMiddleware: AsyncMiddleware {
    func respond(to request: Request, chainingTo next: AsyncResponder) async throws -> Response {
        guard let configuration = request.application.accessConfiguration else {
            request.logger.error("Access configuration is missing")
            return Response(status: .internalServerError)
        }

        if request.url.path == "/health", request.method == .GET || request.method == .HEAD {
            let response = Response(status: .ok)
            response.headers.contentType = .plainText
            if request.method == .GET {
                response.body = .init(string: "ok")
            }
            return response
        }

        switch configuration.mode {
        case .local:
            request.accessContext = AccessContext(mode: .local, principal: nil)
            return try await next.respond(to: request)
        case .staging, .production:
            do {
                let principal = try await authenticate(request, configuration: configuration)
                request.accessContext = AccessContext(mode: configuration.mode, principal: principal)
                return try await next.respond(to: request)
            } catch let failure as GateFailure {
                request.logger.warning("Access rejected (\(failure.logName))")
                return failure.response
            } catch {
                request.logger.warning("Access rejected (token)")
                return GateFailure.unauthorized("token").response
            }
        }
    }

    private func authenticate(_ request: Request, configuration: AccessConfiguration) async throws -> AccessPrincipal {
        let host = try header(request, "host", duplicate: .misdirected)
        let forwarded = try header(request, "x-forwarded-host", duplicate: .misdirected)
        guard HostName.allows(hostHeader: host, forwardedHost: forwarded, configuration: configuration) else {
            throw GateFailure.misdirected
        }

        if configuration.mode == .production {
            try verifyOrigin(request, configuration: configuration)
        }

        guard let verifier = request.application.idTokenVerifier else {
            throw GateFailure.unauthorized("token")
        }
        guard let compactToken = try header(request, "x-ms-token-aad-id-token", duplicate: .unauthorized("token")) else {
            throw GateFailure.unauthorized("token")
        }
        let verified: VerifiedIdentityToken
        do {
            verified = try await verifier.verify(
                compactToken: compactToken,
                configuration: configuration,
                now: Date()
            )
        } catch {
            throw GateFailure.unauthorized("token")
        }

        let headers = PresentedIdentityHeaders(
            principalID: try header(request, "x-ms-client-principal-id", duplicate: .unauthorized("token")),
            principalName: try header(request, "x-ms-client-principal-name", duplicate: .unauthorized("token")),
            identityProvider: try header(request, "x-ms-client-principal-idp", duplicate: .unauthorized("token")),
            principalBlob: try header(request, "x-ms-client-principal", duplicate: .unauthorized("token"))
        )
        let principal: AccessPrincipal
        do {
            principal = try PrincipalAgreement.agree(token: verified, headers: headers)
        } catch {
            throw GateFailure.unauthorized("token")
        }

        do {
            try await request.application.accessAuthorizer.authorize(principal, for: request)
        } catch is AccessDenied {
            throw GateFailure.forbidden
        } catch {
            throw GateFailure.forbidden
        }
        return principal
    }

    private func verifyOrigin(_ request: Request, configuration: AccessConfiguration) throws {
        guard let frontDoorID = configuration.frontDoorID, let secret = configuration.originAuthSecret else {
            throw GateFailure.unauthorized("origin")
        }
        guard let presentedID = try header(request, "x-azure-fdid", duplicate: .unauthorized("origin"))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased(),
            presentedID.range(
                of: #"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"#,
                options: .regularExpression
            ) != nil,
            constantTimeEquals(presentedID, frontDoorID)
        else {
            throw GateFailure.unauthorized("origin")
        }
        guard let presentedSecret = try header(request, configuration.originAuthHeader, duplicate: .unauthorized("origin")),
              constantTimeEquals(presentedSecret, secret)
        else {
            throw GateFailure.unauthorized("origin")
        }
    }

    private func header(_ request: Request, _ name: String, duplicate: GateFailure) throws -> String? {
        let values = request.headers[name]
        if values.isEmpty { return nil }
        guard values.count == 1, let value = values.first, !value.isEmpty else {
            throw duplicate
        }
        return value
    }
}

func constantTimeEquals(_ lhs: String, _ rhs: String) -> Bool {
    let left = Array(lhs.utf8)
    let right = Array(rhs.utf8)
    var difference = left.count ^ right.count
    let count = max(left.count, right.count)
    if count == 0 { return difference == 0 }
    for index in 0..<count {
        let leftByte = index < left.count ? left[index] : 0
        let rightByte = index < right.count ? right[index] : 0
        difference |= Int(leftByte ^ rightByte)
    }
    return difference == 0
}

struct StagingPrivacyMiddleware: AsyncMiddleware {
    func respond(to request: Request, chainingTo next: AsyncResponder) async throws -> Response {
        let response = try await next.respond(to: request)
        guard request.application.accessConfiguration?.mode == .staging else {
            return response
        }
        response.headers.replaceOrAdd(name: "X-Robots-Tag", value: "noindex, nofollow")
        if isHTMLOrAsset(request: request, response: response) {
            response.headers.replaceOrAdd(name: .cacheControl, value: "private, no-store")
        }
        return response
    }

    private func isHTMLOrAsset(request: Request, response: Response) -> Bool {
        if let media = response.headers.contentType {
            if media.type == "text" && (media.subType == "html" || media.subType == "css") {
                return true
            }
            if media.type == "image" || media.type == "font" {
                return true
            }
            if media.subType == "javascript" {
                return true
            }
        }
        let path = request.url.path.lowercased()
        let suffixes = [".css", ".js", ".map", ".png", ".jpg", ".jpeg", ".gif", ".webp", ".svg", ".ico", ".woff", ".woff2", ".ttf", ".eot"]
        return suffixes.contains { path.hasSuffix($0) }
    }
}
