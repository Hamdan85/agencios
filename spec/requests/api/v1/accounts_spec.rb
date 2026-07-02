# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Accounts', type: :request do
  include ActiveJob::TestHelper

  before do
    ActiveJob::Base.queue_adapter = :test
    @user, @workspace = Operations::Users::Register.call(
      email: 'owner@agencios.app', password: 'secret123', name: 'Owner', workspace_name: 'Talk Agency'
    )
    Current.reset
    activate_billing(@workspace)
  end

  def login(email = 'owner@agencios.app', password = 'secret123')
    post '/api/v1/session', params: { email: email, password: password }, as: :json
    expect(response).to have_http_status(:ok)
  end

  describe 'PATCH /api/v1/account' do
    it 'updates the display name' do
      login
      patch '/api/v1/account', params: { user: { name: 'New Name' } }, as: :json
      expect(response).to have_http_status(:ok)
      expect(@user.reload.name).to eq('New Name')
    end

    it 'is reachable even when the workspace is not billing-active (skip_billing_gate)' do
      _user, unpaid_ws = Operations::Users::Register.call(
        email: 'broke@agencios.app', password: 'secret123', name: 'Broke', workspace_name: 'No Plan'
      )
      Current.reset
      login('broke@agencios.app')

      patch '/api/v1/account', params: { user: { name: 'Still Works' } }, as: :json
      expect(response).to have_http_status(:ok)
      expect(unpaid_ws).to be_present
    end
  end

  describe 'PATCH /api/v1/account/password' do
    it 'rejects a wrong current password' do
      login
      patch '/api/v1/account/password',
            params: { current_password: 'wrong', password: 'newsecret123' }, as: :json
      expect(response).to have_http_status(:unprocessable_content)
      expect(@user.reload.authenticate('newsecret123')).to be_falsey
    end

    it 'rejects a too-short new password' do
      login
      patch '/api/v1/account/password',
            params: { current_password: 'secret123', password: 'short' }, as: :json
      expect(response).to have_http_status(:unprocessable_content)
    end

    it 'changes the password with the correct current password' do
      login
      patch '/api/v1/account/password',
            params: { current_password: 'secret123', password: 'newsecret123' }, as: :json
      expect(response).to have_http_status(:ok)
      expect(@user.reload.authenticate('newsecret123')).to be_truthy
    end
  end

  describe 'e-mail change flow' do
    it 'stashes a pending e-mail and only applies it on confirmation' do
      login
      expect do
        post '/api/v1/account/email',
             params: { email: 'new@agencios.app', password: 'secret123' }, as: :json
      end.to have_enqueued_mail(AuthMailer, :confirm_email_change)

      expect(response).to have_http_status(:ok)
      @user.reload
      expect(@user.pending_email).to eq('new@agencios.app')
      expect(@user.email).to eq('owner@agencios.app') # not yet applied

      token = @user.generate_token_for(:email_change)
      post "/api/v1/account/email/confirm/#{token}"
      expect(response).to have_http_status(:ok)

      @user.reload
      expect(@user.email).to eq('new@agencios.app')
      expect(@user.pending_email).to be_nil
    end

    it 'rejects a wrong password' do
      login
      post '/api/v1/account/email',
           params: { email: 'new@agencios.app', password: 'wrong' }, as: :json
      expect(response).to have_http_status(:unprocessable_content)
      expect(@user.reload.pending_email).to be_nil
    end

    it 'rejects an e-mail already taken by another user' do
      User.create!(email: 'taken@agencios.app', password: 'secret123')
      login
      post '/api/v1/account/email',
           params: { email: 'taken@agencios.app', password: 'secret123' }, as: :json
      expect(response).to have_http_status(:unprocessable_content)
    end

    it 'rejects confirmation with an invalid token' do
      post '/api/v1/account/email/confirm/not-a-real-token'
      expect(response).to have_http_status(:unprocessable_content)
    end
  end
end
