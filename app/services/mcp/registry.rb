# frozen_string_literal: true

module Mcp
  # Declarative catalogue of MCP tools. Each spec maps a tool to exactly one
  # `Controllers::*` service (the same one the HTTP API calls), so authorization
  # (Pundit), serialization, and side-effect orchestration are inherited — the
  # tool layer adds nothing but the schema, the scope gate, and the tenant
  # context. `Mcp::ToolBuilder` turns each spec into a FastMcp::Tool subclass.
  #
  # Conventions:
  #   scope            :read | :write | :billing  (coarse OAuth capability)
  #   workspace_scoped true  → a required `workspace` arg selects the tenant
  #   params_arg       false → service takes no params (called as `.call`)
  #   wrap             nest writable args under this key (service does
  #                    `params.require(:wrap)`); `top_level` keys stay flat
  #   side_effect      persisted to the audit log; reads are only logged
  #   cost             real money (Stripe-metered generation) — flagged loudly
  #   destructive      irreversible delete/cancel
  module Registry
    Spec = Struct.new(
      :name, :description, :service, :scope, :workspace_scoped, :params_arg,
      :wrap, :top_level, :side_effect, :destructive, :cost, :args,
      keyword_init: true
    )

    DEFAULT_TOP_LEVEL = %i[id ticket_id].freeze

    # Helper to build a spec with defaults.
    def self.t(name, service, description, scope: :read, workspace_scoped: true, params_arg: true,
               wrap: nil, top_level: DEFAULT_TOP_LEVEL, side_effect: false, destructive: false,
               cost: false, &args)
      Spec.new(
        name: name, service: service, description: description, scope: scope,
        workspace_scoped: workspace_scoped, params_arg: params_arg, wrap: wrap,
        top_level: top_level, side_effect: side_effect, destructive: destructive,
        cost: cost, args: args
      )
    end

    SPECS = [
      # ── Account-level (no workspace) ─────────────────────────────────
      # list_workspaces and me are bespoke tools (see Tools::ListWorkspaces / Tools::Me).

      # ── CRM: clients ─────────────────────────────────────────────────
      t('list_clients', 'Controllers::Clients::Index',
        "List the workspace's clients. Read-only.") { |s| s.optional(:status).filled(:string) },
      t('get_client', 'Controllers::Clients::Show',
        'Fetch one client by id. Read-only.') { |s| s.required(:id).filled(:integer) },
      t('create_client', 'Controllers::Clients::Create',
        'Create a client. WRITE.', scope: :write, side_effect: true, wrap: :client) do |s|
        s.required(:name).filled(:string)
        s.optional(:company).filled(:string)
        s.optional(:email).filled(:string)
        s.optional(:phone).filled(:string)
        s.optional(:document).filled(:string)
        s.optional(:notes).filled(:string)
        s.optional(:status).filled(:string)
      end,
      t('update_client', 'Controllers::Clients::Update',
        'Update a client. WRITE.', scope: :write, side_effect: true, wrap: :client) do |s|
        s.required(:id).filled(:integer)
        s.optional(:name).filled(:string)
        s.optional(:company).filled(:string)
        s.optional(:email).filled(:string)
        s.optional(:phone).filled(:string)
        s.optional(:document).filled(:string)
        s.optional(:notes).filled(:string)
        s.optional(:status).filled(:string)
      end,
      t('archive_client', 'Controllers::Clients::Archive',
        'Archive a client. WRITE.', scope: :write, side_effect: true) { |s| s.required(:id).filled(:integer) },
      t('delete_client', 'Controllers::Clients::Destroy',
        'Permanently delete a client. DESTRUCTIVE.', scope: :write, side_effect: true,
                                                     destructive: true) { |s| s.required(:id).filled(:integer) },

      # ── Projects ─────────────────────────────────────────────────────
      t('list_projects', 'Controllers::Projects::Index', 'List projects. Read-only.') do |s|
        s.optional(:client_id).filled(:integer)
        s.optional(:status).filled(:string)
      end,
      t('get_project', 'Controllers::Projects::Show',
        'Fetch one project (with its tickets). Read-only.') { |s| s.required(:id).filled(:integer) },
      t('create_project', 'Controllers::Projects::Create',
        'Create a project for a client. WRITE.', scope: :write, side_effect: true, wrap: :project) do |s|
        s.required(:client_id).filled(:integer)
        s.required(:name).filled(:string)
        s.optional(:description).filled(:string)
        s.optional(:color).filled(:string)
        s.optional(:status).filled(:string)
        s.optional(:starts_on).filled(:string)
        s.optional(:ends_on).filled(:string)
        s.optional(:budget_cents).filled(:integer)
      end,
      t('update_project', 'Controllers::Projects::Update',
        'Update a project. WRITE.', scope: :write, side_effect: true, wrap: :project) do |s|
        s.required(:id).filled(:integer)
        s.optional(:client_id).filled(:integer)
        s.optional(:name).filled(:string)
        s.optional(:description).filled(:string)
        s.optional(:color).filled(:string)
        s.optional(:status).filled(:string)
        s.optional(:starts_on).filled(:string)
        s.optional(:ends_on).filled(:string)
        s.optional(:budget_cents).filled(:integer)
      end,
      t('delete_project', 'Controllers::Projects::Destroy',
        'Permanently delete a project. DESTRUCTIVE.', scope: :write, side_effect: true,
                                                      destructive: true) { |s| s.required(:id).filled(:integer) },

      # ── Board, tickets & funnel ──────────────────────────────────────
      t('get_board', 'Controllers::Board::Index',
        'The kanban board: the 7 funnel columns with their ticket cards. Read-only.') do |s|
        s.optional(:project_id).filled(:integer)
        s.optional(:client_id).filled(:integer)
        s.optional(:assignee_id).filled(:integer)
        s.optional(:creative_type).filled(:string)
        s.optional(:channel).filled(:string)
      end,
      t('list_tickets', 'Controllers::Tickets::Index', 'List tickets. Read-only.') do |s|
        s.optional(:status).filled(:string)
        s.optional(:project_id).filled(:integer)
      end,
      t('get_ticket', 'Controllers::Tickets::Show',
        'Fetch one ticket (status-contextual view, subtasks, creatives, notes). Read-only.') do |s|
        s.required(:id).filled(:integer)
      end,
      t('create_ticket', 'Controllers::Tickets::Create',
        "Create a ticket (a unit of agency work) in a project. WRITE. Starts in 'ideation'.",
        scope: :write, side_effect: true, wrap: :ticket) do |s|
        s.required(:project_id).filled(:integer)
        s.optional(:title).filled(:string)
        s.optional(:assignee_id).filled(:integer)
        s.optional(:priority).filled(:string).description('low | medium | high')
        s.optional(:due_date).filled(:string)
        s.optional(:scheduled_at).filled(:string)
        s.optional(:creative_type).filled(:string).description('reel | carousel | feed_image | story | ugc_video | ad | thumbnail')
        s.optional(:channels).array(:string)
      end,
      t('update_ticket', 'Controllers::Tickets::Update',
        "Update a ticket's attributes and/or status-specific fields. WRITE. " \
        'Does NOT move the board column — use advance_ticket for status changes.',
        scope: :write, side_effect: true, wrap: :ticket) do |s|
        s.required(:id).filled(:integer)
        s.optional(:title).filled(:string)
        s.optional(:project_id).filled(:integer)
        s.optional(:assignee_id).filled(:integer)
        s.optional(:priority).filled(:string)
        s.optional(:due_date).filled(:string)
        s.optional(:scheduled_at).filled(:string)
        s.optional(:creative_type).filled(:string)
        s.optional(:channels).array(:string)
        s.optional(:fields).value(:hash).description('Status-specific field values (jsonb).')
      end,
      t('advance_ticket', 'Controllers::Tickets::Advance',
        'Move a ticket to a new funnel status (the authoritative board move). WRITE. ' \
        'Statuses: ideation → scoping → production → scheduled → published → retrospective → done.',
        scope: :write, side_effect: true) do |s|
        s.required(:id).filled(:integer)
        s.required(:to_status).filled(:string)
        s.optional(:position).filled(:integer)
      end,
      t('reorder_ticket', 'Controllers::Tickets::Reorder',
        'Reposition a ticket within its board column. WRITE.', scope: :write, side_effect: true) do |s|
        s.required(:id).filled(:integer)
        s.required(:position).filled(:integer)
      end,
      t('summarize_ticket', 'Controllers::Tickets::Summarize',
        "Regenerate the ticket's status-aware AI summary now. WRITE (enqueues AI work).",
        scope: :write, side_effect: true) { |s| s.required(:id).filled(:integer) },
      t('ticket_ai_action', 'Controllers::Tickets::AiAction',
        "Run the AI action for the ticket's current status (idea synthesis, scope build, etc.). WRITE.",
        scope: :write, side_effect: true) { |s| s.required(:id).filled(:integer) },

      # ── Subtasks ─────────────────────────────────────────────────────
      t('create_subtask', 'Controllers::Subtasks::Create',
        'Add a subtask to a ticket. WRITE.', scope: :write, side_effect: true, wrap: :subtask) do |s|
        s.required(:ticket_id).filled(:integer)
        s.required(:title).filled(:string)
        s.optional(:assignee_id).filled(:integer)
        s.optional(:due_date).filled(:string)
      end,
      t('update_subtask', 'Controllers::Subtasks::Update',
        'Update a subtask (title, done, due date, assignee, position). WRITE.',
        scope: :write, side_effect: true, wrap: :subtask) do |s|
        s.required(:id).filled(:integer)
        s.optional(:title).filled(:string)
        s.optional(:done).filled(:bool)
        s.optional(:due_date).filled(:string)
        s.optional(:position).filled(:integer)
        s.optional(:assignee_id).filled(:integer)
      end,
      t('delete_subtask', 'Controllers::Subtasks::Destroy',
        'Delete a subtask. DESTRUCTIVE.', scope: :write, side_effect: true,
                                          destructive: true) { |s| s.required(:id).filled(:integer) },

      # ── Notes ────────────────────────────────────────────────────────
      t('list_notes', 'Controllers::Notes::Index',
        "List a ticket's notes. Read-only.") { |s| s.required(:ticket_id).filled(:integer) },
      t('create_note', 'Controllers::Notes::Create',
        'Add a note to a ticket. WRITE.', scope: :write, side_effect: true, wrap: :note) do |s|
        s.required(:ticket_id).filled(:integer)
        s.required(:body).filled(:string)
      end,

      # ── Posts (scheduled/published on a network) ─────────────────────
      t('list_posts', 'Controllers::Posts::Index',
        "List a ticket's posts. Read-only.") { |s| s.required(:ticket_id).filled(:integer) },
      t('create_post', 'Controllers::Posts::Create',
        'Schedule a post for a ticket on a connected social account. WRITE.',
        scope: :write, side_effect: true, wrap: :post) do |s|
        s.required(:ticket_id).filled(:integer)
        s.required(:social_account_id).filled(:integer)
        s.optional(:caption).filled(:string)
        s.optional(:scheduled_at).filled(:string)
      end,
      t('update_post', 'Controllers::Posts::Update',
        'Update a scheduled post (caption, scheduled_at). WRITE.',
        scope: :write, side_effect: true, wrap: :post) do |s|
        s.required(:ticket_id).filled(:integer)
        s.required(:id).filled(:integer)
        s.optional(:caption).filled(:string)
        s.optional(:scheduled_at).filled(:string)
      end,
      t('delete_post', 'Controllers::Posts::Destroy',
        'Delete a post. DESTRUCTIVE.', scope: :write, side_effect: true, destructive: true) do |s|
        s.required(:ticket_id).filled(:integer)
        s.required(:id).filled(:integer)
      end,

      # ── Creatives & generation ───────────────────────────────────────
      t('list_creatives', 'Controllers::Creatives::Index',
        "List a ticket's creatives. Read-only.") { |s| s.required(:ticket_id).filled(:integer) },
      t('create_creative', 'Controllers::Creatives::Create',
        'Register a creative on a ticket (metadata only; file upload is not available over MCP). WRITE.',
        scope: :write, side_effect: true) do |s|
        s.required(:ticket_id).filled(:integer)
        s.required(:creative_type).filled(:string)
        s.optional(:caption).filled(:string)
        s.optional(:metadata).value(:hash)
      end,
      t('delete_creative', 'Controllers::Creatives::Destroy',
        'Delete a creative. DESTRUCTIVE.', scope: :write, side_effect: true, destructive: true) do |s|
        s.required(:ticket_id).filled(:integer)
        s.required(:id).filled(:integer)
      end,
      t('generate_creative', 'Controllers::Creatives::Generate',
        "Generate a creative via an AI vendor. WRITE. WARNING: 'carousel' and 'video' generations " \
        "are BILLED to the workspace's plan (Stripe usage meter). Confirm with the user first.",
        scope: :write, side_effect: true, cost: true) do |s|
        s.required(:ticket_id).filled(:integer)
        s.required(:kind).filled(:string).description('carousel | video | image')
        s.optional(:params).value(:hash)
      end,
      t('list_generations', 'Controllers::Generations::Index',
        'List generation runs (usage history). Read-only.') { |s| s.optional(:kind).filled(:string) },
      t('get_generation', 'Controllers::Generations::Show',
        'Fetch one generation run. Read-only.') { |s| s.required(:id).filled(:integer) },
      t('studio_generate', 'Controllers::Studio::Generate',
        "Generate a creative from the standalone studio. WRITE. WARNING: 'carousel'/'video' kinds " \
        "are BILLED to the workspace's plan. Confirm with the user first.",
        scope: :write, side_effect: true, cost: true) do |s|
        s.required(:kind).filled(:string).description('carousel | video | image')
        s.optional(:params).value(:hash)
      end,
      t('get_studio', 'Controllers::Studio::Index',
        'Studio context (brand identity, defaults). Read-only.', params_arg: false),

      # ── Calendar, tasks, dashboard ───────────────────────────────────
      t('get_calendar', 'Controllers::Calendar::Index',
        'Scheduled posts + meetings in a date window. Read-only.') do |s|
        s.optional(:from).filled(:string).description('ISO 8601; defaults to start of month')
        s.optional(:to).filled(:string).description('ISO 8601; defaults to end of month')
      end,
      t('list_my_tasks', 'Controllers::Tasks::Index',
        "The current user's subtasks. Read-only.") do |s|
        s.optional(:scope).filled(:string).description("'all_workspaces' to span every workspace; omit for this one")
      end,
      t('get_dashboard', 'Controllers::Dashboard::Index',
        'Workspace dashboard metrics. Read-only.', params_arg: false),

      # ── Meetings ─────────────────────────────────────────────────────
      t('list_meetings', 'Controllers::Meetings::Index', 'List meetings. Read-only.') do |s|
        s.optional(:from).filled(:string)
        s.optional(:to).filled(:string)
      end,
      t('get_meeting', 'Controllers::Meetings::Show',
        'Fetch one meeting. Read-only.') { |s| s.required(:id).filled(:integer) },
      t('create_meeting', 'Controllers::Meetings::Create',
        'Create a meeting (Google Calendar + Meet). WRITE.',
        scope: :write, side_effect: true, wrap: :meeting) do |s|
        s.required(:title).filled(:string)
        s.optional(:starts_at).filled(:string)
        s.optional(:ends_at).filled(:string)
        s.optional(:notes).filled(:string)
        s.optional(:client_id).filled(:integer)
        s.optional(:project_id).filled(:integer)
        s.optional(:attendees).array(:string)
      end,
      t('update_meeting', 'Controllers::Meetings::Update',
        'Update a meeting. WRITE.', scope: :write, side_effect: true, wrap: :meeting) do |s|
        s.required(:id).filled(:integer)
        s.optional(:title).filled(:string)
        s.optional(:starts_at).filled(:string)
        s.optional(:ends_at).filled(:string)
        s.optional(:notes).filled(:string)
        s.optional(:client_id).filled(:integer)
        s.optional(:project_id).filled(:integer)
        s.optional(:attendees).array(:string)
      end,
      t('delete_meeting', 'Controllers::Meetings::Destroy',
        'Delete a meeting. DESTRUCTIVE.', scope: :write, side_effect: true,
                                          destructive: true) { |s| s.required(:id).filled(:integer) },

      # ── Client billing (Mercado Pago invoices) ───────────────────────
      t('list_invoices', 'Controllers::Invoices::Index', 'List client invoices. Read-only.') do |s|
        s.optional(:status).filled(:string)
        s.optional(:client_id).filled(:integer)
      end,
      t('get_invoice', 'Controllers::Invoices::Show',
        'Fetch one invoice. Read-only.') { |s| s.required(:id).filled(:integer) },
      t('create_invoice', 'Controllers::Invoices::Create',
        'Register a client invoice (the agency charging its client). No payment is opened — ' \
        'generate a payment link or mark it paid afterwards. WRITE.',
        scope: :write, side_effect: true, wrap: :invoice) do |s|
        s.required(:client_id).filled(:integer)
        s.required(:amount_cents).filled(:integer)
        s.optional(:description).filled(:string)
        s.optional(:due_date).filled(:string)
        s.optional(:project_ids).array(:integer)
      end,
      t('update_invoice', 'Controllers::Invoices::Update',
        'Update an invoice (description, due date, status, amount). WRITE.',
        scope: :write, side_effect: true, wrap: :invoice) do |s|
        s.required(:id).filled(:integer)
        s.optional(:description).filled(:string)
        s.optional(:due_date).filled(:string)
        s.optional(:status).filled(:string)
        s.optional(:amount_cents).filled(:integer)
      end,
      t('send_invoice', 'Controllers::Invoices::SendInvoice',
        'Send an invoice to the client. WRITE.', scope: :write, side_effect: true) do |s|
        s.required(:id).filled(:integer)
      end,
      t('mark_invoice_paid', 'Controllers::Invoices::MarkPaid',
        'Manually settle an invoice (client paid out-of-band). WRITE.',
        scope: :write, side_effect: true, wrap: :invoice) { |s| s.required(:id).filled(:integer) },
      t('generate_invoice_payment_link', 'Controllers::Invoices::GeneratePaymentLink',
        'Generate a hosted payment link for an invoice (Mercado Pago Checkout Pro). WRITE.',
        scope: :write, side_effect: true, wrap: :invoice) { |s| s.required(:id).filled(:integer) },
      t('cancel_invoice', 'Controllers::Invoices::Cancel',
        'Cancel an invoice. DESTRUCTIVE.', scope: :write, side_effect: true,
                                           destructive: true) { |s| s.required(:id).filled(:integer) },

      # ── Social accounts ──────────────────────────────────────────────
      t('list_social_accounts', 'Controllers::SocialAccounts::Index',
        'List connected social accounts. Read-only.', params_arg: false),
      t('get_social_authorize_url', 'Controllers::SocialAccounts::AuthorizeUrl',
        'Get the OAuth URL to connect a social network. Read-only.') do |s|
        s.required(:network).filled(:string).description('instagram | facebook | tiktok | youtube | linkedin | x')
      end,
      t('reconnect_social_account', 'Controllers::SocialAccounts::Reconnect',
        'Begin reconnecting an expired social account. WRITE.',
        scope: :write, side_effect: true) { |s| s.required(:id).filled(:integer) },
      t('delete_social_account', 'Controllers::SocialAccounts::Destroy',
        'Disconnect a social account. DESTRUCTIVE.', scope: :write, side_effect: true,
                                                     destructive: true) { |s| s.required(:id).filled(:integer) },

      # ── Settings & workspace ─────────────────────────────────────────
      t('get_settings', 'Controllers::Settings::Show',
        'Workspace settings (brand identity, integration status). Read-only.', params_arg: false),
      t('update_settings', 'Controllers::Settings::Update',
        'Update workspace settings. WRITE. Pass a `setting` object (brand_tone, auto_publish_default, preferences).',
        scope: :write, side_effect: true) do |s|
        s.required(:setting).value(:hash)
      end,
      t('get_workspace', 'Controllers::Workspaces::Show',
        "The active workspace's details. Read-only.", params_arg: false),
      t('update_workspace', 'Controllers::Workspaces::Update',
        'Update workspace identity (name, brand voice, default handle, colors). WRITE.',
        scope: :write, side_effect: true, wrap: :workspace) do |s|
        s.optional(:name).filled(:string)
        s.optional(:timezone).filled(:string)
        s.optional(:locale).filled(:string)
        s.optional(:brand_voice).filled(:string)
        s.optional(:default_handle).filled(:string)
        s.optional(:brand_primary_color).filled(:string)
        s.optional(:brand_secondary_color).filled(:string)
      end,

      # ── Members & invitations ────────────────────────────────────────
      t('list_members', 'Controllers::Memberships::Index',
        'List workspace members. Read-only.', params_arg: false),
      t('update_member', 'Controllers::Memberships::Update',
        "Change a member's role. WRITE.", scope: :write, side_effect: true) do |s|
        s.required(:id).filled(:integer)
        s.required(:role).filled(:string).description('owner | admin | manager | member | guest')
      end,
      t('remove_member', 'Controllers::Memberships::Destroy',
        'Remove a member from the workspace. DESTRUCTIVE.', scope: :write, side_effect: true,
                                                            destructive: true) { |s| s.required(:id).filled(:integer) },
      t('list_invitations', 'Controllers::Invitations::Index',
        'List pending invitations. Read-only.', params_arg: false),
      t('create_invitation', 'Controllers::Invitations::Create',
        'Invite a person to the workspace by email. WRITE.', scope: :write, side_effect: true) do |s|
        s.required(:email).filled(:string)
        s.required(:role).filled(:string).description('admin | manager | member | guest')
      end,

      # ── SaaS plan billing (the workspace's own Stripe subscription) ──
      t('get_billing', 'Controllers::Billing::Show',
        "The workspace's own SaaS subscription + usage. Read-only.", params_arg: false),
      t('billing_change_plan', 'Controllers::Billing::ChangePlan',
        "Change the workspace's SaaS plan. BILLING.", scope: :billing, side_effect: true) do |s|
        s.required(:plan).filled(:string).description('solo | agencia | enterprise')
      end,
      t('billing_checkout', 'Controllers::Billing::CheckoutSession',
        'Create a Stripe checkout session for a plan. BILLING.', scope: :billing, side_effect: true) do |s|
        s.optional(:plan).filled(:string)
      end,
      t('billing_portal', 'Controllers::Billing::Portal',
        'Get the Stripe customer-portal URL. BILLING.', scope: :billing, side_effect: true,
                                                        params_arg: false),
      t('billing_cancel', 'Controllers::Billing::Cancel',
        'Schedule cancellation of the SaaS subscription. BILLING / DESTRUCTIVE.',
        scope: :billing, side_effect: true, destructive: true, params_arg: false),
      t('billing_reactivate', 'Controllers::Billing::Reactivate',
        'Undo a scheduled SaaS cancellation. BILLING.', scope: :billing, side_effect: true,
                                                        params_arg: false)
    ].freeze
    # Build the FastMcp::Tool subclasses for every spec. Built fresh each call so
    # a dev code-reload never hands back classes closed over stale constants.
    def self.tool_classes
      SPECS.map { |spec| Mcp::ToolBuilder.build(spec) }
    end
  end
end
