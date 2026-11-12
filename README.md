# MALI — Gestão de Produção

App web (HTML + JavaScript puro) publicado no GitHub Pages em **https://mali.gutgestao.com.br**, com banco no Supabase (projeto **PROJETOS**, schema **`mali`**).

Substitui o app AppSheet **APP MALI** (planilha `1LN6dKyb_jVp9yAzHZdnE5kHYUUeOil1EK-EcahBTZXs`).

## Fluxo

```
Pedido ─► Corte ─► Sublotes (cor × tamanho) ─► Envio p/ facção ─► Retorno (parcial/total)
            │                                     │                    │
            └─ estampar antes ─► Estamparia ──────┘                    ├─► Estamparia / Finalização / Inspeção ─► Estoque ─► Expedição ─► Pedido entregue
                                                                       └─► Conserto (defeito) ─► volta para a etapa escolhida
Produção interna = facção "PRODUÇÃO INTERNA": apontamento por operador × operação × tempo padrão (roteiro), pausas e eficiência.
Fechamento: paga à facção (peças boas × valor por peça) + consertos recebidos.
```

## Módulos

| Menu | O que faz | Perfil que altera |
|---|---|---|
| Painel | Indicadores, envios atrasados, pedidos por entrega | — |
| Pedidos | Pedidos de clientes, itens por produto/cor/tamanho, acompanhamento de corte, estoque e entrega | comercial |
| 1 - Corte | Programa cores × folhas e tamanhos × riscos, confirma, gera sublotes e etiquetas 100×150 mm | corte |
| 2 - Lotes / Envio | Envia sublotes para facção ou produção interna, com aviamentos; romaneio | faccao |
| 3 - Gestão de Facção | Em aberto, prazos, retornos parciais/totais com defeito, ocorrências | faccao |
| Consertos | Peças com defeito na facção; recebimento e destino | faccao |
| Produção Interna | Operadores, apontamentos, pausas, andamento do roteiro, eficiência | producao |
| Estamparia / Finalização / Inspeção | Fila de cada etapa: iniciar, concluir (aprovadas, conserto, perda, destino); OP de estamparia do estoque | estamparia / qualidade |
| Estoque | Saldo por produto/cor/tamanho, movimentações, ajustes | estoque |
| Expedição | Separa itens de pedidos, embalagem, libera (baixa no estoque) | estoque |
| Fechamento Facção | Pagamento dos retornos e consertos, desconto, recibo | financeiro |
| Ficha Técnica | Roteiro com tempo padrão, consumo de matéria-prima, medidas, custo | cadastros |
| Cadastros | Produtos, clientes, facções, cores, tamanhos, operadores, operações, motivos de parada, matéria-prima | cadastros |
| Usuários | Libera contas e define perfis | admin |

**supervisor** pode estornar/excluir lançamentos (corte, envio, retorno, etapa, conserto, expedição, OP). Tudo fica na tabela `auditoria`.

## Primeiro acesso
1. Abra o app e clique em **Criar conta** (e-mail + senha). Confirme pelo e-mail.
2. Entre: como ainda não há administrador, a tela oferece **Tornar-me administrador**.
3. Os demais usuários criam conta e o admin libera em **Usuários**.

## Estrutura
```
index.html, css/app.css, js/app.js (login, menu, rotas), js/util.js, js/romaneio.js, js/telas/*.js (uma tela por arquivo)
supabase/migrations/   estrutura, regras de negócio (funções mali.*), views v_*, RLS
supabase/seed_cadastros.sql   cadastros reais importados da planilha (tools/importar_cadastros.py)
test/rodar.sh          teste do fluxo completo num Postgres 16 local
CNAME                  domínio do GitHub Pages
```

As regras de negócio ficam no banco (funções `mali.*`, `security definer` com checagem de perfil); o front só chama essas funções e lê as views `v_*` (com `security_invoker`, respeitando o RLS).

## Publicação
Branch `main` publicada pelo GitHub Pages a partir da raiz. Domínio: registro **CNAME** `mali` → `facsimprojetos-cloud.github.io` no DNS de `gutgestao.com.br`.
