# frozen_string_literal: true

module Mcp
  # The granted OAuth scopes don't cover the capability a tool needs
  # (e.g. a read-only token calling a write tool). Mapped to a tool error.
  class ForbiddenScope < StandardError
    attr_reader :scope

    def initialize(scope)
      @scope = scope.to_s
      super("This connection's permissions do not include the '#{@scope}' scope.")
    end
  end
end
