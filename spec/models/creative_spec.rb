# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Creative do
  it 'defaults approval_state to pending and supports polymorphic reviewer' do
    ws = Workspace.create!(name: 'WS', slug: "ws-#{SecureRandom.hex(4)}")
    creative = Creative.create!(workspace: ws, creative_type: 'carousel')
    expect(creative.approval_pending?).to be(true)

    user = User.create!(email: 'a@b.co', password: 'password123', name: 'A')
    creative.update!(approval_state: 'approved', reviewed_by: user, decided_at: Time.current)
    expect(creative.reload.reviewed_by).to eq(user)
    expect(creative.approval_approved?).to be(true)
  end
end
