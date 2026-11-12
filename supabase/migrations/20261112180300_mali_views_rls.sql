-- MALI — Parte 4: views de leitura, RLS e permissões

-- ---------- Views ----------
create view mali.v_pedidos with (security_invoker = true) as
select p.*, c.nome as cliente,
  coalesce(t.qtd,0)::int as qtd_total, coalesce(t.entregue,0)::int as qtd_entregue, coalesce(t.itens,0)::int as itens,
  (p.status = 'Aberto' and p.entrega < mali.hoje()) as atrasado
from mali.pedidos p
join mali.clientes c on c.id = p.cliente_id
left join lateral (select sum(qtd) qtd, sum(qtd_entregue) entregue, count(*) itens from mali.pedido_itens i where i.pedido_id = p.id) t on true;

create view mali.v_pedido_itens with (security_invoker = true) as
select i.*, p.numero as pedido_numero, p.status as pedido_status, p.cliente_id, c.nome as cliente, p.entrega,
  pr.nome as produto, co.nome as cor, ta.nome as tamanho, ta.ordem as tamanho_ordem,
  (i.qtd - i.qtd_entregue) as pendente,
  coalesce((select sum(x.qtd) from mali.expedicoes x where x.pedido_item_id = i.id and x.liberado_em is null and x.cancelado_em is null),0)::int as em_expedicao,
  mali._saldo_estoque(i.produto_id, i.cor_id, i.tamanho_id) as saldo_estoque,
  coalesce((select sum(s.qtd_cortada) from mali.sublotes s where s.pedido_id = i.pedido_id and s.produto_id = i.produto_id
            and s.cor_id = i.cor_id and s.tamanho_id = i.tamanho_id),0)::int as qtd_cortada
from mali.pedido_itens i
join mali.pedidos p on p.id = i.pedido_id
join mali.clientes c on c.id = p.cliente_id
join mali.produtos pr on pr.id = i.produto_id
join mali.cores co on co.id = i.cor_id
join mali.tamanhos ta on ta.id = i.tamanho_id;

create view mali.v_cortes with (security_invoker = true) as
select c.id, c.numero, c.mes, c.lote, c.data, c.produto_id, c.pedido_id, c.destino, c.status, c.obs, c.cortado_em, c.criado_em,
  p.nome as produto, pe.numero as pedido_numero,
  (select jsonb_agg(jsonb_build_object('posicao', x.posicao, 'cor_id', x.cor_id, 'cor', k.nome, 'folhas', x.folhas) order by x.posicao)
     from mali.corte_cores x join mali.cores k on k.id = x.cor_id where x.corte_id = c.id) as cores,
  (select jsonb_agg(jsonb_build_object('posicao', y.posicao, 'tamanho_id', y.tamanho_id, 'tamanho', t.nome, 'riscos', y.riscos) order by y.posicao)
     from mali.corte_tamanhos y join mali.tamanhos t on t.id = y.tamanho_id where y.corte_id = c.id) as tamanhos,
  ((select coalesce(sum(folhas),0) from mali.corte_cores where corte_id = c.id) *
   (select coalesce(sum(riscos),0) from mali.corte_tamanhos where corte_id = c.id))::int as total_pecas
from mali.cortes c
join mali.produtos p on p.id = c.produto_id
left join mali.pedidos pe on pe.id = c.pedido_id;

create view mali.v_envios with (security_invoker = true) as
select e.*, f.nome as faccao, f.interna, r.numero as remessa_numero, r.data as remessa_data,
  p.nome as produto, co.nome as cor, t.nome as tamanho, t.ordem as tamanho_ordem,
  coalesce(rt.boas,0)::int as qtd_boas, coalesce(rt.defeito,0)::int as qtd_defeito,
  (e.qtd - coalesce(rt.boas,0) - coalesce(rt.defeito,0))::int as saldo,
  case when e.data_retorno is null then case when e.previsao < mali.hoje() then 'Atrasado' else 'No Prazo' end
       else case when e.data_retorno > e.previsao then 'Entregue com atraso' else 'Entregue no prazo' end end as atraso,
  case when e.data_retorno is null and e.previsao < mali.hoje() then mali.hoje() - e.previsao else 0 end as dias_atraso
from mali.envios e
join mali.faccoes f on f.id = e.faccao_id
join mali.remessas r on r.id = e.remessa_id
join mali.produtos p on p.id = e.produto_id
join mali.cores co on co.id = e.cor_id
join mali.tamanhos t on t.id = e.tamanho_id
left join lateral (select sum(x.qtd) boas, sum(x.qtd_defeito) defeito from mali.retornos x where x.envio_id = e.id) rt on true;

