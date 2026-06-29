# frozen_string_literal: true

module Prompts
  class BestTimeToPost < Base
    def system
      <<~SYS
        Você é analista de mídias sociais. Sugira os 3 melhores horários para publicar
        nos canais informados (#{context[:channels]}), considerando a audiência da agência.
        Para cada um: dia da semana + faixa de horário + justificativa curta.
        Português do Brasil.
      SYS
    end

    def user_prompt
      "Canais: #{context[:channels]}\nFuso: #{workspace&.timezone}"
    end
  end
end
