# frozen_string_literal: true

module Vendors
  module Heygen
    module Actions
      # Create a "creator-from-a-photo" avatar (Photo Avatar / Avatar IV).
      # `POST /v3/avatars` with `{ type: "photo", name:, file: { type:, url|asset_id } }`.
      #
      # Upload the source image first via `UploadAsset` (→ asset_id) or pass a
      # public `url`. Returns the new `avatar_id`, usable in GenerateVideo with the
      # Avatar-IV-only fields (`motion_prompt`, `expressiveness`).
      #
      # See docs/integrations/heygen.md §4.
      class CreatePhotoAvatar
        def self.call(...) = new(...).call

        def initialize(name:, url: nil, asset_id: nil, client: nil)
          @name     = name
          @url      = url
          @asset_id = asset_id
          @client   = client || Client.new
        end

        def call
          file =
            if @asset_id
              { type: "asset_id", asset_id: @asset_id }
            else
              { type: "url", url: @url }
            end

          body = @client.post("/v3/avatars", { type: "photo", name: @name, file: file })
          data = body["data"] || body
          data["avatar_id"] || data["id"]
        end
      end
    end
  end
end
