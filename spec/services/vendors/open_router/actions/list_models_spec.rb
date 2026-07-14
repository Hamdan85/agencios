# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Vendors::OpenRouter::Actions::ListModels do
  def stub_catalog(models)
    catalog = instance_double(Vendors::OpenRouter::Catalog, models: models)
    allow(Vendors::OpenRouter::Catalog).to receive(:new).and_return(catalog)
  end

  it 'searches by id and name, case-insensitively' do
    stub_catalog([{ id: 'google/veo-3.1', name: 'Google: Veo 3.1' },
                  { id: 'bytedance/seedance-2.0', name: 'ByteDance: Seedance 2.0' }])

    result = described_class.call(kind: 'video', query: 'SEED')
    expect(result[:results].map { |m| m[:id] }).to eq(%w[bytedance/seedance-2.0])
    expect(result[:total]).to eq(1)
    expect(result[:has_more]).to be(false)
  end

  it 'paginates and reports has_more' do
    models = Array.new(45) { |i| { id: "vendor/model-#{i}", name: "Model #{i}" } }
    stub_catalog(models)

    page1 = described_class.call(kind: 'text')
    expect(page1[:results].size).to eq(20)
    expect(page1[:has_more]).to be(true)

    page3 = described_class.call(kind: 'text', page: 3)
    expect(page3[:results].size).to eq(5)
    expect(page3[:has_more]).to be(false)
    expect(page3[:total]).to eq(45)
  end

  it 'treats page 0 / blank query as first page, everything' do
    stub_catalog([{ id: 'a/b', name: 'AB' }])
    result = described_class.call(kind: 'image', query: '  ', page: 0)
    expect(result[:results]).to eq([{ id: 'a/b', name: 'AB' }])
  end
end
