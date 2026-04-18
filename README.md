# ⚡ Swift HTMX Kitchen Sink

A comprehensive reference application for **HTMX + Alpine.js** patterns built with **Swift**, **Vapor**, and **Leaf** templates. Plain CSS, no build step, no JavaScript framework.

## Stack

| Layer | Technology |
|-------|-----------|
| Server | [Vapor 4](https://vapor.codes) (Swift 5.10) |
| Templates | [Leaf](https://docs.vapor.codes/leaf/overview/) |
| Interactivity | [HTMX 2.0.7](https://htmx.org) + [Alpine.js 3.x](https://alpinejs.dev) |
| Database | SQLite (default) or PostgreSQL (env toggle) |
| Styling | Plain CSS (no frameworks) |

## Quick Start

```bash
# Clone and run (SQLite, zero config)
swift run

# Open http://localhost:8888
```

## Database Toggle

Set `DB_TYPE` to switch between SQLite and PostgreSQL:

```bash
# SQLite (default)
DB_TYPE=sqlite swift run

# PostgreSQL
DB_TYPE=postgres \
  DB_HOST=localhost DB_PORT=5432 \
  DB_USER=vapor DB_PASS=vapor DB_NAME=kitchen_sink \
  swift run

# Or use a connection string
DB_TYPE=postgres DATABASE_URL=postgres://vapor:vapor@localhost:5432/kitchen_sink swift run
```

## Docker

```bash
# SQLite mode (default)
docker-compose up app

# PostgreSQL mode
docker-compose --profile postgres up
```

## Demos

| Page | Patterns | URL |
|------|----------|-----|
| **Todos** | CRUD, inline edit, toggle, OOB swaps, toast triggers | `/todos` |
| **Contacts** | Active search (debounce), infinite scroll | `/contacts` |
| **Tabs** | Alpine.js state + HTMX lazy-load | `/demos/tabs` |
| **Modals** | HTMX-loaded content, Alpine open/close | `/demos/modals` |
| **Forms** | Server-side validation, inline errors | `/demos/forms` |
| **Toasts** | HX-Trigger headers + Alpine component | `/demos/toasts` |
| **Toggles** | Accordion, dropdown, switches, counter | `/demos/toggles` |
| **Progress** | HTMX polling, simulated task | `/demos/progress` |
| **Bulk Update** | Alpine multi-select + HTMX batch action | `/demos/bulk-update` |

## Architecture

```
Sources/App/
├── configure.swift          # DB toggle, middleware, migrations
├── routes.swift             # Controller registration
├── Controllers/
│   ├── TodoController       # Full HTMX CRUD
│   ├── ContactController    # Search + pagination
│   └── DemoController       # All demo routes
├── Models/                  # Fluent models (Todo, Contact)
├── Migrations/              # Schema + seed data
└── Middleware/
    └── HTMXMiddleware       # Detects HX-Request header

Resources/Views/
├── layout.leaf              # Base HTML5 shell (HTMX + Alpine CDN)
├── index.leaf               # Dashboard
├── todos/                   # Todo CRUD partials
├── contacts/                # Search + scroll partials
└── demos/                   # Demo page templates

Public/css/styles.css        # All styles (~500 lines)
```

### Key Patterns

- **Partials-first**: HTMX endpoints return Leaf partials; direct navigation gets full pages via `layout.leaf`
- **OOB swaps**: Todo count badge updates via `hx-swap-oob` in response body
- **HX-Trigger headers**: Server triggers client-side events (toast notifications, modal close)
- **Alpine + HTMX**: Alpine manages local UI state (dropdowns, toggles), HTMX handles server communication
- **`req.isHTMX`**: Middleware flag lets controllers branch between partial and full-page responses

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `DB_TYPE` | `sqlite` | Database driver (`sqlite` or `postgres`) |
| `DATABASE_URL` | — | PostgreSQL connection string |
| `DB_HOST` | `localhost` | PostgreSQL host |
| `DB_PORT` | `5432` | PostgreSQL port |
| `DB_USER` | `vapor` | PostgreSQL user |
| `DB_PASS` | `vapor` | PostgreSQL password |
| `DB_NAME` | `kitchen_sink` | PostgreSQL database |

## Tests

```bash
swift test
```

## License

MIT
