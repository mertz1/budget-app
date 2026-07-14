# CLAUDE.md — Household Budget App

## What this is
A month-focused personal/household budgeting app (web now, mobile later). Tracks
expenses, income (incl. rental), per-person cost splitting, and month-end
settlement between household members. Intended to run publicly for friends/strangers.

## Stack
- **Backend:** Go API. Postgres access via `pgx` + `sqlc` (raw SQL → type-safe Go).
- **DB + Auth + Storage:** Supabase (managed Postgres). Auth = Supabase/GoTrue;
  Go **verifies** JWTs against Supabase's JWKS — it does **not** own auth.
- **Frontend:** React or Vue (undecided) — a thin client over the Go API.
- **Mobile:** deferred. PWA-first unless native is explicitly chosen.
- **Monorepo:** `/apps` (api, web, mobile) + `/packages` (shared, db).

## Non-negotiable invariants (these change how you write code)
- **Money is always integer cents** (`bigint`). Never floats. Do ratio math with
  care and round explicitly; store results as cents.
- **Multi-tenant: every query is scoped by `household_id`** in the Go data layer.
  Go connects as a privileged role and **bypasses RLS**, so app-layer scoping is
  the real guarantee; RLS is a backstop only. A query without a household filter
  is a bug.
- **Do not hand-roll auth.** No password hashing, OAuth flows, or session logic in
  this codebase. Supabase issues tokens; Go verifies signature + claims via JWKS.
- **Members ≠ users.** `members` are payers/participants and may have no login
  (`user_id` nullable). `users` are auth identities. Don't conflate them.
- **Split attribution:** `expenses.split_rule ∈ {full, equal, income_weighted,
  custom}`. Resolved per-member amounts live in `expense_splits`.
  - `full` / `equal` / `custom` resolve deterministically at write time.
  - `income_weighted` is **derived live for an open month**, then **frozen**
    (`expense_splits.frozen_at`) when the month is settled. Never mutate a frozen
    split.
- **Splits resolve across all active members.** No per-expense participant subset;
  use `custom` weights (zero-weight to exclude) for uneven cases. No debt netting.
- **Budgets** are per category per month, `goal_type ∈ {percent_of_income,
  fixed_amount}`.

## Domain logic belongs on the server
Splits, income proportions, tax, and CSV/statement import run in Go — never in the
client. The client sends inputs; the server resolves and persists.

## Import pipeline (later, but leave seams)
Statement/CSV import is async + human-reviewed: upload → object storage → background
worker → parse (deterministic mappers, LLM fallback behind an interface) → user
confirms → commit → feed corrections into `merchant_category_map`.

## Deeper docs (read when relevant, don't duplicate here)
- `docs/ARCHITECTURE.md` — decisions + rationale
- `docs/schema.sql` — Postgres DDL (source of truth for the model)
- `budget_schema.mermaid` — ERD (regenerate from DB with `mermerd` once migrated)

## Open decisions (resolve before/while building)
- Percent-budget income base: combined household income vs per-member.
- Frontend framework: React vs Vue.
- Mobile: PWA vs native (Expo).

## Commands
_TBD — fill in once scaffolding lands (build, test, migrate, lint)._
