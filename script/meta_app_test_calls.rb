#!/usr/bin/env ruby
# frozen_string_literal: true

# Meta App Review — "Testing" step driver (per-provider).
#
# The App Dashboard → Review → Testing screen lists every permission your use
# cases request as "0 of 1 API call(s) required". Before you can submit for App
# Review, each permission needs at least one Graph API call made with a token
# that actually holds it.
#
# This script fires one representative call per permission for a SINGLE provider,
# using the access token you pass in. Pick the provider that matches the token:
#
#   facebook   -> graph.facebook.com   (a Facebook User/Page token; also covers
#                                        the classic Instagram permissions that
#                                        resolve through a linked Page)
#   instagram  -> graph.instagram.com  (an Instagram-Login user token)
#   threads    -> graph.threads.net    (a Threads user token)
#
# It auto-resolves the assets it needs from the token (Page id + linked Instagram
# business id for facebook), cleans up anything it creates (an unpublished photo;
# a Threads draft container is never published), and prints a pass/fail table you
# can compare against the dashboard counters.
#
# Usage:
#   ruby script/meta_app_test_calls.rb <provider> <access_token>
#   ruby script/meta_app_test_calls.rb facebook  EAA...
#   ruby script/meta_app_test_calls.rb instagram IGAA...
#   ruby script/meta_app_test_calls.rb threads   THAA...
#
# Or via env:
#   PROVIDER=facebook ACCESS_TOKEN=EAA... ruby script/meta_app_test_calls.rb
#
# Optional env overrides:
#   GRAPH_VERSION       (default v25.0)          THREADS_VERSION (default v1.0)
#   PAGE_ID / IG_USER_ID / THREADS_USER_ID       (skip auto-resolution)
#   TEST_IMAGE_URL      (public https jpg/png used for the pages_manage_posts probe)
#   DRY_RUN=1           (skip write probes: pages_manage_posts, threads_content_publish)

require 'net/http'
require 'json'
require 'uri'

GRAPH_VERSION   = ENV.fetch('GRAPH_VERSION', 'v25.0')
THREADS_VERSION = ENV.fetch('THREADS_VERSION', 'v1.0')
FB_HOST         = 'https://graph.facebook.com'
IG_HOST         = 'https://graph.instagram.com'
TH_HOST         = 'https://graph.threads.net'
TEST_IMAGE_URL  = ENV.fetch('TEST_IMAGE_URL', 'https://upload.wikimedia.org/wikipedia/commons/a/a3/June_odd-eyed-cat.jpg')
DRY_RUN         = %w[1 true yes].include?(ENV['DRY_RUN'].to_s.downcase)

PROVIDERS = %w[facebook instagram threads].freeze

# ---- args ------------------------------------------------------------------

provider = (ARGV[0] || ENV['PROVIDER']).to_s.downcase.strip
token    = ARGV[1] || ENV['ACCESS_TOKEN']

# Friendly aliases.
provider = { 'fb' => 'facebook', 'ig' => 'instagram', 'thread' => 'threads' }.fetch(provider, provider)

if provider.empty? || token.to_s.empty?
  abort <<~USAGE
    Usage: ruby script/meta_app_test_calls.rb <provider> <access_token>
      provider: #{PROVIDERS.join(' | ')}
      e.g. ruby script/meta_app_test_calls.rb facebook EAA...
  USAGE
end

unless PROVIDERS.include?(provider)
  abort "Unknown provider #{provider.inspect}. Choose one of: #{PROVIDERS.join(', ')}."
end

# ---- tiny HTTP layer -------------------------------------------------------

Resp = Struct.new(:ok, :status, :body, :error, keyword_init: true)

def request(method, url, params = {})
  uri = URI(url)
  case method
  when :get
    uri.query = URI.encode_www_form(params)
    req = Net::HTTP::Get.new(uri)
  when :delete
    uri.query = URI.encode_www_form(params)
    req = Net::HTTP::Delete.new(uri)
  when :post
    req = Net::HTTP::Post.new(uri)
    req.set_form_data(params)
  else
    raise ArgumentError, method.to_s
  end

  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = true
  http.read_timeout = 60
  res  = http.request(req)
  body = res.body.to_s.empty? ? {} : (JSON.parse(res.body) rescue { 'raw' => res.body })
  if res.is_a?(Net::HTTPSuccess) && !body.is_a?(Hash) || (body.is_a?(Hash) && body['error'].nil? && res.is_a?(Net::HTTPSuccess))
    Resp.new(ok: true, status: res.code.to_i, body: body)
  else
    err = body.is_a?(Hash) && body['error'] ? body['error'] : { 'message' => "HTTP #{res.code}" }
    msg = "#{err['message']} (code #{err['code']}#{err['error_subcode'] ? "/#{err['error_subcode']}" : ''})"
    Resp.new(ok: false, status: res.code.to_i, body: body, error: msg)
  end
