# frozen_string_literal: true

# Thin, provider-agnostic facade over the text-AI layer (Vendors::Ai) for ticket
# summaries, idea synthesis, scope, caption writing, retrospectives, and carousel
# copy. Used by the AI operations / jobs.
#
# The concrete vendor (OpenRouter or Anthropic) is chosen by Vendors::Ai, and the
# model can be routed per `operation:` (Vendors::Ai.model_for). Every completion
# is recorded in the AI cost ledger (AiUsageLog) via Operations::Ai::LogUsage —
# pass an `operation:` label and the `subject:` (ticket/creative/client) so spend
# is attributed.
#
# `web_fetch: true` lets the model use any URL in the prompt as context. On a
# provider with a native URL-reading tool (Anthropic) it's used server-side; on
# one without (OpenRouter) the page content is fetched here (Vendors::Web::Reader)
# and inlined into the prompt — so the behavior is identical to callers.
class AiAdapter
  MAX_FETCH_URLS = 3

  def self.complete(prompt_builder, max_tokens: 1024, operation: 'ai_complete', subject: nil, web_fetch: false)
    new.complete(prompt_builder, max_tokens: max_tokens, operation: operation, subject: subject, web_fetch: web_fetch)
  end

  def complete(prompt_builder, max_tokens: 1024, operation: 'ai_complete', subject: nil, web_fetch: false)
    generate(prompt_builder, max_tokens: max_tokens, operation: operation, subject: subject, web_fetch: web_fetch).text
  end

  # Like .complete, but forces the model to call `tool` (an Anthropic-shaped tool
  # schema: name/description/input_schema) and returns its structured input as a
  # Hash — never freeform text to be parsed. Use for any AI output that must land
  # in a specific JSON shape (see Prompts::FieldFill / Operations::Ai::FillFields).
  def self.complete_tool(prompt_builder, tool:, max_tokens: 1024, operation: 'ai_complete', subject: nil)
    new.complete_tool(prompt_builder, tool: tool, max_tokens: max_tokens, operation: operation, subject: subject)
  end

  def complete_tool(prompt_builder, tool:, max_tokens: 1024, operation: 'ai_complete', subject: nil)
    generate(prompt_builder, max_tokens: max_tokens, operation: operation, subject: subject, tool: tool).tool_input
  end

  private

  def generate(prompt_builder, max_tokens:, operation:, subject:, web_fetch: false, tool: nil)
    client = Vendors::Ai.client(model: Vendors::Ai.model_for(operation))
    system = prompt_builder.system
    prompt = prompt_builder.respond_to?(:user_prompt) ? prompt_builder.user_prompt : ''

    # When the model can't read URLs itself, inline the page content into the
    # prompt so the same instructions (hook link / reference material) still work.
    if web_fetch && !client.supports_web_fetch?
      prompt = inline_url_content(system, prompt)
      web_fetch = false
    end

    result = client.generate(system: system, prompt: prompt, max_tokens: max_tokens, web_fetch: web_fetch, tool: tool)

    Operations::Ai::LogUsage.call(
      provider: client.provider_key,
      operation: operation,
      model: result.model,
      usage: result.usage,
      cost_cents: result.usage.is_a?(Hash) ? result.usage['cost_cents'] : nil,
      subject: subject
    )

    result
  end

  # Fetch the URLs present in the prompt and append their distilled content, so a
  # provider without a server-side fetch tool has the same material to work from.
  def inline_url_content(system, prompt)
    urls = "#{system}\n#{prompt}".scan(%r{https?://[^\s"'<>)\]]+}).uniq.first(MAX_FETCH_URLS)
    blocks = urls.filter_map do |url|
      digest = Vendors::Web::Reader.call(url: url)
      next if digest.nil?

      "URL: #{url}\nTítulo: #{digest[:title]}\nConteúdo:\n#{digest[:text]}"
    end
    return prompt if blocks.empty?

    "#{prompt}\n\n--- CONTEÚDO DAS URLS (leia e use conforme as instruções acima) ---\n#{blocks.join("\n\n")}"
  end
end
