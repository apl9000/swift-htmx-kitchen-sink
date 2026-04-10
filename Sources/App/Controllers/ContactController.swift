import Fluent
import Vapor

struct ContactController: RouteCollection {
    static let pageSize = 10

    func boot(routes: RoutesBuilder) throws {
        let contacts = routes.grouped("contacts")
        contacts.get(use: { try await self.index(req: $0) })
        contacts.get("search", use: { try await self.search(req: $0) })
    }

    func index(req: Request) async throws -> View {
        let page = (try? req.query.get(Int.self, at: "page")) ?? 1
        let contacts = try await Contact.query(on: req.db)
            .sort(\.$lastName)
            .range(((page - 1) * Self.pageSize)..<(page * Self.pageSize))
            .all()
        let total = try await Contact.query(on: req.db).count()
        let hasMore = page * Self.pageSize < total

        if req.isHTMX, page > 1 {
            return try await req.view.render("contacts/rows", ContactsContext(
                contacts: contacts.map { $0.toDTO() },
                page: page,
                hasMore: hasMore,
                query: ""
            ))
        }

        return try await req.view.render("contacts/index", ContactsContext(
            contacts: contacts.map { $0.toDTO() },
            page: page,
            hasMore: hasMore,
            query: "",
            title: "Contacts"
        ))
    }

    func search(req: Request) async throws -> View {
        let query = (try? req.query.get(String.self, at: "q")) ?? ""

        var dbQuery = Contact.query(on: req.db)

        if !query.isEmpty {
            dbQuery = dbQuery.group(.or) { group in
                group.filter(\.$firstName, .custom("LIKE"), "%\(query)%")
                group.filter(\.$lastName, .custom("LIKE"), "%\(query)%")
                group.filter(\.$email, .custom("LIKE"), "%\(query)%")
                group.filter(\.$company, .custom("LIKE"), "%\(query)%")
            }
        }

        let contacts = try await dbQuery
            .sort(\.$lastName)
            .range(0..<Self.pageSize)
            .all()

        let total = try await dbQuery.count()
        let hasMore = Self.pageSize < total

        return try await req.view.render("contacts/rows", ContactsContext(
            contacts: contacts.map { $0.toDTO() },
            page: 1,
            hasMore: hasMore,
            query: query
        ))
    }
}

struct ContactsContext: Content {
    let contacts: [ContactDTO]
    let page: Int
    let hasMore: Bool
    let query: String
    var title: String?
}