create view mali.v_remessas with (security_invoker = true) as
select r.*, f.nome as faccao, f.endereco, f.telefone,
  (select coalesce(sum(qtd),0) from mali.envios e where e.remessa_id = r.id)::int as qtd_total,
  (select coalesce(sum(qtd*valor_unit),0) from mali.envios e where e.remessa_id = r.id) as valor_total,
  (select count(*) from mali.envios e where e.remessa_id = r.id)::int as itens
from mali.remessas r join mali.faccoes f on f.id = r.faccao_id;

create view mali.v_retornos with (security_invoker = true) as
select r.*, e.faccao_id, f.nome as faccao, e.lote, e.sublote_id, e.produto_id, p.nome as produto, co.nome as cor, t.nome as tamanho,
  round(r.qtd * r.valor_unit, 2) as valor_a_pagar, (r.fechamento_id is not null) as pago
from mali.retornos r
join mali.envios e on e.id = r.envio_id
join mali.faccoes f on f.id = e.faccao_id
join mali.produtos p on p.id = e.produto_id
join mali.cores co on co.id = e.cor_id
join mali.tamanhos t on t.id = e.tamanho_id;

create view mali.v_consertos with (security_invoker = true) as
select c.*, f.nome as faccao, s.codigo as sublote, s.produto_id, p.nome as produto, co.nome as cor, t.nome as tamanho,
  case when c.recebido_em is null then 'Em conserto' else 'Recebido' end as situacao,
  round(coalesce(c.qtd_recebida,0) * c.valor_unit, 2) as valor_a_pagar, (c.fechamento_id is not null) as pago
from mali.consertos c
join mali.faccoes f on f.id = c.faccao_id
join mali.sublotes s on s.id = c.sublote_id
join mali.produtos p on p.id = s.produto_id
join mali.cores co on co.id = s.cor_id
join mali.tamanhos t on t.id = s.tamanho_id;

create view mali.v_etapas with (security_invoker = true) as
select x.*, s.codigo as sublote, s.lote, s.produto_id, p.nome as produto, p.estamparia_apos, co.nome as cor, t.nome as tamanho,
  f.nome as faccao, pe.numero as pedido_numero,
  case when x.fim is not null then 'Concluída' when x.inicio is not null then 'Em andamento' else 'Aguardando' end as status,
  case when x.inicio is not null then round(extract(epoch from (coalesce(x.fim, now()) - x.inicio)) / 60) end as minutos
from mali.etapas x
join mali.sublotes s on s.id = x.sublote_id
join mali.produtos p on p.id = s.produto_id
join mali.cores co on co.id = s.cor_id
join mali.tamanhos t on t.id = s.tamanho_id
left join mali.faccoes f on f.id = x.faccao_id
left join mali.pedidos pe on pe.id = s.pedido_id;

create view mali.v_sublotes with (security_invoker = true) as
select s.*, p.nome as produto, co.nome as cor, t.nome as tamanho, t.ordem as tamanho_ordem, c.destino, c.data as data_corte,
  pe.numero as pedido_numero, x.na_faccao, x.em_etapa, x.em_conserto, x.no_estoque,
  case when s.qtd_saldo > 0 then 'Aguardando distribuição'
       when x.em_etapa > 0 then (select 'Em ' || lower(e.tipo) from mali.etapas e where e.sublote_id = s.id and e.fim is null order by e.criado_em limit 1)
       when x.na_faccao > 0 then 'Em facção'
       when x.em_conserto > 0 then 'Em conserto'
       when x.no_estoque > 0 then 'No estoque'
       else 'Concluído' end as status
from mali.sublotes s
join mali.cortes c on c.id = s.corte_id
join mali.produtos p on p.id = s.produto_id
join mali.cores co on co.id = s.cor_id
join mali.tamanhos t on t.id = s.tamanho_id
left join mali.pedidos pe on pe.id = s.pedido_id
cross join lateral (select
  coalesce((select sum(mali._pendente_envio(e.id)) from mali.envios e where e.sublote_id = s.id and e.data_retorno is null),0)::int as na_faccao,
  coalesce((select sum(e.qtd) from mali.etapas e where e.sublote_id = s.id and e.fim is null),0)::int as em_etapa,
  coalesce((select sum(k.qtd) from mali.consertos k where k.sublote_id = s.id and k.recebido_em is null),0)::int as em_conserto,
  coalesce((select sum(m.qtd) from mali.estoque_mov m where m.lote = s.codigo and m.tipo = 'ENTRADA' and m.origem = 'PRODUÇÃO'),0)::int as no_estoque
) x;

