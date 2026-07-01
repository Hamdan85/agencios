# frozen_string_literal: true

module Oauth
  # RFC 7591 Dynamic Client Registration. Claude POSTs its client metadata here
  # and gets back a client_id (and, for confidential clients, a secret). Public
  # by spec; abuse is bounded by rack-attack throttling + https-only redirect
  # validation (see Controllers::Oauth::Register).
  class RegistrationsController < ActionController::API
    def create
      render json: Controllers::Oauth::Register.call(params: params), status: :created
    rescue Operations::Errors::Invalid => e
      render json: { error: 'invalid_client_metadata', error_description: e.message },
             status: :bad_request
    end
  end
end
