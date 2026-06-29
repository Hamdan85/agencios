# frozen_string_literal: true

module Api
  module V1
    class NotesController < BaseController
      def index  = render_ok(Controllers::Notes::Index.call(params:))
      def create = render_created(Controllers::Notes::Create.call(params:))
    end
  end
end
