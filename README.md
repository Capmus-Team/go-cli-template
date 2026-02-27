# Go CLI Starter Template

A batteries-included starter template for building Go CLI applications with [Cobra](https://github.com/spf13/cobra), designed to work well with AI coding agents (Claude, Codex, Cursor, Copilot, etc.) and optimized for prototyping backends that will migrate to Supabase + Next.js.

## Why This Exists

AI coding agents tend to dump everything into a single file or create chaotic folder structures with bridge files and deep nesting. This template solves that by providing:

- **`AGENTS.md`** — a governance file that AI agents read before every change, keeping your codebase structured
- **`scaffold.sh`** — a one-command project generator that creates a working Go project with seed data, tests, CI, and a preview HTTP server
- **Zero-dependency prototyping** — generated projects work immediately with `go run .` — no database, no API keys, no Docker

## Quick Start

```bash
# Clone this template
git clone https://github.com/Capmus-Team/go-cli-template.git
cd go-cli-template

# Scaffold a new project
chmod +x scaffold.sh
./scaffold.sh myapp github.com/Capmus-Team/myapp

# Try it immediately
cd myapp
cp ../AGENTS.md .
go run . version              # → v0.1.0
go run . listings             # → JSON list of seed data
go run . serve                # → preview server at http://localhost:8080
curl localhost:8080/api/listings
```

No database, no API keys, no Docker required. Everything works out of the box.

## Real-World Example: SUPost CLI

This is how we used this template to scaffold [SUPost](https://github.com/Capmus-Team/supost-cli), a university marketplace prototype. The repo name is `supost-cli` but the binary and commands are just `supost`:

```bash
# 1. Go to your template directory
cd ~/Developer/github/capmus-team/go-cli-template

# 2. Run the scaffold (app name "supost", module path uses repo name "supost-cli")
./scaffold.sh supost github.com/Capmus-Team/supost-cli

# 3. Copy AGENTS.md into the generated project
cp AGENTS.md supost/

# 4. Move the generated project to its own directory
mv supost ../supost-cli
cd ../supost-cli

# 5. Initialize git and push
git init
git add -A
git commit -m "Initial commit: SUPost CLI prototype"

# Using gh CLI:
gh repo create Capmus-Team/supost-cli \
  --public \
  --source=. \
  --description "SUPost university marketplace CLI prototype (Cobra + Supabase)" \
  --push

# Or manually: create repo at https://github.com/organizations/Capmus-Team/repositories/new
# Then:
git remote add origin git@github.com:Capmus-Team/supost-cli.git
git branch -M main
git push -u origin main
```

The result: the repo is `Capmus-Team/supost-cli` on GitHub, but the binary and all commands are just `supost`:

```bash
supost version            # → v0.1.0
supost listings            # → JSON seed data
supost serve               # → http://localhost:8080
```

The Go module path (`github.com/Capmus-Team/supost-cli`) handles the repo name, while `scaffold.sh supost` set the binary name, command names, and config file names (`.supost.yaml`) all to the short version.

> **Tip:** The first argument to `scaffold.sh` is the **binary name** (what users type). The second argument is the **Go module path** (which typically matches your GitHub repo URL). They don't need to match.

## What Gets Generated

```
myapp/
├── AGENTS.md                        # AI agent governance file (copy this in)
├── README.md                        # project README
├── Makefile                         # build, test, lint, check, serve, clean
├── main.go                          # entrypoint (wiring only)
├── go.mod / go.sum
├── .gitignore
├── .editorconfig                    # consistent formatting across editors
├── .golangci.yml                    # linter configuration
├── .env.example                     # environment variables (shared with Next.js)
│
├── .github/workflows/ci.yml        # GitHub Actions: build, test, lint
│
├── cmd/                             # one Cobra command per file
│   ├── root.go                      # root command + global flags
│   ├── version.go                   # myapp version
│   ├── listings.go                  # myapp listings (works immediately)
│   └── serve.go                     # myapp serve (preview HTTP server)
│
├── internal/
│   ├── config/config.go             # centralized config (Viper)
│   ├── service/                     # business logic (the brain)
│   │   ├── listings.go
│   │   └── listings_test.go         # table-driven tests with mock repo
│   ├── domain/                      # shared types → Supabase tables
│   │   ├── listing.go               # with json/db tags
│   │   ├── user.go                  # with json/db tags
│   │   └── errors.go                # HTTP-mappable error types
│   ├── repository/                  # swappable data access
│   │   ├── interfaces.go            # shared interface
│   │   └── inmemory.go              # in-memory adapter (zero deps!)
│   ├── adapters/output.go           # JSON/table/text rendering
│   └── util/util.go
│
├── migrations/                      # Supabase-ready SQL schema
│   ├── 001_create_profiles.sql      # with RLS policy stubs
│   ├── 002_create_listings.sql
│   └── README.md
│
├── configs/config.yaml.example
└── testdata/seed/listings.json      # seed data (importable to Supabase)
```

## Key Features

### Works Immediately (No Database Required)

The generated project ships with an **in-memory repository** pre-loaded with seed data. Every command works out of the box:

```bash
go run . listings             # returns seed data as JSON
go run . serve                # starts HTTP server with /api/listings
```

When you're ready for a real database, swap one line in `cmd/` — no changes to business logic.

### AI-Agent Friendly

The `AGENTS.md` file enforces:

- Flat project structure (max 3 levels deep, no bridge packages)
- Strict dependency direction (cmd/ → service/ → repository/, never backwards)
- File size limits (300 line target, 500 line ceiling)
- Core-first workflow (write business logic before CLI wiring)
- JSON tags on every domain type (API contract for the frontend)

### Supabase-Ready

- Domain types have `json` and `db` struct tags matching Postgres column names
- SQL migrations with UUID keys, `TIMESTAMPTZ`, indexes, and RLS policy stubs
- `.env.example` uses the same env var names as Next.js + Supabase
- Seed data in JSON format, importable directly into Supabase
- §12 in AGENTS.md has step-by-step migration instructions

### Preview HTTP Server

`myapp serve` starts a lightweight `net/http` server exposing the service layer as JSON endpoints. Prototype your API before building the Next.js frontend:

```bash
go run . serve
# GET http://localhost:8080/api/listings
# GET http://localhost:8080/api/health
```

### CI/CD Out of the Box

Generated projects include a GitHub Actions workflow that runs on every push/PR:
- Format check (`gofmt`)
- Vet (`go vet`)
- Build
- Test with race detector
- Lint (`golangci-lint`)

## What's in This Template Repo

| File | Purpose |
|---|---|
| `scaffold.sh` | Project generator — run this to create a new project |
| `AGENTS.md` | AI governance file — copy into generated projects |
| `README.md` | This file — docs for the template itself |
| `LICENSE` | MIT license |
| `docs/cheatsheet.md` | Copy-paste templates for common patterns |
| `.gitignore` | For the template repo itself |

## Customizing

### Not using Supabase?

Remove `migrations/`, `db` tags, and §0/§2.5/§5.8/§12 from AGENTS.md. The core architecture works for any Go CLI.

### Different domain?

Replace `Listing` and `User` with your own types. The structure stays the same.

### Want more HTTP endpoints?

Add handlers in `cmd/serve.go`. Each handler calls the service layer and returns JSON — same pattern as the listings endpoint.

## Requirements

- **Go 1.21+**
- **Bash** (for the scaffold script)
- **Optional**: `golangci-lint`, `psql`

## License

MIT — see [LICENSE](LICENSE).
