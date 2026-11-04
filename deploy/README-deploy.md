# Deploying Quizly (Portainer + Nginx Proxy Manager)

The stack is two containers: `quizly` (API + admin dashboard, image from GHCR) and `db` (PostgreSQL 18). Nginx Proxy Manager (NPM) terminates HTTPS for `quizly.jbohacek.cz` and forwards to the `quizly` port. Migrations run automatically on startup.

Do the steps in order. Steps 1–7 are one-time (step 8, the MCP server for Claude, is optional); the runbook below covers updates, rollback, restore and secrets.

## 1. DNS

Create an `A` record (and `AAAA` if the server has IPv6) for `quizly.jbohacek.cz` pointing to the server's public IP. Check it resolves before step 4:

```bash
nslookup quizly.jbohacek.cz
```

## 2. GitHub token for the private image

The image `ghcr.io/jbohacek/quizly` is pushed by the `api` workflow on every merge to `main` and is private.

1. GitHub → **Settings → Developer settings → Personal access tokens → Tokens (classic) → Generate new token**.
2. Name `portainer-ghcr`, expiration as you like, scope **`read:packages` only**.
3. Copy the token.

## 3. Registry in Portainer

Portainer → **Registries → Add registry → Custom registry**:

| Field | Value |
| --- | --- |
| Name | `ghcr` |
| Registry URL | `ghcr.io` |
| Authentication | on |
| Username | `Jbohacek` |
| Password | the token from step 2 |

## 4. Stack in Portainer

Portainer → **Stacks → Add stack**:

1. Name: `quizly`.
2. Build method **Web editor**: paste [`docker-compose.yml`](./docker-compose.yml).
3. **Environment variables**: add every variable from [`.env.example`](./.env.example) with real values:
   - `POSTGRES_PASSWORD`: a long random string (`openssl rand -base64 32`). Use the same value inside `ConnectionStrings__Default`.
   - `Jwt__SigningKey`: at least 32 random bytes (`openssl rand -base64 48`). Changing it later doesn't sign phones out (see Runbook → Rotate secrets).
   - `ADMIN_USERNAME` / `ADMIN_PASSWORD`: your dashboard login.
   - `QUIZLY_TAG`: `latest`, or a commit SHA from GHCR to pin a version.
   - `QUIZLY_PORT`: the host port NPM forwards to (default `8080`; pick a free one).
4. **Deploy the stack.** Portainer pulls the image with the `ghcr` registry credentials.
5. Check the `quizly` container log for `Now listening on: http://[::]:8080` and no errors. `http://<server>:<QUIZLY_PORT>/api/health` returns `{"status":"ok"}`.

The database lives in the `quizly_pgdata` volume, the Data Protection keys (admin cookies survive restarts) in `quizly_keys`, the newest app APK in `quizly_apk`.

## 5. Proxy host in Nginx Proxy Manager

NPM → **Hosts → Proxy Hosts → Add Proxy Host**:

