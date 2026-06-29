# frozen_string_literal: true

# OAuth 2.1 provider. Authorizes external MCP clients (Claude) to act on behalf
# of a User across all their workspaces. The access token is bound to the User
# (the resource owner); every workspace-scoped MCP tool resolves the membership
# for the workspace it is given (see Mcp::ToolContext).
#
# Discovery + DCR endpoints (/.well-known/*, /oauth/register) are wired in
# config/routes.rb; the MCP resource server lives at /mcp.
Doorkeeper.configure do
  orm :active_record

  # ── Resource owner ──────────────────────────────────────────────────
  # Reuse the existing first-party session cookie. The OAuth consent page is
  # opened in the user's browser by Claude; if they already have an agencios
  # session, we resolve it; otherwise bounce to the SPA login, which returns
  # here via ?return_to once authenticated.
  resource_owner_authenticator do
    token = cookies.signed[:session_id]
    session = token.present? && Session.find_by(token: token)

    if session && !session.expired?
      session.touch_activity!
      User.find_by(id: session.user_id)
    else
      redirect_to("/login?#{ { return_to: request.fullpath }.to_query }")
      nil
    end
  end

  # ── Grants & PKCE (OAuth 2.1) ───────────────────────────────────────
  grant_flows %w[authorization_code]
  force_pkce                                  # PKCE mandatory for every client
  pkce_code_challenge_methods %w[S256]        # reject the insecure "plain" method
  use_refresh_token

  # ── Token lifetimes ─────────────────────────────────────────────────
  access_token_expires_in 2.hours            # short-lived; clients refresh
  authorization_code_expires_in 10.minutes

  # ── Scopes (coarse capability grant; Pundit is the per-action gate) ──
  default_scopes  :read
  optional_scopes :write, :billing
  enforce_configured_scopes

  # Persist the authorization (per client+scopes) so re-connects skip the
  # consent screen, but always require an explicit first consent.
  reuse_access_token

  # We expose our own well-known discovery + DCR; keep Doorkeeper's built-in
  # application-management UI off (no first-party /oauth/applications screens).
end
