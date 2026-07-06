# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Operations::Scheduling::NextSlot do
  include ActiveSupport::Testing::TimeHelpers

  let(:ws) { Workspace.create!(name: 'WS', slug: "ws-#{SecureRandom.hex(4)}") }
  let(:client) { Client.create!(workspace: ws, name: 'C') }
  let(:project) do
    Project.create!(workspace: ws, client: client, name: 'P', status: :active,
                    settings: { 'posting_window' => { 'weekdays' => [1, 2, 3, 4, 5], 'times' => ['09:00', '18:00'], 'min_gap_minutes' => 120, 'timezone' => 'America/Sao_Paulo' } })
  end

  around { |ex| travel_to(Time.zone.parse('2026-07-06 08:00:00 -03:00')) { ex.run } } # Monday

  it 'keeps a future desired date when collision-free' do
    desired = Time.zone.parse('2026-07-08 15:00:00 -03:00')
    expect(described_class.call(project: project, desired_at: desired)).to be_within(1.second).of(desired)
  end

  it 'rolls a past desired date to the next window slot' do
    slot = described_class.call(project: project, desired_at: Time.zone.parse('2026-07-01 09:00:00 -03:00'))
    # next window slot after "now" (Mon 08:00) is Mon 09:00 local
    expect(slot.in_time_zone('America/Sao_Paulo').strftime('%Y-%m-%d %H:%M')).to eq('2026-07-06 09:00')
  end

  it 'skips a slot that collides with an existing scheduled post' do
    ticket = Ticket.create!(workspace: ws, project: project, status: :scheduled)
    acct = SocialAccount.create!(workspace: ws, client: client, provider: :instagram)
    Post.create!(workspace: ws, ticket: ticket, social_account: acct, status: :scheduled,
                 scheduled_at: Time.zone.parse('2026-07-06 09:00:00 -03:00'))
    slot = described_class.call(project: project, desired_at: nil)
    # 09:00 is taken (±120min), so it lands on the 18:00 slot
    expect(slot.in_time_zone('America/Sao_Paulo').strftime('%H:%M')).to eq('18:00')
  end
end
