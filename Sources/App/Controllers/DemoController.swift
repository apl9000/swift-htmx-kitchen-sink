import Fluent
import Vapor

struct DemoController: RouteCollection {
    func boot(routes: RoutesBuilder) throws {
        let demos = routes.grouped("demos")

        // Demo pages
        demos.get("tabs", use: { try await self.tabs(req: $0) })
        demos.get("tabs", "content", ":tabId", use: { try await self.tabContent(req: $0) })

        demos.get("modals", use: { try await self.modals(req: $0) })
        demos.get("modals", "confirm", use: { try await self.modalConfirm(req: $0) })
        demos.get("modals", "form", use: { try await self.modalForm(req: $0) })
        demos.post("modals", "form", use: { try await self.modalFormSubmit(req: $0) })

        demos.get("forms", use: { try await self.forms(req: $0) })
        demos.post("forms", "validate", use: { try await self.formValidate(req: $0) })

        demos.get("toasts", use: { try await self.toasts(req: $0) })
        demos.post("toasts", "trigger", use: { try await self.toastTrigger(req: $0) })

        demos.get("toggles", use: { try await self.toggles(req: $0) })

        demos.get("progress", use: { try await self.progress(req: $0) })
        demos.post("progress", "start", use: { try await self.progressStart(req: $0) })
        demos.get("progress", "poll", ":taskId", use: { try await self.progressPoll(req: $0) })

        demos.get("bulk-update", use: { try await self.bulkUpdate(req: $0) })
        demos.post("bulk-update", "action", use: { try await self.bulkAction(req: $0) })
    }

    // MARK: - Tabs

    func tabs(req: Request) async throws -> View {
        try await req.view.render("demos/tabs", ["title": "Tabs Demo"])
    }

    func tabContent(req: Request) async throws -> View {
        let tabId = req.parameters.get("tabId") ?? "overview"
        return try await req.view.render("demos/tab-\(tabId)")
    }

    // MARK: - Modals

    func modals(req: Request) async throws -> View {
        try await req.view.render("demos/modals", ["title": "Modals Demo"])
    }

    func modalConfirm(req: Request) async throws -> View {
        try await req.view.render("demos/modal-confirm")
    }

    func modalForm(req: Request) async throws -> View {
        try await req.view.render("demos/modal-form", ModalFormContext())
    }

