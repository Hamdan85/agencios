# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Approval slots' do
  let(:ws) { Workspace.create!(name: 'WS', slug: "ws-#{SecureRandom.hex(4)}") }
  let(:client) { Client.create!(workspace: ws, name: 'C') }
  let(:project) { Project.create!(workspace: ws, client: client, name: 'P', status: :active) }
  let(:ticket) do
    Ticket.create!(workspace: ws, project: project, status: :production,
                   fields: { 'scoping' => { 'creative_types' => %w[carousel feed_image] } })
  end

  def creative(type, approval: 'pending')
    Creative.create!(workspace: ws, ticket: ticket, creative_type: type, status: :ready, approval_state: approval)
  end

  it 'accepts the not_selected approval state and excludes it from approvable' do
    keep = creative('carousel')
    loser = creative('carousel', approval: 'not_selected')
    expect(ticket.approvable_creatives).to include(keep)
    expect(ticket.approvable_creatives).not_to include(loser)
  end

  it 'groups approvable creatives into slots by type, in creative_types_list order' do
    car_a = creative('carousel')
    car_b = creative('carousel')
    img = creative('feed_image')
    slots = ticket.approval_slots
    expect(slots.keys).to eq(%w[carousel feed_image])
    expect(slots['carousel']).to contain_exactly(car_a, car_b)
    expect(slots['feed_image']).to eq([img])
  end

  it 'is fully_approved only when every slot has an approved winner' do
    car_a = creative('carousel')
    creative('carousel') # a second option
    img = creative('feed_image')
    expect(ticket.fully_approved?).to be(false)

    # Approve one carousel winner + mark the other not_selected; approve the image.
    car_a.update!(approval_state: 'approved')
    ticket.approval_slots['carousel'].reject { |c| c == car_a }.each { |c| c.update!(approval_state: 'not_selected') }
    expect(ticket.reload.fully_approved?).to be(false) # feed_image slot still pending

    img.update!(approval_state: 'approved')
    expect(ticket.reload.fully_approved?).to be(true)
    expect(ticket.approved_winners).to contain_exactly(car_a, img)
  end
end
