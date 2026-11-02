using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace Quizly.Infrastructure.Persistence.Migrations
{
    /// <inheritdoc />
    public partial class DeckAccess : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<bool>(
                name: "for_everyone",
                table: "decks",
                type: "boolean",
                nullable: false,
                // Existing decks stay visible to everyone.
                defaultValue: true);

            migrationBuilder.CreateTable(
                name: "deck_access",
                columns: table => new
                {
                    deck_id = table.Column<int>(type: "integer", nullable: false),
                    user_id = table.Column<int>(type: "integer", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_deck_access", x => new { x.deck_id, x.user_id });
                    table.ForeignKey(
                        name: "fk_deck_access_decks_deck_id",
                        column: x => x.deck_id,
                        principalTable: "decks",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                    table.ForeignKey(
                        name: "fk_deck_access_users_user_id",
                        column: x => x.user_id,
                        principalTable: "users",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateIndex(
                name: "ix_deck_access_user_id",
                table: "deck_access",
                column: "user_id");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "deck_access");

            migrationBuilder.DropColumn(
                name: "for_everyone",
                table: "decks");
        }
    }
}
