# frozen_string_literal: true

module Operations
  module Video
    # Turns a raw vendor failure reason (English, technical) into a friendly PT-BR
    # explanation the user can act on — so a render blocked by the video model's
    # safety/copyright filters reads as helpful guidance in the chat, not an
    # opaque error. Content-facing (PT-BR), per the language rules.
    module FailureNote
      module_function

      # Returns the chat message for a failed scene render.
      def for(reason:, position:)
        scene = "a cena #{position.to_i + 1}"
        "⚠️ Não consegui gerar #{scene}: #{explain(reason.to_s)}"
      end

      def explain(reason)
        r = reason.downcase
        if r.include?('copyright')
          'o gerador bloqueou o vídeo por **direitos autorais** — provavelmente a cena lembra ' \
            'personagens ou marcas conhecidas (ex.: animais/personagens que remetem a filmes). ' \
            'Vale trocar o conceito por algo original: pessoas reais, um mascote próprio ou foco no produto. ' \
            'Me diga como quer refazer que eu ajusto.'
        elsif r.include?('audio') || r.include?('sensitive')
          'o gerador bloqueou o **áudio** por conteúdo sensível — costuma ser a fala. ' \
            'Posso reescrever o texto falado de um jeito mais neutro, ou deixar a cena sem voz. ' \
            'Como prefere?'
        elsif r.include?('safety') || r.include?('policy') || r.include?('moderat')
          'o gerador bloqueou a cena por uma **regra de conteúdo**. Me diga o que quer mostrar ' \
            'que eu reescrevo de um jeito que passe.'
        elsif r.include?('timed out') || r.include?('timeout')
          'a geração **demorou demais** e expirou. Pode ser instabilidade do gerador — ' \
            'quer que eu tente de novo?'
        else
          'o gerador recusou essa cena. Quer tentar de novo ou mudar a ideia dela? ' \
            'Se puder, descreva de outro jeito que eu refaço.'
        end
      end
    end
  end
end
