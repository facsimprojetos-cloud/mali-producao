-- Importação única do histórico do AppSheet "APP MALI" (abas staged em mali_import.raw)
-- Roda numa transação: qualquer erro desfaz tudo.

-- 0) Cortes de experiência lançados no sistema novo (autorizado pelo usuário)
delete from mali.auditoria where registro in (select id::text from mali.cortes);
delete from mali.apontamentos; delete from mali.retornos; delete from mali.consertos; delete from mali.etapas;
delete from mali.envios; delete from mali.remessas; delete from mali.sublotes; delete from mali.cortes;

-- 1) Auxiliares de cadastro
insert into mali.produtos(nome, ativo, obs) values ('PRODUTO NÃO IDENTIFICADO', false, 'Sublotes antigos do AppSheet sem produto') on conflict (nome) do nothing;
insert into mali.cores(nome, ativo) values ('SEM COR', false) on conflict (nome) do nothing;
insert into mali.tamanhos(nome, ordem, ativo) values ('ÚNICO', 99, false) on conflict (nome) do nothing;

create temp table cor_alias(legado text primary key, cor_id bigint);
insert into cor_alias select '6d2f9cbc', id from mali.cores where nome = 'MESCLA 3';

create or replace function pg_temp.cor(t text) returns bigint language sql stable as $$
  select coalesce((select cor_id from cor_alias where legado = btrim(t)), mali_import.cor(t)) $$;
create or replace function pg_temp.prod(t text) returns bigint language sql stable as $$
  select mali_import.prod(regexp_replace(btrim(t), '\s+', ' ', 'g')) $$;

-- 2) Linhas da aba Corte (1 linha = 1 sublote)
create temp table c as
select distinct on (l->>'SUBLOTE')
  l->>'SUBLOTE' as sub,
  coalesce(nullif(l->>'LOTE CUPOM',''), split_part(l->>'SUBLOTE', '.', 1)) as lote,
  coalesce(pg_temp.prod(l->>'PRODUTO'), pg_temp.prod(l->>'PRODUTO.'), (select id from mali.produtos where nome = 'PRODUTO NÃO IDENTIFICADO')) as prod_id,
  coalesce(pg_temp.cor(l->>'COR'), pg_temp.cor(l->>'COR.'), (select id from mali.cores where nome = 'SEM COR')) as cor_id,
  coalesce(mali_import.tam(l->>'GRADE'), (select id from mali.tamanhos where nome = 'ÚNICO')) as tam_id,
  mali_import.num(l->>'QTD')::int as qtd,
  coalesce(mali_import.dt(l->>'DATA E HORA'), mali_import.dt(l->>'Data de Envio'), now()::timestamp) as data,
  mali_import.fac(l->>'Facção') as fac_id,
  mali_import.dt(l->>'Data de Envio') as data_envio,
  mali_import.dt(l->>'Previsão')::date as previsao,
  mali_import.num(l->>'QTD ENVIADA')::int as qtd_enviada,
  mali_import.num(l->>'Valor') as valor,
  mali_import.dt(l->>'Data de Retorno Facção')::date as data_ret,
  mali_import.num(l->>'QTD Entregue')::int as qtd_entregue,
  mali_import.dt(l->>'Data de Pagamento')::date as data_pag,
  l->>'PRÓXIMO PROCESSO' as prox,
  mali_import.dt(l->>'Inspeção Início') as insp_ini, mali_import.dt(l->>'Inspeção Fim') as insp_fim,
  mali_import.dt(l->>'Finalização Início') as fin_ini, mali_import.dt(l->>'Finalização Fim') as fin_fim,
  mali_import.num(l->>'QTD CONSERTO')::int as qtd_conserto,
  mali_import.fac(l->>'Facção Defeito') as fac_def,
  l->>'Ocorrência' as ocorrencia
from mali_import.v where aba = 'corte' and nullif(l->>'SUBLOTE','') is not null
order by l->>'SUBLOTE';
delete from c where coalesce(qtd, 0) <= 0;

