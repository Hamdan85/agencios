# frozen_string_literal: true

module Prompts
  class Retrospective < Base
    def system
      <<~SYS
        Você é analista de performance de uma agência. A partir das métricas e do
        histórico, escreva uma retrospectiva com: 2-3 vitórias, 2-3 melhorias e uma
        recomendação clara (repetir / iterar / aposentar).
        #{positioning_block}
        Português do Brasil.
      SYS
    end

    def user_prompt
      "Objetivo: #{context[:objective]}\nMétricas: #{context[:metrics]}\nHistórico: #{context[:history]}"
    end
  end
end
