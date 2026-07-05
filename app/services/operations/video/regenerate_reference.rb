# frozen_string_literal: true

module Operations
  module Video
    # Regenerates a CHARACTER or SCENARIO asset from a new prompt: makes a fresh
    # reference image (Google Banana, charged as one image generation) and swaps it
    # into every scene's typed references — WITHOUT re-rendering. The scenes keep
    # their current clips (and video) until the user asks for a new render; the new
    # image is what the NEXT render of each scene will use.
    #
    # replace_url: the existing reference image to swap out (an asset already in the
    # video). Absent → the image is prepended as this role to every scene (the
    # identity described the look but had no image yet).
    #
    # Raises InsufficientCredits (→ 402) when the wallet can't cover the image, and
    # Invalid when the prompt is blank / the Banana generation returns nothing.
    class RegenerateReference < Operations::Base
      ROLES = %w[character scene].freeze

      def initialize(creative:, role:, prompt:, replace_url: nil)
        @creative    = creative
        @role        = ROLES.include?(role.to_s) ? role.to_s : 'character'
        @prompt      = prompt.to_s.strip
        @replace_url = replace_url.to_s.strip.presence
      end

      def call
        raise Operations::Errors::Invalid, 'Descreva o que gerar.' if @prompt.blank?

        generation = @creative.generation
        raise Operations::Errors::Invalid, 'Vídeo sem geração associada.' unless generation

        result = GenerateReference.call(
          generation: generation, role: @role, prompt: @prompt, aspect_ratio: aspect_ratio
        )
        raise Operations::Errors::Invalid, 'Não consegui gerar a imagem agora. Tente de novo.' if result.nil?

        swap_across_scenes!(result[:url])
        update_identity_and_description!(generation, result[:url])
        { url: result[:url], role: @role }
      end

      private

      def aspect_ratio
        @creative.video_scenes.first&.aspect_ratio.presence ||
          @creative.generation&.params&.dig('aspect_ratio')
      end

      # Replace the old image in place (keeping its role slot) or prepend the new
      # image as this role. Keeps the url list and the parallel role list in sync;
      # never re-renders (the scenes' clips stay as they are).
      def swap_across_scenes!(new_url)
        @creative.video_scenes.find_each do |scene|
          urls  = scene.reference_urls
          roles = Array(scene.metadata['reference_roles'])

          if @replace_url && (idx = urls.index(@replace_url))
            urls[idx]  = new_url
            roles[idx] = @role
          else
            urls  = [new_url] + urls
            roles = [@role] + roles
          end

          scene.update!(reference_image_urls: urls,
                        metadata: scene.metadata.merge('reference_roles' => roles))
        end
      end

      # Keep the locked identity in step with the new asset (so future renders use
      # it) and store the prompt as the asset's PT description (moving it off the
      # replaced image's key onto the new one), so the Elementos tab reflects it.
      def update_identity_and_description!(generation, new_url)
        field    = @role == 'character' ? 'character' : 'scenario'
        identity = (generation.params['identity'] || {}).merge(field => @prompt)
        identity['has_character'] = true if @role == 'character'

        descriptions = (generation.params['asset_descriptions'] || {}).dup
        descriptions.delete(@replace_url) if @replace_url
        descriptions[new_url] = @prompt

        generation.update!(params: generation.params.merge('identity' => identity,
                                                           'asset_descriptions' => descriptions))
      end
    end
  end
end
