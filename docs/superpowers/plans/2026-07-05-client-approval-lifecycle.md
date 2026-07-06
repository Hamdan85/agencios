# Client Approval Link & Approval-Driven Lifecycle — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a per-ticket, login-less client approval link (per-creative approve / request-changes), make GO (autopilot) stop at `production`, and have full client approval auto-schedule the ticket; redesign the production step's approval UI into real state + confirmed actions; hold the approval/publish/scheduling behavior in a new per-project settings surface.

**Architecture:** Ruby services (`.call`, English) do all work; controllers only delegate. New `Operations::Approvals::*` namespace + `Operations::Scheduling::NextSlot`. Autopilot's `publishing` phase is removed — a new `Operations::Autopilot::Complete` finishes runs at `production` and requests approval; approval completion reuses `Operations::Tickets::ChangeStatus` (production→scheduled) + `Operations::Tickets::Publish` (creates scheduled posts). A public token-authed API (`Api::V1::Public::ApprovalsController`) backs a public React route `/aprovar/:token`. Project settings live in a new `projects.settings` jsonb blob (mirrors `Setting#preferences`).

**Tech Stack:** Rails 8.1 + PostgreSQL, RSpec, Sidekiq/ActiveJob, ActionMailer (branded `mailer` layout); React 19 + React Router 7 + TanStack Query v5 + Radix UI + Tailwind v4; axios via `@/api` (returns `res.data`).

## Global Constraints

- **All code 100% English** (identifiers, columns, enum keys, comments, git messages). Only user-facing UI strings, email copy, and frontend URL segments may be Portuguese (e.g. `/aprovar`).
- **`.call(...)` on every service**; never `.new` a service directly. Base classes: `Controllers::Base`, `Operations::Base`.
- **No AR callbacks for side effects** — orchestrate in operations.
- **Never bare-`create!` another entity from a service** — call that entity's operation (Notes via `Operations::Notes::Create`, Posts via `Operations::Tickets::Publish` / `Operations::Posts::*`).
- **Every query scoped to `Current.workspace`**; the public controller sets `Current.workspace` from the token.
- **Status changes only via `Operations::Tickets::ChangeStatus`** (positional `ChangeStatus.call(ticket, to_status, user:, force:)`).
- **Dates ISO 8601 (`&.iso8601`), money in cents** — never pre-format on the backend; frontend formatters render.
- Serializers subclass `ActiveModel::Serializer`; declare `attributes :a, :b`; overrides are endless one-liners reading `object`.
- Operations expose only `workspace` (`Current.workspace`); they take the acting user as an explicit `user:` kwarg. There is **no `actor`/`current_user`** in `Operations::Base`.
- Run tests with `bundle exec rspec <path>`. Migrate with `bin/rails db:migrate`.

---

## File Structure

**Created (backend):**
- `db/migrate/*_add_approval_to_creatives.rb`, `*_add_approval_to_tickets.rb`, `*_add_settings_to_projects.rb`, `*_narrow_autopilot_active_index.rb`
- `app/services/tickets/project_settings.rb` — project-settings value object (keys, defaults, sanitize).
- `app/services/controllers/projects/update_settings.rb`
- `app/services/operations/scheduling/next_slot.rb`
- `app/services/operations/approvals/{request_approval,decide_creative,approve_all,on_fully_approved,schedule_approved}.rb`
- `app/services/operations/autopilot/complete.rb`
- `app/services/controllers/approvals/{request_approval,approve}.rb` (internal ticket actions)
- `app/services/controllers/public/approvals/{show,approve_creative,request_changes}.rb`
- `app/controllers/api/v1/public/approvals_controller.rb`
- `app/mailers/approval_mailer.rb` + `app/views/approval_mailer/request.{html,text}.erb`

**Modified (backend):** `app/models/creative.rb`, `app/models/ticket.rb`, `app/models/project.rb`, `app/models/autopilot_run.rb`, `app/services/operations/autopilot/{advance,kick_generations,on_generation_settled,start}.rb` (remove `publish_step.rb`), `app/services/tickets/fields.rb`, `app/serializers/{creative_serializer,ticket_serializer,project_serializer}.rb`, `app/controllers/api/v1/{projects_controller,tickets_controller}.rb`, `config/routes.rb`.

**Created (frontend):** `app/frontend/components/creative/CreativeExperience.jsx`, `app/frontend/components/ticket/ApprovalPanel.jsx`, `app/frontend/pages/Approval/Show.jsx`, `app/frontend/components/project/ProjectSettingsTab.jsx`.

**Modified (frontend):** `app/frontend/api/index.js`, `app/frontend/api/queryKeys.js`, `app/frontend/hooks/useData.js`, `app/frontend/App.jsx`, `app/frontend/pages/Projects/Show.jsx`, `app/frontend/components/ticket/FieldGroup.jsx`, `app/frontend/components/ticket/TicketBody.jsx`.

---

# PHASE A — Data model & project settings

### Task A1: Creative approval fields

**Files:**
- Create: `db/migrate/20260706100000_add_approval_to_creatives.rb`
- Modify: `app/models/creative.rb`
- Test: `spec/models/creative_spec.rb`

**Interfaces:**
- Produces: `Creative#approval_state` enum (`approval_pending?`/`approval_approved?`/`approval_changes_requested?`), `#reviewed_by` (polymorphic), columns `client_feedback:text`, `decided_at:datetime`.

- [ ] **Step 1: Write the failing test**

```ruby
# spec/models/creative_spec.rb  (add inside the existing describe, or create the file)
require 'rails_helper'

RSpec.describe Creative do
  it 'defaults approval_state to pending and supports polymorphic reviewer' do
    ws = Workspace.create!(name: 'WS')
    creative = Creative.create!(workspace: ws, creative_type: 'carousel')
    expect(creative.approval_pending?).to be(true)

    user = User.create!(email: 'a@b.co', password: 'password123', name: 'A')
    creative.update!(approval_state: 'approved', reviewed_by: user, decided_at: Time.current)
    expect(creative.reload.reviewed_by).to eq(user)
    expect(creative.approval_approved?).to be(true)
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/models/creative_spec.rb -e 'defaults approval_state'`
Expected: FAIL — `unknown attribute 'approval_state'`.

- [ ] **Step 3: Write the migration + model change**

```ruby
# db/migrate/20260706100000_add_approval_to_creatives.rb
# frozen_string_literal: true

class AddApprovalToCreatives < ActiveRecord::Migration[8.1]
  def change
    add_column :creatives, :approval_state, :string, null: false, default: 'pending'
    add_column :creatives, :client_feedback, :text
    add_column :creatives, :decided_at, :datetime
    # Who decided — a workspace User (internal "Aprovar") or the Client (via link).
    add_reference :creatives, :reviewed_by, polymorphic: true, null: true, index: true
  end
end
```

```ruby
# app/models/creative.rb — add below the existing enums (after line 17)
  enum :approval_state, { pending: 0, approved: 1, changes_requested: 2 },
       prefix: :approval, default: :pending, scopes: false
```

Change the `enum :approval_state` to use string backing to match the string column default. Replace the line above with the string-safe form:

```ruby
# app/models/creative.rb — the approval enum (string-backed, matches the string column)
  enum :approval_state,
       { pending: 'pending', approved: 'approved', changes_requested: 'changes_requested' },
       prefix: :approval, default: 'pending', scopes: false
```

Add the polymorphic association near the other `belongs_to` lines:

```ruby
# app/models/creative.rb — with the other associations (after `belongs_to :parent ...`)
  belongs_to :reviewed_by, polymorphic: true, optional: true
```

- [ ] **Step 4: Migrate and run the test**

Run: `bin/rails db:migrate && bundle exec rspec spec/models/creative_spec.rb -e 'defaults approval_state'`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add db/migrate/20260706100000_add_approval_to_creatives.rb db/schema.rb app/models/creative.rb spec/models/creative_spec.rb
git commit -m "feat(creatives): per-creative approval state + polymorphic reviewer"
```

---

### Task A2: Ticket approval token + derived approval helpers

**Files:**
- Create: `db/migrate/20260706100100_add_approval_to_tickets.rb`
- Modify: `app/models/ticket.rb`
- Test: `spec/models/ticket_spec.rb`

**Interfaces:**
- Produces: `Ticket#approval_token!` (lazily mints/returns a secret), columns `approval_token:string` (unique), `approval_requested_at:datetime`; `Ticket#approvable_creatives` (ready, non-superseded), `#fully_approved?`, `#approval_actor` (the reviewer of the last-decided approved creative).

- [ ] **Step 1: Write the failing test**

```ruby
# spec/models/ticket_spec.rb (add a context)
require 'rails_helper'

RSpec.describe Ticket do
  let(:ws) { Workspace.create!(name: 'WS') }
  let(:client) { Client.create!(workspace: ws, name: 'Cliente', email: 'c@cli.co') }
  let(:project) { Project.create!(workspace: ws, client: client, name: 'Camp', status: :active) }
  let(:ticket) { Ticket.create!(workspace: ws, project: project, status: :production) }

  it 'mints a stable approval token' do
    token = ticket.approval_token!
    expect(token).to be_present
    expect(ticket.approval_token!).to eq(token) # idempotent
  end

  it 'excludes superseded creatives and reports full approval' do
    old = Creative.create!(workspace: ws, ticket: ticket, creative_type: 'carousel', status: :ready)
    fresh = Creative.create!(workspace: ws, ticket: ticket, creative_type: 'carousel', status: :ready, parent: old)
    expect(ticket.approvable_creatives).to contain_exactly(fresh)

    expect(ticket.fully_approved?).to be(false)
    fresh.update!(approval_state: 'approved', reviewed_by: client, decided_at: Time.current)
    expect(ticket.reload.fully_approved?).to be(true)
    expect(ticket.approval_actor).to eq(client)
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/models/ticket_spec.rb -e 'approval token'`
Expected: FAIL — `undefined method 'approval_token!'`.

- [ ] **Step 3: Migration + model methods**

```ruby
# db/migrate/20260706100100_add_approval_to_tickets.rb
# frozen_string_literal: true

class AddApprovalToTickets < ActiveRecord::Migration[8.1]
  def change
    add_column :tickets, :approval_token, :string
    add_column :tickets, :approval_requested_at, :datetime
    add_index  :tickets, :approval_token, unique: true
  end
end
```

```ruby
# app/models/ticket.rb — add these methods (near fields_for / creative_types_list)

  # A ticket's random, revocable approval-link secret. Lazily minted; stable
  # across calls so "reenviar link" reuses the same URL. Powers /aprovar/:token.
  def approval_token!
    return approval_token if approval_token.present?

    update!(approval_token: "apv_#{SecureRandom.urlsafe_base64(32)}")
    approval_token
  end

  # The creatives the client approves: ready, and not superseded by a newer
  # version (a creative referenced as another creative's parent is superseded).
  def approvable_creatives
    ready = creatives.select(&:status_ready?)
    superseded_ids = creatives.filter_map(&:parent_id).to_set
    ready.reject { |c| superseded_ids.include?(c.id) }
  end

  # Approved iff there is at least one approvable creative and all are approved.
  def fully_approved?
    set = approvable_creatives
    set.any? && set.all?(&:approval_approved?)
  end

  # The reviewer (User or Client) of the most recently decided approved creative
  # — drives "Aprovado por <actor>".
  def approval_actor
    approvable_creatives.select(&:approval_approved?)
                        .max_by { |c| c.decided_at || Time.at(0) }&.reviewed_by
  end
```

