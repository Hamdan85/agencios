# frozen_string_literal: true

module Prompts
  # Builds the end-of-run project audit: from the project's real numbers
  # (aggregated post + account metrics) and ticket context, Claude writes the
  # qualitative sections of the report deck as ONE structured JSON object — the
  # same "return only JSON" discipline as CarouselCopy / FieldFill.
  #
  # The quantitative tiles are computed separately and merged in by the operation;
  # the model never invents numbers — it interprets the ones it's given.
  class ProjectAudit < Base
    def system
      <<~SYS
        Você é um(a) auditor(a) sênior de redes sociais de uma agência. A partir dos
        DADOS REAIS de uma campanha (métricas agregadas + contexto dos tickets),
        escreva uma auditoria estratégica honesta e acionável, no estilo de um
        relatório de consultoria.
        #{brand_block}
        #{positioning_block}

        Regras:
        - Use SOMENTE os números fornecidos; não invente métricas. Interprete-os.
        - Seja específico e direto; aponte gargalos reais e oportunidades concretas.
        - #{response_language}. Tom profissional, sem floreio.

        Responda SOMENTE com um objeto JSON válido (sem markdown, sem cercas de
        código, sem texto fora do JSON), exatamente nesta forma:
        {
          "wins": [
            {"emoji":"<1 emoji>","title":"<título curto>","body":"<1-2 frases>"}
          ],
          "content_performance": {
            "winners": [{"label":"<formato/peça>","metric":"<número + leitura>"}],
            "losers":  [{"label":"<formato/peça>","metric":"<número + leitura>"}]
          },
          "bottlenecks": [
            {"title":"<gargalo>","body":"<diagnóstico em 1-2 frases>"}
          ],
          "opportunities": [
            {"tag":"<ALTO IMPACTO|RÁPIDO DE EXECUTAR|MATERIAL JÁ EXISTE|NOVO VETOR>",
             "title":"<oportunidade>","body":"<1-2 frases>"}
          ],
          "matrix": [
            {"dimension":"<Crescimento|Engajamento|Reels|Stories|Feed/Identidade|Alcance Externo|Posicionamento|Conversão>",
             "score":<0-10, uma casa decimal>,"comment":"<curto>"}
          ],
          "overall": {
            "score":<0-10, uma casa decimal>,
            "verdict":"<uma frase>",
            "to_8":["<passo>","<passo>"],
            "to_9":["<passo>","<passo>"]
          },
          "action_plan": {
            "d7":["<ação>"], "d30":["<ação>"], "d90":["<ação>"]
          },
          "projection": {
            "verdict":"<cenário em 12 meses, uma frase forte>",
            "narrative":["<parágrafo>","<parágrafo>"]
          },
          "growth_angle": {
            "title":"<ângulo de crescimento principal>",
            "intro":"<1 frase>",
            "tactics":[{"tag":"<curto>","title":"<tática>","body":"<1-2 frases>"}]
          }
        }
        Use de 3 a 5 itens em wins, bottlenecks, opportunities e matrix; 2 a 4 em
        cada coluna do action_plan; 3 a 4 táticas em growth_angle.
      SYS
    end

    def user_prompt
      <<~TXT
        Campanha: #{context[:project_name]}
        Cliente: #{client&.name}
        Período: #{context[:period_label]}

        MÉTRICAS AGREGADAS (numbers are ground truth):
        #{context[:metrics_json]}

        DESEMPENHO POR PEÇA (mais vistas primeiro):
        #{context[:content_json]}

        CONTEXTO DOS TICKETS (objetivos e histórico):
        #{context[:tickets_context]}
      TXT
    end
  end
end
