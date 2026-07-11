# frozen_string_literal: true

module Mcp
  # Establishes the per-call tenant context for an MCP tool, mirroring what the
  # Authentication concern does for an HTTP request. The OAuth token is bound to
  # a User; the workspace arrives as a tool argument. We resolve the membership
  # and populate `Current` so the reused `Controllers::*` services + Pundit see
  # exactly the same context they would on a normal request.
  #
  # The workspace is resolved ONLY from the user's own memberships — a token can
  # never reach a workspace its user isn't a member of.
  module ToolContext
    class WorkspaceNotFound < StandardError
      def initialize(ref)
        super("Workspace '#{ref}' was not found among your workspaces. " \
              'Call list_workspaces to see the slugs you can use.')
      end
    end

    class NotAMember < StandardError; end

    # The connector is an Agência+ feature; Solo workspaces can't be operated
    # over MCP.
    class PlanRequired < StandardError; end

    module_function

    # Workspace-scoped tools.
    def for(user:, workspace_ref:, &block)
      raise ArgumentError, 'user is required' if user.nil?

      workspace  = resolve_workspace(user, workspace_ref)
      membership = user.membership_for(workspace)
      raise NotAMember, "You are not a member of '#{workspace_ref}'." if membership.nil?
      unless workspace.mcp_available?
        plan_locale = I18n.available_locales.find { |l| l.to_s == user.locale.to_s } || I18n.default_locale
        raise PlanRequired,
              I18n.t('api.mcp.plan_required_workspace', slug: workspace.slug,
                     host: SystemConfig.app_host, locale: plan_locale)
      end

      with_current(actor: user, workspace: workspace, membership: membership, &block)
    end

    # Account-level tools (list_workspaces, me) — no workspace/membership.
    def for_user(user:, &block)
      raise ArgumentError, 'user is required' if user.nil?

      with_current(actor: user, &block)
    end

    def resolve_workspace(user, ref)
      ref = ref.to_s.strip
      raise WorkspaceNotFound, ref if ref.empty?

      workspaces = user.workspaces
      by_slug = workspaces.find { |w| w.slug == ref }
      return by_slug if by_slug

      id = Integer(ref, exception: false)
      by_id = id && workspaces.find { |w| w.id == id }
      return by_id if by_id

      raise WorkspaceNotFound, ref
    end

    def with_current(actor:, workspace: nil, membership: nil)
      Current.actor      = actor
      Current.workspace  = workspace
      Current.membership = membership
      yield
    ensure
      Current.reset
    end
  end
end
