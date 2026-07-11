# frozen_string_literal: true

module Operations
  module Video
    # Opens a video as an INTERVIEW instead of generating immediately: creates a
    # DRAFT creative (no generation, no credit hold, no render) that just holds
    # the intake + the chat, then runs the FIRST agent turn so the editor opens
    # already asking. The SAME chat agent (Chat::ResolveTurn / Prompts::VideoEditor)
    # drives the interview and later decides — via its `generate` action — when it
    # has enough context to actually build the video (or the user orders it).
    #
    # This is the studio "new video" flow. Autopilot / ticket flows still
    # generate immediately through Operations::Creatives::GenerateUgcVideo.
    class StartInterview < Operations::Base
      def initialize(workspace:, ticket: nil, client_id: nil, mode: nil, prompt: nil,
                     voice: nil, aspect_ratio: nil, duration: nil, reference_image_urls: [],
                     reference_descriptions: {}, with_audio: nil, creative_type: nil)
        @workspace     = workspace
        @ticket        = ticket
        @client_id     = client_id
        @mode          = mode
        @prompt        = prompt.to_s.strip.presence
        @voice         = voice
        @aspect_ratio  = aspect_ratio
        @duration      = duration
        @ref_urls      = Array(reference_image_urls).map { |u| u.to_s.strip }.reject(&:blank?)
        # { url => "what the user says this file is" }, kept for the urls in play.
        @ref_descriptions = (reference_descriptions || {}).to_h.select { |u, _| @ref_urls.include?(u.to_s) }
        @with_audio    = with_audio.nil? ? true : ActiveModel::Type::Boolean.new.cast(with_audio)
        @creative_type = creative_type
      end

      def call
        client = @client_id.present? ? @workspace.clients.find_by(id: @client_id) : nil
        ensure_client_active!(client) if client
        ctx = ::Tickets::CreativeContext.for(@ticket, creative_type: type, client: client)

        aspect   = @aspect_ratio.presence || ctx.aspect_ratio.presence || '9:16'
        duration = clamp_duration(@duration)
        # Seed the type from the attached references (photos ⇒ product) — the
        # storyboard director makes the final call at generation time.
        mode = VideoConfig::MODES.include?(@mode.to_s) ? @mode.to_s : (@ref_urls.any? ? 'product' : 'avatar')

        creative = Operations::Creatives::Create.call(
          ticket: @ticket, client: client, creative_type: ctx.creative_type || type,
          source: :generated, status: :draft, provider: 'openrouter',
          metadata: {
            mode: mode, aspect_ratio: aspect, duration: duration, with_audio: @with_audio,
            quality: 'draft', phase: 'interview',
            # Everything the `generate` action needs to launch once the interview
            # has gathered enough context.
            intake: { mode: mode, brief: @prompt, voice: @voice, client_id: client&.id,
                      aspect_ratio: aspect, duration: duration, with_audio: @with_audio,
                      reference_image_urls: @ref_urls,
                      reference_descriptions: @ref_descriptions.presence }.compact
          }
        )

        # The user's own brief is the FIRST message in the editor (with any
        # reference images they attached shown as thumbnails), so the chat opens
        # with what they wrote — then the agent responds to it.
        if @prompt.present? || @ref_urls.any?
          creative.push_chat_message(role: :user, content: @prompt.to_s, images: @ref_urls)
          creative.save!
        end

        # The agent's opening turn (kickoff): it reads the brief above and either
        # asks a clarifying question or, with enough context, proceeds.
        Operations::Video::Chat::ResolveTurn.call(creative: creative, message: nil, kickoff: true)
        creative.reload
      end

      private

      def type
        @creative_type.presence || @ticket&.creative_type.presence || 'ugc_video'
      end

      def clamp_duration(seconds)
        max = VideoConfig.instance.max_duration
        (seconds.presence || Pricing::DEFAULT_VIDEO_SECONDS).to_i.clamp(1, max)
      end
    end
  end
end
