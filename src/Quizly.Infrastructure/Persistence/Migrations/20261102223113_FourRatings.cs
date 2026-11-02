using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace Quizly.Infrastructure.Persistence.Migrations
{
    /// <inheritdoc />
    public partial class FourRatings : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropCheckConstraint(
                name: "ck_review_logs_rating",
                table: "review_logs");

            migrationBuilder.AddColumn<bool>(
                name: "four_ratings",
                table: "user_settings",
                type: "boolean",
                nullable: false,
                defaultValue: false);

            migrationBuilder.AddCheckConstraint(
                name: "ck_review_logs_rating",
                table: "review_logs",
                sql: "rating IN (1, 2, 3, 4)");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropCheckConstraint(
                name: "ck_review_logs_rating",
                table: "review_logs");

            migrationBuilder.DropColumn(
                name: "four_ratings",
                table: "user_settings");

            migrationBuilder.AddCheckConstraint(
                name: "ck_review_logs_rating",
                table: "review_logs",
                sql: "rating IN (1, 3)");
        }
    }
}
