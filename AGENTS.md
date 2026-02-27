# AGENTS.md

> **Read this file first. Every time. Before making any change.**
>
> This is the single source of truth for any AI coding agent (Claude, Codex,
> Grok, Cursor, Copilot, etc.) and any human contributor working on this
> project. Follow it strictly.
>
> This file exists because a previous 6000-line version of this app was
> destroyed by AI agents that dumped everything into a monolith, then
> shattered it into MVC spaghetti with bridge files and deep nesting.
> Every rule here exists to prevent that from happening again.

---

## 0. Project Context — Read This First

This Go CLI is a **prototype backend for a web application**. The production
stack will be:

- **Database**: Supabase (PostgreSQL)
- **Frontend**: Next.js + TypeScript
- **Auth**: Supabase Auth (Row Level Security)

**What this means for every decision you make:**

1. **Domain types are the contract.** The structs in `internal/domain/` will
   become TypeScript interfaces and Supabase table schemas. Design them as if
   they are a public API. Always include `json` struct tags. Use `snake_case`
   for JSON keys (matches Postgres column naming and Supabase conventions).

2. **Repository layer is swappable.** The project ships with an in-memory
   adapter for zero-dependency prototyping. When ready, swap to the Postgres
   adapter — no changes to business logic. In production, the Supabase JS SDK
   replaces the Go repository entirely.

3. **Service logic will port to Next.js API routes.** Keep services so clean
   that translating them to TypeScript is a matter of syntax, not architecture.
   If a service function can't be explained as "take this input, validate,
   query, transform, return" — it's too coupled.

4. **SQL migrations are the single source of schema truth.** The `migrations/`
   directory defines every table. These same migrations (or their Supabase SQL
   editor equivalents) will create the production schema.

5. **JSON is the default output.** The real consumer is a web frontend, not a
   terminal. Default `--format` is `json`. Table/text output is a convenience
   for CLI debugging.

6. **The `serve` command is a preview.** `myapp serve` runs a lightweight HTTP
   server exposing the same service layer as JSON endpoints. This is for
   prototyping only — it will be replaced by Next.js API routes in production.

---

## 1. Role and Philosophy

You are an expert Go developer. Your code must be idiomatic Go.

- **Simplicity over cleverness.** Readable, boring code is correct code.
- **Do NOT use MVC patterns.** No `controllers/`, `models/`, `views/` folders. This is Go, not Rails.
- **Flat over nested.** When in doubt, put the file in an existing package. Do not create a new sub-folder.
- **Accept interfaces, return structs.** This is a Go proverb. Follow it. Define small interfaces where they are consumed; return concrete types from constructors.
- **Core logic must be pure.** Business logic must never import Cobra, read environment variables, open files, or make network calls directly. It receives dependencies via interfaces.
- **Think in tables.** Every domain type should map cleanly to a Postgres table. If it doesn't, reconsider the design.
- **Zero external deps for prototyping.** The app must run with `go run .` and no database, no API keys, no Docker. The in-memory adapter makes this possible.

---

## 2. Project Layout

```
myapp/                              # repo root
├── AGENTS.md                       # THIS FILE — read first, always
├── README.md                       # user-facing documentation
├── Makefile                        # build, test, lint, clean targets
├── go.mod
├── go.sum
├── .gitignore
├── .editorconfig                   # consistent formatting across editors
├── .golangci.yml                   # linter configuration
├── .env.example                    # environment variable template
├── main.go                         # entrypoint — wiring ONLY (see §2.1)
│
├── .github/
│   └── workflows/
│       └── ci.yml                  # GitHub Actions CI pipeline
│
├── cmd/                            # one file per CLI command (see §2.2)
│   ├── root.go                     # root command + global persistent flags
│   ├── version.go                  # myapp version
│   ├── listings.go                 # myapp listings
│   └── serve.go                    # myapp serve (preview HTTP server)
│
├── internal/                       # private application code (see §2.3)
│   ├── config/                     # config loading + validation
│   │   └── config.go
│   ├── service/                    # core business logic — MUST be testable
│   │   ├── listings.go
│   │   └── listings_test.go
│   ├── domain/                     # shared types, interfaces, constants
│   │   ├── listing.go              # → becomes Supabase "listings" table
│   │   ├── user.go                 # → becomes Supabase "profiles" table
│   │   └── errors.go              # custom error types
│   ├── repository/                 # data access — swappable adapters
│   │   ├── interfaces.go           # repository interface (shared contract)
│   │   ├── inmemory.go             # in-memory adapter (prototyping, tests)
│   │   └── postgres.go             # Postgres adapter (add when ready)
│   ├── adapters/                   # external side effects — APIs, email, storage
│   │   ├── http_client.go
│   │   └── output.go              # JSON/table/CSV rendering
│   └── util/                       # small, stateless, pure helper functions
│       └── strings.go
│
├── migrations/                     # SQL migrations — source of schema truth
│   ├── 001_create_profiles.sql
│   ├── 002_create_listings.sql
│   └── README.md                   # notes on applying to Supabase
│
├── configs/                        # example config files (committed to repo)
│   └── config.yaml.example
│
└── testdata/                       # test fixtures, golden files, seed data
    ├── fixtures/
    └── seed/                       # JSON seed data for development
        └── listings.json
```

