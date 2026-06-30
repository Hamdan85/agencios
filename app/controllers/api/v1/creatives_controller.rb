# frozen_string_literal: true

module Api
  module V1
    # Creatives: nested under a ticket (index/create/destroy/generate) AND
    # workspace-level (workspace_index/update/workspace_destroy) for the Studio gallery.
    class CreativesController < BaseController
      # Ticket-nested actions
      def index   = render_ok(Controllers::Creatives::Index.call(params:))
      def create  = render_created(Controllers::Creatives::Create.call(params:))
      def destroy = render_ok(Controllers::Creatives::Destroy.call(params:))

      # POST /tickets/:ticket_id/creatives/generate — body { kind, params }
      def generate = render_created(Controllers::Creatives::Generate.call(params:))

      # Workspace-level actions (Studio gallery)
      def workspace_index   = render_ok(Controllers::Creatives::WorkspaceIndex.call(params:))
      def update            = render_ok(Controllers::Creatives::Update.call(params:))
      def workspace_destroy = render_ok(Controllers::Creatives::WorkspaceDestroy.call(params:))
    end
  end
end
