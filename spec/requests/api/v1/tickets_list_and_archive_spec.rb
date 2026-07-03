# frozen_string_literal: true

require 'rails_helper'

# Covers the global ticket list (filters + view + pagination), the board search,
# the clear-column / archive operations, and the paginated resource endpoints.
RSpec.describe 'Tickets list, search & archive', type: :request do
  before do
    ActiveJob::Base.queue_adapter = :test
    @user, @workspace = Operations::Users::Register.call(
      email: 'owner@agencios.app', password: 'secret123', name: 'Owner', workspace_name: 'Agency'
    )
    Current.reset
    # The workspace sits behind the total paywall until billing is active.
    activate_billing(@workspace)
    @client = @workspace.clients.create!(name: 'ACME Corp')
    @project = @workspace.projects.create!(client: @client, name: 'Launch', color: '#7C3AED')

    @reel = Operations::Tickets::Create.call(
      workspace: @workspace, user: @user,
      params: { project_id: @project.id, title: 'Reel de lançamento', creative_type: 'reel', channels: %w[instagram] }
    )
    @carousel = Operations::Tickets::Create.call(
      workspace: @workspace, user: @user,
      params: { project_id: @project.id, title: 'Carrossel institucional', creative_type: 'carousel', channels: %w[linkedin] }
    )
  end

  def login(email = 'owner@agencios.app', password = 'secret123')
    post '/api/v1/session', params: { email: email, password: password }, as: :json
    expect(response).to have_http_status(:ok)
  end

  def json = JSON.parse(response.body)

  describe 'GET /api/v1/tickets (global list)' do
    it 'lists all active tickets with row fields + pagination meta' do
      login
      get '/api/v1/tickets'
      expect(response).to have_http_status(:ok)
      expect(json['tickets'].size).to eq(2)
      row = json['tickets'].find { |t| t['title'] == 'Reel de lançamento' }
      expect(row['client']).to include('name' => 'ACME Corp')
      expect(row['archived']).to eq(false)
      expect(json['meta']).to include('page' => 1, 'total' => 2, 'has_more' => false)
    end

    it 'paginates with per/page and reports has_more' do
      login
      get '/api/v1/tickets', params: { per: 1, page: 1 }
      expect(json['tickets'].size).to eq(1)
      expect(json['meta']).to include('has_more' => true, 'total' => 2)
    end

    it 'searches by title via q' do
      login
      get '/api/v1/tickets', params: { q: 'carrossel' }
      titles = json['tickets'].map { |t| t['title'] }
      expect(titles).to eq(['Carrossel institucional'])
    end

    it 'filters by creative_type' do
      login
      get '/api/v1/tickets', params: { creative_type: 'reel' }
      expect(json['tickets'].map { |t| t['title'] }).to eq(['Reel de lançamento'])
    end
  end

  describe 'archive / clear column' do
    it 'archives a single ticket and surfaces it under the archived view' do
      login
      post "/api/v1/tickets/#{@reel.id}/archive"
      expect(response).to have_http_status(:ok)
      expect(@reel.reload.archived_at).to be_present

      get '/api/v1/tickets' # active only
      expect(json['tickets'].map { |t| t['id'] }).to contain_exactly(@carousel.id)

      get '/api/v1/tickets', params: { view: 'archived' }
      expect(json['tickets'].map { |t| t['id'] }).to contain_exactly(@reel.id)
    end

    it 'restores an archived ticket' do
      login
      Operations::Tickets::Archive.call(@reel, user: @user, archived: true)
      post "/api/v1/tickets/#{@reel.id}/unarchive"
      expect(response).to have_http_status(:ok)
      expect(@reel.reload.archived_at).to be_nil
    end

    it 'archiving CANCELS still-scheduled posts (an archived ticket must never publish)' do
      account = @client.social_accounts.create!(workspace: @workspace, provider: 'instagram')
      scheduled = Post.create!(workspace: @workspace, ticket: @reel, social_account: account,
                               status: :scheduled, scheduled_at: 1.day.from_now)
      published = Post.create!(workspace: @workspace, ticket: @reel, social_account: account,
                               status: :published, published_at: Time.current)

      Operations::Tickets::Archive.call(@reel, user: @user, archived: true)

      expect(Post.exists?(scheduled.id)).to be(false)   # canceled
      expect(Post.exists?(published.id)).to be(true)    # history preserved
      expect(@reel.notes.order(:created_at).last.body).to include('agendamento(s) de publicação cancelado(s)')
    end

    it 'clears the done column (bulk archive) for a manager' do
      login
      Operations::Tickets::ChangeStatus.call(@reel, 'done', user: @user, force: true)
      expect(@reel.reload.status).to eq('done')

      post '/api/v1/tickets/clear_column', params: { status: 'done' }, as: :json
      expect(response).to have_http_status(:ok)
      expect(json['archived_count']).to eq(1)
      expect(@reel.reload.archived_at).to be_present

      get '/api/v1/board'
      done = json['columns'].find { |c| c['status'] == 'done' }
      expect(done['tickets']).to be_empty
    end

    it 'forbids a non-manager from clearing a column' do
      member = User.create!(email: 'member@agencios.app', password: 'secret123', name: 'Member')
      Membership.create!(workspace: @workspace, user: member, role: :member)
      login('member@agencios.app')

      post '/api/v1/tickets/clear_column', params: { status: 'done' }, as: :json
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe 'GET /api/v1/tickets/ids (select-all)' do
    it 'returns every matching id across the whole result set (unpaginated)' do
      login
      get '/api/v1/tickets/ids'
      expect(response).to have_http_status(:ok)
      expect(json['ids']).to contain_exactly(@reel.id, @carousel.id)
    end

    it 'honors the same filters as the list (e.g. q search + project join)' do
      login
      get '/api/v1/tickets/ids', params: { q: 'carrossel' }
      expect(json['ids']).to contain_exactly(@carousel.id)
    end

    it 'scopes ids to the requested view (archived)' do
      login
      Operations::Tickets::Archive.call(@reel, user: @user, archived: true)
      get '/api/v1/tickets/ids', params: { view: 'archived' }
      expect(json['ids']).to contain_exactly(@reel.id)
    end
  end

  describe 'bulk destroy' do
    it 'permanently deletes the selected tickets for a manager' do
      login
      post '/api/v1/tickets/bulk_destroy',
           params: { ticket_ids: [@reel.id, @carousel.id] }, as: :json
      expect(response).to have_http_status(:ok)
      expect(json['deleted_count']).to eq(2)
      expect(Ticket.where(id: [@reel.id, @carousel.id])).to be_empty
    end

    it 'ignores ids from another workspace (tenant-scoped)' do
      other_user, other_ws = Operations::Users::Register.call(
        email: 'rival@agencios.app', password: 'secret123', name: 'Rival', workspace_name: 'Rival Agency'
      )
      Current.reset
      other_client = other_ws.clients.create!(name: 'Other')
      other_project = other_ws.projects.create!(client: other_client, name: 'Other', color: '#000000')
      foreign = Operations::Tickets::Create.call(
        workspace: other_ws, user: other_user,
        params: { project_id: other_project.id, title: 'Não me exclua', creative_type: 'reel', channels: %w[instagram] }
      )

      login
      post '/api/v1/tickets/bulk_destroy',
           params: { ticket_ids: [@reel.id, foreign.id] }, as: :json
      expect(response).to have_http_status(:ok)
      expect(json['deleted_count']).to eq(1)
      expect(Ticket.exists?(@reel.id)).to be(false)
      expect(Ticket.exists?(foreign.id)).to be(true)
    end

    it 'forbids a non-manager from bulk-deleting' do
      member = User.create!(email: 'member@agencios.app', password: 'secret123', name: 'Member')
      Membership.create!(workspace: @workspace, user: member, role: :member)
      login('member@agencios.app')

      post '/api/v1/tickets/bulk_destroy', params: { ticket_ids: [@reel.id] }, as: :json
      expect(response).to have_http_status(:forbidden)
      expect(Ticket.exists?(@reel.id)).to be(true)
    end
  end

  describe 'board search' do
    it 'narrows the board columns by q' do
      login
      get '/api/v1/board', params: { q: 'reel' }
      tickets = json['columns'].flat_map { |c| c['tickets'] }
      expect(tickets.map { |t| t['title'] }).to eq(['Reel de lançamento'])
    end
  end

  describe 'paginated + searchable resources' do
    it 'returns the full project list by default (no meta) for backward compatibility' do
      login
      get '/api/v1/projects'
      expect(json).to have_key('projects')
      expect(json).not_to have_key('meta')
    end

    it 'paginates projects and searches by q' do
      @workspace.projects.create!(client: @client, name: 'Rebrand', color: '#EC4899')
      login
      get '/api/v1/projects', params: { per: 1, page: 1 }
      expect(json['projects'].size).to eq(1)
      expect(json['meta']).to include('has_more' => true)

      get '/api/v1/projects', params: { q: 'rebr' }
      expect(json['projects'].map { |p| p['name'] }).to eq(['Rebrand'])
    end

    it 'searches workspace members by q' do
      login
      get '/api/v1/workspace/memberships', params: { q: 'owner' }
      expect(json['memberships'].map { |m| m['name'] }).to include('Owner')
    end
  end
end
