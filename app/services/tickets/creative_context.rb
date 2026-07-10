# frozen_string_literal: true

module Tickets
  # The creative-generation presenter: the single seam that gathers everything
  # the generators and prompt builders need — the client + brand identity +
  # positioning, the ticket scope (ideation/scoping/production fields), the
  # status-scoped AI summary, and the target creative type's spec (dimensions /
  # aspect / safe areas / prompt scaffold).
  #
  # Works with OR without a ticket: the studio passes an explicit `client:` and
  # `overrides:` (topic / objective / text / url source), while ticket-driven
  # generation derives them from the funnel. Overrides always win over scope.
  class CreativeContext
    def self.for(ticket, creative_type: nil, client: nil, overrides: {})
      new(ticket: ticket, creative_type: creative_type, client: client, overrides: overrides)
    end

    def initialize(ticket:, creative_type: nil, client: nil, overrides: {})
      @ticket          = ticket
      @creative_type   = (creative_type || ticket&.creative_type).to_s.presence
      @explicit_client = client
      @overrides       = (overrides || {}).symbolize_keys
    end

    attr_reader :ticket, :creative_type

    def client    = @explicit_client || ticket&.project&.client
    def workspace = ticket&.workspace || client&.workspace || Current.workspace

    # --- creative spec (proportions) ------------------------------------------

    def spec = (creative_type && Creatives.spec_for(creative_type)) || {}

    def width  = spec[:width]
    def height = spec[:height]
    def dimensions = [width, height].compact

    def aspect_ratio = spec[:aspect].presence || '1:1'

    def image_aspect_ratio
      supported = Vendors::OpenRouter::Image::SUPPORTED_ASPECT_RATIOS
      return aspect_ratio if supported.include?(aspect_ratio)

      if portrait?
        '3:4'
      else
        (landscape? ? '4:3' : '1:1')
      end
    end

    def portrait?  = width && height && height > width
    def landscape? = width && height && width > height

    # --- scope (funnel fields) + overrides ------------------------------------

    def ideation   = ticket&.fields_for('ideation') || {}
    def scoping    = ticket&.fields_for('scoping') || {}
    def production = ticket&.fields_for('production') || {}

    def brief          = ideation['brief']
    def persona        = ideation['target_persona']
    def content_pillar = ideation['content_pillar']
    def script         = @overrides[:script].presence || scoping['script']
    def caption        = production['caption']

    # Production-stage direction that guides the creative (references, what to
    # show/avoid, mandatory elements). Rich text — strip HTML so the prompt gets
    # clean prose. Fed into every generator (image/carousel/video copy).
    def production_scope = strip_html(production['production_scope'])

    URL_RE = %r{https?://\S+}i

    # Reference material the team attached in ideation (+ any override). Free text
    # is kept; URLs are extracted so generators can fetch/read them and feed the
    # whole into the content generators.
    def references
      vals = Array(@overrides[:references]) + Array(ideation['references'])
      vals.map { |v| v.to_s.strip }.reject(&:blank?).uniq
    end

    def reference_urls
      references.flat_map { |r| r.scan(URL_RE) }.uniq
    end

    def objective
      @overrides[:objective].presence || ideation['objective']
    end

    # --- client positioning (for planning direction) --------------------------

    def positioning = client&.positioning? ? client.positioning : {}

    # Hard "avoid" constraints ("Restrições / o que evitar"). These are the one
    # positioning field that is constraint-shaped and safe to hand the RENDER
    # model as a do-not list (props/wardrobe/set the model invents beyond the
    # scene prompt could otherwise violate them). Array or string.
    def guardrails
      val = positioning['guardrails']
      Array(val).map { |v| v.to_s.strip }.reject(&:blank?).join('; ').presence
    end

    # Compact PT-BR positioning briefing for the video PLANNER (storyboard/editor)
    # — the fields that shape what the video says and shows. Kept short so it
    # frames the plan without bloating the system prompt.
    POSITIONING_BRIEF_KEYS = {
      'statement' => 'Posicionamento', 'one_liner' => 'O que faz',
      'value_proposition' => 'Proposta de valor', 'target_audience' => 'Público',
      'audience_pain' => 'Dor da audiência', 'differentiators' => 'Diferenciais',
      'guardrails' => 'Evitar'
    }.freeze

    def positioning_brief
      POSITIONING_BRIEF_KEYS.filter_map do |key, label|
        value = positioning[key]
        value = value.join('; ') if value.is_a?(Array)
        next if value.blank?

        "#{label}: #{value.to_s.strip}"
      end.join("\n").presence
    end

    # The message/source material: an explicit text/url-extracted source wins,
    # then the scoping copy brief. A regeneration folds the client's requested
    # changes in here so BOTH the image prompt (Escopo) and the carousel copy
    # incorporate the feedback.
    def copy_brief
      base = @overrides[:source_text].presence || @overrides[:text].presence || scoping['copy_brief']
      notes = @overrides[:revision_notes].to_s.strip.presence
      return base unless notes

      [base, "Ajustes solicitados pelo cliente: #{notes}"].compact.join('. ')
    end

    def channels
      vals = Array(scoping['channels']).reject(&:blank?)
      vals.presence || Array(ticket&.channels).reject(&:blank?)
    end

    def summary = ticket&.summary_for(ticket.status)

    # A SHORT one-line subject for prompts/headlines — never the full source body
    # (the body lives in copy_brief). Falls back to the first sentence of the
    # source, then the ticket title.
    def topic
      explicit = [@overrides[:topic], @overrides[:idea], @overrides[:prompt]].map do |v|
        v.to_s.strip.presence
      end.compact.first
      base = explicit || objective.presence || first_sentence(copy_brief) || brief.presence || ticket&.display_title
      base.to_s.strip[0, 160]
    end

    def first_sentence(text)
      return nil if text.blank?

      text.to_s.split(/(?<=[.!?])\s+/).first.to_s.strip[0, 120].presence
    end

    # --- brand identity (client → workspace fallback) -------------------------

    def brand_name      = client&.name.presence || workspace&.name
    def brand_voice     = client&.brand_voice.presence || workspace&.brand_voice.presence || 'tom profissional, próximo e criativo'
    def brand_handle    = client&.default_handle.presence || workspace&.default_handle.presence
    def brand_primary   = client&.brand_primary_color.presence || workspace&.brand_primary_color.presence || '#7C3AED'
    def brand_secondary = client&.brand_secondary_color.presence || workspace&.brand_secondary_color.presence || '#F59E0B'

    def logo   = attachment(:logo)
    def avatar = attachment(:default_creator_avatar)

    # --- brand reference images (for multimodal image models) -----------------

    # The brand logo + creator avatar downloaded as labeled reference payloads
    # handed to the image model. The image model is multimodal: it SEES these and
    # decides — per the prompt — whether to use them (place the logo, feature the
    # creator). Empty when neither asset is attached. Pair with
    # REFERENCE_ASSETS_DIRECTIVE so the model knows they're optional.
    def reference_images
      [
        reference_image(logo,   'MARCA (logotipo)'),
        reference_image(avatar, 'CRIADOR (avatar/rosto do porta-voz)')
      ].compact
    end

    # Public URLs of the brand's visual-identity assets, for URL-based vendors
    # (the video API takes reference URLs, not bytes). SVGs and other non-raster
    # types are skipped — the same guard as reference_image.
    def brand_logo_url   = raster_url(logo)
    def brand_avatar_url = raster_url(avatar)

    # Tells the model the attached references are OPTIONAL — use them only when
    # the requested content calls for them, never force them in.
    REFERENCE_ASSETS_DIRECTIVE =
      'Referências visuais anexadas (logotipo da marca e/ou avatar do criador): ' \
      'use-as SOMENTE se o conteúdo pedido combinar com elas — aplique o logotipo ' \
      'quando a cena pedir a presença da marca e retrate o criador quando a cena ' \
      'tiver uma pessoa/porta-voz. Se o prompt não pedir marca nem pessoa, IGNORE ' \
      'as referências por completo e não as force na imagem.'

    # --- prompt + image helpers -----------------------------------------------

    def prompt_context
      {
        topic: topic, objective: objective, brief: brief, persona: persona,
        copy_brief: copy_brief, script: script, content_pillar: content_pillar,
        production_scope: production_scope, channels: channels.join(', '),
        summary: summary, caption: caption,
        creative_type: creative_type, aspect: aspect_ratio,
        references: references.presence&.join('; '),
        width: width, height: height
      }.compact
    end

    def image_prompt(base = nil)
      [
        base.to_s.strip.presence || topic.presence,
        copy_brief.present? ? "Escopo: #{copy_brief}" : nil,
        production_scope.present? ? "Direção de produção: #{production_scope}" : nil,
        content_pillar.present? ? "Pilar: #{content_pillar}" : nil,
        spec[:prompt_scaffold],
        brand_descriptor,
        TEXT_RENDERING_DIRECTIVE
      ].compact.join('. ')
    end

    # Image models (Imagen/Banana) routinely hallucinate garbled, misspelled, or
    # nonsensical lettering. Force a binary choice: only render text that is real,
    # correctly spelled, and meaningful (in Brazilian Portuguese unless the copy
    # clearly calls for another language) — otherwise render NO text at all.
    # Overlaid headlines/CTAs are composited later, so a clean, text-free image is
    # always preferable to fake typography.
    TEXT_RENDERING_DIRECTIVE =
      'Regra de texto: qualquer palavra ou letra visível na imagem DEVE ser ' \
      'real, ortograficamente correta e fazer sentido (em português do Brasil, ' \
      'salvo se a copy pedir outro idioma). Se não for possível garantir texto ' \
      'legível e correto, NÃO escreva absolutamente nenhum texto — prefira uma ' \
      'imagem totalmente sem texto a letras falsas, embaralhadas ou sem sentido. ' \
      "Nunca invente logotipos, marcas d'água ou caracteres decorativos ilegíveis."

    def brand_descriptor
      bits = []
      bits << "Marca: #{brand_name}" if brand_name.present?
      bits << "tom #{brand_voice}" if brand_voice.present?
      colors = [brand_primary, brand_secondary].compact.join(' e ')
      bits << "paleta #{colors}" if colors.present?
      bits.join(', ')
    end

    private

    # Rich-text fields are stored as HTML; prompts want clean prose.
    def strip_html(value)
      return nil if value.blank?

      ActionController::Base.helpers.strip_tags(value.to_s).squish.presence
    end

    def attachment(name)
      [client, workspace].compact.each do |owner|
        att = owner.public_send(name) if owner.respond_to?(name)
        return att if att&.attached?
      end
      nil
    end

    # Public blob URL of a raster brand asset (nil for SVG/missing/unreadable).
    def raster_url(att)
      return nil unless att.respond_to?(:attached?) && att.attached?

      ct = att.blob&.content_type.to_s.downcase
      return nil unless Vendors::OpenRouter::Image::SUPPORTED_IMAGE_MIME_TYPES.include?(ct)

      Rails.application.routes.url_helpers.rails_blob_url(att, host: SystemConfig.app_host)
    rescue StandardError
      nil
    end

    # Download a brand attachment into a labeled reference payload for the image
    # model. Returns nil (skipped) when the asset is missing or unreadable.
    def reference_image(att, label)
      return nil if att.nil?
      return nil if att.respond_to?(:attached?) && !att.attached?

      ct = att.respond_to?(:content_type) ? att.content_type : att.blob&.content_type
      ct = ct.presence || 'image/png'

      # Image models only accept a fixed set of raster MIME types. Brand logos are
      # frequently SVGs, which the vendor rejects — skip them rather than 500.
      unless Vendors::OpenRouter::Image::SUPPORTED_IMAGE_MIME_TYPES.include?(ct.to_s.downcase)
        Rails.logger.info("[CreativeContext] skipping unsupported reference image (#{ct}) for #{label}")
        return nil
      end

      { label: label, bytes: att.download, content_type: ct }
    rescue StandardError => e
      Rails.logger.warn("[CreativeContext] reference image read failed: #{e.message}")
      nil
    end
  end
end
