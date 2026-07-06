# frozen_string_literal: true

module Tickets
  # Value object for a project's approval/publishing/scheduling configuration,
  # stored in `projects.settings` (jsonb). Mirrors the Tickets::Fields pattern:
  # a single source of truth for allowed keys, typed coercion, and default
  # resolution (with a workspace-level fallback for auto-publish).
  module ProjectSettings
    module_function

    def defaults
      {
        'require_client_approval' => true,
        'auto_publish_after_approval' => false,
        'posting_window' => {
          'weekdays' => [1, 2, 3, 4, 5], # 0=Sun .. 6=Sat
          'times' => ['09:00', '12:00', '18:00'],
          'min_gap_minutes' => 120,
          'timezone' => 'America/Sao_Paulo'
        }
      }
    end

    # Keep only known keys, coercing to the right types. Unknown keys dropped.
    def sanitize(raw)
      raw = (raw || {}).to_h.stringify_keys
      out = {}
      out['require_client_approval'] = to_bool(raw['require_client_approval']) if raw.key?('require_client_approval')
      out['auto_publish_after_approval'] = to_bool(raw['auto_publish_after_approval']) if raw.key?('auto_publish_after_approval')
      out['posting_window'] = sanitize_window(raw['posting_window']) if raw.key?('posting_window')
      out
    end

    # Defaults, overlaid with the workspace auto-publish fallback, overlaid with
    # the project's own stored settings.
    def resolve(project)
      base = defaults
      ws_default = project.workspace.setting&.auto_publish_default
      base['auto_publish_after_approval'] = ws_default unless ws_default.nil?
      deep_merge(base, sanitize(project.settings))
    end

    def sanitize_window(raw)
      raw = (raw || {}).to_h.stringify_keys
      d = defaults['posting_window']
      {
        'weekdays' => Array(raw['weekdays']).map { |w| w.to_i }.select { |w| (0..6).cover?(w) }.uniq.presence || d['weekdays'],
        'times' => Array(raw['times']).filter_map { |t| normalize_time(t) }.uniq.presence || d['times'],
        'min_gap_minutes' => (raw['min_gap_minutes'].presence || d['min_gap_minutes']).to_i.clamp(0, 10_080),
        'timezone' => raw['timezone'].to_s.presence || d['timezone']
      }
    end

    # "9:0" -> "09:00"; invalid -> nil.
    def normalize_time(value)
      m = value.to_s.strip.match(/\A(\d{1,2}):(\d{1,2})\z/)
      return nil unless m

      h = m[1].to_i
      min = m[2].to_i
      return nil unless (0..23).cover?(h) && (0..59).cover?(min)

      format('%02d:%02d', h, min)
    end

    def to_bool(value)
      ActiveModel::Type::Boolean.new.cast(value) || false
    end

    def deep_merge(a, b)
      a.merge(b) { |_k, av, bv| av.is_a?(Hash) && bv.is_a?(Hash) ? deep_merge(av, bv) : bv }
    end
  end
end