- [ ] **Step 4: Migrate and run**

Run: `bin/rails db:migrate && bundle exec rspec spec/models/ticket_spec.rb -e 'superseded'`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add db/migrate/20260706100100_add_approval_to_tickets.rb db/schema.rb app/models/ticket.rb spec/models/ticket_spec.rb
git commit -m "feat(tickets): approval token + derived approval helpers"
```

---

### Task A3: Project settings blob + resolver + value object

**Files:**
- Create: `db/migrate/20260706100200_add_settings_to_projects.rb`, `app/services/tickets/project_settings.rb`
- Modify: `app/models/project.rb`
- Test: `spec/services/tickets/project_settings_spec.rb`, `spec/models/project_spec.rb`

**Interfaces:**
- Produces: `Project#settings` jsonb; `Project#resolved_settings` (defaults + workspace fallback merged); `Project#setting(key)`; `Tickets::ProjectSettings.defaults`, `.sanitize(hash)`, `.resolve(project)` returning a hash with keys `require_client_approval` (bool), `auto_publish_after_approval` (bool), `posting_window` (`{weekdays:[Int], times:[String], min_gap_minutes:Int, timezone:String}`).

- [ ] **Step 1: Write the failing test**

```ruby
# spec/services/tickets/project_settings_spec.rb
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
    ws = Workspace.create!(name: 'WS')
    ws.create_setting!(auto_publish_default: true)
    client = Client.create!(workspace: ws, name: 'C')
    project = Project.create!(workspace: ws, client: client, name: 'P', status: :active)

    resolved = described_class.resolve(project)
    expect(resolved['require_client_approval']).to be(false) # default
    expect(resolved['auto_publish_after_approval']).to be(true) # from workspace
    expect(resolved['posting_window']['weekdays']).to eq([1, 2, 3, 4, 5])
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/services/tickets/project_settings_spec.rb`
Expected: FAIL — uninitialized constant `Tickets::ProjectSettings`.

- [ ] **Step 3: Migration, value object, model**

```ruby
# db/migrate/20260706100200_add_settings_to_projects.rb
# frozen_string_literal: true

class AddSettingsToProjects < ActiveRecord::Migration[8.1]
  def change
    add_column :projects, :settings, :jsonb, null: false, default: {}
  end
end
```

```ruby
# app/services/tickets/project_settings.rb
# frozen_string_literal: true

module Tickets
  # Value object for a project's approval/publishing/scheduling configuration,
  # stored in `projects.settings` (jsonb). Mirrors the Tickets::Fields pattern:
  # a single source of truth for allowed keys, typed coercion, and default
  # resolution (with a workspace-level fallback for auto-publish).
  module ProjectSettings
    module_function

    def defaults
      {
        'require_client_approval' => false,
        'auto_publish_after_approval' => false,
        'posting_window' => {
          'weekdays' => [1, 2, 3, 4, 5], # 0=Sun .. 6=Sat
          'times' => ['09:00', '12:00', '18:00'],
          'min_gap_minutes' => 120,
          'timezone' => 'America/Sao_Paulo'
        }
      }
    end

    # Keep only known keys, coercing to the right types. Unknown keys dropped.
    def sanitize(raw)
      raw = (raw || {}).to_h.stringify_keys
      out = {}
      out['require_client_approval'] = to_bool(raw['require_client_approval']) if raw.key?('require_client_approval')
      out['auto_publish_after_approval'] = to_bool(raw['auto_publish_after_approval']) if raw.key?('auto_publish_after_approval')
      out['posting_window'] = sanitize_window(raw['posting_window']) if raw.key?('posting_window')
      out
    end

    # Defaults, overlaid with the workspace auto-publish fallback, overlaid with
    # the project's own stored settings.
    def resolve(project)
      base = defaults
      ws_default = project.workspace.setting&.auto_publish_default
      base['auto_publish_after_approval'] = ws_default unless ws_default.nil?
      deep_merge(base, sanitize(project.settings))
    end

    def sanitize_window(raw)
      raw = (raw || {}).to_h.stringify_keys
      d = defaults['posting_window']
      {
        'weekdays' => Array(raw['weekdays']).map { |w| w.to_i }.select { |w| (0..6).cover?(w) }.uniq.presence || d['weekdays'],
        'times' => Array(raw['times']).filter_map { |t| normalize_time(t) }.uniq.presence || d['times'],
        'min_gap_minutes' => (raw['min_gap_minutes'].presence || d['min_gap_minutes']).to_i.clamp(0, 10_080),
        'timezone' => raw['timezone'].to_s.presence || d['timezone']
      }
    end

    # "9:0" -> "09:00"; invalid -> nil.
    def normalize_time(value)
      m = value.to_s.strip.match(/\A(\d{1,2}):(\d{1,2})\z/)
      return nil unless m

      h = m[1].to_i
      min = m[2].to_i
      return nil unless (0..23).cover?(h) && (0..59).cover?(min)

      format('%02d:%02d', h, min)
    end

    def to_bool(value)
      ActiveModel::Type::Boolean.new.cast(value) || false
    end

    def deep_merge(a, b)
      a.merge(b) { |_k, av, bv| av.is_a?(Hash) && bv.is_a?(Hash) ? deep_merge(av, bv) : bv }
    end
  end
end
```

```ruby
# app/models/project.rb — add methods (near latest_report)
  def resolved_settings
    Tickets::ProjectSettings.resolve(self)
  end

  def setting(key)
    resolved_settings[key.to_s]
  end
```

- [ ] **Step 4: Migrate and run**

Run: `bin/rails db:migrate && bundle exec rspec spec/services/tickets/project_settings_spec.rb`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add db/migrate/20260706100200_add_settings_to_projects.rb db/schema.rb app/services/tickets/project_settings.rb app/models/project.rb spec/services/tickets/project_settings_spec.rb
git commit -m "feat(projects): settings jsonb + ProjectSettings value object with workspace fallback"
```

---

### Task A4: Project settings endpoint + serializer

**Files:**
- Create: `app/services/controllers/projects/update_settings.rb`
- Modify: `app/controllers/api/v1/projects_controller.rb`, `config/routes.rb`, `app/serializers/project_serializer.rb`
- Test: `spec/requests/api/v1/project_settings_spec.rb`

**Interfaces:**
- Consumes: `Tickets::ProjectSettings.sanitize` (A3), `require_manager!` (Controllers::Base).
- Produces: `PATCH /api/v1/projects/:id/settings` → `Controllers::Projects::UpdateSettings`; `ProjectSerializer#settings` (resolved).

- [ ] **Step 1: Write the failing test**

```ruby
# spec/requests/api/v1/project_settings_spec.rb
require 'rails_helper'

RSpec.describe 'Project settings', type: :request do
  include_context 'authenticated manager' if defined?(RSpec) # see note below

  it 'updates and echoes resolved settings' do
    sign_in_as_manager # helper that logs in a manager + activates billing
    project = Project.create!(workspace: current_workspace, client: Client.create!(workspace: current_workspace, name: 'C'), name: 'P', status: :active)

    patch "/api/v1/projects/#{project.id}/settings",
          params: { settings: { require_client_approval: true, posting_window: { weekdays: [1, 2], times: ['10:00'] } } },
          as: :json

    expect(response).to have_http_status(:ok)
    body = JSON.parse(response.body)
    expect(body['project']['settings']['require_client_approval']).to be(true)
    expect(body['project']['settings']['posting_window']['weekdays']).to eq([1, 2])
  end
end
```

> Note: this repo's request specs must activate billing after registering (see `spec/support` billing helpers). Reuse the existing manager/billing helper used by other `spec/requests/api/v1/*` specs (grep for `sign_in_as_manager` / the shared context). If a different helper name exists, use it verbatim.

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/requests/api/v1/project_settings_spec.rb`
Expected: FAIL — 404 (no route) / missing service.

- [ ] **Step 3: Service, controller action, route, serializer**

```ruby
# app/services/controllers/projects/update_settings.rb
# frozen_string_literal: true

module Controllers
  module Projects
    class UpdateSettings < Base
      def initialize(params:)
        @params = params
      end

      def call
        require_manager!
        project = workspace.projects.find(@params[:id])
        incoming = @params.fetch(:settings, {}).permit!.to_h
        project.update!(settings: Tickets::ProjectSettings.sanitize(incoming))
        { project: serialize(project, ProjectSerializer) }
      end
    end
  end
end
```

```ruby
# app/controllers/api/v1/projects_controller.rb — add inside the class
      def settings = render_ok(Controllers::Projects::UpdateSettings.call(params:))
```

```ruby
# config/routes.rb — inside `resources :projects do ... member do ... end`, add to the member block:
          patch :settings
```

```ruby
# app/serializers/project_serializer.rb — add `:settings` to the attributes list and this method
  def settings = object.resolved_settings
```

- [ ] **Step 4: Run the test**

Run: `bundle exec rspec spec/requests/api/v1/project_settings_spec.rb`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add app/services/controllers/projects/update_settings.rb app/controllers/api/v1/projects_controller.rb config/routes.rb app/serializers/project_serializer.rb spec/requests/api/v1/project_settings_spec.rb
git commit -m "feat(projects): PATCH settings endpoint + serialized resolved settings"
```

---

### Task A5: Project settings UI (Configurações tab)

**Files:**
- Modify: `app/frontend/api/index.js`, `app/frontend/api/queryKeys.js`, `app/frontend/hooks/useData.js`, `app/frontend/App.jsx`, `app/frontend/pages/Projects/Show.jsx`
- Create: `app/frontend/components/project/ProjectSettingsTab.jsx`

**Interfaces:**
- Consumes: `PATCH /api/v1/projects/:id/settings` (A4).
- Produces: `projectsApi.updateSettings(id, settings)`, `useProjectMutations().updateSettings`, a `Configurações` tab on `/campanhas/:id/configuracoes`.

- [ ] **Step 1: API + hook + route wiring**

```js
// app/frontend/api/index.js — add to projectsApi object
  updateSettings: (id, settings) => api.patch(`/projects/${id}/settings`, { settings }),
```

```js
// app/frontend/hooks/useData.js — add to the object returned by useProjectMutations()
    updateSettings: useMutation({
      mutationFn: ({ id, settings }) => projectsApi.updateSettings(id, settings),
      onSuccess: () => { inv(); toast.success('Configurações da campanha salvas!') },
      onError: onErr('Erro ao salvar as configurações.'),
    }),
```

