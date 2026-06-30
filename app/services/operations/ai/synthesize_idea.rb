# frozen_string_literal: true

module Operations
  module Ai
    # ideation action — synthesize the brief into angles/hooks (returns text;
    # also recorded as an AI note on the ticket).
    class SynthesizeIdea < Operations::Base
      def initialize(ticket:)
        @ticket = ticket
      end

      def call
        fields = @ticket.fields_for("ideation")
        builder = Prompts::IdeaSynthesis.new(
          workspace: @ticket.workspace, client: @ticket.project.client,
          brief: fields["brief"], objective: fields["objective"], persona: fields["target_persona"]
        )
        text = AiAdapter.complete(
          builder, max_tokens: 700, operation: "synthesize_idea", subject: @ticket
        ).to_s.strip
        Operations::Notes::Create.call(ticket: @ticket, user: nil, kind: :ai, body: text)
        text
      end
    end
  end
end
