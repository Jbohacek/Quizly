using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace Quizly.Infrastructure.Persistence.Migrations
{
    /// <inheritdoc />
    public partial class LeaderboardOptOut : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<bool>(
                name: "show_in_leaderboard",
                table: "user_settings",
                type: "boolean",
                nullable: false,
                // Everyone stays in Žebříček until they hide themselves in Nastavení.
                defaultValue: true);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropColumn(
                name: "show_in_leaderboard",
                table: "user_settings");
        }
    }
}