```jsx
// app/frontend/App.jsx — add a :tab route beside /campanhas/:id (inside the protected Layout block)
          <Route path="/campanhas/:id/:tab" element={<ProjectShow />} />
```

- [ ] **Step 2: Build the settings tab component**

```jsx
// app/frontend/components/project/ProjectSettingsTab.jsx
import { useEffect, useState } from 'react'
import { ShieldCheck, Rocket, CalendarClock } from 'lucide-react'
import { Card } from '@/components/ui/card'
import { Switch } from '@/components/ui/switch'
import { Button } from '@/components/ui/button'
import { useProjectMutations } from '@/hooks/useData'

const WEEKDAYS = [
  { v: 1, label: 'Seg' }, { v: 2, label: 'Ter' }, { v: 3, label: 'Qua' },
  { v: 4, label: 'Qui' }, { v: 5, label: 'Sex' }, { v: 6, label: 'Sáb' }, { v: 0, label: 'Dom' },
]

export default function ProjectSettingsTab({ project }) {
  const s = project.settings || {}
  const w = s.posting_window || {}
  const [requireApproval, setRequireApproval] = useState(!!s.require_client_approval)
  const [autoPublish, setAutoPublish] = useState(!!s.auto_publish_after_approval)
  const [weekdays, setWeekdays] = useState(w.weekdays || [1, 2, 3, 4, 5])
  const [times, setTimes] = useState((w.times || ['09:00', '12:00', '18:00']).join(', '))
  const [minGap, setMinGap] = useState(w.min_gap_minutes ?? 120)
  const { updateSettings } = useProjectMutations()

  useEffect(() => {
    setRequireApproval(!!s.require_client_approval)
    setAutoPublish(!!s.auto_publish_after_approval)
  }, [project.id]) // eslint-disable-line react-hooks/exhaustive-deps

  const toggleDay = (v) => setWeekdays((d) => (d.includes(v) ? d.filter((x) => x !== v) : [...d, v]))

  const save = () => updateSettings.mutate({
    id: project.id,
    settings: {
      require_client_approval: requireApproval,
      auto_publish_after_approval: autoPublish,
      posting_window: {
        weekdays,
        times: times.split(',').map((t) => t.trim()).filter(Boolean),
        min_gap_minutes: Number(minGap) || 0,
        timezone: w.timezone || 'America/Sao_Paulo',
      },
    },
  })

  return (
    <div className="flex flex-col gap-4">
      <Card className="p-5">
        <div className="flex items-start gap-3">
          <ShieldCheck className="mt-0.5 text-brand" size={20} />
          <div className="flex-1">
            <p className="font-semibold text-ink">Exigir aprovação do cliente</p>
            <p className="text-sm text-ink-muted">O GO para em Produção e o cliente recebe o link de aprovação por e-mail.</p>
          </div>
          <Switch checked={requireApproval} onCheckedChange={setRequireApproval} />
        </div>
      </Card>

      <Card className="p-5">
        <div className="flex items-start gap-3">
          <Rocket className="mt-0.5 text-brand" size={20} />
          <div className="flex-1">
            <p className="font-semibold text-ink">Publicar após aprovação</p>
            <p className="text-sm text-ink-muted">Quando todos os criativos forem aprovados, o post é agendado automaticamente.</p>
          </div>
          <Switch checked={autoPublish} onCheckedChange={setAutoPublish} />
        </div>
      </Card>

      <Card className="p-5">
        <div className="mb-3 flex items-center gap-2">
          <CalendarClock className="text-brand" size={20} />
          <p className="font-semibold text-ink">Janela de postagem</p>
        </div>
        <div className="mb-3 flex flex-wrap gap-1.5">
          {WEEKDAYS.map((d) => (
            <button key={d.v} type="button" onClick={() => toggleDay(d.v)}
              className={`rounded-lg px-3 py-1.5 text-sm font-medium transition ${weekdays.includes(d.v) ? 'bg-brand text-white' : 'bg-surface-muted text-ink-muted'}`}>
              {d.label}
            </button>
          ))}
        </div>
        <label className="mb-1 block text-xs font-medium text-ink-muted">Horários (separados por vírgula)</label>
        <input value={times} onChange={(e) => setTimes(e.target.value)} placeholder="09:00, 12:00, 18:00"
          className="mb-3 w-full rounded-xl border border-border bg-surface px-3.5 py-2.5 text-sm" />
        <label className="mb-1 block text-xs font-medium text-ink-muted">Intervalo mínimo entre posts (min)</label>
        <input type="number" value={minGap} onChange={(e) => setMinGap(e.target.value)}
          className="w-full rounded-xl border border-border bg-surface px-3.5 py-2.5 text-sm" />
      </Card>

      <div className="flex justify-end">
        <Button onClick={save} disabled={updateSettings.isPending}>
          {updateSettings.isPending ? 'Salvando…' : 'Salvar configurações'}
        </Button>
      </div>
    </div>
  )
}
```

- [ ] **Step 3: Add tabs to Projects/Show.jsx**

Mirror `Clients/Show.jsx`. Add the import, the maps, URL-driven tab state, and wrap the existing body. Concretely:

```jsx
// app/frontend/pages/Projects/Show.jsx
// (1) imports
import { Tabs, TabsList, TabsTrigger, TabsContent } from '@/components/ui/tabs'
import { FolderKanban, Settings } from 'lucide-react'
import ProjectSettingsTab from '@/components/project/ProjectSettingsTab'

// (2) near the top, module-level:
const TAB_TO_SEG = { tickets: '', config: 'configuracoes' }
const SEG_TO_TAB = { configuracoes: 'config' }

// (3) inside the component, replace `const { id } = useParams()` with:
const { id, tab: seg } = useParams()
const navigate = useNavigate() // already imported? if not, add to react-router-dom import
const tab = SEG_TO_TAB[seg] || 'tickets'
const setTab = (value) => {
  const s = TAB_TO_SEG[value] || ''
  navigate(`/campanhas/${id}${s ? `/${s}` : ''}`, { replace: true })
}

// (4) Wrap the existing tickets/body region (everything below the hero Card) in:
<Tabs value={tab} onValueChange={setTab}>
  <TabsList className="mb-5">
    <TabsTrigger value="tickets"><FolderKanban size={15} /> Tickets</TabsTrigger>
    <TabsTrigger value="config"><Settings size={15} /> Configurações</TabsTrigger>
  </TabsList>
  <TabsContent value="tickets" className="animate-rise">
    {/* ...existing autopilot progress + pending-plan banner + tickets list... */}
  </TabsContent>
  <TabsContent value="config" className="animate-rise">
    <ProjectSettingsTab project={project} />
  </TabsContent>
</Tabs>
```

- [ ] **Step 4: Verify in the app**

Run: `bin/dev` (or the running dev server). Navigate to a campaign → **Configurações** tab, toggle "Exigir aprovação", change the window, Save. Expected: success toast; reload keeps the values.

- [ ] **Step 5: Commit**

```bash
git add app/frontend/api/index.js app/frontend/hooks/useData.js app/frontend/App.jsx app/frontend/pages/Projects/Show.jsx app/frontend/components/project/ProjectSettingsTab.jsx
git commit -m "feat(projects): Configurações tab for approval/publish/posting-window settings"
```

---

# PHASE B — Approval backend & autopilot GO→production

### Task B1: Scheduling::NextSlot (pure logic)

**Files:**
- Create: `app/services/operations/scheduling/next_slot.rb`
- Test: `spec/services/operations/scheduling/next_slot_spec.rb`

**Interfaces:**
- Consumes: `project.setting('posting_window')` (A3).
- Produces: `Operations::Scheduling::NextSlot.call(project:, desired_at:) -> Time` (UTC-aware `ActiveSupport::TimeWithZone`).

- [ ] **Step 1: Write the failing tests**

```ruby
# spec/services/operations/scheduling/next_slot_spec.rb
require 'rails_helper'

RSpec.describe Operations::Scheduling::NextSlot do
  let(:ws) { Workspace.create!(name: 'WS') }
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
    acct = SocialAccount.create!(workspace: ws, provider: :instagram)
    Post.create!(workspace: ws, ticket: ticket, social_account: acct, status: :scheduled,
                 scheduled_at: Time.zone.parse('2026-07-06 09:00:00 -03:00'))
    slot = described_class.call(project: project, desired_at: nil)
    # 09:00 is taken (±120min), so it lands on the 18:00 slot
    expect(slot.in_time_zone('America/Sao_Paulo').strftime('%H:%M')).to eq('18:00')
  end
end
```

> If `SocialAccount`/`Post` require extra non-null columns in this repo, set them (grep an existing factory/spec). Keep the scheduled_at values as written.

- [ ] **Step 2: Run to verify failure**

Run: `bundle exec rspec spec/services/operations/scheduling/next_slot_spec.rb`
Expected: FAIL — uninitialized constant.

- [ ] **Step 3: Implement**

```ruby
# app/services/operations/scheduling/next_slot.rb
# frozen_string_literal: true

module Operations
  module Scheduling
    # Pure computation: pick a "reasonable" publish moment for a ticket, given the
    # project's posting window and its already-scheduled posts. Keeps the desired
    # date when it is in the future and collision-free; otherwise returns the
    # earliest window slot >= max(now, desired) that respects the min-gap against
    # the project's other scheduled posts. Searches up to HORIZON_DAYS ahead.
    class NextSlot < Operations::Base
      HORIZON_DAYS = 60

      def initialize(project:, desired_at:)
        @project = project
        @desired_at = desired_at
      end

      def call
        return @desired_at if @desired_at.present? && @desired_at.future? && !collides?(@desired_at)

        lower = [Time.current, @desired_at].compact.max
        scan_from(lower) || lower
      end

      private

      def window = @window ||= @project.setting('posting_window') || {}
      def zone   = @zone ||= (ActiveSupport::TimeZone[window['timezone']] || Time.zone)
      def weekdays = Array(window['weekdays']).map(&:to_i)
      def times    = Array(window['times'])
      def gap      = window['min_gap_minutes'].to_i.minutes

      def scan_from(lower)
        start_date = lower.in_time_zone(zone).to_date
        (0..HORIZON_DAYS).each do |offset|
          date = start_date + offset
          next unless weekdays.include?(date.wday)

          times.sort.each do |hhmm|
            h, m = hhmm.split(':').map(&:to_i)
            slot = zone.local(date.year, date.month, date.day, h, m)
            next if slot < lower
            next if collides?(slot)

            return slot
          end
        end
        nil
      end

      # A candidate collides if any of the project's scheduled posts sits within
      # `gap` of it.
      def collides?(candidate)
        return false if gap.zero?

        scheduled_times.any? { |t| (t - candidate).abs < gap }
      end

      def scheduled_times
        @scheduled_times ||= Post
                             .where(ticket_id: @project.tickets.select(:id))
                             .status_scheduled
                             .where.not(scheduled_at: nil)
                             .pluck(:scheduled_at)
      end
    end
  end
end
```