rescue StandardError => e
  Resp.new(ok: false, status: 0, error: e.message)
end

def get(host, path, token, params = {})
  request(:get, "#{host}/#{path}", params.merge(access_token: token))
end

def post(host, path, token, params = {})
  request(:post, "#{host}/#{path}", params.merge(access_token: token))
end

# ---- output ----------------------------------------------------------------

GREEN = "\e[32m"; RED = "\e[31m"; YELLOW = "\e[33m"; DIM = "\e[2m"; RESET = "\e[0m"
RESULTS = []

def probe(permission, note = nil)
  printf "  %-34s ", permission
  resp = yield
  if resp.nil?
    puts "#{YELLOW}SKIP#{RESET} #{DIM}#{note}#{RESET}"
    RESULTS << [permission, :skip, note]
  elsif resp.ok
    puts "#{GREEN}OK#{RESET}   #{DIM}#{note}#{RESET}"
    RESULTS << [permission, :ok, note]
  else
    puts "#{RED}FAIL#{RESET} #{DIM}#{resp.error}#{RESET}"
    RESULTS << [permission, :fail, resp.error]
  end
  resp
end

def section(title)
  puts "\n#{title}"
end

# ---- provider runners ------------------------------------------------------

def run_facebook(token)
  fbv        = GRAPH_VERSION
  page_id    = ENV['PAGE_ID']
  page_token = nil
  ig_user_id = ENV['IG_USER_ID']

  puts "Resolving assets from the Facebook token…"
  accounts = get(FB_HOST, "#{fbv}/me/accounts", token,
                 fields: 'id,name,access_token,instagram_business_account{id,username}')
  if accounts.ok && (data = accounts.body['data']).is_a?(Array) && !data.empty?
    page = data.find { |p| p['instagram_business_account'] } || data.first
    page_id    ||= page['id']
    page_token   = page['access_token']
    ig_user_id ||= page.dig('instagram_business_account', 'id')
    puts "  page_id=#{page_id} ig_user_id=#{ig_user_id || '(none linked)'}"
  else
    puts "  #{YELLOW}Could not list Pages (#{accounts.error || 'empty'}). Using the user token directly.#{RESET}"
  end
  # Fall back to the user token for Page/IG calls when no Page token was returned.
  page_token ||= token

  section "Facebook / classic Instagram permissions (graph.facebook.com)"

  probe('public_profile', 'GET /me') do
    get(FB_HOST, "#{fbv}/me", token, fields: 'id,name')
  end

  probe('pages_show_list', 'GET /me/accounts') do
    get(FB_HOST, "#{fbv}/me/accounts", token, fields: 'id,name')
  end

  probe('business_management', 'GET /me/businesses') do
    get(FB_HOST, "#{fbv}/me/businesses", token, fields: 'id,name')
  end

  if page_id
    probe('pages_read_engagement', 'GET /{page}?fields=fan_count') do
      get(FB_HOST, "#{fbv}/#{page_id}", page_token, fields: 'id,name,fan_count,followers_count')
    end

    probe('pages_read_user_content', 'GET /{page}/feed') do
      get(FB_HOST, "#{fbv}/#{page_id}/feed", page_token, limit: 1)
    end

    probe('read_insights', 'GET /{page}/insights') do
      get(FB_HOST, "#{fbv}/#{page_id}/insights", page_token,
          metric: 'page_post_engagements,page_views_total', period: 'day')
    end

    probe('pages_manage_posts', DRY_RUN ? '(dry-run)' : 'POST /{page}/photos published=false → DELETE') do
      next nil if DRY_RUN

      created = post(FB_HOST, "#{fbv}/#{page_id}/photos", page_token,
                     url: TEST_IMAGE_URL, published: 'false',
                     caption: 'agencios app-review test — auto-deleted')
      if created.ok && (photo_id = created.body['id'])
        request(:delete, "#{FB_HOST}/#{fbv}/#{photo_id}", access_token: page_token)
      end
      created
    end
  else
    %w[pages_read_engagement pages_read_user_content read_insights pages_manage_posts].each do |perm|
      probe(perm, 'no Page resolved from token') { nil }
    end
  end

  if ig_user_id
    probe('instagram_basic', 'GET /{ig-user}?fields=username') do
      get(FB_HOST, "#{fbv}/#{ig_user_id}", page_token, fields: 'id,username,media_count')
    end

    probe('instagram_content_publish', 'GET /{ig-user}/content_publishing_limit') do
      get(FB_HOST, "#{fbv}/#{ig_user_id}/content_publishing_limit", page_token,
          fields: 'config,quota_usage')
    end

    probe('instagram_manage_comments', 'GET /{latest-media}/comments') do
      media = get(FB_HOST, "#{fbv}/#{ig_user_id}/media", page_token, fields: 'id', limit: 1)
      mid   = media.ok && media.body.dig('data', 0, 'id')
      next media unless mid

      get(FB_HOST, "#{fbv}/#{mid}/comments", page_token, limit: 1)
    end

    probe('instagram_manage_messages', 'GET /{ig-user}/conversations') do
      get(FB_HOST, "#{fbv}/#{ig_user_id}/conversations", page_token, platform: 'instagram')
    end
  else
    %w[instagram_basic instagram_content_publish instagram_manage_comments
       instagram_manage_messages].each do |perm|
      probe(perm, 'no linked Instagram business account') { nil }
    end
  end
