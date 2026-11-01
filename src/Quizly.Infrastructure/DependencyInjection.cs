using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Quizly.Application.Abstractions;
using Quizly.Infrastructure.Persistence;

namespace Quizly.Infrastructure;

public static class DependencyInjection
{
    public static IServiceCollection AddInfrastructure(this IServiceCollection services, IConfiguration configuration)
    {
        var connectionString = configuration.GetConnectionString("Default")
            ?? throw new InvalidOperationException("ConnectionStrings__Default must be set.");

        services.AddDbContext<QuizlyDbContext>(options => Configure(options, connectionString));
        services.AddScoped<IAppDbContext>(sp => sp.GetRequiredService<QuizlyDbContext>());
        services.AddScoped<DatabaseInitializer>();
        return services;
    }

    internal static void Configure(DbContextOptionsBuilder options, string connectionString)
    {
        // Password auth only; without this Npgsql probes GSS encryption and logs a missing libgssapi in the slim image.
        var builder = new Npgsql.NpgsqlConnectionStringBuilder(connectionString) { GssEncryptionMode = Npgsql.GssEncryptionMode.Disable };
        options.UseNpgsql(builder.ConnectionString).UseSnakeCaseNamingConvention();
    }
}
