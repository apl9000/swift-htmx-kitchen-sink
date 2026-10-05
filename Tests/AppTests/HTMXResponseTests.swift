@testable import App
import Vapor
import XCTest

final class HTMXResponseTests: XCTestCase {
    func testHTMLResponseSetsContentTypeAndBody() throws {
        let response = try HTMXResponse.html("<p>Updated</p>")

        XCTAssertEqual(response.status, .ok)
        XCTAssertEqual(response.headers.first(name: "Content-Type"), "text/html")
        XCTAssertEqual(response.body.string, "<p>Updated</p>")
        XCTAssertNil(response.headers.first(name: "HX-Trigger"))
    }

    func testTriggerEncodesDynamicMessageAsValidJSON() throws {
        let message = #"It's "ready" — 100%!"#
        let response = try HTMXResponse.html("", trigger: HTMXTrigger(
            showToast: .init(message: message, type: "success"),
            closeModal: true
        ))
        let trigger = try XCTUnwrap(response.headers.first(name: "HX-Trigger"))
        let decoded = try JSONDecoder().decode(DecodedTrigger.self, from: Data(trigger.utf8))

        XCTAssertEqual(decoded.showToast.message, message)
        XCTAssertEqual(decoded.showToast.type, "success")
        XCTAssertTrue(decoded.closeModal)
    }
}

private struct DecodedTrigger: Decodable {
    struct Toast: Decodable {
        let message: String
        let type: String
    }

    let showToast: Toast
    let closeModal: Bool
}
