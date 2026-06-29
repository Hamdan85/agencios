# agencios — Project Structure

The operating system of a social-media / creative agency.
**Rails 8.1 JSON API** (`/api/v1`) + **React 19 SPA** (Vite, Tailwind v4, TanStack Query, @dnd-kit),
strict service layer, Sidekiq + Action Cable, direct integrations to every network and billing rail.

```
agencios/
├── CLAUDE.md                     # working agreement (the rules of the codebase)
├── README.md                     # quick start + demo login
├── Procfile.dev                  # web (Rails) · vite · worker (Sidekiq)
├── Gemfile                       # Rails 8.1, pg, sidekiq, pundit, stripe, google-apis, faraday…
├── package.json                  # React 19, Vite, Tailwind v4, Radix, @dnd-kit, TanStack Query
├── vite.config.ts · jsconfig.json
├── docs/
│   ├── ARCHITECTURE.md · SPECIFICATION.md · STRUCTURE.md (this file)
│   └── integrations/             # one playbook per vendor (meta, tiktok, youtube, …, stripe, mercado-pago)
│
├── config/
│   ├── routes.rb                 # /api/v1 · /auth/:provider/callback · /webhooks/* · ActionCable · SPA catch-all
│   ├── database.yml · cable.yml (redis) · sidekiq.yml (5 queues) · schedule.yml (sidekiq-cron)
│   ├── puma.rb · storage.yml (S3) · application.rb
│   └── initializers/
│       ├── sidekiq.rb            # redis + ActiveJob adapter + loads schedule.yml on boot
│       ├── active_record_encryption.rb   # keys for the `encrypts` token columns
│       ├── content_security_policy.rb · filter_parameter_logging.rb · inflections.rb · assets.rb
│
├── db/
│   └── migrate/                  # 8 domain migrations + AS tables + 2 social-column add-ons
│       ├── …_create_tenancy.rb           # users, workspaces, memberships, sessions, settings, subscriptions
│       ├── …_create_crm.rb               # clients, projects
│       ├── …_create_tickets_domain.rb    # tickets, ticket_status_logs, notes, subtasks
│       ├── …_create_creatives.rb         # creatives, generations
│       ├── …_create_social.rb            # social_accounts, posts, post_metrics
│       ├── …_create_meetings.rb          # meetings
│       ├── …_create_client_billing.rb    # invoices, invoice_projects, charges
│       └── …_add_{tiktok,youtube}_columns_to_social_accounts.rb
│
└── app/
    ├── models/                   # AR: associations, enums, scopes, pure derivations — NO callbacks
    │   ├── current.rb            # ActiveSupport::CurrentAttributes (session, workspace, membership)
    │   ├── user.rb · session.rb · workspace.rb · membership.rb · setting.rb · subscription.rb
    │   ├── client.rb · project.rb
    │   ├── ticket.rb             # WORKFLOW + STATUS_LABELS; status only via ChangeStatus
    │   ├── ticket_status_log.rb · note.rb · subtask.rb
    │   ├── creative.rb · generation.rb
    │   ├── social_account.rb     # provider enum (6 networks, encrypted tokens)
    │   ├── post.rb · post_metric.rb
    │   ├── meeting.rb
    │   ├── invoice.rb · invoice_project.rb · charge.rb
    │   ├── broadcaster.rb        # never-raising Action Cable facade
    │   └── system_config.rb      # APP_HOST etc.
    │
    ├── controllers/
    │   ├── application_controller.rb · spa_controller.rb   # serves the React shell
    │   ├── concerns/authentication.rb                       # session cookie → Current (tenant resolution)
    │   ├── api/v1/                                          # 30 thin REST controllers → Controllers::*/Operations::*
    │   │   ├── base_controller.rb (auth + Pundit + CSRF + error mapping)
    │   │   ├── sessions · registrations · password_resets · me · workspaces · memberships · invitations
    │   │   ├── clients · projects · board · tickets · subtasks · tasks · calendar · notes · posts
    │   │   ├── creatives · studio · generations
    │   │   ├── social_accounts (+ authorize_url) · meetings · invoices · settings · billing · dashboard
    │   ├── auth/omniauth_controller.rb                      # social OAuth callback → ConnectAccount
    │   └── webhooks/                                        # stripe · mercado_pago · heygen · meta (signature-verified)
    │
    ├── channels/                 # Action Cable
    │   ├── application_cable/{connection,channel}.rb
    │   ├── ticket_channel.rb · board_channel.rb · generations_channel.rb
    │
    ├── serializers/              # ActiveModel::Serializer (ISO 8601 dates, money in cents) — 18 files
    │   └── {ticket,ticket_card,subtask,note,post,creative,generation,client,project,invoice,
    │        meeting,setting,subscription,social_account,workspace,membership,user,my_task}_serializer.rb
    │
    ├── policies/                 # Pundit, keyed on Membership role — 10 files (application + per-entity)
    │
    ├── jobs/                     # thin → Operations::*
    │   ├── application_job.rb (retry/discard + billing gate)
    │   ├── summarize_ticket_job · draft_retrospective_job
    │   ├── publish_post_job · monitor_scheduled_posts_job · posts/sync_metrics_job
    │   ├── social/refresh_token_job · purge_expired_sessions_job
    │   ├── reconcile_seats_job (Stripe) · invoices/reconcile_job (Mercado Pago sweep)
    │   ├── sync_mercado_pago_payment_job · poll_heygen_video_job
    │
    ├── adapters/ai_adapter.rb    # Anthropic facade for the AI operations
    │
    └── services/                 # ★ the heart — every class is `.call`
        ├── controllers/base.rb           # HTTP-layer service base (serialize helpers)
        ├── operations/                   # domain ops — own ALL side effects
        │   ├── base.rb · errors.rb
        │   ├── tickets/  change_status.rb ★ (the single status authority) · create · update · update_fields · reorder
        │   ├── subtasks/create · notes/create
        │   ├── ai/  summarize_ticket · synthesize_idea · build_scope
        │   ├── creatives/  create · generate_carousel · generate_ugc_video · generate_image · finalize_generation
        │   ├── generations/run            # studio dispatcher
        │   ├── posts/  publish · sync_metrics
        │   ├── social/  connect_account · refresh_token
        │   ├── clients/{create,archive} · projects/create · invoices/create
        │   ├── meetings/{create,sync_to_calendar}
        │   ├── billing/  record_usage (Stripe meters) · sync_subscription · sync_payment_status (MP)
        │   ├── users/register · workspaces/setup_for_user
        ├── publishers/social_publisher.rb # ★ the publish seam (provider → direct vendor)
        ├── prompts/                       # status-aware AI prompt builders
        │   └── base · ticket_summary · idea_synthesis · scope_builder · caption_writer · carousel_copy · retrospective · best_time_to_post
        ├── creatives.rb + creatives/      # creative-type registry: reel, feed_image, carousel, story, ugc_video, ad, thumbnail, cover
        ├── tickets/fields.rb              # per-status allowed-field map (Tickets::Fields)
        └── vendors/                       # ★ third-party wrappers (Client + Actions::*) — all external knowledge
            ├── base.rb                    # Faraday + retry + error mapping + credential(:vendor, :key)
            ├── meta/      (IG + FB, one app)  client · webhook · 34 actions (containers, reels, resumable video, insights, oauth)
            │   └── …including the uniform seam: publish_post · sync_insights · authorize_url · connect_account · refresh_token
            ├── tik_tok/   client · webhook · 13 actions (content posting + uniform seam)
            ├── youtube/   client · 12 actions (resumable upload, analytics + uniform seam)
            ├── linkedin/  client · 21 actions (Posts API, org analytics + uniform seam)
            ├── x/         client · 12 actions (v2 + PKCE + media upload + uniform seam)
            ├── stripe/    client · webhook · checkout · portal · report_meter_event
            ├── mercado_pago/ client · webhook · create_payment (Pix) · get_payment · create_preference · oauth
            ├── heygen/    client · webhook · error · 10 actions (avatar/template/render/poll)
            ├── image_gen/ client · error · generate_image
            ├── anthropic/ client            # real Messages API + deterministic stub fallback
            └── google/    calendar.rb        # Google Calendar + Meet

app/frontend/                                # React 19 SPA — Portuguese routes, bold/iconographic design
├── entrypoints/  application.jsx (mount + providers) · application.css (Tailwind v4)
├── styles/theme.css                         # ★ design tokens: brand violet, 7 status colors, gradients
├── App.jsx                                  # router: / (landing) · /login · /cadastro · protected app
├── api/  client.js (axios+CSRF) · index.js (resources) · queryKeys.js
├── lib/  utils.js (cn) · formatters.js (dt/brl/relativeDay) · constants.js (★ STATUS/CHANNEL/CREATIVE meta) · cable.js
├── hooks/  useAuth · useBoard · useTicket · useData (all resources) · useRealtime (Action Cable)
├── components/
│   ├── ui/         button · card · badge · input · select · dialog · dropdown-menu · tabs · switch ·
│   │               popover · date-picker · avatar · label · iconography · feedback · page-header
│   ├── layout/     Layout · Sidebar (colorful nav) · navItems
│   ├── board/      TicketCard · BoardColumn · BoardFilters · NewTicketDialog   (the Kanban)
│   ├── ticket/     StatusStepper · AiSummaryCard · FieldGroup · CreativesPanel · MetaCard · SubtasksPanel · ActivityFeed
│   ├── calendar/   EventChip · MeetingDialog · calendarUtils
│   ├── studio/     GeneratorCard · GenerateDialog
│   └── shared/     ProtectedRoute (+ GuestRoute)
└── pages/                                   # one dir per domain
    ├── Landing/Index                        # public marketing site
    ├── Auth/  Login · Register · AuthShell
    ├── Dashboard/Index   (/painel)
    ├── Board/Index       (/quadro — Kanban DnD)
    ├── Tickets/Show      (/tickets/:id — contextual, per-status)
    ├── Calendar/Index    (/calendario)
    ├── Tasks/Index       (/tarefas)
    ├── Projects/{Index,Show}   · Clients/{Index,Show}
    ├── Studio/Index      (/estudio — AI generation)
    ├── Meetings/Index    · Invoices/Index   · Settings/Index   · Billing/Index
```

