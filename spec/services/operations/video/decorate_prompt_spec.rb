# frozen_string_literal: true

require 'rails_helper'

# The render-prompt COMPILER: every piece of context meets here — visual prompt
# first, then one contract per line (continuity, dialogue/audio, lettering,
# reference manifest, fenced style). Golden coverage per scenario so the shape
# never silently regresses.
RSpec.describe Operations::Video::DecoratePrompt do
  def ctx_double(overrides = {})
    instance_double(
      Tickets::CreativeContext,
      {
        brand_name: 'ACME', brand_voice: 'tom jovem e direto',
        brand_primary: '#111111', brand_secondary: nil,
        production_scope: nil, brand_logo_url: nil, brand_avatar_url: nil
      }.merge(overrides)
    )
  end

  it 'opens with the visual prompt and gives brand look as natural guidance — no hex, no labels' do
    out = described_class.call(prompt: 'A cheetah sprints across a rooftop', mode: 'product',
                               ctx: ctx_double(brand_primary: '#035e09', brand_secondary: '#F59E0B'))

    expect(out).to start_with("A cheetah sprints across a rooftop\n")
    expect(out).to include('Look & feel', 'NEVER show any color name, hex code, label')
    expect(out).to include('keep the mood tom jovem e direto', 'grade toward the brand colors (deep green and orange)')
    # The literal metadata that leaked onto the frame must NOT be in the prompt.
    expect(out).not_to include('#035e09', '#F59E0B', 'brand:', 'palette:')
  end

  it 'omits the generic default voice (no boilerplate a literal model could print)' do
    out = described_class.call(prompt: 'p', mode: 'avatar',
                               ctx: ctx_double(brand_voice: 'tom profissional, próximo e criativo',
                                               brand_primary: nil, brand_secondary: nil))
    expect(out).not_to include('Look & feel') # nothing meaningful to say
  end

  it 'renders the typed reference manifest — position, identifier and the role contract' do
    out = described_class.call(
      prompt: 'p', mode: 'product', ctx: ctx_double,
      references: [{ id: 'img_product_v1', url: 'https://x/p.jpg', role: 'product', kind: 'img' },
                   { id: 'vid_camera_ref_v1', url: 'https://x/c.mp4', role: 'camera', kind: 'vid' },
                   { id: 'img_logo_v1', url: 'https://x/l.png', role: 'logo', kind: 'img' }]
    )

    expect(out).to include('Reference manifest')
    expect(out).to include('input 1 = img_product_v1: PRODUCT reference')
    expect(out).to include('input 2 = vid_camera_ref_v1: CAMERA reference (video)',
                           'replicate ONLY its camera movement')
    expect(out).to include('input 3 = img_logo_v1: the brand LOGO')
    # Identifiers cited in the scene prompt resolve through the manifest.
    expect(out).to include('When this prompt cites an identifier above')
  end

  it 'adds the right continuity contract per seed kind' do
    base = described_class.call(prompt: 'p', mode: 'avatar', ctx: ctx_double)
    prev = described_class.call(prompt: 'p', mode: 'avatar', ctx: ctx_double, continuation: :previous)
    keep = described_class.call(prompt: 'p', mode: 'avatar', ctx: ctx_double, continuation: :self)
    cut  = described_class.call(prompt: 'wide shot', mode: 'avatar', ctx: ctx_double, continuation: :cut)

    expect(base).not_to include('Continuity:')
    expect(prev).to include('NEXT BEAT', 'Never restart, re-establish or retake')
    expect(keep).to include("this scene's CURRENT look", 'apply ONLY the changes')
    expect(keep).not_to include('NEXT BEAT')
    # A CUT is a new shot in the same video — not seeded, not a seamless beat.
    expect(cut).to include('CUT to a NEW shot within the SAME video', 'does not continue from a')
    expect(cut).not_to include('NEXT BEAT')
  end

  it 'tells the model to generate NO music (a single track is burned in post)' do
    out = described_class.call(prompt: 'p', mode: 'avatar', ctx: ctx_double,
                               with_audio: true, dialogue: 'Oi')

    expect(out).to include('NO music of any kind', '(no music, no background music',
                           'added separately in post-production')
  end

  it 'tells the model to lip-sync to the fixed-voice audio reference when voiced' do
    out = described_class.call(prompt: 'p', mode: 'avatar', ctx: ctx_double,
                               with_audio: true, dialogue: 'Com a gente, nenhum prazo escapa.', voiced: true)

    expect(out).to include('"Com a gente, nenhum prazo escapa."', 'AUDIO REFERENCE (a fixed voice)',
                           'lip-sync to that exact audio', 'do NOT generate a different voice')
    # The free "delivery tone" phrasing is replaced by the fixed-voice contract.
    expect(out).not_to include('Delivered in a')
  end

  it 'locks speech to the verbatim dialogue field' do
    out = described_class.call(prompt: 'p', mode: 'avatar', ctx: ctx_double,
                               with_audio: true, dialogue: 'Com a ACME, nenhum prazo escapa.')

    expect(out).to include('spoken EXACTLY as written', 'NOTHING else may be spoken',
                           '"Com a ACME, nenhum prazo escapa."')
  end

  it 'states ambient-only when sound is on without dialogue, and full silence when sound is off' do
    ambient = described_class.call(prompt: 'p', mode: 'avatar', ctx: ctx_double, with_audio: true)
    silent  = described_class.call(prompt: 'p', mode: 'avatar', ctx: ctx_double,
                                   with_audio: false, dialogue: 'ignored')
    legacy  = described_class.call(prompt: 'p', mode: 'avatar', ctx: ctx_double)

    expect(ambient).to include('no dialogue in this scene — ambient/natural sound only')
    expect(silent).to include('SILENT video — no speech')
    expect(silent).not_to include('ignored') # a silent video never carries dialogue
    expect(legacy).not_to include('Audio:', 'Dialogue')
  end

  it 'demands the exact on-screen text — or bans lettering entirely' do
    with_text = described_class.call(prompt: 'p', mode: 'avatar', ctx: ctx_double,
                                     on_screen_text: 'Nunca mais perca um prazo')
    without   = described_class.call(prompt: 'p', mode: 'avatar', ctx: ctx_double)

    expect(with_text).to include('EXACTLY as written', '"Nunca mais perca um prazo"',
                                 'no other lettering', 'Typography:')
    expect(without).to include('On-screen text: NONE — never invent lettering')
  end

  it 'strips a legacy decorated prompt to its clean visual part and recompiles (no boilerplate stacking, no dropped fields)' do
    legacy = 'A creator waves. On-screen text rule: legible or nothing. Never invent watermarks'
    out = described_class.call(prompt: legacy, mode: 'avatar', ctx: ctx_double,
                               with_audio: true, dialogue: 'Olá!')

    expect(out).to start_with('A creator waves.')
    expect(out).not_to include('On-screen text rule:') # legacy directive stripped, not re-appended
    expect(out).to include('"Olá!"') # the new first-class dialogue survives (old bug: it was dropped)
  end

  it 'adds hard brand guardrails as a do-not constraint' do
    out = described_class.call(prompt: 'p', mode: 'avatar', ctx: ctx_double,
                               guardrails: 'bebidas alcoólicas; antes e depois')
    expect(out).to include('Hard brand constraints — the scene must NOT contain any of: bebidas alcoólicas; antes e depois')
  end

  it 'applies the chosen voice delivery tone to the spoken line' do
    out = described_class.call(prompt: 'p', mode: 'avatar', ctx: ctx_double,
                               with_audio: true, dialogue: 'Vem já!', voice_tone: 'energetic and upbeat')
    expect(out).to include('"Vem já!"', 'Delivered in a energetic and upbeat tone')
  end

  it 'injects the LOCKED identity into every scene (character, wardrobe, scenario, style)' do
    out = described_class.call(prompt: 'p', mode: 'avatar', ctx: ctx_double, identity: {
                                 'has_character' => true, 'character' => 'a cheetah lawyer',
                                 'wardrobe' => 'navy suit', 'scenario' => 'modern office', 'style' => 'golden hour'
                               })
    expect(out).to include('Project identity — keep IDENTICAL in every scene',
                           'the SAME character throughout', 'a cheetah lawyer',
                           'wardrobe/styling: navy suit', 'setting/world: modern office', 'visual style: golden hour')
  end

  it 'states there is no character when the scope has none, and adds no identity line when unset' do
    none = described_class.call(prompt: 'p', mode: 'product', ctx: ctx_double, identity: { 'has_character' => false })
    unset = described_class.call(prompt: 'p', mode: 'product', ctx: ctx_double)

    expect(none).to include('no recurring character/person')
    expect(unset).not_to include('Project identity')
  end
end
