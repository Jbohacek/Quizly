using Microsoft.AspNetCore.Identity;
using Microsoft.Extensions.DependencyInjection;
using Quizly.Application.Auth;
using Quizly.Application.Decks;
using Quizly.Application.Learning;
using Quizly.Application.Profile;
using Quizly.Application.NotificationTexts;
using Quizly.Application.Overview;
using Quizly.Application.Shop;
using Quizly.Application.Stats;
using Quizly.Application.Users;
using Quizly.Application.Yaml;
using Quizly.Domain;

namespace Quizly.Application;

public static class DependencyInjection
{
    public static IServiceCollection AddApplication(this IServiceCollection services)
    {
        services.AddSingleton(TimeProvider.System);
        services.AddSingleton<IPasswordHasher<User>, PasswordHasher<User>>();
        services.AddSingleton<IPasswordGenerator, PasswordGenerator>();
        services.AddSingleton<ILoginThrottle, LoginThrottle>();
        services.AddSingleton<IAdminAuthenticator, AdminAuthenticator>();

        services.AddScoped<IAuthService, AuthService>();
        services.AddScoped<IUserAdminService, UserAdminService>();
        services.AddScoped<IDeckService, DeckService>();
        services.AddScoped<ICardService, CardService>();
        services.AddScoped<IShopItemService, ShopItemService>();
        services.AddScoped<INotificationTextService, NotificationTextService>();

        services.AddScoped<Progress>();
        services.AddScoped<StudyService>();
        services.AddScoped<IStudyService>(sp => sp.GetRequiredService<StudyService>());
        services.AddScoped<IReviewService, ReviewService>();
        services.AddScoped<IMeService, MeService>();
        services.AddScoped<IShopService, ShopService>();
        services.AddScoped<IClaimAdminService, ClaimAdminService>();
        services.AddScoped<IStatsService, StatsService>();
        services.AddScoped<IYamlDeckService, YamlDeckService>();
        services.AddScoped<IOverviewService, OverviewService>();
        return services;
    }
}
