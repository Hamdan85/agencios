# frozen_string_literal: true

# Singleton row holding the VIDEO-generation engine routing (admin-editable, no
# deploy). The platform decides the best cost/benefit model per generation MODE
# — the user never picks an engine. The OpenRouter API key stays in credentials;
# only the non-secret provider choice + per-mode model slugs + the duration cap
# live here. Read through Vendors::OpenRouter::Video. `instance` returns the row,
# or an unsaved defaults-populated record when the table is empty so reads never
# write (mirrors AiConfig).
class VideoConfig < ApplicationRecord
  # A generation mode maps to a different kind of engine: an avatar talking-head
  # vs a product clip generated from reference photos.
  MODES = %w[avatar product].freeze

  MODE_LABELS = {
    'avatar'  => 'Avatar UGC (pessoa falando)',
    'product' => 'Produto (a partir de fotos)'
  }.freeze

  # Sensible OpenRouter video slugs per mode — the current best cost/benefit for
  # each job. Editable in ActiveAdmin; these are only the seed / fallback.
  DEFAULT_MODE_MODELS = {
    'avatar'  => 'google/veo-3.1',        # native audio + lip-sync, best quality
    'product' => 'bytedance/seedance-2.0' # best product-photo fidelity
  }.freeze

  # DRAFT engines: fast/cheap preview models. A generation renders draft-first so
  # the user iterates quickly, then upgrades to the final model on approval.
  DEFAULT_DRAFT_MODELS = {
    'avatar'  => 'google/veo-3.1-fast',
    'product' => 'bytedance/seedance-2.0'
  }.freeze

  QUALITIES = %w[draft final].freeze

  DEFAULT_MODEL = 'google/veo-3.1-fast'

  # Background-music moods the storyboard can pick from. The video model never
  # generates music — the compose step burns the chosen mood's track (from the
  # admin-managed `music_tracks` base) under the audio.
  MUSIC_MOODS = %w[upbeat calm corporate energetic emotional epic playful cinematic].freeze

  MUSIC_MOOD_LABELS = {
    'upbeat' => 'Animada', 'calm' => 'Calma', 'corporate' => 'Corporativa',
    'energetic' => 'Energética', 'emotional' => 'Emocional', 'epic' => 'Épica',
    'playful' => 'Divertida', 'cinematic' => 'Cinematográfica'
  }.freeze

  PROVIDERS = ['', AiUsageLog::PROVIDER_OPENROUTER].freeze

  validates :provider, inclusion: { in: PROVIDERS }, allow_nil: true
  validates :max_duration_seconds, numericality: { greater_than: 0, less_than_or_equal_to: 120 }

  def self.instance
    first || new
  end

  # The OpenRouter model slug for `mode` at a given quality tier. `final` (the
  # default) resolves the per-mode override, else the default model, else the
  # coded seed. `draft` resolves the per-mode draft override, else the coded
  # draft seed, else falls back to the final chain. Never blank.
  def model_for(mode, quality: 'final')
    key = mode.to_s
    if quality.to_s == 'draft'
      slug = draft_models[key].presence || DEFAULT_DRAFT_MODELS[key]
      return slug if slug.present?
    end
    (mode_models[key].presence || default_model.presence || DEFAULT_MODE_MODELS[key] || DEFAULT_MODEL)
  end

  # 'openrouter' | '' (auto) — normalized.
  def resolved_provider
    provider.to_s.strip.downcase
  end

  def max_duration = max_duration_seconds.presence || 30

  # The track for a mood: the exact mood, else any configured track (so a mood
  # with no track still gets music), else nil (no music). Returns a hash
  # { 'url' =>, 'title' =>, 'attribution' => } or nil.
  def music_track_for(mood)
    tracks = music_tracks.is_a?(Hash) ? music_tracks : {}
    entry = tracks[mood.to_s].presence || tracks.values.find(&:present?)
    return nil unless entry.is_a?(Hash) && entry['url'].present?

    entry.slice('url', 'title', 'attribution')
  end

  # Only store known moods with a non-blank url — no admin input can corrupt the map.
  def music_tracks=(value)
    super(clean_music_map(value))
  end

  # --- ActiveAdmin: one url/title/attribution set per mood ---
  MUSIC_MOODS.each do |mood|
    define_method(:"music_url_#{mood}") { (music_tracks[mood] || {})['url'] }
    define_method(:"music_url_#{mood}=") { |v| merge_music(mood, 'url', v) }
    define_method(:"music_title_#{mood}") { (music_tracks[mood] || {})['title'] }
    define_method(:"music_title_#{mood}=") { |v| merge_music(mood, 'title', v) }
  end

  def self.music_attributes
    MUSIC_MOODS.flat_map { |mood| [:"music_url_#{mood}", :"music_title_#{mood}"] }
  end

  # Only store known modes with trimmed non-blank slugs — no admin input can
  # corrupt the map (mirrors AiConfig#operation_models=).
  def mode_models=(value)
    super(clean_mode_map(value))
  end

  def draft_models=(value)
    super(clean_mode_map(value))
  end

  # --- ActiveAdmin: one text field per mode (can't mistype a mode key) ---
  MODES.each do |mode|
    define_method(:"model_#{mode}") { mode_models[mode] }
    define_method(:"model_#{mode}=") { |value| self.mode_models = mode_models.merge(mode => value) }
    define_method(:"draft_model_#{mode}") { draft_models[mode] }
    define_method(:"draft_model_#{mode}=") { |value| self.draft_models = draft_models.merge(mode => value) }
  end

  def self.mode_model_attributes
    MODES.map { |mode| :"model_#{mode}" }
  end

  def self.draft_model_attributes
    MODES.map { |mode| :"draft_model_#{mode}" }
  end

  def self.ransackable_attributes(_auth = nil)
    %w[id provider default_model max_duration_seconds created_at updated_at]
  end

  def self.ransackable_associations(_auth = nil) = []

  private

  def clean_mode_map(value)
    coerce_hash(value).each_with_object({}) do |(mode, model), acc|
      mode  = mode.to_s
      model = model.to_s.strip
      acc[mode] = model if MODES.include?(mode) && model.present?
    end
  end

  # Keep only known moods with a non-blank url; trim url/title/attribution.
  def clean_music_map(value)
    coerce_hash(value).each_with_object({}) do |(mood, entry), acc|
      mood = mood.to_s
      next unless MUSIC_MOODS.include?(mood)

      h = entry.respond_to?(:to_unsafe_h) ? entry.to_unsafe_h : (entry.respond_to?(:to_h) ? entry.to_h : {})
      url = h['url'].to_s.strip
      next if url.blank?

      acc[mood] = { 'url' => url, 'title' => h['title'].to_s.strip, 'attribution' => h['attribution'].to_s.strip }.compact_blank
    end
  end

  def merge_music(mood, key, value)
    current = music_tracks[mood.to_s] || {}
    self.music_tracks = music_tracks.merge(mood.to_s => current.merge(key => value.to_s))
  end

  def coerce_hash(value)
    return {} if value.blank?
    return value.to_unsafe_h if value.respond_to?(:to_unsafe_h)

    value.respond_to?(:to_h) ? value.to_h : {}
  end
end
