# frozen_string_literal: true

module Operations
  module Tickets
    class Create < Operations::Base
      def initialize(workspace:, user:, params:)
        @workspace = workspace
        @user = user
        @params = params
      end

      def call
        # New work only lands on live campaigns of live clients — an archived
        # client is read-only (this is what makes the plan's client limit real).
        project = @workspace.projects.find(@params[:project_id])
        raise Errors::Invalid, "A campanha \"#{project.name}\" está arquivada — reative-a para criar tickets." if project.status_archived?

        ensure_client_active!(project.client)

        channels = Array(@params[:channels]).compact_blank
        types = Array(@params[:creative_types].presence || @params[:creative_type]).map(&:to_s).compact_blank

        ticket = Ticket.new(
          workspace: @workspace,
          created_by: @user,
          project_id: @params[:project_id],
          title: @params[:title],
          assignee_id: @params[:assignee_id],
          priority: @params[:priority] || :medium,
          due_date: @params[:due_date],
          scheduled_at: @params[:scheduled_at],
          channels: channels,
          creative_type: types.first,
          creative_types: types,
          fields: scoping_seed(channels, types),
          strategy_session_id: @params[:strategy_session_id],
          status: :ideation,
          position: next_position
        )
        ticket.save!

        # A ticket is born in Ideação — persist any context captured at creation
        # (e.g. the brief) into the status-scoped field bag via the canonical op.
        if ideation_fields.present?
          Operations::Tickets::UpdateFields.call(ticket: ticket, status: :ideation, values: ideation_fields)
        end

        Operations::Notes::Create.call(ticket: ticket, user: nil, kind: :system,
                                       body: "Ticket criado por #{@user&.display_name || 'sistema'}.")
        Broadcaster.board(@workspace.id, 'ticket_created', ticket_id: ticket.id, status: ticket.status)
        notify_assignee(ticket)
        ticket
      end

      def notify_assignee(ticket)
        Operations::Push::Notify.call(
          user: ticket.assignee, actor: @user,
          title: 'Novo ticket atribuído a você',
          body: ticket.title,
          path: "/tickets/#{ticket.id}"
        )

        assignee = ticket.assignee
        return if assignee.nil? || assignee.email.blank? || assignee.id == @user&.id

        TicketMailer.assigned(ticket: ticket, assignee: assignee, actor: @user).deliver_later
      end

      private

      # Seed the scoping field bag when the strategy is already known at creation
      # (e.g. a ticket materialized from an AI content plan). The scoping panel
      # reads channels/creative types from `fields['scoping']`, not the top-level
      # columns, so without this seed a chatbot-created ticket shows them blank.
      # Returns the full fields hash for Ticket.new (empty when nothing to seed).
      def scoping_seed(channels, types)
        seed = {}
        seed['channels'] = channels if channels.present?
        seed['creative_types'] = types if types.present?
        seed.present? ? { 'scoping' => seed } : {}
      end

      def ideation_fields
        raw = @params[:fields]
        return {} if raw.blank?

        (raw.respond_to?(:to_unsafe_h) ? raw.to_unsafe_h : raw).to_h.stringify_keys
      end

      def next_position
        (@workspace.tickets.where(status: :ideation).maximum(:position) || -1) + 1
      end
    end
  end
end
