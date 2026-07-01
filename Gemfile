# frozen_string_literal: true

source 'https://rubygems.org'

gem 'aws-sdk-s3', require: false
gem 'pg', '~> 1.1'
gem 'propshaft'
gem 'puma', '>= 5.0'
gem 'rails', '~> 8.1.3'

# HTTP/2 proxy, asset caching + X-Sendfile in front of Puma (used as the
# container CMD: `bin/thrust bin/rails server`).
gem 'thruster', require: false

# Active Storage image analysis + variants, via libvips (loaded lazily).
gem 'image_processing', '~> 2.0'
gem 'ruby-vips', '~> 2.2', require: false

# Vite — the SPA bundler
gem 'vite_rails'

# Google OAuth (sign-in + Calendar)
gem 'omniauth-google-oauth2'
gem 'omniauth-rails_csrf_protection'

# Background jobs + real-time
gem 'connection_pool', '~> 3.0'
gem 'redis', '~> 5.0'
gem 'sidekiq', '~> 8.0'
gem 'sidekiq-cron'

# pgvector — future semantic search
gem 'neighbor'

# Rate limiting
gem 'rack-attack'

# HTTP clients
gem 'faraday', '~> 2.12'
gem 'faraday-retry', '~> 2.2'
gem 'httparty'
gem 'oj', '~> 3.16'

# SaaS billing
gem 'stripe'

# Google Workspace (Calendar + Meet)
gem 'google-apis-calendar_v3'
gem 'google-apis-meet_v2'
gem 'googleauth'

# Serialization
gem 'active_model_serializers'

# Authorization
gem 'pundit'

# OAuth 2.1 provider (authorizes Claude / external MCP clients per-user)
gem 'doorkeeper', '~> 5.8'

# Remote MCP server (Streamable HTTP) — lets Claude operate workspaces as a connector
gem 'fast-mcp', '~> 1.5'

# Pagination
gem 'pagy'

gem 'bcrypt', '~> 3.1'

# Windows tz data
gem 'tzinfo-data', platforms: %i[windows jruby]

# Boot caching
gem 'bootsnap', require: false

group :development, :test do
  gem 'brakeman', require: false
  gem 'debug', platforms: %i[mri windows], require: 'debug/prelude'
  gem 'dotenv-rails'
  gem 'factory_bot_rails'
  gem 'rspec-rails'
  gem 'webmock'
end

group :development do
  gem 'letter_opener_web'
  gem 'web-console'
end

gem 'activeadmin', '~> 4.0.0.beta'
# Active Admin 4 serves its own JS via importmap (the SPA still uses Vite).
gem 'importmap-rails'

gem 'ferrum', '~> 0.17.2'