- [ ] **Step 4: Run**

Run: `bundle exec rspec spec/services/operations/scheduling/next_slot_spec.rb`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add app/services/operations/scheduling/next_slot.rb spec/services/operations/scheduling/next_slot_spec.rb
git commit -m "feat(scheduling): NextSlot — keep planned date, else next collision-free window slot"
```

---

### Task B2: ApprovalMailer + RequestApproval

**Files:**
- Create: `app/mailers/approval_mailer.rb`, `app/views/approval_mailer/request.html.erb`, `app/views/approval_mailer/request.text.erb`, `app/services/operations/approvals/request_approval.rb`
- Test: `spec/services/operations/approvals/request_approval_spec.rb`, `spec/mailers/approval_mailer_spec.rb`

**Interfaces:**
- Consumes: `Ticket#approval_token!` (A2), `Operations::Notes::Create`.
- Produces: `Operations::Approvals::RequestApproval.call(ticket:, sent_by:)`; `ApprovalMailer.request(ticket:, recipients:)`.

- [ ] **Step 1: Write the failing tests**

```ruby
# spec/services/operations/approvals/request_approval_spec.rb
require 'rails_helper'

RSpec.describe Operations::Approvals::RequestApproval do
  let(:ws) { Workspace.create!(name: 'Agência X') }
  let(:client) { Client.create!(workspace: ws, name: 'Cliente', email: 'cliente@ex.co') }
  let(:project) { Project.create!(workspace: ws, client: client, name: 'P', status: :active) }
  let(:ticket) { Ticket.create!(workspace: ws, project: project, status: :production) }
  let(:user) { User.create!(email: 'm@ag.co', password: 'password123', name: 'M') }

  it 'mints a token, stamps requested_at, emails the client, and writes a note' do
    Current.workspace = ws
    expect { described_class.call(ticket: ticket, sent_by: user) }
      .to change { ActionMailer::Base.deliveries.size }.by(1)
      .and change { ticket.reload.approval_token.present? }.from(false).to(true)
      .and change { ticket.notes.count }.by(1)

    expect(ticket.approval_requested_at).to be_present
    mail = ActionMailer::Base.deliveries.last
    expect(mail.to).to eq(['cliente@ex.co'])
    expect(mail.body.encoded).to include("/aprovar/#{ticket.approval_token}")
  end
end
```

- [ ] **Step 2: Run to verify failure**

Run: `bundle exec rspec spec/services/operations/approvals/request_approval_spec.rb`
Expected: FAIL — uninitialized constant `Operations::Approvals::RequestApproval`.

- [ ] **Step 3: Implement mailer, views, service**

```ruby
# app/mailers/approval_mailer.rb
# frozen_string_literal: true

# Client-facing content approval — the agency asking its client to review the
# ticket's creatives via a login-less link. Agency-branded (@brand_workspace).
class ApprovalMailer < ApplicationMailer
  def request(ticket:, recipients:)
    @ticket = ticket
    @client = ticket.project.client
    @project = ticket.project
    @brand_workspace = ticket.workspace
    @url = app_url("/aprovar/#{ticket.approval_token!}")
    mail(to: recipients, subject: "Aprove o conteúdo — #{@project.name}")
  end
end
```

```erb
<%# app/views/approval_mailer/request.html.erb %>
<% content_for :preheader do %>Revise e aprove os criativos de <%= @project.name %>.<% end %>
<% content_for :eyebrow do %>Aprovação<% end %>

<h1 style="margin:0 0 16px;font-family:'Sora','Inter',Helvetica,Arial,sans-serif;font-size:22px;font-weight:800;letter-spacing:-0.02em;color:#18122B;">
  Conteúdo pronto para sua aprovação
</h1>

<p style="margin:0 0 16px;font-size:15px;line-height:1.6;color:#564F6F;">
  Olá<%= @client&.name.present? ? ", #{@client.name}" : "" %>. Preparamos o conteúdo de
  <strong><%= @project.name %></strong> e gostaríamos da sua aprovação. É rápido: revise cada
  criativo e aprove — ou peça ajustes.
</p>

<%= email_button('Revisar e aprovar', @url) %>

<p style="margin:16px 0 0;font-size:13px;line-height:1.5;color:#8B86A3;">
  Assim que tudo estiver aprovado, agendamos a publicação automaticamente.
</p>
```

```erb
<%# app/views/approval_mailer/request.text.erb %>
Olá<%= @client&.name.present? ? ", #{@client.name}" : "" %>!

O conteúdo de <%= @project.name %> está pronto para sua aprovação.
Revise e aprove (ou peça ajustes) aqui:

<%= @url %>

Assim que tudo estiver aprovado, agendamos a publicação automaticamente.
```

```ruby
# app/services/operations/approvals/request_approval.rb
# frozen_string_literal: true

module Operations
  module Approvals
    # Sends (or resends) the client the ticket's approval link and records it.
    # Called by autopilot completion and by the "Reenviar link" action.
    class RequestApproval < Operations::Base
      def initialize(ticket:, sent_by: nil)
        @ticket = ticket
        @sent_by = sent_by
      end

      def call
        @ticket.approval_token! # ensure a token exists (idempotent)
        @ticket.update!(approval_requested_at: Time.current)

        recipients = self.class.recipients_for(@ticket)
        ApprovalMailer.request(ticket: @ticket, recipients: recipients).deliver_later if recipients.any?

        Operations::Notes::Create.call(
          ticket: @ticket, user: @sent_by, kind: :system,
          body: 'Link de aprovação enviado ao cliente.'
        )
        @ticket
      end

      # The client's registered email (recipients are not a project setting).
      def self.recipients_for(ticket)
        Array(ticket.project.client&.email).map(&:to_s).compact_blank.uniq
      end
    end
  end
end
```

- [ ] **Step 4: Run**

Run: `bundle exec rspec spec/services/operations/approvals/request_approval_spec.rb`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add app/mailers/approval_mailer.rb app/views/approval_mailer app/services/operations/approvals/request_approval.rb spec/services/operations/approvals/request_approval_spec.rb
git commit -m "feat(approvals): RequestApproval + agency-branded ApprovalMailer"
```

---

### Task B3: DecideCreative → OnFullyApproved → ScheduleApproved

**Files:**
- Create: `app/services/operations/approvals/decide_creative.rb`, `on_fully_approved.rb`, `schedule_approved.rb`
- Test: `spec/services/operations/approvals/decide_creative_spec.rb`

**Interfaces:**
- Consumes: `Ticket#fully_approved?` (A2), `Scheduling::NextSlot` (B1), `Operations::Tickets::ChangeStatus`, `Operations::Tickets::Publish`, `project.setting('auto_publish_after_approval')`.
- Produces: `Operations::Approvals::DecideCreative.call(creative:, decision:, actor:, feedback: nil)`, `OnFullyApproved.call(ticket:)`, `ScheduleApproved.call(ticket:, user: nil)`.

- [ ] **Step 1: Write the failing tests**

```ruby
# spec/services/operations/approvals/decide_creative_spec.rb
require 'rails_helper'

RSpec.describe Operations::Approvals::DecideCreative do
  let(:ws) { Workspace.create!(name: 'WS') }
  let(:client) { Client.create!(workspace: ws, name: 'C', email: 'c@c.co') }
  let(:project) do
    Project.create!(workspace: ws, client: client, name: 'P', status: :active,
                    settings: { 'auto_publish_after_approval' => true,
                                'posting_window' => { 'weekdays' => [0,1,2,3,4,5,6], 'times' => ['09:00'], 'min_gap_minutes' => 0, 'timezone' => 'America/Sao_Paulo' } })
  end
  let(:ticket) { Ticket.create!(workspace: ws, project: project, status: :production, channels: ['instagram']) }
  let!(:creative) { Creative.create!(workspace: ws, ticket: ticket, creative_type: 'carousel', status: :ready) }

  before { Current.workspace = ws }

  it 'marks changes_requested without advancing' do
    described_class.call(creative: creative, decision: 'changes_requested', actor: client, feedback: 'trocar cor')
    expect(creative.reload.approval_changes_requested?).to be(true)
    expect(creative.client_feedback).to eq('trocar cor')
    expect(ticket.reload.status).to eq('production')
  end

  it 'approves and, when fully approved + auto-publish, schedules the ticket' do
    allow(Operations::Tickets::Publish).to receive(:call).and_return({ posts: [1], skipped: [] })
    described_class.call(creative: creative, decision: 'approved', actor: client)

    expect(creative.reload.approval_approved?).to be(true)
    expect(creative.reviewed_by).to eq(client)
    expect(ticket.reload.status).to eq('scheduled')
    expect(Operations::Tickets::Publish).to have_received(:call).with(hash_including(mode: 'scheduled'))
  end
end
```

- [ ] **Step 2: Run to verify failure**

Run: `bundle exec rspec spec/services/operations/approvals/decide_creative_spec.rb`
Expected: FAIL — uninitialized constant.

- [ ] **Step 3: Implement the three services**

```ruby
# app/services/operations/approvals/decide_creative.rb
# frozen_string_literal: true

module Operations
  module Approvals
    # Records one creative's approval decision (from the client link or an
    # internal actor), then re-evaluates whether the ticket is fully approved.
    class DecideCreative < Operations::Base
      DECISIONS = %w[approved changes_requested].freeze

      def initialize(creative:, decision:, actor:, feedback: nil)
        @creative = creative
        @decision = decision.to_s
        @actor = actor
        @feedback = feedback
      end

      def call
        raise Operations::Errors::Invalid, 'Decisão inválida.' unless DECISIONS.include?(@decision)

        @creative.update!(
          approval_state: @decision, reviewed_by: @actor, decided_at: Time.current,
          client_feedback: (@decision == 'changes_requested' ? @feedback.to_s.presence : nil)
        )

        ticket = @creative.ticket
        Broadcaster.ticket(ticket, 'approval_updated', creative_id: @creative.id, decision: @decision)

        if @decision == 'changes_requested'
          notify_changes(ticket)
        elsif ticket.reload.fully_approved?
          OnFullyApproved.call(ticket: ticket)
        end
        @creative
      end

      private

      def notify_changes(ticket)
        actor_name = @actor.respond_to?(:name) ? @actor.name : 'Cliente'
        Operations::Notes::Create.call(
          ticket: ticket, user: nil, kind: :system,
          body: "#{actor_name} pediu ajustes em um criativo: #{@feedback.to_s.truncate(200)}"
        )
      end
    end
  end
end
```