### 2.1 main.go — Entrypoint

```go
package main

import "myapp/cmd"

func main() {
    cmd.Execute()
}
```

**Rules:**
- No business logic. No flag parsing. No imports beyond `cmd`.
- This file must never exceed 10 lines.
- If you are tempted to add anything here, it belongs in `cmd/root.go` or `internal/`.

### 2.2 cmd/ — CLI Command Layer

Each file defines exactly ONE Cobra command (or a tightly related parent/child pair like `config get` / `config set`).

**Rules:**
- **One file per command.** `cmd/serve.go` defines the `serve` command.
- **Commands are thin wrappers.** They parse flags, construct dependencies (choosing which repository adapter to use), call `internal/service/`, and format output. That's it.
- **All commands register themselves** in their `init()` function via `rootCmd.AddCommand()`.
- **Global persistent flags** (like `--verbose`, `--config`, `--format`) live in `cmd/root.go`.
- **No business logic in commands.** If your `RunE` function has more than ~10 lines of logic, extract it to `internal/service/`.
- **Always use `RunE`** (not `Run`) so errors propagate properly.
- **Commands own dependency wiring.** The command's `RunE` function creates the repository (in-memory or Postgres based on config) and injects it into the service. This is the composition root.
- **Commands own error presentation.** Services return errors; commands decide how to display them.

**Standard command pattern:**

```go
// cmd/listings.go
package cmd

import (
    "fmt"
    "myapp/internal/adapters"
    "myapp/internal/config"
    "myapp/internal/repository"
    "myapp/internal/service"

    "github.com/spf13/cobra"
)

var listingsCmd = &cobra.Command{
    Use:   "listings",
    Short: "List active marketplace listings",
    RunE: func(cmd *cobra.Command, args []string) error {
        cfg, err := config.Load()
        if err != nil {
            return fmt.Errorf("loading config: %w", err)
        }
        repo := repository.NewInMemory()  // swap to NewPostgres(cfg.DatabaseURL) later
        svc := service.NewListingService(repo)
        listings, err := svc.ListActive(cmd.Context())
        if err != nil {
            return fmt.Errorf("fetching listings: %w", err)
        }
        return adapters.Render(cfg.Format, listings)
    },
}

func init() {
    rootCmd.AddCommand(listingsCmd)
}
```

### 2.3 internal/ — Private Application Code

Everything under `internal/` is private to this module (Go compiler enforces this). All real code lives here.

**Package responsibilities are strict. Do not blur them:**

| Package              | Contains                                  | May Import                          | Never Imports           |
|----------------------|-------------------------------------------|-------------------------------------|-------------------------|
| `internal/config`    | Config structs, loading, validation       | `domain`                            | `cmd`, `service`        |
| `internal/service`   | Business logic, orchestration, use-cases  | `domain`, `repository`, `adapters`  | `cmd`                   |
| `internal/domain`    | Shared types, interfaces, constants, enums| standard library only               | everything else         |
| `internal/repository`| Data access — in-memory, Postgres, etc.   | `domain`                            | `service`, `cmd`        |
| `internal/adapters`  | External API calls, email, storage, output| `domain`                            | `service`, `cmd`        |
| `internal/util`      | Pure stateless helper functions           | standard library only               | everything else         |

### 2.4 Key Package Details

