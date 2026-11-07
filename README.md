# Quizly

A private Android flashcard app in Czech. Spaced repetition (FSRS) on the server, points with a streak multiplier, a daily goal, a shop of real-life rewards, and warm, friendly notifications. One admin manages decks, users, the shop and notification texts in a web dashboard.

- **App:** Flutter, Android 8.0+ (sideloaded APK)
- **API + admin dashboard:** ASP.NET Core (.NET 10) with Blazor Server at `/admin`, REST at `/api`
- **Database:** PostgreSQL via EF Core
- **Hosting:** Docker Compose in Portainer, behind Nginx Proxy Manager, at `https://quizly.jbohacek.cz`
- **CI/CD:** GitHub Actions (tests, Docker image to GHCR, signed release APK)

## Status

The project is built in stages. Progress lives in [`STAGES.md`](./STAGES.md). Now: Etapa 8, polish and a first beta tester ([`docs/beta.md`](./docs/beta.md)), then `v1.0.0`.
The full brief (features, business rules, data model, API, design tokens) is in [`CLAUDE.md`](./CLAUDE.md).
Detailed specs live in [`docs/`](./docs): [spec](./docs/spec.md) · [API](./docs/api.md) · [YAML format](./docs/yaml-format.md) · [notifications](./docs/notifications.md) · [notification texts](./docs/notification-texts.md) · [architecture](./docs/architecture.md) · [MCP server](./docs/mcp.md) · [design](./docs/design/).

## Repository layout

```
src/        ASP.NET Core solution (Domain, Application, Infrastructure, Web)
tests/      xUnit tests
app/        Flutter app
deploy/     docker-compose.yml, .env.example, backup.sh / restore.sh, deploy guide + runbook
docs/       spec, API, YAML format, notifications, architecture, design, FSRS vectors
.github/    CI workflows
```

Details in [`docs/architecture.md`](./docs/architecture.md).

## Local development (API)

Needs the .NET 10 SDK and Docker.

```bash
docker compose -f deploy/docker-compose.dev.yml up -d
```

```bash
dotnet run --project src/Quizly.Web
```

- Admin dashboard: http://localhost:5278/admin (dev credentials in `src/Quizly.Web/appsettings.Development.json`).
- Swagger UI: http://localhost:5278/api/docs (admin login via `POST /api/admin/auth/login`).
- Deploying to the server, backups and the runbook (update, rollback, restore, rotate secrets): [`deploy/README-deploy.md`](./deploy/README-deploy.md).
- Migrations run on startup. Every request is in `src/Quizly.Web/Quizly.Web.http`.
- **Sample data (#44):** the first Development start on an empty database also creates sample users, decks, a shop and about six weeks of study history, so there is something to look at right away. Set `Seed__DevelopmentData=false` to skip it. To start over, run `pwsh deploy/dev-reset.ps1` (it deletes the dev database volume), then `dotnet run` again.

  Every sample user has the password `123`:

  | User | Story |
  | --- | --- |
  | `anna` | 16-day streak (1,2×), today 12 of 20, a confirmed, a pending and a sold-out purchase, hearted rewards, sees the restricted deck "Anatomie" |
  | `petr` | streak of 10 that broke 4 days ago, "Těžké a Snadné" on, a rejected purchase |
  | `eva` | 3-day streak with today's goal met, shop off, hidden from Žebříček |
  | `novacek` | brand new: nothing studied, for the first-run screens |
  | `stary` | deactivated, cannot log in |

  There are four decks (C# základy, Angličtina: slovíčka, Násobilka, the restricted Anatomie) and an archived one, with tags and light formatting. The history is replayed through the real FSRS, points and streak rules, so balances, streaks, heatmaps and the Žebříček all add up.
- New migration: `dotnet tool restore`, then `dotnet ef migrations add <Name> --project src/Quizly.Infrastructure --output-dir Persistence/Migrations`.

Tests (start PostgreSQL 18 with Testcontainers, so Docker must be running):

```bash
dotnet test --solution Quizly.slnx
```

Whole stack in containers, built from this checkout (copy `deploy/.env.example` to `deploy/.env` first):

```bash
docker compose -f deploy/docker-compose.yml -f deploy/docker-compose.build.yml up --build
```

## Local development (app)

Needs Flutter (stable) and the Android SDK. Details, the signing key and installing the APK: [`app/README.md`](./app/README.md).

```bash
cd app
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:5278
```

`10.0.2.2` is the PC from inside the Android emulator. Without `--dart-define` the app talks to `https://quizly.jbohacek.cz`.

## Secrets

Never commit `.env` files, keystores, tokens or passwords. Configuration goes through `deploy/.env.example` and GitHub Secrets.

## License

[MIT](./LICENSE)
