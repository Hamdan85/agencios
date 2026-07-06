# Client "Performance" Tab Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a **Performance** tab to the client detail page (`/clientes/:id/desempenho`) showing that client's post analytics + an AI-written analysis, filterable by date range, campaign, network, and creative type.

**Architecture:** A read-only, client-scoped aggregation service (`Operations::Analytics::ClientPerformance`) — a sibling of the existing `Operations::Reports::AggregateProjectMetrics` — computes KPIs, a daily timeseries, breakdowns (network / type / campaign), top posts, and account-level snapshots over a filtered window. A second stateless op (`Operations::Analytics::ClientPerformanceInsight`) feeds that aggregate to the AI seam for a markdown narrative. Two nested endpoints under `clients` expose them. The frontend adds a URL-driven Radix tab rendering a new `ClientPerformance` component (existing `StatCard` KPIs + `recharts` charts — recharts' first use in the app).

**Tech Stack:** Rails 8.1 service objects + RSpec (no FactoryBot — inline `create!` + `Operations::*.call`), Pundit; React 19 + React Router 7 + TanStack Query v5 + recharts + Tailwind v4.

## Global Constraints

- **All code 100% English** (identifiers, columns, keys, comments, git messages). Portuguese is allowed ONLY in user-facing UI strings and the React Router URL segment (`desempenho`).
- **Controllers call services only** — no business logic in controllers. HTTP layer = `Controllers::*` (< `Controllers::Base`); domain logic = `Operations::*` (< `Operations::Base`); AI text via `AiAdapter.complete`.
- **Every query scoped to `Current.workspace`** — load the client via `workspace.clients.find(...)`, never a bare id.
- **No AR callbacks.** This feature writes nothing (read-only aggregation + one stateless AI call).
- **`.call(...)` on every service; never `new` a service directly.**
- **Dates serialized as ISO 8601, money in cents** — all formatting on the frontend.
- **AI seam never raises** (`AiAdapter.complete` returns a stub string on outage). The insight op must detect an empty/no-data result and report `available: false` — never fabricate.
- **Tests:** `bundle exec rspec`. No FactoryBot — build graphs inline. Request specs must call `activate_billing(workspace)` after `Operations::Users::Register.call` or every endpoint returns HTTP 402 (total paywall). Service specs set `Current.workspace` / `Current.actor` in `before` and `Current.reset` in `after`.

---

## File Structure

**Backend (create):**
- `app/services/operations/analytics/client_performance.rb` — pure aggregator (the meat).
- `app/services/operations/analytics/client_performance_insight.rb` — AI narrative op.
- `app/services/prompts/performance_insight.rb` — the prompt builder.
- `app/services/controllers/clients/performance.rb` — HTTP layer, data endpoint.
- `app/services/controllers/clients/performance_insight.rb` — HTTP layer, insight endpoint.

**Backend (modify):**
- `config/routes.rb` — add two member routes under `resources :clients`.
- `app/controllers/api/v1/clients_controller.rb` — add `#performance` + `#performance_insight`.

**Backend (test):**
- `spec/services/operations/analytics/client_performance_spec.rb`
- `spec/services/operations/analytics/client_performance_insight_spec.rb`
- `spec/requests/api/v1/client_performance_spec.rb`

**Frontend (create):**
- `app/frontend/components/ui/charts.jsx` — themed recharts wrappers.
- `app/frontend/components/client/ClientPerformance.jsx` — orchestrator (filters state + data hook + layout).
- `app/frontend/components/client/performance/FilterBar.jsx`
- `app/frontend/components/client/performance/KpiRow.jsx`
- `app/frontend/components/client/performance/Breakdowns.jsx`
- `app/frontend/components/client/performance/TopPosts.jsx`
- `app/frontend/components/client/performance/AiInsightCard.jsx`

**Frontend (modify):**
- `app/frontend/api/index.js` — add `clientsApi.performance` + `.performanceInsight`.
- `app/frontend/api/queryKeys.js` — add `clientPerformance`.
- `app/frontend/hooks/useData.js` — add `useClientPerformance` + `useClientPerformanceInsight`.
- `app/frontend/pages/Clients/Show.jsx` — extend tab maps + add trigger/content.

_(No `App.jsx` change: `/clientes/:id/:tab` is already a registered wildcard route.)_

---

### Task 1: `Operations::Analytics::ClientPerformance` (pure aggregator)

**Files:**
- Create: `app/services/operations/analytics/client_performance.rb`
- Test: `spec/services/operations/analytics/client_performance_spec.rb`

**Interfaces:**
- Consumes: `Post`, `Ticket`, `Client`, `PostMetric`, `AccountMetric` models; `Post.status_published` scope; `PostMetric#engagement`; `AccountMetric.as_of(time)` scope; `Ticket#creative_type` / `#creative_types_list` / `#display_title`.
- Produces: `Operations::Analytics::ClientPerformance.call(client:, from:, to:, project_ids:, providers:, creative_types:)` → Hash with symbol keys `{ period, kpis, account, timeseries, by_network, by_type, by_campaign, top_posts, meta }`. `kpis` = `{ reach, views, likes, comments, shares, saves, engagement, posts_count, engagement_rate, deltas: {<key> => pct|nil} }`. Constant `METRIC_SUPPORT` (provider → supported metric symbols).

- [ ] **Step 1: Write the failing spec**

Create `spec/services/operations/analytics/client_performance_spec.rb`:

```ruby
# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Operations::Analytics::ClientPerformance do
  let(:user) { User.create!(email: "perf-#{SecureRandom.hex(3)}@agencios.app", password: 'secret123', name: 'Perf') }
  let(:workspace) { Operations::Workspaces::SetupForUser.call(user: user, name: 'Perf Studio') }
  let(:client) { workspace.clients.create!(name: 'ACME') }
  let(:project) { workspace.projects.create!(client: client, name: 'Camp A', color: '#7C3AED') }
  let(:account) { client.social_accounts.create!(workspace: workspace, provider: 'instagram') }

  before do
    Current.workspace = workspace
    Current.actor = user
  end

  after { Current.reset }

  # A published post with one metric snapshot, published `days_ago` days back.
  def published_post(creative_type:, days_ago:, views:, likes: 0, comments: 0, shares: 0, saves: 0, reach: 0, acct: account, proj: project)
    ticket = Operations::Tickets::Create.call(
      workspace: workspace, user: user,
      params: { project_id: proj.id, title: "T-#{SecureRandom.hex(2)}", creative_type: creative_type, channels: %w[instagram] }
    )
    post = Post.create!(workspace: workspace, ticket: ticket, social_account: acct,
                        status: :published, published_at: days_ago.days.ago, external_post_id: SecureRandom.hex(4))
    post.post_metrics.create!(captured_at: Time.current, views: views, likes: likes,
                              comments: comments, shares: shares, saves: saves, reach: reach)
    post
  end

  it 'sums the latest metric per post into KPIs with engagement and engagement_rate' do
    published_post(creative_type: 'reel', days_ago: 2, views: 100, likes: 5, comments: 3, shares: 2, saves: 0, reach: 80)
    published_post(creative_type: 'carousel', days_ago: 3, views: 100, likes: 10, comments: 0, shares: 0, saves: 0, reach: 90)

    result = described_class.call(client: client)

    expect(result[:kpis][:views]).to eq(200)
    expect(result[:kpis][:reach]).to eq(170)
    expect(result[:kpis][:engagement]).to eq(20) # 5+3+2 + 10
    expect(result[:kpis][:posts_count]).to eq(2)
    expect(result[:kpis][:engagement_rate]).to eq(10.0) # 20 / 200 * 100
  end

  it 'breaks down by network, creative type, and campaign' do
    published_post(creative_type: 'reel', days_ago: 1, views: 300)
    published_post(creative_type: 'carousel', days_ago: 1, views: 100)

    result = described_class.call(client: client)

    expect(result[:by_network].first).to include(provider: 'instagram', posts_count: 2, views: 400)
    expect(result[:by_type].map { |g| g[:creative_type] }).to contain_exactly('reel', 'carousel')
    expect(result[:by_type].first).to include(creative_type: 'reel', views: 300) # sorted by views desc
    expect(result[:by_campaign].first).to include(project_id: project.id, project_name: 'Camp A', views: 400)
  end

  it 'filters by creative_type' do
    published_post(creative_type: 'reel', days_ago: 1, views: 300)
    published_post(creative_type: 'carousel', days_ago: 1, views: 100)

    result = described_class.call(client: client, creative_types: %w[carousel])

    expect(result[:kpis][:views]).to eq(100)
    expect(result[:kpis][:posts_count]).to eq(1)
  end

  it 'filters by the published_at window' do
    published_post(creative_type: 'reel', days_ago: 2, views: 50)
    published_post(creative_type: 'reel', days_ago: 90, views: 999)

    result = described_class.call(client: client, from: 30.days.ago.to_date, to: Date.current)

    expect(result[:kpis][:views]).to eq(50)
  end

  it 'builds a daily timeseries keyed by published_at' do
    published_post(creative_type: 'reel', days_ago: 1, views: 10, likes: 1)
    result = described_class.call(client: client)
    point = result[:timeseries].find { |p| p[:date] == 1.day.ago.to_date.iso8601 }
    expect(point).to include(views: 10, engagement: 1)
  end

  it 'includes connected-account follower snapshots' do
    account.account_metrics.create!(workspace: workspace, captured_at: Time.current,
                                    period_start: 30.days.ago.to_date, period_end: Date.current,
                                    followers: 1000, new_followers: 50, accounts_reached: 4000, profile_views: 200)
    result = described_class.call(client: client)
    ig = result[:account].find { |a| a[:provider] == 'instagram' }
    expect(ig).to include(followers: 1000, follower_growth: 50, profile_reach: 4000)
  end

  it 'exposes the per-network metric support map' do
    result = described_class.call(client: client)
    expect(result[:meta][:metric_support]['tiktok']).not_to include(:saves)
    expect(result[:meta][:metric_support]['instagram']).to include(:reach, :saves)
  end
end
```

- [ ] **Step 2: Run the spec to verify it fails**

Run: `bundle exec rspec spec/services/operations/analytics/client_performance_spec.rb`
Expected: FAIL — `uninitialized constant Operations::Analytics::ClientPerformance`.

- [ ] **Step 3: Implement the aggregator**

Create `app/services/operations/analytics/client_performance.rb`:

```ruby
# frozen_string_literal: true

module Operations
  module Analytics
    # Pure computation: aggregates a CLIENT's published-post metrics + connected
    # account snapshots over a window, filterable by campaign / network / creative
    # type. Client-scoped sibling of Operations::Reports::AggregateProjectMetrics.
    # No side effects. Returns a Hash with symbol keys.
    class ClientPerformance < Operations::Base
      METRIC_KEYS = %i[reach views likes comments shares saves].freeze
      DELTA_KEYS = (METRIC_KEYS + %i[engagement posts_count engagement_rate]).freeze

      # Which numeric metrics each network actually reports; the rest render as
      # "—" on the frontend (not a misleading 0). Derived from each vendor's
      # SyncInsights action (reach/saves are sparse on video-only networks).
      METRIC_SUPPORT = {
        'instagram' => %i[reach views likes comments shares saves],
        'facebook'  => %i[reach views likes comments shares],
        'threads'   => %i[views likes comments shares],
        'tiktok'    => %i[views likes comments shares],
        'youtube'   => %i[views likes comments shares],
        'linkedin'  => %i[reach views likes comments shares],
        'x'         => %i[reach views likes comments shares saves]
      }.freeze

      def initialize(client:, from: nil, to: nil, project_ids: nil, providers: nil, creative_types: nil)
        @client = client
        @to = to.presence ? to.to_date : Date.current
        @from = from.presence ? from.to_date : (@to - 29)
        @project_ids = Array(project_ids).map(&:to_i).presence
        @providers = Array(providers).map(&:to_s).presence
        @creative_types = Array(creative_types).map(&:to_s).presence
      end

      def call
        {
          period: period_block,
          kpis: kpis,
          account: account_block,
          timeseries: timeseries,
          by_network: by_network,
          by_type: by_type,
          by_campaign: by_campaign,
          top_posts: top_posts,
          meta: { metric_support: METRIC_SUPPORT, generated_at: Time.current.iso8601 }
        }
      end

      private

      def window_days = (@to - @from).to_i.clamp(1, 730)
      def range = @from.beginning_of_day..@to.end_of_day
      def prior_range = (@from - window_days - 1).beginning_of_day..(@from - 1).end_of_day

      # Tickets under this client's projects, honoring the campaign filter.
      def client_ticket_ids
        projects = @client.projects
        projects = projects.where(id: @project_ids) if @project_ids
        Ticket.where(project_id: projects.select(:id)).select(:id)
      end

      # Published posts in `r`; provider + creative-type filters applied in Ruby
      # since both derive from associations.
      def posts_in(r)
        Post.where(ticket_id: client_ticket_ids)
            .status_published
            .where(published_at: r)
            .includes(:post_metrics, :social_account, ticket: :project)
            .to_a
            .select { |p| provider_ok?(p) && type_ok?(p) }
      end

      def posts = @posts ||= posts_in(range)
      def prior_posts = @prior_posts ||= posts_in(prior_range)

      def provider_ok?(post)
        return true unless @providers

        @providers.include?(post.social_account&.provider)
      end

      def type_ok?(post)
        return true unless @creative_types

        @creative_types.include?(type_for(post))
      end

      # Same resolution the project report uses (legacy singular first), with a
      # fallback to the multi-scoping array for tickets that only set it.
      def type_for(post)
        ticket = post.ticket
        (ticket&.creative_type.presence || ticket&.creative_types_list&.first).presence || 'outros'
      end

      def latest_for(post) = post.post_metrics.max_by { |m| m.captured_at || Time.at(0) }

      def totals_for(list)
        totals = METRIC_KEYS.index_with { 0 }
        list.each do |post|
          metric = latest_for(post)
          next unless metric

          METRIC_KEYS.each { |k| totals[k] += metric.public_send(k).to_i }
        end
        totals[:engagement] = totals[:likes] + totals[:comments] + totals[:shares] + totals[:saves]
        totals[:posts_count] = list.size
        totals[:engagement_rate] = totals[:views].zero? ? 0.0 : (totals[:engagement] / totals[:views].to_f * 100).round(2)
        totals
      end

      def kpis
        current = totals_for(posts)
        prior = totals_for(prior_posts)
        current.merge(deltas: DELTA_KEYS.index_with { |k| pct_delta(current[k], prior[k]) })
      end

      def pct_delta(current, prior)
        return nil if current.nil? || prior.nil? || prior.zero?

        (((current - prior) / prior.to_f) * 100).round(1)
      end

      def timeseries
        buckets = Hash.new { |h, k| h[k] = { views: 0, reach: 0, engagement: 0 } }
        posts.each do |post|
          metric = latest_for(post)
          next unless metric && post.published_at

          day = post.published_at.to_date.iso8601
          buckets[day][:views] += metric.views.to_i
          buckets[day][:reach] += metric.reach.to_i
          buckets[day][:engagement] += metric.engagement
        end
        buckets.sort.map { |day, v| { date: day }.merge(v) }
      end

      def group_block(list)
        totals = totals_for(list)
        totals.slice(*METRIC_KEYS, :engagement, :posts_count, :engagement_rate)
      end

      def by_network
        posts.group_by { |p| p.social_account&.provider || 'desconhecido' }
             .map { |provider, list| { provider: provider }.merge(group_block(list)) }
             .sort_by { |g| -g[:views] }
      end

      def by_type
        posts.group_by { |p| type_for(p) }
             .map { |type, list| { creative_type: type }.merge(group_block(list)) }
             .sort_by { |g| -g[:views] }
      end

      def by_campaign
        projects = @client.projects.index_by(&:id)
        posts.group_by { |p| p.ticket&.project_id }
             .map do |project_id, list|
               project = projects[project_id]
               { project_id: project_id, project_name: project&.name, color: project&.color }.merge(group_block(list))
             end
             .sort_by { |g| -g[:views] }
      end

      def top_posts
        posts.filter_map do |post|
          metric = latest_for(post)
          next unless metric

          {
            post_id: post.id,
            label: post.ticket&.display_title,
            provider: post.social_account&.provider,
            creative_type: type_for(post),
            project_name: post.ticket&.project&.name,
            published_at: post.published_at&.iso8601,
            reach: metric.reach.to_i, views: metric.views.to_i, likes: metric.likes.to_i,
            comments: metric.comments.to_i, shares: metric.shares.to_i, saves: metric.saves.to_i,
            engagement: metric.engagement, permalink: post.permalink
          }
        end.sort_by { |c| -c[:views] }.first(20)
      end

      def account_block
        accounts = @client.social_accounts.status_connected
        accounts = accounts.where(provider: @providers) if @providers
        accounts.map do |account|
          current = account.account_metrics.as_of(@to.end_of_day).first
          prior = account.account_metrics.as_of(@from.end_of_day).first
          {
            provider: account.provider,
            username: account.username,
            followers: current&.followers,
            follower_growth: current&.new_followers,
            follower_growth_pct: pct_delta(current&.followers, prior&.followers),
            profile_reach: current&.accounts_reached,
            profile_views: current&.profile_views
          }
        end
      end

      def period_block
        {
          from: @from.iso8601,
          to: @to.iso8601,
          days: window_days,
          prev_from: (@from - window_days - 1).iso8601,
          prev_to: (@from - 1).iso8601
        }
      end
    end
  end
end
```

- [ ] **Step 4: Run the spec to verify it passes**

Run: `bundle exec rspec spec/services/operations/analytics/client_performance_spec.rb`
Expected: PASS (all examples green).

- [ ] **Step 5: Commit**

```bash
git add app/services/operations/analytics/client_performance.rb spec/services/operations/analytics/client_performance_spec.rb
git commit -m "feat(analytics): client-scoped performance aggregator"
```

---

### Task 2: `Prompts::PerformanceInsight` + `Operations::Analytics::ClientPerformanceInsight`

**Files:**
- Create: `app/services/prompts/performance_insight.rb`
- Create: `app/services/operations/analytics/client_performance_insight.rb`
- Test: `spec/services/operations/analytics/client_performance_insight_spec.rb`

**Interfaces:**
- Consumes: `Prompts::Base` (constructor `initialize(workspace:, client:, **context)`, helpers `#brand_block` / `#positioning_block`); `AiAdapter.complete(builder, max_tokens:, operation:, subject:)` → String; the Hash produced by Task 1.
- Produces: `Operations::Analytics::ClientPerformanceInsight.call(client:, data:)` → `{ insight: String|nil, available: Boolean }`.

- [ ] **Step 1: Write the failing spec**

Create `spec/services/operations/analytics/client_performance_insight_spec.rb`:

```ruby
# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Operations::Analytics::ClientPerformanceInsight do
  let(:user) { User.create!(email: "ins-#{SecureRandom.hex(3)}@agencios.app", password: 'secret123', name: 'Ins') }
  let(:workspace) { Operations::Workspaces::SetupForUser.call(user: user, name: 'Ins Studio') }
  let(:client) { workspace.clients.create!(name: 'ACME') }

  before do
    Current.workspace = workspace
    Current.actor = user
  end

  after { Current.reset }

  let(:data) do
    {
      period: { from: '2026-06-01', to: '2026-06-30' },
      kpis: { views: 500, engagement: 40, posts_count: 3, engagement_rate: 8.0, deltas: {} },
      by_network: [{ provider: 'instagram', views: 500 }],
      by_type: [{ creative_type: 'reel', views: 500 }],
      by_campaign: [{ project_name: 'Camp A', views: 500 }],
      top_posts: [{ label: 'Reel', views: 300 }]
    }
  end

  it 'returns the AI markdown when there is post data' do
    allow(AiAdapter).to receive(:complete).and_return("## Panorama\nBom desempenho.")
    result = described_class.call(client: client, data: data)
    expect(result[:available]).to be(true)
    expect(result[:insight]).to include('Panorama')
  end

  it 'passes the performance operation label + client subject to the AI seam' do
    expect(AiAdapter).to receive(:complete).with(
      an_instance_of(Prompts::PerformanceInsight),
      hash_including(operation: 'client_performance_insight', subject: client)
    ).and_return('ok')
    described_class.call(client: client, data: data)
  end

  it 'reports unavailable (no fabrication) when there are no posts' do
    empty = data.merge(kpis: { views: 0, engagement: 0, posts_count: 0, engagement_rate: 0.0, deltas: {} })
    allow(AiAdapter).to receive(:complete).and_return('irrelevant')
    result = described_class.call(client: client, data: empty)
    expect(result[:available]).to be(false)
    expect(result[:insight]).to be_nil
  end

  it 'reports unavailable when the AI seam returns a blank string (outage stub)' do
    allow(AiAdapter).to receive(:complete).and_return('   ')
    result = described_class.call(client: client, data: data)
    expect(result[:available]).to be(false)
    expect(result[:insight]).to be_nil
  end
end
```

- [ ] **Step 2: Run the spec to verify it fails**

Run: `bundle exec rspec spec/services/operations/analytics/client_performance_insight_spec.rb`
Expected: FAIL — `uninitialized constant Operations::Analytics::ClientPerformanceInsight`.

- [ ] **Step 3: Implement the prompt builder**

Create `app/services/prompts/performance_insight.rb`:

```ruby
# frozen_string_literal: true

module Prompts
  # System + user prompt for the client Performance-tab AI reading. Fed the
  # already-aggregated numbers (never raw posts) so it is one fast call.
  class PerformanceInsight < Base
    def system
      <<~SYS
        Você é o analista de performance de uma agência de social media.
        #{brand_block}
        #{positioning_block}

        Escreva uma leitura objetiva e acionável dos dados de performance dos posts
        do cliente, em português do Brasil, em markdown. Estruture em:
        1. **Panorama** — 2 a 3 frases sobre o desempenho geral no período.
        2. **O que funcionou** — formatos, redes e posts de melhor desempenho, com números.
        3. **Pontos de atenção** — quedas ou baixo desempenho.
        4. **Recomendações** — 3 a 5 ações concretas para o próximo ciclo.

        Baseie-se APENAS nos números fornecidos. Não invente métricas. Se os dados
        forem escassos, diga isso com honestidade. Seja conciso.
      SYS
    end

    def user_prompt
      <<~TXT
        Período: #{context[:period_label]}

        KPIs (com variação vs. período anterior em deltas):
        #{context[:kpis_json]}

        Desempenho por rede:
        #{context[:by_network_json]}

        Desempenho por tipo de criativo:
        #{context[:by_type_json]}

        Desempenho por campanha:
        #{context[:by_campaign_json]}

        Top posts:
        #{context[:top_posts_json]}
      TXT
    end
  end
end
```

- [ ] **Step 4: Implement the operation**

Create `app/services/operations/analytics/client_performance_insight.rb`:

```ruby
# frozen_string_literal: true

module Operations
  module Analytics
    # Turns an aggregated ClientPerformance payload into a markdown narrative via
    # the AI seam. Stateless — writes nothing. AiAdapter never raises (returns a
    # stub on outage), so we gate `available` on real post data + non-blank text
    # and report honestly instead of fabricating a reading.
    class ClientPerformanceInsight < Operations::Base
      MAX_TOKENS = 1200

      def initialize(client:, data:)
        @client = client
        @data = data
      end

      def call
        return { insight: nil, available: false } unless @data.dig(:kpis, :posts_count).to_i.positive?

        builder = Prompts::PerformanceInsight.new(
          workspace: @client.workspace,
          client: @client,
          period_label: period_label,
          kpis_json: JSON.pretty_generate(@data[:kpis]),
          by_network_json: JSON.pretty_generate(@data[:by_network]),
          by_type_json: JSON.pretty_generate(@data[:by_type]),
          by_campaign_json: JSON.pretty_generate(@data[:by_campaign]),
          top_posts_json: JSON.pretty_generate(@data[:top_posts])
        )
        text = AiAdapter.complete(
          builder, max_tokens: MAX_TOKENS, operation: 'client_performance_insight', subject: @client
        ).to_s.strip

        text.present? ? { insight: text, available: true } : { insight: nil, available: false }
      end

      private

      def period_label
        period = @data[:period] || {}
        "#{period[:from]} a #{period[:to]}"
      end
    end
  end
end
```

- [ ] **Step 5: Run the spec to verify it passes**

Run: `bundle exec rspec spec/services/operations/analytics/client_performance_insight_spec.rb`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add app/services/prompts/performance_insight.rb app/services/operations/analytics/client_performance_insight.rb spec/services/operations/analytics/client_performance_insight_spec.rb
git commit -m "feat(analytics): AI performance-insight prompt + operation"
```

---

### Task 3: Data endpoint — `GET /api/v1/clients/:id/performance`

**Files:**
- Create: `app/services/controllers/clients/performance.rb`
- Modify: `config/routes.rb:134-140` (member block under `resources :clients`)
- Modify: `app/controllers/api/v1/clients_controller.rb`
- Test: `spec/requests/api/v1/client_performance_spec.rb`

**Interfaces:**
- Consumes: `Controllers::Base` helpers (`workspace`, `authorize!`, `deny_guests!`); Task 1's `Operations::Analytics::ClientPerformance.call(...)`.
- Produces: `Controllers::Clients::Performance.call(params:)` → the aggregator Hash. Route helper `performance_api_v1_client` (`GET /api/v1/clients/:id/performance`).

- [ ] **Step 1: Write the failing request spec**

Create `spec/requests/api/v1/client_performance_spec.rb`:

```ruby
# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Client performance', type: :request do
  before do
    ActiveJob::Base.queue_adapter = :test
    @user, @workspace = Operations::Users::Register.call(
      email: 'owner@agencios.app', password: 'secret123', name: 'Owner', workspace_name: 'Agency'
    )
    Current.reset
    activate_billing(@workspace)
    @client = @workspace.clients.create!(name: 'ACME Corp')
    @project = @workspace.projects.create!(client: @client, name: 'Launch', color: '#7C3AED')
    @account = @client.social_accounts.create!(workspace: @workspace, provider: 'instagram')
    ticket = Operations::Tickets::Create.call(
      workspace: @workspace, user: @user,
      params: { project_id: @project.id, title: 'Reel', creative_type: 'reel', channels: %w[instagram] }
    )
    post = Post.create!(workspace: @workspace, ticket: ticket, social_account: @account,
                        status: :published, published_at: 2.days.ago, external_post_id: 'ext-1')
    post.post_metrics.create!(captured_at: Time.current, views: 120, likes: 8, comments: 2, shares: 1, saves: 0, reach: 100)
  end

  def login(email = 'owner@agencios.app', password = 'secret123')
    post '/api/v1/session', params: { email: email, password: password }, as: :json
    expect(response).to have_http_status(:ok)
  end

  def json = JSON.parse(response.body)

  it 'returns aggregated KPIs + breakdowns for the client' do
    login
    get "/api/v1/clients/#{@client.id}/performance"
    expect(response).to have_http_status(:ok)
    expect(json['kpis']).to include('views' => 120, 'engagement' => 11, 'posts_count' => 1)
    expect(json['by_network'].first).to include('provider' => 'instagram', 'views' => 120)
    expect(json['meta']['metric_support']).to have_key('instagram')
  end

  it 'honors filters (creative_types that match nothing → empty)' do
    login
    get "/api/v1/clients/#{@client.id}/performance", params: { creative_types: ['carousel'] }
    expect(response).to have_http_status(:ok)
    expect(json['kpis']['posts_count']).to eq(0)
  end

  it 'returns 402 without active billing' do
    @workspace.subscription.update!(status: 'incomplete', card_on_file: false)
    login
    get "/api/v1/clients/#{@client.id}/performance"
    expect(response).to have_http_status(:payment_required)
  end
end
```

- [ ] **Step 2: Run the spec to verify it fails**

Run: `bundle exec rspec spec/requests/api/v1/client_performance_spec.rb`
Expected: FAIL — routing error (`No route matches [GET] ".../performance"`).

- [ ] **Step 3: Add the route**

In `config/routes.rb`, extend the `member do` block under `resources :clients` (currently lines 135-140) to add the two performance routes:

```ruby
        member do
          post  :archive
          post  :unarchive
          patch :positioning, action: :update_positioning
          patch :brand_assets
          # Performance tab: analytics aggregate + its on-demand AI reading.
          get   :performance
          post  :performance_insight
        end
```

- [ ] **Step 4: Add the controller action**

In `app/controllers/api/v1/clients_controller.rb`, add after `#brand_assets` (line 32):

```ruby
      # GET /api/v1/clients/:id/performance — filtered post-analytics aggregate.
      def performance = render_ok(Controllers::Clients::Performance.call(params:))

      # POST /api/v1/clients/:id/performance_insight — AI reading over the same filters.
      def performance_insight = render_ok(Controllers::Clients::PerformanceInsight.call(params:))
```

_(The `#performance_insight` action is wired now to keep the controller edit atomic; its service lands in Task 4 — the route/action referencing it does not break the data-endpoint spec, which never calls it.)_

- [ ] **Step 5: Implement the data-endpoint service**

Create `app/services/controllers/clients/performance.rb`:

```ruby
# frozen_string_literal: true

module Controllers
  module Clients
    # GET /api/v1/clients/:id/performance — filtered client post-analytics.
    class Performance < Base
      def initialize(params:)
        @params = params
      end

      def call
        client = workspace.clients.find(@params[:id])
        authorize!(client, :show?)
        deny_guests!
        Operations::Analytics::ClientPerformance.call(
          client: client,
          from: @params[:from],
          to: @params[:to],
          project_ids: @params[:project_ids],
          providers: @params[:providers],
          creative_types: @params[:creative_types]
        )
      end
    end
  end
end
```

- [ ] **Step 6: Run the spec to verify it passes**

Run: `bundle exec rspec spec/requests/api/v1/client_performance_spec.rb`
Expected: The two data-endpoint examples PASS and the 402 example PASSES. (No insight example yet.)

- [ ] **Step 7: Commit**

```bash
git add config/routes.rb app/controllers/api/v1/clients_controller.rb app/services/controllers/clients/performance.rb spec/requests/api/v1/client_performance_spec.rb
git commit -m "feat(api): client performance data endpoint"
```

---

### Task 4: Insight endpoint — `POST /api/v1/clients/:id/performance_insight`

**Files:**
- Create: `app/services/controllers/clients/performance_insight.rb`
- Modify: `spec/requests/api/v1/client_performance_spec.rb` (add insight example)

**Interfaces:**
- Consumes: `Controllers::Base` helpers; Task 1 aggregator + Task 2 insight op. Route/action added in Task 3.
- Produces: `Controllers::Clients::PerformanceInsight.call(params:)` → `{ insight:, available: }`.

- [ ] **Step 1: Add the failing insight example**

Append to `spec/requests/api/v1/client_performance_spec.rb` (inside the top-level `describe`, after the existing `it` blocks):

```ruby
  it 'generates an AI reading over the filtered data' do
    allow(AiAdapter).to receive(:complete).and_return('## Panorama\nBom mês.')
    login
    post "/api/v1/clients/#{@client.id}/performance_insight"
    expect(response).to have_http_status(:ok)
    expect(json['available']).to be(true)
    expect(json['insight']).to include('Panorama')
  end
```

- [ ] **Step 2: Run the spec to verify it fails**

Run: `bundle exec rspec spec/requests/api/v1/client_performance_spec.rb -e "generates an AI reading"`
Expected: FAIL — `uninitialized constant Controllers::Clients::PerformanceInsight`.

- [ ] **Step 3: Implement the insight-endpoint service**

Create `app/services/controllers/clients/performance_insight.rb`:

```ruby
# frozen_string_literal: true

module Controllers
  module Clients
    # POST /api/v1/clients/:id/performance_insight — recomputes the aggregate for
    # the given filters (never trusts client-sent numbers) then asks the AI seam
    # for a markdown reading.
    class PerformanceInsight < Base
      def initialize(params:)
        @params = params
      end

      def call
        client = workspace.clients.find(@params[:id])
        authorize!(client, :show?)
        deny_guests!
        data = Operations::Analytics::ClientPerformance.call(
          client: client,
          from: @params[:from],
          to: @params[:to],
          project_ids: @params[:project_ids],
          providers: @params[:providers],
          creative_types: @params[:creative_types]
        )
        Operations::Analytics::ClientPerformanceInsight.call(client: client, data: data)
      end
    end
  end
end
```

- [ ] **Step 4: Run the full request spec to verify it passes**

Run: `bundle exec rspec spec/requests/api/v1/client_performance_spec.rb`
Expected: PASS (all four examples).

- [ ] **Step 5: Commit**

```bash
git add app/services/controllers/clients/performance_insight.rb spec/requests/api/v1/client_performance_spec.rb
git commit -m "feat(api): client performance AI-insight endpoint"
```

---

### Task 5: Frontend data layer + Performance tab shell (filters + KPIs)

**Files:**
- Modify: `app/frontend/api/index.js:144-162` (`clientsApi`)
- Modify: `app/frontend/api/queryKeys.js`
- Modify: `app/frontend/hooks/useData.js` (Clients section, ~line 112-131)
- Create: `app/frontend/components/client/ClientPerformance.jsx`
- Create: `app/frontend/components/client/performance/FilterBar.jsx`
- Create: `app/frontend/components/client/performance/KpiRow.jsx`
- Modify: `app/frontend/pages/Clients/Show.jsx` (tab maps + trigger/content)

**Interfaces:**
- Consumes: Task 3 endpoint via `clientsApi.performance`; existing `StatCard` from `@/components/ui/page-header`.
- Produces: hook `useClientPerformance(id, filters)` → `{ data, isLoading, isFetching }`; `useClientPerformanceInsight(id)` → mutation. Component `<ClientPerformance clientId projects accounts />`. FilterBar `onChange(filters)` where `filters = { from, to, project_ids, providers, creative_types }`.

- [ ] **Step 1: Add the API wrappers**

In `app/frontend/api/index.js`, add to the `clientsApi` object (after `uploadBrandAssets`, before the closing brace at line 161):

```js
  // Performance tab: filtered post-analytics aggregate + on-demand AI reading.
  // `params` = { from, to, project_ids[], providers[], creative_types[] }.
  performance: (id, params) => api.get(`/clients/${id}/performance`, { params }),
  performanceInsight: (id, params) => api.post(`/clients/${id}/performance_insight`, params),
```

- [ ] **Step 2: Add the query key**

In `app/frontend/api/queryKeys.js`, add after `client:` (line 11):

```js
  clientPerformance: (id, f = {}) => ['clients', String(id), 'performance', f],
```

- [ ] **Step 3: Add the hooks**

In `app/frontend/hooks/useData.js`, add at the end of the Clients section (after `useClientMutations`, ~line 131):

```js
export const useClientPerformance = (id, filters = {}) =>
  useQuery({
    queryKey: keys.clientPerformance(id, filters),
    queryFn: () => clientsApi.performance(id, filters),
    enabled: !!id,
    placeholderData: keepPreviousData,
  })

export function useClientPerformanceInsight(id) {
  return useMutation({
    mutationFn: (filters = {}) => clientsApi.performanceInsight(id, filters),
    onError: onErr('Erro ao gerar a leitura da IA.'),
  })
}
```

- [ ] **Step 4: Build the KpiRow**

Create `app/frontend/components/client/performance/KpiRow.jsx`:

```jsx
import { Eye, Radio, Heart, Share2, Bookmark, LayoutGrid, Users, TrendingUp } from 'lucide-react'
import { StatCard } from '@/components/ui/page-header'

const nf = new Intl.NumberFormat('pt-BR', { notation: 'compact', maximumFractionDigits: 1 })
const num = (v) => nf.format(Number(v) || 0)
const pct = (v) => `${(Number(v) || 0).toFixed(1)}%`

// Small "▲ 12,3%" delta line for a StatCard `sub`.
function delta(d) {
  if (d === null || d === undefined) return undefined
  const n = Number(d)
  const arrow = n > 0 ? '▲' : n < 0 ? '▼' : '■'
  return `${arrow} ${Math.abs(n).toFixed(1)}% vs. período anterior`
}

export default function KpiRow({ kpis, account }) {
  const d = kpis.deltas || {}
  const followers = (account || []).reduce((sum, a) => sum + (Number(a.followers) || 0), 0)
  const growth = (account || []).reduce((sum, a) => sum + (Number(a.follower_growth) || 0), 0)

  return (
    <div className="grid grid-cols-2 gap-3 sm:grid-cols-3 lg:grid-cols-4">
      <StatCard label="Alcance" value={num(kpis.reach)} icon={Radio} color="#7C3AED" sub={delta(d.reach)} />
      <StatCard label="Views" value={num(kpis.views)} icon={Eye} color="#2563EB" sub={delta(d.views)} />
      <StatCard label="Engajamento" value={num(kpis.engagement)} icon={Heart} color="#DB2777" sub={delta(d.engagement)} />
      <StatCard label="Taxa de eng." value={pct(kpis.engagement_rate)} icon={TrendingUp} color="#059669" sub="engajamento ÷ views" />
      <StatCard label="Compart." value={num(kpis.shares)} icon={Share2} color="#0891B2" sub={delta(d.shares)} />
      <StatCard label="Salvos" value={num(kpis.saves)} icon={Bookmark} color="#CA8A04" sub={delta(d.saves)} />
      <StatCard label="Posts" value={num(kpis.posts_count)} icon={LayoutGrid} color="#4F46E5" />
      <StatCard label="Seguidores" value={num(followers)} icon={Users} color="#7C3AED" sub={growth ? `+${num(growth)} no período` : undefined} />
    </div>
  )
}
```

- [ ] **Step 5: Build the FilterBar**

Create `app/frontend/components/client/performance/FilterBar.jsx`:

```jsx
import { cn } from '@/lib/utils'

const PROVIDER_LABELS = { instagram: 'Instagram', facebook: 'Facebook', tiktok: 'TikTok', youtube: 'YouTube', linkedin: 'LinkedIn', x: 'X', threads: 'Threads' }
const TYPE_LABELS = { reel: 'Reel', feed_image: 'Imagem', carousel: 'Carrossel', story: 'Story', ugc_video: 'UGC', ad: 'Anúncio', thumbnail: 'Thumb', cover: 'Capa', outros: 'Outros' }
const PRESETS = [{ key: '7', label: '7 dias' }, { key: '30', label: '30 dias' }, { key: '90', label: '90 dias' }]

function isoDaysAgo(days) {
  const d = new Date()
  d.setDate(d.getDate() - days)
  return d.toISOString().slice(0, 10)
}

function Chip({ active, onClick, children }) {
  return (
    <button
      type="button"
      onClick={onClick}
      className={cn(
        'rounded-full border px-3 py-1 text-xs font-semibold transition',
        active ? 'border-brand bg-brand text-white' : 'border-border bg-surface text-ink-muted hover:border-brand/50'
      )}
    >
      {children}
    </button>
  )
}

// Controlled: `value` = { from, to, providers, creative_types, project_ids, preset }.
export default function FilterBar({ value, onChange, projects = [], accounts = [] }) {
  const set = (patch) => onChange({ ...value, ...patch })
  const toggle = (key, item) => {
    const list = value[key] || []
    set({ [key]: list.includes(item) ? list.filter((x) => x !== item) : [...list, item] })
  }
  const setPreset = (days) => set({ preset: days, from: isoDaysAgo(Number(days)), to: isoDaysAgo(0) })

  const providers = [...new Set(accounts.map((a) => a.provider))]
  const types = Object.keys(TYPE_LABELS).filter((t) => t !== 'outros')

  return (
    <div className="mb-5 flex flex-col gap-3 rounded-2xl border border-border bg-surface p-4">
      <div className="flex flex-wrap items-center gap-2">
        <span className="text-xs font-bold uppercase tracking-wider text-ink-muted">Período</span>
        {PRESETS.map((p) => (
          <Chip key={p.key} active={value.preset === p.key} onClick={() => setPreset(p.key)}>{p.label}</Chip>
        ))}
        <input type="date" value={value.from || ''} onChange={(e) => set({ preset: 'custom', from: e.target.value })}
               className="rounded-lg border border-border bg-bg px-2 py-1 text-xs text-ink" />
        <span className="text-xs text-ink-muted">até</span>
        <input type="date" value={value.to || ''} onChange={(e) => set({ preset: 'custom', to: e.target.value })}
               className="rounded-lg border border-border bg-bg px-2 py-1 text-xs text-ink" />
      </div>

      {providers.length > 0 && (
        <div className="flex flex-wrap items-center gap-2">
          <span className="text-xs font-bold uppercase tracking-wider text-ink-muted">Redes</span>
          {providers.map((p) => (
            <Chip key={p} active={(value.providers || []).includes(p)} onClick={() => toggle('providers', p)}>{PROVIDER_LABELS[p] || p}</Chip>
          ))}
        </div>
      )}

      <div className="flex flex-wrap items-center gap-2">
        <span className="text-xs font-bold uppercase tracking-wider text-ink-muted">Tipos</span>
        {types.map((t) => (
          <Chip key={t} active={(value.creative_types || []).includes(t)} onClick={() => toggle('creative_types', t)}>{TYPE_LABELS[t]}</Chip>
        ))}
      </div>

      {projects.length > 0 && (
        <div className="flex flex-wrap items-center gap-2">
          <span className="text-xs font-bold uppercase tracking-wider text-ink-muted">Campanhas</span>
          {projects.map((p) => (
            <Chip key={p.id} active={(value.project_ids || []).includes(p.id)} onClick={() => toggle('project_ids', p.id)}>{p.name}</Chip>
          ))}
        </div>
      )}
    </div>
  )
}
```

- [ ] **Step 6: Build the orchestrator**

Create `app/frontend/components/client/ClientPerformance.jsx`:

```jsx
import { useState } from 'react'
import { TrendingUp } from 'lucide-react'
import { useClientPerformance } from '@/hooks/useData'
import FilterBar from './performance/FilterBar'
import KpiRow from './performance/KpiRow'

function defaultFilters() {
  const to = new Date().toISOString().slice(0, 10)
  const fromD = new Date()
  fromD.setDate(fromD.getDate() - 29)
  return { preset: '30', from: fromD.toISOString().slice(0, 10), to, providers: [], creative_types: [], project_ids: [] }
}

export default function ClientPerformance({ clientId, projects = [], accounts = [] }) {
  const [filters, setFilters] = useState(defaultFilters)
  const query = { from: filters.from, to: filters.to, providers: filters.providers, creative_types: filters.creative_types, project_ids: filters.project_ids }
  const { data, isLoading, isFetching } = useClientPerformance(clientId, query)

  const kpis = data?.kpis
  const empty = kpis && kpis.posts_count === 0

  return (
    <div className="animate-rise">
      <FilterBar value={filters} onChange={setFilters} projects={projects} accounts={accounts} />

      {isLoading && <div className="py-16 text-center text-sm text-ink-muted">Carregando desempenho…</div>}

      {!isLoading && empty && (
        <div className="rounded-2xl border border-dashed border-border bg-surface py-16 text-center">
          <TrendingUp className="mx-auto mb-3 text-ink-muted" size={28} />
          <p className="font-semibold text-ink">Sem posts publicados neste período</p>
          <p className="mt-1 text-sm text-ink-muted">Ajuste os filtros ou publique conteúdo para ver as métricas aqui.</p>
        </div>
      )}

      {!isLoading && kpis && !empty && (
        <div className={isFetching ? 'opacity-60 transition' : 'transition'}>
          <KpiRow kpis={kpis} account={data.account} />
          {/* Charts (Task 6), Top posts (Task 7) and AI insight (Task 8) mount here. */}
        </div>
      )}
    </div>
  )
}
```

- [ ] **Step 7: Wire the tab into the client page**

In `app/frontend/pages/Clients/Show.jsx`:

(a) Add the icon + component imports. Find the lucide import line and add `TrendingUp`; add a new import for the component near the other component imports:

```jsx
import ClientPerformance from '@/components/client/ClientPerformance'
```

(b) Extend the tab maps (lines 499 & 501):

```jsx
const TAB_TO_SEG = { branding: '', config: 'configuracoes', projects: 'campanhas', invoices: 'faturas', meetings: 'reunioes', performance: 'desempenho' }
const SEG_TO_TAB = { configuracoes: 'config', campanhas: 'projects', projetos: 'projects', faturas: 'invoices', reunioes: 'meetings', desempenho: 'performance' }
```

(c) Add the trigger (after the `projects` trigger, line 550):

```jsx
            <TabsTrigger value="performance"><TrendingUp size={15} /> Performance</TabsTrigger>
```

(d) Add the content panel (after the `projects` TabsContent, line 566):

```jsx
          <TabsContent value="performance" className="animate-rise">
            <ClientPerformance clientId={id} projects={projects} accounts={socialAccounts} />
          </TabsContent>
```

- [ ] **Step 8: Verify the build compiles**

Run: `bin/vite build`
Expected: build succeeds (no unresolved imports / syntax errors).

- [ ] **Step 9: Manually verify in the running app**

Run `bin/dev`, open a client with published posts, click the **Performance** tab (`/clientes/:id/desempenho`). Expected: filter bar renders; KPI cards show real numbers; changing a preset re-fetches (cards dim briefly); a client with no posts shows the empty state.

- [ ] **Step 10: Commit**

```bash
git add app/frontend/api/index.js app/frontend/api/queryKeys.js app/frontend/hooks/useData.js app/frontend/components/client/ClientPerformance.jsx app/frontend/components/client/performance/FilterBar.jsx app/frontend/components/client/performance/KpiRow.jsx app/frontend/pages/Clients/Show.jsx
git commit -m "feat(clients): Performance tab shell — filters + KPIs"
```

---

### Task 6: Charts — themed recharts wrappers + trend + breakdowns

**Files:**
- Create: `app/frontend/components/ui/charts.jsx`
- Create: `app/frontend/components/client/performance/Breakdowns.jsx`
- Modify: `app/frontend/components/client/ClientPerformance.jsx` (render charts)

**Interfaces:**
- Consumes: `recharts` (already a dependency); the `timeseries` / `by_network` / `by_type` / `by_campaign` arrays from Task 1.
- Produces: `<TrendChart data />` (line), `<CategoryBars data dataKey nameKey />` (horizontal bars) from `charts.jsx`; `<Breakdowns data />` composing the three breakdown blocks.

- [ ] **Step 1: Build the themed chart wrappers**

Create `app/frontend/components/ui/charts.jsx`:

```jsx
import { ResponsiveContainer, LineChart, Line, XAxis, YAxis, Tooltip, CartesianGrid, BarChart, Bar, Cell } from 'recharts'

const AXIS = { fontSize: 11, fill: 'var(--color-ink-muted, #94a3b8)' }
const nf = new Intl.NumberFormat('pt-BR', { notation: 'compact', maximumFractionDigits: 1 })

const tooltipStyle = {
  borderRadius: 12,
  border: '1px solid var(--color-border, #e2e8f0)',
  background: 'var(--color-surface, #fff)',
  fontSize: 12,
}

// Multi-series line for the daily timeseries. `series` = [{ key, label, color }].
export function TrendChart({ data = [], series }) {
  return (
    <ResponsiveContainer width="100%" height={240}>
      <LineChart data={data} margin={{ top: 8, right: 8, left: -12, bottom: 0 }}>
        <CartesianGrid strokeDasharray="3 3" stroke="var(--color-border, #e2e8f0)" vertical={false} />
        <XAxis dataKey="date" tick={AXIS} tickFormatter={(d) => d?.slice(5)} axisLine={false} tickLine={false} />
        <YAxis tick={AXIS} tickFormatter={(v) => nf.format(v)} axisLine={false} tickLine={false} width={44} />
        <Tooltip contentStyle={tooltipStyle} formatter={(v) => nf.format(v)} />
        {series.map((s) => (
          <Line key={s.key} type="monotone" dataKey={s.key} name={s.label} stroke={s.color} strokeWidth={2.4} dot={false} />
        ))}
      </LineChart>
    </ResponsiveContainer>
  )
}

// Horizontal category bars (per network / type / campaign). `colorFor(entry)` optional.
export function CategoryBars({ data = [], dataKey = 'views', nameKey = 'label', colorFor }) {
  return (
    <ResponsiveContainer width="100%" height={Math.max(120, data.length * 42)}>
      <BarChart data={data} layout="vertical" margin={{ top: 4, right: 12, left: 8, bottom: 4 }}>
        <XAxis type="number" tick={AXIS} tickFormatter={(v) => nf.format(v)} axisLine={false} tickLine={false} />
        <YAxis type="category" dataKey={nameKey} tick={AXIS} width={96} axisLine={false} tickLine={false} />
        <Tooltip contentStyle={tooltipStyle} formatter={(v) => nf.format(v)} cursor={{ fill: 'var(--color-border, #e2e8f0)', opacity: 0.3 }} />
        <Bar dataKey={dataKey} radius={[0, 6, 6, 0]} maxBarSize={26}>
          {data.map((entry, i) => (
            <Cell key={i} fill={colorFor ? colorFor(entry) : '#7C3AED'} />
          ))}
        </Bar>
      </BarChart>
    </ResponsiveContainer>
  )
}
```

- [ ] **Step 2: Build the Breakdowns section**

Create `app/frontend/components/client/performance/Breakdowns.jsx`:

```jsx
import { TrendChart, CategoryBars } from '@/components/ui/charts'

const PROVIDER_LABELS = { instagram: 'Instagram', facebook: 'Facebook', tiktok: 'TikTok', youtube: 'YouTube', linkedin: 'LinkedIn', x: 'X', threads: 'Threads' }
const TYPE_LABELS = { reel: 'Reel', feed_image: 'Imagem', carousel: 'Carrossel', story: 'Story', ugc_video: 'UGC', ad: 'Anúncio', thumbnail: 'Thumb', cover: 'Capa', outros: 'Outros' }
const PROVIDER_COLORS = { instagram: '#DB2777', facebook: '#2563EB', tiktok: '#0F172A', youtube: '#DC2626', linkedin: '#0A66C2', x: '#334155', threads: '#111827' }

function Panel({ title, children }) {
  return (
    <div className="rounded-2xl border border-border bg-surface p-4 sm:p-5">
      <h3 className="mb-3 text-xs font-bold uppercase tracking-wider text-ink-muted">{title}</h3>
      {children}
    </div>
  )
}

export default function Breakdowns({ data }) {
  const trend = data.timeseries || []
  const networks = (data.by_network || []).map((n) => ({ ...n, label: PROVIDER_LABELS[n.provider] || n.provider }))
  const types = (data.by_type || []).map((t) => ({ ...t, label: TYPE_LABELS[t.creative_type] || t.creative_type }))
  const campaigns = (data.by_campaign || []).map((c) => ({ ...c, label: c.project_name || '—' }))

  return (
    <div className="mt-4 grid grid-cols-1 gap-4 lg:grid-cols-2">
      <div className="lg:col-span-2">
        <Panel title="Tendência ao longo do tempo">
          {trend.length > 0
            ? <TrendChart data={trend} series={[
                { key: 'views', label: 'Views', color: '#2563EB' },
                { key: 'reach', label: 'Alcance', color: '#7C3AED' },
                { key: 'engagement', label: 'Engajamento', color: '#DB2777' },
              ]} />
            : <p className="py-8 text-center text-sm text-ink-muted">Sem dados no período.</p>}
        </Panel>
      </div>

      <Panel title="Por rede">
        <CategoryBars data={networks} dataKey="views" nameKey="label" colorFor={(e) => PROVIDER_COLORS[e.provider] || '#7C3AED'} />
      </Panel>
      <Panel title="Por tipo de criativo">
        <CategoryBars data={types} dataKey="views" nameKey="label" />
      </Panel>
      {campaigns.length > 0 && (
        <div className="lg:col-span-2">
          <Panel title="Por campanha">
            <CategoryBars data={campaigns} dataKey="views" nameKey="label" colorFor={(e) => e.color || '#4F46E5'} />
          </Panel>
        </div>
      )}
    </div>
  )
}
```

- [ ] **Step 3: Render Breakdowns in the orchestrator**

In `app/frontend/components/client/ClientPerformance.jsx`, add the import and mount it below `<KpiRow />`:

```jsx
import Breakdowns from './performance/Breakdowns'
```

Replace the placeholder comment line inside the `{!isLoading && kpis && !empty && (...)}` block with:

```jsx
          <KpiRow kpis={kpis} account={data.account} />
          <Breakdowns data={data} />
          {/* Top posts (Task 7) and AI insight (Task 8) mount here. */}
```

- [ ] **Step 4: Verify the build compiles**

Run: `bin/vite build`
Expected: build succeeds (recharts resolves; no errors).

- [ ] **Step 5: Manually verify**

Reload the Performance tab. Expected: a multi-line trend chart and horizontal bar breakdowns by network / type / campaign render, themed to the app; tooltips format numbers in compact pt-BR.

- [ ] **Step 6: Commit**

```bash
git add app/frontend/components/ui/charts.jsx app/frontend/components/client/performance/Breakdowns.jsx app/frontend/components/client/ClientPerformance.jsx
git commit -m "feat(clients): Performance charts — trend + breakdowns (recharts)"
```

---

### Task 7: Top posts table + honest partial-metric rendering

**Files:**
- Create: `app/frontend/components/client/performance/TopPosts.jsx`
- Modify: `app/frontend/components/client/ClientPerformance.jsx` (render + pass `metric_support`)

**Interfaces:**
- Consumes: `data.top_posts`, `data.meta.metric_support` from Task 1; existing `date` formatter from `@/lib/formatters`.
- Produces: `<TopPosts posts metricSupport />` rendering a ranked list; a metric a network doesn't report shows `—`, not `0`.

- [ ] **Step 1: Build the TopPosts component**

Create `app/frontend/components/client/performance/TopPosts.jsx`:

```jsx
import { ExternalLink } from 'lucide-react'
import { date } from '@/lib/formatters'

const PROVIDER_LABELS = { instagram: 'Instagram', facebook: 'Facebook', tiktok: 'TikTok', youtube: 'YouTube', linkedin: 'LinkedIn', x: 'X', threads: 'Threads' }
const TYPE_LABELS = { reel: 'Reel', feed_image: 'Imagem', carousel: 'Carrossel', story: 'Story', ugc_video: 'UGC', ad: 'Anúncio', thumbnail: 'Thumb', cover: 'Capa', outros: 'Outros' }
const nf = new Intl.NumberFormat('pt-BR', { notation: 'compact', maximumFractionDigits: 1 })

// Renders the metric, or "—" when the post's network doesn't report it.
function metricCell(post, key, metricSupport) {
  const supported = metricSupport?.[post.provider]
  if (supported && !supported.includes(key)) return <span className="text-ink-muted/50">—</span>
  return nf.format(Number(post[key]) || 0)
}

export default function TopPosts({ posts = [], metricSupport }) {
  if (posts.length === 0) return null
  const cols = [['views', 'Views'], ['reach', 'Alcance'], ['engagement', 'Eng.'], ['shares', 'Compart.'], ['saves', 'Salvos']]

  return (
    <div className="mt-4 rounded-2xl border border-border bg-surface p-4 sm:p-5">
      <h3 className="mb-3 text-xs font-bold uppercase tracking-wider text-ink-muted">Top posts</h3>
      <div className="overflow-x-auto">
        <table className="w-full min-w-[560px] text-sm">
          <thead>
            <tr className="border-b border-border text-left text-xs font-bold uppercase tracking-wider text-ink-muted">
              <th className="py-2 pr-3">Post</th>
              {cols.map(([, label]) => <th key={label} className="px-3 py-2 text-right">{label}</th>)}
              <th className="py-2" />
            </tr>
          </thead>
          <tbody>
            {posts.map((post) => (
              <tr key={post.post_id} className="border-b border-border/60 last:border-0">
                <td className="py-2.5 pr-3">
                  <p className="font-semibold text-ink line-clamp-1">{post.label || 'Post'}</p>
                  <p className="text-xs text-ink-muted">
                    {(PROVIDER_LABELS[post.provider] || post.provider)} · {TYPE_LABELS[post.creative_type] || post.creative_type}
                    {post.published_at ? ` · ${date(post.published_at)}` : ''}
                  </p>
                </td>
                {cols.map(([key]) => (
                  <td key={key} className="px-3 py-2.5 text-right font-medium tabular-nums text-ink">{metricCell(post, key, metricSupport)}</td>
                ))}
                <td className="py-2.5 pl-2">
                  {post.permalink && (
                    <a href={post.permalink} target="_blank" rel="noreferrer" className="text-ink-muted transition hover:text-brand">
                      <ExternalLink size={15} />
                    </a>
                  )}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
      <p className="mt-3 text-xs text-ink-muted">
        "—" = métrica não reportada por essa rede. As métricas são atualizadas por ~30 dias após a publicação.
      </p>
    </div>
  )
}
```

- [ ] **Step 2: Render TopPosts in the orchestrator**

In `app/frontend/components/client/ClientPerformance.jsx`, add the import and mount it after `<Breakdowns />`:

```jsx
import TopPosts from './performance/TopPosts'
```

```jsx
          <Breakdowns data={data} />
          <TopPosts posts={data.top_posts} metricSupport={data.meta?.metric_support} />
          {/* AI insight (Task 8) mounts here. */}
```

- [ ] **Step 3: Verify the build compiles**

Run: `bin/vite build`
Expected: build succeeds.

- [ ] **Step 4: Manually verify**

Reload the Performance tab. Expected: a ranked top-posts table with network/type/date subline; a TikTok/YouTube row shows `—` under Alcance/Salvos; permalinks open in a new tab; the honesty footnote is visible.

- [ ] **Step 5: Commit**

```bash
git add app/frontend/components/client/performance/TopPosts.jsx app/frontend/components/client/ClientPerformance.jsx
git commit -m "feat(clients): Performance top-posts table with honest partial metrics"
```

---

### Task 8: AI insight card

**Files:**
- Create: `app/frontend/components/client/performance/AiInsightCard.jsx`
- Modify: `app/frontend/components/client/ClientPerformance.jsx` (mount + pass filters)

**Interfaces:**
- Consumes: `useClientPerformanceInsight(clientId)` mutation from Task 5; the same `query` filter object the data hook uses.
- Produces: `<AiInsightCard clientId query />` — button-triggered generation, loading/empty/error states, markdown render.

- [ ] **Step 1: Confirm the markdown renderer available in the app**

Run: `grep -rn "react-markdown\|ReactMarkdown\|marked" app/frontend | head`
Expected: shows how rich text / AI output is already rendered (e.g. `react-markdown`). Use whatever this reveals in Step 2. If nothing is found, render the text in a `whitespace-pre-wrap` block (fallback shown below).

- [ ] **Step 2: Build the AiInsightCard**

Create `app/frontend/components/client/performance/AiInsightCard.jsx`:

```jsx
import { useState } from 'react'
import { Sparkles, RefreshCw } from 'lucide-react'
import { useClientPerformanceInsight } from '@/hooks/useData'

export default function AiInsightCard({ clientId, query }) {
  const insight = useClientPerformanceInsight(clientId)
  const [text, setText] = useState(null)
  const [unavailable, setUnavailable] = useState(false)

  const generate = () => {
    insight.mutate(query, {
      onSuccess: (res) => {
        setUnavailable(!res?.available)
        setText(res?.available ? res.insight : null)
      },
    })
  }

  return (
    <div className="mt-4 rounded-2xl border border-brand/30 bg-brand/[0.04] p-4 sm:p-5">
      <div className="mb-3 flex items-center justify-between gap-2">
        <h3 className="flex items-center gap-2 text-sm font-bold text-ink">
          <Sparkles size={16} className="text-brand" /> Leitura da IA
        </h3>
        <button
          type="button"
          onClick={generate}
          disabled={insight.isPending}
          className="inline-flex items-center gap-1.5 rounded-lg bg-brand px-3 py-1.5 text-xs font-semibold text-white transition hover:opacity-90 disabled:opacity-50"
        >
          {insight.isPending ? <RefreshCw size={14} className="animate-spin" /> : <Sparkles size={14} />}
          {text ? 'Gerar novamente' : 'Gerar análise'}
        </button>
      </div>

      {insight.isPending && <p className="text-sm text-ink-muted">Analisando o desempenho…</p>}

      {!insight.isPending && insight.isError && (
        <p className="text-sm text-red-600">Não foi possível gerar a leitura agora. Tente novamente.</p>
      )}

      {!insight.isPending && unavailable && (
        <p className="text-sm text-ink-muted">Leitura indisponível — sem dados suficientes no período (ou a IA está temporariamente fora do ar).</p>
      )}

      {!insight.isPending && text && (
        <div className="prose prose-sm max-w-none whitespace-pre-wrap text-sm leading-relaxed text-ink">{text}</div>
      )}

      {!insight.isPending && !text && !unavailable && !insight.isError && (
        <p className="text-sm text-ink-muted">Gere uma análise em linguagem natural do desempenho filtrado acima.</p>
      )}
    </div>
  )
}
```

_(If Step 1 revealed `react-markdown`, replace the `<div className="prose …">{text}</div>` with the app's markdown component, e.g. `<ReactMarkdown>{text}</ReactMarkdown>` inside a `prose` wrapper. The `whitespace-pre-wrap` version above is a correct fallback.)_

- [ ] **Step 3: Mount it in the orchestrator**

In `app/frontend/components/client/ClientPerformance.jsx`, add the import and mount it last:

```jsx
import AiInsightCard from './performance/AiInsightCard'
```

```jsx
          <TopPosts posts={data.top_posts} metricSupport={data.meta?.metric_support} />
          <AiInsightCard clientId={clientId} query={query} />
```

- [ ] **Step 4: Verify the build compiles**

Run: `bin/vite build`
Expected: build succeeds.

- [ ] **Step 5: Manually verify**

Reload the Performance tab, click **Gerar análise**. Expected: spinner, then a markdown reading; on a client with no posts in range the card is not shown (empty-state branch) or shows the "indisponível" line if generated; changing filters + regenerating reflects the new window.

- [ ] **Step 6: Run the full backend suite to confirm no regressions**

Run: `bundle exec rspec spec/services/operations/analytics spec/requests/api/v1/client_performance_spec.rb`
Expected: all PASS.

- [ ] **Step 7: Commit**

```bash
git add app/frontend/components/client/performance/AiInsightCard.jsx app/frontend/components/client/ClientPerformance.jsx
git commit -m "feat(clients): Performance AI-insight card"
```

---

## Self-Review (completed against the spec)

- **Spec coverage:** date/campaign/network/type filters → Task 1 params + Task 5 FilterBar ✓; KPIs + deltas → Task 1 `kpis` + Task 5 KpiRow ✓; account-level metrics → Task 1 `account_block` + KpiRow followers card ✓; timeseries + breakdowns → Task 1 + Task 6 ✓; top posts → Task 1 + Task 7 ✓; AI narrative (sync, honest failure) → Tasks 2/4/8 ✓; recharts hybrid → Task 6 ✓; data-honesty (`—`, ~30-day note, engagement_rate ÷ views tooltip) → Tasks 1/5/7 ✓; tab wiring `/desempenho` → Task 5 ✓; Pundit + workspace scoping + 402 gate → Tasks 3/4 + request spec ✓.
- **Placeholder scan:** no TBD/TODO; every code step carries full code; the only "mounts here" markers are inline comments replaced by real JSX in the next task.
- **Type consistency:** `Operations::Analytics::ClientPerformance.call(client:, from:, to:, project_ids:, providers:, creative_types:)` and `ClientPerformanceInsight.call(client:, data:)` used identically in ops, controllers, and specs; response keys (`kpis/account/timeseries/by_network/by_type/by_campaign/top_posts/meta`) consumed with the same names on the frontend; `clientsApi.performance/performanceInsight`, `keys.clientPerformance`, `useClientPerformance/useClientPerformanceInsight` names match across files.
