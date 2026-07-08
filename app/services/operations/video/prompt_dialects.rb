# frozen_string_literal: true

module Operations
  module Video
    # The SERIALIZATION layer for the cinematic spine: one dialect per engine turns
    # a PromptSpec into the exact prompt shape that model wants. The spine is
    # universal (PromptSpec); only the rendering differs here.
    #
    # Which dialect an engine uses is derived from its slug (VideoConfig.model_for):
    #   seedance → Seedance   (our primary engine)
    #   veo      → Veo        (rich cinematic paragraph)
    #   kling    → Kling      (camera-first structured NL)
    #   anything else → Default (= Veo paragraph, the safe fallback)
    #
    # Grounded in each engine's documented prompt best-practices (Google Cloud/
    # DeepMind for Veo, BytePlus/Replicate for Seedance, fal for Kling).
    module PromptDialects
      module_function

      # Map a model slug (or an already-resolved dialect symbol) to a serializer.
      def for(dialect)
        case dialect&.to_sym
        when :seedance then Seedance
        when :veo      then Veo
        when :kling    then Kling
        else Default
        end
      end

      # The dialect symbol for a model slug — the video engines we actually run
      # (Seedance) or may switch to (Veo, Kling); everything else falls back.
      def dialect_for_model(slug)
        s = slug.to_s.downcase
        return :seedance if s.include?('seedance')
        return :veo      if s.include?('veo')
        return :kling    if s.include?('kling')

        :default
      end

      # Serialize a spec in its own dialect.
      def serialize(spec)
        self.for(spec.dialect).call(spec)
      end
    end
  end
end
