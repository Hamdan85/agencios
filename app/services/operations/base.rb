# frozen_string_literal: true

module Operations
  # Base class for domain operations. Own all side effects (DB writes, emails,
  # external API calls, broadcasts). Called by jobs, webhooks, controllers, or
  # other operations. No HTTP concerns.
  class Base
    def self.call(...)
      new(...).call
    end

    private

    # Convenience: the active tenant for the current request.
    def workspace
      Current.workspace
    end
  end
end
