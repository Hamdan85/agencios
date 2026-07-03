# frozen_string_literal: true

module Operations
  module Posts
    # Cancels a not-yet-live publication: the post is deleted before going live
    # (it can be scheduled again from the posting step). This is the single
    # authority for the "cancelable" rule — only `scheduled` / `failed` posts
    # qualify; a post already on the network must be UNPUBLISHED instead, so its
    # record and metrics survive. Callers: the posting step's cancel action
    # (Controllers::Posts::Destroy) and archiving (Operations::Tickets::Archive).
    class Cancel < Operations::Base
      def initialize(post:)
        @post = post
      end

      def call
        unless @post.status_scheduled? || @post.status_failed?
          raise Operations::Errors::Invalid,
                'Só é possível cancelar publicações agendadas ou com falha. Para tirar um post do ar, despublique-o.'
        end

        @post.destroy!
        @post
      end
    end
  end
end