-- 3) Cortes (um por lote + produto)
create temp table k as
select lote, prod_id, min(data) as data,
  row_number() over (partition by lote order by min(data), prod_id) as rk,
  (regexp_match(lote, '^(\d+)-(\d{2}) (\d{4})$')) as m
from c group by lote, prod_id;
alter table k add column id uuid default gen_random_uuid(), add column lote_final text, add column numero int, add column mes date;
update k set lote_final = case when rk = 1 then lote else lote || ' (' || rk || ')' end,
  mes = case when m is not null then make_date(m[3]::int, m[2]::int, 1) else date_trunc('month', data)::date end,
  numero = case when m is not null then m[1]::int + (rk - 1) * 10000 else 900000 + rk end;
-- garante (mes, numero) únicos para lotes fora do padrão
update k set numero = numero + x.n from (select id, row_number() over (partition by mes, numero order by lote) - 1 as n from k) x
  where x.id = k.id and x.n > 0;
insert into mali.cortes(id, numero, mes, lote, data, produto_id, destino, status, obs, cortado_em, criado_em)
select id, numero, mes, lote_final, data, prod_id, 'PRODUÇÃO', 'Cortado', 'Importado do AppSheet', data, data from k;

-- grade de corte aproximada (folhas = maior quantidade da cor; riscos = 1); o total real vem dos sublotes
insert into mali.corte_cores(corte_id, posicao, cor_id, folhas)
select k.id, row_number() over (partition by k.id order by min(c.sub)), c.cor_id, greatest(max(c.qtd), 1)
from c join k on k.lote = c.lote and k.prod_id = c.prod_id group by k.id, c.cor_id;
insert into mali.corte_tamanhos(corte_id, posicao, tamanho_id, riscos)
select k.id, row_number() over (partition by k.id order by t.ordem, t.nome), c.tam_id, 1
from c join k on k.lote = c.lote and k.prod_id = c.prod_id join mali.tamanhos t on t.id = c.tam_id group by k.id, c.tam_id, t.ordem, t.nome;

-- 4) Sublotes
alter table c add column sub_id uuid default gen_random_uuid(), add column corte_id uuid, add column env_qtd int;
update c set corte_id = k.id from k where k.lote = c.lote and k.prod_id = c.prod_id;
update c set env_qtd = case when fac_id is not null and data_envio is not null then greatest(coalesce(nullif(qtd_enviada, 0), qtd), 1) end;
insert into mali.sublotes(id, codigo, lote, corte_id, produto_id, cor_id, tamanho_id, qtd_cortada, qtd_saldo, criado_em)
select c.sub_id, c.sub, k.lote_final, c.corte_id, c.prod_id, c.cor_id, c.tam_id, c.qtd,
  case when c.env_qtd is null then c.qtd else greatest(c.qtd - c.env_qtd, 0) end, c.data
from c join k on k.id = c.corte_id;

-- 5) Remessas (facção + lote + data de envio) com aviamentos da aba ENVIO
create temp table av as
select mali_import.fac(l->>'FACÇÃO') as fac_id, l->>'LOTE.' as lote,
  sum(mali_import.num(l->>'VIÉS')) vies, sum(mali_import.num(l->>'FIO')) fio, sum(mali_import.num(l->>'LINHA')) linha,
  sum(mali_import.num(l->>'ELÁSTICO')) elastico, sum(mali_import.num(l->>'ALÇA')) alca, sum(mali_import.num(l->>'ETIQUETA')) etiqueta
from mali_import.v where aba = 'envio' group by 1, 2;
create temp table r as
select gen_random_uuid() as id, fac_id, lote, data_envio::date as dia, min(data_envio) as data, max(previsao) as previsao
from c where env_qtd is not null group by fac_id, lote, data_envio::date;
insert into mali.remessas(id, token, faccao_id, data, previsao, obs, vies, fio, linha, elastico, alca, etiqueta)
select r.id, 'import-' || md5(r.fac_id || r.lote || r.dia), r.fac_id, r.data, r.previsao, 'Importado do AppSheet (lote ' || r.lote || ')',
  av.vies, av.fio, av.linha, av.elastico, av.alca, av.etiqueta
