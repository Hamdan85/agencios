# frozen_string_literal: true

module Operations
  module Video
    # Removes a video element: drops a reference image/video from every scene (so
    # the NEXT render no longer uses it), or clears a locked-identity field when
    # the element is an image-less character/scenario. No re-render.
    #
    # key: the asset key from AssetList — a reference URL, or "identity:<field>".
    class RemoveReference < Operations::Base
      IDENTITY_KEY = /\Aidentity:(character|scenario)\z/

      def initialize(creative:, key:)
        @creative = creative
        @key      = key.to_s.strip
      end

      def call
        raise Operations::Errors::Invalid, I18n.t('operations.video.errors.remove_reference.invalid_element') if @key.blank?

        if (field = @key[IDENTITY_KEY, 1])
          clear_identity_field!(field)
        else
          drop_url_from_scenes!(@key)
          drop_description!(@key)
        end
        true
      end

      private

      # Remove the URL from every scene, keeping the parallel role list aligned.
      def drop_url_from_scenes!(url)
        @creative.video_scenes.find_each do |scene|
          idx = scene.reference_urls.index(url)
          next if idx.nil?

          urls  = scene.reference_urls.dup.tap { |a| a.delete_at(idx) }
          roles = Array(scene.metadata['reference_roles']).dup.tap { |a| a.delete_at(idx) }
          scene.update!(reference_image_urls: urls,
                        metadata: scene.metadata.merge('reference_roles' => roles))
        end
      end

      def clear_identity_field!(field)
        generation = @creative.generation
        return unless generation

        identity = (generation.params['identity'] || {}).except(field)
        identity['has_character'] = false if field == 'character'
        generation.update!(params: generation.params.merge('identity' => identity))
      end

      def drop_description!(url)
        generation = @creative.generation
        return unless generation && generation.params['asset_descriptions'].is_a?(Hash)

        descriptions = generation.params['asset_descriptions'].except(url)
        generation.update!(params: generation.params.merge('asset_descriptions' => descriptions))
      end
    end
  end
end