create view mali.v_estoque with (security_invoker = true) as
select m.produto_id, m.cor_id, m.tamanho_id, p.nome as produto, p.estamparia_apos, co.nome as cor, t.nome as tamanho, t.ordem as tamanho_ordem,
  sum(case when m.tipo = 'ENTRADA' then m.qtd else 0 end)::int as entradas,
  sum(case when m.tipo = 'SAÍDA' then m.qtd else 0 end)::int as saidas,
  sum(case when m.tipo = 'AJUSTE' then m.qtd else 0 end)::int as ajustes,
  sum(case when m.tipo = 'SAÍDA' then -m.qtd else m.qtd end)::int as saldo,
  max(m.em) as ultima_mov
from mali.estoque_mov m
join mali.produtos p on p.id = m.produto_id
join mali.cores co on co.id = m.cor_id
join mali.tamanhos t on t.id = m.tamanho_id
group by m.produto_id, m.cor_id, m.tamanho_id, p.nome, p.estamparia_apos, co.nome, t.nome, t.ordem;

create view mali.v_estoque_mov with (security_invoker = true) as
select m.*, p.nome as produto, co.nome as cor, t.nome as tamanho, pe.numero as pedido_numero, cl.nome as cliente, u.nome as usuario
from mali.estoque_mov m
join mali.produtos p on p.id = m.produto_id
join mali.cores co on co.id = m.cor_id
join mali.tamanhos t on t.id = m.tamanho_id
left join mali.pedidos pe on pe.id = m.pedido_id
left join mali.clientes cl on cl.id = m.cliente_id
left join mali.usuarios u on u.id = m.usuario_id;

create view mali.v_ops_estamparia with (security_invoker = true) as
select o.*, p.nome as produto, co.nome as cor, t.nome as tamanho, pe.numero as pedido_numero,
  case when o.retorno_em is not null then 'Concluída' when o.previsao < mali.hoje() then 'Atrasada' else 'Aguardando retorno' end as status
from mali.ops_estamparia o
join mali.produtos p on p.id = o.produto_id
join mali.cores co on co.id = o.cor_id
join mali.tamanhos t on t.id = o.tamanho_id
left join mali.pedidos pe on pe.id = o.pedido_id;

create view mali.v_expedicoes with (security_invoker = true) as
select x.*, p.nome as produto, co.nome as cor, t.nome as tamanho, pe.numero as pedido_numero, cl.nome as cliente,
  case when x.cancelado_em is not null then 'Cancelada' when x.liberado_em is not null then 'Liberada'
       when x.embalagem_fim is not null then 'Embalada' when x.embalagem_inicio is not null then 'Embalando' else 'Aguardando embalagem' end as status,
  mali._saldo_estoque(x.produto_id, x.cor_id, x.tamanho_id) as saldo_estoque
from mali.expedicoes x
join mali.produtos p on p.id = x.produto_id
join mali.cores co on co.id = x.cor_id
join mali.tamanhos t on t.id = x.tamanho_id
left join mali.pedidos pe on pe.id = x.pedido_id
left join mali.clientes cl on cl.id = x.cliente_id;

-- Lotes na produção interna com andamento por operação
create view mali.v_lotes_internos with (security_invoker = true) as
select e.id as envio_id, e.lote, e.qtd, e.previsao, e.produto_id, p.nome as produto, co.nome as cor, t.nome as tamanho, e.criado_em,
  (select count(*) from mali.produto_processos pp where pp.produto_id = e.produto_id)::int as operacoes,
  (select coalesce(sum(pp.tempo_seg),0) from mali.produto_processos pp where pp.produto_id = e.produto_id) as tempo_peca_seg,
  (select coalesce(sum(a.qtd * a.tempo_seg),0) from mali.apontamentos a where a.envio_id = e.id and a.fim is not null) as seg_produzidos,
  (select coalesce(jsonb_agg(jsonb_build_object('processo_id', pp.processo_id, 'processo', pr.nome, 'sequencia', pp.sequencia, 'tempo_seg', pp.tempo_seg,
      'feito', coalesce((select sum(a.qtd) from mali.apontamentos a where a.envio_id = e.id and a.processo_id = pp.processo_id and a.fim is not null),0))
      order by pp.sequencia), '[]'::jsonb)
   from mali.produto_processos pp join mali.processos pr on pr.id = pp.processo_id where pp.produto_id = e.produto_id) as roteiro
from mali.envios e
join mali.faccoes f on f.id = e.faccao_id and f.interna
join mali.produtos p on p.id = e.produto_id
join mali.cores co on co.id = e.cor_id
join mali.tamanhos t on t.id = e.tamanho_id
where e.data_retorno is null;

