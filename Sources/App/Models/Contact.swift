import Fluent
import struct Foundation.UUID

final class Contact: Model, @unchecked Sendable {
    static let schema = "contacts"

    @ID(key: .id)
    var id: UUID?

    @Field(key: "first_name")
    var firstName: String

    @Field(key: "last_name")
    var lastName: String

    @Field(key: "email")
    var email: String

    @Field(key: "phone")
    var phone: String

    @Field(key: "company")
    var company: String

    init() { }

    init(id: UUID? = nil, firstName: String, lastName: String, email: String, phone: String, company: String) {
        self.id = id
        self.firstName = firstName
        self.lastName = lastName
        self.email = email
        self.phone = phone
        self.company = company
    }
}

struct ContactDTO: Content {
    var id: UUID?
    var firstName: String
    var lastName: String
    var email: String
    var phone: String
    var company: String
}

import Vapor

extension Contact {
    func toDTO() -> ContactDTO {
        .init(
            id: self.id,
            firstName: self.firstName,
            lastName: self.lastName,
            email: self.email,
            phone: self.phone,
            company: self.company
        )
    }
}
