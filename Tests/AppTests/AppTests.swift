@testable import App
import XCTVapor
import Fluent

final class AppTests: XCTestCase {
    var app: Application!
    
    override func setUp() async throws {
        self.app = try await Application.make(.testing)
        try await configure(app)
        try await app.autoMigrate()
    }

    override func tearDown() async throws {
        try await app.autoRevert()
        try await app.asyncShutdown()
        self.app = nil
    }
    
    func testHomePage() async throws {
        try await self.app.test(.GET, "/") { res async in
            XCTAssertEqual(res.status, .ok)
            XCTAssertTrue(res.body.string.contains("Kitchen Sink"))
        }
    }
    
    func testTodosIndex() async throws {
        try await self.app.test(.GET, "todos") { res async in
            XCTAssertEqual(res.status, .ok)
            XCTAssertTrue(res.body.string.contains("Todos"))
        }
    }
    
    func testContactsIndex() async throws {
        try await self.app.test(.GET, "contacts") { res async in
            XCTAssertEqual(res.status, .ok)
            XCTAssertTrue(res.body.string.contains("Contacts"))
        }
    }
    
    func testDemoTabs() async throws {
        try await self.app.test(.GET, "demos/tabs") { res async in
            XCTAssertEqual(res.status, .ok)
            XCTAssertTrue(res.body.string.contains("Tabs"))
        }
    }

    func testDemoModals() async throws {
        try await self.app.test(.GET, "demos/modals") { res async in
            XCTAssertEqual(res.status, .ok)
        }
    }

    func testDemoForms() async throws {
        try await self.app.test(.GET, "demos/forms") { res async in
            XCTAssertEqual(res.status, .ok)
        }
    }
    
    func testDemoToasts() async throws {
        try await self.app.test(.GET, "demos/toasts") { res async in
            XCTAssertEqual(res.status, .ok)
        }
    }
    
    func testTodoCreate() async throws {
        try await self.app.test(.POST, "todos",
            beforeRequest: { req async throws in
                req.headers.contentType = .urlEncodedForm
                try req.content.encode(["title": "Test todo"], as: .urlEncodedForm)
            },
            afterResponse: { res async in
                XCTAssertEqual(res.status, .ok)
                XCTAssertTrue(res.body.string.contains("Test todo"))
            }
        )
    }
}
