# Architecture: repo layout and packages

Final layout for v1. Versions are pinned to the latest stable release when each project is created (Etapa 2 for .NET, Etapa 5 for Flutter) and locked by `packages.lock.json` / `pubspec.lock`.

## 1. Repository

```
/
├─ CLAUDE.md · STAGES.md · README.md · LICENSE
├─ .editorconfig · .gitattributes · .gitignore
├─ Quizly.slnx                      solution (new XML format, .NET 10)
├─ Directory.Build.props            net10.0, Nullable, TreatWarningsAsErrors, ImplicitUsings
├─ Directory.Packages.props         central package versions
├─ Dockerfile                       multi-stage: sdk:10.0 → aspnet:10.0, non-root, port 8080
├─ src/
│  ├─ Quizly.Domain/                entities, enums, pure logic, no dependencies
│  │  ├─ Scheduling/                FSRS-6 scheduler (Fsrs.cs: FsrsScheduler, FsrsCard, FsrsRating)
│  │  ├─ Gamification/              Points (multiplier), Milestones, Streaks, SmartTimes
│  │  └─ PragueCalendar.cs          Europe/Prague days (time comes from the injected TimeProvider)
│  ├─ Quizly.Application/           use-case services shared by REST and Blazor
│  │  ├─ Abstractions/              IAppDbContext (DbSets), IPasswordGenerator
│  │  ├─ Auth/ · Learning/ (session, reviews, progress) · Profile/ (/me, settings) · Stats/ · Shop/ · Decks/ · Users/ · NotificationTexts/ (Yaml/ and Overview/ in Etapa 4)
│  │  └─ Common/                    Result/error types, validation
│  ├─ Quizly.Infrastructure/        QuizlyDbContext, entity configurations, migrations, seeding
│  │  ├─ Persistence/ · Migrations/ · Seed/ (notification-texts.json, demo deck for Development)
│  └─ Quizly.Web/                   ASP.NET Core host
│     ├─ Api/                       minimal API endpoint groups per feature, ProblemDetails mapping
│     ├─ Auth/                      JWT (app), cookie (admin), rate-limit policies
│     ├─ Mcp/                       MCP server for Claude: secret path, deck tools (docs/mcp.md)
│     ├─ Components/                Blazor: App/Routes, Layout/ (AdminLayout), Pages/ (Login, Overview, Decks, DeckDetail, Shop, Users, NotificationTexts), Shared/, AdminPage (one DI scope per operation)
│     ├─ wwwroot/                   admin CSS (tokens from CLAUDE.md §9.2), bundled fonts
│     └─ Program.cs
├─ tests/
│  └─ Quizly.Tests/                 xUnit
│     ├─ Domain/                    FSRS vectors, points, streak, Prague days (pure, fast)
│     ├─ Application/               services against a real PostgreSQL (Testcontainers)
│     ├─ Api/                       WebApplicationFactory end-to-end
│     └─ TestData/                  fsrs6-reference-vectors.json (linked from docs/fsrs, one source of truth)
├─ app/                             Flutter project (Android only)
├─ deploy/                          docker-compose.yml, .env.example, backup.sh, README-deploy.md
├─ docs/                            spec, API, YAML, notifications, design/, fsrs/
└─ .github/workflows/               api.yml, app.yml
```

Dependencies point inward: `Web → Application → Domain`, `Infrastructure → Application, Domain`. `Web` references `Infrastructure` only to register it in DI.

## 2. .NET packages

