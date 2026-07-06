# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Tickets::ProjectSettings do
  it 'sanitizes to known keys with typed coercion' do
    out = described_class.sanitize(
      'require_client_approval' => 'true',
      'auto_publish_after_approval' => false,
      'posting_window' => { 'weekdays' => %w[1 3 5], 'times' => ['9:0', '18:00'], 'min_gap_minutes' => '120', 'timezone' => 'America/Sao_Paulo' },
      'junk' => 'x'
    )
    expect(out['require_client_approval']).to be(true)
    expect(out['auto_publish_after_approval']).to be(false)
    expect(out['posting_window']['weekdays']).to eq([1, 3, 5])
    expect(out['posting_window']['times']).to eq(['09:00', '18:00'])
    expect(out['posting_window']['min_gap_minutes']).to eq(120)
    expect(out).not_to have_key('junk')
  end

  it 'resolves defaults with workspace auto_publish fallback' do
    ws = Workspace.create!(name: 'WS', slug: "ws-#{SecureRandom.hex(4)}")
    ws.create_setting!(auto_publish_default: true)
    client = Client.create!(workspace: ws, name: 'C')
    project = Project.create!(workspace: ws, client: client, name: 'P', status: :active)

    resolved = described_class.resolve(project)
    expect(resolved['require_client_approval']).to be(false) # default
    expect(resolved['auto_publish_after_approval']).to be(true) # from workspace
    expect(resolved['posting_window']['weekdays']).to eq([1, 2, 3, 4, 5])
  end
end
