# frozen_string_literal: true

module Vendors
  module Linkedin
    module Actions
      # POST https://api.linkedin.com/rest/posts — creates a text/image/video/
      # article post. Author is urn:li:person:{id} (member) or
      # urn:li:organization:{id} (org). Success = 201; the new post URN is in the
      # `x-restli-id` response header.
      # See docs/integrations/linkedin.md §6.
      class CreatePost
        def self.call(...) = new(...).call

        # @param author_urn [String] urn:li:person:{id} or urn:li:organization:{id}
        # @param commentary [String] the post body (supports @mentions, #hashtags)
        # @param media [Hash, nil] e.g. { "id" => "urn:li:image:...", "altText" => "..." }
        # @param article [Hash, nil] { source:, title:, description:, thumbnail? }
        def initialize(social_account:, author_urn:, commentary:, media: nil, article: nil, visibility: 'PUBLIC')
          @social_account = social_account
          @author_urn = author_urn
          @commentary = commentary
          @media = media
          @article = article
          @visibility = visibility
        end

        # Returns { post_urn: "urn:li:share:..." }.
        def call
          client = Vendors::Linkedin::Client.new(social_account: @social_account)
          response = client.rest_post_raw('/rest/posts', payload)

          unless response.status == 201
            raise Vendors::Base::Error.new(
              'LinkedIn create post failed', status: response.status, body: response.body
            )
          end

          { post_urn: response.headers['x-restli-id'] }
        end

        private

        def payload
          body = {
            'author' => @author_urn,
            'commentary' => @commentary.to_s,
            'visibility' => @visibility,
            'distribution' => {
              'feedDistribution' => 'MAIN_FEED',
              'targetEntities' => [],
              'thirdPartyDistributionChannels' => []
            },
            'lifecycleState' => 'PUBLISHED',
            'isReshareDisabledByAuthor' => false
          }

          if @media
            body['content'] = { 'media' => @media }
          elsif @article
            body['content'] = { 'article' => @article }
          end

          body
        end
      end
    end
  end
end
