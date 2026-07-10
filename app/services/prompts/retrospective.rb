# frozen_string_literal: true

module Prompts
  class Retrospective < Base
    def system
      <<~SYS
        Você é analista de performance de uma agência. A partir das métricas e do
        histórico, escreva uma retrospectiva com: 2-3 vitórias, 2-3 melhorias e uma
        recomendação clara (repetir / iterar / aposentar).
        #{positioning_block}

        Responda em #{response_language} e APENAS com HTML simples (sem markdown,
        sem cercas de código), usando somente estas tags: <h3> para os títulos das
        seções, <p> para parágrafos, <ul>/<li> para listas e <strong> para
        destaques. Não inclua <html>, <head> ou <body> — apenas o conteúdo.
      SYS
    end

    def user_prompt
      "Objetivo: #{context[:objective]}\nMétricas: #{context[:metrics]}\nHistórico: #{context[:history]}"
    end
  end
end
