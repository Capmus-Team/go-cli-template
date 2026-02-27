#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# Go CLI Project Scaffolder (Supabase/Next.js Prototype)
# Creates the Cobra CLI project structure defined in AGENTS.md
#
# Usage:
#   ./scaffold.sh myapp
#   ./scaffold.sh myapp github.com/yourname/myapp
# ============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

log()  { echo -e "${GREEN}✓${NC} $1"; }
info() { echo -e "${CYAN}→${NC} $1"; }
err()  { echo -e "${RED}✗${NC} $1" >&2; exit 1; }

# ---------------------------------------------------------------------------
# Args
# ---------------------------------------------------------------------------
APP_NAME="${1:-}"
MODULE_PATH="${2:-}"

if [[ -z "$APP_NAME" ]]; then
    err "Usage: ./scaffold.sh <app-name> [module-path]\n  Example: ./scaffold.sh supost github.com/greg/supost"
fi

if [[ -d "$APP_NAME" ]]; then
    err "Directory '$APP_NAME' already exists. Pick a new name or remove it first."
fi

if [[ -z "$MODULE_PATH" ]]; then
    MODULE_PATH="$APP_NAME"
    info "No module path provided — using '${MODULE_PATH}'"
fi

# Helper to write files with the correct module path
mod() { sed "s|MODPATH|${MODULE_PATH}|g"; }

# ---------------------------------------------------------------------------
# Create directory structure
# ---------------------------------------------------------------------------
info "Scaffolding ${BOLD}${APP_NAME}${NC} ..."

mkdir -p "${APP_NAME}"/{cmd,internal/{config,service,domain,repository,adapters,util},migrations,configs,testdata/{fixtures,seed},.github/workflows}

log "Created directory structure"

# ---------------------------------------------------------------------------
# main.go
# ---------------------------------------------------------------------------
cat > "${APP_NAME}/main.go" << EOF
package main

import "${MODULE_PATH}/cmd"

func main() {
	cmd.Execute()
}
EOF
log "Created main.go"

# ---------------------------------------------------------------------------
# cmd/root.go
# ---------------------------------------------------------------------------
cat << 'EOF' | mod > "${APP_NAME}/cmd/root.go"
package cmd

import (
	"fmt"
	"os"

	"github.com/spf13/cobra"
	"github.com/spf13/viper"
)

var cfgFile string

var rootCmd = &cobra.Command{
	Use:   "APP_NAME_PH",
	Short: "APP_NAME_PH — a CLI tool",
	Long:  `APP_NAME_PH is a command-line application built with Cobra.`,
}

// Execute is called by main.go — the single entrypoint into the CLI.
func Execute() {
	if err := rootCmd.Execute(); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}

func init() {
	cobra.OnInitialize(initConfig)
	rootCmd.PersistentFlags().StringVar(&cfgFile, "config", "", "config file (default is $HOME/.APP_NAME_PH.yaml)")
	rootCmd.PersistentFlags().BoolP("verbose", "v", false, "enable verbose output")
	rootCmd.PersistentFlags().String("format", "json", "output format: json, table, text")
}

func initConfig() {
	if cfgFile != "" {
		viper.SetConfigFile(cfgFile)
	} else {
		home, err := os.UserHomeDir()
		cobra.CheckErr(err)
		viper.AddConfigPath(home)
		viper.AddConfigPath(".")
		viper.SetConfigType("yaml")
		viper.SetConfigName(".APP_NAME_PH")
	}

	viper.AutomaticEnv()

	if err := viper.ReadInConfig(); err == nil {
		if verbose, _ := rootCmd.Flags().GetBool("verbose"); verbose {
			fmt.Fprintln(os.Stderr, "Using config file:", viper.ConfigFileUsed())
		}
	}
}
EOF
sed -i "s/APP_NAME_PH/${APP_NAME}/g" "${APP_NAME}/cmd/root.go"
log "Created cmd/root.go"

# ---------------------------------------------------------------------------
# cmd/version.go
# ---------------------------------------------------------------------------
cat > "${APP_NAME}/cmd/version.go" << 'EOF'
package cmd

