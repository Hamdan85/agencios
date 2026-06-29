# frozen_string_literal: true

module Mcp
  # The full set of MCP tools exposed to clients: the registry-generated tools
  # plus the bespoke account-level ones. Built fresh per request (cheap; the MCP
  # endpoint is low-QPS) so dev reloads never serve stale classes.
  module Catalog
    BESPOKE = [Mcp::Tools::ListWorkspaces, Mcp::Tools::Me].freeze

    module_function

    def tool_classes
      Registry.tool_classes + BESPOKE
    end

    def find(name)
      tool_classes.find { |klass| klass.tool_name == name }
    end
  end
end
