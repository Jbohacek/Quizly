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
  static String pointsBalance(int balance) => 'Máš ${points(balance)}';
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
  static String deckMetaLearning(int total, int mastered, int learning) =>
      '${cards(total)} · ${formatPercent(mastered)} zvládnuto · ${formatPercent(learning)} učím se';
  static String deckProgressLabel(int mastered, int learning) =>
      'Postup: ${formatPercent(mastered)} zvládnuto, ${formatPercent(learning)} učím se';
  static String moreNewCards(int count) => 'Ještě ${countOf(count, 'nová karta', 'nové karty', 'nových karet')}';
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
  static const searchCards = 'Hledat v kartách';
  static const clearSearch = 'Smazat hledání';
  static const filterAll = 'Vše';
  static const filterProblematic = 'Problémové';
  static const statusProblematic = 'Problémová';
  static const noMatch = 'Tomu neodpovídá žádná karta.';
  static String cardsShown(int shown, int total) => '${formatInt(shown)} z ${formatInt(total)}';
  static const cardProgress = 'Cesta ke zvládnutí';
  static String cardAnswers(int know, int dontKnow) => 'Vím: ${formatInt(know)} · Nevím: ${formatInt(dontKnow)}';
  // Problematic cards always have at least 2 recent answers, so "odpovědí" (genitive plural) fits.
  static String recentDontKnow(int dontKnow, int answers) =>
      'Z posledních ${formatInt(answers)} odpovědí: Nevím ${formatInt(dontKnow)}×';
  static String nextReview(String when) => 'Další opakování: $when';
  static const nextReviewNow = 'Další opakování: teď';
  static const notStudiedYet = 'Zatím bez odpovědi. Přijde na řadu mezi novými kartami.';
  static const showCard = 'Ukázat odpověď a postup';
  static const hideCard = 'Skrýt odpověď';
  static const emptyDeck = 'V tomhle balíčku zatím nejsou žádné karty.';

  // Card editor (#23)
  static const editCard = 'Upravit';
  static const editCardTitle = 'Upravit kartu';
  static const newCard = 'Nová karta';
  static const addCard = 'Přidat kartu';
  static const questionLabel = 'Otázka';
  static const answerLabel = 'Odpověď';
  static const fillQuestion = 'Vyplň otázku.';
  static const fillAnswer = 'Vyplň odpověď.';
  static const formattingHint = 'Formátování: **tučně**, *kurzíva*, <small>malé písmo</small>. '
      'Řádek začínající „- “ je odrážka, „1. “ číslovaný seznam.';
  static const tagsLabel = 'Tagy';
  static const tagsHint = 'Odděl středníkem, např. ai_gen ; prednaska_01';
  static String tagsSemantics(List<String> tags) => 'Tagy: ${tags.join(', ')}';
  static const preview = 'Náhled';
  static const saveCard = 'Uložit kartu';
  static const deleteCard = 'Smazat kartu';
  static const deleteCardTitle = 'Smazat kartu?';
  static const deleteCardText = 'Karta zmizí všem uživatelům i s jejich postupem. Nejde to vrátit.';
  static const delete = 'Smazat';
  static const cardEditShared = 'Úprava se projeví všem, kdo balíček vidí. Postup v kartě zůstane.';
  static const discardTitle = 'Zahodit změny?';
  static const discardText = 'Úpravy karty se neuloží.';
  static const keepEditing = 'Pokračovat v úpravách';
  static const discard = 'Zahodit';

  // Session
  static const closeSession = 'Ukončit učení';
  static String cardOf(int index, int total) => 'Karta $index z $total';
  static const progressLabel = 'Postup v sezení';
  static const allDecks = 'Vše';
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
  static const hard = 'Těžké';
  static const easy = 'Snadné';
  static const stampHard = 'TĚŽKÉ';
  static const stampEasy = 'SNADNÉ';
  static const skip = 'Přeskočit';
  static const stampKnow = 'VÍM';
  static const stampDontKnow = 'NEVÍM';
  static const saving = 'Ukládám odpovědi…';
  static const emptySessionTitle = 'Na teď je hotovo';
  static const emptySessionText = 'Žádné karty k opakování ani nové karty na dnešek. Zítra tu budou další.';
  static const emptySessionMore = 'Nové karty na dnešek máš za sebou. Jestli máš chuť, přidej si další.';
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
  static String hardRow(int count) => '${formatInt(count)} × Těžké';
  static String easyRow(int count) => '${formatInt(count)} × Snadné';
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
  static const howItWorks = 'Jak Quizly dávkuje karty';
  static const howItWorksHint = 'Proč se karty vracejí, kdy se vracejí';
  static const howItWorksText = [
    'Quizly používá algoritmus FSRS. U každé karty sleduje, jak dlouho ti odpověď vydrží v paměti.',
    'Kartu ti ukáže znovu ve chvíli, kdy šance, že si odpověď vybavíš, klesne zhruba na 90 %. Opakuješ tak jen to, co je potřeba.',
    '**Vím:** pauza do dalšího opakování se prodlouží. Z minut jsou dny, pak týdny a měsíce.',
    '**Nevím:** karta se ještě jednou vrátí na konec učení a pak brzy znovu, dokud se neusadí.',
    '**Těžké a Snadné** (zapneš v Nastavení): Těžké znamená, že odpověď šla ztuha, pauza se prodlouží méně. Snadné ji prodlouží víc. Body jsou stejné jako za Vím.',
    '**Nové karty** přibývají po pár denně (Nové karty denně v Nastavení), ať se opakování nenahromadí. Chceš víc? Až bude na dnešek hotovo, dej na Domů „Ještě 5 nových karet“.',
    '**Nová:** zatím bez odpovědi. **Učím se:** karta se teprve usazuje. **Zvládnuto:** vydrží v paměti aspoň 3 týdny.',
  ];
  static const dailyGoalHint = 'Kolik karet denně stačí, aby se den počítal do série';
  static const decreaseGoal = 'Snížit denní cíl';
  static const increaseGoal = 'Zvýšit denní cíl';
  static const newPerDay = 'Nové karty denně';
  static const newPerDayHint = 'Kolik nových karet přidat k opakování';
  static const fourRatings = 'Těžké a Snadné';
  static const fourRatingsHint = 'Po otočení karty i tlačítka Těžké a Snadné. Body jako za Vím.';
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

  // Žebříček (#34)
  static const myStats = 'Moje statistiky';
  static const leaderboard = 'Žebříček';
  static const periodWeek = 'Tento týden';
  static const periodAllTime = 'Celkově';
  static const metricPoints = 'Body';
  static const metricStreak = 'Série';
  static const emptyLeaderboard = 'V žebříčku zatím nikdo není.';
  static const hiddenFromLeaderboard = 'V žebříčku tě ostatní nevidí. Zapnout to jde v Nastavení.';
  static String rankPosition(int rank) => '$rank.';
  static String rankLabel(int rank) => '$rank. místo';
  static String yourRankBadge(int rank) => 'Jsi na $rank. místě';
  static const youBadge = 'Ty';
  static String leaderboardPointsLine(int streak, int count) => 'Série: ${days(streak)} · ${cards(count)}';
  static String leaderboardStreakLine(int earned, int count) => '${points(earned)} · ${cards(count)}';
  static const showInLeaderboard = 'Zobrazit mě v žebříčku';
  static const showInLeaderboardHint = 'Ostatní uvidí tvé body a sérii ve Statistikách.';

  // Notifications (docs/notifications.md)
  static const channelReminders = 'Připomínky';
  static const channelRemindersHint = 'Ranní a večerní připomínka a poslední výzva';
  static const channelAchievements = 'Úspěchy';
  static const channelAchievementsHint = 'Milníky série a odměny ze seznamu přání';
  static const fallbackMorning = 'Dobré ráno! ☀️ Na dnešek tě čeká pár karet. Pojďme na to spolu.';
  static const fallbackEvening = 'Ještě je čas na pár karet 📚 Dáme to spolu?';
  static const fallbackLastCall = 'Dnešní cíl je pořád na dosah 🔥 Pár minut a série jede dál.';
  static const fallbackMilestone = 'Další milník v sérii! 🎉 Máš můj obdiv.';
  static const fallbackWishlist = 'Na odměnu ze seznamu přání už máš body 🎁 Mrkni do obchodu.';
  static const fallbackComeback = 'Vítej zpátky 💚 Začneme znovu, spolu to dáme!';
  static const askTitle = 'Mám ti připomínat učení? 🔔';
  static const askText = 'Ráno ti napíšu, kolik karet tě čeká. Večer připomenu denní cíl, jen když ještě není splněný.';
  static const allow = 'Povolit';
  static const notNow = 'Teď ne';

  // App updates (docs/app-updates.md)
  static const updateTitle = 'Je dostupná nová verze';
  static String updateText(String version, String size) =>
      'Verze $version je připravená ($size). Po stažení potvrď instalaci v Androidu, přihlášení zůstane.';
  static const updateNow = 'Aktualizovat';
  static const updateLater = 'Později';
  static String updateDownloading(String percent) => 'Stahuji… $percent';
  static const updateFailed = 'Stažení se nepovedlo. Zkus to prosím znovu.';
  static const updateInstallFailed = 'Instalaci se nepodařilo otevřít. Zkus to prosím znovu.';
  static const notifications = 'Upozornění';
  static const sendNotifications = 'Posílat upozornění';
  static const sendNotificationsHint = 'Připomínky učení, milníky a odměny';
  static const systemOff = 'Upozornění jsou vypnutá v systému';
  static const systemOffText = 'Povol je v nastavení telefonu, jinak ti žádné nepřijde.';
  static const allowNotifications = 'Povolit upozornění';
  static const morningReminder = 'Ranní připomínka';
  static const morningReminderHint = 'Kolik karet tě dnes čeká';
  static const eveningReminder = 'Večerní připomínka';
  static const eveningReminderHint = 'Jen když ještě nemáš splněný cíl';
  static String eveningSmart(String time) => 'S Chytrými časy teď v $time';
  static const lastCall = 'Poslední výzva';
  static const lastCallHint = 'Když je série v ohrožení';
  static const quietHours = 'Tichý režim';
  static const quietHoursHint = 'V tuto dobu nic nepošleme';
  static const quietFrom = 'Tichý režim od';
  static const quietTo = 'Tichý režim do';
  static String quietRange(String from, String to) => '$from–$to';
  static const quietSame = 'Tichý režim musí začínat a končit v jiný čas.';
  static const smartTimes = 'Chytré časy';
  static const smartTimesHint = 'Posouvat večerní připomínku k času, kdy se obvykle učíš';
  static String timeLabel(String title, String time) => '$title, $time';
}
