# frozen_string_literal: true

# Thin facade over Anthropic for ticket summaries, idea synthesis, scope, caption
# writing, retrospectives, and carousel copy. Used by the AI operations / jobs.
#
# Every completion is recorded in the AI cost ledger (AiUsageLog) via
# Operations::Ai::LogUsage — pass an `operation:` label and the `subject:` the
# call is about (ticket/creative/client) so spend can be attributed.
#
# `web_fetch: true` lets Claude read any URL in the prompt itself (server-side
# web_fetch tool) and use it as context — used for carousels from a link.
class AiAdapter
  def self.complete(prompt_builder, max_tokens: 1024, operation: 'ai_complete', subject: nil, web_fetch: false)
    new.complete(prompt_builder, max_tokens: max_tokens, operation: operation, subject: subject, web_fetch: web_fetch)
  end

  def complete(prompt_builder, max_tokens: 1024, operation: 'ai_complete', subject: nil, web_fetch: false)
    result = Vendors::Anthropic::Client.new.generate(
      system: prompt_builder.system,
      prompt: prompt_builder.respond_to?(:user_prompt) ? prompt_builder.user_prompt : '',
      max_tokens: max_tokens,
      web_fetch: web_fetch
    )

    Operations::Ai::LogUsage.call(
      provider: AiUsageLog::PROVIDER_ANTHROPIC,
      operation: operation,
      model: result.model,
      usage: result.usage,
      subject: subject
    )

    result.text
  end
end