| Tab | Field | Value |
| --- | --- | --- |
| Details | Domain Names | `quizly.jbohacek.cz` |
| Details | Scheme | `http` |
| Details | Forward Hostname / IP | the server's LAN IP (or the `quizly` container name if NPM shares a Docker network with the stack) |
| Details | Forward Port | `QUIZLY_PORT` (e.g. `8080`) |
| Details | **Websockets Support** | **on** (the Blazor dashboard needs it) |
| Details | Block Common Exploits | on |
| SSL | SSL Certificate | Request a new SSL Certificate (Let's Encrypt) |
| SSL | Force SSL, HTTP/2 Support, HSTS Enabled | on |

The app trusts `X-Forwarded-For` / `X-Forwarded-Proto` from the proxy, so it sees HTTPS and the real client IP (used by login rate limits). Keep `QUIZLY_PORT` reachable only from NPM: don't open it in the router/firewall.

## 6. First login

1. Open `https://quizly.jbohacek.cz/admin` → you are sent to the login page.
2. Log in with `ADMIN_USERNAME` / `ADMIN_PASSWORD`.
3. **Balíčky → Nový balíček** (or **Importovat YAML**), add cards.
4. **Uživatelé → Nový uživatel**: the generated password is shown once; send it to the user.
5. API docs: `https://quizly.jbohacek.cz/api/docs` (needs the admin login in production).

The 52 notification texts are seeded on the first start. Production starts without demo data.

## 7. Backups

[`backup.sh`](./backup.sh) runs on the server from cron: one compressed `pg_dump` per night, the newest 14 kept. [`restore.sh`](./restore.sh) puts a dump back. Both run `pg_dump`/`pg_restore` inside the `db` container, so they need no database password, only access to `docker`.

1. Copy both scripts to the server, e.g. to `/opt/quizly/`, and make them executable:

   ```bash
   sudo mkdir -p /opt/quizly/backups
   sudo cp backup.sh restore.sh /opt/quizly/ && sudo chmod +x /opt/quizly/*.sh
   ```

2. Check the database container's name (Portainer → Containers). It is `quizly-db-1` for a stack named `quizly`. If it differs, put `QUIZLY_DB_CONTAINER=<name>` in front of the commands below.
3. Run a backup by hand once:

   ```bash
   sudo /opt/quizly/backup.sh
   ```

   It prints `backup ok: /opt/quizly/backups/quizly-2026-11-02-0330.dump (…)`.
4. Add it to root's crontab (`sudo crontab -e`), every night at 03:30:

   ```
   30 3 * * * /opt/quizly/backup.sh >> /opt/quizly/backups/backup.log 2>&1
   ```

5. Copy `/opt/quizly/backups` somewhere off the server now and then (NAS, cloud drive). A backup on the same disk doesn't survive that disk.
6. Do the **restore drill** below once, so you know the dumps work.

Settings: `QUIZLY_BACKUP_DIR` (default `/opt/quizly/backups`), `QUIZLY_BACKUP_KEEP` (default `14` dumps).

## 8. MCP server for Claude (optional)

Lets Claude (claude.ai and Claude Code) list decks, read one as YAML, preview a change and save it. It never deletes cards. Details: [`docs/mcp.md`](../docs/mcp.md).

1. Generate the secret (≥ 48 URL-safe characters) and keep it like a password:

   ```bash
   openssl rand -base64 48 | tr '+/' '-_' | tr -d '='
   ```

2. Portainer → stack `quizly` → **Environment variables**: `Mcp__Enabled` = `true`, `Mcp__Secret` = the value from step 1 → **Update the stack**. If the container stops with `Mcp__Secret must be at least 48 URL-safe characters`, the secret is missing or too short.
3. NPM needs no change: the existing proxy host forwards `/mcp/…` like everything else, over HTTPS. The app sends `X-Accel-Buffering: no`, so Nginx doesn't buffer the streamed responses. Check it from your PC (`<secret>` = the value from step 1). The answer is a `200` with `content-type: text/event-stream` and a `data: {"result":…}` line that comes at once:

   ```bash
   curl -sS -i -N https://quizly.jbohacek.cz/mcp/<secret> -H 'Content-Type: application/json' -H 'Accept: application/json, text/event-stream' -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"curl","version":"1"}}}'
   ```

   A wrong secret gives `404`.
4. **claude.ai:** Settings → Connectors → **Add custom connector**: name `Quizly`, URL `https://quizly.jbohacek.cz/mcp/<secret>`, no authentication. Then ask e.g. *"Jaké balíčky mám v Quizly?"*
5. **Claude Code:**

   ```bash
   claude mcp add --transport http quizly https://quizly.jbohacek.cz/mcp/<secret>
   ```

The full URL ends up in NPM's access log on the server, so treat that log like the `.env`. To turn MCP off, set `Mcp__Enabled` = `false` and update the stack.

## 9. App updates

The server fetches each new full release's APK from GitHub and the app offers it on Domů. Setup, releasing and troubleshooting: [`docs/app-updates.md`](../docs/app-updates.md).

1. Create a fine-grained GitHub token: only `Jbohacek/Quizly`, **Contents: Read-only**, with an expiry (note the date).
2. Portainer → stack `quizly`: paste the new [`docker-compose.yml`](./docker-compose.yml) (it adds the `apk` volume), set `Updates__Repository` = `Jbohacek/Quizly` and `Updates__GitHubToken` = the token → **Update the stack**.
3. The `quizly` log shows `App update 1.0.0 (<run>) is ready` once a full release exists (before that: `No full release found`).

## Runbook

### Update

Every merge to `main` pushes `ghcr.io/jbohacek/quizly:latest` and `:<commit sha>`.

1. Take a backup first: `sudo /opt/quizly/backup.sh`.
2. With `QUIZLY_TAG=latest`: Portainer → stack `quizly` → **Pull and redeploy** (enable "Re-pull image"). Pinned: set `QUIZLY_TAG` to the new SHA → **Update the stack**.
3. Check the `quizly` log and `https://quizly.jbohacek.cz/api/health`.

Migrations run on startup; a failed migration stops the container (check its log) and leaves the database as it was.

The app updates separately: tag `v1.0.1` and phones offer the new version on Domů within ~15 minutes (§9). Builds older than `v1.0.0` (betas) are installed by hand from the GitHub Release. The login stays.

### Rollback

1. Set `QUIZLY_TAG` to the previous SHA (GHCR → package `quizly` → versions) → **Update the stack**.
2. If the newer version ran a migration, the old one may not start on the newer database. Then also **restore** the backup taken before the update (below).

### Restore

1. Portainer → stack `quizly` → stop the **`quizly`** container (keep `db` running), so nobody writes during the restore.
2. Pick a dump: `ls -lt /opt/quizly/backups`.
3. Restore it. It asks for `yes` and replaces the whole database in one transaction; if anything fails, the database stays as it was:

   ```bash
   sudo /opt/quizly/restore.sh /opt/quizly/backups/quizly-2026-11-02-0330.dump
   ```

4. Start the `quizly` container again and check `/api/health` and the dashboard.

Phones keep their login. Answers they made after the backup are gone from the server; points and streaks are as they were at the backup.

**Restore drill** (once after setting up backups, then e.g. yearly): take a backup by hand, restore that same file as above, and check that Přehled shows the same users and points. Restoring the dump you just made changes nothing.

### Rotate secrets

Change the value in the stack's environment variables in Portainer, then **Update the stack**.

| Secret | Notes |
| --- | --- |
| `ADMIN_PASSWORD` | Takes effect after the update. An admin session that is already open stays valid until its cookie expires. |
| `POSTGRES_PASSWORD` | The `db` container sets the password only when the volume is created, so change it in the database first: `docker exec -it quizly-db-1 psql -U quizly -d quizly -c "ALTER USER quizly PASSWORD '<new>'"`. Then put `<new>` in **both** `POSTGRES_PASSWORD` and `ConnectionStrings__Default` and update the stack. |
| `Jwt__SigningKey` | Access tokens signed with the old key stop working; phones get a new one with their refresh token automatically, so nobody is signed out. |
| Sign every phone out | Delete the refresh tokens: `docker exec quizly-db-1 psql -U quizly -d quizly -c "DELETE FROM refresh_tokens"`. Each user logs in again with their password. For one user, use **Reset hesla** on the dashboard instead. |
| `Mcp__Secret` | Generate a new one (§8), put it in the stack and **Update the stack**. The old URL answers `404` at once; change the URL in the claude.ai connector and in Claude Code (`claude mcp remove quizly`, then add it again). |
| GHCR token (Portainer registry) | Create a new `read:packages` token, put it in Portainer → Registries → `ghcr`, delete the old one on GitHub. |
| `Updates__GitHubToken` | Before it expires: create a new token (§9), put it in the stack and **Update the stack**, then revoke the old one on GitHub. Until then phones simply aren't offered new versions. |
| Android signing key | **Never rotate.** A new key can't install over the old app; every phone would have to uninstall (and log in again). Keep a copy of the keystore and its passwords outside GitHub. |

## Troubleshooting

| Symptom | Cause |
| --- | --- |
| Container exits with `ADMIN_USERNAME and ADMIN_PASSWORD must be set` | variable missing in the stack |
| `Jwt__SigningKey must be at least 32 bytes` | key too short |
| Dashboard loads but buttons do nothing, "Něco se pokazilo" | NPM **Websockets Support** is off |
| Logged out of the dashboard after every redeploy | the `keys` volume is missing or not writable |
| Image pull fails | registry `ghcr` missing or token without `read:packages` |
| `/api/health` → 503 | database not reachable: check `ConnectionStrings__Default` and the `db` container |
| Container exits with `Mcp__Secret must be at least 48 URL-safe characters` | `Mcp__Enabled=true` but the secret is missing, short, or has characters like `+` `/` `=` (§8) |
| Claude says the Quizly connector can't connect | `Mcp__Enabled` is off, or the URL's secret differs from `Mcp__Secret` (both give `404`), or too many requests (`429`, 60 per minute) |
| Log: `App update check failed` … `401` | `Updates__GitHubToken` expired or was revoked (Runbook → Rotate secrets) |
| Phones don't offer a new version | only a pre-release was tagged, the APK isn't attached yet, or updates are off (`docs/app-updates.md` §5) |
| First start logs one failed `SELECT … FROM "__EFMigrationsHistory"` | normal: EF checks the history table before the first migration creates it |
