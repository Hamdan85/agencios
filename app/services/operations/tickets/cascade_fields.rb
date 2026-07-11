# frozen_string_literal: true

module Operations
  module Tickets
    # When an earlier stage's content changes, re-derive the LATER stages so they
    # reflect the change instead of drifting out of sync. Complements CarryOver
    # (which seeds a stage's BLANK fields on advance): the cascade REGENERATES the
    # already-worked later stages after an edit to an earlier one.
    #
    # Guardrails:
    #   * Only stages that ALREADY hold content are refreshed — a still-blank future
    #     stage is left for CarryOver on advance, so editing ideation on a fresh
    #     ticket never eagerly generates a full production caption set.
    #   * Only content fields are rewritten (Operations::Ai::FillFields drives it);
    #     dates, switches, channels and other human decisions are never touched.
    #   * Runs the targets in funnel order so each stage sees the freshly-updated
    #     one above it.
    class CascadeFields < Operations::Base
      # Mirrors CarryOver's targets: retrospective is metrics-driven, published/done
      # carry no editable content, so only these three hold derived content.
      TARGET_STATUSES = %w[scoping production scheduled].freeze

      def initialize(ticket:, from_status:)
        @ticket = ticket
        @from_status = from_status.to_s
      end

      def call
        targets = downstream.select { |status| stage_has_content?(status) }
        return @ticket if targets.empty?

        targets.each do |status|
          Operations::Ai::FillFields.call(ticket: @ticket, status: status, only_blank: false, note: false)
        end

        # Status labels are DATA in the note params — render them once in the
        # workspace language (this runs off-request, where I18n.locale is default).
        from_name, labels = I18n.with_locale(workspace_locale(@ticket.workspace)) do
          [from_label, targets.map { |s| Ticket::STATUS_LABELS[s] || s }.join(', ')]
        end
        Operations::Notes::Create.call(
          ticket: @ticket, user: nil, kind: :ai,
          i18n_key: 'notes.cascade_fields',
          i18n_params: { from: from_name, labels: labels }
        )
        @ticket
      rescue StandardError => e
        Rails.logger.warn("[CascadeFields] ticket #{@ticket.id} from #{@from_status}: #{e.class}: #{e.message}")
        @ticket
      end

      private

      def downstream
        from_idx = Ticket::WORKFLOW.index(@from_status.to_sym)
        return [] if from_idx.nil?

        TARGET_STATUSES.select { |s| (Ticket::WORKFLOW.index(s.to_sym) || -1) > from_idx }
      end

      # A stage "has content" when any of its AI-fillable fields is already set —
      # the signal that the team has reached and worked it.
      def stage_has_content?(status)
        fields = @ticket.fields_for(status)
        Prompts::FieldFill.fillable_keys(status).any? { |k| fields[k].present? }
      end

      def from_label
        Ticket::STATUS_LABELS[@from_status] || @from_status
      end

      def workspace_locale(ws)
        I18n.available_locales.find { |l| l.to_s == ws&.locale.to_s } || I18n.default_locale
      end
    end
  end
end
