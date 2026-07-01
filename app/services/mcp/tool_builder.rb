# frozen_string_literal: true

module Mcp
  # Turns a Registry::Spec into a concrete FastMcp::Tool subclass: the argument
  # schema (with the injected `workspace` selector), the scope gate, and the
  # call that maps tool args → ActionController::Parameters → the service.
  module ToolBuilder
    module_function

    def build(spec)
      workspace_scoped = spec.workspace_scoped
      arg_block = spec.args

      Class.new(Mcp::Tools::BaseTool) do
        tool_name spec.name
        description spec.description

        define_singleton_method(:mcp_spec) { spec }

        arguments do
          if workspace_scoped
            required(:workspace).filled(:string)
                                .description('Workspace slug or numeric id (see list_workspaces).')
          end
          arg_block&.call(self)
        end

        define_method(:call) do |**args|
          require_scope!(spec.scope)
          params = Mcp::ToolBuilder.build_params(spec, args)

          if spec.workspace_scoped
            run_workspace_service(spec.service, args[:workspace], params)
          else
            run_account_service(spec.service, params)
          end
        end
      end
    end

    # Shape the tool args into the params hash the target service expects:
    #   - drops the `workspace` selector (it routes the tenant, isn't a param)
    #   - when `wrap` is set, nests writable args under that key (the service
    #     does `params.require(:wrap)`), keeping `top_level` keys (id/ticket_id)
    #     flat so the service can `find` by them
    #   - returns nil for params-less services (called as `.call`)
    def build_params(spec, args)
      return nil unless spec.params_arg

      rest = args.reject { |k, _| k == :workspace }
      return deep_symbol_hash(rest) unless spec.wrap

      top = spec.top_level || Registry::DEFAULT_TOP_LEVEL
      flat = {}
      nested = {}
      rest.each { |k, v| (top.include?(k) ? flat : nested)[k] = v }
      flat.merge(spec.wrap => nested)
    end

    def deep_symbol_hash(hash)
      hash.transform_values { |v| v }
    end
  end
end
