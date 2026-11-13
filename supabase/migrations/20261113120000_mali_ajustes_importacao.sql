-- Ajustes antes da importação do histórico do AppSheet
-- 1) Produção interna também recebe valor por peça (como no AppSheet)
create or replace function mali.enviar_faccao(p_faccao_id bigint, p_itens jsonb, p_token text, p_previsao date default null,
  p_aviamentos jsonb default null, p_obs text default null) returns jsonb
language plpgsql security definer set search_path to '' as $$
declare f record; it jsonb; s record; v_rem uuid; v_qtd int; v_val numeric; v_prev date := coalesce(p_previsao, mali.hoje() + 7);
        v_tot_q int := 0; v_tot_v numeric := 0; v_ids uuid[] := '{}'; av jsonb := coalesce(p_aviamentos, '{}'::jsonb);
begin
  perform mali.exigir_perfil('faccao');
  if p_token is null or p_token !~ '^[A-Za-z0-9_-]{12,100}$' then raise exception 'Token de confirmação inválido.'; end if;
  select id into v_rem from mali.remessas where token = p_token;
  if v_rem is not null then return jsonb_build_object('remessa_id', v_rem, 'ja_processado', true); end if;
  select * into f from mali.faccoes where id = p_faccao_id and ativo;
  if not found then raise exception 'Facção inexistente ou inativa.'; end if;
  if jsonb_array_length(coalesce(p_itens,'[]')) = 0 then raise exception 'Nenhum sublote para enviar.'; end if;
  if jsonb_array_length(p_itens) > 150 then raise exception 'Máximo de 150 sublotes por envio.'; end if;
  insert into mali.remessas(token, faccao_id, previsao, obs, vies, fio, linha, elastico, alca, etiqueta)
  values (p_token, p_faccao_id, v_prev, p_obs, (av->>'vies')::numeric, (av->>'fio')::numeric, (av->>'linha')::numeric,
          (av->>'elastico')::numeric, (av->>'alca')::numeric, (av->>'etiqueta')::numeric)
  returning id into v_rem;
  for it in select * from jsonb_array_elements(p_itens) loop
    if (it->>'sublote_id')::uuid = any(v_ids) then raise exception 'Sublote duplicado na solicitação.'; end if;
    v_ids := v_ids || (it->>'sublote_id')::uuid;
    select * into s from mali.sublotes where id = (it->>'sublote_id')::uuid for update;
    if not found then raise exception 'Sublote inexistente.'; end if;
    v_qtd := (it->>'qtd')::int;
    if v_qtd is null or v_qtd <= 0 or v_qtd > s.qtd_saldo then raise exception 'Quantidade inválida para % (disponível: %).', s.codigo, s.qtd_saldo; end if;
    v_val := coalesce(nullif(it->>'valor_unit','')::numeric, (select valor_faccao from mali.produtos where id = s.produto_id), 0);
    if v_val < 0 then raise exception 'Valor inválido.'; end if;
    insert into mali.envios(remessa_id, sublote_id, faccao_id, produto_id, cor_id, tamanho_id, lote, qtd, valor_unit, previsao)
    values (v_rem, s.id, p_faccao_id, s.produto_id, s.cor_id, s.tamanho_id, s.codigo, v_qtd, v_val, v_prev);
    update mali.sublotes set qtd_saldo = qtd_saldo - v_qtd where id = s.id;
    v_tot_q := v_tot_q + v_qtd; v_tot_v := v_tot_v + v_qtd * v_val;
  end loop;
  perform mali._audit('enviar_faccao', 'remessas', v_rem::text, jsonb_build_object('faccao', f.nome, 'qtd', v_tot_q, 'valor', v_tot_v));
  return jsonb_build_object('remessa_id', v_rem, 'ja_processado', false, 'qtd_total', v_tot_q, 'valor_total', round(v_tot_v, 2));
end $$;

-- 2) Total de peças do corte: depois de cortado vale a soma dos sublotes (lotes importados não têm folhas × riscos exatos)
create or replace view mali.v_cortes with (security_invoker = true) as
select c.id, c.numero, c.mes, c.lote, c.data, c.produto_id, c.pedido_id, c.destino, c.status, c.obs, c.cortado_em, c.criado_em,
  p.nome as produto, pe.numero as pedido_numero,
  (select jsonb_agg(jsonb_build_object('posicao', x.posicao, 'cor_id', x.cor_id, 'cor', k.nome, 'folhas', x.folhas) order by x.posicao)
     from mali.corte_cores x join mali.cores k on k.id = x.cor_id where x.corte_id = c.id) as cores,
  (select jsonb_agg(jsonb_build_object('posicao', y.posicao, 'tamanho_id', y.tamanho_id, 'tamanho', t.nome, 'riscos', y.riscos) order by y.posicao)
     from mali.corte_tamanhos y join mali.tamanhos t on t.id = y.tamanho_id where y.corte_id = c.id) as tamanhos,
  coalesce((select sum(s.qtd_cortada) from mali.sublotes s where s.corte_id = c.id),
    (select coalesce(sum(folhas),0) from mali.corte_cores where corte_id = c.id) *
    (select coalesce(sum(riscos),0) from mali.corte_tamanhos where corte_id = c.id))::int as total_pecas
from mali.cortes c
join mali.produtos p on p.id = c.produto_id
left join mali.pedidos pe on pe.id = c.pedido_id;
