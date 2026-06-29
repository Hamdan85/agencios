# frozen_string_literal: true

module Api
  module V1
    # Creatives nested under a ticket. Members may create/upload and generate;
    # destroy is manager-gated (enforced in the service).
    class CreativesController < BaseController
      def index   = render_ok(Controllers::Creatives::Index.call(params:))
      def create  = render_created(Controllers::Creatives::Create.call(params:))
      def destroy = render_ok(Controllers::Creatives::Destroy.call(params:))

      # POST /tickets/:ticket_id/creatives/generate — body { kind, params }
      def generate = render_created(Controllers::Creatives::Generate.call(params:))
    end
  end
end
