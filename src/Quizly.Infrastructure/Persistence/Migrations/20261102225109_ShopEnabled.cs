using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace Quizly.Infrastructure.Persistence.Migrations
{
    /// <inheritdoc />
    public partial class ShopEnabled : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<bool>(
                name: "shop_enabled",
                table: "users",
                type: "boolean",
                nullable: false,
                // Everyone keeps the shop until the admin turns it off.
                defaultValue: true);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropColumn(
                name: "shop_enabled",
                table: "users");
        }
    }
}
