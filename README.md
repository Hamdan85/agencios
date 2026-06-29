# agencios

> The operating system of a social-media / creative agency. A user joins one or more
> **workspaces** (each workspace *is* an agency) that own **clients**, **projects**, **tickets**
> (the unit of agency work, moving through a content production funnel), in-app **creative
> generation**, multi-network **publishing + analytics**, **meetings**, and **billing**.

Rails 8.1 JSON API + React 19 SPA (Vite, Tailwind v4, TanStack Query, Radix, @dnd-kit).
See [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md), [`docs/SPECIFICATION.md`](docs/SPECIFICATION.md)
and [`CLAUDE.md`](CLAUDE.md).

## Quick start

```bash
bundle install
npm install
bin/rails db:prepare db:seed   # creates + seeds a full demo agency
bin/dev                        # Rails (:3000) + Vite + Sidekiq via Procfile.dev
```

Then open **http://localhost:3000** and sign in with the demo account:

| | |
|---|---|
| **E-mail** | `demo@agencios.app` |
| **Senha** | `demo1234` |

The seed builds **Estúdio Pulse** — 5 clients, 8 projects, 17 tickets spread across all 7 funnel
statuses, generated creatives, published posts with metrics, meetings, and Pix invoices — so every
screen is alive on first login. Team members (`rafael@`, `julia@`, `pedro@`, `bia@agencios.app`,
same password) exercise the role system.

## The product

- **Painel** (`/painel`) — agency cockpit: stats, the production funnel, upcoming meetings, recent generations.
- **Quadro** (`/quadro`) — the signature **Kanban board**: 7 status columns, drag-and-drop, project-color cards, rich filters.
- **Ticket** (`/tickets/:id`) — the **contextual** view: the field group + AI summary + AI action change per funnel status.
- **Calendário** (`/calendario`) — unified calendar of scheduled posts + meetings.
- **Estúdio** (`/estudio`) — in-app AI creative generation (carousel / UGC video / image).
- **Tarefas, Projetos, Clientes, Reuniões, Cobranças, Configurações, Assinatura** — the full agency surface.

## The seven-status funnel

`ideation → scoping → production → scheduled → published → retrospective → done`

Every transition flows through the single authoritative `Operations::Tickets::ChangeStatus`
(records a log + history note, refreshes the status-scoped Claude summary, fires side effects,
broadcasts over Action Cable). Each status has its own vivid color + icon — the board and ticket
view read at a glance.

## Architecture (per CLAUDE.md)

Thin controllers → `Controllers::*` / `Operations::*` services → `Vendors::*` / `Publishers::*` /
`Prompts::*`. No business logic in controllers, no AR callbacks for side effects, every query scoped
to `Current.workspace`, status only via `ChangeStatus`, dates ISO 8601, money in cents.

## Tests

```bash
bundle exec rspec        # request + service specs
bin/vite build           # production frontend build
bin/rails zeitwerk:check # eager-load sanity
```

## Notes

Vendor integrations (HeyGen, the image model, Meta/TikTok/etc., Stripe, Mercado Pago, Google
Calendar) are wired through their `Vendors::*` seams with working stubs so the funnel runs
end-to-end; swap each stub for the real client per `docs/integrations/<vendor>.md`. Anthropic powers
the contextual summaries (falls back to a deterministic stub when no API key is configured).
