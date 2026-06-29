# frozen_string_literal: true

module Api
  module V1
    class BaseController < ActionController::API
      include ActionController::Cookies
      # CSRF: the SPA shell emits form_authenticity_token in a <meta> tag; axios
      # echoes it back as the X-CSRF-Token header on mutating requests.
      include ActionController::RequestForgeryProtection
      protect_from_forgery with: :exception
      # ActionController::API doesn't inherit the per-env forgery config from
      # ActionController::Base — sync it explicitly (on in dev/prod, off in test).
      self.allow_forgery_protection = ActionController::Base.allow_forgery_protection
      include Pundit::Authorization
      include Authentication

      rescue_from ActionController::InvalidAuthenticityToken, with: :invalid_csrf
      rescue_from ActiveRecord::RecordNotFound,            with: :not_found
      rescue_from ActiveRecord::RecordInvalid,             with: :unprocessable
      rescue_from ActionController::ParameterMissing,      with: :bad_request
      rescue_from Pundit::NotAuthorizedError,              with: :forbidden
      rescue_from Operations::Errors::Forbidden,           with: :forbidden
      rescue_from Operations::Errors::SeatLimitReached,    with: :payment_required
      rescue_from Operations::Errors::BillingRequired,     with: :payment_required
      rescue_from Operations::Errors::InvalidTransition,   with: :unprocessable
      rescue_from Operations::Errors::Invalid,             with: :unprocessable

      private

      def render_ok(data = {})
        render json: data
      end

      def render_created(data = {})
        render json: data, status: :created
      end

      def render_error(msg, status: :unprocessable_entity)
        render json: { error: msg }, status: status
      end

      def invalid_csrf(_error) = render json: { error: "Token CSRF inválido.", code: "invalid_csrf" }, status: :forbidden
      def not_found(error)    = render_error(error.message, status: :not_found)
      def bad_request(error)  = render_error(error.message, status: :bad_request)
      def unprocessable(error) = render_error(error.message)
      def forbidden(error)    = render json: { error: error.message, code: "forbidden" }, status: :forbidden
      def payment_required(error) = render json: { error: error.message, code: "billing_required" }, status: :payment_required

      def current_user       = Current.user
      def current_workspace  = Current.workspace
      def current_membership = Current.membership

      # Pundit policies are keyed on the active membership role.
      def pundit_user = Current.membership

      def serialize(record, serializer_class, **opts)
        serializer_class.new(record, opts).as_json
      end

      def serialize_collection(records, serializer_class, **opts)
        records.map { |record| serializer_class.new(record, opts).as_json }
      end
    end
  end
end
