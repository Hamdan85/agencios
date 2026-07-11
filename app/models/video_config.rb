# frozen_string_literal: true

# Singleton row holding the VIDEO-generation engine routing (admin-editable, no
# deploy). The platform runs exactly TWO engines — one DRAFT (fast/cheap preview)
# and one FINAL (best quality) — the user never picks an engine, and the model no
# longer varies by generation mode. The OpenRouter API key stays in credentials;
# only the non-secret provider choice + the two model slugs + the duration cap
# live here. Read through Vendors::OpenRouter::Video. `instance` returns the row,
# or an unsaved defaults-populated record when the table is empty so reads never
# write (mirrors AiConfig).
class VideoConfig < ApplicationRecord
  # A generation MODE is the fundamental KIND of video — it routes what references
  # attach and how the storyboard frames scenes (NOT the engine anymore; that's a
  # single draft/final pair). The UI exposes the two everyday ones (avatar /
  # product); the ORCHESTRATOR can pick any (character / scene / motion too).
  MODES = %w[avatar product character scene motion].freeze

  # Modes the generate dialog offers directly (the rest are director-only).
  UI_MODES = %w[avatar product].freeze

  # Locale-aware: `MODE_LABELS[mode]` renders the current-locale label.
  MODE_LABELS = Hash.new { |_h, k| I18n.t("admin.video_config.mode_labels.#{k}", default: k.to_s) }.freeze

  # One-line brief the storyboard uses to pick the right mode.
  MODE_GUIDANCE = {
    'avatar'    => 'a real person talking to camera (authentic UGC, selfie framing, natural light); distribute the script across the scenes',
    'product'   => 'the product is the hero, shown in selling angles and motion, faithful to the reference photos',
    'character' => 'a recurring stylized/illustrated/animated CHARACTER or mascot acts/narrates (not a real person) — keep it identical across scenes',
    'scene'     => 'cinematic scenes / b-roll / lifestyle (locations, moments, people in context) — no talking-head, no single product hero',
    'motion'    => 'design-forward, abstract or kinetic visuals (textures, shapes, energy, motion graphics feel)'
  }.freeze

  QUALITIES = %w[draft final].freeze

  # The two engines the platform runs (editable in ActiveAdmin; these are only the
  # seed / fallback). Both are Google Veo 3.1 — FINAL = veo-3.1-fast (the cheaper
  # mid tier), DRAFT = veo-3.1-lite (the cheapest image-capable model on OpenRouter,
  # ~$0.03/s). A generation renders draft-first, then upgrades to final on approval.
  #
  # WHY Veo, not Seedance: Seedance 2.0 categorically REJECTS person input images
  # (references AND continuity frames) with a privacy block, so it cannot run the
  # avatar/UGC/multi-scene-person pipeline. Veo accepts real people (empirically
  # verified end-to-end) with no special flag, and Veo-lite is even cheaper than
  # Seedance-fast. Trade-off: Veo renders FIXED 4/6/8s clips and LOCKS to 8s once a
  # reference/frame image is attached (REFERENCE_LOCKED_SECONDS) — the trim
  # pipeline handles that (render 8s, trim to the audio-driven target).
  DEFAULT_MODEL = 'google/veo-3.1-fast'
  DEFAULT_DRAFT_MODEL = 'google/veo-3.1-lite'

  # The DISCRETE clip lengths (seconds) an engine actually renders. A scene's
  # RENDER duration must be one of these; the shown scene is then trimmed to its
  # audio-driven target in compose (so the final length isn't forced to a clip
  # multiple). Keyed by model slug; anything unlisted uses DEFAULT_CLIP_SECONDS.
  #
  # These are best-effort defaults — confirm each engine's real supported lengths
  # against its API (GET /api/v1/videos/models) and add overrides here. Sorted asc.
  DEFAULT_CLIP_SECONDS = [4, 6, 8].freeze
  MODEL_CLIP_SECONDS = {
    'google/veo-3.1'              => [4, 6, 8],
    'google/veo-3.1-fast'         => [4, 6, 8],
    'google/veo-3.1-lite'         => [4, 6, 8],
    # Seedance 2.0 renders 4–15s (verified against ByteDance/Replicate/Segmind);
    # the safe discrete set. OpenRouter's exact enforced enum isn't published —
    # query GET /api/v1/videos/models if renders reject a length. Both tiers
    # (full + -fast) share the same range.
    'bytedance/seedance-2.0'      => [4, 5, 6, 8, 10, 12, 15],
    'bytedance/seedance-2.0-fast' => [4, 5, 6, 8, 10, 12, 15]
  }.freeze

  # Models whose duration is FORCED to a single length once a reference/frame
  # image is attached (Veo 3.1 locks to 8s with reference or first-frame images —
  # and our scenes almost always carry a continuity seed and/or references). When
  # this applies we render that fixed length and TRIM to the target in compose —
  # exactly the "render 8s and trim" path these engines require. Keyed by slug.
  REFERENCE_LOCKED_SECONDS = {
    'google/veo-3.1'      => 8,
    'google/veo-3.1-fast' => 8,
    'google/veo-3.1-lite' => 8
  }.freeze

  # Background-music moods the storyboard can pick from. The video model never
  # generates music — the compose step burns the chosen mood's track (from the
  # admin-managed `music_tracks` base) under the audio.
  MUSIC_MOODS = %w[upbeat calm corporate energetic emotional epic playful cinematic].freeze

  # Locale-aware: `MUSIC_MOOD_LABELS[mood]` renders the current-locale label.
  MUSIC_MOOD_LABELS = Hash.new { |_h, k| I18n.t("admin.video_config.music_mood_labels.#{k}", default: k.to_s) }.freeze

  # Consistent voice: one FIXED Cartesia voice per video (a voice_id) so the
  # spoken voice is identical across every scene (the model's own per-clip voice
  # drifts). `voice_catalog` maps a friendly label → voice_id (admin-managed, one
  # `label = voice_id` per line); `default_voice_id` is the fallback. Empty ⇒ the
  # feature degrades to the model's native audio (like an empty music catalog).
  VOICE_LANGUAGE = 'pt'

  PROVIDERS = ['', AiUsageLog::PROVIDER_OPENROUTER].freeze

  # The background-music provider — an adapter switch resolved through
  # Vendors::Music. Jamendo (royalty-free) is the default; Epidemic Sound is the
  # licensed alternative (needs an entitled API account before it can download).
  MUSIC_PROVIDERS = %w[jamendo epidemic_sound].freeze
  # Locale-aware: `MUSIC_PROVIDER_LABELS[provider]` renders the current-locale label.
  MUSIC_PROVIDER_LABELS = Hash.new { |_h, k| I18n.t("admin.video_config.music_provider_labels.#{k}", default: k.to_s) }.freeze
  DEFAULT_MUSIC_PROVIDER = 'jamendo'

  validates :provider, inclusion: { in: PROVIDERS }, allow_nil: true
  validates :music_provider, inclusion: { in: MUSIC_PROVIDERS }
  validates :max_duration_seconds, numericality: { greater_than: 0, less_than_or_equal_to: 120 }

  # The active music provider key, never blank (defaults to Jamendo).
  def music_provider
    super.presence || DEFAULT_MUSIC_PROVIDER
  end

  def self.instance
    first || new
  end

  # The OpenRouter video slug for a quality tier — mode-independent now (there are
  # exactly two engines). `final` (the default) resolves `default_model` else the
  # coded seed; `draft` resolves `draft_model`, else the coded draft seed, else
  # falls back to the final chain. `mode` is accepted for call-site compatibility
  # but ignored. Never blank.
  def model_for(_mode = nil, quality: 'final')
    if quality.to_s == 'draft'
      slug = draft_model.presence || DEFAULT_DRAFT_MODEL
      return slug if slug.present?
    end
    default_model.presence || DEFAULT_MODEL
  end

  # The clip lengths the engines support. A scene renders both a draft and a final
  # clip, so the duration must be valid for BOTH tiers — return their intersection
  # (falling back to the final tier's set if they don't overlap). `mode` is
  # accepted for call-site compatibility but ignored.
  def clip_seconds_for(_mode = nil)
    final = MODEL_CLIP_SECONDS[model_for(quality: 'final')] || DEFAULT_CLIP_SECONDS
    draft = MODEL_CLIP_SECONDS[model_for(quality: 'draft')] || DEFAULT_CLIP_SECONDS
    (final & draft).presence || final
  end

  # Snap an arbitrary seconds value to the NEAREST supported clip length (ties
  # round down — the cheaper clip). Blank/zero → the shortest.
  def snap_seconds(seconds, mode = nil)
    opts = clip_seconds_for(mode)
    secs = seconds.to_i
    return opts.min if secs <= 0

    opts.min_by { |o| [(o - secs).abs, o] }
  end

  # The clip length to actually RENDER for a target duration: the SMALLEST
  # supported length that is >= the target, so the rendered clip is always long
  # enough to be TRIMMED back down to the (audio-driven) target. Falls back to
  # the longest supported clip when the target exceeds every option (compose then
  # fits the audio into that longest clip). Blank/zero → the shortest.
  def clip_length_for(target_seconds, mode = nil)
    opts = clip_seconds_for(mode)
    secs = target_seconds.to_f
    return opts.min if secs <= 0

    opts.find { |o| o >= secs - 0.01 } || opts.max
  end

  # The clip length to RENDER for a target, accounting for engines that FORCE a
  # fixed duration when a reference/frame image is attached (Veo → 8s). When such
  # a lock applies (the current tier's model is reference-locked AND the scene
  # carries reference/seed media), render that fixed length; otherwise snap up
  # normally. Compose trims the shown scene back to the target either way, so the
  # final length is still audio-driven — this only keeps the SUBMIT valid.
  def render_clip_length(target_seconds, quality: 'final', has_reference_media: false)
    locked = has_reference_media ? REFERENCE_LOCKED_SECONDS[model_for(quality: quality)] : nil
    return locked if locked

    clip_length_for(target_seconds)
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

  # --- Voice catalog (Cartesia) ---------------------------------------------

  # The catalog as { label => voice_id } (empty ⇒ no configured voices).
  def voices = voice_catalog.is_a?(Hash) ? voice_catalog : {}

  # Resolve a director/chat voice pick to a concrete Cartesia voice_id: an exact
  # label, else a raw voice_id already in the catalog, else the default. Nil when
  # nothing resolves (feature stays off — model native audio).
  def resolved_voice_id(pick = nil)
    p = pick.to_s.strip
    return voices[p] if voices.key?(p)
    return p if p.present? && voices.value?(p)

    default_voice_id.presence
  end

  # Only store labels mapped to a non-blank voice_id — no admin input can corrupt it.
  def voice_catalog=(value)
    super(clean_voice_map(value))
  end

  # ActiveAdmin editing: one `label = voice_id` per line (labels are free text,
  # so no fixed per-slot fields like the music moods).
  def voice_catalog_text
    voices.map { |label, id| "#{label} = #{id}" }.join("\n")
  end

  def voice_catalog_text=(text)
    self.voice_catalog = text.to_s.each_line.each_with_object({}) do |line, acc|
      label, id = line.split('=', 2).map { |s| s.to_s.strip }
      acc[label] = id if label.present? && id.present?
    end
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

  def self.ransackable_attributes(_auth = nil)
    %w[id provider music_provider default_model draft_model max_duration_seconds default_voice_id voice_dub_in_post created_at updated_at]
  end

  def self.ransackable_associations(_auth = nil) = []

  private

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

  # Keep only { label => voice_id } with both non-blank (trimmed).
  def clean_voice_map(value)
    coerce_hash(value).each_with_object({}) do |(label, id), acc|
      label = label.to_s.strip
      id    = id.to_s.strip
      acc[label] = id if label.present? && id.present?
    end
  end

  def coerce_hash(value)
    return {} if value.blank?
    return value.to_unsafe_h if value.respond_to?(:to_unsafe_h)

    value.respond_to?(:to_h) ? value.to_h : {}
  end
end