import (
	"fmt"

	"github.com/spf13/cobra"
)

// Version is updated on every release. See AGENTS.md §11.
var Version = "0.1.0"

var versionCmd = &cobra.Command{
	Use:   "version",
	Short: "Print the version number",
	RunE: func(cmd *cobra.Command, args []string) error {
		fmt.Printf("v%s\n", Version)
		return nil
	},
}

func init() {
	rootCmd.AddCommand(versionCmd)
}
EOF
log "Created cmd/version.go"

# ---------------------------------------------------------------------------
# cmd/listings.go — working command using in-memory repo
# ---------------------------------------------------------------------------
cat << 'EOF' | mod > "${APP_NAME}/cmd/listings.go"
package cmd

import (
	"fmt"

	"MODPATH/internal/adapters"
	"MODPATH/internal/config"
	"MODPATH/internal/repository"
	"MODPATH/internal/service"

	"github.com/spf13/cobra"
)

var listingsCmd = &cobra.Command{
	Use:   "listings",
	Short: "List active marketplace listings",
	Long:  `Display all active listings from the marketplace. Uses in-memory seed data by default.`,
	RunE: func(cmd *cobra.Command, args []string) error {
		cfg, err := config.Load()
		if err != nil {
			return fmt.Errorf("loading config: %w", err)
		}

		// Composition root: choose the repository adapter.
		// Swap to repository.NewPostgres(cfg.DatabaseURL) when ready.
		repo := repository.NewInMemory()
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
	listingsCmd.Flags().StringP("category", "c", "", "filter by category")
}
EOF
log "Created cmd/listings.go"

# ---------------------------------------------------------------------------
# cmd/serve.go — lightweight HTTP preview server
# ---------------------------------------------------------------------------
cat << 'EOF' | mod > "${APP_NAME}/cmd/serve.go"
package cmd

import (
	"encoding/json"
	"fmt"
	"log"
	"net/http"

	"MODPATH/internal/config"
	"MODPATH/internal/repository"
	"MODPATH/internal/service"

	"github.com/spf13/cobra"
)

var serveCmd = &cobra.Command{
	Use:   "serve",
	Short: "Start a preview HTTP server",
	Long: `Start a lightweight HTTP server that exposes the service layer as JSON
endpoints. This is for prototyping only — it will be replaced by Next.js
API routes in production. Uses in-memory data by default.`,
	RunE: func(cmd *cobra.Command, args []string) error {
		cfg, err := config.Load()
		if err != nil {
			return fmt.Errorf("loading config: %w", err)
		}

		port := cfg.Port
		if port == 0 {
			port = 8080
		}

		// Composition root: choose the repository adapter.
		repo := repository.NewInMemory()
		listingSvc := service.NewListingService(repo)

		mux := http.NewServeMux()

		// GET /api/listings — returns active listings as JSON
		mux.HandleFunc("GET /api/listings", func(w http.ResponseWriter, r *http.Request) {
			listings, err := listingSvc.ListActive(r.Context())
			if err != nil {
				http.Error(w, err.Error(), http.StatusInternalServerError)
				return
			}
			w.Header().Set("Content-Type", "application/json")
			json.NewEncoder(w).Encode(listings)
		})

		// Health check
		mux.HandleFunc("GET /api/health", func(w http.ResponseWriter, r *http.Request) {
			w.Header().Set("Content-Type", "application/json")
			json.NewEncoder(w).Encode(map[string]string{"status": "ok"})
		})

		addr := fmt.Sprintf(":%d", port)
		log.Printf("Preview server running at http://localhost%s", addr)
		log.Printf("  GET /api/listings")
		log.Printf("  GET /api/health")
		log.Printf("Press Ctrl+C to stop.")
		return http.ListenAndServe(addr, mux)
	},
}

func init() {
	rootCmd.AddCommand(serveCmd)
	serveCmd.Flags().IntP("port", "p", 8080, "port to listen on")
}
EOF
log "Created cmd/serve.go"

# ---------------------------------------------------------------------------
# internal/config/config.go
# ---------------------------------------------------------------------------
cat > "${APP_NAME}/internal/config/config.go" << 'EOF'
package config

import "github.com/spf13/viper"

// Config holds all application configuration.
// All config loads through this package. No os.Getenv() elsewhere.
// See AGENTS.md §5.2.
type Config struct {
	Verbose     bool   `json:"verbose"`
	Format      string `json:"format"`
	DatabaseURL string `json:"database_url"` // postgresql://user:pass@host:port/dbname
	Port        int    `json:"port"`

	// Supabase (used by future Next.js frontend — shared .env)
	SupabaseURL    string `json:"supabase_url"`
	SupabaseAnonKey string `json:"supabase_anon_key"`
}

// Load reads configuration from viper (merges file + env + flags).
func Load() (*Config, error) {
	return &Config{
		Verbose:        viper.GetBool("verbose"),
		Format:         viper.GetString("format"),
		DatabaseURL:    viper.GetString("database_url"),
		Port:           viper.GetInt("port"),
		SupabaseURL:    viper.GetString("supabase_url"),
		SupabaseAnonKey: viper.GetString("supabase_anon_key"),
	}, nil
}
EOF
log "Created internal/config/config.go"

# ---------------------------------------------------------------------------
# internal/domain/
# ---------------------------------------------------------------------------
cat > "${APP_NAME}/internal/domain/user.go" << 'EOF'
package domain

import "time"

// User maps to the Supabase "profiles" table.
// TypeScript equivalent: interface User { id: string; email: string; ... }
// Keep types plain — string, int, time.Time, []string — for TypeScript portability.
type User struct {
	ID        string    `json:"id"         db:"id"`
	Email     string    `json:"email"      db:"email"`
	Name      string    `json:"name"       db:"name"`
	CreatedAt time.Time `json:"created_at" db:"created_at"`
	UpdatedAt time.Time `json:"updated_at" db:"updated_at"`
}
EOF

cat > "${APP_NAME}/internal/domain/listing.go" << 'EOF'
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
EOF

cat > "${APP_NAME}/internal/domain/errors.go" << 'EOF'
package domain

import "errors"

// Domain errors. Designed to map cleanly to HTTP status codes.
// NotFound → 404, Validation → 400, Unauthorized → 401, Conflict → 409.
var (
	ErrNotFound     = errors.New("not found")
	ErrUnauthorized = errors.New("unauthorized")
	ErrConflict     = errors.New("conflict")

	// Validation errors
	ErrMissingTitle = errors.New("title is required")
	ErrInvalidPrice = errors.New("price must be non-negative")
)
EOF
log "Created internal/domain/"

# ---------------------------------------------------------------------------
# internal/service/listings.go
# ---------------------------------------------------------------------------
cat << 'EOF' | mod > "${APP_NAME}/internal/service/listings.go"
// Package service contains the core business logic.
// Services are 100% CLI-agnostic: no Cobra, no os.Exit(), no stdout.
// Services accept interfaces and are fully testable.
// See AGENTS.md §2.4, §6.1.
package service

import (
	"context"

	"MODPATH/internal/domain"
)

// ListingRepository defines the data access interface for listings.
// Defined here (where consumed), not in repository/ (where implemented).
type ListingRepository interface {
	ListActive(ctx context.Context) ([]domain.Listing, error)
	GetByID(ctx context.Context, id string) (*domain.Listing, error)
	Create(ctx context.Context, listing *domain.Listing) error
}

// ListingService orchestrates listing-related business logic.
type ListingService struct {
	repo ListingRepository
}

// NewListingService creates a new ListingService.
func NewListingService(repo ListingRepository) *ListingService {
	return &ListingService{repo: repo}
}

// ListActive returns all active listings.
func (s *ListingService) ListActive(ctx context.Context) ([]domain.Listing, error) {
	return s.repo.ListActive(ctx)
}

// Create validates and persists a new listing.
func (s *ListingService) Create(ctx context.Context, listing *domain.Listing) error {
	if err := listing.Validate(); err != nil {
		return err
	}
	return s.repo.Create(ctx, listing)
}
EOF
log "Created internal/service/listings.go"

# ---------------------------------------------------------------------------
# internal/service/listings_test.go
# ---------------------------------------------------------------------------
cat << 'EOF' | mod > "${APP_NAME}/internal/service/listings_test.go"
package service

import (
	"context"
	"testing"

	"MODPATH/internal/domain"
)

// mockListingRepo is a minimal test double.
type mockListingRepo struct {
	listings []domain.Listing
	created  []*domain.Listing
}

func (m *mockListingRepo) ListActive(_ context.Context) ([]domain.Listing, error) {
	var active []domain.Listing
	for _, l := range m.listings {
		if l.Status == "active" {
			active = append(active, l)
		}
	}
	return active, nil
}

func (m *mockListingRepo) GetByID(_ context.Context, id string) (*domain.Listing, error) {
	for _, l := range m.listings {
		if l.ID == id {
			return &l, nil
		}
	}
	return nil, domain.ErrNotFound
}

func (m *mockListingRepo) Create(_ context.Context, listing *domain.Listing) error {
	m.created = append(m.created, listing)
	return nil
}

func TestListingService_ListActive(t *testing.T) {
	repo := &mockListingRepo{
		listings: []domain.Listing{
			{ID: "1", Title: "Active Item", Status: "active"},
			{ID: "2", Title: "Sold Item", Status: "sold"},
		},
	}
	svc := NewListingService(repo)

	items, err := svc.ListActive(context.Background())
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(items) != 1 {
		t.Errorf("expected 1 active listing, got %d", len(items))
	}
}

func TestListingService_Create_Validation(t *testing.T) {
	repo := &mockListingRepo{}
	svc := NewListingService(repo)

	tests := []struct {
		name    string
		listing domain.Listing
		wantErr bool
	}{
		{
			name:    "valid listing",
			listing: domain.Listing{Title: "Textbook", Price: 4500},
			wantErr: false,
		},
		{
			name:    "missing title",
			listing: domain.Listing{Title: "", Price: 4500},
			wantErr: true,
		},
		{
			name:    "negative price",
			listing: domain.Listing{Title: "Textbook", Price: -100},
			wantErr: true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			err := svc.Create(context.Background(), &tt.listing)
			if (err != nil) != tt.wantErr {
				t.Errorf("Create() error = %v, wantErr %v", err, tt.wantErr)
			}
		})
	}
}
EOF
log "Created internal/service/listings_test.go"

