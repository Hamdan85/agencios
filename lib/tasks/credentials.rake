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
    "config/credentials.yml.enc"             => "config/master.key",
    "config/credentials/development.yml.enc" => "config/credentials/development.key",
    "config/credentials/production.yml.enc"  => "config/credentials/production.key"
  }.freeze

  desc "Unify Google/Calendar/YouTube credentials under a single `google:` key (APPLY=1 to write)"
  task unify_google: :environment do
    apply = ENV["APPLY"] == "1"
    puts apply ? "== credentials:unify_google (APPLY) ==" : "== credentials:unify_google (DRY-RUN — nothing written) =="
    puts

    TARGETS.each do |config_path, key_path|
      migrate_target(config_path, key_path, apply: apply)
      puts
    end

    unless apply
      puts "Dry-run complete. Re-run with APPLY=1 to write the changes:"
      puts "  APPLY=1 bin/rails credentials:unify_google"
    end
  end

  # ── helpers ──────────────────────────────────────────────────────────────

  def migrate_target(config_path, key_path, apply:)
    abs = Rails.root.join(config_path)
    unless abs.exist?
      puts "• #{config_path} — SKIP (file not found)"
      return
    end
    unless Rails.root.join(key_path).exist? || ENV["RAILS_MASTER_KEY"].present?
      puts "• #{config_path} — SKIP (no key: #{key_path} missing and RAILS_MASTER_KEY unset)"
      return
    end

    enc = encrypted_config(config_path, key_path)
    content = enc.read
    data = YAML.safe_load(content, aliases: true) || {}

    unless data.key?("youtube")
      puts "• #{config_path} — already unified (no `youtube:` block)"
      return
    end

    new_content = transform(content, has_google: data.key?("google"))
    new_data = YAML.safe_load(new_content, aliases: true) || {}

    verify!(config_path, data, new_data)

    action = data.key?("google") ? "remove duplicate `youtube:`" : "rename `youtube:` → `google:`"
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
    unless has_google
      return content.sub(/^youtube:.*$/, "google:")
    end

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
    raise "#{config_path}: `youtube:` still present after transform" if after.key?("youtube")
    %w[client_id client_secret].each do |k|
      v = after.dig("google", k)
      raise "#{config_path}: google.#{k} missing/blank after transform" if v.to_s.empty?
    end

    expected = before.except("youtube")
    expected["google"] ||= before["youtube"] # rename case
    if after != expected
      changed = (after.keys | expected.keys).reject { |k| after[k] == expected[k] }
      raise "#{config_path}: unexpected change beyond Google unification in keys: #{changed.inspect}"
    end
  end

  def encrypted_config(config_path, key_path)
    ActiveSupport::EncryptedConfiguration.new(
      config_path: Rails.root.join(config_path).to_s,
      key_path: Rails.root.join(key_path).to_s,
      env_key: "RAILS_MASTER_KEY",
      raise_if_missing_key: true
    )
  end

  def mask(value)
    s = value.to_s
    return "(blank)" if s.empty?
    return s if s.length <= 12

    "#{s[0, 8]}…#{s[-4, 4]}"
  end
end
