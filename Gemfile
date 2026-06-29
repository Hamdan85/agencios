source "https://rubygems.org"

gem "rails", "~> 8.1.3"
gem "propshaft"
gem "pg", "~> 1.1"
gem "puma", ">= 5.0"
gem "aws-sdk-s3", require: false

# Active Storage image analysis + variants, via libvips (loaded lazily).
gem "image_processing", "~> 2.0"
gem "ruby-vips", "~> 2.2", require: false

# Vite — the SPA bundler
gem "vite_rails"

# Google OAuth (sign-in + Calendar)
gem "omniauth-google-oauth2"
gem "omniauth-rails_csrf_protection"

# Background jobs + real-time
gem "sidekiq", "~> 8.0"
gem "sidekiq-cron"
gem "connection_pool", "~> 3.0"
gem "redis", "~> 5.0"

# pgvector — future semantic search
gem "neighbor"

# Rate limiting
gem "rack-attack"

# HTTP clients
gem "httparty"
gem "faraday",       "~> 2.12"
gem "faraday-retry", "~> 2.2"
gem "oj",            "~> 3.16"

# SaaS billing
gem "stripe"

# Google Workspace (Calendar + Meet)
gem "google-apis-calendar_v3"
gem "google-apis-meet_v2"
gem "googleauth"

# Serialization
gem "active_model_serializers"

# Authorization
gem "pundit"

# OAuth 2.1 provider (authorizes Claude / external MCP clients per-user)
gem "doorkeeper", "~> 5.8"

# Remote MCP server (Streamable HTTP) — lets Claude operate workspaces as a connector
gem "fast-mcp", "~> 1.5"

# Pagination
gem "pagy"

gem "bcrypt", "~> 3.1"

# Windows tz data
gem "tzinfo-data", platforms: %i[ windows jruby ]

# Boot caching
gem "bootsnap", require: false

group :development, :test do
  gem "debug", platforms: %i[ mri windows ], require: "debug/prelude"
  gem "dotenv-rails"
  gem "rspec-rails"
  gem "factory_bot_rails"
  gem "webmock"
  gem "brakeman", require: false
end

group :development do
  gem "web-console"
  gem "letter_opener_web"
end
