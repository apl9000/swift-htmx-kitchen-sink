import Fluent
import Vapor

func routes(_ app: Application) throws {
    app.get { req async throws in
        try await req.view.render("index", ["title": "Home Page"])
    }

    app.get("about") { req async throws in
        try await req.view.render("about", ["title": "About Page"])
    }

    app.get("hello") { req async -> String in
        "Hello, world!"
    }

    try app.register(collection: TodoController())
}
