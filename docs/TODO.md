# TODO

Backlog de itens pendentes — features prometidas mas ainda não prontas para produção,
puxadas do marketing até que estejam completas.

## Legendas com IA

Geração automática de legendas por IA (caption writer por rede — regras de tamanho/hashtag
por canal). Removida das páginas de marketing / landing em 2026-07-05 porque ainda não está
pronta para ser anunciada como recurso incluso.

**O que fazer para reativar (concluir + re-anunciar):**
- [ ] Concluir o pipeline de legendas (`Prompts::CaptionWriter` + `GenerateCaptionsJob` →
      variantes por rede) e validar qualidade/idioma.
- [ ] Definir se é inclusa no plano (não gasta créditos) ou se consome créditos.
- [ ] Restaurar o anúncio nos locais de onde foi removido (todos na landing/marketing):
  - `app/views/pages/pricing.html.erb` — meta description, hero, explicador de créditos
    e o card de feature dedicado ("Legendas com IA") na lista da economia de créditos.
  - `app/views/pages/home.html.erb` — copy do preview de planos.
  - `app/models/pricing.rb` — feature do plano Solo (`DEFAULT_PLANS`).
  - `app/controllers/pages_controller.rb` — resposta do FAQ "O que são os créditos?".
- [ ] Reconciliar as menções que **permaneceram** (fora da landing, propositalmente não
      removidas agora — revisar quando o recurso shipar):
  - `app/frontend/pages/Billing/Paywall.jsx` — paywall in-app.
  - `app/views/pages/terms.html.erb` e `app/views/pages/privacy.html.erb` — textos legais.

> Nota: `pricing_plans` está vazio em produção, então a feature-list dos planos vem do
> código (`DEFAULT_PLANS`). Se um dia a tabela for populada via ActiveAdmin, editar a
> feature também lá.