| Package | Project | Why |
| --- | --- | --- |
| `Npgsql.EntityFrameworkCore.PostgreSQL` | Infrastructure | EF Core 10 provider |
| `EFCore.NamingConventions` | Infrastructure | snake_case tables/columns |
| `Microsoft.EntityFrameworkCore`, `Microsoft.EntityFrameworkCore.Relational` | Application | `IAppDbContext` with `DbSet`s; `FromSql` for row locks |
| `Microsoft.EntityFrameworkCore.Design` | Infrastructure (private) | migrations tooling (`dotnet ef`, local tool in `dotnet-tools.json`) |
| `Microsoft.AspNetCore.Authentication.JwtBearer` | Web | app auth |
| `Microsoft.AspNetCore.OpenApi` | Web | built-in OpenAPI document |
| `Microsoft.Extensions.Diagnostics.HealthChecks.EntityFrameworkCore` | Web | `/api/health` DB check |
| `ModelContextProtocol.AspNetCore` | Web | MCP server (Streamable HTTP) for Claude's deck tools (docs/mcp.md) |
| `YamlDotNet` | Application | deck YAML (representation model for line numbers) |
| `xunit.v3` | Tests | test framework, runs on Microsoft.Testing.Platform (`global.json` → `test.runner`) |
| `Microsoft.AspNetCore.Mvc.Testing` | Tests | in-memory API host |
| `Testcontainers.PostgreSql` | Tests | real PostgreSQL in tests (needs Docker; available on GitHub runners) |
| `Microsoft.Extensions.TimeProvider.Testing` | Tests | `FakeTimeProvider` |
| `ModelContextProtocol` | Tests | MCP client for the MCP server tests |

Built into the framework, no package needed: rate limiting, ProblemDetails, Data Protection, forwarded headers, `PasswordHasher<T>`, `TimeProvider`, Blazor.
Swagger UI is a small page at `/api/docs` that loads `swagger-ui-dist` from jsDelivr and reads the built-in OpenAPI document (no Swashbuckle, which has known issues on .NET 9+).
No UI component library for the admin: plain Razor components and CSS with the §9.2 tokens.
Assertions: plain xUnit `Assert` (no FluentAssertions; its v8 license is commercial).

## 3. Flutter packages

| Package | Why |
| --- | --- |
| `flutter_localizations` (SDK) | Material's built-in Czech texts only (no i18n framework) |
| `flutter_riverpod` | state |
| `go_router` | routing (login redirect, bottom nav shell) |
| `dio` | HTTP + auth interceptor that refreshes on 401 |
| `flutter_secure_storage` | access and refresh tokens |
| `shared_preferences` | review outbox, cached texts, text history, last summary |
| `uuid` | review and claim ids (v4) |
| `connectivity_plus` | "Jsi offline" detection (with request failures, api.md §11) |
| `flutter_local_notifications` | local notifications |
| `timezone` | `Europe/Prague` scheduling (`TZDateTime`) |
| `workmanager` | daily background refresh |
| `fl_chart` | sparkline, bars, heatmap helpers |
| `flutter_animate` | flip, stamps, floating points, counters |
| `confetti` | goal and milestone celebrations |
| `package_info_plus` | app version in Nastavení |
| dev: `flutter_lints`, `mocktail` | lints, test doubles |

- Icons: Flutter's built-in Material `Icons.*_rounded` (no extra package).
- Czech number/date formatting is a small hand-written helper in `lib/core/format.dart` (`1 457`, `1,1×`, `83 %`, `31. 10.`), unit-tested. No `intl`, no i18n framework; all strings in `lib/core/strings.dart`.
- Fonts bundled in `app/assets/fonts/`: Bricolage Grotesque (600/700/800) and Manrope (400/600/700/800) as static TTF weights (see `app/assets/fonts/README.md`). JetBrains Mono is only used by the admin YAML editor, bundled in `wwwroot`.
- Packages are added in the stage that first uses them: Etapa 5 has riverpod, go_router, dio, secure storage, shared_preferences, uuid, connectivity_plus, package_info_plus; `fl_chart`, `flutter_animate`, `confetti` come in Etapa 6, notifications/`timezone`/`workmanager` in Etapa 7.
- `minSdk 26`, `targetSdk` = latest stable at Etapa 5.

### 3.1 App structure

```
app/lib/
├─ main.dart · router.dart (go_router, login redirect, bottom-nav shell)
├─ core/        api/ (dio client with token refresh, DTOs, ApiException) · storage/ (secure token store)
│               theme/ (tokens §9.1) · widgets/ · strings.dart · format.dart · providers.dart · config.dart
└─ features/
   ├─ auth/ · home/ (Domů, Balíček, week strip) · session/ (queue + tally, review outbox sync, controller, swipe card, Hotovo)
   ├─ shell/ (bottom navigation) · stats/ (screen + pure helpers) · shop/ (screen, wishlist target) · settings/
   └─ notifications/   planner.dart (pure Dart, docs/notifications.md) · notifications.dart (cache + re-plan) · notification_platform.dart (plugin glue) · notification_store.dart · background.dart · ask_card.dart
```
