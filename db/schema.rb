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

ActiveRecord::Schema[8.1].define(version: 2026_08_30_164412) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "lanscan_runs", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "error_message"
    t.datetime "finished_at"
    t.integer "hosts_found", default: 0, null: false
    t.string "ports", null: false
    t.datetime "started_at"
    t.string "status", default: "pending", null: false
    t.string "target", null: false
    t.integer "timeout", null: false
    t.bigint "total_probes"
    t.datetime "updated_at", null: false
    t.bigint "user_id"
    t.index ["created_at"], name: "index_lanscan_runs_on_created_at"
    t.index ["status"], name: "index_lanscan_runs_on_status"
    t.index ["user_id"], name: "index_lanscan_runs_on_user_id"
  end

  create_table "lanscans", force: :cascade do |t|
    t.datetime "created_at", default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.string "ip_address", null: false
    t.bigint "lanscan_run_id"
    t.string "mac_address"
    t.string "open_ports"
    t.datetime "scanned_at", null: false
    t.string "target", null: false
    t.datetime "updated_at", default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.index ["ip_address"], name: "index_lanscans_on_ip_address"
    t.index ["lanscan_run_id"], name: "index_lanscans_on_lanscan_run_id"
    t.index ["scanned_at"], name: "index_lanscans_on_scanned_at"
    t.index ["target"], name: "index_lanscans_on_target"
  end

  create_table "users", force: :cascade do |t|
    t.boolean "admin", default: false, null: false
    t.string "category"
    t.datetime "created_at", null: false
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.integer "failed_attempts", default: 0, null: false
    t.string "first_name"
    t.string "gender"
    t.string "last_name"
    t.datetime "locked_at"
    t.boolean "manager", default: false, null: false
    t.string "province"
    t.string "region"
    t.boolean "regular", default: false, null: false
    t.datetime "remember_created_at"
    t.datetime "reset_password_sent_at"
    t.string "reset_password_token"
    t.string "unlock_token"
    t.datetime "updated_at", null: false
    t.string "username", null: false
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
    t.index ["unlock_token"], name: "index_users_on_unlock_token", unique: true
    t.index ["username"], name: "index_users_on_username", unique: true
  end

  add_foreign_key "lanscan_runs", "users"
  add_foreign_key "lanscans", "lanscan_runs"
end
