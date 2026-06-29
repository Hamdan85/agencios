# frozen_string_literal: true

module Prompts
  class CarouselCopy < Base
    def system
      <<~SYS
        Você é especialista em carrosséis virais. Escreva o copy slide a slide:
        slide de gancho, slides de valor e slide de CTA (total #{context[:slides] || 6}).
        Uma linha curta e impactante por slide, no formato "Slide N: <texto>".
        #{brand_block}
        #{positioning_block}
        Português do Brasil.
      SYS
    end

    def user_prompt
      "Tema: #{context[:topic]}\nObjetivo: #{context[:objective]}"
    end
  end
end
