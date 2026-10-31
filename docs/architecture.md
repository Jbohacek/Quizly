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
│  │  ├─ Scheduling/                FSRS-6 scheduler (Fsrs.cs, FsrsParameters.cs, CardMemory.cs)
│  │  ├─ Gamification/              PointsCalculator, Multiplier, StreakRules, Milestones
│  │  └─ PragueCalendar.cs          Europe/Prague days (time comes from the injected TimeProvider)
│  ├─ Quizly.Application/           use-case services shared by REST and Blazor
│  │  ├─ Abstractions/              IAppDbContext (DbSets), IPasswordGenerator
│  │  ├─ Auth/ · Session/ · Reviews/ · Stats/ · Shop/ · Decks/ · Yaml/ · Users/ · NotificationTexts/ · Overview/
│  │  └─ Common/                    Result/error types, validation
│  ├─ Quizly.Infrastructure/        QuizlyDbContext, entity configurations, migrations, seeding
│  │  ├─ Persistence/ · Migrations/ · Seed/ (notification-texts.json, demo deck for Development)
│  └─ Quizly.Web/                   ASP.NET Core host
│     ├─ Api/                       minimal API endpoint groups per feature, ProblemDetails mapping
│     ├─ Auth/                      JWT (app), cookie (admin), rate-limit policies
│     ├─ Components/                Blazor: App.razor, Layout/, Pages/Admin/*, Shared/
│     ├─ wwwroot/                   admin CSS (tokens from CLAUDE.md §9.2), bundled fonts
│     └─ Program.cs
├─ tests/
│  └─ Quizly.Tests/                 xUnit
│     ├─ Domain/                    FSRS vectors, points, streak, Prague days (pure, fast)
│     ├─ Application/               services against a real PostgreSQL (Testcontainers)
│     ├─ Api/                       WebApplicationFactory end-to-end
│     └─ TestData/                  fsrs6-reference-vectors.json (copied from docs/fsrs)
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
| `YamlDotNet` | Application | deck YAML (representation model for line numbers) |
| `xunit.v3` | Tests | test framework, runs on Microsoft.Testing.Platform (`global.json` → `test.runner`) |
| `Microsoft.AspNetCore.Mvc.Testing` | Tests | in-memory API host |
| `Testcontainers.PostgreSql` | Tests | real PostgreSQL in tests (needs Docker; available on GitHub runners) |
| `Microsoft.Extensions.TimeProvider.Testing` | Tests | `FakeTimeProvider` |

Built into the framework, no package needed: rate limiting, ProblemDetails, Data Protection, forwarded headers, `PasswordHasher<T>`, `TimeProvider`, Blazor.
Swagger UI is a small page at `/api/docs` that loads `swagger-ui-dist` from jsDelivr and reads the built-in OpenAPI document (no Swashbuckle, which has known issues on .NET 9+).
No UI component library for the admin: plain Razor components and CSS with the §9.2 tokens.
Assertions: plain xUnit `Assert` (no FluentAssertions; its v8 license is commercial).

## 3. Flutter packages

| Package | Why |
| --- | --- |
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
- Fonts bundled in `app/assets/fonts/`: Bricolage Grotesque and Manrope (JetBrains Mono is only used by the admin YAML editor, bundled in `wwwroot`).
- `minSdk 26`, `targetSdk` = latest stable at Etapa 5.

### 3.1 App structure

```
app/lib/
├─ main.dart
├─ core/        api/ (dio client, interceptors, DTOs) · theme/ (tokens §9.1) · strings.dart · format.dart · storage/
└─ features/
   ├─ auth/ · home/ · session/ (queue, outbox, swipe card) · stats/ · shop/ · settings/
   └─ notifications/   planner.dart (pure Dart, docs/notifications.md) · scheduler.dart (plugin glue) · background.dart
```
