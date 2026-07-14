# frozen_string_literal: true

module Tickets
  # Value object mapping each ticket status to the structured field keys allowed
  # in `ticket.fields[status]`. The backend validates that incoming keys belong
  # to the current status group; the frontend mirrors this with Zod schemas.
  module Fields
    ALLOWED = {
      # Ideation: WHY this content exists — the idea and who it's for.
      'ideation' => %w[brief objective target_persona references content_pillar format_hypothesis],
      # Scoping: WHAT will be made and by when — formats, channels, direction.
      'scoping' => %w[creative_types channels copy_brief script deliverables due_date effort_estimate],
      # Production: the words that ship with the pieces + direction for generation.
      'production' => %w[caption hashtags production_scope],
      # Aprovação has no editable fields: the stage IS the decision (approve /
      # request changes), taken on the creatives themselves.
      'approval' => [],
      # Publication: the PostingPanel's working state (per-network captions etc.)
      # + what Operations::Tickets::Publish persists about the chosen posting.
      'scheduled' => %w[creative_id creative_ids post_mode scheduled_at first_comment link_in_bio captions],
      # No ar is read-only monitoring (posts + PostMetrics are real records).
      'published' => [],
      # Retrospective: the performance review (lessons auto-drafted from metrics).
      'retrospective' => %w[wins improvements repeat_recommendation lessons_learned],
      # Concluído surfaces the AI case-study summary (ai_summaries) — no field bag.
      'done' => []
    }.freeze

    module_function

    def allowed_keys(status)
      ALLOWED.fetch(status.to_s, [])
    end

    # Keep only keys that belong to the given status group.
    def sanitize(status, incoming)
      keys = allowed_keys(status)
      (incoming || {}).slice(*keys)
    end
  end
end
