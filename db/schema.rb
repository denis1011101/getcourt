# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.0].define(version: 2026_02_09_165303) do
  create_table "cities", force: :cascade do |t|
    t.integer "geoname_id"
    t.string "name"
    t.string "asciiname"
    t.string "country_code"
    t.decimal "latitude", precision: 10, scale: 6
    t.decimal "longitude", precision: 10, scale: 6
    t.integer "population"
    t.string "timezone"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["country_code"], name: "index_cities_on_country_code"
    t.index ["geoname_id"], name: "index_cities_on_geoname_id", unique: true
    t.index ["name"], name: "index_cities_on_name"
    t.index ["timezone"], name: "index_cities_on_timezone"
  end

  create_table "courts", force: :cascade do |t|
    t.string "name"
    t.string "coordinates"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id"
    t.string "contact_type"
    t.string "contact_value"
    t.string "moderation_status", default: "pending", null: false
    t.datetime "approved_at"
    t.index ["moderation_status"], name: "index_courts_on_moderation_status"
    t.index ["user_id"], name: "index_courts_on_user_id"
  end

  create_table "games", force: :cascade do |t|
    t.date "date"
    t.time "time"
    t.integer "court_id", null: false
    t.integer "user_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "recurring", default: false, null: false
    t.integer "occurrences_per_week", default: 1, null: false
    t.time "time2"
    t.text "times", default: "[]", null: false
    t.boolean "with_coach", default: false, null: false
    t.date "last_participations_reset_at"
    t.integer "players_count", default: 4, null: false
    t.string "sport"
    t.string "skill_level"
    t.boolean "prebooking_enabled", default: false, null: false
    t.string "post_game_stats_reminder_job_id"
    t.integer "tournament_id"
    t.index ["court_id"], name: "index_games_on_court_id"
    t.index ["prebooking_enabled"], name: "index_games_on_prebooking_enabled"
    t.index ["recurring"], name: "index_games_on_recurring"
    t.index ["tournament_id"], name: "index_games_on_tournament_id"
    t.index ["user_id"], name: "index_games_on_user_id"
    t.index ["with_coach"], name: "index_games_on_with_coach"
  end

  create_table "matches", force: :cascade do |t|
    t.integer "user_id", null: false
    t.integer "opponent_id"
    t.integer "game_id"
    t.string "mode", null: false
    t.string "outcome", null: false
    t.string "surface"
    t.string "score"
    t.datetime "played_at", null: false
    t.json "stats", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["game_id"], name: "index_matches_on_game_id"
    t.index ["opponent_id"], name: "index_matches_on_opponent_id"
    t.index ["user_id", "mode", "played_at"], name: "index_matches_on_user_id_and_mode_and_played_at"
    t.index ["user_id", "played_at"], name: "index_matches_on_user_id_and_played_at"
    t.index ["user_id"], name: "index_matches_on_user_id"
  end

  create_table "participations", force: :cascade do |t|
    t.integer "user_id", null: false
    t.integer "game_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "status", default: "approved", null: false
    t.datetime "approved_at"
    t.index ["game_id"], name: "index_participations_on_game_id"
    t.index ["user_id", "game_id"], name: "index_participations_on_user_and_game", unique: true
    t.index ["user_id"], name: "index_participations_on_user_id"
  end

  create_table "player_statistic_entries", force: :cascade do |t|
    t.integer "user_id", null: false
    t.integer "game_id", null: false
    t.integer "actor_id", null: false
    t.string "source", default: "telegram", null: false
    t.json "data", default: {}, null: false
    t.datetime "recorded_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["actor_id"], name: "index_player_statistic_entries_on_actor_id"
    t.index ["game_id"], name: "index_player_statistic_entries_on_game_id"
    t.index ["user_id", "game_id", "source"], name: "index_ps_entries_on_user_game_source", unique: true
    t.index ["user_id"], name: "index_player_statistic_entries_on_user_id"
  end

  create_table "player_statistics", force: :cascade do |t|
    t.integer "user_id", null: false
    t.float "singles_hours"
    t.float "doubles_hours"
    t.integer "singles_sessions"
    t.integer "doubles_sessions"
    t.integer "singles_games"
    t.integer "doubles_games"
    t.integer "singles_wins"
    t.integer "singles_losses"
    t.integer "doubles_wins"
    t.integer "doubles_losses"
    t.integer "aces"
    t.integer "double_faults"
    t.float "first_serve_percent"
    t.float "singles_rating"
    t.float "doubles_rating"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "individual_training"
    t.integer "group_training"
    t.integer "break_points_saved"
    t.integer "break_points_converted"
    t.integer "winners"
    t.integer "unforced_errors"
    t.integer "net_points_won"
    t.integer "service_points_won"
    t.integer "return_points_won"
    t.integer "return_games_won"
    t.integer "games_won_total"
    t.index ["user_id"], name: "index_player_statistics_on_user_id"
  end

  create_table "prebooking_cancellations", force: :cascade do |t|
    t.integer "game_id", null: false
    t.date "date", null: false
    t.integer "user_id", null: false
    t.datetime "cancelled_at", default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["game_id", "date"], name: "index_prebooking_cancellations_on_game_id_and_date", unique: true
    t.index ["game_id"], name: "index_prebooking_cancellations_on_game_id"
    t.index ["user_id"], name: "index_prebooking_cancellations_on_user_id"
  end

  create_table "prebookings", force: :cascade do |t|
    t.integer "game_id", null: false
    t.date "date", null: false
    t.integer "slot_index", null: false
    t.integer "user_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "status", default: "approved", null: false
    t.datetime "approved_at"
    t.index ["game_id", "date", "slot_index"], name: "index_prebookings_on_game_date_slot", unique: true
    t.index ["game_id"], name: "index_prebookings_on_game_id"
    t.index ["user_id"], name: "index_prebookings_on_user_id"
  end

  create_table "telegram_channels", force: :cascade do |t|
    t.string "username", null: false
    t.string "url"
    t.string "title"
    t.bigint "last_message_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["username"], name: "index_telegram_channels_on_username", unique: true
  end

  create_table "telegram_posts", force: :cascade do |t|
    t.integer "telegram_channel_id", null: false
    t.bigint "message_id", null: false
    t.text "text"
    t.json "extra", default: {}
    t.datetime "published_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["published_at"], name: "index_telegram_posts_on_published_at"
    t.index ["telegram_channel_id", "message_id"], name: "index_telegram_posts_on_telegram_channel_id_and_message_id", unique: true
    t.index ["telegram_channel_id"], name: "index_telegram_posts_on_telegram_channel_id"
  end

  create_table "tournament_courts", force: :cascade do |t|
    t.integer "tournament_id", null: false
    t.integer "court_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["court_id"], name: "index_tournament_courts_on_court_id"
    t.index ["tournament_id"], name: "index_tournament_courts_on_tournament_id"
  end

  create_table "tournament_dates", force: :cascade do |t|
    t.integer "tournament_id", null: false
    t.date "date"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["tournament_id"], name: "index_tournament_dates_on_tournament_id"
  end

  create_table "tournament_participants", force: :cascade do |t|
    t.integer "tournament_id", null: false
    t.integer "user_id", null: false
    t.string "name"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["tournament_id"], name: "index_tournament_participants_on_tournament_id"
    t.index ["user_id"], name: "index_tournament_participants_on_user_id"
  end

  create_table "tournaments", force: :cascade do |t|
    t.integer "players_count"
    t.string "format"
    t.date "start_date"
    t.date "end_date"
    t.integer "user_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "name"
    t.json "bracket_data", default: {}
    t.integer "selected_variant"
    t.index ["user_id"], name: "index_tournaments_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.string "name"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "email"
    t.boolean "admin", default: false, null: false
    t.string "telegram_username"
    t.bigint "telegram_chat_id"
    t.string "telegram_registration_token"
    t.string "skill_level"
    t.boolean "coach", default: false, null: false
    t.text "preferred_sports"
    t.json "skill_levels", default: {}, null: false
    t.string "login_code"
    t.datetime "login_code_sent_at"
    t.string "login_via"
    t.boolean "require_verification", default: false, null: false
    t.string "preferred_login_via"
    t.string "registration_source", default: "email", null: false
    t.boolean "telegram_generated_email", default: false, null: false
    t.string "timezone", default: "Asia/Yekaterinburg"
    t.string "city_name"
    t.boolean "notify_nearby", default: false, null: false
    t.index ["email"], name: "index_users_on_email", unique: true, where: "email IS NOT NULL"
    t.index ["login_code"], name: "index_users_on_login_code"
    t.index ["registration_source"], name: "index_users_on_registration_source"
    t.index ["skill_level"], name: "index_users_on_skill_level"
    t.index ["telegram_chat_id"], name: "index_users_on_telegram_chat_id_unique", unique: true
    t.index ["telegram_registration_token"], name: "index_users_on_telegram_registration_token", unique: true
    t.index ["telegram_username"], name: "index_users_on_telegram_username"
  end

  add_foreign_key "courts", "users"
  add_foreign_key "games", "courts"
  add_foreign_key "games", "tournaments"
  add_foreign_key "games", "users"
  add_foreign_key "matches", "games"
  add_foreign_key "matches", "users"
  add_foreign_key "matches", "users", column: "opponent_id"
  add_foreign_key "participations", "games"
  add_foreign_key "participations", "users"
  add_foreign_key "player_statistic_entries", "games"
  add_foreign_key "player_statistic_entries", "users"
  add_foreign_key "player_statistic_entries", "users", column: "actor_id"
  add_foreign_key "player_statistics", "users"
  add_foreign_key "prebooking_cancellations", "games"
  add_foreign_key "prebooking_cancellations", "users"
  add_foreign_key "prebookings", "games"
  add_foreign_key "prebookings", "users"
  add_foreign_key "telegram_posts", "telegram_channels"
  add_foreign_key "tournament_courts", "courts"
  add_foreign_key "tournament_courts", "tournaments"
  add_foreign_key "tournament_dates", "tournaments"
  add_foreign_key "tournament_participants", "tournaments"
  add_foreign_key "tournament_participants", "users"
  add_foreign_key "tournaments", "users"
end
