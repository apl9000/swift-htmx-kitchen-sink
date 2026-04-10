import Vapor

struct HTMXRequestKey: StorageKey {
    typealias Value = Bool
}

extension Request {
    var isHTMX: Bool {
        get { storage[HTMXRequestKey.self] ?? false }
        set { storage[HTMXRequestKey.self] = newValue }
    }
}

struct HTMXMiddleware: AsyncMiddleware {
    func respond(to request: Request, chainingTo next: AsyncResponder) async throws -> Response {
        request.isHTMX = request.headers.first(name: "HX-Request") == "true"
        return try await next.respond(to: request)
    }
}
