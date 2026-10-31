using Testcontainers.PostgreSql;

[assembly: AssemblyFixture(typeof(Quizly.Tests.Infrastructure.PostgresContainer))]

namespace Quizly.Tests.Infrastructure;

/// <summary>One PostgreSQL 18 container for the whole test run; every test class gets its own database.</summary>
public sealed class PostgresContainer : IAsyncLifetime
{
    private readonly PostgreSqlContainer _container = new PostgreSqlBuilder("postgres:18").Build();

    public string ConnectionString(string database) =>
        new Npgsql.NpgsqlConnectionStringBuilder(_container.GetConnectionString()) { Database = database }.ConnectionString;

    public ValueTask InitializeAsync() => new(_container.StartAsync());

    public ValueTask DisposeAsync() => _container.DisposeAsync();
}
