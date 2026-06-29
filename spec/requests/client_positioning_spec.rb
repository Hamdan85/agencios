# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Client positioning API", type: :request do
  before do
    ActiveJob::Base.queue_adapter = :test
    @user, @workspace = Operations::Users::Register.call(
      email: "pos@agencios.app", password: "secret123", name: "Pos", workspace_name: "Pos Agency"
    )
    Current.reset
    post "/api/v1/session", params: { email: "pos@agencios.app", password: "secret123" }, as: :json
    expect(response).to have_http_status(:ok)
  end

  it "creates a client with a sanitized positioning bag" do
    post "/api/v1/clients", params: {
      client: {
        name: "ACME",
        positioning: { one_liner: "faz x", content_pillars: %w[dicas bastidores], bogus: "drop" }
      }
    }, as: :json

    expect(response).to have_http_status(:created)
    body = JSON.parse(response.body)
    expect(body.dig("client", "has_positioning")).to be(true)
    expect(body.dig("client", "positioning", "one_liner")).to eq("faz x")
    expect(body.dig("client", "positioning", "content_pillars")).to eq(%w[dicas bastidores])
    expect(body.dig("client", "positioning")).not_to have_key("bogus")
  end

  it "returns an AI-synthesized positioning preview" do
    post "/api/v1/clients/positioning_preview", params: {
      name: "ACME", one_liner: "vende doces", target_audience: "PMEs"
    }, as: :json

    expect(response).to have_http_status(:ok)
    body = JSON.parse(response.body)
    expect(body["positioning"]).to have_key("statement")
    expect(body.dig("positioning", "statement")).to be_present
  end

  it "updates an existing client's positioning" do
    client = @workspace.clients.create!(name: "ACME")

    patch "/api/v1/clients/#{client.id}/positioning", params: {
      positioning: { value_proposition: "promessa única", content_pillars: %w[prova] }
    }, as: :json

    expect(response).to have_http_status(:ok)
    expect(client.reload.positioning).to eq(
      "value_proposition" => "promessa única", "content_pillars" => %w[prova]
    )
  end
end