from r left join lateral (select * from av where av.fac_id = r.fac_id and av.lote = r.lote limit 1) av on true
order by r.data;
-- aviamentos ficam só na primeira remessa do lote para aquela facção
update mali.remessas x set vies = null, fio = null, linha = null, elastico = null, alca = null, etiqueta = null
from (select id, row_number() over (partition by faccao_id, substring(obs from '\(lote (.*)\)') order by data) n from mali.remessas where token like 'import-%') y
where y.id = x.id and y.n > 1;

-- 6) Envios
alter table c add column env_id uuid;
update c set env_id = gen_random_uuid() where env_qtd is not null;
insert into mali.envios(id, remessa_id, sublote_id, faccao_id, produto_id, cor_id, tamanho_id, lote, qtd, valor_unit, previsao, data_retorno, ocorrencia, criado_em)
select c.env_id, r.id, c.sub_id, c.fac_id, c.prod_id, c.cor_id, c.tam_id, c.sub, c.env_qtd, coalesce(c.valor, 0), c.previsao, c.data_ret, c.ocorrencia, c.data_envio
from c join r on r.fac_id = c.fac_id and r.lote = c.lote and r.dia = c.data_envio::date
where c.env_qtd is not null;

-- 7) Retornos
create temp table rp as
select l->>'id facção' as sub, mali_import.num(l->>'QTD')::int as qtd, mali_import.num(l->>'Valor') as valor,
  coalesce(mali_import.dt(l->>'Data da Parcial'), mali_import.dt(l->>'Data da Inspeção'))::date as data,
  mali_import.dt(l->>'Data de Pagamento')::date as data_pag, l->>'Data de Separação' as prox, l->>'id' as rp_id
from mali_import.v where aba = 'retorno_parcial';
create temp table rt as
select gen_random_uuid() as id, c.env_id, c.sub_id, c.fac_id, rp.qtd, coalesce(rp.valor, c.valor, 0) as valor,
  coalesce(rp.data, c.data_ret, c.data_envio::date) as data, coalesce(rp.data_pag, c.data_pag) as data_pag,
  case upper(coalesce(rp.prox, c.prox, '')) when 'FINALIZAÇÃO INTERNA' then 'FINALIZAÇÃO' when 'ESTAMPARIA' then 'ESTAMPARIA' else 'INSPEÇÃO' end as proximo,
  'Importado do AppSheet (retorno parcial)' as obs
from rp join c on c.sub = rp.sub
where c.env_id is not null and coalesce(rp.qtd, 0) > 0
union all
select gen_random_uuid(), c.env_id, c.sub_id, c.fac_id, c.qtd_entregue, coalesce(c.valor, 0),
  coalesce(c.data_ret, c.data_envio::date), c.data_pag,
  case upper(coalesce(c.prox, '')) when 'FINALIZAÇÃO INTERNA' then 'FINALIZAÇÃO' else 'INSPEÇÃO' end,
  'Importado do AppSheet'
from c
where c.env_id is not null and coalesce(c.qtd_entregue, 0) > 0 and not exists (select 1 from rp where rp.sub = c.sub and coalesce(rp.qtd,0) > 0);
-- envio nunca menor que o que voltou (dados antigos inconsistentes)
update mali.envios e set qtd = x.tot from (select env_id, sum(qtd) tot from rt group by env_id) x where x.env_id = e.id and x.tot > e.qtd;
insert into mali.retornos(id, envio_id, data_retorno, qtd, qtd_defeito, proximo, valor_unit, obs, criado_em)
select id, env_id, data, qtd, 0, proximo, valor, obs, data from rt;

