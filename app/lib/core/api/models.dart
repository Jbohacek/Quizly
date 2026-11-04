// DTOs of the REST API (docs/api.md). Hand-written fromJson/toJson, no codegen.

typedef Json = Map<String, dynamic>;

int _int(Object? v) => (v as num).toInt();
double _double(Object? v) => (v as num).toDouble();

/// Card tags (#29); an older server doesn't send them.
List<String> _tags(Object? v) => (v as List?)?.cast<String>() ?? const [];

class AppUser {
  const AppUser({required this.id, required this.username, required this.displayName, this.shopEnabled = true});

  factory AppUser.fromJson(Json j) => AppUser(
        id: _int(j['id']),
        username: j['username'] as String,
        displayName: j['displayName'] as String,
        shopEnabled: j['shopEnabled'] as bool? ?? true,
      );

  final int id;
  final String username;
  final String displayName;

  /// The admin can keep a user out of the shop: then Obchod, rewards and purchases are hidden.
  final bool shopEnabled;

  Json toJson() => {'id': id, 'username': username, 'displayName': displayName, 'shopEnabled': shopEnabled};
}

/// Tokens from `/auth/login` and `/auth/refresh`.
class AuthTokens {
  const AuthTokens({
    required this.accessToken,
    required this.accessTokenExpiresAt,
    required this.refreshToken,
    required this.refreshTokenExpiresAt,
    required this.user,
  });

  factory AuthTokens.fromJson(Json j) => AuthTokens(
        accessToken: j['accessToken'] as String,
        accessTokenExpiresAt: DateTime.parse(j['accessTokenExpiresAt'] as String),
        refreshToken: j['refreshToken'] as String,
        refreshTokenExpiresAt: DateTime.parse(j['refreshTokenExpiresAt'] as String),
        user: AppUser.fromJson(j['user'] as Json),
      );

  final String accessToken;
  final DateTime accessTokenExpiresAt;
  final String refreshToken;
  final DateTime refreshTokenExpiresAt;
  final AppUser user;

  Json toJson() => {
        'accessToken': accessToken,
        'accessTokenExpiresAt': accessTokenExpiresAt.toUtc().toIso8601String(),
        'refreshToken': refreshToken,
        'refreshTokenExpiresAt': refreshTokenExpiresAt.toUtc().toIso8601String(),
        'user': user.toJson(),
      };
}

class Today {
  const Today({
    required this.date,
    required this.graded,
    required this.correct,
    required this.goal,
    required this.goalMet,
    required this.points,
  });

  factory Today.fromJson(Json j) => Today(
        date: DateTime.parse(j['date'] as String),
        graded: _int(j['graded']),
        correct: _int(j['correct']),
        goal: _int(j['goal']),
        goalMet: j['goalMet'] as bool,
        points: _int(j['points']),
      );

  final DateTime date;
  final int graded;
  final int correct;
  final int goal;
  final bool goalMet;
  final int points;

  /// Graded answers still missing to meet the goal (0 once met).
  int get left => goalMet ? 0 : (goal - graded).clamp(0, goal);
}

class NextMultiplier {
  const NextMultiplier({required this.value, required this.inDays});

  factory NextMultiplier.fromJson(Json j) => NextMultiplier(value: _double(j['value']), inDays: _int(j['inDays']));

  final double value;
  final int inDays;
}

/// The streak that was lost, set while it's fresh (api.md §1.2).
class StreakBroken {
  const StreakBroken({required this.previousStreak, required this.brokenOn});

  factory StreakBroken.fromJson(Json j) =>
      StreakBroken(previousStreak: _int(j['previousStreak']), brokenOn: DateTime.parse(j['brokenOn'] as String));

  final int previousStreak;

  /// The Prague day the streak broke at (the day after the missed one).
  final DateTime brokenOn;
}

