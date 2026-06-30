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

        titles = text.lines.map { |l| l.strip.sub(/\A[-*\d.]+\s*/, "") }.reject(&:blank?).first(8)
        created = titles.map do |title|
          Operations::Subtasks::Create.call(ticket: @ticket, title: title)
        end

        Operations::Notes::Create.call(ticket: @ticket, user: nil, kind: :ai,
                                       body: "Checklist de produção gerada com #{created.size} subtarefas.")
        created
      end
    end
  end
end
