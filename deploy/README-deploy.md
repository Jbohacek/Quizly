# Deploying Quizly (Portainer + Nginx Proxy Manager)

The stack is two containers: `quizly` (API + admin dashboard, image from GHCR) and `db` (PostgreSQL 18). Nginx Proxy Manager (NPM) terminates HTTPS for `quizly.jbohacek.cz` and forwards to the `quizly` port. Migrations run automatically on startup.

Do the steps in order. Steps 1–4 are one-time.

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
   - `Jwt__SigningKey`: at least 32 random bytes (`openssl rand -base64 48`). Changing it later signs every phone out.
   - `ADMIN_USERNAME` / `ADMIN_PASSWORD`: your dashboard login.
   - `QUIZLY_TAG`: `latest`, or a commit SHA from GHCR to pin a version.
   - `QUIZLY_PORT`: the host port NPM forwards to (default `8080`; pick a free one).
4. **Deploy the stack.** Portainer pulls the image with the `ghcr` registry credentials.
5. Check the `quizly` container log for `Now listening on: http://[::]:8080` and no errors. `http://<server>:<QUIZLY_PORT>/api/health` returns `{"status":"ok"}`.

The database lives in the `quizly_pgdata` volume, the Data Protection keys (admin cookies survive restarts) in `quizly_keys`.

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

## Updating

Every merge to `main` pushes `ghcr.io/jbohacek/quizly:latest` and `:<commit sha>`.

- With `QUIZLY_TAG=latest`: Portainer → stack `quizly` → **Pull and redeploy** (enable "Re-pull image").
- Pinned: set `QUIZLY_TAG` to the new SHA → **Update the stack**.

Migrations run on startup; a failed migration stops the container (check its log) and leaves the database as it was.

**Rollback:** set `QUIZLY_TAG` to the previous SHA and update the stack. If the newer version ran a migration, restore the backup taken before the update (backups and restore steps arrive with `backup.sh` in Etapa 8; until then take a manual dump first):

```bash
docker exec quizly-db-1 pg_dump -U quizly -d quizly -Fc > quizly-$(date +%F).dump
```

## Troubleshooting

| Symptom | Cause |
| --- | --- |
| Container exits with `ADMIN_USERNAME and ADMIN_PASSWORD must be set` | variable missing in the stack |
| `Jwt__SigningKey must be at least 32 bytes` | key too short |
| Dashboard loads but buttons do nothing, "Něco se pokazilo" | NPM **Websockets Support** is off |
| Logged out of the dashboard after every redeploy | the `keys` volume is missing or not writable |
| Image pull fails | registry `ghcr` missing or token without `read:packages` |
| `/api/health` → 503 | database not reachable: check `ConnectionStrings__Default` and the `db` container |
| First start logs one failed `SELECT … FROM "__EFMigrationsHistory"` | normal: EF checks the history table before the first migration creates it |