/// Balance, streak, multiplier and today's progress (api.md §1.2).
class Summary {
  const Summary({
    required this.balance,
    required this.streak,
    required this.bestStreak,
    required this.multiplier,
    required this.nextMultiplier,
    required this.today,
    this.streakBroken,
  });

  factory Summary.fromJson(Json j) => Summary(
        balance: _int(j['balance']),
        streak: _int(j['streak']),
        bestStreak: _int(j['bestStreak']),
        multiplier: _double(j['multiplier']),
        nextMultiplier: j['nextMultiplier'] == null ? null : NextMultiplier.fromJson(j['nextMultiplier'] as Json),
        today: Today.fromJson(j['today'] as Json),
        streakBroken: j['streakBroken'] == null ? null : StreakBroken.fromJson(j['streakBroken'] as Json),
      );

  final int balance;
  final int streak;
  final int bestStreak;
  final double multiplier;
  final NextMultiplier? nextMultiplier;
  final Today today;
  final StreakBroken? streakBroken;
}

/// Cards waiting at the next morning reminder (api.md §3).
class Forecast {
  const Forecast({required this.nextMorning, required this.dueByNextMorning});

  factory Forecast.fromJson(Json j) =>
      Forecast(nextMorning: DateTime.parse(j['nextMorning'] as String), dueByNextMorning: _int(j['dueByNextMorning']));

  final DateTime nextMorning;
  final int dueByNextMorning;
}

class Me {
  const Me({
    required this.user,
    required this.summary,
    required this.dueNow,
    this.forecast,
    this.smartEveningTime,
  });

  factory Me.fromJson(Json j) => Me(
        user: AppUser.fromJson(j['user'] as Json),
        summary: Summary.fromJson(j['summary'] as Json),
        dueNow: _int(j['dueNow']),
        forecast: j['forecast'] == null ? null : Forecast.fromJson(j['forecast'] as Json),
        smartEveningTime: j['smartEveningTime'] as String?,
      );

  final AppUser user;
  final Summary summary;

  /// Length of the "Učit se vše" queue: due cards + new cards left for today.
  final int dueNow;

  final Forecast? forecast;

  /// Typical study time for Chytré časy (`HH:mm`), null with too few sessions.
  final String? smartEveningTime;
}

class Deck {
  const Deck({
    required this.id,
    required this.name,
    required this.description,
    required this.color,
    required this.totalCards,
    required this.dueNow,
    required this.newAvailable,
    required this.masteredPercent,
    this.learningPercent = 0,
    this.unseenCards = 0,
  });

  factory Deck.fromJson(Json j) => Deck(
        id: _int(j['id']),
        name: j['name'] as String,
        description: j['description'] as String,
        color: j['color'] as String,
        totalCards: _int(j['totalCards']),
        dueNow: _int(j['dueNow']),
        newAvailable: _int(j['newAvailable']),
        masteredPercent: _int(j['masteredPercent']),
        // Older servers (before Etapa 8 fixes) don't send these.
        learningPercent: _int(j['learningPercent'] ?? 0),
        unseenCards: _int(j['unseenCards'] ?? 0),
      );

  final int id;
  final String name;
  final String description;

  /// `#RRGGBB`.
  final String color;
  final int totalCards;

  /// Cards due for review (new cards not included).
  final int dueNow;
  final int newAvailable;
  final int masteredPercent;
  final int learningPercent;

  /// Cards never answered, whether or not today's allowance is left ("Ještě 5 nových karet").
  final int unseenCards;

  int get freshPercent => (100 - masteredPercent - learningPercent).clamp(0, 100);
}

/// My progress on one card (spec §3.5): Nová, Učím se, Zvládnuto.
enum CardStatus {
  newCard('new'),
  learning('learning'),
  mastered('mastered');

  const CardStatus(this.json);

  final String json;

  static CardStatus parse(String value) => values.firstWhere((s) => s.json == value, orElse: () => learning);
}

