# frozen_string_literal: true

require 'rails_helper'

# Guard: user-facing copy must live in config/locales, never hardcoded in code.
# Scans CONVERTED directories for Portuguese-accented characters inside string
# literals (comments are exempt). As i18n phases land, add their directory to
# COVERED_PATHS — never remove one.
RSpec.describe 'i18n hardcoded copy guard' do
  COVERED_PATHS = %w[
    app/controllers/api
    app/controllers/admin
    app/controllers/concerns
    app/controllers/mcp
    app/helpers
    app/jobs
    app/mailers
    app/serializers
    app/services/concerns
    app/services/controllers
    app/services/mcp
    app/services/operations
  ].freeze

  # Deliberately NOT covered (intentional PT that is not user-facing UI copy):
  #   app/services/prompts  — prompt-engineering scaffolding + JSON field hints
  #                           (the OUTPUT language is localized via Prompts::Base)
  #   app/services/vendors  — technical exceptions mapped to generic messages by
  #                           the API error handler + AI fallback stubs
  #   app/models/pricing.rb — plan `name` fallback ('Agência'); localized by key
  #                           at read time via Pricing#localize_name

  PT_CHARS = /[ãáàâçéêíóôõúÃÁÀÂÇÉÊÍÓÔÕÚ]/

  it 'has no Portuguese copy hardcoded in covered paths' do
    offenders = []

    COVERED_PATHS.each do |dir|
      Dir[Rails.root.join(dir, '**/*.rb')].each do |file|
        File.readlines(file).each_with_index do |line, i|
          next unless line =~ PT_CHARS
          next if line.strip.start_with?('#') # comments are fine

          offenders << "#{file.sub("#{Rails.root}/", '')}:#{i + 1}: #{line.strip[0, 100]}"
        end
      end
    end

    expect(offenders).to be_empty, <<~MSG
      Portuguese copy found hardcoded in i18n-covered paths — move it to config/locales
      and reference it with I18n.t:

      #{offenders.join("\n")}
    MSG
  end

  it 'keeps pt-BR and en locale trees in parity' do
    flatten = lambda do |hash, prefix = ''|
      hash.flat_map do |key, value|
        path = prefix.empty? ? key.to_s : "#{prefix}.#{key}"
        value.is_a?(Hash) ? flatten.call(value, path) : [path]
      end
    end

    backend = I18n.backend
    backend.send(:init_translations) unless backend.initialized?
    translations = backend.send(:translations)
    pt = flatten.call(translations[:'pt-BR'] || {})
    en = flatten.call(translations[:en] || {})

    # rails-i18n ships full locale data per language; compare only OUR namespaces.
    ours = ->(keys) { keys.select { |k| k =~ /\A(api|operations|notes|push|credits|statuses|mailers|reports|pages|models|admin)\./ } }
    missing_en = ours.call(pt) - ours.call(en)
    missing_pt = ours.call(en) - ours.call(pt)

    expect(missing_en).to be_empty, "en is missing keys present in pt-BR:\n#{missing_en.join("\n")}"
    expect(missing_pt).to be_empty, "pt-BR is missing keys present in en:\n#{missing_pt.join("\n")}"
  end
end
