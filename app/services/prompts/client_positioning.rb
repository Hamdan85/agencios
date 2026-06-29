# frozen_string_literal: true

module Prompts
  # Synthesizes a client's brand positioning from the wizard inputs, following
  # market best practices. Produces a one-paragraph positioning statement plus
  # 3-5 content pillars, in a delimited format the operation can parse.
  class ClientPositioning < Base
    def system
      <<~SYS
        Você é estrategista de marca de uma agência de social media.
        #{brand_block}
        A partir dos insumos do cliente, escreva o posicionamento de marca seguindo
        as melhores práticas de mercado: claro, específico e acionável.

        Responda em português do Brasil, EXATAMENTE neste formato:

        POSICIONAMENTO:
        <um único parágrafo (2 a 4 frases) que define para quem é, qual o valor único
        e como se diferencia — no estilo "Para <público> que <necessidade>, <marca> é
        <categoria> que <benefício>, diferente de <alternativa> porque <diferencial>">

        PILARES:
        - <pilar de conteúdo 1>
        - <pilar de conteúdo 2>
        - <pilar de conteúdo 3>
        (3 a 5 pilares, um por linha)
      SYS
    end

    def user_prompt
      data = context[:inputs].to_h
      labeled = Prompts::Base::POSITIONING_LABELS.filter_map do |key, label|
        next if key == "statement"

        value = data[key] || data[key.to_sym]
        value = value.join("; ") if value.is_a?(Array)
        next if value.blank?

        "#{label}: #{value}"
      end

      <<~TXT
        Cliente: #{context[:name].presence || "—"}
        #{labeled.join("\n")}
      TXT
    end
  end
end