# ---------------------------------------------------------------------------
# internal/repository/interfaces.go
# ---------------------------------------------------------------------------
cat << 'EOF' | mod > "${APP_NAME}/internal/repository/interfaces.go"
// Package repository handles all data access.
// The interface is defined in service/ (where consumed). This package
// provides concrete implementations: inmemory.go for prototyping,
// postgres.go for production.
// See AGENTS.md §2.4, §5.8, §6.5.
package repository

import (
	"context"

	"MODPATH/internal/domain"
)

// ListingStore is the shared interface for listing data access.
// Defined here because both inmemory and postgres adapters implement it,
// and cmd/ needs to reference the concrete constructors.
type ListingStore interface {
	ListActive(ctx context.Context) ([]domain.Listing, error)
	GetByID(ctx context.Context, id string) (*domain.Listing, error)
	Create(ctx context.Context, listing *domain.Listing) error
}
EOF
log "Created internal/repository/interfaces.go"

# ---------------------------------------------------------------------------
# internal/repository/inmemory.go — zero-dependency prototype adapter
# ---------------------------------------------------------------------------
cat << 'EOF' | mod > "${APP_NAME}/internal/repository/inmemory.go"
package repository

import (
	"context"
	"fmt"
	"sync"
	"time"

	"MODPATH/internal/domain"
)

