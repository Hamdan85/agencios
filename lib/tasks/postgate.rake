# frozen_string_literal: true

# One-time (idempotent) PostGate environment setup: register this environment's
# return-URL origin (required before the first hosted-connect call — see
# Operations::Social::Postgate::CreateConnectUrl) and create the inbound webhook
# subscription (see Controllers::Webhooks::Postgate::Receive for the events
# consumed). Safe to re-run.
#
#   bin/rails postgate:setup
namespace :postgate do
  desc 'Register the connect-return origin and create the webhook subscription (idempotent)'
  task setup: :environment do
    abort('postgate.api_key is not configured — set it via rails credentials:edit first.') unless
      Vendors::Postgate::Client.configured?

    client = Vendors::Postgate::Client.new

    setup_connect_origin(client)
    setup_webhook(client)
  end

  # PostGate only redirects a hosted-connect flow back to a pre-registered
  # return_url origin (POST /api/connect-origins) — without this, every
  # CreateConnectUrl call is rejected.
  def setup_connect_origin(client)
    origin = SystemConfig.app_host
    existing = client.connect_origins
    registered = Array(existing['data']).any? { |o| o['origin'] == origin }

    if registered
      puts "Connect origin already registered: #{origin}"
      return
    end

    client.allow_connect_origin(origin: origin, label: 'agencios')
    puts "Registered connect origin: #{origin}"
  end

  # Events consumed by Controllers::Webhooks::Postgate::Receive.
  WEBHOOK_EVENTS = %w[
    post.published post.failed post.partial post.insights
    profile.connected profile.disconnected profile.expiring profile.expired
    profile.reauth_required profile.stats_updated
  ].freeze

  def setup_webhook(client)
    url = "#{SystemConfig.app_host}/webhooks/postgate"
    existing = client.list_webhooks
    already_exists = Array(existing['data']).any? { |w| w['url'] == url }

    if already_exists
      puts "Webhook already registered: #{url}"
      return
    end

    webhook = client.create_webhook(url: url, events: WEBHOOK_EVENTS)
    puts "Webhook created: #{url}"
    puts "Events: #{WEBHOOK_EVENTS.join(', ')}"
    puts ''
    puts "Signing secret (shown once — store it now, it cannot be re-fetched):"
    puts "  #{webhook['secret']}"
    puts ''
    puts 'Store it with:'
    puts '  EDITOR=nano bin/rails credentials:edit'
    puts 'and add:'
    puts '  postgate:'
    puts "    webhook_secret: #{webhook['secret']}"
  end
end
