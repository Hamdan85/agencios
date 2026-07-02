# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Operations::Ai::FillFields do
  before do
    @user, @workspace = Operations::Users::Register.call(
      email: 'ff@agencios.app', password: 'secret123', name: 'FF', workspace_name: 'FF Agency'
    )
    Current.workspace = @workspace
    Current.membership = @workspace.memberships.find_by(user: @user)
    @client = @workspace.clients.create!(name: 'ACME')
    @project = @workspace.projects.create!(client: @client, name: 'Camp', color: '#7C3AED')
  end

  after { Current.reset }

  # The whole point of slice 4: a ticket born from a plan is a slim card, so the
  # per-ticket brief fill must still see the planning conversation — otherwise the
  # nuances discussed in chat (tone, do's & don'ts) are lost.
  it 'feeds the originating strategy conversation into the fill context' do
    session = @workspace.strategy_sessions.create!(
      project: @project, user: @user, status: 'proposed',
      proposed_plan: { 'summary' => 'Série Animais Advogados, tom fofo e leve.' },
      messages: [
        { 'role' => 'user', 'content' => 'Rinoceronte: não seja tosco, mas de forma gentil e sem polêmica.' },
        { 'role' => 'assistant', 'content' => 'Fechado — tom fofo, nada agressivo.' }
      ]
    )
    ticket = Operations::Tickets::Create.call(
      workspace: @workspace, user: @user,
      params: { project_id: @project.id, title: 'Rinoceronte — não seja tosco',
                creative_type: 'carousel', strategy_session_id: session.id }
    )

    dump = described_class.new(ticket: ticket).send(:context_dump)

    expect(dump).to include('Conversa de estratégia')
    expect(dump).to include('Série Animais Advogados')
    expect(dump).to include('gentil e sem polêmica')
    expect(dump).to include('ESTRATEGISTA:')
  end

  it 'omits the strategy block for a ticket with no session' do
    ticket = Operations::Tickets::Create.call(
      workspace: @workspace, user: @user, params: { project_id: @project.id, title: 'Avulso' }
    )
    expect(described_class.new(ticket: ticket).send(:context_dump)).not_to include('Conversa de estratégia')
  end

  # The brief is the flagship ideation field — the "Atualizar campos com IA" action
  # must be able to fill it (it was silently excluded, so AI-created tickets always
  # landed with an empty brief and regenerate never touched it).
  it 'makes the ideation brief AI-fillable' do
    expect(Prompts::FieldFill.fillable_keys('ideation')).to include('brief')
    expect(Prompts::FieldFill.tool('ideation')['input_schema']['properties']).to have_key('brief')
  end
end
