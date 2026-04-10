import Fluent

struct CreateContact: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema("contacts")
            .id()
            .field("first_name", .string, .required)
            .field("last_name", .string, .required)
            .field("email", .string, .required)
            .field("phone", .string, .required)
            .field("company", .string, .required)
            .create()
    }

    func revert(on database: Database) async throws {
        try await database.schema("contacts").delete()
    }
}
