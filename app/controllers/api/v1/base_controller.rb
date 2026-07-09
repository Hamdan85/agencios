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

      # Total paywall: once authenticated + tenant resolved, block every endpoint
      # for a workspace that isn't billing-active (no free tier). Auth, identity,
      # billing, and workspace-switching controllers opt out via `skip_billing_gate`
      # so the user can always see their status, pay, or switch to a paid workspace.
      before_action :require_active_billing

      def self.skip_billing_gate(**opts)
        skip_before_action :require_active_billing, **opts
      end

      # Declared first so it sits at the bottom of the handler stack: every more
      # specific handler below is checked before this catch-all.
      rescue_from StandardError,                           with: :internal_error
      rescue_from ActionController::InvalidAuthenticityToken, with: :invalid_csrf
      rescue_from ActiveRecord::RecordNotFound,            with: :not_found
      rescue_from ActiveRecord::RecordInvalid,             with: :record_invalid
      rescue_from ActionController::ParameterMissing,      with: :bad_request
      rescue_from Pundit::NotAuthorizedError,              with: :not_authorized
      rescue_from Operations::Errors::Forbidden,           with: :forbidden
      rescue_from Operations::Errors::SeatLimitReached,    with: :payment_required
      rescue_from Operations::Errors::ClientLimitReached,  with: :payment_required
      rescue_from Operations::Errors::BillingRequired,     with: :payment_required
      rescue_from Operations::Errors::InsufficientCredits, with: :insufficient_credits
      rescue_from Operations::Errors::InvalidTransition,   with: :unprocessable
      rescue_from Operations::Errors::Invalid,             with: :unprocessable

      private

      def render_ok(data = {})
        render json: data
      end

      def render_created(data = {})
        render json: data, status: :created
      end

      def render_accepted(data = {})
        render json: data, status: :accepted
      end

      def render_error(msg, status: :unprocessable_entity)
        render json: { error: msg }, status: status
      end

      def invalid_csrf(_error) = render json: { error: 'Token CSRF inválido.', code: 'invalid_csrf' },
                                        status: :forbidden

      # Framework exceptions carry raw, technical, often-English messages — e.g.
      # `Couldn't find Creative with 'id'=245 [WHERE "creatives"."workspace_id" = $1]`.
      # Every API error is customer-facing, so those must never reach the user: we
      # map each framework exception to friendly Portuguese copy and only surface
      # `error.message` for our own Operations::Errors::* (which already carry
      # customer-safe copy) and model validations.
      def not_found(_error) = render_error('Não encontramos esse item — ele pode já ter sido removido.',
                                           status: :not_found)
      def bad_request(_error) = render_error('Requisição inválida. Confira os dados e tente novamente.',
                                             status: :bad_request)
      def not_authorized(_error) = render json: { error: 'Você não tem permissão para realizar esta ação.',
                                                   code: 'forbidden' }, status: :forbidden

      # Model validation failures — surface the validation copy without the
      # technical "Validation failed:" prefix that Rails prepends to #message.
      def record_invalid(error)
        render_error(error.record.errors.full_messages.to_sentence.presence ||
          'Não foi possível salvar. Confira os dados e tente novamente.')
      end

      def unprocessable(error) = render_error(error.message)
      def forbidden(error) = render json: { error: error.message, code: 'forbidden' }, status: :forbidden

      # Last-resort catch-all: an unhandled exception here is a bug. Log it loudly
      # (and re-raise outside production so it crashes visibly in dev/test rather
      # than being masked), but never leak internals to the customer — the user
      # gets a generic, friendly 500.
      def internal_error(error)
        raise error unless Rails.env.production?

        Rails.logger.error(
          "[api] unhandled #{error.class}: #{error.message}\n#{Array(error.backtrace).first(20).join("\n")}"
        )
        render_error('Algo deu errado do nosso lado. Tente novamente em instantes.',
                     status: :internal_server_error)
      end

      def payment_required(error) = render json: { error: error.message, code: 'billing_required' },
                                           status: :payment_required

      def insufficient_credits(error)
        render json: {
          error: error.message, code: 'insufficient_credits',
          required: error.required, available: error.available
        }, status: :payment_required
      end

      # Enforced on every authenticated endpoint except the allowlisted ones.
      # No active subscription / trial-with-card / godfathered ⇒ 402.
      def require_active_billing
        return if performed?
        return if Current.workspace.nil? # unauthenticated flows resolve no tenant
        return if Current.workspace.billing_active?

        render json: {
          error: 'Assinatura necessária para acessar o workspace.',
          code: 'billing_required'
        }, status: :payment_required
      end

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
