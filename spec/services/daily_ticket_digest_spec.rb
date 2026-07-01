# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Operations::Digests::SendDailyTicketDigest" do
  before { ActiveJob::Base.queue_adapter = :test }

  def build_workspace(active: true)
    user, workspace = Operations::Users::Register.call(
      email: "u#{SecureRandom.hex(4)}@agencios.app", password: "secret123", name: "U", workspace_name: "W"
    )
    workspace.subscription.update!(status: active ? "active" : "canceled")
    [user, workspace]
  end

  def build_ticket(workspace, user, **attrs)
    client = workspace.clients.create!(name: "ACME")
    project = workspace.projects.create!(client: client, name: "Camp", color: "#7C3AED")
    workspace.tickets.create!(project: project, assignee: user, title: "T", **attrs)
  end

  it "emails tickets due today or overdue, assigned to the user, in active workspaces" do
    user, workspace = build_workspace
    due_today = build_ticket(workspace, user, due_date: Date.current)
    overdue = build_ticket(workspace, user, due_date: 2.days.ago.to_date)
    build_ticket(workspace, user, due_date: 2.days.from_now.to_date) # not due yet
    build_ticket(workspace, user, due_date: Date.current, status: :done) # done, excluded
    build_ticket(workspace, user, due_date: Date.current, archived_at: Time.current) # archived, excluded

    expect { Operations::Digests::SendDailyTicketDigest.call(user: user) }
      .to have_enqueued_mail(DigestMailer, :daily_tickets)
      .with(user: user, tickets: match_array([due_today, overdue]))
  end

  it "does not email a user with no active workspace" do
    user, = build_workspace(active: false)
    build_ticket(user.workspaces.first, user, due_date: Date.current)

    expect { Operations::Digests::SendDailyTicketDigest.call(user: user) }
      .not_to have_enqueued_mail(DigestMailer, :daily_tickets)
  end
end