create view mali.v_apontamentos with (security_invoker = true) as
select a.*, o.nome as operador, pr.nome as processo, e.lote, p.nome as produto, co.nome as cor, t.nome as tamanho,
  (a.inicio at time zone 'America/Sao_Paulo')::date as dia,
  round(extract(epoch from (coalesce(a.fim, now()) - a.inicio)) / 60, 1) as minutos,
  round(coalesce(a.qtd,0) * a.tempo_seg / 60, 1) as minutos_padrao
from mali.apontamentos a
join mali.operadores o on o.id = a.operador_id
join mali.processos pr on pr.id = a.processo_id
join mali.envios e on e.id = a.envio_id
join mali.produtos p on p.id = e.produto_id
join mali.cores co on co.id = e.cor_id
join mali.tamanhos t on t.id = e.tamanho_id;

create view mali.v_pausas with (security_invoker = true) as
select x.*, o.nome as operador, m.nome as motivo, (x.inicio at time zone 'America/Sao_Paulo')::date as dia,
  round(extract(epoch from (coalesce(x.fim, now()) - x.inicio)) / 60, 1) as minutos
from mali.pausas x join mali.operadores o on o.id = x.operador_id join mali.motivos_parada m on m.id = x.motivo_id;

-- Eficiência por operador e dia: minutos padrão produzidos ÷ minutos apontados (descontando pausas não produtivas)
create view mali.v_eficiencia_dia with (security_invoker = true) as
select a.operador_id, a.operador, a.dia,
  sum(coalesce(a.qtd,0))::int as pecas,
  round(sum(a.minutos_padrao), 1) as min_padrao,
  round(sum(a.minutos), 1) as min_apontados,
  coalesce((select round(sum(pz.minutos),1) from mali.v_pausas pz join mali.motivos_parada m on m.id = pz.motivo_id
            where pz.operador_id = a.operador_id and pz.dia = a.dia and not m.produtiva), 0) as min_pausas,
  case when sum(a.minutos) - coalesce((select sum(pz.minutos) from mali.v_pausas pz join mali.motivos_parada m on m.id = pz.motivo_id
            where pz.operador_id = a.operador_id and pz.dia = a.dia and not m.produtiva), 0) > 0
       then round(100 * sum(a.minutos_padrao) / (sum(a.minutos) - coalesce((select sum(pz.minutos) from mali.v_pausas pz join mali.motivos_parada m on m.id = pz.motivo_id
            where pz.operador_id = a.operador_id and pz.dia = a.dia and not m.produtiva), 0)), 1) end as eficiencia
from mali.v_apontamentos a
where a.fim is not null
group by a.operador_id, a.operador, a.dia;

create view mali.v_fechamentos with (security_invoker = true) as
select fe.*, f.nome as faccao, u.nome as usuario,
  (select count(*) from mali.fechamento_itens i where i.fechamento_id = fe.id)::int as itens,
  (select coalesce(sum(i.qtd),0) from mali.fechamento_itens i where i.fechamento_id = fe.id)::int as pecas
from mali.fechamentos fe join mali.faccoes f on f.id = fe.faccao_id left join mali.usuarios u on u.id = fe.criado_por;

-- Custo do produto: matéria-prima (ficha técnica) + tempo do roteiro
create view mali.v_custo_produto with (security_invoker = true) as
select p.id as produto_id, p.nome as produto, p.codigo, p.preco, p.valor_faccao,
  coalesce((select sum(ft.consumo * mp.valor) from mali.ficha_tecnica ft join mali.materias_primas mp on mp.id = ft.materia_prima_id where ft.produto_id = p.id),0)::numeric(12,2) as custo_mp,
  coalesce((select sum(pp.tempo_seg) from mali.produto_processos pp where pp.produto_id = p.id),0) as tempo_seg,
  (select count(*) from mali.produto_processos pp where pp.produto_id = p.id)::int as operacoes,
  (select count(*) from mali.ficha_tecnica ft where ft.produto_id = p.id)::int as itens_mp
from mali.produtos p;

