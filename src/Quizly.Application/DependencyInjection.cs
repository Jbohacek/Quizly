using Microsoft.AspNetCore.Identity;
using Microsoft.Extensions.DependencyInjection;
using Quizly.Application.Auth;
using Quizly.Application.Decks;
using Quizly.Application.NotificationTexts;
using Quizly.Application.Shop;
using Quizly.Application.Users;
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
        return services;
    }
}
