# frozen_string_literal: true

module Vendors
  module Heygen
    module Actions
      # List the workspace's reusable Studio templates. `GET /v2/templates`.
      # Returns the array of template objects. See docs/integrations/heygen.md §3c.
      class ListTemplates
        def self.call(...) = new(...).call

        def initialize(client: nil)
          @client = client || Client.new
        end

        def call
          body = @client.get('/v2/templates')
          data = body['data'] || {}
          data['templates'] || data || []
        end
      end
    end
  end
end
