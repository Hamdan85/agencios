# frozen_string_literal: true

require 'rails_helper'

RSpec.describe PortalChannel, type: :channel do
  let(:owner) { User.create!(email: "o-#{SecureRandom.hex(3)}@agencios.app", password: 'secret123', name: 'O') }
  let(:ws) { Operations::Workspaces::SetupForUser.call(user: owner, name: 'Studio') }
  let(:client) { ws.clients.create!(name: 'ACME') }

  before { stub_connection(current_user: nil) } # portal is login-less

  it 'streams the client portal for a valid token' do
    subscribe(token: client.approval_token!)
    expect(subscription).to be_confirmed
    expect(subscription).to have_stream_from("portal_#{client.id}")
  end

  it 'rejects an invalid token' do
    subscribe(token: 'not-a-token')
    expect(subscription).to be_rejected
  end
end
