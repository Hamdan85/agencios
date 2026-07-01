# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Ticket follow-up on done (iterate / repeat)' do
  before do
    ActiveJob::Base.queue_adapter = :test
    @user, @workspace = Operations::Users::Register.call(
      email: 'fu@agencios.app', password: 'secret123', name: 'FU', workspace_name: 'FU Agency'
    )
    Current.workspace = @workspace
    Current.membership = @workspace.memberships.find_by(user: @user)
    @client = @workspace.clients.create!(name: 'ACME')
    @project = @workspace.projects.create!(client: @client, name: 'Camp', color: '#7C3AED')
    allow(Broadcaster).to receive(:board)
    allow(Broadcaster).to receive(:ticket)
    allow(Operations::Push::Notify).to receive(:call)
  end

  after { Current.reset }

  def advance_to_done(ticket)
    Operations::Tickets::ChangeStatus.call(ticket, 'done', user: @user, force: true)
  end

  it 'spawns a linked ideation ticket when the recommendation is iterate' do
    source = Operations::Tickets::Create.call(
      workspace: @workspace, user: @user,
      params: { project_id: @project.id, title: 'Reel X', channels: %w[instagram], creative_type: 'reel', fields: { brief: 'Brief original' } }
    )
    source.update!(status: :retrospective, fields: source.fields.merge(
      'retrospective' => { 'repeat_recommendation' => 'iterate', 'lessons_learned' => '<p>mais <strong>UGC</strong></p>' }
    ))

    expect { advance_to_done(source) }.to change { @workspace.tickets.count }.by(1)

    relation = TicketRelation.find_by(related_ticket: source)
    expect(relation.kind).to eq('iteration_of')

    spawned = relation.ticket
    expect(spawned.status).to eq('ideation')
    expect(spawned.title).to include('Iteração')
    expect(spawned.channels).to eq(%w[instagram])
    # Lessons (HTML stripped) are carried into the new brief alongside the original.
    expect(spawned.fields_for('ideation')['brief']).to include('mais UGC').and include('Brief original')
  end

  it 'uses repetition_of for the repeat recommendation' do
    source = Operations::Tickets::Create.call(
      workspace: @workspace, user: @user, params: { project_id: @project.id, title: 'Reel Y' }
    )
    source.update!(status: :retrospective, fields: { 'retrospective' => { 'repeat_recommendation' => 'repeat' } })

    advance_to_done(source)
    expect(TicketRelation.find_by(related_ticket: source).kind).to eq('repetition_of')
  end

  it 'does nothing when the recommendation is retire (or absent)' do
    source = Operations::Tickets::Create.call(
      workspace: @workspace, user: @user, params: { project_id: @project.id, title: 'Reel Z' }
    )
    source.update!(status: :retrospective, fields: { 'retrospective' => { 'repeat_recommendation' => 'retire' } })

    expect { advance_to_done(source) }.not_to change(Ticket, :count)
  end
end
