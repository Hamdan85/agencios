# frozen_string_literal: true

require 'rails_helper'

# The scene layer: planning (deterministic split), composing (ffmpeg concat +
# finalize), and per-scene editing (free caption / charged re-render). FFmpeg and
# the OpenRouter vendor are stubbed so the specs stay offline.
RSpec.describe 'video scene pipeline' do
  include ActiveJob::TestHelper

  let(:user) { User.create!(email: 'sc@agencios.app', password: 'secret123', name: 'Sc') }
  let(:workspace) { Operations::Workspaces::SetupForUser.call(user: user, name: 'Studio Co') }
  let(:client) { workspace.clients.create!(name: 'ACME') }
  let(:project) { workspace.projects.create!(client: client, name: 'Camp', color: '#7C3AED') }
  let(:ticket) do
    Operations::Tickets::Create.call(
      workspace: workspace, user: user,
      params: { project_id: project.id, title: 'Reel', creative_type: 'ugc_video', channels: %w[instagram] }
    )
  end
  let(:ctx) { Tickets::CreativeContext.for(ticket, creative_type: 'ugc_video') }

  before do
    ActiveJob::Base.queue_adapter = :test
    Current.workspace = workspace
    Current.actor = user
    Operations::Credits::EnsureWallet.call(workspace: workspace).update!(purchased_balance: 10_000)
    # Force the deterministic storyboard fallback (no live AI in specs).
    allow(Vendors::Ai).to receive(:client).and_raise(StandardError, 'no ai in test')
    # Voice discovery is a network call — keep it offline (no voices ⇒ model audio).
    allow(Vendors::Cartesia::Actions::ListVoices).to receive(:call).and_return([])
  end

  after { Current.reset }

  describe Operations::Video::PlanScenes do
    it 'an 8s request is exactly ONE scene — the duration is a hard scene budget' do
      scenes = described_class.call(ctx: ctx, mode: 'avatar', script: 'Um. Dois. Três.',
                                    total_duration: 8, aspect_ratio: '9:16')
      expect(scenes.size).to eq(1)
      expect(scenes.first[:duration_seconds]).to eq(8)
      # The whole script still rides in the single scene — as its DIALOGUE.
      expect(scenes.first[:dialogue]).to include('Um.', 'Dois.', 'Três.')
      expect(scenes.first[:prompt]).not_to include('Um.') # visual prompt stays visual
    end

    it 'distributes the avatar script across the scenes the duration buys (~8s each)' do
      scenes = described_class.call(ctx: ctx, mode: 'avatar', script: 'Um. Dois. Três. Quatro. Cinco.',
                                    total_duration: 20, aspect_ratio: '9:16')
      expect(scenes.size).to eq(3) # ceil(20/8), not one per sentence
      expect(scenes.map { |s| s[:duration_seconds] }.sum).to be_within(5).of(20)
      joined = scenes.map { |s| s[:dialogue] }.join(' ')
      %w[Um. Dois. Três. Quatro. Cinco.].each { |sentence| expect(joined).to include(sentence) }
    end

    it 'builds hook→feature→cta beats for product, carrying references' do
      scenes = described_class.call(ctx: ctx, mode: 'product', brief: 'Café gelado',
                                    total_duration: 24, aspect_ratio: '9:16',
                                    reference_image_urls: ['https://x/cup.jpg'])
      expect(scenes.size).to eq(3)
      expect(scenes).to all(include(reference_image_urls: ['https://x/cup.jpg']))
      # Beats CHAIN: only scene 1 states the subject; later beats continue the
      # same shot instead of re-describing the whole video (no "versions").
      expect(scenes.first[:prompt]).to include('Café gelado')
      scenes.drop(1).each do |s|
        expect(s[:prompt]).to include('SAME product video continues')
        expect(s[:prompt]).not_to include('Café gelado')
      end
    end

    it 'falls back to the TICKET scope when no script param is passed (ticket/autopilot flow)' do
      # Ticket-driven generation passes params:{} — the script lives on the ticket.
      ticket.update!(fields: { 'scoping' => { 'script' => 'Fala do ticket um. Fala do ticket dois.' } })
      ticket_ctx = Tickets::CreativeContext.for(ticket, creative_type: 'ugc_video')

      scenes = described_class.call(ctx: ticket_ctx, mode: 'avatar', script: nil, brief: nil,
                                    total_duration: 16, aspect_ratio: '9:16')

      dialogue = scenes.map { |s| s[:dialogue] }.join(' ')
      expect(dialogue).to include('Fala do ticket um.', 'Fala do ticket dois.')
    end

    it 'marks scene 1 as non-continuing and later fallback scenes as seamless continuations' do
      scenes = described_class.call(ctx: ctx, mode: 'avatar', script: 'Um. Dois. Três. Quatro.',
                                    total_duration: 24, aspect_ratio: '9:16')
      expect(scenes.first[:continues_previous]).to be(false)
      expect(scenes.drop(1)).to all(include(continues_previous: true))
    end

    it 'honors a storyboard per-scene duration and a CUT flag (agnostic to the prompt)' do
      allow(Vendors::Ai).to receive(:client).and_call_original
      ai = instance_double('ai_client', provider_key: 'openrouter')
      allow(ai).to receive(:generate).and_return(
        Vendors::Ai::Result.new(text: '', usage: {}, model: 'x', tool_input: {
          'scenes' => [
            { 'prompt' => 'creator talks', 'caption' => 'fala', 'duration_seconds' => 6 },
            { 'prompt' => 'wide shot of the office team', 'caption' => 'corte', 'continues_previous' => false }
          ]
        })
      )
      allow(Vendors::Ai).to receive(:client).and_return(ai)
      allow(Vendors::Ai).to receive(:model_for).and_return('x')

      scenes = described_class.call(ctx: ctx, mode: 'avatar', script: 'oi', total_duration: 16, aspect_ratio: '9:16')

      expect(scenes.size).to eq(2)
      expect(scenes.first[:duration_seconds]).to eq(6) # storyboard-paced (a supported length)
      expect(scenes.last[:continues_previous]).to be(false) # a cut
    end

    it 'snaps a storyboard duration that is NOT a supported clip length to the nearest option' do
      ai = instance_double('ai_client', provider_key: 'openrouter')
      allow(ai).to receive(:generate).and_return(
        Vendors::Ai::Result.new(text: '', usage: {}, model: 'x', tool_input: {
          'scenes' => [{ 'prompt' => 'creator talks', 'caption' => 'fala', 'duration_seconds' => 7 }]
        })
      )
      allow(Vendors::Ai).to receive(:client).and_return(ai)
      allow(Vendors::Ai).to receive(:model_for).and_return('x')

      scenes = described_class.call(ctx: ctx, mode: 'avatar', script: 'oi', total_duration: 8, aspect_ratio: '9:16')

      # avatar → veo-3.1 family supports [4, 6, 8]; 7 snaps to 6 (tie rounds down).
      expect(VideoConfig::DEFAULT_CLIP_SECONDS).to include(scenes.first[:duration_seconds])
      expect(scenes.first[:duration_seconds]).to eq(6)
    end

    it 'caps scenes so their durations never overshoot the total (over-pacing → fewer scenes)' do
      ai = instance_double('ai_client', provider_key: 'openrouter')
      allow(ai).to receive(:generate).and_return(
        Vendors::Ai::Result.new(text: '', usage: {}, model: 'x', tool_input: {
          # Two full 8s clips = 16s for an 8s video — must be capped to fit.
          'scenes' => [{ 'prompt' => 'a', 'duration_seconds' => 8 }, { 'prompt' => 'b', 'duration_seconds' => 8 }]
        })
      )
      allow(Vendors::Ai).to receive(:client).and_return(ai)
      allow(Vendors::Ai).to receive(:model_for).and_return('x')

      scenes = described_class.call(ctx: ctx, mode: 'avatar', script: 'oi', total_duration: 8, aspect_ratio: '9:16')
      expect(scenes.size).to eq(1) # 8s already fills the 8s total
      expect(scenes.sum { |s| s[:duration_seconds] }).to be <= 8
    end

    it 'a short total is a SINGLE clip, never two min-length clips' do
      # total 6 → floor(6/4)=1 scene (two 4s clips would be 8s > 6s).
      scenes = described_class.call(ctx: ctx, mode: 'avatar', script: 'Um. Dois. Três.',
                                    total_duration: 6, aspect_ratio: '9:16')
      expect(scenes.size).to eq(1)
    end

    it 'captures the orchestrator request to GENERATE consistency references' do
      ai = instance_double('ai_client', provider_key: 'openrouter')
      allow(ai).to receive(:generate).and_return(
        Vendors::Ai::Result.new(text: '', usage: {}, model: 'x', tool_input: {
          'generated_references' => [
            { 'role' => 'character', 'prompt' => 'a cheetah lawyer in a navy suit' },
            { 'role' => 'bogus', 'prompt' => '' } # dropped (blank prompt)
          ],
          'scenes' => [{ 'prompt' => 'creator talks', 'caption' => 'fala' }]
        })
      )
      allow(Vendors::Ai).to receive(:client).and_return(ai)
      allow(Vendors::Ai).to receive(:model_for).and_return('x')

      plan = described_class.call(ctx: ctx, mode: 'avatar', script: 'oi', total_duration: 8, aspect_ratio: '9:16')
      expect(plan.generated_references).to eq([{ 'role' => 'character', 'prompt' => 'a cheetah lawyer in a navy suit' }])
    end

    it 'captures the orchestrator music spec (query + mix params), one per video' do
      ai = instance_double('ai_client', provider_key: 'openrouter')
      allow(ai).to receive(:generate).and_return(
        Vendors::Ai::Result.new(text: '', usage: {}, model: 'x', tool_input: {
          'music' => { 'query' => 'upbeat corporate', 'mood' => 'upbeat', 'volume' => 0.3, 'duck' => true },
          'scenes' => [{ 'prompt' => 'creator talks', 'caption' => 'fala' }]
        })
      )
      allow(Vendors::Ai).to receive(:client).and_return(ai)
      allow(Vendors::Ai).to receive(:model_for).and_return('x')

      plan = described_class.call(ctx: ctx, mode: 'avatar', script: 'oi', total_duration: 8, aspect_ratio: '9:16')
      expect(plan.music).to include('query' => 'upbeat corporate', 'mood' => 'upbeat')

      # The deterministic fallback picks no music.
      allow(Vendors::Ai).to receive(:client).and_raise(StandardError, 'offline')
      expect(described_class.call(ctx: ctx, mode: 'avatar', script: 'oi', total_duration: 8, aspect_ratio: '9:16').music).to be_nil
    end

    it 'lets the orchestrator switch the mode and attaches only user refs for non-avatar/product modes' do
      ai = instance_double('ai_client', provider_key: 'openrouter')
      allow(ai).to receive(:generate).and_return(
        Vendors::Ai::Result.new(text: '', usage: {}, model: 'x', tool_input: {
          'mode' => 'character',
          'scenes' => [{ 'prompt' => 'an animated fox lawyer waves', 'caption' => 'raposa' }]
        })
      )
      allow(Vendors::Ai).to receive(:client).and_return(ai)
      allow(Vendors::Ai).to receive(:model_for).and_return('x')

      # Requested as avatar, but the director switches to character.
      scenes = described_class.call(ctx: ctx, mode: 'avatar', script: 'oi', total_duration: 8,
                                    aspect_ratio: '9:16', reference_image_urls: ['https://x/ref.jpg'])

      expect(scenes.first[:mode]).to eq('character')
      # character mode: only the user's ref (role reference), no forced avatar/logo.
      expect(scenes.first[:reference_roles]).to eq(['reference'])
      expect(scenes.first[:reference_image_urls]).to eq(['https://x/ref.jpg'])
    end

    it 'captures the orchestrator-locked identity (scope + look)' do
      ai = instance_double('ai_client', provider_key: 'openrouter')
      allow(ai).to receive(:generate).and_return(
        Vendors::Ai::Result.new(text: '', usage: {}, model: 'x', tool_input: {
          'identity' => { 'has_character' => true, 'character' => 'a cheetah lawyer', 'wardrobe' => 'navy suit', 'palette' => '#000' },
          'scenes' => [{ 'prompt' => 'creator talks', 'caption' => 'fala' }]
        })
      )
      allow(Vendors::Ai).to receive(:client).and_return(ai)
      allow(Vendors::Ai).to receive(:model_for).and_return('x')

      plan = described_class.call(ctx: ctx, mode: 'avatar', script: 'oi', total_duration: 8, aspect_ratio: '9:16')
      expect(plan.identity).to include('has_character' => true, 'character' => 'a cheetah lawyer', 'wardrobe' => 'navy suit')
    end

    it 'persists each reference image ROLE alongside the URL (avatar mode → avatar role)' do
      scenes = described_class.call(ctx: ctx, mode: 'avatar', script: 'Oi.',
                                    total_duration: 8, aspect_ratio: '9:16')
      # No brand avatar attached in this ctx → no refs; role list stays parallel.
      expect(scenes.first).to have_key(:reference_roles)
      expect(scenes.first[:reference_roles].size).to eq(scenes.first[:reference_image_urls].size)
    end

    it 'stores CLEAN prompts — the standing directives are applied at render time' do
      scenes = described_class.call(ctx: ctx, mode: 'avatar', script: 'Um. Dois.',
                                    total_duration: 16, aspect_ratio: '9:16')
      expect(scenes.size).to eq(2)
      scenes.each { |s| expect(s[:prompt]).not_to include('On-screen text rule') }
    end
  end

  describe Operations::Video::RenderScene do
    let(:creative) do
      Operations::Creatives::Create.call(ticket: ticket, creative_type: 'ugc_video',
                                         source: :generated, status: :generating, provider: 'openrouter')
    end
    let!(:generation) do
      workspace.generations.create!(user: user, creative: creative, kind: :video, status: :processing,
                                    provider: 'openrouter', params: { mode: 'avatar', quality: 'draft' })
    end
    let(:scene) do
      Operations::Video::Scenes::Create.call(creative: creative, position: 0, mode: 'avatar',
                                             prompt: 'A creator waves hello', duration_seconds: 8, aspect_ratio: '9:16')
    end

    before { allow(Vendors::OpenRouter::Actions::GenerateVideo).to receive(:call).and_return('job_render') }

    it 'passes the synthesized voice clip as an audio reference and demands lip-sync' do
      generation.update!(params: generation.params.merge('with_audio' => true, 'voice_id' => 'voice_abc'))
      scene.update!(metadata: scene.metadata.merge('dialogue' => 'Fala fixa', 'voice_fingerprint' => 'x'))
      # Pre-attach a voice clip whose fingerprint matches → ensure_voice_clip! reuses it
      # (no Cartesia call) and the render carries it as the lip-sync audio reference.
      allow_any_instance_of(Operations::Video::RenderScene).to receive(:ensure_voice_clip!)
      scene.voice_clip.attach(io: StringIO.new('AUDIO'), filename: 'v.mp3', content_type: 'audio/mpeg')

      described_class.call(scene: scene)

      expect(Vendors::OpenRouter::Actions::GenerateVideo).to have_received(:call).with(
        hash_including(
          audio_references: [hash_including(url: a_string_including('/rails/'))],
          prompt: a_string_including('AUDIO REFERENCE (a fixed voice)')
        )
      )
    end

    it 'sends no audio reference when there is no synthesized voice' do
      described_class.call(scene: scene)
      expect(Vendors::OpenRouter::Actions::GenerateVideo).to have_received(:call).with(
        hash_including(audio_references: [])
      )
    end

    it 'submits the COMPILED prompt but keeps the stored prompt clean' do
      described_class.call(scene: scene)

      expect(Vendors::OpenRouter::Actions::GenerateVideo).to have_received(:call).with(
        hash_including(prompt: satisfy do |p|
          p.start_with?('A creator waves hello') && p.include?('On-screen text: NONE') &&
            !p.include?('NEXT BEAT')
        end)
      )
      expect(scene.reload.prompt).to eq('A creator waves hello')
    end

    it 'adds the next-beat continuity directive when a first frame seeds the render' do
      described_class.call(scene: scene, first_frame_url: 'https://x/last.png')

      expect(Vendors::OpenRouter::Actions::GenerateVideo).to have_received(:call).with(
        hash_including(
          prompt: a_string_including('NEXT BEAT'),
          frame_images: [{ url: 'https://x/last.png', frame_type: 'first' }]
        )
      )
    end

    it 'a CUT scene does NOT seed from the previous frame and carries the cut directive' do
      prev = Operations::Video::Scenes::Create.call(creative: creative, position: 0, mode: 'avatar',
                                                    prompt: 'p0', duration_seconds: 8, aspect_ratio: '9:16')
      prev.last_frame.attach(io: StringIO.new('FRAME'), filename: 'l.png', content_type: 'image/png')
      prev.update!(render_state: :ready)
      cut = Operations::Video::Scenes::Create.call(creative: creative, position: 1, mode: 'avatar',
                                                   prompt: 'wide shot of the whole team', duration_seconds: 8,
                                                   aspect_ratio: '9:16', continues_previous: false)

      described_class.call(scene: cut)

      expect(Vendors::OpenRouter::Actions::GenerateVideo).to have_received(:call).with(
        hash_including(frame_images: [], prompt: a_string_including('CUT to a NEW shot within the SAME video'))
      )
    end

    it 'seeds a later scene with the previous frame INLINED as pixels (data URL)' do
      scene.update!(render_state: :ready)
      scene.last_frame.attach(io: StringIO.new('FRAMEPNG'), filename: 'last.png', content_type: 'image/png')
      later = Operations::Video::Scenes::Create.call(creative: creative, position: 1, mode: 'avatar',
                                                     prompt: 'keeps talking', duration_seconds: 8, aspect_ratio: '9:16')

      described_class.call(scene: later)

      expected = "data:image/png;base64,#{Base64.strict_encode64('FRAMEPNG')}"
      expect(Vendors::OpenRouter::Actions::GenerateVideo).to have_received(:call).with(
        hash_including(
          prompt: a_string_including('NEXT BEAT'),
          frame_images: [{ url: expected, frame_type: 'first' }]
        )
      )
    end

    it 'strips a legacy decorated prompt to its clean part instead of re-appending directives' do
      legacy = 'old prompt. On-screen text rule: legible or nothing'
      scene.update!(prompt: legacy)

      described_class.call(scene: scene)

      expect(Vendors::OpenRouter::Actions::GenerateVideo).to have_received(:call).with(
        hash_including(prompt: satisfy do |p|
          p.start_with?('old prompt.') && p.scan('On-screen text rule:').size.zero?
        end)
      )
    end

    it 'KEEPS THE LOOK on a first-scene re-render: seeds with its own opening frame' do
      scene.clip.attach(io: StringIO.new('OLDCLIP'), filename: 's0.mp4', content_type: 'video/mp4')
      scene.update!(render_state: :stale)
      allow(Vendors::Ffmpeg::FirstFrame).to receive(:call) do |input_path:, output_path:|
        File.write(output_path, 'FIRSTPNG')
        output_path
      end

      described_class.call(scene: scene)

      expected = "data:image/png;base64,#{Base64.strict_encode64('FIRSTPNG')}"
      expect(Vendors::OpenRouter::Actions::GenerateVideo).to have_received(:call).with(
        hash_including(
          prompt: a_string_including("this scene's CURRENT look"),
          frame_images: [{ url: expected, frame_type: 'first' }]
        )
      )
    end

    it 'a restyle re-render breaks from the current look (no self seed)' do
      scene.clip.attach(io: StringIO.new('OLDCLIP'), filename: 's0.mp4', content_type: 'video/mp4')
      scene.update!(render_state: :stale, metadata: { 'restyle' => true })
      allow(Vendors::Ffmpeg::FirstFrame).to receive(:call)

      described_class.call(scene: scene)

      expect(Vendors::Ffmpeg::FirstFrame).not_to have_received(:call)
      expect(Vendors::OpenRouter::Actions::GenerateVideo).to have_received(:call).with(
        hash_including(frame_images: [])
      )
    end

    it 'a restyle on a LATER scene also breaks continuity (no previous-frame seed, no NEXT BEAT)' do
      prev = Operations::Video::Scenes::Create.call(creative: creative, position: 0, mode: 'avatar',
                                                    prompt: 'p0', duration_seconds: 8, aspect_ratio: '9:16')
      prev.last_frame.attach(io: StringIO.new('FRAME'), filename: 'l.png', content_type: 'image/png')
      prev.update!(render_state: :ready)
      later = Operations::Video::Scenes::Create.call(creative: creative, position: 1, mode: 'avatar',
                                                     prompt: 'neon futurista', duration_seconds: 8, aspect_ratio: '9:16')
      later.update!(render_state: :stale, metadata: { 'restyle' => true })

      described_class.call(scene: later)

      expect(Vendors::OpenRouter::Actions::GenerateVideo).to have_received(:call).with(
        hash_including(frame_images: [], prompt: satisfy { |p| !p.include?('NEXT BEAT') })
      )
    end

    it 'labels references by their persisted ROLE with the stable identifier, not by URL equality' do
      scene.update!(reference_image_urls: ['https://stale-host/old-avatar.png'],
                    metadata: { 'reference_roles' => ['avatar'] })

      described_class.call(scene: scene)

      expect(Vendors::OpenRouter::Actions::GenerateVideo).to have_received(:call).with(
        hash_including(prompt: a_string_including('input 1 = img_avatar_v1: the CREATOR (the spokesperson)'))
      )
    end

    it 'submits a video reference as a video_url part and manifests it as a camera guide' do
      scene.update!(reference_image_urls: ['https://cdn/guide.mp4'],
                    metadata: { 'reference_roles' => ['camera'] })

      described_class.call(scene: scene)

      expect(Vendors::OpenRouter::Actions::GenerateVideo).to have_received(:call).with(
        hash_including(
          input_references: [{ url: 'https://cdn/guide.mp4', type: 'video_url' }],
          prompt: a_string_including('input 1 = vid_camera_ref_v1: CAMERA reference (video)')
        )
      )
    end

    it 'compiles the scene dialogue as the verbatim speech contract when sound is on' do
      generation.update!(params: generation.params.merge('with_audio' => true))
      scene.update!(metadata: { 'dialogue' => 'Nunca mais perca um prazo.' })

      described_class.call(scene: scene)

      expect(Vendors::OpenRouter::Actions::GenerateVideo).to have_received(:call).with(
        hash_including(prompt: a_string_including('spoken EXACTLY as written', '"Nunca mais perca um prazo."'))
      )
    end
  end

  describe Operations::Video::Compose do
    let(:creative) do
      Operations::Creatives::Create.call(ticket: ticket, creative_type: 'ugc_video',
                                         source: :generated, status: :generating, provider: 'openrouter')
    end
    let!(:generation) do
      workspace.generations.create!(user: user, creative: creative, kind: :video, status: :processing,
                                    provider: 'openrouter', params: { mode: 'avatar', aspect_ratio: '9:16' })
    end

    before do
      # Two ready scenes with attached (fake) clips.
      2.times do |i|
        scene = Operations::Video::Scenes::Create.call(creative: creative, position: i, mode: 'avatar',
                                                       prompt: "p#{i}", duration_seconds: 8, aspect_ratio: '9:16')
        scene.clip.attach(io: StringIO.new('FAKEMP4'), filename: "s#{i}.mp4", content_type: 'video/mp4')
        scene.update!(render_state: :ready, cost_cents: 50)
      end
      # Held credits for a 30s estimate (the pipeline default) to reconcile down.
      Operations::Credits::Debit.call(workspace: workspace,
                                      amount: Pricing.credits_for(kind: :video, seconds: 30),
                                      generation: generation)
      # Stub ffmpeg: just create the output file so ActiveStorage can attach it.
      allow(Vendors::Ffmpeg::Concat).to receive(:call) { |input_paths:, output_path:, **_| File.write(output_path, 'OUT'); output_path }
    end

    it 'concats scenes, attaches the final video, completes the generation, and reconciles credits' do
      described_class.call(creative: creative)

      expect(creative.reload.status).to eq('ready')
      expect(creative.assets).to be_attached
      expect(generation.reload.status).to eq('completed')
      expect(generation.result['duration']).to eq(16)
      # Held a 30s estimate, trued-up to the REAL summed scene cost (2 × 50¢ = 100¢).
      net = -workspace.credit_transactions.where(generation_id: generation.id).sum(:amount)
      expect(net).to eq(Pricing.credits_for_cost(cost_cents: 100))
    end

    it 'is idempotent — a completed generation short-circuits' do
      generation.update!(status: :completed)
      expect { described_class.call(creative: creative) }.not_to change { creative.reload.status }
    end

    it 'burns the selected music track under the audio (passes music_path to ffmpeg)' do
      generation.update!(params: generation.params.merge('music_url' => 'https://x/track.mp3'))
      # Stub the download so no HTTP happens; return a fake local file.
      allow_any_instance_of(Operations::Video::Compose).to receive(:music_path) do |_, dir|
        path = File.join(dir, 'm'); File.write(path, 'M'); path
      end

      described_class.call(creative: creative)

      expect(Vendors::Ffmpeg::Concat).to have_received(:call).with(hash_including(music_path: a_string_including('/m')))
    end

    it 'ships without music when there is no track selected' do
      described_class.call(creative: creative)
      expect(Vendors::Ffmpeg::Concat).to have_received(:call).with(hash_including(music_path: nil))
    end

    it 'does NOT re-reconcile after per-scene edit debits (no full-video re-charge on recompose)' do
      described_class.call(creative: creative) # first compose settles the initial hold

      # An edit: exact per-scene charge, generation reopens, video recomposes.
      generation.update!(status: :processing)
      Operations::Credits::Debit.call(workspace: workspace, generation: generation,
                                      amount: Pricing.credits_for(kind: :video, seconds: 8),
                                      description: 'Refazer cena do vídeo')

      expect { described_class.call(creative: creative) }.not_to(change do
        workspace.credit_transactions.where(generation_id: generation.id, kind: 'adjustment').count
      end)
    end
  end

  describe Operations::Video::EditScene do
    let(:creative) do
      Operations::Creatives::Create.call(ticket: ticket, creative_type: 'ugc_video',
                                         source: :generated, status: :ready, provider: 'openrouter')
    end
    let!(:generation) do
      workspace.generations.create!(user: user, creative: creative, kind: :video, status: :completed,
                                    provider: 'openrouter', params: { mode: 'avatar' })
    end
    let!(:scene) do
      Operations::Video::Scenes::Create.call(creative: creative, position: 0, mode: 'avatar',
                                             prompt: 'original', duration_seconds: 8, aspect_ratio: '9:16')
                                       .tap { |s| s.update!(render_state: :ready, seed: 'seed1') }
    end

    it 'a caption-only edit is free and does not re-render' do
      allow(Vendors::OpenRouter::Actions::GenerateVideo).to receive(:call)
      expect do
        described_class.call(scene: scene, caption: 'Nova legenda')
      end.not_to change { workspace.credit_transactions.count }
      expect(scene.reload.caption).to eq('Nova legenda')
      expect(Vendors::OpenRouter::Actions::GenerateVideo).not_to have_received(:call)
    end

    it 'a dialogue-only change re-renders the scene (speech is a creative field)' do
      allow(Vendors::OpenRouter::Actions::GenerateVideo).to receive(:call).and_return('job_dlg')

      described_class.call(scene: scene, dialogue: 'Nova fala exata.')

      expect(scene.reload.render_state).to eq('rendering')
      expect(scene.metadata['dialogue']).to eq('Nova fala exata.')
      expect(scene.prompt).to eq('original') # visual prompt untouched
    end

    it 'a prompt change re-renders only that scene, charges it, and reopens the generation' do
      allow(Vendors::OpenRouter::Actions::GenerateVideo).to receive(:call).and_return('job_re')

      described_class.call(scene: scene, prompt: 'novo prompt')

      expect(scene.reload.prompt).to eq('novo prompt')
      expect(scene.render_state).to eq('rendering')
      expect(generation.reload.status).to eq('processing')
      debit = workspace.credit_transactions.debits.where(generation_id: generation.id).last
      expect(-debit.amount).to eq(Pricing.credits_for(kind: :video, seconds: 8))
      expect(PollVideoSceneJob).to have_been_enqueued.with(scene.id)
    end

    it 'an identical prompt RETRIES a failed scene (and reopens a failed creative)' do
      allow(Vendors::OpenRouter::Actions::GenerateVideo).to receive(:call).and_return('job_retry')
      scene.update!(render_state: :failed)
      creative.update!(status: :failed)
      generation.update!(status: :failed)

      described_class.call(scene: scene, prompt: 'original')

      expect(scene.reload.render_state).to eq('rendering')
      expect(creative.reload.status).to eq('generating')
      expect(generation.reload.status).to eq('processing')
    end

    it 'appends attached reference images (role reference) and re-renders' do
      allow(Vendors::OpenRouter::Actions::GenerateVideo).to receive(:call).and_return('job_ref')

      described_class.call(scene: scene, add_reference_urls: ['https://cdn/ref.jpg'])

      expect(scene.reload.reference_urls).to include('https://cdn/ref.jpg')
      expect(scene.metadata['reference_roles']).to eq(['reference'])
      expect(scene.render_state).to eq('rendering')
    end

    it 'a restyle-only edit (no field change) still re-renders a ready scene' do
      allow(Vendors::OpenRouter::Actions::GenerateVideo).to receive(:call).and_return('job_rs')

      described_class.call(scene: scene, restyle: true)

      expect(scene.reload.render_state).to eq('rendering')
      expect(scene.metadata['restyle']).to be(true)
    end

    it 'drops a dialogue edit on a SILENT generation — no charge, no re-render' do
      generation.update!(params: generation.params.merge('with_audio' => false))
      allow(Vendors::OpenRouter::Actions::GenerateVideo).to receive(:call)

      expect do
        described_class.call(scene: scene, dialogue: 'fala que nunca vai tocar')
      end.not_to change { workspace.credit_transactions.count }
      expect(scene.reload.render_state).to eq('ready')
      expect(Vendors::OpenRouter::Actions::GenerateVideo).not_to have_received(:call)
    end

    it 'holds a later scene as stale until its predecessors are ready (continuity chain)' do
      allow(Vendors::OpenRouter::Actions::GenerateVideo).to receive(:call).and_return('job_x')
      scene.update!(render_state: :failed) # predecessor not ready
      later = Operations::Video::Scenes::Create.call(creative: creative, position: 1, mode: 'avatar',
                                                     prompt: 'p1', duration_seconds: 8, aspect_ratio: '9:16')
                                               .tap { |s| s.update!(render_state: :failed) }

      described_class.call(scene: later, prompt: 'p1 novo')

      expect(later.reload.render_state).to eq('stale') # queued, not submitted
      expect(Vendors::OpenRouter::Actions::GenerateVideo).not_to have_received(:call)
    end

    it 'supersedes an IN-FLIGHT render: new prompt lands, charged, no duplicate submit' do
      allow(Vendors::OpenRouter::Actions::GenerateVideo).to receive(:call)
      scene.update!(render_state: :rendering, external_id: 'old_job')

      expect do
        described_class.call(scene: scene, prompt: 'novo rumo')
      end.to change { workspace.credit_transactions.debits.count }.by(1)

      expect(scene.reload.render_state).to eq('stale') # voided; poll re-submits on completion
      expect(scene.prompt).to eq('novo rumo')
      expect(Vendors::OpenRouter::Actions::GenerateVideo).not_to have_received(:call)
    end
  end

  describe Operations::Video::RemoveScene do
    let(:creative) do
      Operations::Creatives::Create.call(ticket: ticket, creative_type: 'ugc_video',
                                         source: :generated, status: :failed, provider: 'openrouter')
    end
    let!(:generation) do
      workspace.generations.create!(user: user, creative: creative, kind: :video, status: :failed,
                                    provider: 'openrouter', params: { mode: 'avatar' })
    end

    def build_scene(position, state, with_clip: false)
      scene = Operations::Video::Scenes::Create.call(creative: creative, position: position, mode: 'avatar',
                                                     prompt: "p#{position}", duration_seconds: 8, aspect_ratio: '9:16')
      scene.clip.attach(io: StringIO.new('MP4'), filename: "s#{position}.mp4", content_type: 'video/mp4') if with_clip
      scene.update!(render_state: state)
      scene
    end

    it 'removes the scene, reindexes positions, and recomposes when the rest is ready' do
      failed = build_scene(0, :failed)
      build_scene(1, :ready, with_clip: true)
      build_scene(2, :ready, with_clip: true)
      allow(Operations::Video::Compose).to receive(:call)

      described_class.call(scene: failed)

      expect(creative.video_scenes.ordered.pluck(:position)).to eq([0, 1])
      expect(generation.reload.status).to eq('processing') # reopened so Compose can complete it
      expect(Operations::Video::Compose).to have_received(:call).with(creative: creative)
    end

    it 'resumes the render chain when the cut unblocks pending scenes' do
      failed = build_scene(0, :failed)
      build_scene(1, :ready, with_clip: true)
      pending = build_scene(2, :stale)
      allow(Operations::Video::RenderScene).to receive(:call)

      described_class.call(scene: failed)

      expect(Operations::Video::RenderScene).to have_received(:call).with(scene: pending)
      expect(creative.reload.status).to eq('generating')
    end

    it 'refuses to remove the last remaining scene' do
      only = build_scene(0, :ready, with_clip: true)

      expect { described_class.call(scene: only) }
        .to raise_error(Operations::Errors::Invalid, /pelo menos uma cena/)
    end
  end

  describe Operations::Video::AddScene do
    let(:creative) do
      Operations::Creatives::Create.call(ticket: ticket, creative_type: 'ugc_video',
                                         source: :generated, status: :ready, provider: 'openrouter')
    end
    let!(:generation) do
      workspace.generations.create!(user: user, creative: creative, kind: :video, status: :completed,
                                    provider: 'openrouter', params: { mode: 'avatar', aspect_ratio: '9:16' })
    end

    def ready_scene(position)
      Operations::Video::Scenes::Create.call(creative: creative, position: position, mode: 'avatar',
                                             prompt: "p#{position}", duration_seconds: 8, aspect_ratio: '9:16')
                                       .tap do |s|
        s.clip.attach(io: StringIO.new('MP4'), filename: "s#{position}.mp4", content_type: 'video/mp4')
        s.update!(render_state: :ready)
      end
    end

    before { allow(Vendors::OpenRouter::Actions::GenerateVideo).to receive(:call).and_return('job_add') }

    it 'appends a scene at the end: charged, rendered right away, generation reopened' do
      ready_scene(0)
      allow(Vendors::Ffmpeg::FirstFrame).to receive(:call) # scene 0 untouched — but stub for safety

      scene = described_class.call(creative: creative, position: 1, prompt: 'Closing logo shot', caption: 'Final')

      expect(scene).to have_attributes(position: 1, render_state: 'rendering', mode: 'avatar', aspect_ratio: '9:16')
      expect(generation.reload.status).to eq('processing')
      debit = workspace.credit_transactions.debits.where(generation_id: generation.id).last
      expect(debit.description).to eq('Adicionar cena 2 do vídeo')
    end

    it 'inserts mid-video: shifts positions and re-links the follower (stale + charged)' do
      ready_scene(0)
      follower = ready_scene(1)

      described_class.call(creative: creative, position: 1, prompt: 'New middle beat')

      expect(creative.video_scenes.ordered.pluck(:position)).to eq([0, 1, 2])
      expect(follower.reload).to have_attributes(position: 2, render_state: 'stale')
      descriptions = workspace.credit_transactions.debits.where(generation_id: generation.id).pluck(:description)
      expect(descriptions).to include('Adicionar cena 2 do vídeo', 'Refazer cena do vídeo (continuidade)')
    end

    it 'refuses to exceed the scene budget cap' do
      Operations::Video::PlanScenes::MAX_SCENES.times { |i| ready_scene(i) }

      expect { described_class.call(creative: creative, position: 9, prompt: 'one too many') }
        .to raise_error(Operations::Errors::Invalid, /máximo/)
    end
  end

  describe Operations::Video::ReorderScene do
    let(:creative) do
      Operations::Creatives::Create.call(ticket: ticket, creative_type: 'ugc_video',
                                         source: :generated, status: :ready, provider: 'openrouter')
    end
    let!(:generation) do
      workspace.generations.create!(user: user, creative: creative, kind: :video, status: :completed,
                                    provider: 'openrouter', params: { mode: 'avatar' })
    end

    it 'moves the scene, reindexes and recomposes for free' do
      scenes = 3.times.map do |i|
        Operations::Video::Scenes::Create.call(creative: creative, position: i, mode: 'avatar',
                                               prompt: "p#{i}", duration_seconds: 8, aspect_ratio: '9:16')
                                         .tap do |s|
          s.clip.attach(io: StringIO.new('MP4'), filename: "s#{i}.mp4", content_type: 'video/mp4')
          s.update!(render_state: :ready)
        end
      end
      allow(Operations::Video::Compose).to receive(:call)

      expect do
        described_class.call(scene: scenes[2], to_position: 0)
      end.not_to change { workspace.credit_transactions.count }

      expect(creative.video_scenes.ordered.pluck(:id)).to eq([scenes[2].id, scenes[0].id, scenes[1].id])
      expect(Operations::Video::Compose).to have_received(:call).with(creative: creative)
    end
  end

  describe Operations::Video::CancelRender do
    let(:creative) do
      Operations::Creatives::Create.call(ticket: ticket, creative_type: 'ugc_video',
                                         source: :generated, status: :generating, provider: 'openrouter')
    end
    let!(:generation) do
      workspace.generations.create!(user: user, creative: creative, kind: :video, status: :processing,
                                    provider: 'openrouter', params: { mode: 'avatar' })
    end

    it 'abandons in-flight renders and settles through FailGeneration' do
      rendering = Operations::Video::Scenes::Create.call(creative: creative, position: 0, mode: 'avatar',
                                                         prompt: 'p0', duration_seconds: 8, aspect_ratio: '9:16')
                                                   .tap { |s| s.update!(render_state: :rendering, external_id: 'j1') }
      allow(Operations::Creatives::FailGeneration).to receive(:call)

      described_class.call(creative: creative)

      expect(rendering.reload.render_state).to eq('failed')
      expect(rendering.metadata['failure']).to eq('Cancelado pelo usuário')
      expect(Operations::Creatives::FailGeneration).to have_received(:call)
        .with(generation: generation, reason: 'Cancelado pelo usuário')
    end

    it 'refuses when nothing is processing' do
      generation.update!(status: :completed)
      expect { described_class.call(creative: creative) }
        .to raise_error(Operations::Errors::Invalid, /Nada para cancelar/)
    end
  end

  describe PollVideoSceneJob do
    let(:creative) do
      Operations::Creatives::Create.call(ticket: ticket, creative_type: 'ugc_video',
                                         source: :generated, status: :generating, provider: 'openrouter')
    end
    let(:scene) do
      Operations::Video::Scenes::Create.call(creative: creative, position: 0, mode: 'avatar',
                                             prompt: 'p0', duration_seconds: 8, aspect_ratio: '9:16')
    end

    it 're-submits a superseded (stale) scene instead of finalizing the outdated render' do
      scene.update!(render_state: :stale, external_id: 'old_job')
      allow(Operations::Video::RenderScene).to receive(:call)
      allow(Vendors::OpenRouter::Actions::GetVideoStatus).to receive(:call)

      described_class.new.perform(scene.id)

      expect(Operations::Video::RenderScene).to have_received(:call).with(scene: scene)
      expect(Vendors::OpenRouter::Actions::GetVideoStatus).not_to have_received(:call)
    end

    it 'posts a friendly failure explanation to the editor chat when a render is blocked' do
      scene.update!(render_state: :rendering, external_id: 'job_x')
      allow(Vendors::OpenRouter::Actions::GetVideoStatus).to receive(:call).and_return(
        completed: false, failed: true, failure_message: 'The output video may be related to copyright restrictions.'
      )

      described_class.new.perform(scene.id)

      last = creative.reload.chat_messages.last
      expect(last['kind']).to eq('alert')
      expect(last['content']).to include('cena 1', 'direitos autorais')
      expect(scene.reload.render_state).to eq('failed')
    end
  end
end
