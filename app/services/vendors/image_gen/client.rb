# frozen_string_literal: true

module Vendors
  module ImageGen
    # Image-generation API wrapper (SPECIFICATION.md §5 — an image model that
    # takes a prompt + brand refs and returns an image URL).
    #
    # Structured against a Replicate-style prediction API: create a prediction
    # (`POST /v1/predictions`), then poll it (`GET /v1/predictions/{id}`) until it
    # `succeeded`/`failed`, reading the output URL off the finished prediction.
    # To swap providers (Replicate → fal.ai → OpenAI Images → a self-hosted SDXL),
    # change BASE_URL + the create/poll payload shape in the two private methods
    # below; the public `generate_image` contract stays the same. (See the
    # "PROVIDER SWAP POINT" markers.)
    #
    # Auth: Bearer token from credentials (`image_gen.api_key`) with ENV fallback
    # (`IMAGE_GEN_API_KEY`). Base URL is configurable via `image_gen.base_url` /
    # `IMAGE_GEN_BASE_URL`.
    class Client < Vendors::Base
      DEFAULT_BASE_URL = "https://api.replicate.com"
      # PROVIDER SWAP POINT: the model/version identifier the create call targets.
      DEFAULT_MODEL_VERSION = "black-forest-labs/flux-1.1-pro"

      POLL_INTERVAL = 1.5
      MAX_POLLS     = 60

      def initialize(api_key: nil, base_url: nil, model_version: nil)
        @api_key  = api_key || credential(:image_gen, :api_key, env: "IMAGE_GEN_API_KEY")
        @base_url = base_url || credential(:image_gen, :base_url, env: "IMAGE_GEN_BASE_URL") || DEFAULT_BASE_URL
        @model_version = model_version ||
                         credential(:image_gen, :model_version, env: "IMAGE_GEN_MODEL_VERSION") ||
                         DEFAULT_MODEL_VERSION
      end

      # Generates one image. Returns { url:, external_id: }.
      # `ref_images` are public URLs of brand references the model conditions on.
      def generate_image(prompt:, ref_images: [], size: "1080x1350")
        require_credential!(@api_key, "image_gen.api_key")

        prediction = create_prediction(prompt: prompt, ref_images: ref_images, size: size)
        id = prediction["id"]
        prediction = await(prediction)

        {
          url: output_url(prediction),
          external_id: id
        }
      end

      private

      # PROVIDER SWAP POINT — create a prediction. Replicate accepts
      # `{ version, input: {...} }` and returns `{ id, status, urls, output }`.
      def create_prediction(prompt:, ref_images:, size:)
        width, height = parse_size(size)
        input = {
          prompt: prompt,
          width: width,
          height: height,
          aspect_ratio: aspect_ratio(width, height),
          output_format: "png"
        }
        # Brand references — fed to image-prompting / img2img conditioning.
        input[:image_prompt] = ref_images.first if ref_images.present?
        input[:reference_images] = ref_images if ref_images.present?

        handle(connection.post("/v1/predictions", { version: @model_version, input: input }))
      end

      # Poll until the prediction is terminal. `Prefer: wait` could collapse this
      # to a single blocking call on Replicate, but we poll explicitly so the
      # contract holds across providers.
      def await(prediction)
        polls = 0
        while in_progress?(prediction) && polls < MAX_POLLS
          sleep(POLL_INTERVAL) unless Rails.env.test?
          polls += 1
          prediction = handle(connection.get("/v1/predictions/#{prediction['id']}"))
        end

        if prediction["status"].to_s == "failed" || prediction["status"].to_s == "canceled"
          raise Vendors::ImageGen::Error.new(
            prediction["error"] || "Image generation failed",
            status: nil, body: prediction
          )
        end
        prediction
      end

      def in_progress?(prediction)
        %w[starting processing].include?(prediction["status"].to_s)
      end

      # PROVIDER SWAP POINT — extract the produced image URL from the finished
      # prediction. Replicate's `output` is a string URL or an array of URLs.
      def output_url(prediction)
        output = prediction["output"]
        case output
        when Array then output.first
        when String then output
        else prediction.dig("urls", "get")
        end
      end

      def parse_size(size)
        w, h = size.to_s.split("x").map(&:to_i)
        w = 1080 if w.to_i.zero?
        h = 1350 if h.to_i.zero?
        [w, h]
      end

      def aspect_ratio(width, height)
        gcd = width.gcd(height)
        "#{width / gcd}:#{height / gcd}"
      end

      def connection
        @connection ||= build_connection(@base_url, auth_token: @api_key)
      end
    end
  end
end
