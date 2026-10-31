using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Design;

namespace Quizly.Infrastructure.Persistence;

/// <summary>Used by <c>dotnet ef migrations add</c>; no database connection is needed for that.</summary>
internal sealed class DesignTimeDbContextFactory : IDesignTimeDbContextFactory<QuizlyDbContext>
{
    public QuizlyDbContext CreateDbContext(string[] args)
    {
        var options = new DbContextOptionsBuilder<QuizlyDbContext>();
        var connectionString = Environment.GetEnvironmentVariable("ConnectionStrings__Default")
            ?? "Host=localhost;Database=quizly;Username=quizly;Password=quizly";
        DependencyInjection.Configure(options, connectionString);
        return new QuizlyDbContext(options.Options);
    }
}
