import NIOSSL
import Fluent
import FluentSQLiteDriver
import FluentPostgresDriver
import Leaf
import Vapor

public func configure(_ app: Application) async throws {
    // Default port: 8888
    app.http.server.configuration.port = 8888

    // Static file serving
    app.middleware.use(FileMiddleware(publicDirectory: app.directory.publicDirectory))

    // HTMX request detection
    app.middleware.use(HTMXMiddleware())

    // Database: toggle via DB_TYPE env var (sqlite | postgres)
    let dbType = Environment.get("DB_TYPE") ?? "sqlite"
    if dbType == "postgres" {
        if let url = Environment.get("DATABASE_URL") {
            try app.databases.use(.postgres(url: url), as: .psql)
        } else {
            let host = Environment.get("DB_HOST") ?? "localhost"
            let port = Environment.get("DB_PORT").flatMap(Int.init) ?? 5432
            let user = Environment.get("DB_USER") ?? "vapor"
            let pass = Environment.get("DB_PASS") ?? "vapor"
            let name = Environment.get("DB_NAME") ?? "kitchen_sink"
            app.databases.use(.postgres(
                hostname: host,
                port: port,
                username: user,
                password: pass,
                database: name
            ), as: .psql)
        }
    } else {
        app.databases.use(DatabaseConfigurationFactory.sqlite(.file("db.sqlite")), as: .sqlite)
    }

    // Migrations
    app.migrations.add(CreateTodo())
    app.migrations.add(CreateContact())
    app.migrations.add(SeedContacts())

    // Auto-migrate (idempotent — safe to run every startup)
    try await app.autoMigrate()

    // Leaf templates
    app.views.use(.leaf)

    try routes(app)
}
