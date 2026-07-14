# Architecture & Decisions — Household Budget App

This records *why* the major choices were made, so the reasoning survives past the
conversation that produced it. CLAUDE.md holds the enforced invariants; this holds
the context behind them.

## 1. Scope & scale
Public, multi-tenant app for friends/strangers, holding financial PII. This is not
a household-only tool — signup is open — which makes multi-tenancy, real auth, data
isolation, backups, and account/data deletion first-class concerns.

## 2. Stack rationale
- **Go backend.** Chosen for control and because the eventual LLM-assisted import
  pipeline is long-running concurrent work that suits Go (goroutines, a small static
  binary) far better than serverless functions. Trade-off accepted: two languages
  (Go + JS frontend), bridged by generated types (OpenAPI→TS or Connect/gRPC).
- **pgx + sqlc.** Raw SQL with type-safe Go. Direct DB connection runs privileged and
  bypasses RLS → tenant isolation moves to the app layer (see invariants).
- **Supabase = managed Postgres + Auth + Storage.** Kept specifically for auth + RLS
  + storage being integrated — the tedious, security-sensitive surface a public app
  forces. Go treats it as: Postgres (pgx), identity provider (verify JWT via JWKS),
  object storage (S3-compatible) for statement uploads.
- **Frontend thin client.** Because all logic lives behind the Go API, web and mobile
  share nothing but the API contract. This decouples the web-framework choice from
  mobile; mobile is a deferrable, independent decision.

## 3. Auth
Auth stays with Supabase even in a Go-everything world. Go only verifies tokens. Auth
is the one area where "control" has poor risk/reward: undifferentiated, catastrophic
when wrong, and AI-generated auth compiles-and-works in the happy path while hiding
adversarial holes (missing `alg` check, unrotated refresh tokens, non-expiring reset
links). If Supabase-coupling ever becomes unacceptable, self-host **Ory Kratos**
before hand-rolling.

## 4. Data model (derived from 7 years of the actual spreadsheet)
The source workbook already implemented most requirements as formulas. Key findings:
- Ledger columns: Date / Item(merchant) / $ / Category / Paid(payer) / Split / Full PB
  / Cost. Cost = `if(Split, C/2, if(FullPB, C, C))`.
- Payer was a dropdown (`null/Hayley/Michael`) — confirms members as a small
  configurable set, distinct from auth users.
- Category was **free text** → typos silently broke SUMIFS. In the app it becomes a
  FK to a configurable `categories` table. This is a real integrity upgrade.
- Two category dimensions: spending categories (Groceries, Gas, …) and higher-level
  groups (flexible / fixed / investments / savings).
- Budget goals were computed as **% of income** (50/30/20 framing) — hence
  `monthly_budgets` supports both percent and fixed-dollar per month.
- Per-person income incl. rental (properties Saulsbury / 16th Ave) → `properties` +
  `incomes`, with a `tax_meta` JSONB seam for future tax brackets.
- `Paid / Covered For / Owed` rows = month-end settlement → `settlements`.
- Money stored as floats → convert to integer cents on import.

## 5. Split attribution
Rule is stored on the expense; resolved amounts live in `expense_splits`.
- `full` → 100% to one member (`full_target_member_id`; set to the non-payer for the
  "I paid for my spouse" case).
- `equal` → equal across all active members (the 50/50 generalization).
- `income_weighted` → by each participant's income share **for that month**; derived
  and month-dependent, so live while open, **frozen on settlement**. This gives live
  accuracy now and immutable history later (settlements must not silently re-ripple).
- `custom` → explicit per-member percentages.
Payer is independent of participants (payer can front a cost they're not part of).

Deliberately **not** built: per-expense participant subsets (splits resolve across all
active members; `custom` covers uneven cases) and debt netting (settlements stay
pairwise). Both are regret-free to add later — purely additive.

## 6. Budgets
Per category per month. `goal_type = percent_of_income` (resolved against that
month's income) or `fixed_amount` (hardcoded cents override). Open question: does the
percent base use combined household income or per-member.

## 7. Hosting & cost
- Dev: Supabase free tier is fine for a solo, unmarketed public URL (durability holds
  through crashes/pauses; only backups are missing, covered by migrations + source
  CSVs + occasional `pg_dump`). Free tier pauses after 7 days idle and needs a manual
  dashboard restore (~60s) — not auto-wake.
- Public: Supabase Pro (~$25/mo: always-on, daily backups, 100K MAU auth included) +
  frontend host (~$0–20/mo). ~$25–45/mo realistic. Free→Pro is a toggle on the same
  project — no migration.

## 8. Migration from the workbook
12 monthly sheets (Jan–Dec) are the real data; the rest are backups/scratch. Importer
maps ledger rows → expenses, resolving Split/Full PB into `split_rule`, converting
floats → cents, and mapping free-text categories → the `categories` FK (with a
merchant→category seed for auto-fill).