    func modalFormSubmit(req: Request) async throws -> Response {
        struct ModalInput: Content {
            var name: String?
            var message: String?
        }

        let input = try req.content.decode(ModalInput.self)
        let name = input.name?.trimmingCharacters(in: .whitespaces) ?? ""
        let message = input.message?.trimmingCharacters(in: .whitespaces) ?? ""

        if name.isEmpty || message.isEmpty {
            let view = try await req.view.render("demos/modal-form", ModalFormContext(
                name: name,
                message: message,
                nameError: name.isEmpty ? "Name is required" : nil,
                messageError: message.isEmpty ? "Message is required" : nil
            ))
            return try await view.encodeResponse(for: req).get()
        }

        let response = Response(status: .ok, body: .init(string: """
        <div class="card">
            <p>✅ Message sent from <strong>\(name)</strong>: "\(message)"</p>
        </div>
        """))
        response.headers.replaceOrAdd(name: "Content-Type", value: "text/html")
        response.headers.replaceOrAdd(name: "HX-Trigger", value: #"{"showToast":{"message":"Form submitted!","type":"success"}, "closeModal":true}"#)
        return response
    }

    // MARK: - Forms

    func forms(req: Request) async throws -> View {
        try await req.view.render("demos/forms", FormContext(title: "Form Validation Demo"))
    }

    func formValidate(req: Request) async throws -> View {
        struct RegistrationForm: Content {
            var username: String?
            var email: String?
            var password: String?
            var confirmPassword: String?
        }

        let form = try req.content.decode(RegistrationForm.self)
        let username = form.username?.trimmingCharacters(in: .whitespaces) ?? ""
        let email = form.email?.trimmingCharacters(in: .whitespaces) ?? ""
        let password = form.password ?? ""
        let confirmPassword = form.confirmPassword ?? ""

        var errors = FormErrors()
        if username.isEmpty { errors.username = "Username is required" }
        else if username.count < 3 { errors.username = "Username must be at least 3 characters" }

        if email.isEmpty { errors.email = "Email is required" }
        else if !email.contains("@") { errors.email = "Please enter a valid email address" }

        if password.isEmpty { errors.password = "Password is required" }
        else if password.count < 8 { errors.password = "Password must be at least 8 characters" }

        if confirmPassword != password { errors.confirmPassword = "Passwords do not match" }

        if errors.hasErrors {
            return try await req.view.render("demos/forms", FormContext(
                title: "Form Validation Demo",
                username: username,
                email: email,
                errors: errors
            ))
        }

        return try await req.view.render("demos/form-success", ["username": username])
    }

    // MARK: - Toasts

    func toasts(req: Request) async throws -> View {
        try await req.view.render("demos/toasts", ["title": "Toasts Demo"])
    }

    func toastTrigger(req: Request) async throws -> Response {
        struct ToastInput: Content {
            var type: String
            var message: String
        }

        let input = try req.content.decode(ToastInput.self)
        let response = Response(status: .ok, body: .init(string: ""))
        response.headers.replaceOrAdd(name: "Content-Type", value: "text/html")
        response.headers.replaceOrAdd(name: "HX-Trigger", value: """
        {"showToast":{"message":"\(input.message)","type":"\(input.type)"}}
        """)
        return response
    }

    // MARK: - Toggles

    func toggles(req: Request) async throws -> View {
        try await req.view.render("demos/toggles", ["title": "Toggles & Accordion Demo"])
    }

    // MARK: - Progress

    func progress(req: Request) async throws -> View {
        try await req.view.render("demos/progress", ["title": "Progress Bar Demo"])
    }

    func progressStart(req: Request) async throws -> Response {
        let taskId = UUID().uuidString.prefix(8).lowercased()

        // Store progress in application storage
        var tasks = req.application.storage[ProgressTaskKey.self] ?? [:]
        tasks[String(taskId)] = 0
        req.application.storage[ProgressTaskKey.self] = tasks

        let response = Response(status: .ok, body: .init(string: """
        <div id="progress-area"
             hx-get="/demos/progress/poll/\(taskId)"
             hx-trigger="load delay:500ms"
             hx-swap="outerHTML">
            <div class="progress-bar">
                <div class="progress-fill" style="width: 0%">0%</div>
            </div>
            <p class="text-sm text-muted mt-1">Starting...</p>
        </div>
        """))
        response.headers.replaceOrAdd(name: "Content-Type", value: "text/html")
        return response
    }

    func progressPoll(req: Request) async throws -> Response {
        let taskId = req.parameters.get("taskId") ?? ""
        var current = (req.application.storage[ProgressTaskKey.self] ?? [:])[taskId] ?? 0

        // Simulate progress increment
        current = min(current + Int.random(in: 8...20), 100)
        var tasks = req.application.storage[ProgressTaskKey.self] ?? [:]
        tasks[taskId] = current
        req.application.storage[ProgressTaskKey.self] = tasks

        if current >= 100 {
            // Clean up
            var cleanTasks = req.application.storage[ProgressTaskKey.self] ?? [:]
            cleanTasks.removeValue(forKey: taskId)
            req.application.storage[ProgressTaskKey.self] = cleanTasks

            let response = Response(status: .ok, body: .init(string: """
            <div id="progress-area">
                <div class="progress-bar">
                    <div class="progress-fill" style="width: 100%">100%</div>
                </div>
                <p class="text-sm mt-1" style="color: #22c55e">✅ Task complete!</p>
            </div>
            """))
            response.headers.replaceOrAdd(name: "Content-Type", value: "text/html")
            response.headers.replaceOrAdd(name: "HX-Trigger", value: #"{"showToast":{"message":"Task completed!","type":"success"}}"#)
            return response
        }

        let response = Response(status: .ok, body: .init(string: """
        <div id="progress-area"
             hx-get="/demos/progress/poll/\(taskId)"
             hx-trigger="load delay:500ms"
             hx-swap="outerHTML">
            <div class="progress-bar">
                <div class="progress-fill" style="width: \(current)%">\(current)%</div>
            </div>
            <p class="text-sm text-muted mt-1">Processing... \(current)%</p>
        </div>
        """))
        response.headers.replaceOrAdd(name: "Content-Type", value: "text/html")
        return response
    }

    // MARK: - Bulk Update

    func bulkUpdate(req: Request) async throws -> View {
        let items = (1...12).map { BulkItem(id: $0, name: "Item \($0)", status: $0 % 3 == 0 ? "inactive" : "active") }
        return try await req.view.render("demos/bulk-update", BulkContext(title: "Bulk Update Demo", items: items))
    }

    func bulkAction(req: Request) async throws -> Response {
        struct BulkActionInput: Content {
            var action: String
            var ids: [Int]?
        }

        let input = try req.content.decode(BulkActionInput.self)
        let ids = input.ids ?? []
        let action = input.action

        let message: String
        switch action {
        case "activate":
            message = "Activated \(ids.count) item(s)"
        case "deactivate":
            message = "Deactivated \(ids.count) item(s)"
        case "delete":
            message = "Deleted \(ids.count) item(s)"
        default:
            message = "Unknown action"
        }

        // Re-render the table with updated statuses
        var items = (1...12).map { BulkItem(id: $0, name: "Item \($0)", status: $0 % 3 == 0 ? "inactive" : "active") }
        for i in 0..<items.count {
            if ids.contains(items[i].id) {
                switch action {
                case "activate": items[i].status = "active"
                case "deactivate": items[i].status = "inactive"
                default: break
                }
            }
        }

        if action == "delete" {
            items = items.filter { !ids.contains($0.id) }
        }

        let view = try await req.view.render("demos/bulk-rows", BulkContext(items: items))
        let response = try await view.encodeResponse(for: req).get()
        response.headers.replaceOrAdd(name: "HX-Trigger", value: """
        {"showToast":{"message":"\(message)","type":"success"}}
        """)
        return response
    }
}

// MARK: - Context Types

struct ModalFormContext: Content {
    var name: String?
    var message: String?
    var nameError: String?
    var messageError: String?
}

struct FormContext: Content {
    var title: String?
    var username: String?
    var email: String?
    var errors: FormErrors?
}

struct FormErrors: Content {
    var username: String?
    var email: String?
    var password: String?
    var confirmPassword: String?

    var hasErrors: Bool {
        username != nil || email != nil || password != nil || confirmPassword != nil
    }
}

struct BulkItem: Content {
    var id: Int
    var name: String
    var status: String
}

struct BulkContext: Content {
    var title: String?
    var items: [BulkItem]
}

struct ProgressTaskKey: StorageKey {
    typealias Value = [String: Int]
}
