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

ActiveRecord::Schema[8.1].define(version: 2026_11_17_230655) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "infrastructure_assets", force: :cascade do |t|
    t.string "hostname", null: false
    t.string "fqdn"
    t.string "ip_address"
    t.string "asset_type", null: false
    t.string "operating_system"
    t.string "operating_system_version"
    t.string "environment", default: "Production", null: false
    t.string "location"
    t.string "business_function"
    t.string "status", default: "Active", null: false
    t.string "source", default: "Manual", null: false
    t.string "ad_object_guid"
    t.string "ad_distinguished_name"
    t.datetime "last_ad_sync_at"
    t.text "description"
    t.text "notes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "dns_status"
    t.string "resolved_ip_address"
    t.string "icmp_status"
    t.float "icmp_response_ms"
    t.datetime "last_connectivity_check_at"
    t.text "connectivity_error"
    t.index "lower((fqdn)::text)", name: "index_infrastructure_assets_on_lower_fqdn", unique: true, where: "((fqdn IS NOT NULL) AND ((fqdn)::text <> ''::text))"
    t.index ["ad_object_guid"], name: "index_infrastructure_assets_on_ad_object_guid", unique: true
    t.index ["asset_type"], name: "index_infrastructure_assets_on_asset_type"
    t.index ["environment"], name: "index_infrastructure_assets_on_environment"
    t.index ["hostname"], name: "index_infrastructure_assets_on_hostname"
    t.index ["source"], name: "index_infrastructure_assets_on_source"
    t.index ["status"], name: "index_infrastructure_assets_on_status"
  end

  create_table "infrastructure_connectivity_results", force: :cascade do |t|
    t.bigint "infrastructure_asset_id", null: false
    t.bigint "infrastructure_monitoring_run_id"
    t.string "dns_status"
    t.string "resolved_ip_address"
    t.string "icmp_status"
    t.float "icmp_response_ms"
    t.text "connectivity_error"
    t.datetime "checked_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["infrastructure_asset_id", "checked_at"], name: "index_connectivity_results_on_asset_and_checked_at"
    t.index ["infrastructure_asset_id"], name: "idx_on_infrastructure_asset_id_a336a50ee8"
    t.index ["infrastructure_monitoring_run_id"], name: "idx_on_infrastructure_monitoring_run_id_881504039e"
  end

  create_table "infrastructure_monitoring_runs", force: :cascade do |t|
    t.string "status", default: "Queued", null: false
    t.integer "total_assets", default: 0, null: false
    t.integer "processed_assets", default: 0, null: false
    t.integer "reachable_assets", default: 0, null: false
    t.integer "unreachable_assets", default: 0, null: false
    t.integer "unknown_assets", default: 0, null: false
    t.integer "failed_checks", default: 0, null: false
    t.datetime "started_at"
    t.datetime "completed_at"
    t.text "error_message"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index "(\nCASE\n    WHEN ((status)::text = ANY ((ARRAY['Queued'::character varying, 'Running'::character varying])::text[])) THEN 1\n    ELSE NULL::integer\nEND)", name: "index_infrastructure_monitoring_runs_one_active", unique: true
    t.index ["created_at"], name: "index_infrastructure_monitoring_runs_on_created_at"
    t.index ["status"], name: "index_infrastructure_monitoring_runs_on_status"
  end

  create_table "portal_applications", force: :cascade do |t|
    t.string "name"
    t.text "description"
    t.string "url"
    t.string "category"
    t.string "icon"
    t.boolean "active", default: true, null: false
    t.integer "position", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "users", force: :cascade do |t|
    t.string "username", null: false
    t.string "email"
    t.string "display_name"
    t.text "ad_dn"
    t.boolean "admin", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["username"], name: "index_users_on_username", unique: true
  end

  add_foreign_key "infrastructure_connectivity_results", "infrastructure_assets"
  add_foreign_key "infrastructure_connectivity_results", "infrastructure_monitoring_runs"
end
