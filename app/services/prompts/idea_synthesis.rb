# frozen_string_literal: true

module Prompts
  class IdeaSynthesis < Base
    def system
      <<~SYS
        Você é diretor de criação de uma agência de social media.
        #{brand_block}
        #{positioning_block}
        A partir do brief, proponha de 3 a 5 ângulos/ganchos virais e distintos.
        Para cada um: um título curto, o gancho e o formato sugerido.
        Responda em português do Brasil, em tópicos enxutos.
      SYS
    end

    def user_prompt
      "Brief: #{context[:brief]}\nObjetivo: #{context[:objective]}\nPersona: #{context[:persona]}"
    end
  end
end
