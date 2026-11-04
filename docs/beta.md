# Beta: the first tester

Etapa 8 part 1 ends with one beta user who isn't Jakub. They use the app for real for a while; what they find goes into part 2, then `v1.0.0` is released.

## 1. Build the beta APK

After this stage's PR is merged and the server runs the new image (Runbook → Update in [`deploy/README-deploy.md`](../deploy/README-deploy.md)):

```bash
git checkout main
git pull
git tag v1.0.0-beta.1
git push origin v1.0.0-beta.1
```

The `app` workflow builds the signed APK and creates a GitHub **pre-release** `v1.0.0-beta.1` with `quizly-1.0.0-beta.1-<run>.apk` attached. The repository is private, so download the APK from the release and send the file to the tester yourself (chat, e-mail, cloud drive).

The next beta builds are `v1.0.0-beta.2`, … They install over the old app; the login stays.

## 2. Create the account

Dashboard → **Uživatelé → Nový uživatel**:

- username: lowercase letters and digits;
- display name: what the app greets them with;
- **Denní cíl**: start low (e.g. 10), they can change it in Nastavení;
- the generated password is shown **once**. Send it separately from the APK.

Check that there's a deck to study and a couple of rewards in **Obchod** they would actually like.

## 3. Message for the tester

Copy, fill in, send (gender-neutral, like the app):

> Ahoj! Díky, že mi pomůžeš otestovat Quizly 🙌
>
> **Instalace:** otevři přiložený soubor `quizly-….apk`. Telefon se zeptá, jestli může instalovat aplikace z tohohle zdroje: povol to a dej **Instalovat**. Když Play Protect varuje, zvol **Přesto nainstalovat**. Potřebuješ Android 8 nebo novější.
>
> **Přihlášení:** jméno `…`, heslo ti pošlu zvlášť. Heslo si pak můžeš změnit v Nastavení.
>
> **Upozornění:** na Domů se aplikace zeptá, jestli ti má připomínat učení. Dej **Povolit**. Časy si nastavíš v Nastavení → Upozornění.
> Na Samsungu (a podobně na Xiaomi) je dobré v Nastavení telefonu → Baterie → Limity používání na pozadí zkontrolovat, že Quizly není mezi uspanými aplikacemi, jinak můžou připomínky chodit pozdě.
>
> **Co zkusit:** uč se každý den aspoň chvilku, sleduj sérii a body, označ si srdíčkem odměnu a jednu si kup. Nákup schvaluju já.
>
> **Když něco nefunguje nebo je divné:** pošli mi screenshot a napiš, co se zrovna dělo a kolik bylo hodin. Každá poznámka pomůže, i drobnost v textu.

## 4. During the beta

- **Přehled → Uživatelé dnes:** streak, today's progress and last activity show whether the app is being used.
- **Obchod → historie nákupů:** confirm or reject their purchases.
- **Notifications:** ask after a few days whether the morning reminder came and whether the evening one stopped on days the goal was met. This also covers the Etapa 7 gate.
- Backups run every night (Runbook → Backups).
- Collect the feedback in one place (e.g. GitHub issues or a note). It becomes the task list of part 2.

## 5. After the beta

Part 2 of Etapa 8: fix what came up, then tag `v1.0.0` (`app/pubspec.yaml` already says `1.0.0`). The tester installs that APK over the beta by hand, one last time: from `v1.0.0` on, new versions are offered in the app ([`app-updates.md`](./app-updates.md)).
