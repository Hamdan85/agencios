# frozen_string_literal: true

module Admin
  # JSON source for the admin model-picker typeahead (AI config pages). Proxies
  # OpenRouter's public model catalog per kind (text / image / video) with
  # server-side search + pagination, so staff can only pick slugs OpenRouter
  # actually serves for that use. Staff-only, read-only.
  class OpenrouterModelsController < ApplicationController
    before_action :authenticate_staff!

    def index
      kind = params[:kind].to_s
      unless Vendors::OpenRouter::Catalog::KINDS.include?(kind)
        return render json: { error: I18n.t('admin.model_picker.unknown_kind') }, status: :unprocessable_entity
      end

      render json: Vendors::OpenRouter::Actions::ListModels.call(
        kind: kind, query: params[:q], page: params[:page].to_i
      )
    rescue Vendors::Base::Error => e
      render json: { error: e.message, results: [], has_more: false }, status: :bad_gateway
    end

    private

    # The staff gate redirects HTML requests to '/'; for this JSON endpoint
    # answer 401 instead so the picker can show a clean error state.
    def authenticate_staff!
      return if current_staff_user

      render json: { error: I18n.t('api.errors.staff_only') }, status: :unauthorized
    end
  end
end
