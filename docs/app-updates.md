# App updates

From `v1.0.0` on, the app tells its users when a new version is out and installs it from inside the app. Nobody has to send APK files around any more.

## 1. How it works

```
git tag v1.0.1  →  GitHub Actions (app.yml)  →  GitHub Release v1.0.1 + quizly-1.0.1-<run>.apk
                                                        │  (private repository)
                         Quizly server, every 15 min ───┘  GET releases/latest with a read-only token
                         downloads the APK to /data/apk  (size and SHA-256 checked against GitHub)
                                                        │
       app (Domů) ── GET /api/app/latest ───────────────┤  "Je dostupná nová verze"
                  ── GET /api/app/apk ──────────────────┘  downloads in the app → Android's install screen
```

- **Only full releases.** The server asks GitHub for `releases/latest`, which skips pre-releases and drafts. A beta tag (`v1.0.1-beta.1`) never reaches phones; betas are still installed by hand ([`beta.md`](./beta.md)).
- **The version comes from the APK's name**, which CI sets: `quizly-<versionName>-<versionCode>.apk`. `versionCode` is the `app` workflow's run number, so it always grows.
- **The app compares versionCodes.** A higher one on the server shows the card on Domů. The check runs when Domů loads, on pull-to-refresh and when the app comes back to the front. A failed check shows nothing.
- **The token never leaves the server.** The app talks only to `quizly.jbohacek.cz`; the APK download needs the user's login, like every other app endpoint.
- **The newest APK is kept on a volume** (`quizly_apk` → `/data/apk`), so a restart serves it without asking GitHub again. Older APKs are deleted.

## 2. On the phone

1. Domů shows **"Je dostupná nová verze"** with the version and size. **Později** hides it until the app starts again.
2. **Aktualizovat** downloads the APK inside the app (progress in %).
3. Android opens its install screen. **The first time**, Android asks to allow installs from Quizly ("Instalace neznámých aplikací" → povolit pro Quizly), then goes back to the install screen.
4. **Instalovat.** The new version installs over the old one. The login, settings and progress stay, because every build is signed with the same key.

A sideloaded app can't install itself silently; the user always confirms in Android's own dialog. Play Protect may ask once whether to scan the app; that's fine.

Builds older than `v1.0.0` have no update check. They need one last manual install.

## 3. Setting it up (once)

1. **Token.** GitHub → Settings → Developer settings → Fine-grained personal access tokens → **Generate new token**:
   - Name `quizly-updates`, expiration up to a year (put the renewal date in your calendar);
   - Repository access: **Only select repositories** → `Jbohacek/Quizly`;
   - Permissions: **Contents: Read-only** (Metadata: Read-only is added automatically). Nothing else.
2. **Portainer** → stack `quizly` → **Environment variables**:
   - `Updates__Repository` = `Jbohacek/Quizly`
   - `Updates__GitHubToken` = the token
   
   → **Update the stack** (with the new `docker-compose.yml`, which adds the `apk` volume).
3. Check: the container log shows `App update 1.0.0 (58) is ready` within a minute of the start (or `No full release found` before the first full release).

Without both variables updates are off: the server never asks GitHub, and the app shows no card.

## 4. Releasing a new version

1. Merge the changes to `main`.
2. Set the version in `app/pubspec.yaml` (`version: 1.0.1+1`; the `+1` is replaced by the run number in CI) and merge that too.
3. Tag and push:
   ```bash
   git tag v1.0.1
   git push origin v1.0.1
   ```
4. The `app` workflow builds the signed APK and attaches it to the **full** release `v1.0.1` (a tag without `-` is not a pre-release).
5. Within ~15 minutes the server has it; phones show the card the next time Domů loads or the app comes back to the front.

## 5. Troubleshooting

| Symptom | Cause |
| --- | --- |
| Log: `No full release found in Jbohacek/Quizly` | only pre-releases so far, or the token can't see the repository |
| Log: `App update check failed` with `401` | the token expired or was revoked: create a new one (§3) and update the stack |
| Log: `Release v1.0.1 has no APK yet` | the workflow is still uploading it, or it failed: check the Actions run |
| Log: `SHA-256 doesn't match` / `got N bytes` | a broken download; the old APK stays and the next check tries again |
| The card doesn't show on a phone | the phone already has that versionCode, or "Později" was tapped (restart the app), or the build is older than `v1.0.0` |
| Android says the app isn't installed / conflicts | the APK was signed with another key (never rotate the signing key, `deploy/README-deploy.md`) |
