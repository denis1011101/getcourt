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

ActiveRecord::Schema[8.1].define(version: 2026_08_15_000000) do
  create_table "active_storage_attachments", force: :cascade do |t|
    t.integer "blob_id", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.integer "record_id", null: false
    t.string "record_type", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.string "content_type"
    t.datetime "created_at", null: false
    t.string "filename", null: false
    t.string "key", null: false
    t.text "metadata"
    t.string "service_name", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.integer "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "ahoy_events", force: :cascade do |t|
    t.string "name"
    t.json "properties"
    t.datetime "time"
    t.integer "user_id"
    t.integer "visit_id"
    t.index ["name", "time"], name: "index_ahoy_events_on_name_and_time"
    t.index ["user_id"], name: "index_ahoy_events_on_user_id"
    t.index ["visit_id"], name: "index_ahoy_events_on_visit_id"
  end

  create_table "ahoy_visits", force: :cascade do |t|
    t.string "app_version"
    t.string "browser"
    t.string "city"
    t.string "country"
    t.string "device_type"
    t.string "ip"
    t.text "landing_page"
    t.float "latitude"
    t.float "longitude"
    t.string "os"
    t.string "os_version"
    t.string "platform"
    t.text "referrer"
    t.string "referring_domain"
    t.string "region"
    t.datetime "started_at"
    t.text "user_agent"
    t.integer "user_id"
    t.string "utm_campaign"
    t.string "utm_content"
    t.string "utm_medium"
    t.string "utm_source"
    t.string "utm_term"
    t.string "visit_token"
    t.string "visitor_token"
    t.index ["user_id"], name: "index_ahoy_visits_on_user_id"
    t.index ["visit_token"], name: "index_ahoy_visits_on_visit_token", unique: true
    t.index ["visitor_token"], name: "index_ahoy_visits_on_visitor_token"
  end

  create_table "cities", force: :cascade do |t|
    t.string "asciiname"
    t.string "country_code"
    t.datetime "created_at", null: false
    t.integer "geoname_id"
    t.decimal "latitude", precision: 10, scale: 6
    t.decimal "longitude", precision: 10, scale: 6
    t.string "name"
    t.integer "population"
    t.string "timezone"
    t.datetime "updated_at", null: false
    t.index ["country_code"], name: "index_cities_on_country_code"
    t.index ["geoname_id"], name: "index_cities_on_geoname_id", unique: true
    t.index ["name"], name: "index_cities_on_name"
    t.index ["timezone"], name: "index_cities_on_timezone"
  end

  create_table "coach_prebookings", force: :cascade do |t|
    t.integer "coach_id", null: false
    t.datetime "created_at", null: false
    t.date "date", null: false
    t.integer "game_id", null: false
    t.datetime "updated_at", null: false
    t.index ["coach_id"], name: "index_coach_prebookings_on_coach_id"
    t.index ["game_id", "coach_id", "date"], name: "index_coach_prebookings_on_game_id_and_coach_id_and_date", unique: true
    t.index ["game_id"], name: "index_coach_prebookings_on_game_id"
  end

  create_table "court_suggestions", force: :cascade do |t|
    t.text "comment"
    t.integer "court_id", null: false
    t.datetime "created_at", null: false
    t.json "payload", default: {}, null: false
    t.datetime "reviewed_at"
    t.integer "reviewed_by_id"
    t.string "status", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["court_id", "status"], name: "index_court_suggestions_on_court_id_and_status"
    t.index ["court_id", "user_id"], name: "index_unique_pending_court_suggestions", unique: true, where: "status = 'pending'"
    t.index ["court_id"], name: "index_court_suggestions_on_court_id"
    t.index ["reviewed_by_id"], name: "index_court_suggestions_on_reviewed_by_id"
    t.index ["user_id"], name: "index_court_suggestions_on_user_id"
  end

  create_table "courts", force: :cascade do |t|
    t.datetime "approved_at"
    t.string "city_name"
    t.string "contact_type"
    t.string "contact_value"
    t.string "coordinates"
    t.datetime "created_at", null: false
    t.boolean "free", default: false, null: false
    t.boolean "indoor", default: false, null: false
    t.string "moderation_status", default: "pending", null: false
    t.string "name"
    t.boolean "outdoor", default: false, null: false
    t.string "sport"
    t.text "surfaces"
    t.datetime "updated_at", null: false
    t.integer "user_id"
    t.index ["city_name"], name: "index_courts_on_city_name"
    t.index ["moderation_status"], name: "index_courts_on_moderation_status"
    t.index ["sport"], name: "index_courts_on_sport"
    t.index ["user_id"], name: "index_courts_on_user_id"
  end

  create_table "favorite_courts", force: :cascade do |t|
    t.integer "court_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["court_id"], name: "index_favorite_courts_on_court_id"
    t.index ["user_id", "court_id"], name: "index_favorite_courts_on_user_id_and_court_id", unique: true
    t.index ["user_id"], name: "index_favorite_courts_on_user_id"
  end

  create_table "featured_matches", force: :cascade do |t|
    t.boolean "active", default: false, null: false
    t.integer "court_id"
    t.datetime "created_at", null: false
    t.text "description"
    t.string "photo_credit"
    t.string "photo_credit_url"
    t.string "player_left_flag"
    t.string "player_left_name", null: false
    t.string "player_right_flag"
    t.string "player_right_name", null: false
    t.text "result"
    t.string "slug", null: false
    t.datetime "starts_at", null: false
    t.string "status", default: "scheduled", null: false
    t.string "surface_label"
    t.string "tournament_label", null: false
    t.datetime "updated_at", null: false
    t.index ["active"], name: "index_featured_matches_on_active", unique: true, where: "active = 1"
    t.index ["court_id"], name: "index_featured_matches_on_court_id"
    t.index ["slug"], name: "index_featured_matches_on_slug", unique: true
    t.index ["starts_at"], name: "index_featured_matches_on_starts_at"
  end

  create_table "games", force: :cascade do |t|
    t.integer "coach_id"
    t.string "coach_invitation_status"
    t.text "comment"
    t.integer "court_id", null: false
    t.datetime "created_at", null: false
    t.date "date"
    t.integer "duration_minutes"
    t.string "environment"
    t.date "last_participations_reset_at"
    t.integer "occurrences_per_week", default: 1, null: false
    t.integer "players_count", default: 4, null: false
    t.string "post_game_stats_reminder_job_id"
    t.boolean "prebooking_enabled", default: false, null: false
    t.boolean "recurring", default: false, null: false
    t.string "skill_level"
    t.string "sport"
    t.string "surface"
    t.string "threads_post_id"
    t.datetime "threads_posted_at"
    t.time "time"
    t.time "time2"
    t.text "times", default: "[]", null: false
    t.integer "tournament_id"
    t.datetime "updated_at", null: false
    t.boolean "urgent_player_search", default: false, null: false
    t.integer "user_id", null: false
    t.boolean "with_coach", default: false, null: false
    t.index ["coach_id"], name: "index_games_on_coach_id"
    t.index ["court_id"], name: "index_games_on_court_id"
    t.index ["prebooking_enabled"], name: "index_games_on_prebooking_enabled"
    t.index ["recurring"], name: "index_games_on_recurring"
    t.index ["tournament_id"], name: "index_games_on_tournament_id"
    t.index ["urgent_player_search"], name: "index_games_on_urgent_player_search"
    t.index ["user_id"], name: "index_games_on_user_id"
    t.index ["with_coach"], name: "index_games_on_with_coach"
  end

  create_table "matches", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "game_id"
    t.string "mode", null: false
    t.integer "opponent_id"
    t.string "outcome", null: false
    t.datetime "played_at", null: false
    t.string "score"
    t.json "stats", default: {}, null: false
    t.string "surface"
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["game_id"], name: "index_matches_on_game_id"
    t.index ["opponent_id"], name: "index_matches_on_opponent_id"
    t.index ["user_id", "mode", "played_at"], name: "index_matches_on_user_id_and_mode_and_played_at"
    t.index ["user_id", "played_at"], name: "index_matches_on_user_id_and_played_at"
    t.index ["user_id"], name: "index_matches_on_user_id"
  end

  create_table "participations", force: :cascade do |t|
    t.datetime "approved_at"
    t.datetime "created_at", null: false
    t.integer "game_id", null: false
    t.string "guest_name"
    t.string "status", default: "approved", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id"
    t.index ["game_id"], name: "index_participations_on_game_id"
    t.index ["user_id", "game_id"], name: "index_participations_on_user_and_game", unique: true
    t.index ["user_id"], name: "index_participations_on_user_id"
  end

  create_table "player_statistic_entries", force: :cascade do |t|
    t.integer "actor_id", null: false
    t.datetime "created_at", null: false
    t.json "data", default: {}, null: false
    t.integer "game_id"
    t.datetime "recorded_at", null: false
    t.string "source", default: "telegram", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["actor_id"], name: "index_player_statistic_entries_on_actor_id"
    t.index ["game_id"], name: "index_player_statistic_entries_on_game_id"
    t.index ["user_id", "game_id", "source"], name: "index_ps_entries_on_user_game_source", unique: true
    t.index ["user_id"], name: "index_player_statistic_entries_on_user_id"
  end

  create_table "player_statistics", force: :cascade do |t|
    t.integer "aces"
    t.integer "break_points_converted"
    t.integer "break_points_saved"
    t.datetime "created_at", null: false
    t.integer "double_faults"
    t.integer "doubles_games"
    t.float "doubles_hours"
    t.integer "doubles_losses"
    t.float "doubles_rating"
    t.integer "doubles_sessions"
    t.integer "doubles_wins"
    t.float "first_serve_percent"
    t.integer "games_won_total"
    t.integer "group_training"
    t.integer "individual_training"
    t.integer "net_points_won"
    t.integer "return_games_won"
    t.integer "return_points_won"
    t.integer "service_points_won"
    t.integer "singles_games"
    t.float "singles_hours"
    t.integer "singles_losses"
    t.float "singles_rating"
    t.integer "singles_sessions"
    t.integer "singles_wins"
    t.datetime "stats_reset_at"
    t.integer "unforced_errors"
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.integer "winners"
    t.index ["user_id"], name: "index_player_statistics_on_user_id"
  end

  create_table "prebooking_cancellations", force: :cascade do |t|
    t.datetime "cancelled_at", default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.datetime "created_at", null: false
    t.date "date", null: false
    t.integer "game_id", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["game_id", "date"], name: "index_prebooking_cancellations_on_game_id_and_date", unique: true
    t.index ["game_id"], name: "index_prebooking_cancellations_on_game_id"
    t.index ["user_id"], name: "index_prebooking_cancellations_on_user_id"
  end

  create_table "prebookings", force: :cascade do |t|
    t.datetime "approved_at"
    t.datetime "created_at", null: false
    t.date "date", null: false
    t.integer "game_id", null: false
    t.integer "slot_index", null: false
    t.string "status", default: "approved", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id"
    t.index ["game_id", "date", "slot_index"], name: "index_prebookings_on_game_date_slot", unique: true
    t.index ["game_id"], name: "index_prebookings_on_game_id"
    t.index ["user_id"], name: "index_prebookings_on_user_id"
  end

  create_table "telegram_channels", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "last_message_id"
    t.string "title"
    t.datetime "updated_at", null: false
    t.string "url"
    t.string "username", null: false
    t.index ["username"], name: "index_telegram_channels_on_username", unique: true
  end

  create_table "telegram_posts", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.json "extra", default: {}
    t.bigint "message_id", null: false
    t.datetime "published_at"
    t.integer "telegram_channel_id", null: false
    t.text "text"
    t.text "text_en"
    t.datetime "updated_at", null: false
    t.index ["published_at"], name: "index_telegram_posts_on_published_at"
    t.index ["telegram_channel_id", "message_id"], name: "index_telegram_posts_on_telegram_channel_id_and_message_id", unique: true
    t.index ["telegram_channel_id"], name: "index_telegram_posts_on_telegram_channel_id"
  end

  create_table "tournament_courts", force: :cascade do |t|
    t.integer "court_id", null: false
    t.datetime "created_at", null: false
    t.integer "tournament_id", null: false
    t.datetime "updated_at", null: false
    t.index ["court_id"], name: "index_tournament_courts_on_court_id"
    t.index ["tournament_id"], name: "index_tournament_courts_on_tournament_id"
  end

  create_table "tournament_dates", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.date "date"
    t.integer "tournament_id", null: false
    t.datetime "updated_at", null: false
    t.index ["tournament_id"], name: "index_tournament_dates_on_tournament_id"
  end

  create_table "tournament_matches", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "played_at"
    t.integer "player_a2_id"
    t.integer "player_a_id", null: false
    t.integer "player_b2_id"
    t.integer "player_b_id", null: false
    t.string "result"
    t.string "score"
    t.integer "tournament_id", null: false
    t.datetime "updated_at", null: false
    t.index ["player_a2_id"], name: "index_tournament_matches_on_player_a2_id"
    t.index ["player_a_id"], name: "index_tournament_matches_on_player_a_id"
    t.index ["player_b2_id"], name: "index_tournament_matches_on_player_b2_id"
    t.index ["player_b_id"], name: "index_tournament_matches_on_player_b_id"
    t.index ["tournament_id", "player_a_id", "player_b_id"], name: "index_tournament_matches_on_players"
    t.index ["tournament_id"], name: "index_tournament_matches_on_tournament_id"
  end

  create_table "tournament_participants", force: :cascade do |t|
    t.datetime "approved_at"
    t.datetime "created_at", null: false
    t.string "name"
    t.string "status", default: "approved", null: false
    t.integer "tournament_id", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["status"], name: "index_tournament_participants_on_status"
    t.index ["tournament_id", "user_id"], name: "index_tournament_participants_on_tournament_and_user", unique: true
    t.index ["tournament_id"], name: "index_tournament_participants_on_tournament_id"
    t.index ["user_id"], name: "index_tournament_participants_on_user_id"
  end

  create_table "tournaments", force: :cascade do |t|
    t.json "bracket_data", default: {}
    t.datetime "created_at", null: false
    t.date "end_date"
    t.string "format"
    t.integer "games_count"
    t.string "name"
    t.integer "players_count"
    t.integer "selected_variant"
    t.date "start_date"
    t.time "time"
    t.string "tournament_type", default: "bracket", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["tournament_type"], name: "index_tournaments_on_tournament_type"
    t.index ["user_id"], name: "index_tournaments_on_user_id"
  end

  create_table "translation_caches", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "text_en", null: false
    t.string "text_hash", null: false
    t.datetime "updated_at", null: false
    t.index ["text_hash"], name: "index_translation_caches_on_text_hash", unique: true
  end

  create_table "users", force: :cascade do |t|
    t.text "about_me"
    t.boolean "admin", default: false, null: false
    t.string "city_name"
    t.boolean "coach"
    t.text "court_preferences_note"
    t.datetime "created_at", null: false
    t.string "email"
    t.string "locale"
    t.string "login_code"
    t.datetime "login_code_sent_at"
    t.string "login_via"
    t.datetime "merged_at"
    t.integer "merged_into_id"
    t.string "name"
    t.string "notification_channel"
    t.boolean "notify_nearby", default: false, null: false
    t.datetime "onboarded_at"
    t.datetime "onboarding_dismissed_at"
    t.string "preferred_login_via"
    t.text "preferred_sports"
    t.json "recent_invite_handles", default: [], null: false
    t.string "registration_source", default: "email", null: false
    t.boolean "require_verification", default: false, null: false
    t.string "skill_level"
    t.json "skill_levels", default: {}, null: false
    t.bigint "telegram_chat_id"
    t.boolean "telegram_generated_email", default: false, null: false
    t.string "telegram_locale"
    t.string "telegram_registration_token"
    t.string "telegram_username"
    t.string "timezone", default: "Asia/Yekaterinburg"
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_users_on_email", unique: true, where: "email IS NOT NULL"
    t.index ["login_code"], name: "index_users_on_login_code"
    t.index ["merged_into_id"], name: "index_users_on_merged_into_id"
    t.index ["registration_source"], name: "index_users_on_registration_source"
    t.index ["skill_level"], name: "index_users_on_skill_level"
    t.index ["telegram_chat_id"], name: "index_users_on_telegram_chat_id_unique", unique: true
    t.index ["telegram_registration_token"], name: "index_users_on_telegram_registration_token", unique: true
    t.index ["telegram_username"], name: "index_users_on_telegram_username"
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "coach_prebookings", "games"
  add_foreign_key "coach_prebookings", "users", column: "coach_id"
  add_foreign_key "court_suggestions", "courts"
  add_foreign_key "court_suggestions", "users"
  add_foreign_key "court_suggestions", "users", column: "reviewed_by_id"
  add_foreign_key "courts", "users"
  add_foreign_key "favorite_courts", "courts"
  add_foreign_key "favorite_courts", "users"
  add_foreign_key "featured_matches", "courts"
  add_foreign_key "games", "courts"
  add_foreign_key "games", "tournaments"
  add_foreign_key "games", "users"
  add_foreign_key "games", "users", column: "coach_id"
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
  add_foreign_key "tournament_matches", "tournaments"
  add_foreign_key "tournament_matches", "users", column: "player_a2_id"
  add_foreign_key "tournament_matches", "users", column: "player_a_id"
  add_foreign_key "tournament_matches", "users", column: "player_b2_id"
  add_foreign_key "tournament_matches", "users", column: "player_b_id"
  add_foreign_key "tournament_participants", "tournaments"
  add_foreign_key "tournament_participants", "users"
  add_foreign_key "tournaments", "users"
  add_foreign_key "users", "users", column: "merged_into_id"
end
