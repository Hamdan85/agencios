# frozen_string_literal: true

module Operations
  module Video
    # Adds an EXISTING media reference (an uploaded file or a library asset) to the
    # video as a typed element — prepended to every scene's references so the NEXT
    # render of each scene uses it. No re-render (the scenes keep their clips until
    # the user asks for one), mirroring RegenerateReference.
    #
    # url: the public reference URL (from Uploads::References or the asset library).
    # role: its job in the render (Operations::Video::References roles).
    # description: an optional PT note shown in the Elementos tab.
    class AddReference < Operations::Base
      def initialize(creative:, role:, url:, description: nil)
        @creative     = creative
        @role         = References::ROLES.include?(role.to_s) ? role.to_s : 'reference'
        @url          = url.to_s.strip
        @description  = description.to_s.strip.presence
      end

      def call
        raise Operations::Errors::Invalid, 'Referência inválida.' if @url.blank?

        kind = References.kind_for(@url)
        @creative.video_scenes.find_each do |scene|
          next if scene.reference_urls.include?(@url) # already present on this scene

          roles = Array(scene.metadata['reference_roles'])
          # Keep the descriptions array index-aligned before prepending this one,
          # so the render manifest tells the model what the file is.
          descriptions = Array.new(scene.reference_urls.size) { |i| Array(scene.metadata['reference_descriptions'])[i] }
          scene.update!(
            reference_image_urls: [@url] + scene.reference_urls,
            metadata: scene.metadata.merge('reference_roles' => [@role] + roles,
                                           'reference_descriptions' => [@description] + descriptions)
          )
        end

        store_description!
        { url: @url, role: @role, kind: kind }
      end

      private

      def store_description!
        return unless @description

        generation = @creative.generation
        return unless generation

        descriptions = (generation.params['asset_descriptions'] || {}).merge(@url => @description)
        generation.update!(params: generation.params.merge('asset_descriptions' => descriptions))
      end
    end
  end
end
