# frozen_string_literal: true

module Api
  module V1
    # Generic ticket files (uploaded across every workflow status). Members
    # upload/manage; guests get read-only access. Destroy is uploader-or-manager
    # gated (enforced in the service).
    class AttachmentsController < BaseController
      def index   = render_ok(Controllers::Attachments::Index.call(params:))
      def create  = render_created(Controllers::Attachments::Create.call(params:))
      def update  = render_ok(Controllers::Attachments::Update.call(params:))
      def destroy = render_ok(Controllers::Attachments::Destroy.call(params:))
    end
  end
end
