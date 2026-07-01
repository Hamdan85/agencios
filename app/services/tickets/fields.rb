# frozen_string_literal: true

module Tickets
  # Value object mapping each ticket status to the structured field keys allowed
  # in `ticket.fields[status]`. The backend validates that incoming keys belong
  # to the current status group; the frontend mirrors this with Zod schemas.
  module Fields
    ALLOWED = {
      "ideation" => %w[brief objective target_persona references content_pillar format_hypothesis],
      "scoping" => %w[creative_type channels copy_brief script deliverables due_date effort_estimate],
      "production" => %w[creative_id caption hashtags approval_status internal_notes],
      "scheduled" => %w[creative_id post_mode scheduled_at schedule first_comment link_in_bio auto_publish],
      "published" => %w[posts metrics monitor_alerts],
      "retrospective" => %w[outcome_metrics wins improvements repeat_recommendation lessons_learned],
      "done" => %w[final_metrics deliverable_links case_study]
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
