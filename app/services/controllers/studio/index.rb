# frozen_string_literal: true

module Controllers
  module Studio
    # Creative studio landing: the type picker + brand context + recent generations.
    class Index < Base
      def call
        {
          creative_types: ::Creatives.all_specs,
          brand: brand_context,
          recent_generations: serialize_collection(recent_generations, GenerationSerializer)
        }
      end

      private

      def brand_context
        {
          handle: workspace.default_handle,
          primary: workspace.brand_primary_color,
          secondary: workspace.brand_secondary_color,
          voice: workspace.brand_voice
        }
      end

      def recent_generations
        workspace.generations.order(created_at: :desc).limit(12)
      end
    end
  end
end
