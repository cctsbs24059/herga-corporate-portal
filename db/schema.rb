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

ActiveRecord::Schema[8.1].define(version: 2026_11_21_232152) do
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

  create_table "infrastructure_availability_alerts", force: :cascade do |t|
    t.bigint "infrastructure_asset_id", null: false
    t.bigint "acknowledged_by_id"
    t.string "status", default: "Active", null: false
    t.datetime "first_detected_at", null: false
    t.datetime "last_observed_at", null: false
    t.datetime "acknowledged_at"
    t.datetime "cleared_at"
    t.decimal "last_availability_percentage", precision: 6, scale: 2
    t.decimal "threshold_percentage", precision: 6, scale: 2, null: false
    t.datetime "assessment_period_end", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["acknowledged_by_id"], name: "index_infrastructure_availability_alerts_on_acknowledged_by_id"
    t.index ["infrastructure_asset_id"], name: "idx_on_infrastructure_asset_id_1567814e28"
    t.index ["infrastructure_asset_id"], name: "index_availability_alerts_one_unresolved_per_asset", unique: true, where: "((status)::text = ANY ((ARRAY['Active'::character varying, 'Acknowledged'::character varying])::text[]))"
    t.index ["status", "last_observed_at"], name: "index_availability_alerts_status_observed"
  end

  create_table "infrastructure_availability_assessments", force: :cascade do |t|
    t.bigint "infrastructure_asset_id", null: false
    t.datetime "period_start", null: false
    t.datetime "period_end", null: false
    t.integer "total_checks", default: 0, null: false
    t.integer "reachable_checks", default: 0, null: false
    t.integer "unreachable_checks", default: 0, null: false
    t.integer "unknown_checks", default: 0, null: false
    t.decimal "availability_percentage", precision: 6, scale: 2
    t.decimal "threshold_percentage", precision: 6, scale: 2, null: false
    t.string "assessment_status", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["infrastructure_asset_id", "period_start", "period_end"], name: "index_infra_availability_assessments_unique_period", unique: true
    t.index ["period_end", "assessment_status"], name: "index_infra_availability_assessments_reporting"
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

  create_table "infrastructure_incident_events", force: :cascade do |t|
    t.bigint "infrastructure_incident_id", null: false
    t.bigint "user_id"
    t.string "event_type", null: false
    t.text "details"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["infrastructure_incident_id", "created_at"], name: "index_incident_events_on_incident_and_created"
    t.index ["infrastructure_incident_id"], name: "idx_on_infrastructure_incident_id_34a5b2e0a0"
    t.index ["user_id"], name: "index_infrastructure_incident_events_on_user_id"
  end

  create_table "infrastructure_incidents", force: :cascade do |t|
    t.bigint "infrastructure_asset_id", null: false
    t.string "incident_type", default: "ICMP Connectivity", null: false
    t.string "severity", default: "Critical", null: false
    t.string "status", default: "Open", null: false
    t.text "description"
    t.datetime "first_detected_at", null: false
    t.datetime "last_observed_at", null: false
    t.integer "consecutive_failures", default: 3, null: false
    t.datetime "resolved_at"
    t.string "resolution_reason"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "assigned_to_id"
    t.bigint "acknowledged_by_id"
    t.bigint "resolved_by_id"
    t.datetime "acknowledged_at"
    t.text "resolution_note"
    t.boolean "suppress_until_recovery", default: false, null: false
    t.index ["acknowledged_by_id"], name: "index_infrastructure_incidents_on_acknowledged_by_id"
    t.index ["assigned_to_id"], name: "index_infrastructure_incidents_on_assigned_to_id"
    t.index ["infrastructure_asset_id", "incident_type"], name: "index_incidents_one_unresolved_per_asset_type", unique: true, where: "((status)::text = ANY ((ARRAY['Open'::character varying, 'Acknowledged'::character varying])::text[]))"
    t.index ["infrastructure_asset_id"], name: "index_infrastructure_incidents_on_infrastructure_asset_id"
    t.index ["resolved_by_id"], name: "index_infrastructure_incidents_on_resolved_by_id"
    t.index ["status", "last_observed_at"], name: "index_infrastructure_incidents_on_status_and_observed"
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
    t.datetime "heartbeat_at"
    t.string "active_job_id"
    t.string "execution_token"
    t.index "(\nCASE\n    WHEN ((status)::text = ANY ((ARRAY['Queued'::character varying, 'Running'::character varying])::text[])) THEN 1\n    ELSE NULL::integer\nEND)", name: "index_infrastructure_monitoring_runs_one_active", unique: true
    t.index ["active_job_id"], name: "index_infrastructure_monitoring_runs_on_active_job_id", unique: true
    t.index ["created_at"], name: "index_infrastructure_monitoring_runs_on_created_at"
    t.index ["execution_token"], name: "index_monitoring_runs_on_execution_token", unique: true
    t.index ["status"], name: "index_infrastructure_monitoring_runs_on_status"
  end

  create_table "infrastructure_notification_attempts", force: :cascade do |t|
    t.bigint "infrastructure_notification_id", null: false
    t.string "status", null: false
    t.datetime "attempted_at", null: false
    t.string "provider_message_id"
    t.string "error_class"
    t.text "error_message"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["attempted_at"], name: "idx_notification_attempts_attempted_at"
    t.index ["infrastructure_notification_id"], name: "idx_notification_attempts_notification"
    t.index ["status"], name: "idx_notification_attempts_status"
  end

  create_table "infrastructure_notifications", force: :cascade do |t|
    t.string "event_key", null: false
    t.string "event_type", null: false
    t.string "notifiable_type"
    t.bigint "notifiable_id"
    t.string "recipient", null: false
    t.string "status", default: "Pending", null: false
    t.integer "escalation_level", default: 0, null: false
    t.integer "attempt_count", default: 0, null: false
    t.datetime "last_attempt_at"
    t.datetime "sent_at"
    t.datetime "next_attempt_at"
    t.text "last_error"
    t.string "message_id"
    t.datetime "event_occurred_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "source_type"
    t.bigint "source_id"
    t.datetime "occurred_at"
    t.datetime "attempted_at"
    t.datetime "accepted_at"
    t.index ["event_key"], name: "index_infrastructure_notifications_on_event_key", unique: true
    t.index ["notifiable_type", "notifiable_id"], name: "index_infrastructure_notifications_on_notifiable"
    t.index ["source_type", "source_id"], name: "idx_on_source_type_source_id_ffe64809bc"
    t.index ["status", "created_at"], name: "idx_infrastructure_notifications_status_created"
    t.index ["status", "next_attempt_at"], name: "idx_infrastructure_notifications_delivery"
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

  add_foreign_key "infrastructure_availability_alerts", "infrastructure_assets"
  add_foreign_key "infrastructure_availability_alerts", "users", column: "acknowledged_by_id"
  add_foreign_key "infrastructure_availability_assessments", "infrastructure_assets"
  add_foreign_key "infrastructure_connectivity_results", "infrastructure_assets"
  add_foreign_key "infrastructure_connectivity_results", "infrastructure_monitoring_runs"
  add_foreign_key "infrastructure_incident_events", "infrastructure_incidents"
  add_foreign_key "infrastructure_incident_events", "users"
  add_foreign_key "infrastructure_incidents", "infrastructure_assets"
  add_foreign_key "infrastructure_incidents", "users", column: "acknowledged_by_id"
  add_foreign_key "infrastructure_incidents", "users", column: "assigned_to_id"
  add_foreign_key "infrastructure_incidents", "users", column: "resolved_by_id"
  add_foreign_key "infrastructure_notification_attempts", "infrastructure_notifications"
end