## The request lifecycle

```
Browser (React SPA) ──JSON /api/v1──▶ thin controller ──▶ Controllers::* / Operations::*
                    ◀──WebSocket /cable──  Action Cable (ticket_<id> · board_<ws> · generations_<ws>)
                                                  │ owns side effects
                                  ┌───────────────┼────────────────────────┐
                                  ▼               ▼                        ▼
                            PostgreSQL      Sidekiq jobs            Vendors::* / Publishers::SocialPublisher
                            ActiveStorage   (publish, metrics,      Prompts::* + Anthropic
                            (S3)            tokens, billing)        Stripe · Mercado Pago · Google · HeyGen · 5 networks
```

## Load-bearing rules (see CLAUDE.md)

- **Every status transition** → `Operations::Tickets::ChangeStatus` (log + history note + AI summary + side effects + broadcast).
- **Every publish** → `Publishers::SocialPublisher` (direct vendor per network; no aggregator).
- **Every query** scoped to `Current.workspace`. Pundit authorizes on the membership role.
- **Controllers thin**, logic in `Operations::*`; **no AR callbacks** for side effects; never bare-`create!` another entity from a service.
- Secrets in Rails credentials (`credential(:vendor, :key, env:)`); per-workspace tokens `encrypts`-ed on models.
- Dates ISO 8601, money in cents. UI copy pt-BR, all identifiers English; statuses translated by a frontend label map.
```
```

## At a glance

| Layer | Count |
|---|---|
| Models | 25 |
| API controllers | 30 (+ webhooks, auth, spa) |
| Service objects (operations/controllers/prompts/creatives) | ~55 |
| Vendor clients + actions | 127 across 11 vendors |
| Serializers | 18 · Policies | 10 · Jobs | 12 · Channels | 3 |
| Frontend pages | 18 · components | 38 · hooks | 5 |
| Migrations | 10 · Cron jobs | 6 |
