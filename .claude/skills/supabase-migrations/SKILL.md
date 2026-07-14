---
name: supabase-migrations
description: >-
  Safe Supabase local development and Postgres schema migrations. Use this
  skill whenever the task involves creating or editing a Supabase migration,
  changing the database schema (adding/renaming/dropping tables or columns,
  changing types, adding constraints or enums), writing seed data, setting up
  or running the local Supabase stack, or deploying schema changes to a remote
  Supabase project. Trigger it even when the user only says things like "add a
  column", "change this table", "update the schema", "new migration", "set up
  the database locally", or "push to Supabase" — any schema change must go
  through this skill's expand/contract discipline so changes apply in order and
  never break a running app or lose data.
---

# Supabase Migrations & Local Development

Encodes a safe, forward-only migration workflow. The overriding goal: every
migration leaves the database in a state the **currently deployed app can still
talk to**, applies in a deterministic order, and never loses data.

## Core rules (non-negotiable)

1. **Migrations are immutable once applied.** Never edit a migration file that
   has already run (locally past a reset you've built on, or ever on remote).
   To fix the model, write a NEW migration. Editing applied migrations causes
   drift between files and the migration-history table.
2. **Forward-only.** No rewriting history. Corrections move forward.
3. **Additive-first.** A single migration must not both remove the old shape and
   require the new one. Split breaking changes across migrations (see
   expand/contract below).
4. **Never change the remote database directly** (SQL editor / Table editor).
   All schema changes go through migration files, or `supabase db push` will
   fail with sync errors.
5. **Ordering is automatic** — do not hand-number files. `supabase migration
   new <name>` timestamps the filename; migrations apply in ascending timestamp
   order. Just create them in the order you want them to run.

## Local development loop

```bash
supabase init                       # once: creates supabase/ + config.toml
supabase start                      # boots full local stack in Docker
supabase migration new <name>       # timestamped file in supabase/migrations/
# ...write SQL in that file...
supabase db reset                   # rebuild local DB, apply ALL migrations, run seed.sql
```

- `supabase start` runs Postgres, Auth (GoTrue), Storage, PostgREST, Studio, and
  a local mail inbox. Requires Docker. It prints local URLs/keys (Postgres
  ~`localhost:54322`, API gateway ~`54321`, Studio ~`54323`).
- `supabase db reset` is the workhorse: it recreates local Postgres, applies
  every migration in order, then runs `supabase/seed.sql`. Use it constantly to
  confirm the full migration chain applies cleanly from scratch.
- `supabase stop` shuts down without wiping local data; only `db reset` discards.

## Authoring style

- Write SQL migrations by hand when the change is known.
- Or make changes in Studio locally, then capture them with
  `supabase db diff -f <name>` into a migration file.
- After any schema change: run `supabase db reset`, then regenerate `sqlc` (this
  project uses pgx + sqlc) so Go types match the new schema.

## Expand / contract — the heart of "no breaking changes, no data loss"

Any change that could break a running app or lose data is split into ordered
migrations (and usually separate deploys):

1. **Expand** — add the new thing backward-compatibly (a *nullable* column, a new
   table). Nothing old breaks.
2. **Backfill** — populate/transform existing rows into the new shape.
3. **Contract** — only *after* the app stops using the old thing, drop or tighten
   it, in a later migration.

### Recipes for the dangerous operations

- **Add a required column** (never add `NOT NULL` to a populated table directly —
  it fails on existing rows):
  1. add column nullable
  2. backfill a value into every row
  3. later migration: `ALTER TABLE ... ALTER COLUMN ... SET NOT NULL`

- **Rename a column** (in-place rename instantly breaks a running app):
  1. add the new column
  2. backfill from the old column
  3. move app reads/writes to the new column
  4. later migration: drop the old column
  (Solo + willing to take a brief outage? An in-place rename is acceptable — but
  that trades away zero-downtime. Choose deliberately.)

- **Change a column's type:** add new column of new type → backfill with a cast →
  swap the app over → drop the old column.

- **Add a constraint to a large table:** add it `NOT VALID` first, then
  `VALIDATE CONSTRAINT` in a separate migration, to avoid a long lock while it
  checks every existing row.

- **Convert free text to a foreign key** (e.g., `expenses.merchant` → a
  `merchants` table): create table + add nullable `merchant_id` → backfill
  distinct values and set the FK → once the app writes `merchant_id`, drop the
  old text column. Three ordered migrations, no lost data.

## Enums: prefer text + CHECK for anything that will grow

Native Postgres enums are ergonomic but painful to evolve — you can
`ALTER TYPE ... ADD VALUE`, but you **cannot remove a value** without recreating
the type. Use enums only for truly fixed domains. For anything expected to grow
(e.g. income sources, categories), prefer **`text` + a `CHECK` constraint** or a
small **lookup table**, both of which evolve with a trivial additive migration.

## Seed vs. migrations

- Keep test/sample data out of migrations. Put it in `supabase/seed.sql`, which
  runs on every `db reset`.
- Migrations contain schema plus, at most, genuine reference data (e.g. default
  category groups) — not test fixtures.
- Backfills inside migrations can be plain `UPDATE`s at small (household-app)
  data volumes; batch/background them only when tables get large.

## Deploying to remote

```bash
supabase link                       # connect local repo to the cloud project
supabase db push                    # apply local migrations to remote
```

- For a public app, move `db push` into CI/CD (official GitHub Action) rather
  than pushing from a laptop.
- If a remote change was ever made outside migrations, `supabase db pull`
  captures it as a migration to re-sync before continuing.

## Pre-flight checklist before writing any migration

- [ ] Is this change additive? If not, split into expand → backfill → contract.
- [ ] Does the currently deployed app still work against the post-migration DB?
- [ ] Am I adding `NOT NULL`/constraints to populated tables safely (nullable +
      backfill first, or `NOT VALID` + validate)?
- [ ] Am I editing an already-applied migration? (Never — write a new one.)
- [ ] Did I `supabase db reset` to prove the whole chain applies from scratch?
- [ ] Did I regenerate sqlc so Go matches?

## Project conventions (see CLAUDE.md for the full set)

- Money is always integer cents (`bigint`), never floats.
- Every tenant-owned table has `household_id`; app-layer queries always scope by
  it (Go bypasses RLS — app scoping is the real guarantee).
- Never hand-roll auth. Supabase issues JWTs; Go verifies against JWKS.
