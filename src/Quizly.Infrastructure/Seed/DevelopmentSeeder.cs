using System.Globalization;
using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging;
using Quizly.Domain;
using Quizly.Domain.Gamification;
using Quizly.Domain.Scheduling;
using Quizly.Infrastructure.Persistence;

namespace Quizly.Infrastructure.Seed;

/// <summary>
/// Development data (#44): a few users with believable history, decks, a shop and claims, so the app and
/// the dashboard have something to show without typing it in. Runs only on an empty database in
/// Development (see <see cref="DatabaseInitializer"/>).
/// <para>
/// The history is replayed with the real rules (FSRS, points, streak, milestones), not inserted as
/// made-up numbers, so every screen and every total stays consistent. The random choices use a fixed
/// seed: the same users always get the same story, shifted to today.
/// </para>
/// </summary>
public sealed class DevelopmentSeeder(
    QuizlyDbContext db, TimeProvider time, IPasswordHasher<User> hasher, ILogger<DevelopmentSeeder> logger)
{
    /// <summary>The password of every seeded app user. Development only; shorter than the 8-character minimum on purpose, since nothing validates it here.</summary>
    public const string Password = "123";

    /// <summary>Only Anna sees this deck (the deck access rule).</summary>
    public const string RestrictedDeckName = DemoDecks.RestrictedDeckName;

    /// <summary>An archived deck nobody sees.</summary>
    public const string ArchivedDeckName = DemoDecks.ArchivedDeckName;

    private const int RandomSeed = 44;

    /// <summary>One seeded user and the story of their last weeks.</summary>
    private sealed record Plan(
        string Username,
        string DisplayName,
        int DailyGoal,
        int NewCardsPerDay,
        Func<int, Random, int> AnswersOn,
        bool IsActive = true,
        bool ShopEnabled = true,
        bool ShowInLeaderboard = true,
        bool FourRatings = false,
        bool CanSeeRestrictedDeck = false);

    // AnswersOn(daysAgo, rng) = how many answers the user gave that study day (0 = did not study).
    private static readonly Plan[] Plans =
    [
        // A streak of 16 days (multiplier 1,2×), two earlier runs, today half way to the goal.
        new("anna", "Anna Nováková", 20, 5, (d, r) => d switch
        {
            0 => 12,
            17 or 22 or 29 => 0,
            <= 40 => 20 + r.Next(0, 8),
            _ => 0,
        }, CanSeeRestrictedDeck: true),
        // A streak of 10 days that broke 4 days ago, "Těžké a Snadné" on.
        new("petr", "Petr Svoboda", 10, 3, (d, r) => d is >= 5 and <= 14 ? 10 + r.Next(0, 4) : 0, FourRatings: true),
        // A 3-day streak with today's goal met; no shop, not in Žebříček.
        new("eva", "Eva Dvořáková", 15, 10, (d, r) => d switch
        {
            0 => 15,
            <= 2 => 15 + r.Next(0, 3),
            _ => 0,
        }, ShopEnabled: false, ShowInLeaderboard: false),
        // Brand new: no history, for the first-run screens and onboarding.
        new("novacek", "Nováček", 20, 5, (_, _) => 0),
        // Deactivated: cannot log in.
        new("stary", "Bývalý uživatel", 10, 5, (d, _) => d is >= 22 and <= 25 ? 10 : 0, IsActive: false),
    ];

    /// <summary>Seeds the data. Returns false (and changes nothing) when the database already has users or decks.</summary>
    public async Task<bool> SeedAsync(CancellationToken ct = default)
    {
        if (await db.Users.AnyAsync(ct) || await db.Decks.AnyAsync(ct))
        {
            return false;
        }

        var now = time.GetUtcNow().UtcDateTime;
        var today = PragueCalendar.DayOf(now);
        await using var transaction = await db.Database.BeginTransactionAsync(ct);

        var users = CreateUsers(now);
        db.Users.AddRange(users.Values);
        await db.SaveChangesAsync(ct);

        var decks = CreateDecks(now, users["anna"].Id);
        db.Decks.AddRange(decks);
        var shop = CreateShopItems(now);
        db.ShopItems.AddRange(shop.Values);
        await db.SaveChangesAsync(ct);

        var balances = new Dictionary<string, int>();
        for (var index = 0; index < Plans.Length; index++)
        {
            var plan = Plans[index];
            var user = users[plan.Username];
            var visible = decks
                .Where(d => d.ArchivedAt is null && (d.ForEveryone || (plan.CanSeeRestrictedDeck && d.Access.Count > 0)))
                .OrderBy(d => d.SortOrder)
                .SelectMany(d => d.Cards.OrderBy(c => c.SortOrder))
                .ToList();
            balances[plan.Username] = SimulateHistory(plan, user, visible, today, now, new Random(RandomSeed + index));
            await db.SaveChangesAsync(ct);
        }

        await AddClaimsAndWishlistAsync(users, shop, balances, now, ct);
        await transaction.CommitAsync(ct);

        logger.LogInformation(
            "Seeded development data: users {Users} (password {Password}), {Decks} decks, {Items} shop items",
            string.Join(", ", Plans.Select(p => p.Username)), Password, decks.Count, shop.Count);
        return true;
    }

    private Dictionary<string, User> CreateUsers(DateTime now)
    {
        var users = new Dictionary<string, User>();
        foreach (var plan in Plans)
        {
            var user = new User
            {
                Username = plan.Username,
                DisplayName = plan.DisplayName,
                IsActive = plan.IsActive,
                ShopEnabled = plan.ShopEnabled,
                CreatedAt = plan.Username == "novacek" ? now.AddHours(-1) : now.AddDays(-45),
                Settings = new UserSettings
                {
                    DailyGoal = plan.DailyGoal,
                    NewCardsPerDay = plan.NewCardsPerDay,
                    FourRatings = plan.FourRatings,
                    ShowInLeaderboard = plan.ShowInLeaderboard,
                },
            };
            user.PasswordHash = hasher.HashPassword(user, Password);
            users[plan.Username] = user;
        }

        return users;
    }

    private static List<Deck> CreateDecks(DateTime now, int annaId)
    {
        var tags = new Dictionary<string, Tag>();
        Tag TagNamed(string name) => tags.TryGetValue(name, out var tag) ? tag : tags[name] = new Tag { Name = name };

        return DemoDecks.All.Select((d, deckIndex) => new Deck
        {
            Name = d.Name,
            Description = d.Description,
            Color = d.Color,
            SortOrder = deckIndex,
            ForEveryone = d.ForEveryone,
            ArchivedAt = d.Archived ? now.AddDays(-10) : null,
            CreatedAt = now.AddDays(-45),
            UpdatedAt = now.AddDays(-45),
            Access = d.ForEveryone ? [] : [new DeckAccess { UserId = annaId }],
            Cards = d.Cards.Select((c, cardIndex) => new Card
            {
                Question = c.Question,
                Answer = c.Answer,
                SortOrder = cardIndex,
                CreatedAt = now.AddDays(-45),
                UpdatedAt = now.AddDays(-45),
                Tags = c.Tags.Split(' ', StringSplitOptions.RemoveEmptyEntries).Select(TagNamed).ToList(),
            }).ToList(),
        }).ToList();
    }

    private static Dictionary<string, ShopItem> CreateShopItems(DateTime now)
    {
        (string Key, string Name, string Description, int Price, int Stock, bool Active)[] items =
        [
            ("seriál", "Hodina seriálu bez výčitek", "Jedna epizoda, žádné „jen ještě chvilku učení“.", 150, 10, true),
            ("oběd", "Dobrý oběd", "Oběd v restauraci podle výběru.", 300, 5, true),
            ("pizza", "Jít na pizzu", "Pizza pro dva, platí správce.", 600, 3, true),
            ("kino", "Výlet do kina", "Lístek na film podle výběru.", 900, 1, true),
            ("úklid", "Den bez úklidu", "Jeden den bez domácích povinností.", 2500, 1, true),
            ("skrytá", "Skrytá odměna", "Neaktivní: v aplikaci se nezobrazí.", 100, 1, false),
        ];
        return items.Select((i, index) => (i.Key, Item: new ShopItem
        {
            Name = i.Name,
            Description = i.Description,
            Price = i.Price,
            InitialStock = i.Stock,
            Stock = i.Stock,
            IsActive = i.Active,
            SortOrder = index,
            CreatedAt = now.AddDays(-45),
            UpdatedAt = now.AddDays(-45),
        })).ToDictionary(x => x.Key, x => x.Item);
    }

    /// <summary>
    /// Replays the user's days from the oldest to today the way <c>ReviewService</c> would have handled them.
    /// Returns the points balance.
    /// </summary>
    private int SimulateHistory(Plan plan, User user, List<Card> visible, DateOnly today, DateTime now, Random rng)
    {
        var states = new Dictionary<int, CardState>();
        var balance = 0;
        for (var daysAgo = 40; daysAgo >= 0; daysAgo--)
        {
            var count = plan.AnswersOn(daysAgo, rng);
            var day = today.AddDays(-daysAgo);
            var schedule = count > 0 ? Schedule(day, daysAgo == 0, count, now, rng) : null;
            if (schedule is null)
            {
                continue;
            }

            var (start, step) = schedule.Value;

            var activity = new DailyActivity { UserId = user.Id, Date = day, Goal = plan.DailyGoal };
            db.DailyActivities.Add(activity);
            var queue = Queue(visible, states, start, plan.NewCardsPerDay).Take(count).ToList();
            for (var i = 0; i < queue.Count; i++)
            {
                var at = start + (step * i);
                var rating = PickRating(plan.FourRatings, rng);
                var multiplier = Points.Multiplier(Streaks.Displayed(user.CurrentStreak, user.LastGoalMetDate, day));
                var points = Points.For(rating, multiplier);
                var stateBefore = ApplyFsrs(states, user.Id, queue[i], rating, at, out var elapsedDays, out var scheduledDays);

                var id = Guid.NewGuid();
                db.ReviewLogs.Add(new ReviewLog
                {
                    Id = id,
                    UserId = user.Id,
                    CardId = queue[i].Id,
                    Rating = rating,
                    StateBefore = stateBefore,
                    ReviewedAt = at,
                    Day = day,
                    Multiplier = multiplier,
                    PointsAwarded = points,
                    ElapsedDays = elapsedDays,
                    ScheduledDays = scheduledDays,
                });
                db.PointsEntries.Add(new PointsEntry
                {
                    UserId = user.Id,
                    Amount = points,
                    Reason = PointsReason.Review,
                    ReferenceId = id.ToString(),
                    CreatedAt = at,
                });
                balance += points;

                activity.GradedCount++;
                activity.CorrectCount += rating == Rating.Again ? 0 : 1;
                activity.Points += points;
                user.LastActiveAt = at;
                if (!activity.GoalMet && activity.GradedCount >= activity.Goal)
                {
                    activity.GoalMet = true;
                    activity.GoalMetAt = at;
                    var streak = Streaks.MarkDayMet(user, day);
                    if (Milestones.BonusFor(streak) is int bonus)
                    {
                        db.PointsEntries.Add(new PointsEntry
                        {
                            UserId = user.Id,
                            Amount = bonus,
                            Reason = PointsReason.Milestone,
                            ReferenceId = Milestones.ReferenceId(streak, day),
                            CreatedAt = at,
                        });
                        activity.Points += bonus;
                        balance += bonus;
                    }
                }
            }
        }

        return balance;
    }

    /// <summary>
    /// When the day's session starts and how far apart the answers are. A past day gets a session
    /// somewhere between 08:00 and 19:00; today's session ends just before now.
    /// </summary>
    private static (DateTime Start, TimeSpan Step)? Schedule(DateOnly day, bool isToday, int count, DateTime now, Random rng)
    {
        var dayStart = PragueCalendar.StartOfDayUtc(day);
        if (!isToday)
        {
            return (dayStart + TimeSpan.FromHours(5) + TimeSpan.FromMinutes(rng.Next(0, 11 * 60)), TimeSpan.FromSeconds(rng.Next(15, 45)));
        }

        var available = now - dayStart - TimeSpan.FromSeconds(30);
        if (available < TimeSpan.FromSeconds(30))
        {
            return null; // The study day has only just started.
        }

        var step = TimeSpan.FromSeconds(Math.Min(30, available.TotalSeconds / (count + 1)));
        return (now - TimeSpan.FromSeconds(15) - (step * count), step);
    }

    /// <summary>
    /// What the user studies: cards due by then (most overdue first), today's new cards, then cards they
    /// know already, then the rest of the unseen ones, so a goal can always be reached.
    /// </summary>
    private static IEnumerable<Card> Queue(List<Card> visible, Dictionary<int, CardState> states, DateTime at, int newPerDay)
    {
        var due = visible.Where(c => states.TryGetValue(c.Id, out var s) && s.Due <= at).OrderBy(c => states[c.Id].Due);
        var unseen = visible.Where(c => !states.ContainsKey(c.Id)).ToList();
        var extra = visible.Where(c => states.TryGetValue(c.Id, out var s) && s.Due > at).OrderBy(c => states[c.Id].LastReview);
        return due.Concat(unseen.Take(newPerDay)).Concat(extra).Concat(unseen.Skip(newPerDay));
    }

    private static Rating PickRating(bool fourRatings, Random rng)
    {
        var roll = rng.NextDouble();
        if (fourRatings)
        {
            return roll switch { < 0.12 => Rating.Again, < 0.20 => Rating.Hard, < 0.85 => Rating.Good, _ => Rating.Easy };
        }

        return roll < 0.15 ? Rating.Again : Rating.Good;
    }

    /// <summary>The same FSRS step as <c>ReviewService</c>. Returns the state before the answer.</summary>
    private FsrsState? ApplyFsrs(
        Dictionary<int, CardState> states, int userId, Card card, Rating rating, DateTime at,
        out int elapsedDays, out int scheduledDays)
    {
        var fsrsRating = (FsrsRating)(int)rating;
        if (!states.TryGetValue(card.Id, out var state))
        {
            var created = FsrsScheduler.Default.Review(FsrsCard.New(at), fsrsRating, at);
            state = new CardState { UserId = userId, CardId = card.Id, FirstReview = at, Reps = 1 };
            Copy(created, state);
            states[card.Id] = state;
            db.CardStates.Add(state);
            elapsedDays = 0;
            scheduledDays = FsrsScheduler.ScheduledDays(created, at);
            return null;
        }

        var before = new FsrsCard(state.State, state.Step, state.Stability, state.Difficulty, state.Due, state.LastReview);
        var after = FsrsScheduler.Default.Review(before, fsrsRating, at);
        var stateBefore = state.State;
        Copy(after, state);
        state.Reps++;
        state.Lapses += stateBefore == FsrsState.Review && rating == Rating.Again ? 1 : 0;
        elapsedDays = FsrsScheduler.ElapsedDays(before, at);
        scheduledDays = FsrsScheduler.ScheduledDays(after, at);
        return stateBefore;
    }

    private static void Copy(FsrsCard card, CardState state)
    {
        state.State = card.State;
        state.Step = (short?)card.Step;
        state.Stability = card.Stability!.Value;
        state.Difficulty = card.Difficulty!.Value;
        state.Due = card.Due;
        state.LastReview = card.LastReview!.Value;
    }

    /// <summary>Purchases in every state, and hearted rewards, using the points the users have earned.</summary>
    private async Task AddClaimsAndWishlistAsync(
        Dictionary<string, User> users, Dictionary<string, ShopItem> shop, Dictionary<string, int> balances,
        DateTime now, CancellationToken ct)
    {
        async Task ClaimAsync(string username, string itemKey, ClaimStatus status, TimeSpan ago)
        {
            var (user, item) = (users[username], shop[itemKey]);
            if (balances[username] < item.Price)
            {
                return; // Cannot afford it with the seeded history; skip rather than go negative.
            }

            var createdAt = now - ago;
            var claim = new Claim
            {
                UserId = user.Id,
                ShopItemId = item.Id,
                RequestId = Guid.NewGuid(),
                Price = item.Price,
                Status = status,
                CreatedAt = createdAt,
                DecidedAt = status == ClaimStatus.Pending ? null : createdAt.AddHours(5),
            };
            db.Claims.Add(claim);
            await db.SaveChangesAsync(ct);

            var reference = claim.Id.ToString(CultureInfo.InvariantCulture);
            db.PointsEntries.Add(new PointsEntry
            {
                UserId = user.Id, Amount = -item.Price, Reason = PointsReason.Claim, ReferenceId = reference, CreatedAt = createdAt,
            });
            if (status == ClaimStatus.Rejected)
            {
                db.PointsEntries.Add(new PointsEntry
                {
                    UserId = user.Id, Amount = item.Price, Reason = PointsReason.Refund, ReferenceId = reference, CreatedAt = claim.DecidedAt!.Value,
                });
            }
            else
            {
                balances[username] -= item.Price;
                item.Stock--; // A rejected claim gives the stock back, so it nets to zero.
            }
        }

        await ClaimAsync("anna", "seriál", ClaimStatus.Confirmed, TimeSpan.FromDays(12));
        await ClaimAsync("anna", "úklid", ClaimStatus.Confirmed, TimeSpan.FromDays(6));
        await ClaimAsync("anna", "pizza", ClaimStatus.Pending, TimeSpan.FromDays(1));
        await ClaimAsync("petr", "seriál", ClaimStatus.Rejected, TimeSpan.FromDays(3));

        // Hearted rewards: Anna can afford the cinema (and has been told), the lunch is further away.
        void Heart(string username, string itemKey)
        {
            var (user, item) = (users[username], shop[itemKey]);
            db.WishlistEntries.Add(new WishlistEntry
            {
                UserId = user.Id,
                ShopItemId = item.Id,
                CreatedAt = now.AddDays(-5),
                NotifiedAt = balances[username] >= item.Price ? now.AddDays(-4) : null,
            });
        }

        Heart("anna", "kino");
        Heart("anna", "oběd");
        Heart("petr", "seriál");
        Heart("petr", "pizza");
        await db.SaveChangesAsync(ct);
    }
}
