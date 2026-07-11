# frozen_string_literal: true

# Client-facing project notifications (the agency looping its client in).
class ProjectMailer < ApplicationMailer
  # A read-only snapshot of the project's planned/produced content, sent to
  # whichever addresses the manager typed in (not necessarily the client's
  # registered email). One row per ticket: name, type(s), and target date —
  # deliberately light on internal detail (no briefs, no assignees).
  def scope_summary(project:, recipients:)
    @project = project
    @client = project.client
    @tickets = project.tickets.active.board_ordered
    @brand_workspace = project.workspace
    with_recipient_locale(@client) do
      mail(to: recipients, subject: I18n.t('mailers.project.scope_summary.subject', project: @project.name))
    end
  end

  helper_method :creative_type_label

  # Creative-type labels mirror the frontend's CREATIVE_TYPE_META
  # (app/frontend/lib/constants.js) — this email is the one place that renders
  # them server-side.
  def creative_type_label(key)
    I18n.t("mailers.project.creative_types.#{key}", default: key.to_s.humanize)
  end
end
