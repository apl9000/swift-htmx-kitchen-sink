import Fluent

struct SeedContacts: AsyncMigration {
    func prepare(on database: Database) async throws {
        let contacts: [(String, String, String, String, String)] = [
            ("Alice", "Johnson", "alice.johnson@example.com", "(555) 100-0001", "Acme Corp"),
            ("Bob", "Smith", "bob.smith@example.com", "(555) 100-0002", "TechFlow Inc"),
            ("Carol", "Williams", "carol.williams@example.com", "(555) 100-0003", "DataPrime"),
            ("David", "Brown", "david.brown@example.com", "(555) 100-0004", "CloudNine"),
            ("Eva", "Davis", "eva.davis@example.com", "(555) 100-0005", "Acme Corp"),
            ("Frank", "Miller", "frank.miller@example.com", "(555) 100-0006", "SkyNet Labs"),
            ("Grace", "Wilson", "grace.wilson@example.com", "(555) 100-0007", "TechFlow Inc"),
            ("Henry", "Moore", "henry.moore@example.com", "(555) 100-0008", "DataPrime"),
            ("Iris", "Taylor", "iris.taylor@example.com", "(555) 100-0009", "GreenLeaf"),
            ("Jack", "Anderson", "jack.anderson@example.com", "(555) 100-0010", "CloudNine"),
            ("Karen", "Thomas", "karen.thomas@example.com", "(555) 100-0011", "SkyNet Labs"),
            ("Leo", "Jackson", "leo.jackson@example.com", "(555) 100-0012", "BrightStar"),
            ("Maya", "White", "maya.white@example.com", "(555) 100-0013", "Acme Corp"),
            ("Noah", "Harris", "noah.harris@example.com", "(555) 100-0014", "TechFlow Inc"),
            ("Olivia", "Martin", "olivia.martin@example.com", "(555) 100-0015", "DataPrime"),
            ("Paul", "Garcia", "paul.garcia@example.com", "(555) 100-0016", "GreenLeaf"),
            ("Quinn", "Martinez", "quinn.martinez@example.com", "(555) 100-0017", "CloudNine"),
            ("Rose", "Robinson", "rose.robinson@example.com", "(555) 100-0018", "BrightStar"),
            ("Sam", "Clark", "sam.clark@example.com", "(555) 100-0019", "SkyNet Labs"),
            ("Tina", "Rodriguez", "tina.rodriguez@example.com", "(555) 100-0020", "Acme Corp"),
            ("Uma", "Lewis", "uma.lewis@example.com", "(555) 100-0021", "TechFlow Inc"),
            ("Victor", "Lee", "victor.lee@example.com", "(555) 100-0022", "DataPrime"),
            ("Wendy", "Walker", "wendy.walker@example.com", "(555) 100-0023", "GreenLeaf"),
            ("Xavier", "Hall", "xavier.hall@example.com", "(555) 100-0024", "CloudNine"),
            ("Yuki", "Allen", "yuki.allen@example.com", "(555) 100-0025", "BrightStar"),
            ("Zara", "Young", "zara.young@example.com", "(555) 100-0026", "SkyNet Labs"),
            ("Aaron", "King", "aaron.king@example.com", "(555) 100-0027", "Acme Corp"),
            ("Beth", "Wright", "beth.wright@example.com", "(555) 100-0028", "TechFlow Inc"),
            ("Carl", "Lopez", "carl.lopez@example.com", "(555) 100-0029", "DataPrime"),
            ("Diana", "Hill", "diana.hill@example.com", "(555) 100-0030", "GreenLeaf"),
            ("Erik", "Scott", "erik.scott@example.com", "(555) 100-0031", "CloudNine"),
            ("Fiona", "Green", "fiona.green@example.com", "(555) 100-0032", "BrightStar"),
            ("George", "Adams", "george.adams@example.com", "(555) 100-0033", "SkyNet Labs"),
            ("Hannah", "Baker", "hannah.baker@example.com", "(555) 100-0034", "Acme Corp"),
            ("Ivan", "Gonzalez", "ivan.gonzalez@example.com", "(555) 100-0035", "TechFlow Inc"),
            ("Julia", "Nelson", "julia.nelson@example.com", "(555) 100-0036", "DataPrime"),
            ("Kyle", "Carter", "kyle.carter@example.com", "(555) 100-0037", "GreenLeaf"),
            ("Luna", "Mitchell", "luna.mitchell@example.com", "(555) 100-0038", "CloudNine"),
            ("Marco", "Perez", "marco.perez@example.com", "(555) 100-0039", "BrightStar"),
            ("Nina", "Roberts", "nina.roberts@example.com", "(555) 100-0040", "SkyNet Labs"),
            ("Oscar", "Turner", "oscar.turner@example.com", "(555) 100-0041", "Acme Corp"),
            ("Priya", "Phillips", "priya.phillips@example.com", "(555) 100-0042", "TechFlow Inc"),
            ("Reed", "Campbell", "reed.campbell@example.com", "(555) 100-0043", "DataPrime"),
            ("Sage", "Parker", "sage.parker@example.com", "(555) 100-0044", "GreenLeaf"),
            ("Troy", "Evans", "troy.evans@example.com", "(555) 100-0045", "CloudNine"),
            ("Uma", "Edwards", "uma.edwards@example.com", "(555) 100-0046", "BrightStar"),
            ("Vera", "Collins", "vera.collins@example.com", "(555) 100-0047", "SkyNet Labs"),
            ("Wade", "Stewart", "wade.stewart@example.com", "(555) 100-0048", "Acme Corp"),
            ("Xena", "Sanchez", "xena.sanchez@example.com", "(555) 100-0049", "TechFlow Inc"),
            ("Yosef", "Morris", "yosef.morris@example.com", "(555) 100-0050", "DataPrime"),
        ]

        for (first, last, email, phone, company) in contacts {
            let contact = Contact(
                firstName: first,
                lastName: last,
                email: email,
                phone: phone,
                company: company
            )
            try await contact.save(on: database)
        }
    }

    func revert(on database: Database) async throws {
        try await Contact.query(on: database).delete()
    }
}
