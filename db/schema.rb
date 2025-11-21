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

ActiveRecord::Schema[8.0].define(version: 2025_11_21_201037) do
  create_table "courts", force: :cascade do |t|
    t.string "name"
    t.string "coordinates"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id"
    t.string "contact_type"
    t.string "contact_value"
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
    t.index ["court_id"], name: "index_games_on_court_id"
    t.index ["recurring"], name: "index_games_on_recurring"
    t.index ["user_id"], name: "index_games_on_user_id"
    t.index ["with_coach"], name: "index_games_on_with_coach"
  end

  create_table "participations", force: :cascade do |t|
    t.integer "user_id", null: false
    t.integer "game_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["game_id"], name: "index_participations_on_game_id"
    t.index ["user_id", "game_id"], name: "index_participations_on_user_and_game", unique: true
    t.index ["user_id"], name: "index_participations_on_user_id"
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
    t.index ["email"], name: "index_users_on_email", unique: true, where: "email IS NOT NULL"
    t.index ["telegram_chat_id"], name: "index_users_on_telegram_chat_id_unique", unique: true
    t.index ["telegram_registration_token"], name: "index_users_on_telegram_registration_token", unique: true
    t.index ["telegram_username"], name: "index_users_on_telegram_username"
  end

  add_foreign_key "courts", "users"
  add_foreign_key "games", "courts"
  add_foreign_key "games", "users"
  add_foreign_key "participations", "games"
  add_foreign_key "participations", "users"
end
