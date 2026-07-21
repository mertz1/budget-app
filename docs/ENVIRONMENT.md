# ENVIRONMENT.md — Local Dev Runbook

A plain-language map of your development environment and which commands are safe,
which need care, and which to avoid. Written for someone new to this stack.

## Mental model (read this first)

You have **two separate databases**:

- **Local** — the whole Supabase stack running on your laptop in Docker. This is
  **disposable**: you can wipe and rebuild it anytime. Do all your development
  and experimentation here. Nothing you do locally can hurt anything real.
- **Remote** — your Supabase cloud project (created later). This is the
  **precious** one. It's only touched by explicit deploy commands (`db push`),
  and every schema change reaches it through committed migration files.

Rule of thumb: **local = safe sandbox, remote = handle with care.** While you're
solo on the free tier, you're almost always working locally, so the stakes are
low.

## What's installed on your machine

| Tool | What it's for | Install (pick your OS) |
|------|---------------|------------------------|
| **Docker Desktop** | Runs the local Supabase stack. Must be running before `supabase start`. | Download Docker Desktop |
| **Supabase CLI** | Runs the local stack + manages migrations + deploys. | mac/Linux: `brew install supabase/tap/supabase` · Windows: `scoop bucket add supabase https://github.com/supabase/scoop-bucket.git` then `scoop install supabase` |
| **Go** | Your API language. | Official installer |
| **sqlc** | Generates type-safe Go from your SQL schema. | `go install github.com/sqlc-dev/sqlc/cmd/sqlc@latest` |

> ⚠️ **Do not** install the Supabase CLI with `npm install -g supabase` — global
> npm install is unsupported and will fail. Use Homebrew or Scoop above, or a
> project dev-dependency (`npm install -D supabase`, then prefix commands with
> `npx`, needs Node 20+).

Verify each is present:
```bash
docker --version
supabase --version
go version
sqlc version
```

## What "the local stack" actually is

When you run `supabase start`, Docker spins up several containers that together
are a full copy of Supabase on your machine:

- **Postgres** — your database (default `localhost:54322`).
- **Auth (GoTrue)** — signup/login; issues the JWTs your Go API verifies.
- **Storage** — file storage (for statement uploads later).
- **API gateway / PostgREST** — auto REST layer (default `localhost:54321`).
- **Studio** — a web dashboard to browse your DB (default `localhost:54323`).
- **Local mail inbox** — catches test auth emails so nothing is really sent.

The exact URLs and keys are **printed when you run `supabase start`**, and you
can reprint them anytime with `supabase status`. Trust that output over the
default ports above.

Local Postgres connection string is typically:
`postgresql://postgres:postgres@localhost:54322/postgres`
(point `pgx` / sqlc at this for local dev; confirm via `supabase status`).

### About the `ANON_KEY` (and other printed keys)

`ANON_KEY` is a JWT that identifies a request to GoTrue/PostgREST as coming
from an unauthenticated ("anonymous") client — required on every Auth API
call (e.g. signup/login), signed-in or not. It's project identification, not
a secret that proves who a *user* is.

- **Local dev only**: this exact key is a fixed, well-known default identical
  across every local Supabase install everywhere. Safe to paste into Postman,
  curl, etc. Forgot it? `supabase status` reprints it.
- **Remote/production is different**: a real project's `anon` key is
  project-specific (still safe to expose client-side, by design), but the
  `SERVICE_ROLE_KEY` must never be exposed to a browser or committed to git —
  it bypasses RLS entirely.

## First-time setup (run once, in this order)

```bash
supabase init                          # creates the supabase/ folder (commit it)
supabase start                         # downloads images (slow first time), boots stack
supabase migration new initial_schema  # makes an empty timestamped migration file
# paste the contents of schema.sql into that new file in supabase/migrations/
supabase db reset                      # applies migrations + seed.sql to local DB
sqlc generate                          # regenerate Go types from the schema
```

## Everyday commands — safe, run freely (all LOCAL)

| Command | What it does |
|---------|--------------|
| `supabase start` | Boot the local stack. |
| `supabase stop` | Shut it down. **Keeps** your local data. |
| `supabase status` | Show what's running + your local URLs/keys. |
| `supabase migration new <name>` | Create a new empty, timestamped migration file. |
| `supabase db reset` | Rebuild local DB from all migrations + seed. (Wipes local data — see below.) |
| `supabase db diff -f <name>` | Capture changes you made in Studio into a migration file. |
| `sqlc generate` | Regenerate Go after a schema change. |
| `docker ps` | See which containers are running. |

## Commands that need care — understand before running

- **`supabase db reset`** — safe, but it **erases all data in your LOCAL
  database** and rebuilds from migrations + `seed.sql`. That's by design (local
  is disposable), just don't expect hand-entered local rows to survive it. Put
  data you want back every time into `seed.sql`.
- **`supabase link`** — connects this repo to your **remote** cloud project.
  Needed before any push/pull. Do this once you actually have a cloud project.
- **`supabase db push`** — applies your local migrations to the **REMOTE**
  database. This is the one command here that changes something real. Only run it
  when you intend to deploy, and (later, for prod) prefer doing it via CI instead
  of your laptop.
- **`supabase stop --no-backup`** — the `--no-backup` flag **deletes your local
  data volumes**. Plain `supabase stop` is the safe version; add the flag only
  when you deliberately want a clean slate.

## Don't do these

- ❌ `npm install -g supabase` — unsupported; use brew/scoop/npx.
- ❌ **Edit a migration file that has already been applied.** Write a *new*
  migration to change things. Editing old ones desyncs the migration history.
- ❌ **Change the remote database directly** in the cloud Studio/SQL editor.
  It bypasses migrations and makes `db push` fail. All changes go through
  migration files.
- ❌ Delete, rename, or reorder files in `supabase/migrations/` after they've run.

## Running the Go API locally

```bash
cd apps/api
cp .env.example .env    # once — fill in local values (already correct by default)
go run ./cmd/api        # loads .env automatically (godotenv), listens on :8080
```

`.env` is required — the server calls `log.Fatal` on startup if `JWKS_URL`
isn't set. `.env` is gitignored; `.env.example` is the committed template.

For testing endpoints (getting a bearer token, Postman setup), see
`docs/POSTMAN.md`.

## "How do I know what's going on?"

- `supabase status` — is the stack up? what are my local URLs/keys?
- Open Studio (the URL from `status`, ~`localhost:54323`) to click through your
  tables and data visually.
- `docker ps` — confirm containers are actually running.
- `supabase --help` or `supabase <command> --help` — the CLI documents itself;
  when unsure what a command does, read its help before running it.

## If something feels broken

- Stack won't start → make sure **Docker Desktop is running** first.
- Weird state after upgrades → `supabase stop` then `supabase start` again.
- Want a guaranteed clean local DB → `supabase db reset` (rebuilds from
  migrations). Local data is disposable; this is your reset button.
