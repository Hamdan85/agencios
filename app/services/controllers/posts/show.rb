# frozen_string_literal: true

module Controllers
  module Posts
    # A single workspace post with its full metric history + creative experience.
    class Show < Base
      def initialize(params:)
        @params = params
      end

      def call
        post = Post.for_workspace(workspace)
                   .includes(:post_metrics, :social_account, ticket: { project: :client })
                   .find(@params[:id])
        { post: serialize(post, PostDetailSerializer) }
      end
    end
  end
end
