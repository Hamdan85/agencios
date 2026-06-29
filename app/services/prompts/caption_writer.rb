# frozen_string_literal: true

module Prompts
  class CaptionWriter < Base
    def system
      <<~SYS
        Você é redator de social media. Escreva 3 variações de legenda para o conteúdo,
        adaptadas às regras de cada rede (#{context[:channels]}): gancho na primeira linha,
        corpo curto, CTA e hashtags relevantes. Respeite limites de caractere por rede.
        #{brand_block}
        #{positioning_block}
        Português do Brasil.
      SYS
    end

    def user_prompt
      "Brief/legenda base: #{context[:brief]}\nTom: #{context[:tone]}"
    end
  end
end
