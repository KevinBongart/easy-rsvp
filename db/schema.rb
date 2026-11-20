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

ActiveRecord::Schema[8.1].define(version: 2026_11_20_150000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"
  enable_extension "pgcrypto"
  enable_extension "uuid-ossp"

  create_table "action_text_rich_texts", force: :cascade do |t|
    t.text "body"
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.bigint "record_id", null: false
    t.string "record_type", null: false
    t.datetime "updated_at", null: false
    t.index ["record_type", "record_id", "name"], name: "index_action_text_rich_texts_uniqueness", unique: true
  end

  create_table "active_storage_attachments", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.datetime "created_at", precision: nil, null: false
    t.string "name", null: false
    t.bigint "record_id", null: false
    t.string "record_type", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.string "content_type"
    t.datetime "created_at", precision: nil, null: false
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

  create_table "events", force: :cascade do |t|
    t.string "admin_token", null: false
    t.datetime "created_at", precision: nil, null: false
    t.date "date", null: false
    t.datetime "ends_at"
    t.boolean "published", default: true, null: false
    t.boolean "show_rsvp_names", default: true, null: false
    t.datetime "starts_at"
    t.string "time_zone"
    t.string "title", null: false
    t.datetime "updated_at", precision: nil, null: false
    t.datetime "spam_at"
    t.string "spam_source"
    t.float "spam_score"
    t.datetime "spam_decided_at"
    t.boolean "spam_verdict_hidden", default: false, null: false
    t.index ["created_at"], name: "index_events_on_created_at"
    t.check_constraint "ends_at IS NULL OR starts_at IS NULL OR ends_at > starts_at", name: "events_schedule_ordered"
    t.check_constraint "spam_at IS NULL AND (spam_source IS NULL OR spam_source::text = 'cleared'::text) OR spam_at IS NOT NULL AND (spam_source::text = ANY (ARRAY['operator'::character varying, 'automatic'::character varying]::text[]))", name: "events_spam_source_matches_spam_at"
    t.check_constraint "starts_at IS NULL AND ends_at IS NULL AND time_zone IS NULL OR starts_at IS NOT NULL AND ends_at IS NOT NULL AND time_zone IS NOT NULL AND btrim(time_zone::text) <> ''::text", name: "events_schedule_complete"
    t.check_constraint "starts_at IS NULL OR ((starts_at AT TIME ZONE 'UTC'::text) AT TIME ZONE time_zone)::date = date AND ((ends_at AT TIME ZONE 'UTC'::text) AT TIME ZONE time_zone)::date = date", name: "events_schedule_matches_date"
  end

  create_table "image_uploads", force: :cascade do |t|
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
  end

  create_table "legacy_event_body_conflicts", force: :cascade do |t|
    t.datetime "action_text_updated_at", null: false
    t.text "body", null: false
    t.datetime "created_at", null: false
    t.bigint "event_id", null: false
    t.datetime "event_updated_at", null: false
    t.index ["event_id"], name: "index_legacy_event_body_conflicts_on_event_id", unique: true
  end

  create_table "recent_event_creations", force: :cascade do |t|
    t.string "client_digest", null: false
    t.datetime "created_at", null: false
    t.bigint "event_id"
    t.datetime "spam_at"
    t.index ["client_digest", "created_at"], name: "index_recent_event_creations_on_client_digest_and_created_at"
    t.index ["created_at"], name: "index_recent_event_creations_on_created_at"
    t.index ["event_id"], name: "index_recent_event_creations_on_event_id"
  end

  create_table "rsvps", force: :cascade do |t|
    t.datetime "created_at", precision: nil, null: false
    t.bigint "event_id", null: false
    t.string "name", null: false
    t.string "response"
    t.datetime "updated_at", precision: nil, null: false
    t.index ["event_id"], name: "index_rsvps_on_event_id"
    t.check_constraint "name IS NOT NULL AND name::text ~ '[^[:space:]]'::text", name: "rsvps_name_present"
    t.check_constraint "response IS NOT NULL AND (response::text = ANY (ARRAY['yes'::character varying::text, 'maybe'::character varying::text, 'no'::character varying::text]))", name: "rsvps_supported_response"
  end

  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "legacy_event_body_conflicts", "events", on_delete: :cascade
  add_foreign_key "recent_event_creations", "events", on_delete: :nullify
  add_foreign_key "rsvps", "events"
end