-- 8) Pagamentos: agrupa retornos pagos por facção + data de pagamento
create temp table fe as
select gen_random_uuid() as id, fac_id, data_pag from rt where data_pag is not null group by fac_id, data_pag;
insert into mali.fechamentos(id, faccao_id, data, pix, obs, criado_em)
select fe.id, fe.fac_id, fe.data_pag, f.pix, 'Importado do AppSheet', fe.data_pag from fe join mali.faccoes f on f.id = fe.fac_id order by fe.data_pag;
insert into mali.fechamento_itens(fechamento_id, tipo, ref_id, qtd, valor_unit, valor)
select fe.id, 'RETORNO', rt.id, rt.qtd, rt.valor, round(rt.qtd * rt.valor, 2) from rt join fe on fe.fac_id = rt.fac_id and fe.data_pag = rt.data_pag;
update mali.retornos x set fechamento_id = fe.id from rt join fe on fe.fac_id = rt.fac_id and fe.data_pag = rt.data_pag where x.id = rt.id;
update mali.fechamentos f set total_bruto = t.v, total = t.v from (select fechamento_id, sum(valor) v from mali.fechamento_itens group by 1) t where t.fechamento_id = f.id;

-- 9) O que está parado em inspeção / finalização no AppSheet entra na fila
insert into mali.etapas(tipo, sublote_id, origem, origem_id, faccao_id, qtd, criado_em, inicio, responsavel, obs)
select case when c.prox = 'FINALIZAÇÃO INTERNA' then 'FINALIZAÇÃO' else 'INSPEÇÃO' end, c.sub_id, 'RETORNO',
  (select rt.id from rt where rt.sub_id = c.sub_id order by rt.data desc limit 1), c.fac_id,
  (select sum(rt.qtd) from rt where rt.sub_id = c.sub_id), coalesce(c.data_ret::timestamp, c.data),
  case when c.prox = 'FINALIZAÇÃO INTERNA' then c.fin_ini else c.insp_ini end, null, 'Importado do AppSheet'
from c
where ((c.prox = 'INSPEÇÃO' and c.insp_fim is null) or (c.prox = 'FINALIZAÇÃO INTERNA' and c.fin_fim is null))
  and c.data_ret is not null and exists (select 1 from rt where rt.sub_id = c.sub_id);

-- 10) Consertos em aberto (QTD CONSERTO > 0 no AppSheet)
insert into mali.consertos(origem, origem_id, sublote_id, faccao_id, qtd, valor_unit, enviado_em, obs)
select 'RETORNO', (select rt.id from rt where rt.sub_id = c.sub_id order by rt.data desc limit 1), c.sub_id, coalesce(c.fac_def, c.fac_id), c.qtd_conserto, 0,
  coalesce(c.data_ret, c.data::date), 'Importado do AppSheet'
from c where coalesce(c.qtd_conserto, 0) > 0 and coalesce(c.fac_def, c.fac_id) is not null and exists (select 1 from rt where rt.sub_id = c.sub_id);

-- 11) Pedidos
create temp table pd as
select mali_import.num(l->>'Nº Pedido')::int as numero, mali_import.dt(l->>'Data')::date as data,
  coalesce((select id from mali.clientes where legado_id = l->>'Cliente' or upper(nome) = upper(coalesce(l->>'CLIENTE.', l->>'Cliente')) limit 1),
           (select id from mali.clientes where nome = 'MALI')) as cliente_id,
  pg_temp.prod(coalesce(l->>'Produto', l->>'PRODUTO.')) as prod_id, coalesce(pg_temp.cor(l->>'Cor'), pg_temp.cor(l->>'COR.')) as cor_id,
  mali_import.tam(l->>'Tamanho') as tam_id, mali_import.num(l->>'Quantidade')::int as qtd, coalesce(mali_import.num(l->>'QTD Entregue')::int, 0) as entregue,
  mali_import.dt(l->>'Data Entrega')::date as entrega, l->>'ESTAMPA' as estampa, l->>'TAG' as tag, l->>'OBSERVAÇÕES' as obs