class DeckCard {
  const DeckCard({
    required this.id,
    required this.question,
    required this.answer,
    required this.status,
    this.masteryPercent = 0,
    this.knowCount = 0,
    this.dontKnowCount = 0,
    this.nextReview,
    this.tags = const [],
  });

  factory DeckCard.fromJson(Json j) => DeckCard(
        id: _int(j['id']),
        question: j['question'] as String,
        answer: j['answer'] as String,
        status: CardStatus.parse(j['status'] as String),
        masteryPercent: _int(j['masteryPercent'] ?? 0),
        knowCount: _int(j['knowCount'] ?? 0),
        dontKnowCount: _int(j['dontKnowCount'] ?? 0),
        nextReview: j['nextReview'] == null ? null : DateTime.parse(j['nextReview'] as String),
        tags: _tags(j['tags']),
      );

  final int id;
  final String question;
  final String answer;
  final CardStatus status;

  /// Way to Zvládnuto: the memory's stability out of 21 days (100 = Zvládnuto).
  final int masteryPercent;
  final int knowCount;
  final int dontKnowCount;

  /// When the card is due again; null for a new card.
  final DateTime? nextReview;

  /// The card's tags, sorted (#29).
  final List<String> tags;
}

/// `GET /decks/{id}/cards`: the deck with my counts and all its cards in order.
class DeckCards {
  const DeckCards({required this.deck, required this.cards});

  factory DeckCards.fromJson(Json j) => DeckCards(
        deck: Deck.fromJson(j['deck'] as Json),
        cards: [for (final c in j['cards'] as List) DeckCard.fromJson(c as Json)],
      );

  final Deck deck;
  final List<DeckCard> cards;
}

class DeckList {
  const DeckList({required this.items, required this.newAllowanceLeft});

  factory DeckList.fromJson(Json j) => DeckList(
        items: [for (final d in j['items'] as List) Deck.fromJson(d as Json)],
        newAllowanceLeft: _int(j['newAllowanceLeft']),
      );

  final List<Deck> items;
  final int newAllowanceLeft;
}

/// What the next answer is worth at the current multiplier.
class PointsValue {
  const PointsValue({required this.know, required this.dontKnow, int? hard, int? easy})
      : hard = hard ?? know,
        easy = easy ?? know;

  factory PointsValue.fromJson(Json j) => PointsValue(
        know: _int(j['know']),
        dontKnow: _int(j['dontKnow']),
        hard: j['hard'] == null ? null : _int(j['hard']),
        easy: j['easy'] == null ? null : _int(j['easy']),
      );

  final int know;
  final int dontKnow;

  /// Těžké and Snadné are worth a Vím (#19); an older server doesn't send them.
  final int hard;
  final int easy;

  int of(Rating rating) => switch (rating) {
        Rating.know => know,
        Rating.dontKnow => dontKnow,
        Rating.hard => hard,
        Rating.easy => easy,
      };
}

enum CardKind {
  newCard('new'),
  learning('learning'),
  review('review'),
  relearning('relearning');

  const CardKind(this.json);

  final String json;

  static CardKind parse(String value) => values.firstWhere((k) => k.json == value, orElse: () => review);
}

class SessionCard {
  const SessionCard({
    required this.cardId,
    required this.deckId,
    required this.question,
    required this.answer,
    required this.kind,
    this.tags = const [],
  });

  factory SessionCard.fromJson(Json j) => SessionCard(
        cardId: _int(j['cardId']),
        deckId: _int(j['deckId']),
        question: j['question'] as String,
        answer: j['answer'] as String,
        kind: CardKind.parse(j['kind'] as String),
        tags: _tags(j['tags']),
      );

  final int cardId;
  final int deckId;
  final String question;
  final String answer;
  final CardKind kind;

  /// The card's tags, sorted (#29).
  final List<String> tags;

  /// The card after an edit in the session (#23).
  SessionCard edited({required String question, required String answer, required List<String> tags}) =>
      SessionCard(cardId: cardId, deckId: deckId, question: question, answer: answer, kind: kind, tags: tags);
}

