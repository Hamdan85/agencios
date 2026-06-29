# frozen_string_literal: true

module Controllers
  module Projects
    class Index < Base
      def initialize(params:)
        @params = params
      end

      def call
        projects = workspace.projects.includes(:client).order(created_at: :desc)
        projects = projects.where(client_id: @params[:client_id]) if @params[:client_id].present?
        projects = projects.where(status: @params[:status]) if @params[:status].present?
        projects = projects.where.not(status: :archived) if ActiveModel::Type::Boolean.new.cast(@params[:exclude_archived])
        projects = projects.where("projects.name ILIKE ?", "%#{escape_like(@params[:q])}%") if @params[:q].present?
        collection_payload(projects, ProjectSerializer, :projects, @params)
      end
    end
  end
end
