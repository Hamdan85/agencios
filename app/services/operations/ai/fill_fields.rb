# frozen_string_literal: true

module Operations
  module Ai
    # The per-phase "Gerar com IA" action: fills the ticket's CURRENT status
    # fields using everything produced in the earlier funnel stages. Status-aware
    # via Prompts::FieldFill; writes through Operations::Tickets::UpdateFields so
    # the same sanitize + mirror-columns + broadcast path is reused.
    class FillFields < Operations::Base
      # only_blank: when true, never overwrite fields the team already filled —
      # only the empty ones are completed. Used by the automatic carry-over on
      # status advance; the manual "Gerar com IA" button refills everything.
      def initialize(ticket:, only_blank: false)
        @ticket = ticket
        @status = ticket.status.to_s
        @only_blank = only_blank
      end

      def call
        keys = Prompts::FieldFill.fillable_keys(@status)
        keys = keys.reject { |k| @ticket.fields_for(@status)[k].present? } if @only_blank
        return { filled: [] } if keys.empty?

        data = AiAdapter.complete_tool(
          build_prompt, tool: Prompts::FieldFill.tool(@status, channels: @ticket.channels),
          max_tokens: 1300, operation: 'fill_fields', subject: @ticket
        )
        return { filled: [] } if data.blank?

        values = coerce(data.slice(*keys))
        return { filled: [] } if values.empty?

        Operations::Tickets::UpdateFields.call(ticket: @ticket, status: @status, values: values)
        Operations::Notes::Create.call(
          ticket: @ticket, user: nil, kind: :ai,
          body: "Campos da etapa “#{label}” preenchidos com IA: #{values.keys.join(', ')}."
        )
        { filled: values.keys }
      end

      private

      def build_prompt
        Prompts::FieldFill.new(
          workspace: @ticket.workspace, client: @ticket.project.client,
          status: @status, status_label: label, ctx: context_dump
        )
      end

      # Labeled dump of every prior (and current) phase's non-blank fields, plus
      # the ticket's headline meta — the raw material the model fills from.
      def context_dump
        lines = ["Ticket: #{@ticket.display_title}"]
        lines << "Tipo de criativo: #{@ticket.creative_type}" if @ticket.creative_type.present?
        lines << "Canais: #{Array(@ticket.channels).join(', ')}" if @ticket.channels.present?

        current_idx = Ticket::WORKFLOW.index(@status.to_sym) || 0
        Ticket::WORKFLOW.each_with_index do |status, idx|
          break if idx > current_idx

          fields = @ticket.fields_for(status.to_s)
          pairs = fields.filter_map do |key, value|
            value = Array(value).reject(&:blank?).join('; ') if value.is_a?(Array)
            next if value.blank?

            "  - #{key}: #{value}"
          end
          next if pairs.empty?

          lines << "[#{Ticket::STATUS_LABELS[status.to_s]}]"
          lines.concat(pairs)
        end

        lines.join("\n")
      end

      # Light type coercion so the persisted shape matches the field contracts —
      # the tool's input_schema already guarantees the JSON *shape* (array vs.
      # string vs. object); this just trims/normalizes the values within it.
      def coerce(values)
        values.each_with_object({}) do |(key, value), out|
          out[key] =
            case key
            when 'deliverables', 'wins', 'improvements'
              Array(value).map { |v| v.to_s.strip }.reject(&:blank?)
            when 'hashtags'
              Array(value).map { |v| v.to_s.sub(/\A#/, '').strip }.reject(&:blank?)
            when 'captions'
              value.is_a?(Hash) ? value.transform_values { |v| v.to_s.strip }.compact_blank : nil
            when 'repeat_recommendation'
              %w[repeat iterate retire].include?(value.to_s) ? value.to_s : nil
            else
              value.is_a?(Array) ? value.join("\n") : value
            end
        end.compact
      end

      def label
        Ticket::STATUS_LABELS[@status] || @status
      end
    end
  end
end
