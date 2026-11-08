@testable import App
import XCTest

final class AccessConfigurationTests: XCTestCase {
    func testDevelopmentWithoutModeIsLocal() throws {
        let configuration = try AccessConfiguration.load(from: [:], vaporEnvironmentName: "development")
        XCTAssertEqual(configuration.mode, .local)
        XCTAssertNil(configuration.publicHost)
        XCTAssertNil(configuration.originAuthSecret)
    }

    func testTestingWithoutModeIsLocal() throws {
        let configuration = try AccessConfiguration.load(from: [:], vaporEnvironmentName: "testing")
        XCTAssertEqual(configuration.mode, .local)
    }

    func testVaporProductionWithoutModeFailsClosed() {
        XCTAssertThrowsError(try AccessConfiguration.load(from: [:], vaporEnvironmentName: "production")) { error in
            XCTAssertTrue(String(describing: error).contains("APP_RUNTIME_MODE"))
        }
    }

    func testLocalModeRejectsAzurePlatformMarkersAndDeploySettings() {
        XCTAssertThrowsError(
            try AccessConfiguration.load(
                from: ["APP_RUNTIME_MODE": "local", "CONTAINER_APP_NAME": "demo"],
                vaporEnvironmentName: "development"
            )
        )
        XCTAssertThrowsError(
            try AccessConfiguration.load(
                from: ["CONTAINER_APP_REVISION": "demo--abc"],
                vaporEnvironmentName: "development"
            )
        )
        XCTAssertThrowsError(
            try AccessConfiguration.load(
                from: ["PUBLIC_HOST": "example.com"],
                vaporEnvironmentName: "development"
            )
        )
    }

    func testStagingNormalizesTrailingDotAndDoesNotDescribeSecrets() throws {
        var environment = AccessFixtures.staging(host: "Staging.Example.COM.")
        environment["ORIGIN_HOST"] = "origin.example.com."
        let configuration = try AccessConfiguration.load(from: environment, vaporEnvironmentName: "production")
        XCTAssertEqual(configuration.mode, .staging)
        XCTAssertEqual(configuration.publicHost, "staging.example.com")
        XCTAssertEqual(configuration.originHost, "origin.example.com")
        XCTAssertEqual(configuration.entraAudience, AccessFixtures.client)
        XCTAssertEqual(configuration.acceptedIssuers.count, 2)
        XCTAssertNil(configuration.frontDoorID)
        XCTAssertNil(configuration.originAuthSecret)
        XCTAssertFalse(configuration.description.contains("secret"))
    }

    func testProductionRequiresDistinctOriginProof() throws {
        let configuration = try AccessConfiguration.load(from: AccessFixtures.production(), vaporEnvironmentName: "production")
        XCTAssertEqual(configuration.mode, .production)
        XCTAssertEqual(configuration.frontDoorID, AccessFixtures.frontDoor)
        XCTAssertEqual(configuration.originAuthHeader, AccessConfiguration.originAuthHeaderDefault)
        XCTAssertFalse(configuration.description.contains(AccessFixtures.originSecret))
    }

