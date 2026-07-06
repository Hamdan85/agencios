# Modelo de Pricing — crédito, custo por operação e blindagem cambial

> Objetivo: **se o negócio não vende, não tem custo; se vende, lucra sempre ≥80%** sobre o
> custo real de IA — mesmo com o dólar oscilando, e dentro da lei brasileira.

## Princípio

1. **Pré-pago + custo-só-na-operação.** O custo de IA (vendor) só é incorrido quando o usuário
   roda uma operação, e só depois de travar (hold) crédito pré-pago suficiente. Sem venda = sem
   custo variável = **sem prejuízo**.
2. **Cost-plus por operação.** Cada operação (um render de clipe, uma imagem) é cobrada em créditos
   proporcionais ao **custo real daquela operação** — não ao tempo do vídeo final. O usuário gera
   vários clipes de 4s/8s e aceita um; cada geração custou, e cada uma é cobrada. Mostramos o custo
   em créditos e o usuário continua ou desiste.
3. **Crédito = R$1,00 nominal, fixo.** Vendido como **saldo em R$**, nunca como quantidade
   ("X vídeos"). Validade de 12 meses, informada antes da compra.

## Fórmula

```
custo_estimado (hold, antes de rodar) = taxa_modelo_USD_por_segundo × segundos
custo_real     (true-up, após rodar)  = usage.cost do vendor (USD), via AiUsageLog

créditos_da_operação = teto( custo_USD_centavos × CÂMBIO_FIXO × MARKUP ÷ 100 )
```

- **CÂMBIO_FIXO** = câmbio conservador (spot + colchão ~10–15%), **fixo**, reprecificado
  periodicamente. Ex.: R$6,00 quando o spot está ~R$5,40. **Nunca ao vivo** (ver Blindagem).
- **MARKUP = 6,5** — cobre IOF 3,5% (Decreto 12.499/2025) + taxa de gateway (~4%) + desconto do
  maior pacote (até 17%), e ainda entrega ≥80% líquido.
- **Piso:** se o vendor não retornar custo, estimar por modelo×segundos. **Nunca cobrar 0** por um
  render que rodou.
- **Todo custo do vendor** entra na conta: vídeo (OpenRouter), imagem (Banana) **e voz (Cartesia)**
  — hoje a voz fica de fora do ledger.

## Por que ≥80% sempre (provado contra 86 operações reais de produção)

Câmbio fixo R$6,00 + markup 6,5×, pior pacote (R$0,833/cr) + gateway 4%, com IOF 3,5% no custo:

| Dólar real (spot) | Pior operação | |
|---|---|---|
| R$5,40 (hoje) | 82,1% | ✅ |
| R$6,00 (borda do buffer) | 80,1% | ✅ |
| R$6,50 | 78,5% | reprecificar |
| R$7,00 | 76,8% | reprecificar (ainda lucro, nunca prejuízo) |

Créditos por operação (câmbio 6,00, markup 6,5): imagem **2**, clipe 4s **~23**, clipe 8s **~50**.

## Blindagem cambial (legal)

- **Câmbio FIXO, não ao vivo.** Preço que segue o dólar em tempo real = **indexação cambial**,
  proibida em contrato doméstico pela **Lei 10.192/2001** (preços em Real), além de ferir a
  transparência do CDC.
- O que é legal: **reprecificação periódica pela própria empresa** (reajuste de preço), não
  indexação no contrato. O câmbio fixo conservador + o markup absorvem a oscilação **entre** os
  reajustes; mesmo furando o colchão, a margem cai mas **não vira prejuízo**.
- **Cadência:** revisar o câmbio fixo **mensalmente + gatilho** (reprecifica fora de hora se o spot
  ultrapassar o câmbio fixo). Só para operações futuras, com o preço sempre visível antes de confirmar.

## Regras legais (CDC) — validar com advogado antes de publicar termos

- Crédito = R$1,00 nominal. **Nunca desvalorizar retroativamente** créditos já comprados (cláusula
  nula, CDC art. 51, IV; apropriação de valor pago).
- **Vender saldo em R$, nunca quantidade** ("1000 créditos = 25 vídeos" → você deve a quantidade).
- Preço da operação **mostrado antes de o usuário confirmar** (cada operação é uma compra à vista).
- Termos: *"os preços das operações podem ser reajustados periodicamente"*. **Nunca** escrever
  *"o valor varia conforme o dólar"* (indexação nula) nem *"podemos alterar o valor dos créditos a
  qualquer tempo"*.
- Validade de 12 meses informada de forma clara e prévia (espelha OpenAI/Anthropic).

## Checklist de implementação (as 4 travas + config)

1. **Câmbio fixo no cálculo** — usar `PricingConfig.usd_brl` no `credits_for` (hoje é só display).
2. **`credits_for(video)` cost-based** — trocar `teto(segundos × per15 ÷ 15)` por
   `teto(custo_USD_¢ × usd_brl × margin_multiplier ÷ 100)`, com estimativa por modelo no hold e
   true-up com o custo real.
3. **Piso anti-zero** — nunca debitar 0 por um render real; cair na estimativa se o custo vier nil.
4. **Voz (Cartesia) no ledger** — logar o custo da voz no `AiUsageLog` para entrar na conta.

Config (DB, editável em `/admin`): `usd_brl = 6.00` (câmbio conservador), `margin_multiplier = 6.5`
(hoje 5, e não era aplicado), + tabela de **taxa USD/segundo por modelo** de vídeo
(veo-3.1-lite ≈ $0,16 · seedance-2.0-fast ≈ $0,15 · veo-3.1 ≈ $0,40).

> Câmbio de referência na redação: spot ~R$5,40 em jul/2026. Reavaliar o câmbio fixo mensalmente.