**internal/service/ — The Brain**
- All decision-making, validation, orchestration, and workflow lives here.
- Services accept interfaces, not concrete types. This enables testing.
- Services never import `cobra`, never call `os.Exit()`, never print to stdout.
- Services return structured errors — the `cmd/` layer decides how to display them.
- One file per domain area: `listings.go`, `users.go`, `search.go`.
- This code must be **100% agnostic to the CLI**. It must not know that Cobra exists.
- **Portability test:** if you can't imagine translating this function to a Next.js API route handler with minimal changes, it's too coupled.

**internal/domain/ — Shared Types (Future Supabase Tables)**
- Pure data structures. No methods with side effects. No I/O.
- **Every struct must have `json:"snake_case"` tags.** These become your API contract and map to Postgres column names.
- **Every struct should have a `db:"column_name"` tag** (for `sqlx` or similar) matching the Postgres column.
- Validation methods are OK (e.g., `func (l *Listing) Validate() error`).
- **Leaf package**: imports nothing from this project.
- Interfaces consumed by multiple packages can live here.
- One file per entity or closely related entity group.
- Include `CreatedAt`, `UpdatedAt` timestamps on every entity (Supabase convention).
- **Keep types plain.** Use `string`, `int`, `time.Time`, `[]string`. Avoid Go-specific types that don't translate to TypeScript. Avoid pointers unless the field is truly optional/nullable.

**Domain type pattern (this is critical):**

```go
// internal/domain/listing.go
package domain

import "time"

// Listing maps to the Supabase "listings" table.
// TypeScript equivalent: interface Listing { id: string; user_id: string; ... }
type Listing struct {
    ID          string    `json:"id"          db:"id"`
    UserID      string    `json:"user_id"     db:"user_id"`
    Title       string    `json:"title"       db:"title"`
    Description string    `json:"description" db:"description"`
    Price       int       `json:"price"       db:"price"`       // cents
    Category    string    `json:"category"    db:"category"`
    Status      string    `json:"status"      db:"status"`      // active, sold, expired
    ImageURLs   []string  `json:"image_urls"  db:"image_urls"`  // Postgres text[]
    CreatedAt   time.Time `json:"created_at"  db:"created_at"`
    UpdatedAt   time.Time `json:"updated_at"  db:"updated_at"`
}

func (l *Listing) Validate() error {
    if l.Title == "" {
        return ErrMissingTitle
    }
    if l.Price < 0 {
        return ErrInvalidPrice
    }
    return nil
}
```

**internal/repository/ — Data Access (Swappable Adapters)**
- The repository interface is defined in `interfaces.go`.
- **Two adapters ship by default:**
  - `inmemory.go` — loads seed data from `testdata/seed/`, stores in a map. Used for prototyping and tests. **Zero external dependencies.**
  - `postgres.go` — real PostgreSQL queries. Add when you're ready for a database.
- The active adapter is chosen in `cmd/` based on config (composition root).
- Repository methods do data access ONLY — no business logic.
- Always accept `context.Context` as the first parameter.
- Use parameterized queries (`$1`, `$2`) — never string concatenation.

**internal/adapters/ — External Side Effects**
- Anything that talks to the outside world besides the database.
- Each external system gets its own file.
- Adapters implement interfaces defined in `domain/` or `service/`.
- Adapters handle retries, timeouts, and serialization internally.
- **Output rendering** (JSON, table, CSV) lives here in `output.go`.

**internal/util/ — Helpers**
- Stateless, pure functions only. No side effects, no config, no state.
- **Leaf package**: imports nothing from this project.
- If a helper is only used in one package, keep it in that package instead.
- Guard against this becoming a dumping ground.

### 2.5 migrations/ — SQL Schema (Supabase-Ready)

- Each migration is a numbered `.sql` file: `001_create_profiles.sql`, `002_create_listings.sql`.
- Migrations are the **single source of truth** for the database schema.
- Write standard PostgreSQL. Supabase runs Postgres — these should work directly in the Supabase SQL editor.
- Include Supabase-relevant features: `uuid` primary keys (using `gen_random_uuid()`), `timestamptz` for timestamps, RLS policy stubs as comments.
- Keep migrations additive. Never modify an existing migration — create a new one.

**Migration pattern:**