    func testRejectsIncompleteOrMixedModes() {
        let rejected: [[String: String]] = [
            ["APP_RUNTIME_MODE": "prod"],
            ["APP_RUNTIME_MODE": "staging"],
            ["APP_RUNTIME_MODE": "staging", "PUBLIC_HOST": "https://example.com", "ENTRA_TENANT_ID": AccessFixtures.tenant, "ENTRA_CLIENT_ID": AccessFixtures.client],
            ["APP_RUNTIME_MODE": "staging", "PUBLIC_HOST": "example.com:443", "ENTRA_TENANT_ID": AccessFixtures.tenant, "ENTRA_CLIENT_ID": AccessFixtures.client],
            ["APP_RUNTIME_MODE": "staging", "PUBLIC_HOST": "example.com.", "ENTRA_TENANT_ID": "00000000-0000-0000-0000-000000000000", "ENTRA_CLIENT_ID": AccessFixtures.client],
            ["APP_RUNTIME_MODE": "staging", "PUBLIC_HOST": "example.com", "ENTRA_TENANT_ID": AccessFixtures.tenant, "ENTRA_CLIENT_ID": "not-a-guid"],
            ["APP_RUNTIME_MODE": "staging", "PUBLIC_HOST": "example.com", "ENTRA_TENANT_ID": AccessFixtures.tenant, "ENTRA_CLIENT_ID": AccessFixtures.client, "ENTRA_AUDIENCE": "api://client id"],
            ["APP_RUNTIME_MODE": "staging", "PUBLIC_HOST": "example.com", "ENTRA_TENANT_ID": AccessFixtures.tenant, "ENTRA_CLIENT_ID": AccessFixtures.client, "FRONTDOOR_ID": AccessFixtures.frontDoor],
            ["APP_RUNTIME_MODE": "staging", "PUBLIC_HOST": "example.com", "ENTRA_TENANT_ID": AccessFixtures.tenant, "ENTRA_CLIENT_ID": AccessFixtures.client, "ORIGIN_AUTH_SECRET": AccessFixtures.originSecret],
            ["APP_RUNTIME_MODE": "production", "PUBLIC_HOST": "example.com", "ENTRA_TENANT_ID": AccessFixtures.tenant, "ENTRA_CLIENT_ID": AccessFixtures.client],
            ["APP_RUNTIME_MODE": "production", "PUBLIC_HOST": "example.com", "ENTRA_TENANT_ID": AccessFixtures.tenant, "ENTRA_CLIENT_ID": AccessFixtures.client, "FRONTDOOR_ID": AccessFixtures.frontDoor, "ORIGIN_AUTH_SECRET": "short-secret"],
            ["APP_RUNTIME_MODE": "production", "PUBLIC_HOST": "example.com", "ENTRA_TENANT_ID": AccessFixtures.tenant, "ENTRA_CLIENT_ID": AccessFixtures.client, "FRONTDOOR_ID": AccessFixtures.frontDoor, "ORIGIN_AUTH_SECRET": String(repeating: "changeme", count: 5)],
            ["APP_RUNTIME_MODE": "production", "PUBLIC_HOST": "example.com", "ENTRA_TENANT_ID": AccessFixtures.tenant, "ENTRA_CLIENT_ID": AccessFixtures.client, "FRONTDOOR_ID": AccessFixtures.frontDoor, "ORIGIN_AUTH_SECRET": AccessFixtures.originSecret, "ORIGIN_AUTH_HEADER": "Authorization"],
            ["APP_RUNTIME_MODE": "production", "PUBLIC_HOST": "example.com", "ENTRA_TENANT_ID": AccessFixtures.tenant, "ENTRA_CLIENT_ID": AccessFixtures.client, "FRONTDOOR_ID": AccessFixtures.frontDoor, "ORIGIN_AUTH_SECRET": AccessFixtures.originSecret, "ENTRA_ISSUER": "http://login.microsoftonline.com/\(AccessFixtures.tenant)/v2.0"],
            ["APP_RUNTIME_MODE": "production", "PUBLIC_HOST": "example.com", "ENTRA_TENANT_ID": AccessFixtures.tenant, "ENTRA_CLIENT_ID": AccessFixtures.client, "FRONTDOOR_ID": AccessFixtures.frontDoor, "ORIGIN_AUTH_SECRET": AccessFixtures.originSecret, "ENTRA_ISSUER": "https://login.microsoftonline.us/\(AccessFixtures.tenant)/v2.0"],
            ["APP_RUNTIME_MODE": "staging", "PUBLIC_HOST": "example.com", "ENTRA_TENANT_ID": AccessFixtures.tenant, "ENTRA_CLIENT_ID": AccessFixtures.client, "ENTRA_JWKS_URL": "http://login.microsoftonline.com/\(AccessFixtures.tenant)/keys"],
        ]

        for environment in rejected {
            XCTAssertThrowsError(try AccessConfiguration.load(from: environment, vaporEnvironmentName: "development"))
        }
    }

    func testNationalCloudIssuerRequiresExplicitJWKS() throws {
        var environment = AccessFixtures.production()
        environment["ENTRA_ISSUER"] = "https://login.microsoftonline.us/\(AccessFixtures.tenant)/v2.0"
        environment["ENTRA_JWKS_URL"] = "https://login.microsoftonline.us/\(AccessFixtures.tenant)/discovery/v2.0/keys"
        let configuration = try AccessConfiguration.load(from: environment, vaporEnvironmentName: "production")
        XCTAssertEqual(configuration.acceptedIssuers, ["https://login.microsoftonline.us/\(AccessFixtures.tenant)/v2.0"])
        XCTAssertEqual(configuration.entraJWKSURL?.host, "login.microsoftonline.us")
    }
}

enum AccessFixtures {
    static let tenant = "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
    static let client = "11111111-2222-3333-4444-555555555555"
    static let frontDoor = "99999999-8888-7777-6666-555555555555"
    static let originSecret = "origin-auth-value-0123456789abcd"

    static func staging(host: String = "staging.example.com") -> [String: String] {
        [
            "APP_RUNTIME_MODE": "staging",
            "PUBLIC_HOST": host,
            "ENTRA_TENANT_ID": tenant,
            "ENTRA_CLIENT_ID": client,
        ]
    }

    static func production() -> [String: String] {
        var environment = staging(host: "app.example.com")
        environment["APP_RUNTIME_MODE"] = "production"
        environment["ORIGIN_HOST"] = "app.internal.azurecontainerapps.io"
        environment["FRONTDOOR_ID"] = frontDoor
        environment["ORIGIN_AUTH_SECRET"] = originSecret
        return environment
    }

    static func configuration(_ environment: [String: String]) throws -> AccessConfiguration {
        try AccessConfiguration.load(from: environment, vaporEnvironmentName: "testing")
    }
}