-- Painel
create or replace function mali.painel() returns jsonb
language sql stable security invoker set search_path to '' as $$
  select jsonb_build_object(
    'pedidos_abertos', (select count(*) from mali.pedidos where status = 'Aberto'),
    'pedidos_atrasados', (select count(*) from mali.pedidos where status = 'Aberto' and entrega < mali.hoje()),
    'cortes_programados', (select count(*) from mali.cortes where status = 'Programado'),
    'pecas_aguardando_distribuicao', (select coalesce(sum(qtd_saldo),0) from mali.sublotes),
    'pecas_em_faccao', (select coalesce(sum(mali._pendente_envio(id)),0) from mali.envios where data_retorno is null),
    'envios_atrasados', (select count(*) from mali.envios where data_retorno is null and previsao < mali.hoje()),
    'etapas', (select coalesce(jsonb_object_agg(tipo, n), '{}'::jsonb) from (select tipo, sum(qtd) n from mali.etapas where fim is null group by tipo) x),
    'em_conserto', (select coalesce(sum(qtd),0) from mali.consertos where recebido_em is null),
    'estoque_total', (select coalesce(sum(case when tipo='SAÍDA' then -qtd else qtd end),0) from mali.estoque_mov),
    'expedicoes_pendentes', (select count(*) from mali.expedicoes where liberado_em is null and cancelado_em is null),
    'a_pagar', (select coalesce(sum(round(r.qtd * r.valor_unit,2)),0) from mali.retornos r where r.fechamento_id is null)
             + (select coalesce(sum(round(coalesce(c.qtd_recebida,0) * c.valor_unit,2)),0) from mali.consertos c where c.fechamento_id is null and c.recebido_em is not null),
    'operadores_trabalhando', (select count(*) from mali.apontamentos where fim is null),
    'producao_hoje', (select coalesce(sum(qtd),0) from mali.apontamentos where fim is not null and (fim at time zone 'America/Sao_Paulo')::date = mali.hoje())
  );
$$;

-- ---------- RLS ----------
do $$
declare t text;
begin
  for t in select tablename from pg_tables where schemaname = 'mali' loop
    execute format('alter table mali.%I enable row level security', t);
    execute format('grant select on mali.%I to authenticated', t);
    if t not in ('usuarios','auditoria') then
      execute format('create policy leitura_usuarios on mali.%I for select to authenticated using ((select mali.eh_usuario()))', t);
    end if;
  end loop;
end $$;

create policy usuario_ve_proprio on mali.usuarios for select to authenticated
  using (id = (select auth.uid()) or (select mali.tem_perfil('admin')));
create policy admin_le_auditoria on mali.auditoria for select to authenticated using ((select mali.tem_perfil('admin')));

-- Cadastros: escrita direta para quem tem o perfil "cadastros" (clientes também para "comercial")
do $$
declare t text;
begin
  foreach t in array array['cores','tamanhos','produtos','faccoes','operadores','processos','motivos_parada','materias_primas',
                           'fichas_produto','ficha_medidas','ficha_tecnica'] loop
    execute format('grant insert, update, delete on mali.%I to authenticated', t);
    execute format('create policy cadastros_insere on mali.%I for insert to authenticated with check ((select mali.tem_perfil(''cadastros'')))', t);
    execute format('create policy cadastros_altera on mali.%I for update to authenticated using ((select mali.tem_perfil(''cadastros''))) with check ((select mali.tem_perfil(''cadastros'')))', t);
    execute format('create policy cadastros_exclui on mali.%I for delete to authenticated using ((select mali.tem_perfil(''cadastros'')))', t);
  end loop;
end $$;
grant insert, update, delete on mali.clientes to authenticated;
create policy clientes_insere on mali.clientes for insert to authenticated with check ((select mali.tem_perfil('cadastros') or mali.tem_perfil('comercial')));
create policy clientes_altera on mali.clientes for update to authenticated using ((select mali.tem_perfil('cadastros') or mali.tem_perfil('comercial'))) with check ((select mali.tem_perfil('cadastros') or mali.tem_perfil('comercial')));
create policy clientes_exclui on mali.clientes for delete to authenticated using ((select mali.tem_perfil('cadastros')));

-- Sequências das tabelas com identity usadas nos inserts diretos
grant usage on all sequences in schema mali to authenticated;

-- Views
grant select on all tables in schema mali to authenticated;

-- Funções: só as públicas ficam executáveis; as auxiliares (_*) não
revoke execute on all functions in schema mali from public, anon;
grant execute on all functions in schema mali to authenticated;
do $$
declare f record;
begin
  for f in select p.oid::regprocedure as sig from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'mali' and p.proname like '\_%' loop
    execute format('revoke execute on function %s from authenticated', f.sig);
  end loop;
end $$;
-- usadas dentro de views com security_invoker: precisam ser executáveis por quem lê
grant execute on function mali._saldo_estoque(bigint,bigint,bigint) to authenticated;
grant execute on function mali._pendente_envio(uuid) to authenticated;

alter default privileges in schema mali revoke execute on functions from public, anon;
