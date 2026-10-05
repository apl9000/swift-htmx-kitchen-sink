import Vapor

struct HTMXTrigger: Encodable {
    struct Toast: Encodable {
        let message: String
        let type: String
    }

    let showToast: Toast?
    let closeModal: Bool?

    init(showToast: Toast? = nil, closeModal: Bool? = nil) {
        self.showToast = showToast
        self.closeModal = closeModal
    }
}

enum HTMXResponse {
    static func html(_ body: String, trigger: HTMXTrigger? = nil) throws -> Response {
        let response = Response(status: .ok, body: .init(string: body))
        response.headers.replaceOrAdd(name: "Content-Type", value: "text/html")
        if let trigger {
            try setTrigger(trigger, on: response)
        }
        return response
    }

    static func setTrigger(_ trigger: HTMXTrigger, on response: Response) throws {
        let data = try JSONEncoder().encode(trigger)
        response.headers.replaceOrAdd(
            name: "HX-Trigger",
            value: String(decoding: data, as: UTF8.self)
        )
    }
}