// InMemory implements ListingStore using an in-memory map.
// Perfect for prototyping and testing — zero external dependencies.
// Swap to Postgres when ready. See AGENTS.md §6.5.
type InMemory struct {
	mu       sync.RWMutex
	listings map[string]domain.Listing
}

// NewInMemory creates a new in-memory repository pre-loaded with seed data.
func NewInMemory() *InMemory {
	repo := &InMemory{
		listings: make(map[string]domain.Listing),
	}
	repo.loadSeedData()
	return repo
}

func (r *InMemory) ListActive(_ context.Context) ([]domain.Listing, error) {
	r.mu.RLock()
	defer r.mu.RUnlock()

	var active []domain.Listing
	for _, l := range r.listings {
		if l.Status == "active" {
			active = append(active, l)
		}
	}
	return active, nil
}

func (r *InMemory) GetByID(_ context.Context, id string) (*domain.Listing, error) {
	r.mu.RLock()
	defer r.mu.RUnlock()

	l, ok := r.listings[id]
	if !ok {
		return nil, domain.ErrNotFound
	}
	return &l, nil
}

func (r *InMemory) Create(_ context.Context, listing *domain.Listing) error {
	r.mu.Lock()
	defer r.mu.Unlock()

	if listing.ID == "" {
		listing.ID = fmt.Sprintf("mem-%d", len(r.listings)+1)
	}
	now := time.Now()
	listing.CreatedAt = now
	listing.UpdatedAt = now
	if listing.Status == "" {
		listing.Status = "active"
	}

	r.listings[listing.ID] = *listing
	return nil
}

