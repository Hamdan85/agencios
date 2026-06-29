# frozen_string_literal: true

# HeyGen webhook setup.
#
# HeyGen does NOT expose a webhook signing secret anywhere in its dashboard. The
# `secret` is generated and returned EXACTLY ONCE — in the response body when you
# register (or rotate) a webhook endpoint. That secret is what verifies inbound
# deliveries (`Heygen-Signature` = HMAC-SHA256 of the raw body). So there is
# nothing to "find": you register the endpoint, capture the secret it returns,
# and store it as `heygen.webhook_secret` in encrypted credentials.
#
#   bin/rails heygen:register_webhook                       # uses SystemConfig.app_host + /webhooks/heygen
#   URL=https://agencios.app/webhooks/heygen bin/rails heygen:register_webhook
#   bin/rails heygen:list_webhooks                          # inspect existing endpoints
#
# After registering, run `bin/rails credentials:edit` and add:
#   heygen:
#     webhook_secret: <the secret printed below>
#
# See docs/integrations/heygen.md §3e.
namespace :heygen do
  desc "Register the agencios webhook endpoint with HeyGen and print the signing secret"
  task register_webhook: :environment do
    url = ENV["URL"].presence || "#{SystemConfig.app_host}/webhooks/heygen"
    puts "== heygen:register_webhook =="
    puts "Registering endpoint: #{url}"
    puts

    endpoint = Vendors::Heygen::Actions::AddWebhookEndpoint.call(url: url)
    secret = endpoint["secret"] || endpoint[:secret]

    puts "  endpoint_id: #{endpoint['endpoint_id'] || endpoint[:endpoint_id]}"
    puts "  status:      #{endpoint['status'] || endpoint[:status]}"
    puts "  events:      #{Array(endpoint['events'] || endpoint[:events]).join(', ')}"
    puts
    if secret.present?
      puts "  SIGNING SECRET (shown only once — store it now):"
      puts "  #{secret}"
      puts
      puts "  → bin/rails credentials:edit, then add under `heygen:`:"
      puts "      webhook_secret: #{secret}"
    else
      puts "  ⚠ No secret in the response. If the endpoint already existed, rotate it:"
      puts "      POST /v3/webhooks/endpoints/{id}/rotate-secret"
    end
  rescue StandardError => e
    abort "  ✗ Failed: #{e.class}: #{e.message}"
  end

  desc "List the webhook endpoints currently registered with HeyGen"
  task list_webhooks: :environment do
    puts "== heygen:list_webhooks =="
    body = Vendors::Heygen::Client.new.get("/v3/webhooks/endpoints")
    endpoints = body.dig("data", "endpoints") || body["data"] || body
    Array(endpoints).each do |ep|
      ep = ep.with_indifferent_access
      puts "  #{ep[:endpoint_id]}  #{ep[:status]}  #{ep[:url]}  [#{Array(ep[:events]).join(', ')}]"
    end
    puts "  (secret is never returned by list — only on create/rotate)"
  rescue StandardError => e
    abort "  ✗ Failed: #{e.class}: #{e.message}"
  end
end
