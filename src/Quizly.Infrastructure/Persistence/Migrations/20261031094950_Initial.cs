using System;
using Microsoft.EntityFrameworkCore.Migrations;
using Npgsql.EntityFrameworkCore.PostgreSQL.Metadata;

#nullable disable

namespace Quizly.Infrastructure.Persistence.Migrations
{
    /// <inheritdoc />
    public partial class Initial : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.CreateTable(
                name: "decks",
                columns: table => new
                {
                    id = table.Column<int>(type: "integer", nullable: false)
                        .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.IdentityByDefaultColumn),
                    name = table.Column<string>(type: "character varying(100)", maxLength: 100, nullable: false),
                    description = table.Column<string>(type: "character varying(500)", maxLength: 500, nullable: false),
                    color = table.Column<string>(type: "character(7)", fixedLength: true, maxLength: 7, nullable: false),
                    sort_order = table.Column<int>(type: "integer", nullable: false),
                    created_at = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                    updated_at = table.Column<DateTime>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_decks", x => x.id);
                    table.CheckConstraint("ck_decks_color", "color ~ '^#[0-9A-Fa-f]{6}$'");
                });

            migrationBuilder.CreateTable(
                name: "notification_texts",
                columns: table => new
                {
                    id = table.Column<int>(type: "integer", nullable: false)
                        .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.IdentityByDefaultColumn),
                    category = table.Column<string>(type: "character varying(16)", maxLength: 16, nullable: false),
                    text = table.Column<string>(type: "character varying(300)", maxLength: 300, nullable: false),
                    is_active = table.Column<bool>(type: "boolean", nullable: false),
                    created_at = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                    updated_at = table.Column<DateTime>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_notification_texts", x => x.id);
                });

            migrationBuilder.CreateTable(
                name: "shop_items",
                columns: table => new
                {
                    id = table.Column<int>(type: "integer", nullable: false)
                        .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.IdentityByDefaultColumn),
                    name = table.Column<string>(type: "character varying(100)", maxLength: 100, nullable: false),
                    description = table.Column<string>(type: "character varying(500)", maxLength: 500, nullable: false),
                    price = table.Column<int>(type: "integer", nullable: false),
                    initial_stock = table.Column<int>(type: "integer", nullable: false),
                    stock = table.Column<int>(type: "integer", nullable: false),
                    is_active = table.Column<bool>(type: "boolean", nullable: false),
                    sort_order = table.Column<int>(type: "integer", nullable: false),
                    created_at = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                    updated_at = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                    xmin = table.Column<uint>(type: "xid", rowVersion: true, nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_shop_items", x => x.id);
                    table.CheckConstraint("ck_shop_items_initial_stock", "initial_stock BETWEEN 0 AND 10000");
                    table.CheckConstraint("ck_shop_items_price", "price BETWEEN 1 AND 1000000");
                    table.CheckConstraint("ck_shop_items_stock", "stock >= 0");
                });

            migrationBuilder.CreateTable(
                name: "users",
                columns: table => new
                {
                    id = table.Column<int>(type: "integer", nullable: false)
                        .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.IdentityByDefaultColumn),
                    username = table.Column<string>(type: "character varying(32)", maxLength: 32, nullable: false),
                    display_name = table.Column<string>(type: "character varying(50)", maxLength: 50, nullable: false),
                    password_hash = table.Column<string>(type: "text", nullable: false),
                    is_active = table.Column<bool>(type: "boolean", nullable: false),
                    created_at = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                    last_active_at = table.Column<DateTime>(type: "timestamp with time zone", nullable: true),
                    current_streak = table.Column<int>(type: "integer", nullable: false),
                    best_streak = table.Column<int>(type: "integer", nullable: false),
                    last_goal_met_date = table.Column<DateOnly>(type: "date", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_users", x => x.id);
                    table.CheckConstraint("ck_users_username", "username ~ '^[a-z0-9]{3,32}$'");
                });

            migrationBuilder.CreateTable(
                name: "cards",
                columns: table => new
                {
                    id = table.Column<int>(type: "integer", nullable: false)
                        .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.IdentityByDefaultColumn),
                    deck_id = table.Column<int>(type: "integer", nullable: false),
                    question = table.Column<string>(type: "character varying(500)", maxLength: 500, nullable: false),
                    answer = table.Column<string>(type: "character varying(2000)", maxLength: 2000, nullable: false),
                    sort_order = table.Column<int>(type: "integer", nullable: false),
                    created_at = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                    updated_at = table.Column<DateTime>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_cards", x => x.id);
                    table.ForeignKey(
                        name: "fk_cards_decks_deck_id",
                        column: x => x.deck_id,
                        principalTable: "decks",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "claims",
                columns: table => new
                {
                    id = table.Column<int>(type: "integer", nullable: false)
                        .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.IdentityByDefaultColumn),
                    user_id = table.Column<int>(type: "integer", nullable: false),
                    shop_item_id = table.Column<int>(type: "integer", nullable: false),
                    request_id = table.Column<Guid>(type: "uuid", nullable: false),
                    price = table.Column<int>(type: "integer", nullable: false),
                    status = table.Column<string>(type: "character varying(16)", maxLength: 16, nullable: false),
                    created_at = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                    decided_at = table.Column<DateTime>(type: "timestamp with time zone", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_claims", x => x.id);
                    table.ForeignKey(
                        name: "fk_claims_shop_items_shop_item_id",
                        column: x => x.shop_item_id,
                        principalTable: "shop_items",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Restrict);
                    table.ForeignKey(
                        name: "fk_claims_users_user_id",
                        column: x => x.user_id,
                        principalTable: "users",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Restrict);
                });

            migrationBuilder.CreateTable(
                name: "daily_activities",
                columns: table => new
                {
                    user_id = table.Column<int>(type: "integer", nullable: false),
                    date = table.Column<DateOnly>(type: "date", nullable: false),
                    graded_count = table.Column<int>(type: "integer", nullable: false),
                    correct_count = table.Column<int>(type: "integer", nullable: false),
                    points = table.Column<int>(type: "integer", nullable: false),
                    goal = table.Column<int>(type: "integer", nullable: false),
                    goal_met = table.Column<bool>(type: "boolean", nullable: false),
                    goal_met_at = table.Column<DateTime>(type: "timestamp with time zone", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_daily_activities", x => new { x.user_id, x.date });
                    table.ForeignKey(
                        name: "fk_daily_activities_users_user_id",
                        column: x => x.user_id,
                        principalTable: "users",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "points_entries",
                columns: table => new
                {
                    id = table.Column<long>(type: "bigint", nullable: false)
                        .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.IdentityByDefaultColumn),
                    user_id = table.Column<int>(type: "integer", nullable: false),
                    amount = table.Column<int>(type: "integer", nullable: false),
                    reason = table.Column<string>(type: "character varying(16)", maxLength: 16, nullable: false),
                    reference_id = table.Column<string>(type: "character varying(64)", maxLength: 64, nullable: false),
                    created_at = table.Column<DateTime>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_points_entries", x => x.id);
                    table.CheckConstraint("ck_points_entries_amount", "amount <> 0");
                    table.ForeignKey(
                        name: "fk_points_entries_users_user_id",
                        column: x => x.user_id,
                        principalTable: "users",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "refresh_tokens",
                columns: table => new
                {
                    id = table.Column<int>(type: "integer", nullable: false)
                        .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.IdentityByDefaultColumn),
                    user_id = table.Column<int>(type: "integer", nullable: false),
                    token_hash = table.Column<byte[]>(type: "bytea", nullable: false),
                    created_at = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                    expires_at = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                    revoked_at = table.Column<DateTime>(type: "timestamp with time zone", nullable: true),
                    replaced_by_id = table.Column<int>(type: "integer", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_refresh_tokens", x => x.id);
                    table.ForeignKey(
                        name: "fk_refresh_tokens_refresh_tokens_replaced_by_id",
                        column: x => x.replaced_by_id,
                        principalTable: "refresh_tokens",
                        principalColumn: "id",
                        onDelete: ReferentialAction.SetNull);
                    table.ForeignKey(
                        name: "fk_refresh_tokens_users_user_id",
                        column: x => x.user_id,
                        principalTable: "users",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "user_settings",
                columns: table => new
                {
                    user_id = table.Column<int>(type: "integer", nullable: false),
                    daily_goal = table.Column<int>(type: "integer", nullable: false),
                    new_cards_per_day = table.Column<int>(type: "integer", nullable: false),
                    notifications_enabled = table.Column<bool>(type: "boolean", nullable: false),
                    morning_time = table.Column<TimeOnly>(type: "time without time zone", nullable: false),
                    evening_time = table.Column<TimeOnly>(type: "time without time zone", nullable: false),
                    last_call_time = table.Column<TimeOnly>(type: "time without time zone", nullable: false),
                    quiet_from = table.Column<TimeOnly>(type: "time without time zone", nullable: false),
                    quiet_to = table.Column<TimeOnly>(type: "time without time zone", nullable: false),
                    smart_times = table.Column<bool>(type: "boolean", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_user_settings", x => x.user_id);
                    table.CheckConstraint("ck_user_settings_daily_goal", "daily_goal BETWEEN 1 AND 500");
                    table.CheckConstraint("ck_user_settings_new_cards", "new_cards_per_day BETWEEN 0 AND 100");
                    table.CheckConstraint("ck_user_settings_quiet_hours", "quiet_from <> quiet_to");
                    table.ForeignKey(
                        name: "fk_user_settings_users_user_id",
                        column: x => x.user_id,
                        principalTable: "users",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "wishlist_entries",
                columns: table => new
                {
                    user_id = table.Column<int>(type: "integer", nullable: false),
                    shop_item_id = table.Column<int>(type: "integer", nullable: false),
                    created_at = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                    notified_at = table.Column<DateTime>(type: "timestamp with time zone", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_wishlist_entries", x => new { x.user_id, x.shop_item_id });
                    table.ForeignKey(
                        name: "fk_wishlist_entries_shop_items_shop_item_id",
                        column: x => x.shop_item_id,
                        principalTable: "shop_items",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                    table.ForeignKey(
                        name: "fk_wishlist_entries_users_user_id",
                        column: x => x.user_id,
                        principalTable: "users",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "card_states",
                columns: table => new
                {
                    user_id = table.Column<int>(type: "integer", nullable: false),
                    card_id = table.Column<int>(type: "integer", nullable: false),
                    state = table.Column<short>(type: "smallint", nullable: false),
                    step = table.Column<short>(type: "smallint", nullable: true),
                    stability = table.Column<double>(type: "double precision", nullable: false),
                    difficulty = table.Column<double>(type: "double precision", nullable: false),
                    due = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                    last_review = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                    first_review = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                    reps = table.Column<int>(type: "integer", nullable: false),
                    lapses = table.Column<int>(type: "integer", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_card_states", x => new { x.user_id, x.card_id });
                    table.CheckConstraint("ck_card_states_state", "state IN (1, 2, 3)");
                    table.ForeignKey(
                        name: "fk_card_states_cards_card_id",
                        column: x => x.card_id,
                        principalTable: "cards",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                    table.ForeignKey(
                        name: "fk_card_states_users_user_id",
                        column: x => x.user_id,
                        principalTable: "users",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "review_logs",
                columns: table => new
                {
                    id = table.Column<Guid>(type: "uuid", nullable: false),
                    user_id = table.Column<int>(type: "integer", nullable: false),
                    card_id = table.Column<int>(type: "integer", nullable: false),
                    rating = table.Column<short>(type: "smallint", nullable: false),
                    state_before = table.Column<short>(type: "smallint", nullable: true),
                    reviewed_at = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                    day = table.Column<DateOnly>(type: "date", nullable: false),
                    multiplier = table.Column<decimal>(type: "numeric(3,1)", precision: 3, scale: 1, nullable: false),
                    points_awarded = table.Column<int>(type: "integer", nullable: false),
                    elapsed_days = table.Column<int>(type: "integer", nullable: false),
                    scheduled_days = table.Column<int>(type: "integer", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_review_logs", x => x.id);
                    table.CheckConstraint("ck_review_logs_rating", "rating IN (1, 3)");
                    table.ForeignKey(
                        name: "fk_review_logs_cards_card_id",
                        column: x => x.card_id,
                        principalTable: "cards",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                    table.ForeignKey(
                        name: "fk_review_logs_users_user_id",
                        column: x => x.user_id,
                        principalTable: "users",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateIndex(
                name: "ix_card_states_card_id",
                table: "card_states",
                column: "card_id");

            migrationBuilder.CreateIndex(
                name: "ix_card_states_user_id_due",
                table: "card_states",
                columns: new[] { "user_id", "due" });

            migrationBuilder.CreateIndex(
                name: "ix_card_states_user_id_first_review",
                table: "card_states",
                columns: new[] { "user_id", "first_review" });

            migrationBuilder.CreateIndex(
                name: "ix_cards_deck_id_sort_order_id",
                table: "cards",
                columns: new[] { "deck_id", "sort_order", "id" });

            migrationBuilder.CreateIndex(
                name: "ix_claims_request_id",
                table: "claims",
                column: "request_id",
                unique: true);

            migrationBuilder.CreateIndex(
                name: "ix_claims_shop_item_id",
                table: "claims",
                column: "shop_item_id");

            migrationBuilder.CreateIndex(
                name: "ix_claims_status_created_at",
                table: "claims",
                columns: new[] { "status", "created_at" });

            migrationBuilder.CreateIndex(
                name: "ix_claims_user_id_created_at",
                table: "claims",
                columns: new[] { "user_id", "created_at" });

            migrationBuilder.CreateIndex(
                name: "ix_decks_sort_order_id",
                table: "decks",
                columns: new[] { "sort_order", "id" });

            migrationBuilder.CreateIndex(
                name: "ix_notification_texts_category",
                table: "notification_texts",
                column: "category");

            migrationBuilder.CreateIndex(
                name: "ix_points_entries_user_id_reason_reference_id",
                table: "points_entries",
                columns: new[] { "user_id", "reason", "reference_id" },
                unique: true);

            migrationBuilder.CreateIndex(
                name: "ix_refresh_tokens_replaced_by_id",
                table: "refresh_tokens",
                column: "replaced_by_id");

            migrationBuilder.CreateIndex(
                name: "ix_refresh_tokens_token_hash",
                table: "refresh_tokens",
                column: "token_hash",
                unique: true);

            migrationBuilder.CreateIndex(
                name: "ix_refresh_tokens_user_id",
                table: "refresh_tokens",
                column: "user_id");

            migrationBuilder.CreateIndex(
                name: "ix_review_logs_card_id",
                table: "review_logs",
                column: "card_id");

            migrationBuilder.CreateIndex(
                name: "ix_review_logs_user_id_day",
                table: "review_logs",
                columns: new[] { "user_id", "day" });

            migrationBuilder.CreateIndex(
                name: "ix_review_logs_user_id_reviewed_at",
                table: "review_logs",
                columns: new[] { "user_id", "reviewed_at" });

            migrationBuilder.CreateIndex(
                name: "ix_shop_items_sort_order_id",
                table: "shop_items",
                columns: new[] { "sort_order", "id" });

            migrationBuilder.CreateIndex(
                name: "ix_users_username",
                table: "users",
                column: "username",
                unique: true);

            migrationBuilder.CreateIndex(
                name: "ix_wishlist_entries_shop_item_id",
                table: "wishlist_entries",
                column: "shop_item_id");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "card_states");

            migrationBuilder.DropTable(
                name: "claims");

            migrationBuilder.DropTable(
                name: "daily_activities");

            migrationBuilder.DropTable(
                name: "notification_texts");

            migrationBuilder.DropTable(
                name: "points_entries");

            migrationBuilder.DropTable(
                name: "refresh_tokens");

            migrationBuilder.DropTable(
                name: "review_logs");

            migrationBuilder.DropTable(
                name: "user_settings");

            migrationBuilder.DropTable(
                name: "wishlist_entries");

            migrationBuilder.DropTable(
                name: "cards");

            migrationBuilder.DropTable(
                name: "shop_items");

            migrationBuilder.DropTable(
                name: "users");

            migrationBuilder.DropTable(
                name: "decks");
        }
    }
}
