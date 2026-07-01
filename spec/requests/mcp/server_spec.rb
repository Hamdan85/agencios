# frozen_string_literal: true

require 'rails_helper'

# The remote MCP endpoint Claude connects to: bearer auth + the JSON-RPC surface.
RSpec.describe 'MCP server endpoint', type: :request do
  before { ActiveJob::Base.queue_adapter = :test }

  let(:setup) do
    user, workspace = Operations::Users::Register.call(
      email: 'srv@agencios.app', password: 'secret123', name: 'Srv', workspace_name: 'Srv Agency'
    )
    Current.reset
    # The Claude connector is an Agência+ feature (Mcp::ToolContext gate).
    workspace.subscription.update!(plan: :agencia, status: 'active')
    client = workspace.clients.create!(name: 'ACME')
    project = workspace.projects.create!(client: client, name: 'Camp', color: '#7C3AED')
    { user: user, workspace: workspace, project: project }
  end

  let(:application) do
    Doorkeeper::Application.create!(name: 'Claude', redirect_uri: 'https://claude.ai/cb',
                                    scopes: 'read write', confidential: false)
  end

  def token_for(user, scopes: 'read write')
    Doorkeeper::AccessToken.create!(
      application: application, resource_owner_id: user.id, scopes: scopes, expires_in: 7200
    ).token
  end

  def rpc(body, token: nil)
    headers = { 'CONTENT_TYPE' => 'application/json' }
    headers['Authorization'] = "Bearer #{token}" if token
    post '/mcp', params: body.to_json, headers: headers
  end

  def call_tool(name, args, token:)
    rpc({ jsonrpc: '2.0', id: 1, method: 'tools/call', params: { name: name, arguments: args } }, token: token)
    JSON.parse(response.body)['result']
  end

  it 'challenges an unauthenticated request with 401 + WWW-Authenticate' do
    rpc({ jsonrpc: '2.0', id: 1, method: 'initialize', params: {} })
    expect(response).to have_http_status(:unauthorized)
    expect(response.headers['WWW-Authenticate']).to include('resource_metadata=')
  end

  it 'negotiates protocol on initialize with a valid token' do
    token = token_for(setup[:user])
    rpc({ jsonrpc: '2.0', id: 1, method: 'initialize', params: { protocolVersion: '2025-06-18' } }, token: token)
    expect(response).to have_http_status(:ok)
    expect(JSON.parse(response.body).dig('result', 'serverInfo', 'name')).to eq('agencios')
  end

  it 'lists the tool catalogue' do
    token = token_for(setup[:user])
    rpc({ jsonrpc: '2.0', id: 1, method: 'tools/list' }, token: token)
    names = JSON.parse(response.body).dig('result', 'tools').map { |t| t['name'] }
    expect(names).to include('list_workspaces', 'get_board', 'create_ticket', 'advance_ticket')
  end

  it 'creates and advances a ticket through the reused service layer' do
    token = token_for(setup[:user])
    created = call_tool('create_ticket',
                        { workspace: setup[:workspace].slug, project_id: setup[:project].id,
                          title: 'Reel via MCP', creative_type: 'reel' }, token: token)
    expect(created['isError']).to be(false)
    ticket_id = created.dig('structuredContent', 'ticket', 'id')

    advanced = call_tool('advance_ticket',
                         { workspace: setup[:workspace].slug, id: ticket_id, to_status: 'scoping' }, token: token)
    expect(advanced['isError']).to be(false)
    expect(Ticket.find(ticket_id).status).to eq('scoping')
    expect(Ticket.find(ticket_id).ticket_status_logs.count).to eq(1) # went through ChangeStatus
  end

  it 'denies a write tool to a read-only token (scope gate)' do
    token = token_for(setup[:user], scopes: 'read')
    result = call_tool('create_ticket',
                       { workspace: setup[:workspace].slug, project_id: setup[:project].id, title: 'x' },
                       token: token)
    expect(result['isError']).to be(true)
    expect(result.dig('content', 0, 'text')).to include('write')
  end

  it 'refuses a workspace the user is not a member of (tenant isolation)' do
    other_user = Operations::Users::Register.call(
      email: 'other@agencios.app', password: 'secret123', name: 'Other', workspace_name: 'Other Agency'
    ).first
    Current.reset
    token = token_for(other_user)

    result = call_tool('get_board', { workspace: setup[:workspace].slug }, token: token)
    expect(result['isError']).to be(true)
    expect(result.dig('content', 0, 'text')).to match(/not found among your workspaces/i)
  end

  it 'rejects a revoked token' do
    access = Doorkeeper::AccessToken.create!(application: application, resource_owner_id: setup[:user].id,
                                             scopes: 'read write', expires_in: 7200)
    access.revoke
    rpc({ jsonrpc: '2.0', id: 1, method: 'tools/list' }, token: access.token)
    expect(response).to have_http_status(:unauthorized)
  end
end
