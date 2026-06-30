# frozen_string_literal: true

require "sidekiq/web"

Rails.application.routes.draw do
  ActiveAdmin.routes(self)
  get "up" => "rails/health#show", as: :rails_health_check

  # ── PWA ────────────────────────────────────────────────────────────
  # Manifest served with the correct Content-Type. The service worker is a
  # static file in public/ (served at /service-worker.js with scope "/").
  get "manifest.json", to: "pwa#manifest", as: :pwa_manifest

  # ── Real-time ──────────────────────────────────────────────────────
  mount ActionCable.server => "/cable"
  mount Sidekiq::Web => "/sidekiq" if Rails.env.development?

  # ── Google sign-in / sign-up (full-page OAuth) ─────────────────────
  # Declared before the generic social callback so "/auth/google/callback"
  # isn't captured by the ":provider" route below.
  get "/auth/google",            to: "auth/google#start"
  get "/auth/google/callback",   to: "auth/google#callback"

  # ── Google Calendar workspace connect ──────────────────────────────
  get "/auth/calendar/callback", to: "auth/calendar#callback"

  # ── OAuth callbacks (Calendar, social-network account connect) ─────
  match "/auth/:provider/callback", to: "auth/omniauth#callback", via: %i[get post]
  post  "/auth/facebook/select",   to: "auth/omniauth#choose_page"
  get   "/auth/failure",           to: "auth/omniauth#failure"
  get   "/auth/social-connected",  to: "auth/omniauth#social_connected"

  # ── Public per-client connect page (login-less; token is the credential) ───
  # The agency shares /conectar/:token with the client to connect their own
  # networks. Declared before the SPA catch-all so it isn't swallowed.
  get "/conectar/:token",           to: "public_connect#show", format: false
  get "/conectar/:token/authorize", to: "public_connect#authorize", format: false

  # Public status page for a Meta data-deletion request (linked from the callback).
  get "/data-deletion", to: "data_deletion#show"

  # ── Inbound webhooks (vendor → us) ─────────────────────────────────
  namespace :webhooks do
    post "stripe",      to: "stripe#create"
    post "mercadopago", to: "mercado_pago#create"
    post "heygen",      to: "heygen#create"
    match "meta", to: "meta#handle", via: %i[get post]
    # Instagram-Login + Threads have their own app secrets, so a dedicated
    # endpoint per provider (verifies with the right secret).
    match "instagram", to: "social#handle", via: %i[get post], defaults: { provider: "instagram" }
    match "threads",   to: "social#handle", via: %i[get post], defaults: { provider: "threads" }
    # Deauthorize callbacks (user removed the app → revoke their accounts). Meta
    # POSTs a signed_request; each product has its own app secret.
    post "facebook/deauthorize",  to: "social#deauthorize", defaults: { provider: "facebook" }
    post "instagram/deauthorize", to: "social#deauthorize", defaults: { provider: "instagram" }
    post "threads/deauthorize",   to: "social#deauthorize", defaults: { provider: "threads" }
    # Data deletion request callbacks (LGPD/GDPR) — delete the user's data + reply
    # with { url, confirmation_code }.
    post "facebook/data-deletion",  to: "social#data_deletion", defaults: { provider: "facebook" }
    post "instagram/data-deletion", to: "social#data_deletion", defaults: { provider: "instagram" }
    post "threads/data-deletion",   to: "social#data_deletion", defaults: { provider: "threads" }
  end

  # ── MCP connector: OAuth 2.1 provider + discovery + the MCP server ──
  # Lets a user authorize Claude (a custom connector) to operate their
  # workspaces. Declared before the SPA catch-all so these paths aren't
  # swallowed by it. See app/services/mcp/* and app/controllers/{oauth,mcp}/*.
  get "/.well-known/oauth-protected-resource",  to: "oauth/metadata#protected_resource"
  get "/.well-known/oauth-authorization-server", to: "oauth/metadata#authorization_server"

  # Doorkeeper: /oauth/authorize, /oauth/token, /oauth/revoke, /oauth/introspect.
  use_doorkeeper do
    skip_controllers :applications, :authorized_applications
  end
  # RFC 7591 Dynamic Client Registration.
  post "/oauth/register", to: "oauth/registrations#create"

  # Streamable HTTP MCP endpoint (Claude connects here).
  post   "/mcp", to: "mcp/server#handle"
  get    "/mcp", to: "mcp/server#stream"
  delete "/mcp", to: "mcp/server#terminate"
  match  "/mcp", to: "mcp/server#handle", via: :options

  # Tokenized connector endpoint — the secret token in the path authenticates the
  # user (no OAuth). This is the URL users paste into Claude as a custom connector.
  post   "/mcp/c/:token", to: "mcp/connector#handle"
  get    "/mcp/c/:token", to: "mcp/connector#stream"
  delete "/mcp/c/:token", to: "mcp/connector#terminate"
  match  "/mcp/c/:token", to: "mcp/connector#handle", via: :options

  # ── JSON API ───────────────────────────────────────────────────────
  namespace :api do
    namespace :v1 do
      # Auth & identity
      resource  :session, only: %i[create destroy], controller: "sessions"
      resource  :registration, only: %i[create], controller: "registrations"
      resources :password_resets, only: %i[create update]
      get "me", to: "me#show"

      # Web Push subscriptions (id is the URL-encoded endpoint)
      resources :push_subscriptions, only: %i[create destroy], constraints: { id: %r{[^/]+} }

      # Claude connector — the user's tokenized MCP URL (+ rotation)
      resource :mcp_connector, only: %i[show], controller: "mcp_connector" do
        post :rotate
      end

      # Tenancy
      resource :workspace, only: %i[show create update], controller: "workspaces" do
        post "switch", on: :collection
        resources :memberships, only: %i[index update destroy]
        resources :invitations, only: %i[index create destroy]
      end
      post "invitations/:token/accept", to: "invitations#accept"

      # CRM
      resources :clients do
        member do
          post  :archive
          patch :positioning, action: :update_positioning
          patch :brand_assets
        end
        collection do
          post :positioning_preview
          post :extract_from_url
        end
        # A client's own connected social networks (the agency connects each
        # client's Instagram/TikTok/etc.; tickets under its projects publish here).
        resources :social_accounts, only: %i[index destroy] do
          collection do
            get :authorize_url
            get :connect_link
          end
          member { post :reconnect }
        end
      end
      resources :projects do
        member { post :finalize }
        # End-of-run audit reports (the finalize deck). Listed under a project;
        # a single report is fetched by its own id (the deck page).
        resources :reports, only: %i[index]
      end
      resources :reports, only: %i[show]

      # Board, tickets & funnel
      get "board", to: "board#index"
      get "calendar", to: "calendar#index"
      get "tasks", to: "tasks#index"
      resources :tickets do
        collection do
          post :clear_column
        end
        member do
          post  :advance
          patch :reorder
          post  :summarize
          post  :ai_action
          post  :generate_subtasks
          post  :archive
          post  :unarchive
        end
        resources :subtasks, only: %i[create update destroy]
        resources :creatives, only: %i[index create destroy] do
          post :generate, on: :collection
        end
        resources :attachments, only: %i[index create update destroy]
        resources :notes, only: %i[index create]
        resources :posts, only: %i[index create update destroy]
      end
      patch "subtasks/:id", to: "subtasks#update_global"

      # Creative studio
      get  "studio", to: "studio#index"
      post "studio/generate", to: "studio#generate"
      resources :generations, only: %i[index show]

      # Workspace-level creative management (Studio gallery)
      get    "creatives",     to: "creatives#workspace_index"
      patch  "creatives/:id", to: "creatives#update",            as: :creative
      delete "creatives/:id", to: "creatives#workspace_destroy"

      # Meetings, billing (social accounts are nested under clients above)
      resources :meetings
      resources :invoices do
        member do
          post :send_invoice
          post :cancel
          post :mark_paid
          post :payment_link
        end
      end

      resource :settings, only: %i[show update], controller: "settings" do
        patch  :brand_assets
        get    :google_calendar_authorize_url
        delete :google_calendar
      end

      resource :billing, only: %i[show], controller: "billing" do
        post :checkout_session
        post :portal
        post :change_plan
        post :cancel
        post :reactivate
      end

      get "dashboard", to: "dashboard#index"

      # Authorized external apps (MCP connectors like Claude) — list + revoke.
      resources :connections, only: %i[index destroy]
    end
  end

  # ── Server-rendered (SSR) public marketing site ────────────────────
  # Portuguese URL segments (user-facing), English controller/actions.
  get "como-funciona",         to: "pages#how_it_works", as: :how_it_works
  get "funcionalidades",       to: "pages#features",     as: :features
  get "funcionalidades/:slug", to: "pages#feature",      as: :feature,
      constraints: { slug: /quadro|estudio|inteligencia|publicacao|calendario|cobrancas/ }
  get "precos",                to: "pages#pricing",      as: :pricing
  get "privacidade",           to: "pages#privacy",      as: :privacy
  get "termos",                to: "pages#terms",        as: :terms

  # ── SPA shell — every other HTML GET boots React ───────────────────
  root to: "pages#home"
  get "*path", to: "spa#index", constraints: lambda { |req|
    req.format.html? &&
      !req.path.start_with?("/api", "/cable", "/sidekiq", "/rails", "/auth", "/webhooks", "/vite",
                            "/mcp", "/oauth", "/.well-known")
  }
end
