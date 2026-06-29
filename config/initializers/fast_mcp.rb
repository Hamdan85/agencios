# frozen_string_literal: true

# The fast-mcp gem ships its entrypoint as `fast_mcp.rb` (underscore) while the
# gem name uses a dash, so Bundler's autorequire doesn't load it. We only use
# the gem for its FastMcp::Tool argument DSL + JSON-Schema generation — the
# transport is our own Mcp::ServerController — so just ensure the constant is
# loaded before Zeitwerk autoloads Mcp::Tools::BaseTool (which subclasses it).
require "fast_mcp"