class SessionData {
  const SessionData({
    required this.deckId,
    required this.multiplier,
    required this.points,
    required this.cards,
    this.fourRatings = false,
  });

  factory SessionData.fromJson(Json j) => SessionData(
        deckId: j['deckId'] == null ? null : _int(j['deckId']),
        multiplier: _double(j['multiplier']),
        points: PointsValue.fromJson(j['points'] as Json),
        cards: [for (final c in j['cards'] as List) SessionCard.fromJson(c as Json)],
        fourRatings: j['fourRatings'] as bool? ?? false,
      );

  final int? deckId;
  final double multiplier;
  final PointsValue points;
  final List<SessionCard> cards;

  /// "Těžké a Snadné" is on: four answer buttons after the flip (#19).
  final bool fourRatings;
}

enum Rating {
  know('know'),
  dontKnow('dontKnow'),
  hard('hard'),
  easy('easy');

  const Rating(this.json);

  final String json;

  /// Everything but Nevím counts as remembered (correct).
  bool get correct => this != Rating.dontKnow;

  static Rating parse(String value) => values.firstWhere((r) => r.json == value);
}

/// One answer in the outbox. [id] is a client UUID v4 (idempotency, api.md §11).
class ReviewItem {
  const ReviewItem({required this.id, required this.cardId, required this.rating});

  factory ReviewItem.fromJson(Json j) =>
      ReviewItem(id: j['id'] as String, cardId: _int(j['cardId']), rating: Rating.parse(j['rating'] as String));

  final String id;
  final int cardId;
  final Rating rating;

  Json toJson() => {'id': id, 'cardId': cardId, 'rating': rating.json};
}

class ReviewResult {
  const ReviewResult({required this.id, required this.status, this.pointsAwarded, this.multiplier, this.code});

  factory ReviewResult.fromJson(Json j) => ReviewResult(
        id: j['id'] as String,
        status: j['status'] as String,
        pointsAwarded: j['pointsAwarded'] == null ? null : _int(j['pointsAwarded']),
        multiplier: j['multiplier'] == null ? null : _double(j['multiplier']),
        code: j['code'] as String?,
      );

  final String id;

  /// `applied`, `duplicate` or `rejected`.
  final String status;
  final int? pointsAwarded;
  final double? multiplier;
  final String? code;
}

/// `goalMet`, `milestone` (days, bonus) or `wishlistReached` (itemId, name, price).
class AppEvent {
  const AppEvent({required this.type, this.days, this.bonus, this.itemId, this.name, this.price});

  factory AppEvent.fromJson(Json j) => AppEvent(
        type: j['type'] as String,
        days: j['days'] == null ? null : _int(j['days']),
        bonus: j['bonus'] == null ? null : _int(j['bonus']),
        itemId: j['itemId'] == null ? null : _int(j['itemId']),
        name: j['name'] as String?,
        price: j['price'] == null ? null : _int(j['price']),
      );

  final String type;
  final int? days;
  final int? bonus;
  final int? itemId;
  final String? name;
  final int? price;
}

class ReviewBatchResult {
  const ReviewBatchResult({required this.results, required this.summary, required this.points, required this.events});

  factory ReviewBatchResult.fromJson(Json j) => ReviewBatchResult(
        results: [for (final r in j['results'] as List) ReviewResult.fromJson(r as Json)],
        summary: Summary.fromJson(j['summary'] as Json),
        points: PointsValue.fromJson(j['points'] as Json),
        events: [for (final e in j['events'] as List) AppEvent.fromJson(e as Json)],
      );

  final List<ReviewResult> results;
  final Summary summary;

  /// Values for the next answer.
  final PointsValue points;
  final List<AppEvent> events;
}

