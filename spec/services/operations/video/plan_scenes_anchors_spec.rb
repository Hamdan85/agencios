# frozen_string_literal: true

require 'rails_helper'

# The deterministic identity anchors: PlanScenes must GUARANTEE a generated
# character/scenario reference image up front (not leave it to the storyboard's
# discretion) whenever the locked identity defines one and no photo exists.
RSpec.describe Operations::Video::PlanScenes do
  def planner(mode: 'product')
    described_class.new(ctx: double('ctx'), mode: mode, script: 'x', brief: 'x',
                        total_duration: 8, aspect_ratio: '9:16')
  end

  def anchors(identity:, requested: [], refs: [], mode: 'product')
    p = planner(mode: mode)
    p.instance_variable_set(:@identity, identity)
    p.send(:ensure_identity_anchors, requested, refs, mode)
  end

  it 'adds a character AND scene anchor when the identity defines them and no photo exists' do
    out = anchors(identity: { 'has_character' => true, 'character' => 'Uma raposa prateada', 'scenario' => 'Uma cozinha aconchegante' },
                  refs: [{ role: 'product' }, { role: 'logo' }])

    expect(out).to contain_exactly(
      { 'role' => 'character', 'prompt' => 'Uma raposa prateada' },
      { 'role' => 'scene', 'prompt' => 'Uma cozinha aconchegante' }
    )
  end

  it 'skips the character anchor when a face photo (avatar) is attached' do
    out = anchors(identity: { 'has_character' => true, 'character' => 'A pessoa', 'scenario' => 'Estúdio' },
                  refs: [{ role: 'avatar' }], mode: 'avatar')

    expect(out.map { |r| r['role'] }).to eq([]) # avatar → no char anchor; avatar mode → no scene anchor
  end

  it 'does not duplicate a role the storyboard already requested' do
    out = anchors(identity: { 'has_character' => true, 'character' => 'Mascote', 'scenario' => 'Praia' },
                  requested: [{ 'role' => 'character', 'prompt' => 'Mascote pedido pelo modelo' }])

    expect(out.select { |r| r['role'] == 'character' }.size).to eq(1)
    expect(out.find { |r| r['role'] == 'character' }['prompt']).to eq('Mascote pedido pelo modelo')
    expect(out.map { |r| r['role'] }).to include('scene')
  end

  it 'skips the scene anchor when a location photo already exists' do
    out = anchors(identity: { 'scenario' => 'Floresta' }, refs: [{ role: 'scene' }])
    expect(out).to eq([])
  end

  it 'adds nothing when the identity has no character/scenario' do
    expect(anchors(identity: { 'has_character' => false })).to eq([])
    expect(anchors(identity: nil)).to eq([])
  end
end