end

def run_instagram(token)
  section "Instagram-Login permissions (graph.instagram.com)"

  probe('instagram_business_basic', 'GET /me?fields=username') do
    get(IG_HOST, "#{GRAPH_VERSION}/me", token, fields: 'id,username')
  end

  probe('instagram_business_manage_messages', 'GET /me/conversations') do
    get(IG_HOST, "#{GRAPH_VERSION}/me/conversations", token, platform: 'instagram')
  end
end

def run_threads(token)
  th_user = ENV['THREADS_USER_ID'] || 'me'

  section "Threads permissions (graph.threads.net)"

  probe('threads_basic', 'GET /me?fields=username') do
    get(TH_HOST, "#{THREADS_VERSION}/me", token, fields: 'id,username')
  end

  probe('threads_content_publish', DRY_RUN ? '(dry-run)' : 'POST /me/threads (draft container, not published)') do
    next nil if DRY_RUN

    post(TH_HOST, "#{THREADS_VERSION}/#{th_user}/threads", token,
         media_type: 'TEXT', text: 'agencios app-review test container')
  end

  probe('threads_manage_insights', 'GET /me/threads_insights?metric=views') do
    get(TH_HOST, "#{THREADS_VERSION}/#{th_user}/threads_insights", token, metric: 'views')
  end

  probe('threads_manage_replies', 'GET /{latest-thread}/replies') do
    posts = get(TH_HOST, "#{THREADS_VERSION}/#{th_user}/threads", token, fields: 'id', limit: 1)
    tid   = posts.ok && posts.body.dig('data', 0, 'id')
    next posts unless tid

    get(TH_HOST, "#{THREADS_VERSION}/#{tid}/replies", token)
  end
end

# ---- dispatch --------------------------------------------------------------

puts "Meta App Review — test-call driver (Graph #{GRAPH_VERSION}, Threads #{THREADS_VERSION})"
puts "Provider: #{provider}"

case provider
when 'facebook'  then run_facebook(token)
when 'instagram' then run_instagram(token)
when 'threads'   then run_threads(token)
end

# ---- summary ---------------------------------------------------------------

ok   = RESULTS.count { |_, s, _| s == :ok }
fail = RESULTS.count { |_, s, _| s == :fail }
skip = RESULTS.count { |_, s, _| s == :skip }

puts "\n" + ('-' * 60)
puts "Summary: #{GREEN}#{ok} OK#{RESET}, #{RED}#{fail} FAIL#{RESET}, #{YELLOW}#{skip} SKIP#{RESET}"
puts "Recheck the dashboard: each OK permission should now read \"1 of 1\"."
puts "FAIL/SKIP usually means the token lacks that permission or the asset" \
     " (Page / IG / Threads / a post) doesn't exist — grant the scope in the" \
     " Graph API Explorer and re-run."
