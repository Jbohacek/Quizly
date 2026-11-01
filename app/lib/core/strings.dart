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
  static const comingSoon = 'Už brzy';
  static const statsSoon = 'Statistiky učení přibudou v příští verzi.';
  static const shopSoon = 'Obchod s odměnami přibude v příští verzi. Body se ti mezitím sčítají.';

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
}
