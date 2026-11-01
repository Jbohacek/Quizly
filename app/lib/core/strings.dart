import 'format.dart';

/// Every Czech UI string of the app (CLAUDE.md §12). Gender-neutral (§2.11).
abstract final class S {
  static const appName = 'Quizly';

  // Common
  static const retry = 'Zkusit znovu';
  static const cancel = 'Zrušit';
  static const offline = 'Jsi offline';
  static const offlineHint = 'Jakmile se připojení vrátí, pokračujeme.';
  static const loadFailed = 'Nepodařilo se načíst data.';
  static const networkError = 'Server teď není k zastižení. Zkontroluj připojení k internetu.';
  static const serverError = 'Něco se pokazilo na serveru. Zkus to prosím za chvíli.';
  static String rateLimited(int seconds) => 'Moc pokusů najednou. Zkus to znovu za ${_wait(seconds)}.';
  static String _wait(int seconds) => seconds < 60 ? '$seconds s' : '${(seconds / 60).ceil()} min';

  // Login
  static const loginTagline = 'Každý den kousek.\nKaždý den o kus lepší.';
  static const username = 'Uživatelské jméno';
  static const usernameHint = 'např. kuba';
  static const password = 'Heslo';
  static const showPassword = 'Zobrazit heslo';
  static const hidePassword = 'Skrýt heslo';
  static const signIn = 'Přihlásit se';
  static const signInNote = 'Účet ti založí správce aplikace. Zapomenuté heslo ti také resetuje správce.';
  static const fillBoth = 'Vyplň uživatelské jméno i heslo.';
  static const sessionExpired = 'Platnost přihlášení vypršela. Přihlas se prosím znovu.';
  static const accountDisabled = 'Účet je deaktivovaný. Ozvi se prosím správci aplikace.';

  // Navigation
  static const navHome = 'Domů';
  static const navStats = 'Statistiky';
  static const navShop = 'Obchod';
  static const navSettings = 'Nastavení';

  // Home
  static String greeting(String name) => 'Ahoj, $name!';
  static String pointsPill(int balance) => 'Máš ${points(balance)}, otevřít obchod';
  static String streakLabel(int streak) => plural(streak, 'den v řadě', 'dny v řadě', 'dní v řadě');
  static String nextMultiplier(int inDays, num value) =>
      'Za ${days(inDays)} násobič stoupne na ${formatMultiplier(value)}';
  static const maxMultiplier = 'Násobič je na maximu. Paráda!';
  static const startStreak = 'Splň dnešní cíl a série začne';
  static const multiplier = 'násobič';
  static const dailyGoal = 'Denní cíl';
  static String goalLeft(int left) => 'Ještě ${cards(left)} a dnešek se počítá';
  static const goalMet = 'Splněno, dnešek se počítá!';
  static String dueAndNew(int due, int fresh) =>
      '${formatInt(due)} k opakování · ${countOf(fresh, 'nová', 'nové', 'nových')}';
  static String studyAll(int count) => 'Učit se vše · ${cards(count)}';
  static const nothingDue = 'Na teď je všechno hotovo';
  static const decks = 'Balíčky';
  static String deckCount(int count) => countOf(count, 'balíček', 'balíčky', 'balíčků');
  static String deckDue(int due) => '${formatInt(due)} k opakování';
  static String deckNew(int fresh) => countOf(fresh, 'nová', 'nové', 'nových');
  static const deckDone = 'hotovo';
  static String deckMeta(int total, int mastered) => '${cards(total)} · ${formatPercent(mastered)} zvládnuto';
  static const noDecks = 'Zatím tu nejsou žádné balíčky. Správce je brzy přidá.';

  // Deck detail
  static const back = 'Zpět';
  static String studyDeck(int count) => 'Učit se · ${cards(count)}';
  static const tileTotal = 'karet';
  static const tileDue = 'k opakování';
  static const tileNew = 'nových dnes';
  static const tileMastered = 'zvládnuto';
  static const cardsInDeck = 'Karty v balíčku';
  static const statusNew = 'Nová';
  static const statusLearning = 'Učím se';
  static const statusMastered = 'Zvládnuto';
  static const showAnswer = 'Klepni pro odpověď';
  static const emptyDeck = 'V tomhle balíčku zatím nejsou žádné karty.';

