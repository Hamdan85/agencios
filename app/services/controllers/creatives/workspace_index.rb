# frozen_string_literal: true

module Controllers
  module Creatives
    # GET /creatives — all creatives in the workspace, filterable for the Studio gallery.
    class WorkspaceIndex < Base
      def initialize(params:)
        @params = params
      end

      def call
        deny_guests!
        scope = workspace.creatives.order(created_at: :desc)
        scope = scope.where(creative_type: @params[:type]) if @params[:type].present?
        # `types` (array) — the studio picker restricts to a ticket's SUPPORTED
        # types so unsupported pieces never show up as choices.
        scope = scope.where(creative_type: Array(@params[:types])) if @params[:types].present?
        scope = scope.where(status: @params[:status]) if @params[:status].present?
        # The ticket-side "use from Studio" picker only offers creatives not yet
        # attached to any ticket — a creative belongs to at most one ticket.
        scope = scope.where(ticket_id: nil) if ActiveModel::Type::Boolean.new.cast(@params[:unassigned])
        scope = apply_client_filter(scope)
        scope = apply_search(scope)
        {
          creatives: serialize_collection(scope.limit(200), CreativeSerializer),
          clients: workspace.clients.order(:name).map { |c| { id: c.id, name: c.name } }
        }
      end

      private

      def apply_client_filter(scope)
        return scope if @params[:client_id].blank?

        cid = @params[:client_id].to_i
        scope.left_joins(ticket: { project: :client })
             .where('creatives.client_id = ? OR clients.id = ?', cid, cid)
      end

      def apply_search(scope)
        return scope if @params[:q].blank?

        q = "%#{@params[:q].strip}%"
        scope.where('creatives.name ILIKE ? OR creatives.caption ILIKE ?', q, q)
      end
    end
  end
end
