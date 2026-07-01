# frozen_string_literal: true

# Migrates every environment's encrypted credentials to the unified Google
# structure: Google sign-in, Calendar/Meet, and YouTube all share ONE OAuth
# client under the `google:` key. The legacy duplicated `youtube:` block (same
# client_id/secret as `google:`) is removed.
#
# Canonical structure: config/credentials.example.yml + docs/CREDENTIALS.md.
#
#   bin/rails credentials:unify_google           # dry-run — prints the plan, writes nothing
#   APPLY=1 bin/rails credentials:unify_google   # rewrites each *.yml.enc (keeps a .bak)
#
# The transform is text-based, so comments and key order in the encrypted files
# are preserved. It is idempotent: a file with no `youtube:` block is left alone.
namespace :credentials do
  # config_path => key_path. nil key_path falls back to RAILS_MASTER_KEY.
  TARGETS = {
    'config/credentials.yml.enc' => 'config/master.key',
    'config/credentials/development.yml.enc' => 'config/credentials/development.key',
    'config/credentials/production.yml.enc' => 'config/credentials/production.key'
  }.freeze

  desc 'Unify Google/Calendar/YouTube credentials under a single `google:` key (APPLY=1 to write)'
  task unify_google: :environment do
    apply = ENV['APPLY'] == '1'
    puts apply ? '== credentials:unify_google (APPLY) ==' : '== credentials:unify_google (DRY-RUN — nothing written) =='
    puts

    TARGETS.each do |config_path, key_path|
      migrate_target(config_path, key_path, apply: apply)
      puts
    end

    unless apply
      puts 'Dry-run complete. Re-run with APPLY=1 to write the changes:'
      puts '  APPLY=1 bin/rails credentials:unify_google'
    end
  end

  desc "Generate a VAPID (Web Push) P-256 key pair and save it into an env's credentials (ENVIRONMENT=production by default; FORCE=1 to overwrite)"
  task generate_vapid: :environment do
    require 'openssl'
    require 'base64'

    env = ENV.fetch('ENVIRONMENT', 'production')
    config_path, key_path =
      case env
      when 'production'  then ['config/credentials/production.yml.enc',  'config/credentials/production.key']
      when 'development' then ['config/credentials/development.yml.enc', 'config/credentials/development.key']
      when 'base'        then ['config/credentials.yml.enc', 'config/master.key']
      else abort("Unknown ENVIRONMENT=#{env.inspect} (use production | development | base)")
      end

    abs = Rails.root.join(config_path)
    abort("#{config_path} not found") unless abs.exist?

    # 1. Generate the pair in the exact encoding Vendors::WebPush::Client expects.
    curve       = Vendors::WebPush::Client::CURVE # "prime256v1"
    ec          = OpenSSL::PKey::EC.generate(curve)
    priv_bytes  = ec.private_key.to_s(2).rjust(32, "\x00")
    pub_bytes   = ec.public_key.to_bn.to_s(2)
    raise "bad public length #{pub_bytes.bytesize}" unless pub_bytes.bytesize == 65
    raise "bad private length #{priv_bytes.bytesize}" unless priv_bytes.bytesize == 32

    public_key  = Base64.urlsafe_encode64(pub_bytes, padding: false)
    private_key = Base64.urlsafe_encode64(priv_bytes, padding: false)

    enc     = encrypted_config(config_path, key_path)
    content = enc.read.dup.force_encoding('UTF-8') # decrypted bytes come back ASCII-8BIT
    data    = YAML.safe_load(content, aliases: true) || {}

    if data.dig('vapid', 'public_key').to_s != '' && ENV['FORCE'] != '1'
      abort("#{config_path} already has a vapid block. Re-run with FORCE=1 to overwrite.")
    end

    new_content =
      if data.key?('vapid')
        # Replace the existing vapid block in place (preserve comments/order).
        replace_block(content, 'vapid', { 'public_key' => public_key, 'private_key' => private_key })
      else
        block = +"\n# ─────────────────────────────────────────────────────────────\n"
        block << "# Web Push (VAPID) — PWA browser notifications. Required in every env.\n"
        block << "# ─────────────────────────────────────────────────────────────\n"
        block << "vapid:\n  public_key:  #{public_key}\n  private_key: #{private_key}\n"
        (content.end_with?("\n") ? content : "#{content}\n") + block
      end

    # 2. Validate: parses, nothing else changed, and the private key round-trips
    #    to the stored public point (proves sign + applicationServerKey match).
    nd = YAML.safe_load(new_content, aliases: true) || {}
    raise 'vapid.public_key missing after write'  if nd.dig('vapid', 'public_key').to_s.empty?
    raise 'vapid.private_key missing after write' if nd.dig('vapid', 'private_key').to_s.empty?

    data.except('vapid').each { |k, v| raise "lost/altered key #{k}" unless nd[k] == v }
    verify_vapid_roundtrip!(private_key, public_key, curve)

    File.binwrite("#{abs}.bak", File.binread(abs))
    enc.write(new_content)

    puts "VAPID written to #{config_path} (env=#{env})."
    puts "  public_key  (applicationServerKey, safe to expose): #{public_key}"
    puts "  private_key (secret): #{mask(private_key)}  [#{private_key.length} chars]"
    puts '  round-trip: derived public point == stored public_key ✓'
    puts "  backup: #{config_path}.bak"
  end

  # ── helpers ──────────────────────────────────────────────────────────────

  # Rebuild the EC key the way the app does and confirm the derived public point
  # equals what we stored — a corrupt private key would fail here, not in prod.
  def verify_vapid_roundtrip!(private_key, public_key, curve)
    raw  = Base64.urlsafe_decode64(private_key.ljust((private_key.length + 3) & ~3, '='))
    asn1 = OpenSSL::ASN1::Sequence([
                                     OpenSSL::ASN1::Integer(OpenSSL::BN.new(1)),
                                     OpenSSL::ASN1::OctetString(raw),
                                     OpenSSL::ASN1::ASN1Data.new([OpenSSL::ASN1::ObjectId(curve)], 0, :CONTEXT_SPECIFIC)
                                   ])
    rebuilt = OpenSSL::PKey::EC.new(asn1.to_der)
    derived = Base64.urlsafe_encode64(rebuilt.public_key.to_bn.to_s(2), padding: false)
    raise 'VAPID round-trip mismatch' unless derived == public_key
  end

  # Replace a top-level `name:` block's children with new key/values, in place.
  def replace_block(content, name, kv)
    lines = content.lines
    out = []
    i = 0
    while i < lines.length
      if lines[i] =~ /\A#{Regexp.escape(name)}:(\s|#|$)/
        out << "#{name}:\n"
        kv.each { |k, v| out << "  #{k}: #{v}\n" }
        i += 1
        i += 1 while i < lines.length && lines[i] =~ /\A[ \t]+\S/
        next
      end
      out << lines[i]
      i += 1
    end
    out.join
  end

  def migrate_target(config_path, key_path, apply:)
    abs = Rails.root.join(config_path)
    unless abs.exist?
      puts "• #{config_path} — SKIP (file not found)"
      return
    end
    unless Rails.root.join(key_path).exist? || ENV['RAILS_MASTER_KEY'].present?
      puts "• #{config_path} — SKIP (no key: #{key_path} missing and RAILS_MASTER_KEY unset)"
      return
    end

    enc = encrypted_config(config_path, key_path)
    content = enc.read
    data = YAML.safe_load(content, aliases: true) || {}

    unless data.key?('youtube')
      puts "• #{config_path} — already unified (no `youtube:` block)"
      return
    end

    new_content = transform(content, has_google: data.key?('google'))
    new_data = YAML.safe_load(new_content, aliases: true) || {}

    verify!(config_path, data, new_data)

    action = data.key?('google') ? 'remove duplicate `youtube:`' : 'rename `youtube:` → `google:`'
    puts "• #{config_path} — #{action}"
    puts "    google.client_id:     #{mask(new_data.dig('google', 'client_id'))}"
    puts "    google.client_secret: #{mask(new_data.dig('google', 'client_secret'))}"

    return unless apply

    backup = "#{abs}.bak"
    File.binwrite(backup, File.binread(abs))
    enc.write(new_content)
    puts "    written ✓  (backup: #{config_path}.bak)"
  end

  # Text transform that preserves comments and ordering.
  #   has_google == true  → drop the entire `youtube:` block.
  #   has_google == false → rename the `youtube:` header line to `google:`.
  def transform(content, has_google:)
    return content.sub(/^youtube:.*$/, 'google:') unless has_google

    lines = content.lines
    out = []
    i = 0
    while i < lines.length
      if lines[i] =~ /\Ayoutube:(\s|#|$)/
        i += 1
        i += 1 while i < lines.length && lines[i] =~ /\A[ \t]+\S/ # indented children
        next
      end
      out << lines[i]
      i += 1
    end
    out.join.gsub(/\n{3,}/, "\n\n")
  end

  # Fail loudly rather than corrupt a secrets file: youtube must be gone, google
  # must carry a client_id/secret, and nothing else may change.
  def verify!(config_path, before, after)
    raise "#{config_path}: `youtube:` still present after transform" if after.key?('youtube')

    %w[client_id client_secret].each do |k|
      v = after.dig('google', k)
      raise "#{config_path}: google.#{k} missing/blank after transform" if v.to_s.empty?
    end

    expected = before.except('youtube')
    expected['google'] ||= before['youtube'] # rename case
    return unless after != expected

    changed = (after.keys | expected.keys).reject { |k| after[k] == expected[k] }
    raise "#{config_path}: unexpected change beyond Google unification in keys: #{changed.inspect}"
  end

  def encrypted_config(config_path, key_path)
    ActiveSupport::EncryptedConfiguration.new(
      config_path: Rails.root.join(config_path).to_s,
      key_path: Rails.root.join(key_path).to_s,
      env_key: 'RAILS_MASTER_KEY',
      raise_if_missing_key: true
    )
  end

  def mask(value)
    s = value.to_s
    return '(blank)' if s.empty?
    return s if s.length <= 12

    "#{s[0, 8]}…#{s[-4, 4]}"
  end
end