  // Session
  static const closeSession = 'Ukončit učení';
  static String cardOf(int index, int total) => 'Karta $index z $total';
  static const progressLabel = 'Postup v sezení';
  static const allDecks = 'Vše';
  static const kindNew = 'Nová';
  static const kindLearning = 'Učím se';
  static const kindReview = 'Opakování';
  static const kindRelearning = 'Znovu';
  static String multiplierChip(num value) => 'násobič ${formatMultiplier(value)}';
  static const question = 'OTÁZKA';
  static const answer = 'ODPOVĚĎ';
  static const tapToFlip = 'Klepni a otoč kartu';
  static const tapToFlipBack = 'Klepni a otoč zpět';
  static String hintDontKnow(int value) => '← Nevím · ${formatSigned(value)}';
  static String hintKnow(int value) => 'Vím · ${formatSigned(value)} →';
  static const hintDrag = 'nebo táhni kartou';
  static const know = 'Vím';
  static const dontKnow = 'Nevím';
  static const skip = 'Přeskočit';
  static const stampKnow = 'VÍM';
  static const stampDontKnow = 'NEVÍM';
  static const saving = 'Ukládám odpovědi…';
  static const emptySessionTitle = 'Na teď je hotovo';
  static const emptySessionText = 'Žádné karty k opakování ani nové karty na dnešek. Zítra tu budou další.';
  static const backHome = 'Zpět domů';
  static const leaveTitle = 'Ukončit učení?';
  static const leaveText = 'Odpovědi, které už máš, zůstanou uložené.';
  static const leave = 'Ukončit';
  static const stay = 'Pokračovat';

  // Done
  static const goalMetTitle = 'Denní cíl splněn!';
  static const doneTitle = 'Hotovo!';
  static String streakNow(int streak) => 'Série: ${days(streak)} v řadě.';
  static String doneGoalLeft(int left) => 'Do denního cíle chybí ještě ${cards(left)}.';
  static const doneGoalAlready = 'Dnešní cíl už máš splněný.';
  static const tileCards = 'karet';
  static const tileCorrect = 'správně';
  static const tilePoints = 'bodů';
  static String knowRow(int count) => '${formatInt(count)} × Vím';
  static String dontKnowRow(int count) => '${formatInt(count)} × Nevím';
  static String milestoneRow(int streakDays) => 'Bonus za ${days(streakDays)} v řadě';
  static const multiplierRow = 'Násobič série';
  static String multiplierCounted(num value) => '${formatMultiplier(value)} započten';
  static const newBalance = 'Nový zůstatek';
  static const studyMore = 'Učit se dál';
  static const done = 'Hotovo';

  // Settings
  static const settings = 'Nastavení';
  static const account = 'Tvůj účet';
  static const changePassword = 'Změnit heslo';
  static const changePasswordHint = 'Ostatní zařízení se odhlásí';
  static const currentPassword = 'Současné heslo';
  static const newPassword = 'Nové heslo';
  static const newPasswordAgain = 'Nové heslo znovu';
  static const passwordRules = 'Aspoň 8 znaků. Zapomenuté heslo ti resetuje správce.';
  static const passwordTooShort = 'Nové heslo musí mít aspoň 8 znaků.';
  static const passwordsDiffer = 'Hesla se neshodují.';
  static const fillCurrentPassword = 'Vyplň současné heslo.';
  static const passwordChanged = 'Heslo je změněné.';
  static const learning = 'Učení';
  static const dailyGoalHint = 'Tolik karet a den se počítá do série';
  static const decreaseGoal = 'Snížit denní cíl';
  static const increaseGoal = 'Zvýšit denní cíl';
  static const newPerDay = 'Nové karty denně';
  static const newPerDayHint = 'Kolik nových karet přidat k opakování';
  static const fewerNew = 'Méně nových karet';
  static const moreNew = 'Více nových karet';
  static const settingsSaveFailed = 'Nastavení se nepodařilo uložit.';
  static const signOut = 'Odhlásit se';
  static const signOutTitle = 'Odhlásit se?';
  static const signOutText = 'Pro další učení se budeš muset znovu přihlásit.';
  static String signOutPending(int count) =>
      'Neodeslané odpovědi: ${formatInt(count)}. Odešlou se po dalším přihlášení.';
  static String version(String version, String host) => 'Quizly $version · $host';

  // Week strip (Domů)
  static const thisWeek = 'Tento týden';
  static const weekdaysShort = ['Po', 'Út', 'St', 'Čt', 'Pá', 'So', 'Ne'];
  static const weekdaysLong = ['pondělí', 'úterý', 'středa', 'čtvrtek', 'pátek', 'sobota', 'neděle'];
  static const dayDone = 'splněno';
  static const dayToday = 'dnes';
  static const dayMissed = 'nesplněno';
  static const dayFuture = 'ještě nebylo';

  // Done (Etapa 6 additions)
  static String milestoneTitle(int streakDays) => '${days(streakDays)} v řadě!';
  static String milestoneText(int bonus) =>
      'Bonus +${points(bonus)} je tvůj. Tohle je paráda! 🎉';
  static String streakGrows(int streak) => 'Série roste na ${days(streak)}.';
  static String multiplierTomorrow(num value) => 'Zítra se ti násobič zvedne na ${formatMultiplier(value)}.';
  static String multiplierIn(int inDays, num value) =>
      'Za ${days(inDays)} se ti násobič zvedne na ${formatMultiplier(value)}.';
  static const fromWishlist = 'Z tvého seznamu přání';
  static String wishlistLeft(int missing, int knows) =>
      'Chybí už jen ${points(missing)}, to je zhruba ${formatInt(knows)} × Vím.';
  static const wishlistReady = 'Už na to máš!';
  static String wishlistReadyText(String name) => 'Body na „$name“ máš pohromadě. Odměna čeká v obchodě.';

