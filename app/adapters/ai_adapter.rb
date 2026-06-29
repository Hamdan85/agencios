# frozen_string_literal: true

# Thin facade over Anthropic for ticket summaries, idea synthesis, scope, caption
# writing, and retrospectives. Used by the AI operations / jobs.
class AiAdapter
  def self.complete(prompt_builder, max_tokens: 1024)
    new.complete(prompt_builder, max_tokens: max_tokens)
  end

  def complete(prompt_builder, max_tokens: 1024)
    Vendors::Anthropic::Client.new.messages(
      system: prompt_builder.system,
      prompt: prompt_builder.respond_to?(:user_prompt) ? prompt_builder.user_prompt : "",
      max_tokens: max_tokens
    )
  end
end
