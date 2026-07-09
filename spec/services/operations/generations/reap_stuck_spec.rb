# frozen_string_literal: true

require 'rails_helper'

# The reaper is the safety net that stops generations/creatives spinning
# "Gerando…" forever when a synchronous studio generation dies mid-flight — a
# vendor outage (e.g. OpenRouter out of credits), a request timeout, or a killed
# worker. Thresholds are kind-aware: image/carousel are fast, video is slow.
RSpec.describe Operations::Generations::ReapStuck do
  let(:user) { User.create!(email: 'reap@agencios.app', password: 'secret123', name: 'Reap') }
  let(:workspace) { Operations::Workspaces::SetupForUser.call(user: user, name: 'Reap Co') }

  def creative(status:)
    workspace.creatives.create!(creative_type: 'feed_image', source: :generated, status: status)
  end

  def generation(kind:, status:, age:, creative_status: :generating)
    c = creative(status: creative_status)
    gen = workspace.generations.create!(user: user, creative: c, kind: kind, status: status, provider: 'test')
    # Bypass the auto-touch so the record looks stranded.
    gen.update_column(:updated_at, age.ago)
    c.update_column(:updated_at, age.ago)
    gen
  end

  it 'fails an image generation stuck in processing past the sync threshold' do
    gen = generation(kind: :image, status: :processing, age: 20.minutes)

    expect(described_class.call).to eq(1)
    expect(gen.reload.status).to eq('failed')
    expect(gen.failure_reason).to be_present
    expect(gen.creative.reload.status).to eq('failed')
  end

  it 'leaves a recently-updated processing generation alone' do
    gen = generation(kind: :image, status: :processing, age: 2.minutes)

    expect(described_class.call).to eq(0)
    expect(gen.reload.status).to eq('processing')
  end

  it 'does not reap a video generation still within its wide margin' do
    gen = generation(kind: :video, status: :processing, age: 30.minutes)

    expect(described_class.call).to eq(0)
    expect(gen.reload.status).to eq('processing')
  end

  it 'reaps a video generation stuck well past any real render' do
    gen = generation(kind: :video, status: :processing, age: 4.hours)

    expect(described_class.call).to eq(1)
    expect(gen.reload.status).to eq('failed')
  end

  it 'fails an orphan generating creative that never got a generation' do
    orphan = creative(status: :generating)
    orphan.update_column(:updated_at, 20.minutes.ago)

    expect(described_class.call).to eq(1)
    expect(orphan.reload.status).to eq('failed')
  end

  it 'never touches ready creatives or completed generations' do
    ready = creative(status: :ready)
    ready.update_column(:updated_at, 1.day.ago)
    done = generation(kind: :image, status: :completed, age: 1.day, creative_status: :ready)

    expect(described_class.call).to eq(0)
    expect(ready.reload.status).to eq('ready')
    expect(done.reload.status).to eq('completed')
  end
end
