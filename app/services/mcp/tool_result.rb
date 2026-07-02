# frozen_string_literal: true

module Mcp
  # A tool's return value enriched with extra MCP content blocks (images,
  # resource links) beyond the default text/structured JSON. When a tool returns
  # one of these, the dispatcher renders `data` as the text + structuredContent
  # (unchanged) and appends `blocks` to the content array so the connected client
  # (Claude / ChatGPT) can display the media.
  class ToolResult
    attr_reader :data, :blocks

    def initialize(data:, blocks: [])
      @data = data
      @blocks = Array(blocks).compact
    end
  end
end
