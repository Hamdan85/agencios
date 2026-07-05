# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Operations::Tickets::CascadeFields do
  before do
    @user, @workspace = Operations::Users::Register.call(
      email: 'cf@agencios.app', password: 'secret123', name: 'CF', workspace_name: 'CF Agency'
    )
    Current.workspace = @workspace
    Current.membership = @workspace.memberships.find_by(user: @user)
    client = @workspace.clients.create!(name: 'ACME')
    project = @workspace.projects.create!(client: client, name: 'P', color: '#7C3AED')
    @ticket = Operations::Tickets::Create.call(
      workspace: @workspace, user: @user, params: { project_id: project.id, title: 'T' }
    )
    # Never hit the AI — assert on which stages we ASK to regenerate.
    allow(Operations::Ai::FillFields).to receive(:call)
  end

  after { Current.reset }

  # Give a stage some AI-fillable content so the cascade treats it as "worked".
  def seed(status, values)
    @ticket.update!(fields: @ticket.fields.merge(status => @ticket.fields_for(status).merge(values)))
  end

  it 'regenerates only the LATER stages that already hold content' do
    seed('scoping', 'copy_brief' => 'algo')       # downstream + has content → refresh
    seed('production', 'caption' => 'legenda')     # downstream + has content → refresh
    # 'scheduled' left blank → skipped

    described_class.call(ticket: @ticket, from_status: 'ideation')

    expect(Operations::Ai::FillFields).to have_received(:call)
      .with(hash_including(ticket: @ticket, status: 'scoping', only_blank: false, note: false))
    expect(Operations::Ai::FillFields).to have_received(:call)
      .with(hash_including(status: 'production'))
    expect(Operations::Ai::FillFields).not_to have_received(:call).with(hash_including(status: 'scheduled'))
  end

  it 'never touches the edited stage itself or the earlier ones' do
    seed('ideation', 'brief' => 'o brief')
    seed('production', 'caption' => 'legenda')

    described_class.call(ticket: @ticket, from_status: 'production')

    # production is the edited stage; scoping/ideation are earlier → none refreshed.
    expect(Operations::Ai::FillFields).not_to have_received(:call)
  end

  it 'no-ops (no note, no AI) when every later stage is still blank' do
    allow(Operations::Notes::Create).to receive(:call)

    described_class.call(ticket: @ticket, from_status: 'ideation')

    expect(Operations::Ai::FillFields).not_to have_received(:call)
    expect(Operations::Notes::Create).not_to have_received(:call)
  end

  it 'writes a single consolidated note naming the refreshed stages' do
    allow(Operations::Notes::Create).to receive(:call)
    seed('scoping', 'copy_brief' => 'algo')

    described_class.call(ticket: @ticket, from_status: 'ideation')

    expect(Operations::Notes::Create).to have_received(:call).once
      .with(hash_including(kind: :ai))
  end
end