class UserSettings {
  const UserSettings({
    required this.dailyGoal,
    required this.newCardsPerDay,
    required this.notificationsEnabled,
    required this.morningTime,
    required this.eveningTime,
    required this.lastCallTime,
    required this.quietFrom,
    required this.quietTo,
    required this.smartTimes,
    this.fourRatings = false,
  });

  factory UserSettings.fromJson(Json j) => UserSettings(
        dailyGoal: _int(j['dailyGoal']),
        newCardsPerDay: _int(j['newCardsPerDay']),
        notificationsEnabled: j['notificationsEnabled'] as bool,
        morningTime: j['morningTime'] as String,
        eveningTime: j['eveningTime'] as String,
        lastCallTime: j['lastCallTime'] as String,
        quietFrom: j['quietFrom'] as String,
        quietTo: j['quietTo'] as String,
        smartTimes: j['smartTimes'] as bool,
        fourRatings: j['fourRatings'] as bool? ?? false,
      );

  static const minGoal = 1;
  static const maxGoal = 500;
  static const minNew = 0;
  static const maxNew = 100;

  final int dailyGoal;
  final int newCardsPerDay;
  final bool notificationsEnabled;
  final String morningTime;
  final String eveningTime;
  final String lastCallTime;
  final String quietFrom;
  final String quietTo;
  final bool smartTimes;

  /// "Těžké a Snadné": four answer buttons instead of Vím / Nevím (#19).
  final bool fourRatings;

  UserSettings copyWith({
    int? dailyGoal,
    int? newCardsPerDay,
    bool? notificationsEnabled,
    String? morningTime,
    String? eveningTime,
    String? lastCallTime,
    String? quietFrom,
    String? quietTo,
    bool? smartTimes,
    bool? fourRatings,
  }) =>
      UserSettings(
        dailyGoal: dailyGoal ?? this.dailyGoal,
        newCardsPerDay: newCardsPerDay ?? this.newCardsPerDay,
        notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
        morningTime: morningTime ?? this.morningTime,
        eveningTime: eveningTime ?? this.eveningTime,
        lastCallTime: lastCallTime ?? this.lastCallTime,
        quietFrom: quietFrom ?? this.quietFrom,
        quietTo: quietTo ?? this.quietTo,
        smartTimes: smartTimes ?? this.smartTimes,
        fourRatings: fourRatings ?? this.fourRatings,
      );

  Json toJson() => {
        'dailyGoal': dailyGoal,
        'newCardsPerDay': newCardsPerDay,
        'notificationsEnabled': notificationsEnabled,
        'morningTime': morningTime,
        'eveningTime': eveningTime,
        'lastCallTime': lastCallTime,
        'quietFrom': quietFrom,
        'quietTo': quietTo,
        'smartTimes': smartTimes,
        'fourRatings': fourRatings,
      };
}

class SettingsUpdate {
  const SettingsUpdate({required this.settings, required this.summary, required this.events});

  factory SettingsUpdate.fromJson(Json j) => SettingsUpdate(
        settings: UserSettings.fromJson(j['settings'] as Json),
        summary: Summary.fromJson(j['summary'] as Json),
        events: [for (final e in j['events'] as List) AppEvent.fromJson(e as Json)],
      );

  final UserSettings settings;
  final Summary summary;
  final List<AppEvent> events;
}

// Stats (api.md §7, spec §10)

int? _intOrNull(Object? v) => v == null ? null : _int(v);

DateTime _day(Object? v) => DateTime.parse(v! as String);

class StatsTiles {
  const StatsTiles({
    required this.streak,
    required this.bestStreak,
    required this.successRate30d,
    required this.sparkline,
    required this.totalReviews,
    required this.totalPointsEarned,
  });

  factory StatsTiles.fromJson(Json j) => StatsTiles(
        streak: _int(j['streak']),
        bestStreak: _int(j['bestStreak']),
        successRate30d: _intOrNull(j['successRate30d']),
        sparkline: [for (final v in j['sparkline'] as List) _intOrNull(v)],
        totalReviews: _int(j['totalReviews']),
        totalPointsEarned: _int(j['totalPointsEarned']),
      );