```ruby
# app/services/operations/approvals/on_fully_approved.rb
# frozen_string_literal: true

module Operations
  module Approvals
    # Reached when every approvable creative on a ticket is approved. Records the
    # "Aprovado por <actor>" note; if the project auto-publishes, schedules it.
    class OnFullyApproved < Operations::Base
      def initialize(ticket:)
        @ticket = ticket
      end

      def call
        actor = @ticket.approval_actor
        actor_name = actor.respond_to?(:name) ? actor.name : 'Cliente'
        Operations::Notes::Create.call(
          ticket: @ticket, user: nil, kind: :system,
          body: "Conteúdo aprovado por #{actor_name}."
        )
        Broadcaster.ticket(@ticket, 'approval_completed', actor: actor_name)

        ScheduleApproved.call(ticket: @ticket) if @ticket.project.setting('auto_publish_after_approval')
        @ticket
      end
    end
  end
end
```

```ruby
# app/services/operations/approvals/schedule_approved.rb
# frozen_string_literal: true

module Operations
  module Approvals
    # Auto-schedule an approved ticket: compute a reasonable slot, move the ticket
    # production→scheduled (authoritative), then reuse Tickets::Publish to create
    # the scheduled posts. Mirrors the retired autopilot PublishStep.
    class ScheduleApproved < Operations::Base
      def initialize(ticket:, user: nil)
        @ticket = ticket
        @user = user
      end

      def call
        return unless @ticket.production?

        slot = Operations::Scheduling::NextSlot.call(project: @ticket.project, desired_at: @ticket.scheduled_at)
        Operations::Tickets::ChangeStatus.call(@ticket, 'scheduled', user: @user, force: true)
        @ticket.reload

        Operations::Tickets::Publish.call(
          ticket: @ticket, user: @user,
          creative_ids: @ticket.approvable_creatives.map { |c| c.id.to_s },
          mode: 'scheduled', scheduled_at: slot
        )
        @ticket
      end
    end
  end
end
```

- [ ] **Step 4: Run**

Run: `bundle exec rspec spec/services/operations/approvals/decide_creative_spec.rb`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add app/services/operations/approvals/decide_creative.rb app/services/operations/approvals/on_fully_approved.rb app/services/operations/approvals/schedule_approved.rb spec/services/operations/approvals/decide_creative_spec.rb
git commit -m "feat(approvals): per-creative decisions drive full-approval scheduling"
```

---

### Task B4: ApproveAll (internal "Aprovar" action)

**Files:**
- Create: `app/services/operations/approvals/approve_all.rb`
- Test: `spec/services/operations/approvals/approve_all_spec.rb`

**Interfaces:**
- Consumes: `Ticket#approvable_creatives`, `DecideCreative` (B3), `OnFullyApproved`.
- Produces: `Operations::Approvals::ApproveAll.call(ticket:, actor:)`.

- [ ] **Step 1: Write the failing test**

```ruby
# spec/services/operations/approvals/approve_all_spec.rb
require 'rails_helper'

RSpec.describe Operations::Approvals::ApproveAll do
  let(:ws) { Workspace.create!(name: 'WS') }
  let(:client) { Client.create!(workspace: ws, name: 'C', email: 'c@c.co') }
  let(:project) { Project.create!(workspace: ws, client: client, name: 'P', status: :active, settings: { 'auto_publish_after_approval' => false }) }
  let(:ticket) { Ticket.create!(workspace: ws, project: project, status: :production, channels: ['instagram']) }
  let(:user) { User.create!(email: 'm@a.co', password: 'password123', name: 'Manager') }
  let!(:c1) { Creative.create!(workspace: ws, ticket: ticket, creative_type: 'carousel', status: :ready) }
  let!(:c2) { Creative.create!(workspace: ws, ticket: ticket, creative_type: 'image', status: :ready) }

  before { Current.workspace = ws }

  it 'approves every approvable creative with the internal actor' do
    described_class.call(ticket: ticket, actor: user)
    expect([c1, c2].map { |c| c.reload.approval_state }).to eq(%w[approved approved])
    expect(ticket.reload.fully_approved?).to be(true)
    expect(ticket.approval_actor).to eq(user)
  end
end
```

- [ ] **Step 2: Run to verify failure**

Run: `bundle exec rspec spec/services/operations/approvals/approve_all_spec.rb`
Expected: FAIL — uninitialized constant.

- [ ] **Step 3: Implement**

```ruby
# app/services/operations/approvals/approve_all.rb
# frozen_string_literal: true

module Operations
  module Approvals
    # The internal "Aprovar" action — a team member approves the whole approvable
    # set on the client's behalf, then the full-approval hook runs once.
    class ApproveAll < Operations::Base
      def initialize(ticket:, actor:)
        @ticket = ticket
        @actor = actor
      end

      def call
        set = @ticket.approvable_creatives
        raise Operations::Errors::Invalid, 'Não há criativos prontos para aprovar.' if set.empty?

        set.each do |creative|
          creative.update!(approval_state: 'approved', reviewed_by: @actor, decided_at: Time.current, client_feedback: nil)
        end
        OnFullyApproved.call(ticket: @ticket.reload)
        @ticket
      end
    end
  end
end
```

- [ ] **Step 4: Run**