// loadSeedData populates the repository with sample data.
// In a more advanced setup, this could read from testdata/seed/*.json.
func (r *InMemory) loadSeedData() {
	now := time.Now()
	seeds := []domain.Listing{
		{
			ID:          "seed-1",
			UserID:      "user-1",
			Title:       "Used Calculus Textbook",
			Description: "Stewart Calculus, 8th edition. Some highlighting.",
			Price:       4500,
			Category:    "textbooks",
			Status:      "active",
			CreatedAt:   now,
			UpdatedAt:   now,
		},
		{
			ID:          "seed-2",
			UserID:      "user-1",
			Title:       "IKEA Desk",
			Description: "MALM desk, white. Good condition. Pickup only.",
			Price:       6000,
			Category:    "furniture",
			Status:      "active",
			CreatedAt:   now,
			UpdatedAt:   now,
		},
		{
			ID:          "seed-3",
			UserID:      "user-2",
			Title:       "Trek Road Bike",
			Description: "2021 Domane AL 2, 56cm. Low miles.",
			Price:       55000,
			Category:    "bikes",
			Status:      "active",
			CreatedAt:   now,
			UpdatedAt:   now,
		},
	}

	for _, s := range seeds {
		r.listings[s.ID] = s
	}
}
EOF
log "Created internal/repository/inmemory.go"

# ---------------------------------------------------------------------------
# internal/adapters/output.go
# ---------------------------------------------------------------------------
cat > "${APP_NAME}/internal/adapters/output.go" << 'EOF'
// Package adapters handles external side effects and output rendering.
// See AGENTS.md §2.4, §5.5.
package adapters

import (
	"encoding/json"
	"fmt"
	"io"
	"os"
)

// Render outputs data in the specified format.
// Default is JSON (the eventual consumer is a web frontend).
func Render(format string, data interface{}) error {
	return RenderTo(os.Stdout, format, data)
}

// RenderTo outputs data to a specific writer (testable).
func RenderTo(w io.Writer, format string, data interface{}) error {
	switch format {
	case "json", "":
		enc := json.NewEncoder(w)
		enc.SetIndent("", "  ")
		return enc.Encode(data)
	case "text":
		_, err := fmt.Fprintf(w, "%v\n", data)
		return err
	default:
		return fmt.Errorf("unsupported format: %s", format)
	}
}
EOF
log "Created internal/adapters/output.go"

# ---------------------------------------------------------------------------
# internal/util/util.go
# ---------------------------------------------------------------------------
cat > "${APP_NAME}/internal/util/util.go" << 'EOF'
// Package util provides small, stateless, pure helper functions.
// LEAF package — must not import from any other internal/ package.
// See AGENTS.md §2.4.
package util
EOF
log "Created internal/util/util.go"

