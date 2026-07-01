# frozen_string_literal: true

module Webhooks
  # Instagram-Login and Threads webhooks (their apps have separate app secrets
  # from the Facebook app, so they can't share the /webhooks/meta endpoint which
  # verifies with the Facebook secret). Same Meta-family scheme: GET hub.challenge
  # handshake + POST signed with X-Hub-Signature-256. `:provider` comes from the
  # route (instagram | threads).
  class SocialController < BaseController
    def handle
      return verify_subscription if request.get?

      status = Controllers::Webhooks::Social::Receive.call(
        provider: params[:provider],
        signature: request.headers['X-Hub-Signature-256'],
        payload: request.raw_post
      )
      head status
    rescue StandardError => e
      Rails.logger.warn("[Webhooks::Social] #{params[:provider]}: #{e.message}")
      head :ok
    end

    # POST deauthorize callback — Meta sends a signed_request when a user removes
    # the app. We revoke that user's accounts for this provider.
    def deauthorize
      Controllers::Webhooks::Social::Deauthorize.call(
        provider: params[:provider], signed_request: params[:signed_request]
      )
      head :ok
    rescue StandardError => e
      Rails.logger.warn("[Webhooks::Social] deauthorize #{params[:provider]}: #{e.message}")
      head :ok
    end

    # POST data deletion request callback — Meta sends a signed_request; we delete
    # the user's data and respond with JSON { url, confirmation_code } (a status
    # page + tracking code, required by Meta).
    def data_deletion
      result = Controllers::Webhooks::Social::DataDeletion.call(
        provider: params[:provider], signed_request: params[:signed_request]
      )
      render json: result
    end

    private

    def verify_subscription
      challenge = Controllers::Webhooks::Social::VerifySubscription.call(
        provider: params[:provider], params: params
      )
      return render plain: challenge.to_s if challenge

      head :forbidden
    end
  end
end
