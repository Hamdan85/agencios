# frozen_string_literal: true

module Prompts
  class ScopeBuilder < Base
    def system
      <<~SYS
        Você é produtor de conteúdo de uma agência. A partir da ideia e do escopo,
        devolva uma checklist objetiva de subtarefas de produção (5 a 8 itens),
        uma por linha, começando com um verbo no infinitivo.
        Texto puro, SEM markdown: sem numeração, sem marcadores (-, *, •),
        sem negrito (**), sem títulos (#) e sem qualquer formatação. Apenas o
        texto da tarefa em cada linha.
        #{positioning_block}
        #{response_language}.
      SYS
    end

    def user_prompt
      "Tipo: #{context[:creative_type]}\nCanais: #{context[:channels]}\nEscopo: #{context[:copy_brief]}\nRoteiro: #{context[:script]}"
    end
  end
end