  final int streak;
  final int bestStreak;
  final int? successRate30d;

  /// 30 daily success rates, oldest first; null on days without reviews.
  final List<int?> sparkline;
  final int totalReviews;
  final int totalPointsEarned;
}

/// 17 weeks × 7 days, Monday first. Levels 0–4, null after today.
class Heatmap {
  const Heatmap({required this.from, required this.today, required this.weeks});

  factory Heatmap.fromJson(Json j) => Heatmap(
        from: _day(j['from']),
        today: _day(j['today']),
        weeks: [
          for (final w in j['weeks'] as List) [for (final v in w as List) _intOrNull(v)],
        ],
      );

  /// The Monday of the first week.
  final DateTime from;
  final DateTime today;
  final List<List<int?>> weeks;

  /// The day in [week] (0 = oldest) and [weekday] (0 = Monday).
  DateTime dayAt(int week, int weekday) => DateTime.utc(from.year, from.month, from.day + week * 7 + weekday);
}

class DayCount {
  const DayCount({required this.date, required this.graded});

  factory DayCount.fromJson(Json j) => DayCount(date: _day(j['date']), graded: _int(j['graded']));

  final DateTime date;
  final int graded;
}

class WeekdayStat {
  const WeekdayStat({required this.weekday, required this.successRate, required this.graded});

  factory WeekdayStat.fromJson(Json j) =>
      WeekdayStat(weekday: _int(j['weekday']), successRate: _intOrNull(j['successRate']), graded: _int(j['graded']));

  /// 1 = Monday … 7 = Sunday.
  final int weekday;

  /// Null below the minimum sample size.
  final int? successRate;
  final int graded;
}

class BestTime {
  const BestTime({required this.from, required this.to, required this.successRate, required this.graded});

  factory BestTime.fromJson(Json j) => BestTime(
        from: j['from'] as String,
        to: j['to'] as String,
        successRate: _int(j['successRate']),
        graded: _int(j['graded']),
      );

  /// `HH:mm`.
  final String from;
  final String to;
  final int successRate;
  final int graded;
}

/// Zvládnuto / Učím se / Nové card counts (spec §3.5).
class Progress {
  const Progress({required this.mastered, required this.learning, required this.fresh});

  factory Progress.fromJson(Json j) =>
      Progress(mastered: _int(j['mastered']), learning: _int(j['learning']), fresh: _int(j['new']));

  final int mastered;
  final int learning;
  final int fresh;

  int get total => mastered + learning + fresh;
}

class DeckProgress {
  const DeckProgress({required this.deckId, required this.name, required this.progress});

  factory DeckProgress.fromJson(Json j) =>
      DeckProgress(deckId: _int(j['deckId']), name: j['name'] as String, progress: Progress.fromJson(j));

  final int deckId;
  final String name;
  final Progress progress;
}

class Stats {
  const Stats({
    required this.deckId,
    required this.tiles,
    required this.heatmap,
    required this.goal,
    required this.daily,
    required this.weekdays,
    required this.bestTime,
    required this.deckProgress,
  });

  factory Stats.fromJson(Json j) {
    final daily = j['daily'] as Json;
    return Stats(
      deckId: _intOrNull(j['deckId']),
      tiles: StatsTiles.fromJson(j['tiles'] as Json),
      heatmap: Heatmap.fromJson(j['heatmap'] as Json),
      goal: _int(daily['goal']),
      daily: [for (final d in daily['days'] as List) DayCount.fromJson(d as Json)],
      weekdays: [for (final w in j['weekdays'] as List) WeekdayStat.fromJson(w as Json)],
      bestTime: j['bestTime'] == null ? null : BestTime.fromJson(j['bestTime'] as Json),
      deckProgress: [for (final d in j['deckProgress'] as List) DeckProgress.fromJson(d as Json)],
    );
  }

