# frozen_string_literal: true

require "rails_helper"

# Carousel generations are one of the two usage-based billing meters
# (SPECIFICATION.md §9). On completion they must emit a Stripe meter event
# exactly once — image generations must not.
RSpec.describe Operations::Creatives::GenerateCarousel do
  include ActiveJob::TestHelper

  let(:user) { User.create!(email: "gen@agencios.app", password: "secret123", name: "Gen") }
  let(:workspace) { Operations::Workspaces::SetupForUser.call(user: user, name: "Studio Co") }
  let(:client) { workspace.clients.create!(name: "ACME") }
  let(:project) { workspace.projects.create!(client: client, name: "Camp", color: "#7C3AED") }
  let(:ticket) do
    Operations::Tickets::Create.call(
      workspace: workspace, user: user,
      params: { project_id: project.id, title: "Carrossel", creative_type: "carousel", channels: %w[instagram] }
    )
  end

  before do
    ActiveJob::Base.queue_adapter = :test
    Current.workspace = workspace
    Current.actor = user
    allow(Vendors::ImageGen::Actions::GenerateImage).to receive(:call)
      .and_return(url: "https://img.example/slide.png", external_id: "img_1")
  end

  after { Current.reset }

  it "meters a completed carousel to Stripe when the workspace has a customer" do
    workspace.subscription.update!(status: "active", stripe_customer_id: "cus_test")
    allow(Vendors::Stripe::Actions::ReportMeterEvent).to receive(:call).and_return(true)

    generation = described_class.call(ticket: ticket, slides: 3)

    expect(generation.kind).to eq("carousel")
    expect(generation.status).to eq("completed")
    expect(generation.metered_at).to be_present
    expect(Vendors::Stripe::Actions::ReportMeterEvent).to have_received(:call).once
  end

  it "skips metering when the workspace has no Stripe customer yet" do
    allow(Vendors::Stripe::Actions::ReportMeterEvent).to receive(:call)

    generation = described_class.call(ticket: ticket, slides: 2)

    expect(generation.metered_at).to be_nil
    expect(Vendors::Stripe::Actions::ReportMeterEvent).not_to have_received(:call)
  end
end
