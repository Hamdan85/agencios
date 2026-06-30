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

  it "returns an AI-filled positioning preview from a free-text brief" do
    post "/api/v1/clients/positioning_preview", params: {
      name: "ACME", brief: "Marca de doces artesanais para PMEs que vendem pelo Instagram"
    }, as: :json

    expect(response).to have_http_status(:ok)
    body = JSON.parse(response.body)
    # Offline (no API key) the adapter stubs non-JSON text, so the operation
    # degrades to seeding one_liner with the brief — the bag is still filled.
    expect(body["positioning"]).to be_present
    expect(body.dig("positioning", "one_liner")).to include("doces artesanais")
  end

  it "extracts a client draft from a landing page URL" do
    digest = {
      url: "https://docearte.com.br", title: "Doce Arte", site_name: "Doce Arte",
      description: "Bolos artesanais", theme_color: "#E91E63",
      emails: ["contato@docearte.com.br"], phones: [],
      socials: { instagram: "https://instagram.com/docearte_oficial" },
      text: "Bolos que encantam."
    }
    allow_any_instance_of(Vendors::Web::Client).to receive(:fetch_digest).and_return(digest)

    post "/api/v1/clients/extract_from_url", params: { url: "docearte.com.br" }, as: :json

    expect(response).to have_http_status(:ok)
    body = JSON.parse(response.body)
    expect(body.dig("extracted", "source_url")).to eq("https://docearte.com.br")
    expect(body.dig("extracted", "contact", "name")).to eq("Doce Arte")
    expect(body.dig("extracted", "contact", "email")).to eq("contato@docearte.com.br")
    expect(body.dig("extracted", "brand", "default_handle")).to eq("docearte_oficial")
  end

  it "returns 422 when the landing page can't be reached" do
    allow_any_instance_of(Vendors::Web::Client)
      .to receive(:fetch_digest).and_raise(Vendors::Base::Error.new("Não foi possível acessar a página."))

    post "/api/v1/clients/extract_from_url", params: { url: "https://broken.example" }, as: :json

    expect(response).to have_http_status(:unprocessable_content)
    expect(JSON.parse(response.body)["error"]).to match(/não foi possível acessar/i)
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
