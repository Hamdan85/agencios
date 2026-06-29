# frozen_string_literal: true

module Prompts
  # Status-aware contextual summary of a ticket. The system prompt changes its
  # framing per funnel stage.
  class TicketSummary < Base
    PER_STATUS = {
      "ideation" => "Sintetize a ideia: qual é o ângulo central, o objetivo e a audiência. Aponte o gancho mais forte.",
      "scoping" => "Resuma o escopo: tipo de criativo, canais, entregáveis e o que falta definir.",
      "production" => "Avalie a produção: o criativo e a legenda atendem ao brief? Aponte ajustes de QA.",
      "scheduled" => "Resuma o plano de publicação: canais, horários e adaptações por rede.",
      "published" => "Avalie o desempenho até agora versus o objetivo, com base nas métricas.",
      "retrospective" => "Destaque vitórias, melhorias e a recomendação (repetir/iterar/aposentar).",
      "done" => "Escreva um micro case-study: o que foi feito e o resultado final."
    }.freeze

    def system
      status = context[:status].to_s
      <<~SYS
        Você é o estrategista de conteúdo de uma agência de social media.
        #{brand_block}
        #{positioning_block}

        Estágio do ticket: #{Ticket::STATUS_LABELS[status]}.
        Tarefa: #{PER_STATUS.fetch(status, "Resuma o estado atual do ticket de forma objetiva.")}

        Responda em português do Brasil, em no máximo 3 frases curtas e diretas,
        sem rodeios e sem repetir os dados literais — entregue leitura estratégica.
      SYS
    end

    def user_prompt
      ticket = context[:ticket]
      status = context[:status].to_s
      fields = ticket.fields_for(status)
      notes = ticket.notes.chronological.last(5).map(&:body).join("\n")

      <<~TXT
        Título: #{ticket.display_title}
        Tipo de criativo: #{ticket.creative_type || "—"}
        Canais: #{ticket.channels.join(", ").presence || "—"}
        Campos do estágio: #{fields.to_json}
        Notas recentes: #{notes.presence || "—"}
      TXT
    end
  end
end