# ---------------------------------------------------------------------------
# migrations/
# ---------------------------------------------------------------------------
cat > "${APP_NAME}/migrations/001_create_profiles.sql" << 'EOF'
-- Migration 001: Create profiles table
-- Maps to: internal/domain/user.go → User struct
-- Supabase note: auth.users is managed by Supabase Auth.

CREATE TABLE IF NOT EXISTS profiles (
    id          UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    email       TEXT NOT NULL,
    name        TEXT NOT NULL DEFAULT '',
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_profiles_email ON profiles(email);

-- TODO: Enable RLS when deploying to Supabase
-- ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;
-- CREATE POLICY "Users can view all profiles" ON profiles FOR SELECT USING (true);
-- CREATE POLICY "Users can update own profile" ON profiles FOR UPDATE USING (auth.uid() = id);
EOF

cat > "${APP_NAME}/migrations/002_create_listings.sql" << 'EOF'
-- Migration 002: Create listings table
-- Maps to: internal/domain/listing.go → Listing struct

CREATE TABLE IF NOT EXISTS listings (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id     UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    title       TEXT NOT NULL,
    description TEXT NOT NULL DEFAULT '',
    price       INTEGER NOT NULL DEFAULT 0,
    category    TEXT NOT NULL DEFAULT '',
    status      TEXT NOT NULL DEFAULT 'active',
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_listings_user_id ON listings(user_id);
CREATE INDEX IF NOT EXISTS idx_listings_status ON listings(status);
CREATE INDEX IF NOT EXISTS idx_listings_category ON listings(category);
CREATE INDEX IF NOT EXISTS idx_listings_created_at ON listings(created_at DESC);

-- TODO: Enable RLS when deploying to Supabase
-- ALTER TABLE listings ENABLE ROW LEVEL SECURITY;
-- CREATE POLICY "Anyone can view active listings" ON listings
--     FOR SELECT USING (status = 'active');
-- CREATE POLICY "Users can manage own listings" ON listings
--     FOR ALL USING (auth.uid() = user_id);
EOF

cat > "${APP_NAME}/migrations/README.md" << 'EOF'
# Migrations

SQL files that define the database schema. **Single source of truth.**

## Applying Locally

```bash
psql $DATABASE_URL -f migrations/001_create_profiles.sql
psql $DATABASE_URL -f migrations/002_create_listings.sql
```

## Applying to Supabase

1. Open the Supabase SQL Editor
2. Paste each migration in order
3. Uncomment the RLS policies
4. Run

## Rules

- Never modify an existing migration — create a new one
- Number sequentially: `003_add_images.sql`
- Each migration should be idempotent (`IF NOT EXISTS`)
- Include commented-out RLS policies for Supabase
EOF
log "Created migrations/"

# ---------------------------------------------------------------------------
# testdata/seed/
# ---------------------------------------------------------------------------
cat > "${APP_NAME}/testdata/seed/listings.json" << 'EOF'
[
  {
    "title": "Used Calculus Textbook",
    "description": "Stewart Calculus, 8th edition. Some highlighting.",
    "price": 4500,
    "category": "textbooks",
    "status": "active"
  },
  {
    "title": "IKEA Desk",
    "description": "MALM desk, white. Good condition. Pickup only.",
    "price": 6000,
    "category": "furniture",
    "status": "active"
  },
  {
    "title": "Trek Road Bike",
    "description": "2021 Domane AL 2, 56cm. Low miles.",
    "price": 55000,
    "category": "bikes",
    "status": "active"
  }
]
EOF
log "Created testdata/seed/"

# ---------------------------------------------------------------------------
# configs/config.yaml.example
# ---------------------------------------------------------------------------
cat > "${APP_NAME}/configs/config.yaml.example" << EOF
# Example configuration for ${APP_NAME}
# Copy to ~/.${APP_NAME}.yaml or ./${APP_NAME}.yaml

verbose: false
format: json
port: 8080

# Supabase Postgres connection (leave empty to use in-memory)
# Local:    postgresql://postgres:postgres@localhost:54322/postgres
# Supabase: get from Project Settings → Database → Connection string
database_url: ""
supabase_url: ""
supabase_anon_key: ""
EOF
log "Created configs/"

# ---------------------------------------------------------------------------
# .env.example
# ---------------------------------------------------------------------------
cat > "${APP_NAME}/.env.example" << EOF
# Environment variables for ${APP_NAME}
# Copy to .env and fill in values. Never commit .env to git.
# These are the SAME env vars your Next.js frontend will use.

# Supabase / Postgres (leave empty to use in-memory prototype)
DATABASE_URL=
SUPABASE_URL=
SUPABASE_ANON_KEY=
SUPABASE_SERVICE_ROLE_KEY=

# App
PORT=8080
VERBOSE=false
FORMAT=json
EOF
log "Created .env.example"

# ---------------------------------------------------------------------------
# .editorconfig
# ---------------------------------------------------------------------------
cat > "${APP_NAME}/.editorconfig" << 'EOF'
root = true

[*]
charset = utf-8
end_of_line = lf
insert_final_newline = true
trim_trailing_whitespace = true
indent_style = tab
indent_size = 4

[*.go]
indent_style = tab

[*.{yml,yaml,json,md,sql}]
indent_style = space
indent_size = 2

[Makefile]
indent_style = tab
EOF
log "Created .editorconfig"

# ---------------------------------------------------------------------------
# .golangci.yml
# ---------------------------------------------------------------------------
cat > "${APP_NAME}/.golangci.yml" << 'EOF'
run:
  timeout: 5m

linters:
  enable:
    - errcheck
    - govet
    - ineffassign
    - staticcheck
    - unused
    - gofmt
    - misspell
    - gosimple
    - gocritic

linters-settings:
  gocritic:
    enabled-tags:
      - diagnostic
      - style
    disabled-checks:
      - ifElseChain
      - hugeParam

issues:
  exclude-rules:
    - path: _test\.go
      linters:
        - gocritic
        - errcheck
EOF
log "Created .golangci.yml"

# ---------------------------------------------------------------------------
# .github/workflows/ci.yml
# ---------------------------------------------------------------------------
cat > "${APP_NAME}/.github/workflows/ci.yml" << 'EOF'
name: CI

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  check:
    name: Build & Test
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-go@v5
        with:
          go-version: '1.21'
      - name: Format check
        run: test -z "$(gofmt -l .)" || (gofmt -l . && exit 1)
      - name: Vet
        run: go vet ./...
      - name: Build
        run: go build ./...
      - name: Test
        run: go test ./... -race -coverprofile=coverage.out
      - name: Upload coverage
        if: github.event_name == 'push'
        uses: actions/upload-artifact@v4
        with:
          name: coverage
          path: coverage.out

  lint:
    name: Lint
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-go@v5
        with:
          go-version: '1.21'
      - uses: golangci/golangci-lint-action@v4
        with:
          version: latest
EOF
log "Created .github/workflows/ci.yml"

# ---------------------------------------------------------------------------
# Makefile
# ---------------------------------------------------------------------------
cat > "${APP_NAME}/Makefile" << 'MKEOF'
.PHONY: build test vet lint fmt check clean serve migrate

build:
	go build -o bin/APP_NAME_PH .

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

serve:
	go run . serve

migrate:
	@echo "Apply migrations to your database:"
	@for f in migrations/*.sql; do echo "  psql $$DATABASE_URL -f $$f"; done

clean:
	rm -rf bin/ coverage.out
MKEOF
sed -i "s/APP_NAME_PH/${APP_NAME}/g" "${APP_NAME}/Makefile"
log "Created Makefile"

# ---------------------------------------------------------------------------
# .gitignore
# ---------------------------------------------------------------------------
cat > "${APP_NAME}/.gitignore" << EOF
bin/
${APP_NAME}
dist/
.DS_Store
Thumbs.db
.idea/
.vscode/
*.swp
*.swo
vendor/
coverage.out
.${APP_NAME}.yaml
.env
EOF
log "Created .gitignore"

# ---------------------------------------------------------------------------
# README.md
# ---------------------------------------------------------------------------
cat > "${APP_NAME}/README.md" << EOF
# ${APP_NAME}

A university marketplace CLI prototype. Production stack: Supabase + Next.js.

## Quick Start

\`\`\`bash
go run . version              # → v0.1.0
go run . listings             # → JSON list of seed data (no DB needed)
go run . serve                # → preview server at http://localhost:8080
curl localhost:8080/api/listings  # → JSON response
\`\`\`

No database, no API keys, no Docker required. Works immediately.

## Development

\`\`\`bash
cp .env.example .env                # optional: configure database
cp configs/config.yaml.example .${APP_NAME}.yaml

make check    # format, vet, build, test
make build    # compile binary to bin/
make test     # run tests with race detector
make serve    # start preview HTTP server
make migrate  # show migration commands
make clean    # remove build artifacts
\`\`\`

## Project Structure

See [AGENTS.md](AGENTS.md) for the full architecture guide.

## Connecting a Database

The app uses in-memory seed data by default. To connect Postgres/Supabase:

1. Set \`DATABASE_URL\` in \`.env\`
2. Run migrations: \`make migrate\`
3. Swap the repository adapter in \`cmd/\` files (see AGENTS.md §6.5)

## Migration to Production

1. Apply \`migrations/*.sql\` to Supabase (uncomment RLS policies)
2. Translate \`internal/domain/\` structs → TypeScript interfaces
3. Port \`internal/service/\` logic → Next.js API routes
4. Import \`testdata/seed/\` into Supabase for test data
EOF
log "Created README.md"

# ---------------------------------------------------------------------------
# Initialize Go module + install deps
# ---------------------------------------------------------------------------
cd "${APP_NAME}"

if command -v go &> /dev/null; then
    go mod init "${MODULE_PATH}" 2>/dev/null
    log "Initialized go.mod (module: ${MODULE_PATH})"

    go get github.com/spf13/cobra@latest 2>/dev/null
    go get github.com/spf13/viper@latest 2>/dev/null
    log "Installed cobra + viper"

    go mod tidy 2>/dev/null
    log "Ran go mod tidy"

    if go build ./... 2>/dev/null; then
        log "Build passed"
    else
        info "Build had issues — run 'go mod tidy' again"
    fi

    if go test ./... -count=1 2>/dev/null; then
        log "Tests passed"
    else
        info "Some tests failed — check with 'go test -v ./...'"
    fi
else
    info "Go not found in PATH — skipping module init. Run these manually:"
    echo "  cd ${APP_NAME}"
    echo "  go mod init ${MODULE_PATH}"
    echo "  go get github.com/spf13/cobra@latest github.com/spf13/viper@latest"
    echo "  go mod tidy"
fi

cd ..

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo -e "${BOLD}Done!${NC} Project ready at ${BOLD}./${APP_NAME}/${NC}"
echo ""
find "${APP_NAME}" -type f -not -path '*/go.sum' -not -path '*/.git/*' | sort | sed "s|^|  |"
echo ""
echo -e "  ${CYAN}Try it now:${NC}"
echo "    cd ${APP_NAME}"
echo "    go run . version                 # → v0.1.0"
echo "    go run . listings                # → JSON seed data"
echo "    go run . listings --format text  # → plain text"
echo "    go run . serve                   # → http://localhost:8080"
echo "    curl localhost:8080/api/listings  # → JSON response"
echo ""
echo -e "  ${CYAN}Development:${NC}"
echo "    make check                       # format + vet + build + test"
echo ""
echo -e "  ${CYAN}Build your first feature:${NC}"
echo "    1. Write migration in migrations/003_xxx.sql"
echo "    2. Add domain type in internal/domain/"
echo "    3. Add logic in internal/service/"
echo "    4. Add to repository interface + inmemory.go"
echo "    5. Wire CLI command in cmd/"
echo "    6. Run: make check"
echo ""
