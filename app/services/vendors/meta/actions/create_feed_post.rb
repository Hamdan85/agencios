# frozen_string_literal: true

module Vendors
  module Meta
    module Actions
      # FB Page feed post — POST /{page_id}/feed (facebook.md §6a/§6c).
      # Text/link posts, or a multi-photo gallery via attached_media. Schedule
      # with published=false + scheduled_publish_time (10min–30d out).
      # Returns { "id" => "{page_id}_{post_id}" }.
      class CreateFeedPost
        def self.call(...) = new(...).call

        # attached_media: array of { media_fbid: "..." } hashes (multi-photo).
        def initialize(social_account:, message: nil, link: nil, attached_media: nil,
                       published: true, scheduled_publish_time: nil, client: nil)
          @social_account = social_account
          @message = message
          @link = link
          @attached_media = attached_media
          @published = published
          @scheduled_publish_time = scheduled_publish_time
          @client = client || Vendors::Meta::Client.new(social_account)
        end

        def call
          params = {
            message: @message,
            link: @link,
            published: @published,
            scheduled_publish_time: @scheduled_publish_time
          }
          Array(@attached_media).each_with_index do |media, i|
            params[:"attached_media[#{i}]"] = media.to_json
          end

          @client.post("/#{@social_account.page_id}/feed", params:)
        end
      end
    end
  end
end