from mali_import.v where aba = 'pedidos';
delete from pd where numero is null or prod_id is null or cor_id is null or tam_id is null or coalesce(qtd, 0) <= 0;
insert into mali.pedidos(numero, data, cliente_id, entrega, status, obs, criado_em)
select numero, coalesce(min(data), current_date), min(cliente_id), min(entrega),
  case when bool_and(entregue >= qtd) then 'Entregue' else 'Aberto' end, 'Importado do AppSheet', coalesce(min(data), current_date)
from pd group by numero;
insert into mali.pedido_itens(pedido_id, produto_id, cor_id, tamanho_id, qtd, qtd_entregue, estampa, tag, obs)
select p.id, pd.prod_id, pd.cor_id, pd.tam_id, pd.qtd, least(pd.entregue, pd.qtd), pd.estampa, pd.tag, pd.obs
from pd join mali.pedidos p on p.numero = pd.numero;

-- 12) Expedições (histórico; o saldo de estoque vem do item 14)
insert into mali.expedicoes(pedido_id, pedido_item_id, cliente_id, produto_id, cor_id, tamanho_id, qtd, embalagem_inicio, embalagem_fim, liberado_em, criado_em, obs)
select p.id,
  (select i.id from mali.pedido_itens i where i.pedido_id = p.id and i.produto_id = x.prod_id and i.cor_id = x.cor_id and i.tamanho_id = x.tam_id limit 1),
  x.cliente_id, x.prod_id, x.cor_id, x.tam_id, x.qtd, x.ini, x.fim, x.lib, coalesce(x.criado, x.ini, x.lib, now()), 'Importado do AppSheet'
from (select pg_temp.prod(l->>'Produto') prod_id, pg_temp.cor(l->>'Cor') cor_id, mali_import.tam(l->>'Grade') tam_id,
        mali_import.num(l->>'QTD')::int qtd, mali_import.num(l->>'Pedido')::int pedido,
        (select id from mali.clientes where legado_id = l->>'Cliente' or upper(nome) = upper(l->>'Cliente') limit 1) cliente_id,
        mali_import.dt(l->>'Embalagem Início') ini, mali_import.dt(l->>'Embalagem Fim') fim, mali_import.dt(l->>'Liberado') lib, mali_import.dt(l->>'Data Hora') criado
      from mali_import.v where aba = 'expedicao') x
left join mali.pedidos p on p.numero = x.pedido
where x.prod_id is not null and x.cor_id is not null and x.tam_id is not null and coalesce(x.qtd, 0) > 0;

-- 13) OPs de estamparia (histórico; sem movimentar estoque)
insert into mali.ops_estamparia(numero, data, previsao, produto_id, cor_id, tamanho_id, qtd, estampa, obs, retorno_em, qtd_retorno, qtd_perda)
overriding system value
select coalesce(mali_import.num(l->>'OP')::int, 100000 + row_number() over ()), coalesce(mali_import.dt(l->>'DATA'), now()), mali_import.dt(l->>'PREVISÃO')::date,
  pg_temp.prod(l->>'PRODUTO'), pg_temp.cor(l->>'COR'), mali_import.tam(l->>'GRADE'), mali_import.num(l->>'QTD')::int, l->>'ESTAMPA',
  concat_ws(' | ', l->>'OBS', 'Importado do AppSheet'), mali_import.dt(l->>'DATA DE RETORNO'),
  case when l->>'DATA DE RETORNO' is not null then mali_import.num(l->>'QTD')::int end, case when l->>'DATA DE RETORNO' is not null then 0 end
from mali_import.v where aba = 'op_estamparia'
  and pg_temp.prod(l->>'PRODUTO') is not null and pg_temp.cor(l->>'COR') is not null and mali_import.tam(l->>'GRADE') is not null and coalesce(mali_import.num(l->>'QTD'), 0) > 0;