Run: `bundle exec rspec spec/services/operations/approvals/approve_all_spec.rb`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add app/services/operations/approvals/approve_all.rb spec/services/operations/approvals/approve_all_spec.rb
git commit -m "feat(approvals): ApproveAll internal action approves the whole set"
```

---

### Task B5: Autopilot stops at production

**Files:**
- Create: `app/services/operations/autopilot/complete.rb`, `db/migrate/20260706100300_narrow_autopilot_active_index.rb`
- Modify: `app/models/autopilot_run.rb`, `app/services/operations/autopilot/{advance,kick_generations,on_generation_settled,start}.rb`
- Delete: `app/services/operations/autopilot/publish_step.rb`
- Test: `spec/services/operations/autopilot/complete_spec.rb`, update `spec/services/operations/autopilot/*` if present

**Interfaces:**
- Consumes: `RequestApproval` (B2), `project.setting('require_client_approval')`.
- Produces: `Operations::Autopilot::Complete.call(run:)` — finishes a ticket-run at `production` (relocates PublishStep#finish's side effects) and requests approval when required.

- [ ] **Step 1: Write the failing test**

```ruby
# spec/services/operations/autopilot/complete_spec.rb
require 'rails_helper'

RSpec.describe Operations::Autopilot::Complete do
  let(:ws) { Workspace.create!(name: 'WS') }
  let(:client) { Client.create!(workspace: ws, name: 'C', email: 'c@c.co') }
  let(:project) { Project.create!(workspace: ws, client: client, name: 'P', status: :active, settings: { 'require_client_approval' => true }) }
  let(:ticket) { Ticket.create!(workspace: ws, project: project, status: :production) }
  let(:user) { User.create!(email: 'u@a.co', password: 'password123', name: 'U') }
  let(:run) { AutopilotRun.create!(workspace: ws, ticket: ticket, user: user, scope: 'ticket', state: 'generating', progress: { 'generation_ids' => [], 'creative_ids' => [] }) }

  before { Current.workspace = ws }

  it 'completes the run at production and requests approval' do
    expect(Operations::Approvals::RequestApproval).to receive(:call).with(hash_including(ticket: ticket))
    Operations::Autopilot::Complete.call(run: run)
    expect(run.reload.state).to eq('completed')
    expect(run.finished_at).to be_present
    expect(ticket.reload.status).to eq('production')
  end
end
```

- [ ] **Step 2: Run to verify failure**

Run: `bundle exec rspec spec/services/operations/autopilot/complete_spec.rb`
Expected: FAIL — uninitialized constant `Operations::Autopilot::Complete`.

- [ ] **Step 3: Implement Complete, repoint state writes, drop `publishing`, fix index**

```ruby
# app/services/operations/autopilot/complete.rb
# frozen_string_literal: true

module Operations
  module Autopilot
    # Terminal step for a ticket-run under the new lifecycle: GO stops at
    # `production` with creatives ready. Relocates the old PublishStep#finish
    # side-effects (spent credits, broadcasts, owner push, batch recompute) and
    # requests client approval when the project requires it.
    class Complete < Operations::Base
      def initialize(run:)
        @run = run
        @ticket = run.ticket
      end

      def call
        return unless claim!

        @run.update!(
          state: 'completed', finished_at: Time.current, spent_credits: computed_spent
        )
        Broadcaster.ticket(@ticket, 'autopilot_completed', run_id: @run.id, posts: 0)
        Broadcaster.board(@run.workspace_id, 'autopilot_completed', ticket_id: @ticket.id, run_id: @run.id)
        notify_owner
        request_approval_if_needed
        Operations::Autopilot::RecomputeBatch.call(batch_id: @run.batch_id) if @run.batch_id
        @run
      end

      private

      # Claim out of the last active phase exactly once (both the sync and async
      # generation paths call Complete).
      def claim!
        @run.with_lock do
          next false if @run.terminal? || @run.progress['completed_claimed']

          @run.update!(progress: @run.progress.merge('completed_claimed' => true))
          true
        end
      end

      def request_approval_if_needed
        return unless @ticket.project.setting('require_client_approval')

        Operations::Approvals::RequestApproval.call(ticket: @ticket, sent_by: @run.user)
      rescue StandardError => e
        Rails.logger.warn("[Autopilot::Complete] approval request failed: #{e.message}")
      end

      def computed_spent
        @run.workspace.credit_transactions.debits
            .where(generation_id: @run.generation_ids).sum(:amount).abs
      end

      def notify_owner
        return if @run.user.nil?

        Operations::Push::Notify.call(
          user: @run.user,
          title: 'Campanha no piloto automático ✅',
          body: "#{@ticket.display_title}: criativos gerados e prontos para aprovação.",
          path: "/tickets/#{@ticket.id}"
        )
      rescue StandardError => e
        Rails.logger.warn("[Autopilot::Complete] notify failed: #{e.message}")
      end
    end
  end
end
```

```ruby
# app/services/operations/autopilot/kick_generations.rb
# Replace the state write (line ~28-33) and the branch (line ~37-41):

        @run.update!(
          state: pending ? 'awaiting_generation' : 'completed',
          progress: @run.progress.merge(
            'generation_ids' => ids, 'creative_ids' => creative_ids, 'total_creatives' => ids.size
          )
        )
        Broadcaster.ticket(@ticket, 'autopilot_progress',
                           run_id: @run.id, state: @run.state, total: ids.size)

        if pending
          AutopilotWatchdogJob.set(wait: AutopilotWatchdogJob::TIMEOUT).perform_later(@run.id)
        else
          Operations::Autopilot::Complete.call(run: @run)
        end
```

```ruby
# app/services/operations/autopilot/on_generation_settled.rb
# In `self.reconcile`, replace the `elsif pending.empty?` branch body:

          elsif pending.empty?
            run.update!(state: 'completing')
            action = :complete
          end
        end

        case action
        when :complete then Operations::Autopilot::Complete.call(run: run)
        when :fail     then Operations::Autopilot::Fail.call(run: run, reason: 'Uma geração de criativo falhou.')
        end
        run
```

> Note: introduce a transient `completing` state only if you prefer an explicit marker; simpler is to call `Complete` directly while still in `awaiting_generation` (Complete's `claim!` guards against double-run). To keep `ACTIVE_STATES` unchanged, call `Complete` directly and drop the `run.update!(state: 'completing')` line — Complete will move it to `completed`. Use the direct form:

```ruby
          elsif pending.empty?
            action = :complete
          end
        end

        case action
        when :complete then Operations::Autopilot::Complete.call(run: run)
        when :fail     then Operations::Autopilot::Fail.call(run: run, reason: 'Uma geração de criativo falhou.')
        end
        run
```

```ruby
# app/services/operations/autopilot/advance.rb — remove the publishing branch (line 25):
        case @run.state
        when 'pending'             then WalkToProduction.call(run: @run)
        when 'generating'          then KickGenerations.call(run: @run)
        when 'awaiting_generation' then OnGenerationSettled.reconcile(run: @run)
        end
```

```ruby
# app/models/autopilot_run.rb — drop 'publishing' from ACTIVE_STATES (line 26):
  ACTIVE_STATES   = %w[pending scoping generating awaiting_generation].freeze
```

Update the model's top doc comment (lines 3-5) to say the run walks to `production` (not `scheduled`). Also change the default `target_status` for new runs — in `start.rb` `create_run` add `target_status: 'production'` (cosmetic; nothing reads it, but keep it truthful):

```ruby
# app/services/operations/autopilot/start.rb — inside create_run's AutopilotRun.create!(...)
          scope: 'ticket', state: 'pending', target_status: 'production',
```

```ruby
# db/migrate/20260706100300_narrow_autopilot_active_index.rb
# frozen_string_literal: true

# 'publishing' is no longer an active ticket-run state (GO stops at production),
# so the one-active-per-ticket partial index must drop it to stay in sync.
class NarrowAutopilotActiveIndex < ActiveRecord::Migration[8.1]
  def up
    remove_index :autopilot_runs, name: 'index_autopilot_runs_one_active_per_ticket'
    add_index :autopilot_runs, :ticket_id, unique: true,
              where: "scope = 'ticket' AND state IN ('pending','scoping','generating','awaiting_generation')",
              name: 'index_autopilot_runs_one_active_per_ticket'
  end

  def down
    remove_index :autopilot_runs, name: 'index_autopilot_runs_one_active_per_ticket'
    add_index :autopilot_runs, :ticket_id, unique: true,
              where: "scope = 'ticket' AND state IN ('pending','scoping','generating','awaiting_generation','publishing')",
              name: 'index_autopilot_runs_one_active_per_ticket'
  end
end
```

```bash
# Delete the retired phase.
git rm app/services/operations/autopilot/publish_step.rb
```

> If `spec/services/operations/autopilot/publish_step_spec.rb` exists, `git rm` it too. If any autopilot integration spec asserts a run ends at `scheduled`, update it to assert `production` + `completed`.

- [ ] **Step 4: Migrate and run**

Run: `bin/rails db:migrate && bundle exec rspec spec/services/operations/autopilot/complete_spec.rb spec/services/operations/autopilot`
Expected: PASS (fix any existing autopilot spec that assumed `scheduled`).

- [ ] **Step 5: Commit**

```bash
git add -A app/services/operations/autopilot app/models/autopilot_run.rb db/migrate/20260706100300_narrow_autopilot_active_index.rb db/schema.rb spec/services/operations/autopilot
git commit -m "feat(autopilot): GO stops at production; Complete relocates finish + requests approval"
```

---

# PHASE C — Public approval page, emails wiring, shared experience

### Task C1: Public approval API

**Files:**
- Create: `app/controllers/api/v1/public/approvals_controller.rb`, `app/services/controllers/public/approvals/{show,approve_creative,request_changes}.rb`
- Modify: `config/routes.rb`
- Test: `spec/requests/api/v1/public/approvals_spec.rb`

**Interfaces:**
- Consumes: `Ticket#approval_token`, `DecideCreative` (B3), `CreativeSerializer` (extended in D-phase, but approval fields added here-first is fine).
- Produces: `GET /api/v1/public/approvals/:token`, `POST …/:token/creatives/:creative_id/approve`, `POST …/:token/creatives/:creative_id/request_changes`.

- [ ] **Step 1: Write the failing tests**

```ruby
# spec/requests/api/v1/public/approvals_spec.rb
require 'rails_helper'

RSpec.describe 'Public approvals', type: :request do
  let(:ws) { Workspace.create!(name: 'Agência') }
  let(:client) { Client.create!(workspace: ws, name: 'Cliente', email: 'c@c.co') }
  let(:project) { Project.create!(workspace: ws, client: client, name: 'P', status: :active, settings: { 'auto_publish_after_approval' => false }) }
  let(:ticket) { Ticket.create!(workspace: ws, project: project, status: :production, channels: ['instagram']) }
  let!(:creative) { Creative.create!(workspace: ws, ticket: ticket, creative_type: 'carousel', status: :ready) }
  let(:token) { ticket.approval_token! }

  it 'loads the approval bundle without auth' do
    get "/api/v1/public/approvals/#{token}"
    expect(response).to have_http_status(:ok)
    body = JSON.parse(response.body)
    expect(body['branding']['name']).to eq('Agência')
    expect(body['creatives'].first['id']).to eq(creative.id)
  end

  it 'records a per-creative approval' do
    post "/api/v1/public/approvals/#{token}/creatives/#{creative.id}/approve", as: :json
    expect(response).to have_http_status(:ok)
    expect(creative.reload.approval_approved?).to be(true)
    expect(creative.reviewed_by).to eq(client)
  end

  it '404s on a bad token' do
    get '/api/v1/public/approvals/nope'
    expect(response).to have_http_status(:not_found)
  end
end
```

- [ ] **Step 2: Run to verify failure**

Run: `bundle exec rspec spec/requests/api/v1/public/approvals_spec.rb`
Expected: FAIL — no route.

- [ ] **Step 3: Implement controller, services, routes**

```ruby
# app/controllers/api/v1/public/approvals_controller.rb
# frozen_string_literal: true

module Api
  module V1
    module Public
      # Login-less client approval endpoints. The path token IS the credential;
      # we resolve the ticket + workspace from it and set Current.workspace so the
      # serializers work. No session auth, no billing gate. CSRF still applies to
      # mutations (the SPA meta token satisfies it, as with password_resets).
      class ApprovalsController < BaseController
        allow_unauthenticated_access
        skip_billing_gate
        before_action :resolve_ticket!

        def show           = render_ok(Controllers::Public::Approvals::Show.call(ticket: @ticket))
        def approve        = render_ok(Controllers::Public::Approvals::ApproveCreative.call(ticket: @ticket, params:))
        def request_changes = render_ok(Controllers::Public::Approvals::RequestChanges.call(ticket: @ticket, params:))

        private

        def resolve_ticket!
          @ticket = Ticket.find_by(approval_token: params[:token].to_s)
          raise ActiveRecord::RecordNotFound, 'Link inválido ou expirado.' unless @ticket

          Current.workspace = @ticket.workspace
        end
      end
    end
  end
end
```

```ruby
# app/services/controllers/public/approvals/show.rb
# frozen_string_literal: true

module Controllers
  module Public
    module Approvals
      class Show < Controllers::Base
        def initialize(ticket:)
          @ticket = ticket
        end

        def call
          {
            branding: branding,
            campaign: @ticket.project.name,
            title: @ticket.display_title,
            approved: @ticket.fully_approved?,
            creatives: serialize_collection(@ticket.approvable_creatives, CreativeSerializer),
            plan: { networks: @ticket.channels, planned_at: @ticket.scheduled_at&.iso8601 }
          }
        end

        private

        def branding
          ws = @ticket.workspace
          { name: ws.name, primary_color: ws.brand_primary_color, logo_url: logo_url(ws) }
        end

        def logo_url(ws)
          return nil unless ws.logo.attached?

          Rails.application.routes.url_helpers.rails_blob_url(ws.logo, host: SystemConfig.app_host)
        rescue StandardError
          nil
        end
      end
    end
  end
end
```

```ruby
# app/services/controllers/public/approvals/approve_creative.rb
# frozen_string_literal: true

module Controllers
  module Public
    module Approvals
      class ApproveCreative < Controllers::Base
        def initialize(ticket:, params:)
          @ticket = ticket
          @params = params
        end

        def call
          creative = @ticket.creatives.find(@params[:creative_id])
          Operations::Approvals::DecideCreative.call(
            creative: creative, decision: 'approved', actor: @ticket.project.client
          )
          { ok: true, approved: @ticket.reload.fully_approved? }
        end
      end
    end
  end
end
```

```ruby
# app/services/controllers/public/approvals/request_changes.rb
# frozen_string_literal: true

module Controllers
  module Public
    module Approvals
      class RequestChanges < Controllers::Base
        def initialize(ticket:, params:)
          @ticket = ticket
          @params = params
        end

        def call
          creative = @ticket.creatives.find(@params[:creative_id])
          Operations::Approvals::DecideCreative.call(
            creative: creative, decision: 'changes_requested',
            actor: @ticket.project.client, feedback: @params[:feedback]
          )
          { ok: true }
        end
      end
    end
  end
end
```

```ruby
# config/routes.rb — inside `namespace :api do namespace :v1 do ... end end`, add:
      namespace :public do
        get   'approvals/:token', to: 'approvals#show'
        post  'approvals/:token/creatives/:creative_id/approve', to: 'approvals#approve'
        post  'approvals/:token/creatives/:creative_id/request_changes', to: 'approvals#request_changes'
      end
```

Also add the approval fields to `CreativeSerializer` now (needed by `show`):

```ruby
# app/serializers/creative_serializer.rb — add to attributes and add methods
  # add these to the `attributes` list: :approval_state, :client_feedback, :decided_at, :reviewed_by_name
  def decided_at = object.decided_at&.iso8601
  def reviewed_by_name = object.reviewed_by.respond_to?(:name) ? object.reviewed_by&.name : nil
```

- [ ] **Step 4: Run**

Run: `bundle exec rspec spec/requests/api/v1/public/approvals_spec.rb`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add app/controllers/api/v1/public/approvals_controller.rb app/services/controllers/public/approvals config/routes.rb app/serializers/creative_serializer.rb spec/requests/api/v1/public/approvals_spec.rb
git commit -m "feat(approvals): public token-authed approval API + creative approval fields in serializer"
```

---

### Task C2: CreativeExperience shared component

**Files:**
- Create: `app/frontend/components/creative/CreativeExperience.jsx`
- Test: manual (rendered by C3 and Plan 2)

**Interfaces:**
- Produces: `<CreativeExperience creative={...} />` — inline native rendering (carousel swipe / video / image), reusing `MediaViewer` for zoom. Consumes a serialized creative (`asset_urls`, `creative_type`, `caption`, `name`, `preview_url`).

- [ ] **Step 1: Implement the component**

```jsx
// app/frontend/components/creative/CreativeExperience.jsx
import { Suspense, lazy, useState } from 'react'
import { ChevronLeft, ChevronRight, Maximize2 } from 'lucide-react'

const MediaViewer = lazy(() => import('@/components/ticket/MediaViewer'))
const isVideoUrl = (url) => /\.(mp4|mov|webm|avi)(\?|$)/i.test(url || '')

// Convert a creative to MediaViewer attachments (mirrors CreativesPanel).
function toAttachments(creative) {
  const urls = creative?.asset_urls || []
  const isCarousel = creative?.creative_type === 'carousel' || urls.length > 1
  return urls.map((url, i) => ({
    id: `${creative.id}-${i}`,
    url,
    filename: isCarousel ? `slide-${i + 1}` : String(creative.id),
    display_name: creative.name || creative.creative_type,
    kind: isVideoUrl(url) ? 'video' : 'image',
    content_type: isVideoUrl(url) ? 'video/mp4' : 'image/jpeg',
    description: creative.caption || undefined,
  }))
}

// Renders a creative in its native form: a swipeable carousel, an inline video
// player, or an image. Reused by the post-detail page and the client approval
// page. Click opens the MediaViewer lightbox for zoom.
export default function CreativeExperience({ creative }) {
  const [idx, setIdx] = useState(0)
  const [open, setOpen] = useState(false)
  const urls = creative?.asset_urls || []
  const cover = urls[0] || creative?.preview_url

  if (!urls.length && !cover) {
    return <div className="flex aspect-square w-full items-center justify-center rounded-2xl bg-surface-muted text-sm text-ink-muted">Sem prévia</div>
  }

  const current = urls[idx] || cover
  const many = urls.length > 1

  return (
    <div className="relative w-full overflow-hidden rounded-2xl border border-border bg-black/[0.03]">
      <div className="relative flex aspect-square w-full items-center justify-center">
        {isVideoUrl(current) ? (
          <video src={current} controls playsInline className="size-full object-contain" />
        ) : (
          <img src={current} alt={creative.name || ''} className="size-full object-contain" />
        )}

        <button type="button" onClick={() => setOpen(true)}
          className="absolute right-2 top-2 rounded-lg bg-black/50 p-1.5 text-white hover:bg-black/70" aria-label="Ampliar">
          <Maximize2 size={16} />
        </button>

        {many && (
          <>
            <button type="button" onClick={() => setIdx((i) => (i - 1 + urls.length) % urls.length)}
              className="absolute left-2 top-1/2 -translate-y-1/2 rounded-full bg-black/50 p-1.5 text-white" aria-label="Anterior">
              <ChevronLeft size={18} />
            </button>
            <button type="button" onClick={() => setIdx((i) => (i + 1) % urls.length)}
              className="absolute right-2 top-1/2 -translate-y-1/2 rounded-full bg-black/50 p-1.5 text-white" aria-label="Próximo">
              <ChevronRight size={18} />
            </button>
            <div className="absolute bottom-2 left-1/2 -translate-x-1/2 rounded-full bg-black/50 px-2 py-0.5 text-xs text-white">
              {idx + 1} / {urls.length}
            </div>
          </>
        )}
      </div>

      <Suspense fallback={null}>
        <MediaViewer attachments={toAttachments(creative)} index={idx} open={open} onClose={() => setOpen(false)} />
      </Suspense>
    </div>
  )
}
```

- [ ] **Step 2: Sanity check the import graph**

Run: `bin/vite build` (or rely on the dev server hot-reload). Expected: builds without unresolved-import errors. (It renders in C3.)

- [ ] **Step 3: Commit**

```bash
git add app/frontend/components/creative/CreativeExperience.jsx
git commit -m "feat(creative): reusable CreativeExperience (carousel/video/image + lightbox)"
```

---

### Task C3: Public /aprovar/:token React page

**Files:**
- Modify: `app/frontend/App.jsx`, `app/frontend/api/index.js`, `app/frontend/api/queryKeys.js`, `app/frontend/hooks/useData.js`
- Create: `app/frontend/pages/Approval/Show.jsx`
- Test: manual E2E

**Interfaces:**
- Consumes: public approval API (C1), `CreativeExperience` (C2), `useConfirm` (existing).
- Produces: public route `/aprovar/:token`; `approvalsApi.get/approve/requestChanges`; `usePublicApproval(token)`.

- [ ] **Step 1: API + keys + hook**

```js
// app/frontend/api/index.js — add a new exported object
// Public client content approval (login-less; token is the credential).
export const approvalsApi = {
  get: (token) => api.get(`/public/approvals/${token}`),
  approve: (token, creativeId) => api.post(`/public/approvals/${token}/creatives/${creativeId}/approve`),
  requestChanges: (token, creativeId, feedback) =>
    api.post(`/public/approvals/${token}/creatives/${creativeId}/request_changes`, { feedback }),
}
```

```js
// app/frontend/api/queryKeys.js — add to keys
  publicApproval: (token) => ['public', 'approvals', token],
```

```js
// app/frontend/hooks/useData.js — add (import approvalsApi in the top import block)
export const usePublicApproval = (token) =>
  useQuery({ queryKey: keys.publicApproval(token), queryFn: () => approvalsApi.get(token), enabled: !!token })
```

- [ ] **Step 2: Route (public, outside ProtectedRoute)**

```jsx
// app/frontend/App.jsx
// (1) lazy import near the other lazy pages
const ApprovalShow = lazy(() => import('@/pages/Approval/Show'))
// (2) add beside the other public routes (e.g. after the /confirmar-troca-email route)
      <Route path="/aprovar/:token" element={<ApprovalShow />} />
```

- [ ] **Step 3: The approval page**

```jsx
// app/frontend/pages/Approval/Show.jsx
import { useParams } from 'react-router-dom'
import { useState } from 'react'
import { CheckCircle2, MessageSquare, Loader2 } from 'lucide-react'
import { toast } from 'sonner'
import { useQueryClient } from '@tanstack/react-query'
import { usePublicApproval } from '@/hooks/useData'
import { approvalsApi } from '@/api'
import { keys } from '@/api/queryKeys'
import CreativeExperience from '@/components/creative/CreativeExperience'
import { useConfirm } from '@/components/ui/confirm-dialog'
import { Button } from '@/components/ui/button'

export default function ApprovalShow() {
  const { token } = useParams()
  const { data, isLoading, isError } = usePublicApproval(token)
  const qc = useQueryClient()
  const confirm = useConfirm()
  const [busyId, setBusyId] = useState(null)

  if (isLoading) return <div className="flex min-h-screen items-center justify-center"><Loader2 className="animate-spin text-brand" /></div>
  if (isError || !data) return <div className="flex min-h-screen items-center justify-center p-6 text-center text-ink-muted">Link inválido ou expirado.</div>

  const brand = data.branding || {}
  const refresh = () => qc.invalidateQueries({ queryKey: keys.publicApproval(token) })

  const approve = async (c) => {
    const ok = await confirm({ title: 'Aprovar este criativo?', description: 'Confirma que este conteúdo está aprovado para publicação?', confirmLabel: 'Aprovar' })
    if (!ok) return
    setBusyId(c.id)
    try { await approvalsApi.approve(token, c.id); refresh(); toast.success('Criativo aprovado!') }
    catch (e) { toast.error(e?.error || 'Erro ao aprovar.') }
    finally { setBusyId(null) }
  }

  const requestChanges = async (c) => {
    const feedback = window.prompt('O que precisa ser ajustado?')
    if (feedback == null) return
    const ok = await confirm({ title: 'Pedir ajustes?', description: 'Enviaremos seu comentário para a equipe.', confirmLabel: 'Enviar' })
    if (!ok) return
    setBusyId(c.id)
    try { await approvalsApi.requestChanges(token, c.id, feedback); refresh(); toast.success('Ajustes solicitados!') }
    catch (e) { toast.error(e?.error || 'Erro ao enviar.') }
    finally { setBusyId(null) }
  }

  return (
    <div className="min-h-screen bg-surface-muted">
      <header className="px-6 py-5 text-white" style={{ background: brand.primary_color || '#7C3AED' }}>
        <div className="mx-auto flex max-w-3xl items-center gap-3">
          {brand.logo_url ? <img src={brand.logo_url} alt={brand.name} className="size-9 rounded-lg bg-white object-cover" />
            : <div className="flex size-9 items-center justify-center rounded-lg bg-white/20 font-bold">{brand.name?.[0]}</div>}
          <span className="font-display text-lg font-bold">{brand.name}</span>
        </div>
      </header>

      <main className="mx-auto max-w-3xl px-4 py-8">
        <h1 className="mb-1 font-display text-2xl font-bold text-ink">Aprovação de conteúdo</h1>
        <p className="mb-6 text-ink-muted">{data.campaign} · {data.title}</p>

        {data.approved && (
          <div className="mb-6 flex items-center gap-2 rounded-xl bg-emerald/10 px-4 py-3 text-emerald">
            <CheckCircle2 size={18} /> Tudo aprovado! A publicação será agendada automaticamente.
          </div>
        )}

        <div className="flex flex-col gap-8">
          {(data.creatives || []).map((c) => (
            <div key={c.id}>
              <CreativeExperience creative={c} />
              {c.caption && <p className="mt-3 whitespace-pre-wrap text-sm text-ink-secondary">{c.caption}</p>}
              {c.approval_state === 'approved' ? (
                <p className="mt-3 flex items-center gap-1.5 font-medium text-emerald"><CheckCircle2 size={16} /> Aprovado</p>
              ) : (
                <div className="mt-3 flex gap-2">
                  <Button onClick={() => approve(c)} disabled={busyId === c.id}>
                    <CheckCircle2 size={16} /> Aprovar
                  </Button>
                  <Button variant="outline" onClick={() => requestChanges(c)} disabled={busyId === c.id}>
                    <MessageSquare size={16} /> Pedir ajustes
                  </Button>
                </div>
              )}
              {c.approval_state === 'changes_requested' && (
                <p className="mt-2 text-sm text-amber-600">Ajustes solicitados: {c.client_feedback}</p>
              )}
            </div>
          ))}
        </div>
      </main>
    </div>
  )
}
```

- [ ] **Step 4: Verify E2E**

Run: with `bin/dev` up, create a ticket in `production` with a ready creative, then in a Rails console `Ticket.find(<id>).approval_token!`. Visit `/aprovar/<token>` in a private window (logged out). Expected: branded page, creative renders in `CreativeExperience`, "Aprovar" works and flips the card to "Aprovado".

- [ ] **Step 5: Commit**

```bash
git add app/frontend/App.jsx app/frontend/api/index.js app/frontend/api/queryKeys.js app/frontend/hooks/useData.js app/frontend/pages/Approval/Show.jsx
git commit -m "feat(approvals): public /aprovar/:token client approval page"
```

---

# PHASE D — Production step redesign

### Task D1: Remove the approval_status field

**Files:**
- Modify: `app/services/tickets/fields.rb`, `app/frontend/components/ticket/FieldGroup.jsx`
- Test: `spec/services/tickets/fields_spec.rb` (if present) or add one

- [ ] **Step 1: Write/adjust the failing test**

```ruby
# spec/services/tickets/fields_spec.rb
require 'rails_helper'

RSpec.describe Tickets::Fields do
  it 'no longer allows approval_status on production' do
    out = described_class.sanitize('production', { 'caption' => 'x', 'approval_status' => 'approved' })
    expect(out).to have_key('caption')
    expect(out).not_to have_key('approval_status')
  end
end
```

- [ ] **Step 2: Run to verify failure**

Run: `bundle exec rspec spec/services/tickets/fields_spec.rb`
Expected: FAIL — `approval_status` still present.

- [ ] **Step 3: Remove it (backend + frontend schema)**

```ruby
# app/services/tickets/fields.rb — the production line becomes:
      'production' => %w[creative_id caption hashtags production_scope],
```

```jsx
// app/frontend/components/ticket/FieldGroup.jsx
// (1) delete the approval_status field object from SCHEMAS.production.fields (the line with key: 'approval_status')
// (2) update SCHEMAS.production.helper text:
    helper: 'A copy final e as hashtags. A aprovação do cliente vira ações abaixo.',
// (3) delete the now-unused APPROVAL_OPTIONS const (lines ~119-123) and,
//     in the `select` case, since only REPEAT_OPTIONS remains, simplify:
      case 'select': {
        const opts = REPEAT_OPTIONS
        // ...unchanged Select markup...
      }
```

- [ ] **Step 4: Run**

Run: `bundle exec rspec spec/services/tickets/fields_spec.rb`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add app/services/tickets/fields.rb app/frontend/components/ticket/FieldGroup.jsx spec/services/tickets/fields_spec.rb
git commit -m "refactor(tickets): drop approval_status field (replaced by real approval state)"
```

---

### Task D2: Approval panel + internal actions

**Files:**
- Create: `app/frontend/components/ticket/ApprovalPanel.jsx`, `app/services/controllers/approvals/{request_approval,approve}.rb`
- Modify: `app/controllers/api/v1/tickets_controller.rb`, `config/routes.rb`, `app/frontend/components/ticket/TicketBody.jsx`, `app/frontend/api/index.js`, `app/frontend/hooks/useData.js`, `app/serializers/ticket_serializer.rb`
- Test: `spec/requests/api/v1/ticket_approval_actions_spec.rb`

**Interfaces:**
- Consumes: `RequestApproval` (B2), `ApproveAll` (B4).
- Produces: `POST /api/v1/tickets/:id/request_approval`, `POST /api/v1/tickets/:id/approve`; `TicketSerializer` approval summary (`approval_requested_at`, `approval` block); `ApprovalPanel` in the production view.

- [ ] **Step 1: Write the failing test**

```ruby
# spec/requests/api/v1/ticket_approval_actions_spec.rb
require 'rails_helper'

RSpec.describe 'Ticket approval actions', type: :request do
  it 'resends the link and approves internally' do
    sign_in_as_manager
    client = Client.create!(workspace: current_workspace, name: 'C', email: 'c@c.co')
    project = Project.create!(workspace: current_workspace, client: client, name: 'P', status: :active, settings: { 'auto_publish_after_approval' => false })
    ticket = Ticket.create!(workspace: current_workspace, project: project, status: :production, channels: ['instagram'])
    Creative.create!(workspace: current_workspace, ticket: ticket, creative_type: 'carousel', status: :ready)

    expect { post "/api/v1/tickets/#{ticket.id}/request_approval", as: :json }
      .to change { ActionMailer::Base.deliveries.size }.by(1)
    expect(response).to have_http_status(:ok)

    post "/api/v1/tickets/#{ticket.id}/approve", as: :json
    expect(response).to have_http_status(:ok)
    expect(ticket.reload.fully_approved?).to be(true)
  end
end
```

- [ ] **Step 2: Run to verify failure**

Run: `bundle exec rspec spec/requests/api/v1/ticket_approval_actions_spec.rb`
Expected: FAIL — no route.

- [ ] **Step 3: Controller services, routes, serializer, panel, wiring**

```ruby
# app/services/controllers/approvals/request_approval.rb
# frozen_string_literal: true

module Controllers
  module Approvals
    class RequestApproval < Base
      def initialize(params:)
        @params = params
      end

      def call
        deny_guests!
        ticket = workspace.tickets.find(@params[:id])
        Operations::Approvals::RequestApproval.call(ticket: ticket, sent_by: user)
        { ok: true }
      end
    end
  end
end
```

```ruby
# app/services/controllers/approvals/approve.rb
# frozen_string_literal: true

module Controllers
  module Approvals
    class Approve < Base
      def initialize(params:)
        @params = params
      end

      def call
        deny_guests!
        ticket = workspace.tickets.find(@params[:id])
        Operations::Approvals::ApproveAll.call(ticket: ticket, actor: user)
        { ok: true }
      end
    end
  end
end
```

```ruby
# app/controllers/api/v1/tickets_controller.rb — add two actions
      def request_approval = render_ok(Controllers::Approvals::RequestApproval.call(params:))
      def approve          = render_ok(Controllers::Approvals::Approve.call(params:))
```

```ruby
# config/routes.rb — inside resources :tickets ... member do ... end
          post :request_approval
          post :approve
```

```ruby
# app/serializers/ticket_serializer.rb — add `:approval` to attributes, and:
  def approval
    {
      requested_at: object.approval_requested_at&.iso8601,
      fully_approved: object.fully_approved?,
      actor_name: object.approval_actor&.then { |a| a.respond_to?(:name) ? a.name : nil }
    }
  end
```

```jsx
// app/frontend/components/ticket/ApprovalPanel.jsx
import { ShieldCheck, Send, CheckCircle2 } from 'lucide-react'
import { toast } from 'sonner'
import { Card } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { useConfirm } from '@/components/ui/confirm-dialog'
import { ticketsApi } from '@/api'

// Production-step approval widget: shows derived status + two confirmed actions
// (resend the client link, approve internally), or "Aprovado por <actor>".
export default function ApprovalPanel({ ticket, onChanged }) {
  const confirm = useConfirm()
  const approval = ticket.approval || {}
  const dt = approval.requested_at ? new Date(approval.requested_at).toLocaleString('pt-BR') : null

  const resend = async () => {
    const ok = await confirm({ title: 'Reenviar link de aprovação?', description: 'O cliente receberá o link por e-mail novamente.', confirmLabel: 'Reenviar' })
    if (!ok) return
    try { await ticketsApi.requestApproval(ticket.id); toast.success('Link reenviado ao cliente!'); onChanged?.() }
    catch (e) { toast.error(e?.error || 'Erro ao reenviar.') }
  }

  const approve = async () => {
    const ok = await confirm({ title: 'Aprovar em nome do cliente?', description: 'Marca todos os criativos como aprovados.', confirmLabel: 'Aprovar' })
    if (!ok) return
    try { await ticketsApi.approve(ticket.id); toast.success('Conteúdo aprovado!'); onChanged?.() }
    catch (e) { toast.error(e?.error || 'Erro ao aprovar.') }
  }

  if (approval.fully_approved) {
    return (
      <Card className="flex items-center gap-2 p-4 text-emerald">
        <CheckCircle2 size={18} />
        <span className="font-semibold">Aprovado{approval.actor_name ? ` por ${approval.actor_name}` : ''}</span>
      </Card>
    )
  }

  return (
    <Card className="p-4">
      <div className="mb-3 flex items-center gap-2 text-ink">
        <ShieldCheck size={18} className="text-brand" />
        <span className="font-semibold">Aguardando aprovação do cliente</span>
      </div>
      {dt && <p className="mb-3 text-xs text-ink-muted">Link enviado em {dt}</p>}
      <div className="flex gap-2">
        <Button variant="outline" onClick={resend}><Send size={16} /> Reenviar link</Button>
        <Button onClick={approve}><CheckCircle2 size={16} /> Aprovar</Button>
      </div>
    </Card>
  )
}
```

```js
// app/frontend/api/index.js — add to ticketsApi
  requestApproval: (id) => api.post(`/tickets/${id}/request_approval`),
  approve: (id) => api.post(`/tickets/${id}/approve`),
```

```jsx
// app/frontend/components/ticket/TicketBody.jsx
// import ApprovalPanel and render it in the production branch (where showCreativesInMain is true),
// above or below the creatives panel:
import ApprovalPanel from '@/components/ticket/ApprovalPanel'
// ...in the production render region:
{status === 'production' && <ApprovalPanel ticket={ticket} onChanged={() => qc.invalidateQueries({ queryKey: keys.ticket(ticket.id) })} />}
```

> Use the ticket-invalidation already available in `TicketBody` (it uses `useTicketMutations`/query client). If `qc`/`keys` aren't in scope there, import `useQueryClient` from `@tanstack/react-query` and `keys` from `@/api/queryKeys`, mirroring other components.

- [ ] **Step 4: Run + verify**

Run: `bundle exec rspec spec/requests/api/v1/ticket_approval_actions_spec.rb`
Expected: PASS. Then in the app, open a ticket in Produção → the ApprovalPanel shows "Reenviar link" / "Aprovar"; approving flips it to "Aprovado por <você>".

- [ ] **Step 5: Commit**

```bash
git add app/services/controllers/approvals app/controllers/api/v1/tickets_controller.rb config/routes.rb app/serializers/ticket_serializer.rb app/frontend/components/ticket/ApprovalPanel.jsx app/frontend/components/ticket/TicketBody.jsx app/frontend/api/index.js spec/requests/api/v1/ticket_approval_actions_spec.rb
git commit -m "feat(tickets): production approval panel (resend link / approve) + internal actions"
```

---

## Self-Review

- **Spec coverage:** Approval link (C1/C3), per-creative approval (A1/B3/C1), GO stops at production (B5), approval→auto-schedule keeping planned date else next slot (B1/B3), project settings + which behaviors (A3/A4/A5), approval email to client (B2, wired in B5/D2), production step redesign to actions + "Aprovado por <actor>" with confirmations (D1/D2), all-confirmations (C3/D2 use `useConfirm`/prompt). Posts hub is Plan 2. ✓
- **No placeholders:** every step has concrete code/commands. The only "read the exact helper name" note is the request-spec sign-in helper (repo-specific) — flagged explicitly, not a code placeholder.
- **Type consistency:** `DecideCreative.call(creative:, decision:, actor:, feedback:)`, `RequestApproval.call(ticket:, sent_by:)`, `ApproveAll.call(ticket:, actor:)`, `ScheduleApproved.call(ticket:, user:)`, `NextSlot.call(project:, desired_at:)`, `Complete.call(run:)` — used consistently across tasks. `approval_state` values `pending/approved/changes_requested` consistent backend↔frontend. `ticketsApi.requestApproval/approve` match routes `request_approval/approve`.

**Open item to confirm during execution:** the request-spec login/billing helper name (`sign_in_as_manager` used illustratively) — replace with this repo's actual shared context per `spec/support`.
