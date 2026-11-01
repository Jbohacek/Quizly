# Quizly app (Flutter, Android)

Czech flashcard app for the Quizly API. Android 8.0+ (API 26). Brief: [`../CLAUDE.md`](../CLAUDE.md), API contract: [`../docs/api.md`](../docs/api.md).

## Run it on a phone or emulator

```bash
cd app
flutter pub get
flutter run --dart-define=API_BASE_URL=https://quizly.jbohacek.cz
```

`API_BASE_URL` defaults to `https://quizly.jbohacek.cz`. For a local API (`dotnet run --project src/Quizly.Web --urls http://0.0.0.0:5278`):

| Where the app runs | `API_BASE_URL` |
| --- | --- |
| Android emulator | `http://10.0.2.2:5278` |
| Phone on the same Wi-Fi | `http://<PC's LAN IP>:5278` (allow port 5278 in Windows Firewall) |

Plain HTTP works only in **debug** builds (`android/app/src/debug/AndroidManifest.xml`); release builds use HTTPS.

A debug build and the release APK are signed with different keys. Uninstall one before installing the other, or Android says "App not installed".

## Tests

```bash
flutter analyze
flutter test
```

Pure Dart tests cover Czech formatting, the session queue (Nevím re-queue, skip), the points tally and the review outbox (retry, back-off, idempotent UUIDs, offline, persistence).

## Release APK (GitHub Actions)

`.github/workflows/app.yml`:
- **Pull request:** `flutter analyze` + `flutter test`.
- **Push to `main`** (changes under `app/`): a signed release APK as the run's artifact `quizly-<version>-<run>.apk`.
- **Tag `v*`:** the same APK is also attached to the GitHub Release.

`versionCode` is the workflow run number, so every new APK installs over the previous one. `versionName` comes from `pubspec.yaml`.

### One-time: the signing key (Jakub)

The APK must be signed with **the same key every time**, or it won't install over the old one. Create it once, on your PC, and back it up outside the repo (e.g. in a password manager). If the key is lost, the app has to be uninstalled and installed again (and logged in again).

1. Create the keystore (PowerShell, use one password for both prompts; PKCS12 uses the same password for the store and the key):

   ```powershell
   & "C:\Program Files\Android\Android Studio\jbr\bin\keytool.exe" -genkeypair -v -keystore "$HOME\quizly-upload.jks" -storetype PKCS12 -keyalg RSA -keysize 4096 -validity 10000 -alias quizly -dname "CN=Quizly"
   ```

2. Add the 4 secrets in GitHub: **Settings → Secrets and variables → Actions → New repository secret** (Actions, not Codespaces). With the GitHub CLI from the repo folder:

   ```powershell
   [Convert]::ToBase64String([IO.File]::ReadAllBytes("$HOME\quizly-upload.jks")) | gh secret set ANDROID_KEYSTORE_BASE64
   gh secret set ANDROID_KEYSTORE_PASSWORD
   gh secret set ANDROID_KEY_PASSWORD
   "quizly" | gh secret set ANDROID_KEY_ALIAS
   ```

   `gh secret set` without a value asks for it, so the password isn't saved in the shell history. Use the keystore password for both `ANDROID_KEYSTORE_PASSWORD` and `ANDROID_KEY_PASSWORD`.

3. Never commit the keystore or `android/key.properties` (both are in `.gitignore`).

To build a signed APK locally, create `android/key.properties` (not committed):

```properties
storeFile=C:/Users/<you>/quizly-upload.jks
storePassword=…
keyAlias=quizly
keyPassword=…
```

Without it, `flutter build apk --release` signs with the debug key.

## Install the APK on the phone

1. GitHub → **Actions → app → the latest run on `main`** → **Artifacts** → download and unzip `quizly-….apk` (or take it from a Release).
2. Copy it to the phone (or download it straight on the phone) and tap it.
3. Allow **Install unknown apps** for the app that opens it (Files / Chrome), then **Install**. If Play Protect warns, choose **Install anyway**.
4. Next versions install over the old one; the login stays.

## Structure

```
lib/
├─ main.dart, router.dart
├─ core/      api/ (dio client with token refresh, DTOs, errors) · storage/ (secure token store)
│             theme/ (tokens §9.1) · widgets/ · strings.dart (all Czech text) · format.dart · providers.dart
└─ features/  auth/ (Přihlášení) · home/ (Domů) · session/ (queue, outbox sync, swipe card, Hotovo)
              settings/ (Nastavení) · shell/ (bottom navigation)
```
