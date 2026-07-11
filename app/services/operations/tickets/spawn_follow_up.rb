# frozen_string_literal: true

module Operations
  module Tickets
    # Spawns a new ideation ticket derived from a finished one, pre-filled with the
    # source's context, and links it back via a TicketRelation. Driven by
    # ChangeStatus when a ticket reaches `done` recommending iterate / repeat.
    class SpawnFollowUp < Operations::Base
      KIND_FOR = { 'iterate' => :iteration_of, 'repeat' => :repetition_of }.freeze

      def initialize(source:, recommendation:, user: nil)
        @source = source
        @recommendation = recommendation.to_s
        @user = user
      end

      def call
        kind = KIND_FOR[@recommendation]
        return nil unless kind

        new_ticket = Operations::Tickets::Create.call(
          workspace: @source.workspace,
          user: @user || @source.created_by,
          params: build_params
        )

        relation = TicketRelation.create!(
          workspace: @source.workspace,
          ticket: new_ticket,
          related_ticket: @source,
          kind: kind
        )

        annotate(new_ticket, relation)
        new_ticket
      end

      private

      def build_params
        {
          project_id: @source.project_id,
          title: "[#{prefix_label}] #{@source.title}",
          channels: @source.channels,
          creative_type: @source.creative_type,
          priority: @source.priority,
          fields: ideation_fields
        }
      end

      # The new ticket's title/brief are persisted plain text (no key column) —
      # render once in the workspace language.
      def prefix_label
        I18n.with_locale(workspace_locale(@source.workspace)) do
          I18n.t("operations.follow_up.prefix.#{@recommendation}")
        end
      end

      def workspace_locale(ws)
        I18n.available_locales.find { |l| l.to_s == ws&.locale.to_s } || I18n.default_locale
      end

      # Carry over the original brief/ideation context. For an iteration, prepend
      # the (plain-text) lessons learned so the new cycle starts from them.
      def ideation_fields
        base = @source.fields_for('ideation').to_h.dup
        if @recommendation == 'iterate'
          lessons = strip_html(@source.fields_for('retrospective')['lessons_learned'])
          if lessons.present?
            header = I18n.with_locale(workspace_locale(@source.workspace)) { I18n.t('operations.follow_up.lessons_header') }
            base['brief'] = ["#{header}\n#{lessons}", base['brief']].reject(&:blank?).join("\n\n")
          end
        end
        base
      end

      def strip_html(text)
        ActionController::Base.helpers.strip_tags(text.to_s).to_s.strip
      end

      def annotate(new_ticket, relation)
        Operations::Notes::Create.call(
          ticket: new_ticket, user: nil, kind: :system,
          body: "#{relation.kind_label} ##{@source.id} — #{@source.title}"
        )
        Operations::Notes::Create.call(
          ticket: @source, user: nil, kind: :system,
          i18n_key: @recommendation == 'iterate' ? 'notes.follow_up.spawned_iteration' : 'notes.follow_up.spawned_repetition',
          i18n_params: { id: new_ticket.id, title: new_ticket.title }
        )
      end
    end
  end
end