```sql
-- migrations/001_create_listings.sql

CREATE TABLE IF NOT EXISTS listings (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id     UUID NOT NULL REFERENCES auth.users(id),
    title       TEXT NOT NULL,
    description TEXT NOT NULL DEFAULT '',
    price       INTEGER NOT NULL DEFAULT 0,
    category    TEXT NOT NULL DEFAULT '',
    status      TEXT NOT NULL DEFAULT 'active',
    image_urls  TEXT[] NOT NULL DEFAULT '{}',
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Index for common queries
CREATE INDEX IF NOT EXISTS idx_listings_user_id ON listings(user_id);
CREATE INDEX IF NOT EXISTS idx_listings_status ON listings(status);

-- TODO: Add RLS policies when migrating to Supabase
-- ALTER TABLE listings ENABLE ROW LEVEL SECURITY;
-- CREATE POLICY "Users can view active listings" ON listings
--     FOR SELECT USING (status = 'active');
```

---

## 3. Dependency Direction

Dependencies flow in ONE direction. Violations cause import cycles and spaghetti.

```
main.go
  └→ cmd/                       ← composition root: wires adapters into services
       └→ internal/config/      → domain/
       └→ internal/repository/  → domain/        (inmemory OR postgres)
       └→ internal/service/     → domain/
                                → repository/ (via interfaces)
                                → adapters/   (via interfaces)
```

**Hard rules:**
- `domain/` and `util/` are **leaf packages**. They import nothing from this project.
- `service/` depends on `repository/` and `adapters/` via **interfaces only**, not concrete types.
- `cmd/` is the **composition root** — it creates concrete repository adapters and injects them into services. This is the only place that knows which adapter is active.
- `cmd/` depends on `service/`, `config/`, and `repository/` (for construction only). It never calls repository methods directly.
- **No package may import from `cmd/`.**
- **No circular imports.** If you get an import cycle, fix it with interfaces or by moving shared types to `domain/`.
- `service/` (core business logic) may only import: other `internal/` packages, `domain/`, and the standard library. It must stay pure.

---

## 4. Refactoring Rules

These rules exist to prevent the structural decay that AI agents commonly cause.

### 4.1 Structure Rules

- **Do not create new nested folder trees.** The layout in §2 is the layout. Period.
- **Maximum folder depth is 3 levels** from repo root: `internal/service/somefile.go`. Never deeper.
- **No "bridge" or "glue" packages.** If two packages need to talk, use a small interface in the consuming package or in `domain/`. Never create a third package to connect them.
- **No "common", "shared", "helpers", "base", or "types" mega-packages.** Use `domain/` for shared types and `util/` for stateless helpers. That's it.
- **Never create new top-level directories without updating this file first.**

### 4.2 File Size Rules

- **Target: 100–300 lines per file.** Ideally under 200.
- **Hard ceiling: 500 lines.** If a file exceeds 500 lines, split it.
- **When splitting**, create **sibling files in the same package**. Do NOT create a sub-package.
  - Good: `service/listings.go` → `service/listing_search.go` + `service/listing_crud.go`
  - Bad: `service/listings.go` → `service/listings/search.go` + `service/listings/crud.go`
- **No function should exceed 80 lines.** If it does, extract helper functions.

### 4.3 Naming Rules

- File names: `snake_case.go`. Never camelCase, never kebab-case.
- One primary type or concept per file. File name matches the concept.
- Test files: `*_test.go` in the same package.
- Avoid generic names: `helpers.go`, `utils.go`, `common.go`, `types.go`. Name files after what they contain.

### 4.4 When Moving Code Between Files

- Move complete functions/types. Never split a function across files.
- Update all imports in one pass. Do not leave broken imports.
- Run `go build ./...` immediately after every move to verify.

---

## 5. Coding Standards

### 5.1 Error Handling

- Always wrap errors with context: `fmt.Errorf("doing X: %w", err)`
- Never silently swallow errors. If intentionally ignoring one, add a comment.
- Use custom error types in `domain/errors.go` when callers need to distinguish error cases (e.g., `ErrNotFound`, `ErrUnauthorized`, `ErrValidation`).
- **Never use `panic`** except during application initialization for truly unrecoverable failures.
- Only `cmd/` may call `os.Exit()` or print errors to stderr.
- **Design errors for HTTP mapping.** Service errors should map cleanly to HTTP status codes in the future (NotFound→404, Validation→400, Unauthorized→401).

### 5.2 Configuration

