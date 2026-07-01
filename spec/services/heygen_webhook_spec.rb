# frozen_string_literal: true

require 'rails_helper'

# Locks in the HeyGen webhook contract: signature is the hex HMAC-SHA256 of the
# RAW body computed with the endpoint secret, carried in `Heygen-Signature`;
# stale deliveries are rejected; success finalizes, fail marks failed.
RSpec.describe Controllers::Webhooks::Heygen::Create do
  let(:secret) { 'whsec_test_123' }
  let(:user) { Operations::Users::Register.call(email: 'hg@agencios.app', password: 'secret123', name: 'HG', workspace_name: 'HG Agency').first }
  let(:workspace) { user.workspaces.first }
  let(:generation) do
    workspace.generations.create!(user: user, kind: :video, status: :processing, external_id: 'vid_xyz789')
  end

  def payload(event_type:, video_id:, url: "https://files.heygen.com/v/#{video_id}.mp4")
    JSON.generate(
      event_id: 'evt_1', event_type: event_type,
      event_data: { video_id: video_id, url: url, callback_id: 'creative_1' }
    )
  end

  def sign(body) = OpenSSL::HMAC.hexdigest('SHA256', secret, body)

  before do
    allow(Vendors::Heygen::Webhook).to receive(:webhook_secret).and_return(secret)
    generation # touch
  end

  def call(body, signature:, timestamp: Time.current.to_i.to_s)
    parsed = JSON.parse(body).deep_symbolize_keys
    described_class.call(signature: signature, timestamp: timestamp, payload: body, params: ActionController::Parameters.new(parsed))
  end

  it 'finalizes the generation on avatar_video.success with a valid signature' do
    body = payload(event_type: 'avatar_video.success', video_id: 'vid_xyz789')
    expect(Operations::Creatives::FinalizeGeneration).to receive(:call)
      .with(hash_including(generation: generation, video_url: 'https://files.heygen.com/v/vid_xyz789.mp4'))

    expect(call(body, signature: sign(body))).to eq(:ok)
  end

  it 'marks the generation failed on avatar_video.fail' do
    body = JSON.generate(event_type: 'avatar_video.fail', event_data: { video_id: 'vid_xyz789', msg: 'render error' })
    expect(call(body, signature: sign(body))).to eq(:ok)
    expect(generation.reload).to be_status_failed
  end

  it 'rejects a bad signature (the bug: wrong/empty header → 401, nothing finalized)' do
    body = payload(event_type: 'avatar_video.success', video_id: 'vid_xyz789')
    expect(Operations::Creatives::FinalizeGeneration).not_to receive(:call)
    expect(call(body, signature: 'deadbeef')).to eq(:unauthorized)
    expect(call(body, signature: nil)).to eq(:unauthorized)
  end

  it 'rejects a stale delivery even when correctly signed (replay defense)' do
    body = payload(event_type: 'avatar_video.success', video_id: 'vid_xyz789')
    expect(Operations::Creatives::FinalizeGeneration).not_to receive(:call)
    expect(call(body, signature: sign(body), timestamp: 1.hour.ago.to_i.to_s)).to eq(:unauthorized)
  end
end
