# frozen_string_literal: true

module Operations
  module Ai
    # scoping action — turn the scope into a subtask checklist, creating real
    # Subtasks via their own operation.
    class BuildScope < Operations::Base
      def initialize(ticket:)
        @ticket = ticket
      end

      def call
        fields = @ticket.fields_for("scoping")
        builder = Prompts::ScopeBuilder.new(
          workspace: @ticket.workspace, client: @ticket.project.client,
          creative_type: fields["creative_type"] || @ticket.creative_type,
          channels: Array(fields["channels"]).join(", "),
          copy_brief: fields["copy_brief"], script: fields["script"]
        )
        text = AiAdapter.complete(
          builder, max_tokens: 700, operation: "build_scope", subject: @ticket
        ).to_s

        titles = text.lines.filter_map { |l| clean_title(l) }.first(8)
        created = titles.map do |title|
          Operations::Subtasks::Create.call(ticket: @ticket, title: title)
        end

        Operations::Notes::Create.call(ticket: @ticket, user: nil, kind: :ai,
                                       body: "Checklist de produção gerada com #{created.size} subtarefas.")
        created
      end

      private

      # The model is asked for one plain task per line, but it occasionally wraps
      # items in markdown (bullets, numbering, **bold**, headings, code fences).
      # Strip all of that down to clean prose so subtasks never carry `**`/`#`/`-`.
      def clean_title(line)
        title = line.strip
        return if title.blank?
        return if title.match?(/\A(```|---|===|\#{1,6}\s*$)/) # fences / rules / empty headings

        title = title.sub(/\A\s*(?:[-*+•–—]\s+|\d+[.)]\s+)/, "") # leading bullet or "1." / "1)"
        title = title.sub(/\A#{'#'}{1,6}\s*/, "")               # leading markdown heading
        title = title.sub(/\A>\s*/, "")                         # blockquote
        title = title.gsub(/\*\*|__|`|~~/, "")                  # bold / code / strike markers
        title = title.gsub(/(?<!\w)[*_](?=\S)|(?<=\S)[*_](?!\w)/, "") # stray emphasis
        title = title.sub(/\A\[[ xX]?\]\s*/, "")                # leftover "[ ]" checkbox
        title.strip.presence
      end
    end
  end
end