  // Shop
  static const savingFor = 'Šetříš na';
  static String savingProgress(int balance, int price) => '${formatInt(balance)} / ${formatInt(price)}';
  static String savingMissing(int missing) => 'Chybí ${points(missing)}.';
  static const savingReady = 'Už na to máš! Odměnu si můžeš koupit.';
  static const savingEmpty = 'Označ srdíčkem odměnu, na kterou šetříš, a tady uvidíš, kolik ti chybí.';
  static const tabRewards = 'Odměny';
  static const myClaims = 'Moje nákupy';
  static String tabClaims(int count) => count == 0 ? myClaims : '$myClaims · ${formatInt(count)}';
  static const soldOut = 'Vyprodáno';
  static const lastPiece = 'Poslední kus';
  static String stockLeft(int stock) => 'Zbývá ${formatInt(stock)} ks';
  static const buy = 'Koupit';
  static String missingShort(int missing) => 'Chybí ${formatInt(missing)}';
  static const wishAdd = 'Přidat na seznam přání';
  static const wishRemove = 'Odebrat ze seznamu přání';
  static const wishFailed = 'Seznam přání se nepodařilo uložit.';
  static const noItems = 'Obchod je zatím prázdný. Správce brzy přidá odměny.';
  static String confirmTitle(String name) => 'Koupit „$name“?';
  static const price = 'Cena';
  static const yourBalance = 'Tvůj zůstatek';
  static const afterPurchase = 'Po nákupu';
  static const confirmInfoStart = 'Body se strhnou hned a nákup pak ';
  static const confirmInfoStrong = 'schválí správce';
  static const confirmInfoEnd = '. Když ho zamítne, body ti vrátíme.';
  static String buyFor(int price) => 'Koupit za ${formatInt(price)}';
  static String cannotBuyYet(int missing) => 'Na tuhle odměnu ti zatím chybí ${points(missing)}.';
  static String bought(String name) => 'Hotovo! „$name“ teď čeká na schválení.';
  static const claimsEmpty = 'Zatím tu nic není. Co si koupíš v obchodě, uvidíš tady i se stavem.';
  static const claimPending = 'Čeká na schválení';
  static const claimConfirmed = 'Schváleno';
  static const claimRejected = 'Zamítnuto';
  static String claimRefunded(int price) => '${points(price)} ${plural(price, 'vrácen', 'vráceny', 'vráceno')}';

  // Stats
  static const allDecksFilter = 'Všechny balíčky';
  static const chooseDeck = 'Vyber balíček';
  static const tileStreak = 'Série';
  static String record(int best) => 'rekord ${days(best)}';
  static const tileSuccess = 'Úspěšnost · 30 dní';
  static const noValue = '–';
  static const noReviewsYet = 'zatím bez odpovědí';
  static const tileReviewed = 'Zopakováno';
  static String reviewedTotal(int count) => '${plural(count, 'karta', 'karty', 'karet')} celkem';
  static const tileEarned = 'Získáno';
  static String earnedTotal(int count) => '${plural(count, 'bod', 'body', 'bodů')} celkem';
  static const activity = 'Aktivita';
  static const last17Weeks = 'posledních 17 týdnů';
  static const monthsShort = ['Led', 'Úno', 'Bře', 'Dub', 'Kvě', 'Čvn', 'Čvc', 'Srp', 'Zář', 'Říj', 'Lis', 'Pro'];
  static const less = 'Méně';
  static const more = 'Více';
  static const darkerBelowGoal = 'tmavší = pod cílem';
  static String activityLabel(int met) => 'Kalendář aktivity za 17 týdnů, splněný cíl: ${days(met)}';
  static const perDay = 'Karet za den';
  static const last14Days = 'posledních 14 dní';
  static String goalLine(int goal) => 'cíl ${formatInt(goal)}';
  static String perDayLabel(int today, int goal) => 'Karet za den, dnes ${formatInt(today)}, cíl ${formatInt(goal)}';
  static const bestTitle = 'Kdy ti to jde nejlíp';
  static const weekdaysLocative = ['v pondělí', 'v úterý', 've středu', 've čtvrtek', 'v pátek', 'v sobotu', 'v neděli'];
  static String bestDay(int weekday) => 'Nejlíp ti to jde ${weekdaysLocative[weekday - 1]}.';
  static String bestTime(int from, int to, int rate) =>
      'Nejlepší čas dne je mezi $from a $to h (${formatPercent(rate)} správně).';
  static const bestNone = 'Až bude odpovědí víc, ukážeme ti, kdy ti to jde nejlíp.';
  static const progressTitle = 'Postup v balíčcích';
  static const legendNew = 'Nové';
  static const noProgress = 'Zatím tu nejsou žádné balíčky.';
}