  final int? deckId;
  final StatsTiles tiles;
  final Heatmap heatmap;

  /// The current daily goal (the dashed line).
  final int goal;

  /// The last 14 days, oldest first.
  final List<DayCount> daily;
  final List<WeekdayStat> weekdays;
  final BestTime? bestTime;
  final List<DeckProgress> deckProgress;
}

// Shop (api.md §8)

class ShopItem {
  const ShopItem({
    required this.id,
    required this.name,
    required this.description,
    required this.price,
    required this.stock,
    required this.soldOut,
    required this.wishlisted,
    required this.missing,
  });

  factory ShopItem.fromJson(Json j) => ShopItem(
        id: _int(j['id']),
        name: j['name'] as String,
        description: j['description'] as String,
        price: _int(j['price']),
        stock: _int(j['stock']),
        soldOut: j['soldOut'] as bool,
        wishlisted: j['wishlisted'] as bool,
        missing: _int(j['missing']),
      );

  final int id;
  final String name;
  final String description;
  final int price;
  final int stock;
  final bool soldOut;
  final bool wishlisted;

  /// Points still missing: `max(0, price − balance)`.
  final int missing;

  bool get canBuy => !soldOut && missing == 0;

  ShopItem copyWith({bool? wishlisted}) => ShopItem(
        id: id,
        name: name,
        description: description,
        price: price,
        stock: stock,
        soldOut: soldOut,
        wishlisted: wishlisted ?? this.wishlisted,
        missing: missing,
      );
}

class Shop {
  const Shop({required this.balance, required this.items});

  factory Shop.fromJson(Json j) => Shop(
        balance: _int(j['balance']),
        items: [for (final i in j['items'] as List) ShopItem.fromJson(i as Json)],
      );

  final int balance;
  final List<ShopItem> items;

  Shop withItem(ShopItem item) => Shop(balance: balance, items: [for (final i in items) i.id == item.id ? item : i]);
}

enum ClaimStatus {
  pending('pending'),
  confirmed('confirmed'),
  rejected('rejected');

  const ClaimStatus(this.json);

  final String json;

  static ClaimStatus parse(String value) => values.firstWhere((s) => s.json == value, orElse: () => pending);
}

class Claim {
  const Claim({
    required this.id,
    required this.itemName,
    required this.price,
    required this.status,
    required this.createdAt,
    required this.decidedAt,
  });

  factory Claim.fromJson(Json j) => Claim(
        id: _int(j['id']),
        itemName: j['itemName'] as String,
        price: _int(j['price']),
        status: ClaimStatus.parse(j['status'] as String),
        createdAt: DateTime.parse(j['createdAt'] as String),
        decidedAt: j['decidedAt'] == null ? null : DateTime.parse(j['decidedAt'] as String),
      );

  final int id;
  final String itemName;
  final int price;
  final ClaimStatus status;
  final DateTime createdAt;
  final DateTime? decidedAt;
}

// Notification texts (api.md §9)

class NotificationText {
  const NotificationText({required this.id, required this.text});

  factory NotificationText.fromJson(Json j) => NotificationText(id: _int(j['id']), text: j['text'] as String);

  final int id;
  final String text;

  Json toJson() => {'id': id, 'text': text};
}

/// Active texts per category id (`morning`, `last_call`, …); [version] is the ETag.
class NotificationTexts {
  const NotificationTexts({required this.version, required this.categories});

  factory NotificationTexts.fromJson(Json j) => NotificationTexts(
        version: j['version'] as String,
        categories: {
          for (final MapEntry(:key, :value) in (j['categories'] as Json).entries)
            key: [for (final t in value as List) NotificationText.fromJson(t as Json)],
        },
      );

  final String version;
  final Map<String, List<NotificationText>> categories;

  Json toJson() => {
        'version': version,
        'categories': {
          for (final MapEntry(:key, :value) in categories.entries) key: [for (final t in value) t.toJson()],
        },
      };
}
