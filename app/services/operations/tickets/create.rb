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
        ticket = Ticket.new(
          workspace: @workspace,
          created_by: @user,
          project_id: @params[:project_id],
          title: @params[:title],
          assignee_id: @params[:assignee_id],
          priority: @params[:priority] || :medium,
          due_date: @params[:due_date],
          scheduled_at: @params[:scheduled_at],
          channels: Array(@params[:channels]).compact_blank,
          creative_type: @params[:creative_type],
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
                                       body: "Ticket criado por #{@user&.display_name || "sistema"}.")
        Broadcaster.board(@workspace.id, "ticket_created", ticket_id: ticket.id, status: ticket.status)
        notify_assignee(ticket)
        ticket
      end

      def notify_assignee(ticket)
        Operations::Push::Notify.call(
          user: ticket.assignee, actor: @user,
          title: "Novo ticket atribuído a você",
          body: ticket.title,
          path: "/tickets/#{ticket.id}"
        )
      end

      private

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
