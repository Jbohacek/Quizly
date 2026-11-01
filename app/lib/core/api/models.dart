// DTOs of the REST API (docs/api.md). Hand-written fromJson/toJson, no codegen.

typedef Json = Map<String, dynamic>;

int _int(Object? v) => (v as num).toInt();
double _double(Object? v) => (v as num).toDouble();

class AppUser {
  const AppUser({required this.id, required this.username, required this.displayName});

  factory AppUser.fromJson(Json j) =>
      AppUser(id: _int(j['id']), username: j['username'] as String, displayName: j['displayName'] as String);

  final int id;
  final String username;
  final String displayName;

  Json toJson() => {'id': id, 'username': username, 'displayName': displayName};
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

/// Balance, streak, multiplier and today's progress (api.md §1.2).
class Summary {
  const Summary({
    required this.balance,
    required this.streak,
    required this.bestStreak,
    required this.multiplier,
    required this.nextMultiplier,
    required this.today,
  });

  factory Summary.fromJson(Json j) => Summary(
        balance: _int(j['balance']),
        streak: _int(j['streak']),
        bestStreak: _int(j['bestStreak']),
        multiplier: _double(j['multiplier']),
        nextMultiplier: j['nextMultiplier'] == null ? null : NextMultiplier.fromJson(j['nextMultiplier'] as Json),
        today: Today.fromJson(j['today'] as Json),
      );

  final int balance;
  final int streak;
  final int bestStreak;
  final double multiplier;
  final NextMultiplier? nextMultiplier;
  final Today today;
}

class Me {
  const Me({required this.user, required this.summary, required this.dueNow});

  factory Me.fromJson(Json j) => Me(
        user: AppUser.fromJson(j['user'] as Json),
        summary: Summary.fromJson(j['summary'] as Json),
        dueNow: _int(j['dueNow']),
      );

  final AppUser user;
  final Summary summary;

  /// Length of the "Učit se vše" queue: due cards + new cards left for today.
  final int dueNow;
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
  const PointsValue({required this.know, required this.dontKnow});

  factory PointsValue.fromJson(Json j) => PointsValue(know: _int(j['know']), dontKnow: _int(j['dontKnow']));

  final int know;
  final int dontKnow;

  int of(Rating rating) => rating == Rating.know ? know : dontKnow;
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
  });

  factory SessionCard.fromJson(Json j) => SessionCard(
        cardId: _int(j['cardId']),
        deckId: _int(j['deckId']),
        question: j['question'] as String,
        answer: j['answer'] as String,
        kind: CardKind.parse(j['kind'] as String),
      );

  final int cardId;
  final int deckId;
  final String question;
  final String answer;
  final CardKind kind;
}

class SessionData {
  const SessionData({required this.deckId, required this.multiplier, required this.points, required this.cards});

  factory SessionData.fromJson(Json j) => SessionData(
        deckId: j['deckId'] == null ? null : _int(j['deckId']),
        multiplier: _double(j['multiplier']),
        points: PointsValue.fromJson(j['points'] as Json),
        cards: [for (final c in j['cards'] as List) SessionCard.fromJson(c as Json)],
      );

  final int? deckId;
  final double multiplier;
  final PointsValue points;
  final List<SessionCard> cards;
}

enum Rating {
  know('know'),
  dontKnow('dontKnow');

  const Rating(this.json);

  final String json;

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

  UserSettings copyWith({int? dailyGoal, int? newCardsPerDay}) => UserSettings(
        dailyGoal: dailyGoal ?? this.dailyGoal,
        newCardsPerDay: newCardsPerDay ?? this.newCardsPerDay,
        notificationsEnabled: notificationsEnabled,
        morningTime: morningTime,
        eveningTime: eveningTime,
        lastCallTime: lastCallTime,
        quietFrom: quietFrom,
        quietTo: quietTo,
        smartTimes: smartTimes,
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
