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

ActiveRecord::Schema[8.1].define(version: 2026_07_06_120000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "account_metrics", force: :cascade do |t|
    t.integer "accounts_reached", default: 0, null: false
    t.datetime "captured_at", null: false
    t.datetime "created_at", null: false
    t.integer "followers", default: 0, null: false
    t.integer "new_followers", default: 0, null: false
    t.date "period_end"
    t.date "period_start"
    t.integer "profile_views", default: 0, null: false
    t.jsonb "raw", default: {}, null: false
    t.bigint "social_account_id", null: false
    t.integer "story_replies", default: 0, null: false
    t.integer "total_interactions", default: 0, null: false
    t.datetime "updated_at", null: false
    t.integer "views", default: 0, null: false
    t.bigint "workspace_id", null: false
    t.index ["social_account_id", "captured_at"], name: "index_account_metrics_on_social_account_id_and_captured_at"
    t.index ["social_account_id"], name: "index_account_metrics_on_social_account_id"
    t.index ["workspace_id", "captured_at"], name: "index_account_metrics_on_workspace_id_and_captured_at"
  end

  create_table "active_admin_comments", force: :cascade do |t|
    t.bigint "author_id"
    t.string "author_type"
    t.text "body"
    t.datetime "created_at", null: false
    t.string "namespace"
    t.bigint "resource_id"
    t.string "resource_type"
    t.datetime "updated_at", null: false
    t.index ["author_type", "author_id"], name: "index_active_admin_comments_on_author"
    t.index ["namespace"], name: "index_active_admin_comments_on_namespace"
    t.index ["resource_type", "resource_id"], name: "index_active_admin_comments_on_resource"
  end

  create_table "active_storage_attachments", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
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
    t.datetime "created_at", null: false
    t.string "filename", null: false
    t.string "key", null: false
    t.text "metadata"
    t.string "service_name", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "admin_audit_logs", force: :cascade do |t|
    t.string "action", null: false
    t.datetime "created_at", null: false
    t.string "ip_address"
    t.jsonb "metadata", default: {}, null: false
    t.bigint "staff_user_id"
    t.bigint "target_id"
    t.string "target_type"
    t.datetime "updated_at", null: false
    t.index ["action", "created_at"], name: "index_admin_audit_logs_on_action_and_created_at"
    t.index ["staff_user_id"], name: "index_admin_audit_logs_on_staff_user_id"
    t.index ["target_type", "target_id"], name: "index_admin_audit_logs_on_target_type_and_target_id"
  end

  create_table "ai_configs", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "default_model", default: "anthropic/claude-sonnet-4.5", null: false
    t.jsonb "operation_models", default: {}, null: false
    t.string "provider"
    t.datetime "updated_at", null: false
  end

  create_table "ai_usage_logs", force: :cascade do |t|
    t.integer "cache_creation_input_tokens", default: 0, null: false
    t.integer "cache_read_input_tokens", default: 0, null: false
    t.decimal "cost_cents", precision: 14, scale: 4, default: "0.0", null: false
    t.datetime "created_at", null: false
    t.integer "input_tokens", default: 0, null: false
    t.string "model"
    t.string "operation", null: false
    t.integer "output_tokens", default: 0, null: false
    t.string "provider", null: false
    t.bigint "subject_id"
    t.string "subject_type"
    t.string "unit_kind"
    t.decimal "units", precision: 12, scale: 3, default: "0.0", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id"
    t.bigint "workspace_id", null: false
    t.index ["operation", "created_at"], name: "index_ai_usage_logs_on_operation_and_created_at"
    t.index ["provider", "created_at"], name: "index_ai_usage_logs_on_provider_and_created_at"
    t.index ["subject_type", "subject_id"], name: "index_ai_usage_logs_on_subject_type_and_subject_id"
    t.index ["user_id"], name: "index_ai_usage_logs_on_user_id"
    t.index ["workspace_id", "created_at"], name: "index_ai_usage_logs_on_workspace_id_and_created_at"
  end

  create_table "attachments", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "description"
    t.jsonb "metadata", default: {}, null: false
    t.bigint "note_id"
    t.integer "position", default: 0, null: false
    t.bigint "ticket_id", null: false
    t.string "title"
    t.datetime "updated_at", null: false
    t.bigint "uploaded_by_id"
    t.bigint "workspace_id", null: false
    t.index ["note_id"], name: "index_attachments_on_note_id"
    t.index ["ticket_id", "position"], name: "index_attachments_on_ticket_id_and_position"
    t.index ["ticket_id"], name: "index_attachments_on_ticket_id"
    t.index ["uploaded_by_id"], name: "index_attachments_on_uploaded_by_id"
    t.index ["workspace_id", "created_at"], name: "index_attachments_on_workspace_id_and_created_at"
    t.index ["workspace_id"], name: "index_attachments_on_workspace_id"
  end

  create_table "autopilot_runs", force: :cascade do |t|
    t.bigint "batch_id"
    t.datetime "created_at", null: false
    t.integer "estimated_credits", default: 0, null: false
    t.string "failure_reason"
    t.datetime "finished_at"
    t.string "mode", default: "scheduled", null: false
    t.jsonb "progress", default: {}, null: false
    t.datetime "scheduled_at"
    t.string "scope", default: "ticket", null: false
    t.integer "spent_credits", default: 0, null: false
    t.datetime "started_at"
    t.string "state", default: "pending", null: false
    t.string "target_status", default: "scheduled", null: false
    t.bigint "ticket_id"
    t.datetime "updated_at", null: false
    t.bigint "user_id"
    t.bigint "workspace_id", null: false
    t.index ["batch_id"], name: "index_autopilot_runs_on_batch_id"
    t.index ["ticket_id", "state"], name: "index_autopilot_runs_on_ticket_id_and_state"
    t.index ["ticket_id"], name: "index_autopilot_runs_on_ticket_id"
    t.index ["ticket_id"], name: "index_autopilot_runs_one_active_per_ticket", unique: true, where: "(((scope)::text = 'ticket'::text) AND ((state)::text = ANY ((ARRAY['pending'::character varying, 'scoping'::character varying, 'generating'::character varying, 'awaiting_generation'::character varying, 'publishing'::character varying])::text[])))"
    t.index ["user_id"], name: "index_autopilot_runs_on_user_id"
    t.index ["workspace_id", "state"], name: "index_autopilot_runs_on_workspace_id_and_state"
    t.index ["workspace_id"], name: "index_autopilot_runs_on_workspace_id"
  end

  create_table "charges", force: :cascade do |t|
    t.integer "amount_cents", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "expires_at"
    t.bigint "invoice_id", null: false
    t.integer "method", default: 0, null: false
    t.string "mp_payment_id"
    t.text "payment_link"
    t.text "pix_qr_code"
    t.text "pix_qr_code_base64"
    t.string "preference_id"
    t.string "provider", default: "mercado_pago", null: false
    t.string "status", default: "pending"
    t.string "ticket_url"
    t.datetime "updated_at", null: false
    t.bigint "workspace_id", null: false
    t.index ["invoice_id"], name: "index_charges_on_invoice_id"
    t.index ["mp_payment_id"], name: "index_charges_on_mp_payment_id", unique: true, where: "(mp_payment_id IS NOT NULL)"
    t.index ["workspace_id"], name: "index_charges_on_workspace_id"
  end

  create_table "clients", force: :cascade do |t|
    t.jsonb "attribution", default: {}, null: false
    t.string "brand_primary_color", default: "#7C3AED", null: false
    t.string "brand_secondary_color", default: "#F59E0B", null: false
    t.text "brand_voice"
    t.string "company"
    t.datetime "created_at", null: false
    t.string "default_handle"
    t.string "document"
    t.string "email"
    t.string "name", null: false
    t.text "notes"
    t.string "phone"
    t.jsonb "positioning", default: {}, null: false
    t.integer "status", default: 0, null: false
    t.datetime "updated_at", null: false
    t.bigint "workspace_id", null: false
    t.index ["workspace_id", "status"], name: "index_clients_on_workspace_id_and_status"
    t.index ["workspace_id"], name: "index_clients_on_workspace_id"
  end

  create_table "creatives", force: :cascade do |t|
    t.string "approval_state", default: "pending", null: false
    t.text "caption"
    t.text "client_feedback"
    t.bigint "client_id"
    t.datetime "created_at", null: false
    t.string "creative_type", null: false
    t.datetime "decided_at"
    t.jsonb "metadata", default: {}, null: false
    t.string "name"
    t.bigint "parent_id"
    t.string "provider"
    t.bigint "reviewed_by_id"
    t.string "reviewed_by_type"
    t.integer "source", default: 0, null: false
    t.integer "status", default: 0, null: false
    t.bigint "ticket_id"
    t.datetime "updated_at", null: false
    t.integer "version", default: 1, null: false
    t.bigint "workspace_id", null: false
    t.index ["client_id"], name: "index_creatives_on_client_id"
    t.index ["parent_id"], name: "index_creatives_on_parent_id"
    t.index ["reviewed_by_type", "reviewed_by_id"], name: "index_creatives_on_reviewed_by"
    t.index ["ticket_id"], name: "index_creatives_on_ticket_id"
    t.index ["workspace_id", "status"], name: "index_creatives_on_workspace_id_and_status"
    t.index ["workspace_id"], name: "index_creatives_on_workspace_id"
  end

  create_table "credit_transactions", force: :cascade do |t|
    t.integer "amount", null: false
    t.integer "balance_after", default: 0, null: false
    t.string "bucket", default: "purchased", null: false
    t.datetime "created_at", null: false
    t.string "description"
    t.datetime "expires_at"
    t.bigint "generation_id"
    t.integer "granted_delta", default: 0, null: false
    t.string "kind", null: false
    t.jsonb "metadata", default: {}, null: false
    t.integer "purchased_delta", default: 0, null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id"
    t.bigint "workspace_id", null: false
    t.index ["generation_id"], name: "index_credit_transactions_on_generation_id"
    t.index ["kind", "created_at"], name: "index_credit_transactions_on_kind_and_created_at"
    t.index ["user_id"], name: "index_credit_transactions_on_user_id"
    t.index ["workspace_id", "created_at"], name: "index_credit_transactions_on_workspace_id_and_created_at"
    t.index ["workspace_id"], name: "index_credit_transactions_on_workspace_id"
  end

  create_table "credit_wallets", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "granted_balance", default: 0, null: false
    t.datetime "granted_expires_at"
    t.integer "purchased_balance", default: 0, null: false
    t.datetime "updated_at", null: false
    t.bigint "workspace_id", null: false
    t.index ["workspace_id"], name: "index_credit_wallets_on_workspace_id", unique: true
  end

  create_table "generations", force: :cascade do |t|
    t.integer "cost_cents"
    t.datetime "created_at", null: false
    t.bigint "creative_id"
    t.string "external_id"
    t.string "failure_reason"
    t.integer "kind", default: 0, null: false
    t.datetime "metered_at"
    t.jsonb "params", default: {}, null: false
    t.string "provider"
    t.jsonb "result", default: {}, null: false
    t.integer "status", default: 0, null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id"
    t.bigint "workspace_id", null: false
    t.index ["creative_id"], name: "index_generations_on_creative_id"
    t.index ["external_id"], name: "index_generations_on_external_id"
    t.index ["user_id"], name: "index_generations_on_user_id"
    t.index ["workspace_id", "kind", "status"], name: "index_generations_on_workspace_id_and_kind_and_status"
    t.index ["workspace_id"], name: "index_generations_on_workspace_id"
  end

  create_table "invoice_projects", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "invoice_id", null: false
    t.bigint "project_id", null: false
    t.datetime "updated_at", null: false
    t.index ["invoice_id", "project_id"], name: "index_invoice_projects_on_invoice_id_and_project_id", unique: true
    t.index ["invoice_id"], name: "index_invoice_projects_on_invoice_id"
    t.index ["project_id"], name: "index_invoice_projects_on_project_id"
  end

  create_table "invoices", force: :cascade do |t|
    t.integer "amount_cents", default: 0, null: false
    t.bigint "client_id", null: false
    t.datetime "created_at", null: false
    t.string "currency", default: "BRL", null: false
    t.text "description"
    t.date "due_date"
    t.string "external_reference"
    t.integer "status", default: 0, null: false
    t.datetime "updated_at", null: false
    t.bigint "workspace_id", null: false
    t.index ["client_id"], name: "index_invoices_on_client_id"
    t.index ["external_reference"], name: "index_invoices_on_external_reference", unique: true, where: "(external_reference IS NOT NULL)"
    t.index ["workspace_id", "status"], name: "index_invoices_on_workspace_id_and_status"
    t.index ["workspace_id"], name: "index_invoices_on_workspace_id"
  end

  create_table "mcp_call_logs", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "error_class"
    t.bigint "oauth_application_id"
    t.boolean "ok", default: true, null: false
    t.string "scope"
    t.string "tool_name", null: false
    t.bigint "user_id"
    t.bigint "workspace_id"
    t.index ["oauth_application_id"], name: "index_mcp_call_logs_on_oauth_application_id"
    t.index ["tool_name"], name: "index_mcp_call_logs_on_tool_name"
    t.index ["user_id"], name: "index_mcp_call_logs_on_user_id"
    t.index ["workspace_id", "created_at"], name: "index_mcp_call_logs_on_workspace_id_and_created_at"
    t.index ["workspace_id"], name: "index_mcp_call_logs_on_workspace_id"
  end

  create_table "meetings", force: :cascade do |t|
    t.jsonb "attendees", default: [], null: false
    t.bigint "client_id"
    t.datetime "created_at", null: false
    t.datetime "ends_at"
    t.string "google_event_id"
    t.string "meet_url"
    t.text "notes"
    t.bigint "project_id"
    t.datetime "starts_at", null: false
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id"
    t.bigint "workspace_id", null: false
    t.index ["client_id"], name: "index_meetings_on_client_id"
    t.index ["project_id"], name: "index_meetings_on_project_id"
    t.index ["user_id"], name: "index_meetings_on_user_id"
    t.index ["workspace_id", "starts_at"], name: "index_meetings_on_workspace_id_and_starts_at"
    t.index ["workspace_id"], name: "index_meetings_on_workspace_id"
  end

  create_table "memberships", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "role", default: 3, null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.bigint "workspace_id", null: false
    t.index ["user_id"], name: "index_memberships_on_user_id"
    t.index ["workspace_id", "user_id"], name: "index_memberships_on_workspace_id_and_user_id", unique: true
    t.index ["workspace_id"], name: "index_memberships_on_workspace_id"
  end

  create_table "notes", force: :cascade do |t|
    t.text "body"
    t.datetime "created_at", null: false
    t.integer "kind", default: 0, null: false
    t.jsonb "mentioned_user_ids", default: [], null: false
    t.bigint "ticket_id", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id"
    t.bigint "workspace_id", null: false
    t.index ["ticket_id", "created_at"], name: "index_notes_on_ticket_id_and_created_at"
    t.index ["ticket_id"], name: "index_notes_on_ticket_id"
    t.index ["user_id"], name: "index_notes_on_user_id"
    t.index ["workspace_id"], name: "index_notes_on_workspace_id"
  end

  create_table "oauth_access_grants", force: :cascade do |t|
    t.bigint "application_id", null: false
    t.string "code_challenge"
    t.string "code_challenge_method"
    t.datetime "created_at", null: false
    t.integer "expires_in", null: false
    t.text "redirect_uri", null: false
    t.bigint "resource_owner_id", null: false
    t.datetime "revoked_at"
    t.string "scopes", default: "", null: false
    t.string "token", null: false
    t.index ["application_id"], name: "index_oauth_access_grants_on_application_id"
    t.index ["resource_owner_id"], name: "index_oauth_access_grants_on_resource_owner_id"
    t.index ["token"], name: "index_oauth_access_grants_on_token", unique: true
  end

  create_table "oauth_access_tokens", force: :cascade do |t|
    t.bigint "application_id", null: false
    t.datetime "created_at", null: false
    t.integer "expires_in"
    t.string "previous_refresh_token", default: "", null: false
    t.string "refresh_token"
    t.bigint "resource_owner_id"
    t.datetime "revoked_at"
    t.string "scopes"
    t.string "token", null: false
    t.index ["application_id"], name: "index_oauth_access_tokens_on_application_id"
    t.index ["refresh_token"], name: "index_oauth_access_tokens_on_refresh_token", unique: true
    t.index ["resource_owner_id"], name: "index_oauth_access_tokens_on_resource_owner_id"
    t.index ["token"], name: "index_oauth_access_tokens_on_token", unique: true
  end

  create_table "oauth_applications", force: :cascade do |t|
    t.boolean "confidential", default: true, null: false
    t.datetime "created_at", null: false
    t.boolean "dynamically_registered", default: false, null: false
    t.string "name", null: false
    t.text "redirect_uri", null: false
    t.string "registration_access_token"
    t.string "scopes", default: "", null: false
    t.string "secret"
    t.string "uid", null: false
    t.datetime "updated_at", null: false
    t.index ["registration_access_token"], name: "index_oauth_applications_on_registration_access_token", unique: true
    t.index ["uid"], name: "index_oauth_applications_on_uid", unique: true
  end

  create_table "post_metrics", force: :cascade do |t|
    t.datetime "captured_at", null: false
    t.integer "comments", default: 0
    t.datetime "created_at", null: false
    t.integer "likes", default: 0
    t.bigint "post_id", null: false
    t.jsonb "raw", default: {}, null: false
    t.integer "reach", default: 0
    t.integer "saves", default: 0
    t.integer "shares", default: 0
    t.datetime "updated_at", null: false
    t.integer "views", default: 0
    t.index ["post_id", "captured_at"], name: "index_post_metrics_on_post_id_and_captured_at"
    t.index ["post_id"], name: "index_post_metrics_on_post_id"
  end

  create_table "posts", force: :cascade do |t|
    t.text "caption"
    t.datetime "created_at", null: false
    t.string "external_post_id"
    t.string "failure_reason"
    t.jsonb "media", default: {}, null: false
    t.string "permalink"
    t.datetime "published_at"
    t.datetime "scheduled_at"
    t.bigint "social_account_id", null: false
    t.integer "status", default: 0, null: false
    t.bigint "ticket_id", null: false
    t.datetime "unpublished_at"
    t.datetime "updated_at", null: false
    t.bigint "workspace_id", null: false
    t.index ["social_account_id"], name: "index_posts_on_social_account_id"
    t.index ["ticket_id"], name: "index_posts_on_ticket_id"
    t.index ["workspace_id", "scheduled_at"], name: "index_posts_on_workspace_id_and_scheduled_at"
    t.index ["workspace_id", "status"], name: "index_posts_on_workspace_id_and_status"
    t.index ["workspace_id"], name: "index_posts_on_workspace_id"
  end

  create_table "pricing_configs", force: :cascade do |t|
    t.integer "annual_discount_percent", default: 15, null: false
    t.integer "carousel_credits", default: 0, null: false
    t.datetime "created_at", null: false
    t.integer "credit_unit_cents", default: 100, null: false
    t.integer "image_credits", default: 1, null: false
    t.decimal "margin_multiplier", precision: 5, scale: 2, default: "6.5", null: false
    t.integer "trial_days", default: 7, null: false
    t.datetime "updated_at", null: false
    t.decimal "usd_brl", precision: 8, scale: 4, default: "5.4", null: false
    t.integer "video_photoreal_credits_per_15s", default: 30, null: false
    t.integer "video_standard_credits_per_15s", default: 8, null: false
    t.decimal "video_usd_per_sec", precision: 6, scale: 4, default: "0.16", null: false
  end

  create_table "pricing_packs", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.integer "credits", default: 0, null: false
    t.string "key", null: false
    t.string "name", null: false
    t.integer "position", default: 0, null: false
    t.integer "price_cents", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_pricing_packs_on_key", unique: true
  end

  create_table "pricing_plans", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.integer "annual_price_cents", default: 0, null: false
    t.integer "clients", default: 1, null: false
    t.datetime "created_at", null: false
    t.jsonb "features", default: [], null: false
    t.integer "included_credits", default: 0, null: false
    t.string "key", null: false
    t.string "name", null: false
    t.integer "position", default: 0, null: false
    t.integer "price_cents", default: 0, null: false
    t.integer "seats", default: 1, null: false
    t.string "stripe_annual_lookup_key"
    t.string "stripe_annual_price_id"
    t.string "stripe_lookup_key"
    t.string "stripe_price_id"
    t.string "stripe_product_id"
    t.datetime "updated_at", null: false
    t.integer "usd_cents", default: 0, null: false
    t.index ["key"], name: "index_pricing_plans_on_key", unique: true
  end

  create_table "project_reports", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.jsonb "data", default: {}, null: false
    t.datetime "generated_at"
    t.decimal "overall_score", precision: 4, scale: 2
    t.date "period_end"
    t.date "period_start"
    t.bigint "project_id", null: false
    t.integer "status", default: 0, null: false
    t.datetime "updated_at", null: false
    t.bigint "workspace_id", null: false
    t.index ["project_id", "created_at"], name: "index_project_reports_on_project_id_and_created_at"
    t.index ["project_id"], name: "index_project_reports_on_project_id"
    t.index ["workspace_id", "created_at"], name: "index_project_reports_on_workspace_id_and_created_at"
  end

  create_table "projects", force: :cascade do |t|
    t.integer "budget_cents"
    t.bigint "client_id", null: false
    t.string "color", default: "#7C3AED", null: false
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.text "description"
    t.date "ends_on"
    t.string "name", null: false
    t.date "starts_on"
    t.integer "status", default: 4, null: false
    t.datetime "updated_at", null: false
    t.bigint "workspace_id", null: false
    t.index ["client_id"], name: "index_projects_on_client_id"
    t.index ["workspace_id", "status"], name: "index_projects_on_workspace_id_and_status"
    t.index ["workspace_id"], name: "index_projects_on_workspace_id"
  end

  create_table "push_subscriptions", force: :cascade do |t|
    t.text "auth_key", null: false
    t.datetime "created_at", null: false
    t.text "endpoint", null: false
    t.text "p256dh_key", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["endpoint"], name: "index_push_subscriptions_on_endpoint", unique: true
    t.index ["user_id"], name: "index_push_subscriptions_on_user_id"
  end

  create_table "sessions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "expires_at"
    t.string "ip_address"
    t.datetime "last_active_at"
    t.string "token", null: false
    t.datetime "updated_at", null: false
    t.string "user_agent"
    t.bigint "user_id", null: false
    t.bigint "workspace_id"
    t.index ["token"], name: "index_sessions_on_token", unique: true
    t.index ["user_id"], name: "index_sessions_on_user_id"
    t.index ["workspace_id"], name: "index_sessions_on_workspace_id"
  end

  create_table "settings", force: :cascade do |t|
    t.boolean "auto_publish_default", default: false, null: false
    t.string "brand_tone"
    t.datetime "created_at", null: false
    t.text "google_access_token"
    t.datetime "google_calendar_connected_at"
    t.text "google_refresh_token"
    t.text "mercadopago_access_token"
    t.string "mercadopago_user_id"
    t.jsonb "preferences", default: {}, null: false
    t.datetime "updated_at", null: false
    t.bigint "workspace_id", null: false
    t.index ["workspace_id"], name: "index_settings_on_workspace_id", unique: true
  end

  create_table "social_accounts", force: :cascade do |t|
    t.string "avatar_url"
    t.string "channel_id"
    t.string "channel_title"
    t.bigint "client_id", null: false
    t.integer "connection_type", default: 0, null: false
    t.datetime "created_at", null: false
    t.string "default_org_urn"
    t.string "display_name"
    t.string "external_user_id"
    t.string "ig_user_id"
    t.datetime "last_synced_at"
    t.string "member_urn"
    t.text "page_access_token"
    t.string "page_id"
    t.integer "provider", null: false
    t.text "refresh_token"
    t.datetime "refresh_token_expires_at"
    t.datetime "revoked_at"
    t.jsonb "scopes", default: [], null: false
    t.integer "status", default: 0, null: false
    t.datetime "token_expires_at"
    t.string "union_id"
    t.datetime "updated_at", null: false
    t.text "user_access_token"
    t.string "username"
    t.bigint "workspace_id", null: false
    t.index ["client_id", "provider"], name: "index_social_accounts_on_client_id_and_provider"
    t.index ["client_id"], name: "index_social_accounts_on_client_id"
    t.index ["workspace_id", "provider"], name: "index_social_accounts_on_workspace_id_and_provider"
    t.index ["workspace_id"], name: "index_social_accounts_on_workspace_id"
  end

  create_table "strategy_sessions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.jsonb "messages", default: [], null: false
    t.bigint "project_id", null: false
    t.jsonb "proposed_plan", default: {}, null: false
    t.string "status", default: "active", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id"
    t.bigint "workspace_id", null: false
    t.index ["project_id", "status"], name: "index_strategy_sessions_on_project_id_and_status"
    t.index ["project_id"], name: "index_strategy_sessions_on_project_id"
    t.index ["project_id"], name: "index_strategy_sessions_one_per_project", unique: true
    t.index ["user_id"], name: "index_strategy_sessions_on_user_id"
    t.index ["workspace_id", "created_at"], name: "index_strategy_sessions_on_workspace_id_and_created_at"
  end

  create_table "subscriptions", force: :cascade do |t|
    t.datetime "cancel_at"
    t.boolean "card_on_file", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "current_period_end"
    t.string "interval", default: "month", null: false
    t.integer "plan", default: 0, null: false
    t.integer "seats", default: 1, null: false
    t.string "status", default: "trialing"
    t.string "stripe_customer_id"
    t.string "stripe_subscription_id"
    t.datetime "trial_ends_at"
    t.boolean "trial_used", default: false, null: false
    t.datetime "updated_at", null: false
    t.bigint "workspace_id", null: false
    t.index ["workspace_id"], name: "index_subscriptions_on_workspace_id", unique: true
  end

  create_table "subtasks", force: :cascade do |t|
    t.bigint "assignee_id"
    t.datetime "created_at", null: false
    t.boolean "done", default: false, null: false
    t.date "due_date"
    t.decimal "estimate_hours", precision: 5, scale: 2
    t.integer "position", default: 0, null: false
    t.bigint "ticket_id", null: false
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.bigint "workspace_id", null: false
    t.index ["assignee_id", "done"], name: "index_subtasks_on_assignee_id_and_done"
    t.index ["assignee_id"], name: "index_subtasks_on_assignee_id"
    t.index ["ticket_id"], name: "index_subtasks_on_ticket_id"
    t.index ["workspace_id"], name: "index_subtasks_on_workspace_id"
  end

  create_table "ticket_relations", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "kind", default: 0, null: false
    t.bigint "related_ticket_id", null: false
    t.bigint "ticket_id", null: false
    t.datetime "updated_at", null: false
    t.bigint "workspace_id", null: false
    t.index ["related_ticket_id"], name: "index_ticket_relations_on_related_ticket_id"
    t.index ["ticket_id", "related_ticket_id", "kind"], name: "index_ticket_relations_unique", unique: true
    t.index ["ticket_id"], name: "index_ticket_relations_on_ticket_id"
    t.index ["workspace_id"], name: "index_ticket_relations_on_workspace_id"
  end

  create_table "ticket_status_logs", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "from_status"
    t.bigint "ticket_id", null: false
    t.integer "to_status", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id"
    t.bigint "workspace_id", null: false
    t.index ["ticket_id"], name: "index_ticket_status_logs_on_ticket_id"
    t.index ["user_id"], name: "index_ticket_status_logs_on_user_id"
    t.index ["workspace_id"], name: "index_ticket_status_logs_on_workspace_id"
  end

  create_table "tickets", force: :cascade do |t|
    t.jsonb "ai_summaries", default: {}, null: false
    t.string "alert_reason"
    t.datetime "archived_at"
    t.bigint "assignee_id"
    t.string "channels", default: [], null: false, array: true
    t.datetime "created_at", null: false
    t.bigint "created_by_id"
    t.string "creative_type"
    t.string "creative_types", default: [], null: false, array: true
    t.date "due_date"
    t.jsonb "fields", default: {}, null: false
    t.integer "position", default: 0, null: false
    t.integer "priority", default: 1, null: false
    t.bigint "project_id", null: false
    t.datetime "published_at"
    t.datetime "scheduled_at"
    t.integer "status", default: 0, null: false
    t.bigint "strategy_session_id"
    t.string "title"
    t.datetime "updated_at", null: false
    t.bigint "workspace_id", null: false
    t.index ["assignee_id"], name: "index_tickets_on_assignee_id"
    t.index ["created_by_id"], name: "index_tickets_on_created_by_id"
    t.index ["project_id"], name: "index_tickets_on_project_id"
    t.index ["strategy_session_id"], name: "index_tickets_on_strategy_session_id"
    t.index ["workspace_id", "scheduled_at"], name: "index_tickets_on_workspace_id_and_scheduled_at"
    t.index ["workspace_id", "status", "position"], name: "index_tickets_on_workspace_id_and_status_and_position"
    t.index ["workspace_id"], name: "index_tickets_on_workspace_id"
  end

  create_table "users", force: :cascade do |t|
    t.datetime "confirmed_at"
    t.datetime "created_at", null: false
    t.string "email", null: false
    t.text "google_access_token"
    t.datetime "google_calendar_connected_at"
    t.text "google_refresh_token"
    t.string "google_uid"
    t.string "mcp_connector_token"
    t.string "name"
    t.string "password_digest"
    t.string "pending_email"
    t.boolean "staff", default: false, null: false
    t.datetime "updated_at", null: false
    t.index "lower((email)::text)", name: "index_users_on_lower_email", unique: true
    t.index ["google_uid"], name: "index_users_on_google_uid", unique: true, where: "(google_uid IS NOT NULL)"
    t.index ["mcp_connector_token"], name: "index_users_on_mcp_connector_token", unique: true
  end

  create_table "video_configs", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "default_model"
    t.string "default_voice_id"
    t.string "draft_model"
    t.integer "max_duration_seconds", default: 30, null: false
    t.string "music_provider", default: "jamendo", null: false
    t.jsonb "music_tracks", default: {}, null: false
    t.string "provider"
    t.datetime "updated_at", null: false
    t.jsonb "voice_catalog", default: {}, null: false
    t.boolean "voice_dub_in_post", default: false, null: false
  end

  create_table "video_scenes", force: :cascade do |t|
    t.string "aspect_ratio"
    t.text "caption"
    t.integer "cost_cents"
    t.datetime "created_at", null: false
    t.bigint "creative_id", null: false
    t.integer "duration_seconds"
    t.string "external_id"
    t.jsonb "metadata", default: {}, null: false
    t.string "mode"
    t.integer "position", default: 0, null: false
    t.text "prompt"
    t.jsonb "reference_image_urls", default: [], null: false
    t.integer "render_state", default: 0, null: false
    t.string "seed"
    t.datetime "updated_at", null: false
    t.bigint "workspace_id", null: false
    t.index ["creative_id", "position"], name: "index_video_scenes_on_creative_id_and_position"
    t.index ["creative_id"], name: "index_video_scenes_on_creative_id"
    t.index ["workspace_id"], name: "index_video_scenes_on_workspace_id"
  end

  create_table "workspaces", force: :cascade do |t|
    t.string "brand_primary_color", default: "#7C3AED"
    t.string "brand_secondary_color", default: "#F59E0B"
    t.text "brand_voice"
    t.datetime "created_at", null: false
    t.string "default_handle"
    t.boolean "godfathered", default: false, null: false
    t.string "locale", default: "pt-BR", null: false
    t.integer "monthly_credit_limit"
    t.string "name", null: false
    t.boolean "over_seat_limit", default: false, null: false
    t.string "slug", null: false
    t.string "timezone", default: "America/Sao_Paulo", null: false
    t.datetime "updated_at", null: false
    t.index ["slug"], name: "index_workspaces_on_slug", unique: true
  end

  add_foreign_key "account_metrics", "social_accounts"
  add_foreign_key "account_metrics", "workspaces"
  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "admin_audit_logs", "users", column: "staff_user_id"
  add_foreign_key "ai_usage_logs", "users"
  add_foreign_key "ai_usage_logs", "workspaces"
  add_foreign_key "attachments", "notes", on_delete: :nullify
  add_foreign_key "attachments", "tickets"
  add_foreign_key "attachments", "users", column: "uploaded_by_id"
  add_foreign_key "attachments", "workspaces"
  add_foreign_key "autopilot_runs", "tickets"
  add_foreign_key "autopilot_runs", "users"
  add_foreign_key "autopilot_runs", "workspaces"
  add_foreign_key "charges", "invoices"
  add_foreign_key "charges", "workspaces"
  add_foreign_key "clients", "workspaces"
  add_foreign_key "creatives", "clients"
  add_foreign_key "creatives", "creatives", column: "parent_id"
  add_foreign_key "creatives", "tickets"
  add_foreign_key "creatives", "workspaces"
  add_foreign_key "credit_transactions", "generations"
  add_foreign_key "credit_transactions", "users"
  add_foreign_key "credit_transactions", "workspaces"
  add_foreign_key "credit_wallets", "workspaces"
  add_foreign_key "generations", "creatives"
  add_foreign_key "generations", "users"
  add_foreign_key "generations", "workspaces"
  add_foreign_key "invoice_projects", "invoices"
  add_foreign_key "invoice_projects", "projects"
  add_foreign_key "invoices", "clients"
  add_foreign_key "invoices", "workspaces"
  add_foreign_key "mcp_call_logs", "users"
  add_foreign_key "mcp_call_logs", "workspaces"
  add_foreign_key "meetings", "clients"
  add_foreign_key "meetings", "projects"
  add_foreign_key "meetings", "users"
  add_foreign_key "meetings", "workspaces"
  add_foreign_key "memberships", "users"
  add_foreign_key "memberships", "workspaces"
  add_foreign_key "notes", "tickets"
  add_foreign_key "notes", "users"
  add_foreign_key "notes", "workspaces"
  add_foreign_key "oauth_access_grants", "oauth_applications", column: "application_id"
  add_foreign_key "oauth_access_tokens", "oauth_applications", column: "application_id"
  add_foreign_key "post_metrics", "posts"
  add_foreign_key "posts", "social_accounts"
  add_foreign_key "posts", "tickets"
  add_foreign_key "posts", "workspaces"
  add_foreign_key "project_reports", "projects"
  add_foreign_key "project_reports", "workspaces"
  add_foreign_key "projects", "clients"
  add_foreign_key "projects", "workspaces"
  add_foreign_key "push_subscriptions", "users"
  add_foreign_key "sessions", "users"
  add_foreign_key "sessions", "workspaces"
  add_foreign_key "settings", "workspaces"
  add_foreign_key "social_accounts", "clients"
  add_foreign_key "social_accounts", "workspaces"
  add_foreign_key "strategy_sessions", "projects"
  add_foreign_key "strategy_sessions", "users"
  add_foreign_key "strategy_sessions", "workspaces"
  add_foreign_key "subscriptions", "workspaces"
  add_foreign_key "subtasks", "tickets"
  add_foreign_key "subtasks", "users", column: "assignee_id"
  add_foreign_key "subtasks", "workspaces"
  add_foreign_key "ticket_relations", "tickets"
  add_foreign_key "ticket_relations", "tickets", column: "related_ticket_id"
  add_foreign_key "ticket_relations", "workspaces"
  add_foreign_key "ticket_status_logs", "tickets"
  add_foreign_key "ticket_status_logs", "users"
  add_foreign_key "ticket_status_logs", "workspaces"
  add_foreign_key "tickets", "projects"
  add_foreign_key "tickets", "strategy_sessions", on_delete: :nullify
  add_foreign_key "tickets", "users", column: "assignee_id"
  add_foreign_key "tickets", "users", column: "created_by_id"
  add_foreign_key "tickets", "workspaces"
  add_foreign_key "video_scenes", "creatives"
  add_foreign_key "video_scenes", "workspaces"
end
