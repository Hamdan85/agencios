# frozen_string_literal: true

module Vendors
  module Heygen
    module Actions
      # Inspect a template's declared variables. `GET /v2/template/{template_id}`.
      # Returns the template detail object (variable names + types).
      # See docs/integrations/heygen.md §3c.
      class GetTemplate
        def self.call(...) = new(...).call

        def initialize(template_id:, client: nil)
          @template_id = template_id
          @client      = client || Client.new
        end

        def call
          body = @client.get("/v2/template/#{@template_id}")
          body["data"] || body
        end
      end
    end
  end
end