- All configuration loads through `internal/config/`.
- Use Viper (Cobra's companion) for config files, env vars, and flag binding.
- Config struct is defined once and passed down via dependency injection.
- **No `os.Getenv()` scattered through the codebase.** Centralize in `config/`.
- Sensitive values (API keys, tokens, `DATABASE_URL`) come from env vars or secret managers, never hardcoded.
- Provide an example config in `configs/config.yaml.example`.
- **Use the same env var names your Next.js app will use:** `DATABASE_URL`, `SUPABASE_URL`, `SUPABASE_ANON_KEY`. This way `.env.example` is shared across both projects.

### 5.3 Interfaces

- **Define interfaces where they are consumed, not where they are implemented.**
  - Good: `ListingRepository` interface defined in `internal/service/listings.go`
  - Acceptable: shared interface in `internal/repository/interfaces.go` when used by multiple services
  - Bad: defining in the concrete adapter file
- Keep interfaces small: 1–3 methods. Go proverb: "The bigger the interface, the weaker the abstraction."
- **Accept interfaces, return structs.** Constructors return concrete types; function parameters accept interfaces.

### 5.4 Concurrency

- Use goroutines and channels carefully.
- **Always manage goroutine lifecycles** using `context.Context` or `sync.WaitGroup`.
- Never fire-and-forget a goroutine without a shutdown mechanism.
- Prefer `context.Context` for cancellation and timeouts on all I/O operations.

### 5.5 Output Formatting

- **Default format is `json`** (the eventual consumer is a web frontend).
- Support `--format json|table|text` on commands that display data.
- Output rendering logic lives in `internal/adapters/output.go`, not in `cmd/`.
- JSON output must use the same `snake_case` keys as the domain struct tags.
- Never use `fmt.Println` for structured data output.

### 5.6 Logging

- Use a structured logger (`slog`, `zerolog`, or `zap`). No `fmt.Println` for logs.
- Logger is initialized in `cmd/root.go` and passed via dependency injection or context.
- Log levels: `debug` for dev tracing, `info` for operational events, `warn` for recoverable issues, `error` for user-affecting failures.

### 5.7 Testing

- **Table-driven tests** for functions with multiple input/output cases.
- **Use the in-memory repository for all service tests.** It's fast, deterministic, and needs no setup.
- Test files live next to the code: `service/listings.go` → `service/listings_test.go`.
- `testdata/` at repo root holds fixtures and golden files.
- `testdata/seed/` holds JSON seed data that can also be used to populate Supabase during development.
- Integration tests (real DB, network) use build tags: `//go:build integration`.
- **Unit tests for `service/` must be 100% pure** — no network, no filesystem, no database.
- Aim for >80% coverage on `internal/service/`.
- Always run tests with `-race` flag to catch data races.

### 5.8 Database Conventions (Postgres/Supabase)

- **Primary keys**: UUID, generated with `gen_random_uuid()`.
- **Timestamps**: `TIMESTAMPTZ` with `DEFAULT now()`. Always include `created_at` and `updated_at`.
- **Column names**: `snake_case` (matches Go `json` and `db` tags).
- **Foreign keys**: always include, with `REFERENCES` and appropriate `ON DELETE` behavior.
- **Indexes**: create for any column used in WHERE clauses or JOINs.
- **Parameterized queries only**: `$1`, `$2`, etc. Never concatenate user input into SQL.
- **RLS stubs**: include commented-out Row Level Security policies in migrations for future Supabase deployment.

---

## 6. AI Agent Workflow — How to Build Features

### 6.1 Adding a New Command

Follow this exact sequence. **Core first. Adapter second. CLI last.**

1. **Migration** — If the feature needs a new table or column, write the SQL migration in `migrations/`. This is the source of truth.
2. **Domain types** — Add the struct to `internal/domain/` with `json` and `db` tags. It must mirror the migration schema exactly.
3. **Core logic** — Write the business logic in `internal/service/`. Write unit tests using the in-memory repository. This code must work with zero knowledge of Cobra or the CLI.
4. **Repository** — Add methods to `internal/repository/interfaces.go`. Implement in `inmemory.go` first (for immediate use), then optionally in `postgres.go`.
5. **Adapter** — If the core logic needs external data (API, email, storage), write the adapter in `internal/adapters/`.
6. **CLI command** — Create `cmd/newcommand.go`. Register it in `init()`. The `RunE` function constructs the repository, creates the service, calls it, and renders output.
7. **Seed data** — Add sample JSON to `testdata/seed/` for the new entity.
8. **Verify** — Run `make check`.

**Never start by writing the CLI command.** If the feature can't be tested without Cobra, the design is wrong.

### 6.2 Adding a Feature to an Existing Command

1. Check if logic belongs in an existing service or needs a new one.
2. Add logic to `internal/service/`. Write a test.
3. If new repository methods are needed, add to interface and both adapters.
4. Wire it in the command's `RunE`.
5. New flags go in the command's `init()`.
6. If schema changes are needed, write a new migration first.
7. Verify.

### 6.3 Fixing a Bug

- Keep changes isolated to the responsible package.
- Write a regression test that fails before the fix and passes after.
- Do not refactor unrelated code in the same change.

### 6.4 Refactoring

- Never move code into `cmd/`.
- Never create new nested folders.
- Show the full file + diff when moving code between packages.
- Verify builds and tests pass after every file move.

### 6.5 Switching from In-Memory to Postgres

When you're ready to connect a real database:

1. Implement the repository interface in `internal/repository/postgres.go`.
2. In the relevant `cmd/*.go`, swap `repository.NewInMemory()` for `repository.NewPostgres(cfg.DatabaseURL)`.
3. Optionally, use `cfg.DatabaseURL` to auto-detect: if empty, use in-memory; if set, use Postgres.
4. No changes to `internal/service/` — that's the whole point of the interface.

---

## 7. Anti-Patterns — Things That Must Never Happen

| Anti-Pattern | Why It's Bad | What to Do Instead |
|---|---|---|
| God file (500+ lines) | Agents make more mistakes editing large files | Split by responsibility into sibling files |
| Bridge/wrapper/glue package | Adds indirection without value | Delete it; use a direct import or interface |
| Business logic in `cmd/` | Untestable; mixes presentation with logic | Move to `internal/service/` |
| `os.Getenv()` scattered everywhere | Untestable; config becomes invisible | Centralize in `internal/config/` |
| Circular imports | Won't compile; sign of tangled design | Move shared types to `domain/`; use interfaces |
| Package named `common`/`shared`/`base` | Becomes a dumping ground | Use specific package names |
| Deeply nested folders | Confusing; unnecessary complexity | Max 3 levels from repo root |
| Unused code / dead imports | Confuses agents and humans | Delete it; `go vet` catches unused imports |
| MVC folder names | Wrong paradigm for Go | Use the layout in §2 |
| Dumping everything in main.go | Untestable monolith | main.go is wiring only |
| `fmt.Println` for logs | Unstructured; can't filter or search | Use structured logger |
| `Run` instead of `RunE` | Swallows errors silently | Always use `RunE` on Cobra commands |
| `panic` in application code | Crashes ungracefully | Return errors; let `cmd/` handle display |
| Fire-and-forget goroutines | Resource leaks; undefined behavior | Use `context.Context` or `sync.WaitGroup` |
| Domain types without JSON tags | Breaks API contract; breaks frontend | Always add `json:"snake_case"` tags |
| String concatenation in SQL | SQL injection risk | Use parameterized queries (`$1`, `$2`) |
| Schema changes without migrations | Invisible schema drift | Always write a migration file first |
| Go-specific types in domain | Won't translate to TypeScript | Use `string`, `int`, `time.Time`, `[]string` |
| Requiring a database to prototype | Slows iteration; couples to infra | Use in-memory adapter first |

---

## 8. Commands to Run

```bash
# Format
gofmt -w .

# Vet — catches common mistakes
go vet ./...

# Build — must pass before any commit
go build ./...

# Test — always with race detector
go test ./... -race -cover

# Tidy modules
go mod tidy

# Lint (if golangci-lint is installed)
golangci-lint run

# Build binary
go build -o bin/myapp .

# Full pre-commit check (copy-paste this)
gofmt -w . && go vet ./... && go build ./... && go test ./... -race && echo "ALL PASSED"
```

### Makefile

Place this at the repo root:

```makefile
.PHONY: build test vet lint fmt check clean seed serve migrate

build:
	go build -o bin/myapp .

test:
	go test ./... -race -coverprofile=coverage.out

vet:
	go vet ./...

lint:
	golangci-lint run

fmt:
	gofmt -w .

check: fmt vet build test
	@echo "All checks passed."

seed:
	go run . seed

serve:
	go run . serve

migrate:
	@for f in migrations/*.sql; do echo "psql $$DATABASE_URL -f $$f"; done

clean:
	rm -rf bin/ coverage.out
```

---

## 9. Agent-Specific Instructions

### Before Making Any Change

1. **Read this file.** (You're doing it now. Good.)
2. Read `cmd/root.go` to understand the command tree.
3. Identify which layer the change belongs to: `cmd/`, `service/`, `repository/`, `adapters/`, `domain/`.
4. Check existing files in that layer before creating new ones.
5. **If adding a new entity**: start with the migration, then domain type, then work outward.

### While Making Changes

- Follow the dependency direction in §3. If you get an import cycle, **stop and rethink**.
- Keep changes focused. If asked to add a feature, don't also refactor unrelated code.
- If a file is getting too long, split into sibling files — not sub-packages.
- Always use the full module import path (e.g., `github.com/yourname/myapp/internal/service`).
- **Every domain struct must have `json` tags.** No exceptions.
- **Every SQL query must use parameterized inputs.** No exceptions.
- **When adding repository methods**, implement in both `inmemory.go` and `postgres.go` (if it exists).

### After Making Changes

- Run `make check` (or the full command chain from §8).
- Verify no new packages were created that aren't in §2.
- Verify no file exceeds 500 lines.
- Verify no function exceeds 80 lines.
- Verify new domain types have `json` and `db` tags.
- Verify new tables have corresponding migrations.

### When You're Unsure

- **Where does code go?** → `internal/service/`
- **Do I need a new package?** → No. Use an existing one.
- **Where does the interface go?** → Where it's consumed. Keep it small.
- **How do I organize this file?** → Look at sibling files in the same package and follow the pattern.
- **Do I need a migration?** → If you're adding or changing a domain type, yes.
- **Which repository adapter do I implement first?** → In-memory. Always.

### If You See a Violation

**Call it out immediately.** If existing code violates these rules, tell the human before making changes. Do not silently propagate bad patterns. Do not "fix" violations unless asked to — just flag them.

---

## 10. Quick Reference — "Where Does This Go?"

| I need to...                                    | Put it in...                                       |
|-------------------------------------------------|----------------------------------------------------|
| Parse CLI flags and args                        | `cmd/commandname.go`                               |
| Load config from file/env                       | `internal/config/config.go`                        |
| Define a shared data struct or interface        | `internal/domain/`                                 |
| Write business logic / orchestration            | `internal/service/`                                |
| Query Postgres / read-write data                | `internal/repository/postgres.go`                  |
| Prototype data access (no DB)                   | `internal/repository/inmemory.go`                  |
| Call an external API / send email               | `internal/adapters/`                               |
| Write a pure helper function                    | `internal/util/`                                   |
| Render output (JSON, table, CSV)                | `internal/adapters/output.go`                      |
| Add or change a database table                  | `migrations/NNN_description.sql`                   |
| Add test fixtures                               | `testdata/`                                        |
| Add seed data for development                   | `testdata/seed/`                                   |
| Add an example config file                      | `configs/`                                         |
| Define an interface                             | Where it's consumed (usually `internal/service/`)  |
| Wire dependencies together                      | `cmd/` (the composition root)                      |

---

## 11. Versioning and Releases

- Use **semantic versioning**: `v0.1.0` → `v1.0.0`.
- Tag releases: `git tag vX.Y.Z && git push --tags`.
- Store the version constant in `cmd/version.go`.
- Update the version constant on every release.

---

## 12. Migration Path to Production Stack

When moving from this CLI prototype to the production Next.js + Supabase stack:

1. **Schema** → Apply `migrations/*.sql` in the Supabase SQL editor or via Supabase CLI. Uncomment the RLS policies.
2. **Domain types** → Translate `internal/domain/*.go` structs to TypeScript interfaces. The `json` tags define the field names exactly.
3. **Service logic** → Port `internal/service/*.go` functions to Next.js API routes or server actions. The logic should transfer almost 1:1 since services are pure and framework-agnostic.
4. **Repository layer** → Replace with Supabase JS SDK (`supabase.from('listings').select(...)`) or keep as raw SQL via Supabase's `rpc()`.
5. **Auth** → Replace any CLI auth stubs with Supabase Auth + RLS policies.
6. **Seed data** → `testdata/seed/*.json` can be imported directly into Supabase.
7. **HTTP endpoints** → The `serve` command's routes become Next.js API routes. Same paths, same JSON shape.

The cleaner the separation in this prototype, the easier this migration will be.

---

*Last updated: February 2026*
*Maintained by: the human owner + any AI agent working on this project.*
