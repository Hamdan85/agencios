# frozen_string_literal: true

module Operations
  module Video
    # The TYPED media-reference system for video generation — the single source
    # of truth mapping each attached reference to an explicit ROLE the model can
    # act on. An unlabeled pile of files reads as "put all of this in the video";
    # a typed manifest tells the model exactly which job each input has.
    #
    # Every reference gets a stable IDENTIFIER derived from its media kind, role
    # and version — `img_character_v1`, `img_style_v1`, `vid_camera_ref_v1` — the
    # SAME identifier the code stores, the manifest lists and the scene prompt
    # cites, so the three can never drift apart. Identifiers never depend on the
    # original upload filename.
    #
    # Roles (one job each — never blended):
    #   character — recurring character/person identity (face, wardrobe, pose)
    #   avatar    — the creator/spokesperson (system asset from Settings)
    #   product   — product fidelity (shape, colors, label)
    #   scene     — setting/location/environment
    #   style     — palette, texture, lighting, aesthetic (never its subject)
    #   camera    — camera movement, framing, rhythm (video reference)
    #   motion    — action, choreography, movement timing (video reference)
    #   logo      — the brand mark (context only)
    #   reference — generic user attachment with no declared job (legacy default)
    module References
      module_function

      ROLES = %w[character avatar product scene style camera motion logo reference].freeze

      # Roles the chat/editor agent may assign to a user attachment (system
      # assets — avatar/logo — are attached by the pipeline, never declared).
      ASSIGNABLE_ROLES = %w[character product scene style camera motion reference].freeze

      KINDS = %w[img vid].freeze

      # Ordering when a scene's references are first assembled: the SUBJECT
      # (who/what must stay faithful) leads, then world/style/movement guides,
      # generic attachments, and the logo last (context-only).
      ROLE_PRIORITY = {
        'character' => 0, 'avatar' => 0, 'product' => 1, 'scene' => 2,
        'style' => 3, 'camera' => 4, 'motion' => 5, 'reference' => 6, 'logo' => 7
      }.freeze

      # What each role MEANS to the render model: its one job plus the negative
      # constraint that stops the classic failure ("use the style image's subject",
      # "invent a variant logo"). Compiled into the manifest by DecoratePrompt.
      ROLE_CONTRACTS = {
        'character' => 'CHARACTER identity reference — the recurring character must match this ' \
                       'face, hair, body and wardrobe EXACTLY in every shot. Never redesign, ' \
                       'restyle or swap the character.',
        'avatar'    => 'the CREATOR (the spokesperson) — the person on camera must faithfully ' \
                       'match this face and appearance. Never swap or alter the face.',
        'product'   => 'PRODUCT reference — keep the product faithful: exact shape, colors, ' \
                       'materials and label. Never distort, restyle or invent variants.',
        'scene'     => 'SETTING reference — match this location/environment: its space, ' \
                       'architecture, light and mood. Never copy people or products from it.',
        'style'     => 'STYLE reference — apply ONLY its palette, lighting, texture and overall ' \
                       'aesthetic. Never copy its subject, people or composition.',
        'camera'    => 'CAMERA reference (video) — replicate ONLY its camera movement, framing ' \
                       'and pacing. Ignore its subject and content entirely.',
        'motion'    => 'MOTION reference (video) — match ONLY its action, choreography and ' \
                       'movement timing. Ignore its subject, style and setting.',
        'logo'      => 'the brand LOGO — whenever the scene shows branding (an end card, a lower-third, ' \
                       'signage, an on-screen overlay, a screen/UI), render THIS EXACT logo, faithfully ' \
                       'reproduced (never invent, redraw or alter it). If a scene has no branding moment, ' \
                       'do not force the logo in.',
        'reference' => 'a general REFERENCE the user attached (style / subject / scene guidance) ' \
                       '— draw on it for what the scene should look like; use it only where the ' \
                       'prompt calls for it.'
      }.freeze

      VIDEO_EXTENSIONS = %w[mp4 mov webm m4v].freeze

      # The stable identifier: `img_character_v1`, `vid_camera_ref_v1`. Video
      # kinds carry a `_ref` suffix (they are always guides, never content).
      def identifier(role:, kind:, version:)
        "#{kind}_#{role}#{kind == 'vid' ? '_ref' : ''}_v#{version}"
      end

      # Media kind from the URL's file extension ('img' | 'vid'). Blob URLs keep
      # the original filename, so the extension survives upload; anything
      # unrecognized defaults to an image (every current engine accepts images).
      def kind_for(url)
        ext = File.extname(URI.parse(url.to_s).path.to_s).delete('.').downcase
        VIDEO_EXTENSIONS.include?(ext) ? 'vid' : 'img'
      rescue URI::InvalidURIError
        'img'
      end

      # Normalizes raw { url:, role:, kind:, description: } entries into the
      # canonical typed set: valid roles only, priority-SORTED (stable), kind
      # inferred from the URL when absent, and a version + identifier assigned per
      # (kind, role) in final order. This runs when a scene's references are
      # ASSEMBLED — the stored url/role arrays keep this order, so the submitted
      # inputs, the manifest and the identifiers always line up. `description` is
      # the USER's own words for what the file IS ("what is this document?") —
      # carried verbatim into the manifest so the model/agent knows how to use it.
      def build(entries)
        typed = Array(entries).filter_map do |e|
          url = e[:url].to_s.strip
          next if url.blank?

          role = ROLES.include?(e[:role].to_s) ? e[:role].to_s : 'reference'
          { url: url, role: role, kind: KINDS.include?(e[:kind].to_s) ? e[:kind].to_s : kind_for(url),
            description: e[:description].to_s.strip.presence }
        end
        number(typed.sort_by.with_index { |e, i| [ROLE_PRIORITY.fetch(e[:role], 6), i] })
      end

      # Assigns versions/identifiers by occurrence WITHOUT re-sorting — used for
      # entries whose order is already persisted (a stored scene): re-sorting
      # here would desync the manifest from the submitted input order.
      def number(entries)
        counters = Hash.new(0)
        entries.map do |e|
          version = counters[[e[:kind], e[:role]]] += 1
          e.merge(id: identifier(role: e[:role], kind: e[:kind], version: version))
        end
      end

      # The manifest lines for the render prompt: position → identifier → the
      # role's contract → the USER's description of the file. Position anchors the
      # identifier to the attached input (the API carries no names); the identifier
      # is what scene prompts cite. The user's own description ("what is this?") is
      # appended so the model uses the file the way the user meant it, not just by
      # a generic role guess.
      def manifest_lines(entries)
        entries.map.with_index do |e, i|
          base = "input #{i + 1} = #{e[:id]}: #{ROLE_CONTRACTS.fetch(e[:role], ROLE_CONTRACTS['reference'])}"
          e[:description].present? ? "#{base} The user describes this file as: \"#{e[:description]}\"." : base
        end
      end

      # One compact "id (role — description)" listing — the agent-facing view of a
      # scene's references (chat context, storyboard context).
      def summary(entries)
        entries.map do |e|
          e[:description].present? ? "#{e[:id]} (#{e[:role]} — #{e[:description]})" : "#{e[:id]} (#{e[:role]})"
        end.join(', ')
      end

      # A user/agent-declared role for an attachment, constrained to the
      # assignable set (system assets can't be declared); generic fallback.
      def assignable_role(role)
        ASSIGNABLE_ROLES.include?(role.to_s) ? role.to_s : 'reference'
      end
    end
  end
end
