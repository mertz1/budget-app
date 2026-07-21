# POSTMAN.md — API Testing

## Where the collection lives

`apps/api/postman/budget-app.postman_collection.json` — commit this. It holds
the request definitions: URLs, headers, body shapes, and the Tests script that
saves `access_token`.

**Never export or commit a Postman Environment file.** That's where live
token values live — same reasoning as `.env` being gitignored (see
`docs/ENVIRONMENT.md`). Keep your Environment (e.g. "Local") local-only.

## Getting a bearer token

Protected routes (e.g. `GET /whoami`) need a real Supabase-issued JWT.

1. **First time**: `POST {API_URL}/auth/v1/signup`
   - Headers: `apikey: <ANON_KEY>`, `Content-Type: application/json`
   - Body: `{"email": "...", "password": "..."}`
2. **Already signed up**: use `POST {API_URL}/auth/v1/token?grant_type=password`
   instead (same headers/body shape). Signup on an existing email errors or
   no-ops — sign-in is the repeatable way to get a fresh token.
3. Either response includes `access_token` in the JSON body.

Local `API_URL` is `http://127.0.0.1:54321` (confirm via `supabase status`).
See `docs/ENVIRONMENT.md` for what `ANON_KEY` is and why it's safe to paste
into Postman for local dev.

## Auto-saving the token (Tests script)

On the signup/sign-in request, in Postman's **Tests** tab (or **Post-response
Scripts** in newer Postman versions):

```javascript
const response = pm.response.json();

if (response.access_token) {
    pm.environment.set("access_token", response.access_token);
} else {
    console.warn("No access_token in response:", response);
}
```

Requires an **Environment** to be selected in Postman's top-right dropdown —
`pm.environment.set` silently no-ops otherwise.

Then on protected requests, set Authorization type to **Bearer Token** with
value `{{access_token}}` (or header `Authorization: Bearer {{access_token}}`).

## Cleaning up test users

Local Supabase auth data is disposable, same as the rest of the local DB:

- Duplicate/extra signup attempts on the same email are harmless — just sign
  in instead of signing up again.
- To delete a specific test user: open Studio (`supabase status` for the URL,
  default `localhost:54323`) → Authentication → Users.
- To wipe everything (all local data, not just auth): `supabase db reset`.
