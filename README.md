# Quizly

A private Android flashcard app in Czech. Spaced repetition (FSRS) on the server, points with a streak multiplier, a daily goal, a shop of real-life rewards, and warm, friendly notifications. One admin manages decks, users, the shop and notification texts in a web dashboard.

- **App:** Flutter, Android 8.0+ (sideloaded APK)
- **API + admin dashboard:** ASP.NET Core (.NET 10) with Blazor Server at `/admin`, REST at `/api`
- **Database:** PostgreSQL via EF Core
- **Hosting:** Docker Compose in Portainer, behind Nginx Proxy Manager, at `https://quizly.jbohacek.cz`
- **CI/CD:** GitHub Actions (tests, Docker image to GHCR, signed release APK)

## Status

The project is built in stages. Progress lives in [`STAGES.md`](./STAGES.md).
The full brief (features, business rules, data model, API, design tokens) is in [`CLAUDE.md`](./CLAUDE.md).
Detailed specs live in [`docs/`](./docs): [spec](./docs/spec.md) · [API](./docs/api.md) · [YAML format](./docs/yaml-format.md) · [notifications](./docs/notifications.md) · [notification texts](./docs/notification-texts.md) · [architecture](./docs/architecture.md) · [design](./docs/design/).

## Repository layout

```
src/        ASP.NET Core solution (Domain, Application, Infrastructure, Web)
tests/      xUnit tests
app/        Flutter app
deploy/     docker-compose.yml, .env.example, backup script, deploy guide
docs/       spec, API, YAML format, notifications, architecture, design, FSRS vectors
.github/    CI workflows
```

Details in [`docs/architecture.md`](./docs/architecture.md). Local development instructions arrive with the code (Etapa 2 for the API, Etapa 5 for the app).

## Secrets

Never commit `.env` files, keystores, tokens or passwords. Configuration goes through `deploy/.env.example` and GitHub Secrets.

## License

[MIT](./LICENSE)
