@testable import App
import XCTest

final class HostNameTests: XCTestCase {
    func testNormalizeAcceptsOneTrailingDotAndCase() {
        XCTAssertEqual(HostName.normalize("Example.COM."), "example.com")
        XCTAssertEqual(HostName.normalize("  example.com. "), "example.com")
        XCTAssertEqual(HostName.normalize("app.internal.azurecontainerapps.io"), "app.internal.azurecontainerapps.io")
    }

    func testNormalizeRejectsLookalikesPortsAndExtraDots() {
        XCTAssertNil(HostName.normalize("example.com.."))
        XCTAssertNil(HostName.normalize(".example.com"))
        XCTAssertNil(HostName.normalize("example.com:443"))
        XCTAssertNil(HostName.normalize("example.com/admin"))
        XCTAssertNil(HostName.normalize("user@example.com"))
        XCTAssertNil(HostName.normalize("example.com%2e"))
        XCTAssertNil(HostName.normalize("example.com,evil.com"))
        XCTAssertNil(HostName.normalize("localhost"))
        XCTAssertNil(HostName.normalize("[::1]"))
        XCTAssertNil(HostName.normalize("-bad.example"))
        XCTAssertNil(HostName.normalize("bad-.example"))
        XCTAssertNil(HostName.normalize(""))
        XCTAssertNil(HostName.normalize("exàmple.com."))
    }

    func testAllowlistUsesNormalizedTrailingDot() throws {
        let staging = try AccessFixtures.configuration(AccessFixtures.staging(host: "Example.COM."))
        XCTAssertTrue(HostName.allows(hostHeader: "example.com.", forwardedHost: nil, configuration: staging))
        XCTAssertTrue(HostName.allows(hostHeader: "EXAMPLE.com", forwardedHost: nil, configuration: staging))
        XCTAssertFalse(HostName.allows(hostHeader: "example.com..", forwardedHost: nil, configuration: staging))
        XCTAssertFalse(HostName.allows(hostHeader: "example.com.evil.net.", forwardedHost: nil, configuration: staging))
        XCTAssertFalse(HostName.allows(hostHeader: "notexample.com.", forwardedHost: nil, configuration: staging))
        XCTAssertFalse(HostName.allows(hostHeader: "example.com:443", forwardedHost: nil, configuration: staging))
    }

    func testForwardedHostMustMatchPublicHostAndHostMayBeOrigin() throws {
        let production = try AccessFixtures.configuration(AccessFixtures.production())
        XCTAssertTrue(
            HostName.allows(
                hostHeader: "app.internal.azurecontainerapps.io.",
                forwardedHost: "App.Example.com.",
                configuration: production
            )
        )
        XCTAssertTrue(
            HostName.allows(
                hostHeader: "app.example.com",
                forwardedHost: nil,
                configuration: production
            )
        )
        XCTAssertFalse(
            HostName.allows(
                hostHeader: "app.internal.azurecontainerapps.io",
                forwardedHost: nil,
                configuration: production
            )
        )
        XCTAssertFalse(
            HostName.allows(
                hostHeader: "app.example.com",
                forwardedHost: "app.example.com.evil.net.",
                configuration: production
            )
        )
        XCTAssertFalse(
            HostName.allows(
                hostHeader: "evil.example.",
                forwardedHost: "app.example.com.",
                configuration: production
            )
        )
        XCTAssertFalse(
            HostName.allows(
                hostHeader: "app.example.com",
                forwardedHost: "app.example.com,app.example.com",
                configuration: production
            )
        )
    }
}
