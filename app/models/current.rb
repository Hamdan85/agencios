# frozen_string_literal: true

# Single source of "who and where" for the request: the auth session, the active
# tenant (workspace), and the user's membership in that workspace.
#
# HTTP requests authenticate via a cookie `session` and the user is delegated
# from it. Tokened requests (the MCP server) have no session — they set `actor`
# to the OAuth resource owner directly. `user` resolves either path.
class Current < ActiveSupport::CurrentAttributes
  attribute :session, :workspace, :membership, :actor

  def user
    session&.user || actor
  end
end