select setval(pg_get_serial_sequence('mali.ops_estamparia', 'numero'), greatest((select max(numero) from mali.ops_estamparia where numero < 100000), 1));

-- 14) Saldo de estoque atual (aba Estoque, coluna SALDO), como ajuste inicial
insert into mali.estoque_mov(tipo, origem, produto_id, cor_id, tamanho_id, qtd, obs)
select 'AJUSTE', 'AJUSTE', pg_temp.prod(v.p), pg_temp.cor(v.c), mali_import.tam(v.g), v.q, 'Saldo inicial importado do AppSheet'
from (values ('BLUSA SUEDE','OLIVA','M',14),('CALÇA JOGGER','GRAFIT 1','G',60),('CALÇA JOGGER','GRAFIT 1','M',89),('CALÇA JOGGER','GRAFITE','G',376),('CALÇA JOGGER','GRAFITE','GG',163),('CALÇA JOGGER','GRAFITE','M',535),('CALÇA JOGGER','GRAFITE','P',267),('CALÇA JOGGER','GRAFITE 2','G',115),('CALÇA JOGGER','GRAFITE 2','M',238),('CALÇA JOGGER','MESCLA','G',186),('CALÇA JOGGER','MESCLA','M',506),('CALÇA JOGGER','MESCLA 4','M',7),('CALÇA JOGGER','PRETO','G',352),('CALÇA JOGGER','PRETO','GG',250),('CALÇA JOGGER','PRETO','M',658),('CALÇA JOGGER','PRETO','P',381),('CALÇA LEGGING BLACK OUT','MARINHO','G',31),('CALÇA LEGGING BLACK OUT','MARINHO','GG',30),('CALÇA LEGGING BLACK OUT','MARINHO','M',29),('CALÇA LEGGING BLACK OUT','MARROM','M',129),('CALÇA LEGGING BLACK OUT','PRETO','G',217),('CALÇA LEGGING BLACK OUT','PRETO','GG',106),('CALÇA LEGGING BLACK OUT','PRETO','M',152),('CALÇA LEGGING BLACK OUT','PRETO','P',323),('CASACO CANGURU','GRAFITE','G',114),('CASACO CANGURU','GRAFITE','P',56),('CASACO CANGURU','PRETO','G',107),('CASACO CANGURU','PRETO','GG',107),('CASACO CANGURU','PRETO','M',107),('CASACO CANGURU','PRETO','P',107),('LEGGING MICRO CANELADO','MARINHO','G',9),('LEGGING MICRO CANELADO','MARINHO','GG',9),('LEGGING MICRO CANELADO','MARINHO','M',12),('LEGGING MICRO CANELADO','MARINHO','P',9),('LEGGING MICRO CANELADO','MARROM','G',9),('LEGGING MICRO CANELADO','MARROM','M',9),('LEGGING MICRO CANELADO','MARROM','P',9),('LEGGING MICRO CANELADO','ODALISCA','G',9),('LEGGING MICRO CANELADO','ODALISCA','GG',9),('LEGGING MICRO CANELADO','ODALISCA','M',8),('LEGGING MICRO CANELADO','ODALISCA','P',9),('LEGGING MICRO CANELADO','PRETO','G',14),('LEGGING MICRO CANELADO','PRETO','GG',15),('LEGGING MICRO CANELADO','PRETO','M',12),('LEGGING MICRO CANELADO','PRETO','P',14),('LEGGING MICRO CANELADO','VERDE','G',9),('LEGGING MICRO CANELADO','VERDE','GG',18),('LEGGING MICRO CANELADO','VERDE','M',9),('LEGGING MICRO CANELADO','VERDE','P',9),('MACAQUINHO','AZUL','G',8),('MACAQUINHO','AZUL','M',8),('MACAQUINHO','GRAFITE','G',14),('MACAQUINHO','GRAFITE','M',28),('MACAQUINHO','GRAFITE','P',14),('MACAQUINHO','MARINHO','G',28),('MACAQUINHO','MARINHO','M',42),('MACAQUINHO','MARINHO','P',14),('MACAQUINHO','MARROM','G',20),('MACAQUINHO','MARROM','M',20),('MACAQUINHO','MERLOT','G',16),('MACAQUINHO','MERLOT','M',28),('MACAQUINHO','MERLOT','P',12),('MACAQUINHO','OLIVA','P',54),('MACAQUINHO','PRETO','G',42),('MACAQUINHO','PRETO','M',79),('MACAQUINHO','PRETO','P',37),('MACAQUINHO','RUBRO','M',13),('MACAQUINHO','RUBRO','P',51),('MACAQUINHO','VERDE','M',16),('MACAQUINHO','VERDE','P',16),('SHORT BD. AMAMENTAÇÃO','MARINHO','GG',34),('SHORT CAROL','LILÁS','G',33),('SHORT CAROL','MARAGOGI','G',18),('SHORT CAROL','MARAGOGI','GG',18),('SHORT CAROL','MARAGOGI','M',18),('SHORT CAROL','MARAGOGI','P',18),('SHORT CAROL','MARINHO','GG',26),('SHORT CAROL','MARINHO','P',28),('SHORT CAROL','MARROM','M',38),('SHORT CAROL','MARROM','P',38),('SHORT CAROL','PRETO','G',72),('SHORT CAROL','PRETO','M',72),('SHORT CAROL','VERDE MILITAR','G',75),('SHORT CAROL','VINO','G',54),('SHORT VIRGINIA','CHOCOLATE','G',7),('SHORT VIRGINIA','CHOCOLATE','GG',7),('SHORT VIRGINIA','CHOCOLATE','M',8),('SHORT VIRGINIA','CHOCOLATE','P',8),('SHORT VIRGINIA','CHUMBO','G',16),('SHORT VIRGINIA','CHUMBO','GG',16),('SHORT VIRGINIA','CHUMBO','M',16),('SHORT VIRGINIA','CHUMBO','P',16),('SHORT VIRGINIA','MARAGOGI','G',8),('SHORT VIRGINIA','MARAGOGI','M',8),('SHORT VIRGINIA','MARAGOGI','P',7),('SHORT VIRGINIA','MARINHO','G',16),('SHORT VIRGINIA','MARINHO','GG',16),('SHORT VIRGINIA','MARINHO','M',16),('SHORT VIRGINIA','MARINHO','P',16),('SHORT VIRGINIA','MARROM','G',17),('SHORT VIRGINIA','MARROM','GG',17),('SHORT VIRGINIA','MARROM','M',16),('SHORT VIRGINIA','MARROM','P',17),('SHORT VIRGINIA','MERLOT','G',15),('SHORT VIRGINIA','MERLOT','GG',16),('SHORT VIRGINIA','MERLOT','M',16),('SHORT VIRGINIA','MERLOT','P',14),('SHORT VIRGINIA','MILITAR','G',12),('SHORT VIRGINIA','MILITAR','GG',12),('SHORT VIRGINIA','MILITAR','M',12),('SHORT VIRGINIA','MILITAR','P',12),('SHORT VIRGINIA','PRETO','G',59),('SHORT VIRGINIA','PRETO','GG',126),('SHORT VIRGINIA','PRETO','M',70),('SHORT VIRGINIA','PRETO','P',66),('SHORT VIRGINIA','ROYAL','G',12),('SHORT VIRGINIA','ROYAL','GG',12),('SHORT VIRGINIA','ROYAL','P',12),('SHORT VIRGINIA','RUBRO','P',18),('SHORT VIRGINIA','VULCANO','G',16),('SHORT VIRGINIA','VULCANO','GG',15),('SHORT VIRGINIA','VULCANO','M',15),('SHORT VIRGINIA','VULCANO','P',15),('TOP CAROL','MARINHO','G',18),('TOP CAROL','MARINHO','GG',17),('TOP CAROL','MARINHO','M',17),('TOP CAROL','MARINHO','P',28),('TOP CAROL','MARROM','G',38),('TOP CAROL','MARROM','GG',38),('TOP CAROL','MARROM','M',38),('TOP CAROL','MERLOT','GG',34),('TOP CAROL','MERLOT','P',32),('TOP CAROL','MILITAR','G',34),('TOP CAROL','PRETO','G',144),('TOP CAROL','VERDE MILITAR','GG',56),('TOP CAROL','VINHO','G',22),('TOP CAROL','VINHO','GG',33),('TOP CAROL','VINHO','M',10),('TOP MICRO CANELADO','MARINHO','GG',9),('TOP MICRO CANELADO','MARINHO','M',9),('TOP MICRO CANELADO','MARINHO','P',9),('TOP MICRO CANELADO','MARROM','G',9),('TOP MICRO CANELADO','MARROM','GG',9),('TOP MICRO CANELADO','MARROM','M',9),('TOP MICRO CANELADO','MARROM','P',9),('TOP MICRO CANELADO','ODALISCA','GG',9),('TOP MICRO CANELADO','ODALISCA','M',9),('TOP MICRO CANELADO','ODALISCA','P',9),('TOP MICRO CANELADO','PRETO','G',30),('TOP MICRO CANELADO','PRETO','GG',15),('TOP MICRO CANELADO','PRETO','M',15),('TOP MICRO CANELADO','PRETO','P',15),('TOP MICRO CANELADO','VERDE','G',9),('TOP MICRO CANELADO','VERDE','GG',9),('TOP MICRO CANELADO','VERDE','M',9),('TOP MICRO CANELADO','VERDE','P',8),('TOP VIRGÍNIA','CHOCOLATE','G',8),('TOP VIRGÍNIA','CHOCOLATE','GG',8),('TOP VIRGÍNIA','CHOCOLATE','M',8),('TOP VIRGÍNIA','CHOCOLATE','P',8),('TOP VIRGÍNIA','CHUMBO','G',16),('TOP VIRGÍNIA','CHUMBO','GG',16),('TOP VIRGÍNIA','CHUMBO','M',16),('TOP VIRGÍNIA','CHUMBO','P',16),('TOP VIRGÍNIA','LILÁS','G',17),('TOP VIRGÍNIA','LILÁS','M',17),('TOP VIRGÍNIA','LILÁS','P',17),('TOP VIRGÍNIA','MARAGOGI','G',7),('TOP VIRGÍNIA','MARAGOGI','GG',8),('TOP VIRGÍNIA','MARAGOGI','M',8),('TOP VIRGÍNIA','MARAGOGI','P',7),('TOP VIRGÍNIA','MARINHO','G',16),('TOP VIRGÍNIA','MARINHO','GG',16),('TOP VIRGÍNIA','MARINHO','M',16),('TOP VIRGÍNIA','MARINHO','P',16),('TOP VIRGÍNIA','MARROM','G',17),('TOP VIRGÍNIA','MARROM','M',17),('TOP VIRGÍNIA','MARROM','P',17),('TOP VIRGÍNIA','MERLOT','G',16),('TOP VIRGÍNIA','PRETO','G',45),('TOP VIRGÍNIA','PRETO','GG',45),('TOP VIRGÍNIA','PRETO','M',45),('TOP VIRGÍNIA','PRETO','P',45),('TOP VIRGÍNIA','ROYAL','GG',12),('TOP VIRGÍNIA','ROYAL','P',12),('TOP VIRGÍNIA','RUBRO','G',15),('TOP VIRGÍNIA','RUBRO','GG',14),('TOP VIRGÍNIA','RUBRO','M',16),('TOP VIRGÍNIA','VINO','M',16),('TOP VIRGÍNIA','VINO','P',16),('TOP VIRGÍNIA','VULCANO','P',16)) v(p, c, g, q);
drop table if exists cor_alias, c, k, av, r, rp, rt, fe, pd;
