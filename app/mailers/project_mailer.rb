# frozen_string_literal: true

# Client-facing project notifications (the agency looping its client in).
class ProjectMailer < ApplicationMailer
  # PT-BR labels for creative types, mirroring the frontend's CREATIVE_TYPE_META
  # (app/frontend/lib/constants.js) — this email is the one place that renders
  # them server-side.
  CREATIVE_TYPE_LABELS = {
    "reel" => "Reel", "feed_image" => "Imagem", "carousel" => "Carrossel",
    "story" => "Story", "ugc_video" => "Vídeo UGC", "ad" => "Anúncio",
    "thumbnail" => "Thumbnail", "cover" => "Capa"
  }.freeze

  # A read-only snapshot of the project's planned/produced content, sent to
  # whichever addresses the manager typed in (not necessarily the client's
  # registered email). One row per ticket: name, type(s), and target date —
  # deliberately light on internal detail (no briefs, no assignees).
  def scope_summary(project:, recipients:)
    @project = project
    @client = project.client
    @tickets = project.tickets.active.board_ordered
    @brand_workspace = project.workspace
    mail(to: recipients, subject: "Escopo de conteúdo — #{@project.name}")
  end

  helper_method :creative_type_label

  def creative_type_label(key)
    CREATIVE_TYPE_LABELS[key.to_s] || key.to_s.humanize
  end
end
