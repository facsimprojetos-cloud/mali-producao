-- MALI — Parte 3: regras de negócio (funções chamadas pelo app)

-- ================= Auxiliares =================
create or replace function mali._saldo_estoque(p_produto bigint, p_cor bigint, p_tam bigint) returns int
language sql stable security invoker set search_path to '' as $$
  select coalesce(sum(case when tipo = 'SAÍDA' then -qtd else qtd end), 0)::int
  from mali.estoque_mov where produto_id = p_produto and cor_id = p_cor and tamanho_id = p_tam;
$$;

create or replace function mali._entrada_estoque(p_origem text, p_origem_id uuid, p_sublote_id uuid, p_qtd int, p_obs text default null) returns void
language plpgsql security definer set search_path to '' as $$
declare s record;
begin
  if p_qtd <= 0 then return; end if;
  select * into s from mali.sublotes where id = p_sublote_id;
  insert into mali.estoque_mov(tipo, origem, origem_id, produto_id, cor_id, tamanho_id, qtd, lote, pedido_id, obs)
  values ('ENTRADA', p_origem, p_origem_id, s.produto_id, s.cor_id, s.tamanho_id, p_qtd, s.codigo, s.pedido_id, p_obs);
end $$;

-- Remove a entrada de estoque gerada por um registro (estornos). Falha se o saldo ficaria negativo.
create or replace function mali._desfazer_entrada(p_origem_id uuid) returns void
language plpgsql security definer set search_path to '' as $$
declare m record;
begin
  for m in select * from mali.estoque_mov where origem_id = p_origem_id and tipo = 'ENTRADA' loop
    if mali._saldo_estoque(m.produto_id, m.cor_id, m.tamanho_id) < m.qtd then
      raise exception 'Não é possível estornar: as peças já saíram do estoque.'; end if;
    delete from mali.estoque_mov where id = m.id;
  end loop;
end $$;

create or replace function mali._nova_etapa(p_tipo text, p_sublote uuid, p_origem text, p_origem_id uuid, p_faccao bigint, p_qtd int) returns uuid
language plpgsql security definer set search_path to '' as $$
declare v uuid;
begin
  if p_qtd <= 0 then return null; end if;
  insert into mali.etapas(tipo, sublote_id, origem, origem_id, faccao_id, qtd)
  values (p_tipo, p_sublote, p_origem, p_origem_id, p_faccao, p_qtd) returning id into v;
  return v;
end $$;

-- Encaminha peças boas para o próximo destino
create or replace function mali._encaminhar(p_destino text, p_sublote uuid, p_origem text, p_origem_id uuid, p_faccao bigint, p_qtd int) returns void
language plpgsql security definer set search_path to '' as $$
begin
  if p_qtd <= 0 then return; end if;
  if p_destino = 'ESTOQUE' then
    perform mali._entrada_estoque('PRODUÇÃO', p_origem_id, p_sublote, p_qtd);
  elsif p_destino = 'FACÇÃO' then
    update mali.sublotes set qtd_saldo = qtd_saldo + p_qtd where id = p_sublote;
  elsif p_destino in ('ESTAMPARIA','FINALIZAÇÃO','INSPEÇÃO') then
    perform mali._nova_etapa(p_destino, p_sublote, p_origem, p_origem_id, p_faccao, p_qtd);
  else
    raise exception 'Destino inválido: %', p_destino;
  end if;
end $$;

-- Desfaz o encaminhamento (estornos)
create or replace function mali._desfazer_encaminhamento(p_destino text, p_sublote uuid, p_origem_id uuid, p_qtd int) returns void
language plpgsql security definer set search_path to '' as $$
begin
  if p_qtd is null or p_qtd <= 0 then return; end if;
  if p_destino = 'ESTOQUE' then
    perform mali._desfazer_entrada(p_origem_id);
  elsif p_destino = 'FACÇÃO' then
    update mali.sublotes set qtd_saldo = qtd_saldo - p_qtd where id = p_sublote and qtd_saldo >= p_qtd;
    if not found then raise exception 'Não é possível estornar: as peças já foram enviadas para facção.'; end if;
  else
    if exists (select 1 from mali.etapas where origem_id = p_origem_id and inicio is not null) then
      raise exception 'Não é possível estornar: a etapa seguinte já foi iniciada.'; end if;
    delete from mali.etapas where origem_id = p_origem_id;
  end if;
end $$;

-- ================= Pedidos =================
create or replace function mali.salvar_pedido(p_id uuid, p_cliente_id bigint, p_data date, p_entrega date, p_obs text, p_itens jsonb) returns uuid
language plpgsql security definer set search_path to '' as $$
declare v_id uuid := p_id; v_num int; it jsonb; v_ids uuid[] := '{}'; v_item uuid; r record;
begin
  perform mali.exigir_perfil('comercial');
  if not exists (select 1 from mali.clientes where id = p_cliente_id) then raise exception 'Cliente inválido.'; end if;
  if jsonb_array_length(coalesce(p_itens,'[]')) = 0 then raise exception 'Inclua ao menos um item.'; end if;
  if v_id is null then
    perform pg_advisory_xact_lock(hashtext('mali.pedido'));
    select coalesce(max(numero),0)+1 into v_num from mali.pedidos;
    insert into mali.pedidos(numero, data, cliente_id, entrega, obs) values (v_num, coalesce(p_data, mali.hoje()), p_cliente_id, p_entrega, p_obs)
    returning id into v_id;
  else
    update mali.pedidos set cliente_id = p_cliente_id, data = coalesce(p_data, data), entrega = p_entrega, obs = p_obs
    where id = v_id and status = 'Aberto';
    if not found then raise exception 'Pedido não encontrado ou não está aberto.'; end if;
  end if;
  for it in select * from jsonb_array_elements(p_itens) loop
    if coalesce((it->>'qtd')::int,0) <= 0 then raise exception 'Quantidade inválida.'; end if;
    if nullif(it->>'id','') is not null then
      v_item := (it->>'id')::uuid;
      update mali.pedido_itens set produto_id = (it->>'produto_id')::bigint, cor_id = (it->>'cor_id')::bigint,
        tamanho_id = (it->>'tamanho_id')::bigint, qtd = (it->>'qtd')::int, estampa = it->>'estampa', tag = it->>'tag', obs = it->>'obs'
      where id = v_item and pedido_id = v_id;
      if not found then raise exception 'Item inválido.'; end if;
      if exists (select 1 from mali.pedido_itens where id = v_item and qtd < qtd_entregue) then
        raise exception 'A quantidade não pode ser menor que a já entregue.'; end if;
    else
      insert into mali.pedido_itens(pedido_id, produto_id, cor_id, tamanho_id, qtd, estampa, tag, obs)
      values (v_id, (it->>'produto_id')::bigint, (it->>'cor_id')::bigint, (it->>'tamanho_id')::bigint, (it->>'qtd')::int,
              it->>'estampa', it->>'tag', it->>'obs') returning id into v_item;
    end if;
    v_ids := v_ids || v_item;
  end loop;
  for r in select * from mali.pedido_itens where pedido_id = v_id and id <> all(v_ids) loop
    if r.qtd_entregue > 0 or exists (select 1 from mali.expedicoes e where e.pedido_item_id = r.id and e.cancelado_em is null) then
      raise exception 'Um item com expedição não pode ser removido.'; end if;
    delete from mali.pedido_itens where id = r.id;
  end loop;
  perform mali._audit(case when p_id is null then 'criar_pedido' else 'editar_pedido' end, 'pedidos', v_id::text, jsonb_build_object('itens', jsonb_array_length(p_itens)));
  return v_id;
end $$;

create or replace function mali.cancelar_pedido(p_id uuid, p_motivo text) returns void
language plpgsql security definer set search_path to '' as $$
begin
  perform mali.exigir_perfil('comercial');
  update mali.expedicoes set cancelado_em = now() where pedido_id = p_id and liberado_em is null and cancelado_em is null;
  update mali.pedidos set status = 'Cancelado', obs = concat_ws(' | ', obs, 'Cancelado: ' || p_motivo) where id = p_id and status = 'Aberto';
  if not found then raise exception 'Pedido não encontrado ou não está aberto.'; end if;
  perform mali._audit('cancelar_pedido', 'pedidos', p_id::text, jsonb_build_object('motivo', p_motivo));
end $$;

create or replace function mali.reabrir_pedido(p_id uuid) returns void
language plpgsql security definer set search_path to '' as $$
begin
  perform mali.exigir_perfil('supervisor');
  update mali.pedidos set status = 'Aberto' where id = p_id and status <> 'Aberto';
  if not found then raise exception 'Pedido não encontrado ou já aberto.'; end if;
  perform mali._audit('reabrir_pedido', 'pedidos', p_id::text, null);
end $$;

-- ================= Corte =================
create or replace function mali._grava_grade(p_corte_id uuid, p_cores jsonb, p_tamanhos jsonb) returns void
language plpgsql security definer set search_path to '' as $$
begin
  if jsonb_array_length(coalesce(p_cores,'[]')) = 0 or jsonb_array_length(coalesce(p_tamanhos,'[]')) = 0 then
    raise exception 'Informe ao menos uma cor e um tamanho.'; end if;
  if jsonb_array_length(p_cores) > 20 or jsonb_array_length(p_tamanhos) > 8 then
    raise exception 'Máximo de 20 cores e 8 tamanhos.'; end if;
  delete from mali.corte_cores where corte_id = p_corte_id;
  delete from mali.corte_tamanhos where corte_id = p_corte_id;
  insert into mali.corte_cores(corte_id, posicao, cor_id, folhas)
  select p_corte_id, t.i, (t.e->>'cor_id')::bigint, (t.e->>'folhas')::int from jsonb_array_elements(p_cores) with ordinality t(e,i);
  insert into mali.corte_tamanhos(corte_id, posicao, tamanho_id, riscos)
  select p_corte_id, t.i, (t.e->>'tamanho_id')::bigint, (t.e->>'riscos')::int from jsonb_array_elements(p_tamanhos) with ordinality t(e,i);
end $$;

create or replace function mali.criar_corte(p_produto_id bigint, p_destino text, p_cores jsonb, p_tamanhos jsonb,
  p_pedido_id uuid default null, p_data timestamptz default null, p_obs text default null) returns uuid
language plpgsql security definer set search_path to '' as $$
declare v_id uuid; v_data timestamptz := coalesce(p_data, now()); v_mes date; v_num int; v_lote text;
begin
  perform mali.exigir_perfil('corte');
  if coalesce(p_destino,'') not in ('PRODUÇÃO','ESTAMPARIA') then raise exception 'Destino inválido.'; end if;
  if not exists (select 1 from mali.produtos where id = p_produto_id and ativo) then raise exception 'Produto inexistente ou inativo.'; end if;
  if p_pedido_id is not null and not exists (select 1 from mali.pedidos where id = p_pedido_id and status = 'Aberto') then
    raise exception 'Pedido não está aberto.'; end if;
  v_mes := date_trunc('month', v_data at time zone 'America/Sao_Paulo')::date;
  perform pg_advisory_xact_lock(hashtext('mali.lote.' || v_mes::text));
  select coalesce(max(numero), 0) + 1 into v_num from mali.cortes where mes = v_mes;
  v_lote := v_num::text || '-' || to_char(v_mes, 'MM YYYY');
  insert into mali.cortes(numero, mes, lote, data, produto_id, pedido_id, destino, obs)
  values (v_num, v_mes, v_lote, v_data, p_produto_id, p_pedido_id, p_destino, p_obs) returning id into v_id;
  perform mali._grava_grade(v_id, p_cores, p_tamanhos);
  perform mali._audit('criar_corte', 'cortes', v_id::text, jsonb_build_object('lote', v_lote));
  return v_id;
end $$;

create or replace function mali.editar_corte(p_corte_id uuid, p_produto_id bigint, p_destino text, p_cores jsonb, p_tamanhos jsonb,
  p_pedido_id uuid default null, p_obs text default null) returns void
language plpgsql security definer set search_path to '' as $$
begin
  perform mali.exigir_perfil('corte');
  if coalesce(p_destino,'') not in ('PRODUÇÃO','ESTAMPARIA') then raise exception 'Destino inválido.'; end if;
  update mali.cortes set produto_id = p_produto_id, destino = p_destino, pedido_id = p_pedido_id, obs = p_obs
  where id = p_corte_id and status = 'Programado';
  if not found then raise exception 'Só é possível editar pedidos de corte ainda não cortados.'; end if;
  perform mali._grava_grade(p_corte_id, p_cores, p_tamanhos);
  perform mali._audit('editar_corte', 'cortes', p_corte_id::text, null);
end $$;

create or replace function mali.confirmar_corte(p_corte_id uuid, p_ajustes jsonb default null) returns jsonb
language plpgsql security definer set search_path to '' as $$
declare c record; cc record; ct record; v_n int := 0; v_qtd int; v_sub uuid; v_codigo text;
        v_labels jsonb := '[]'::jsonb; v_total int := 0; v_prod text; r int; a jsonb; v_bloco int;
begin
  perform mali.exigir_perfil('corte');
  select * into c from mali.cortes where id = p_corte_id for update;
  if not found then raise exception 'Corte não encontrado.'; end if;
  if c.status = 'Cortado' then
    return jsonb_build_object('ja_confirmado', true, 'etiquetas', c.etiquetas, 'mensagem', 'Corte já confirmado. Etiquetas recuperadas.');
  end if;
  if c.status <> 'Programado' then raise exception 'Corte indisponível: status atual é "%".', c.status; end if;
  if p_ajustes is not null then
    for a in select * from jsonb_array_elements(coalesce(p_ajustes->'cores','[]')) loop
      if (a->>'folhas')::int <= 0 then raise exception 'Folhas inválidas.'; end if;
      update mali.corte_cores set folhas = (a->>'folhas')::int where corte_id = p_corte_id and posicao = (a->>'posicao')::int;
    end loop;
    for a in select * from jsonb_array_elements(coalesce(p_ajustes->'tamanhos','[]')) loop
      if (a->>'riscos')::int <= 0 then raise exception 'Riscos inválidos.'; end if;
      update mali.corte_tamanhos set riscos = (a->>'riscos')::int where corte_id = p_corte_id and posicao = (a->>'posicao')::int;
    end loop;
  end if;
  select nome into v_prod from mali.produtos where id = c.produto_id;
  -- numeração dos sublotes como no app antigo: tamanho 1 → .1, .2…; tamanho 2 → .21, .22…; tamanho 3 → .41…
  for ct in select y.*, t.nome as tamanho from mali.corte_tamanhos y join mali.tamanhos t on t.id = y.tamanho_id where y.corte_id = p_corte_id order by y.posicao loop
    v_bloco := (ct.posicao - 1) * 20;
    v_n := 0;
    for cc in select x.*, k.nome as cor from mali.corte_cores x join mali.cores k on k.id = x.cor_id where x.corte_id = p_corte_id order by x.posicao loop
      v_n := v_n + 1;
      v_qtd := cc.folhas * ct.riscos; v_total := v_total + v_qtd;
      v_codigo := c.lote || '.' || (v_bloco + v_n);
      insert into mali.sublotes(codigo, lote, corte_id, produto_id, cor_id, tamanho_id, pedido_id, qtd_cortada, qtd_saldo)
      values (v_codigo, c.lote, p_corte_id, c.produto_id, cc.cor_id, ct.tamanho_id, c.pedido_id, v_qtd,
              case when c.destino = 'ESTAMPARIA' then 0 else v_qtd end)
      returning id into v_sub;
      if c.destino = 'ESTAMPARIA' then perform mali._nova_etapa('ESTAMPARIA', v_sub, 'CORTE', p_corte_id, null, v_qtd); end if;
      for r in 1..ct.riscos loop
        v_labels := v_labels || jsonb_build_object('lote', c.lote, 'produto', v_prod,
          'data', to_char(c.data at time zone 'America/Sao_Paulo','DD/MM/YYYY'), 'sublote', v_codigo,
          'cor', cc.cor, 'tamanho', ct.tamanho, 'pacote', r, 'total_pacotes', ct.riscos, 'quantidade', cc.folhas);
      end loop;
    end loop;
  end loop;
  update mali.cortes set status = 'Cortado', cortado_em = now(), cortado_por = auth.uid(), etiquetas = v_labels where id = p_corte_id;
  perform mali._audit('confirmar_corte', 'cortes', p_corte_id::text, jsonb_build_object('pecas', v_total));
  return jsonb_build_object('ja_confirmado', false, 'total_pecas', v_total, 'etiquetas', v_labels,
    'mensagem', (select count(*) from mali.sublotes where corte_id = p_corte_id) || ' sublotes gravados; ' || jsonb_array_length(v_labels) || ' etiquetas prontas.');
end $$;

create or replace function mali.cancelar_corte(p_corte_id uuid, p_motivo text) returns void
language plpgsql security definer set search_path to '' as $$
begin
  perform mali.exigir_perfil('corte');
  update mali.cortes set status = 'Cancelado', obs = concat_ws(' | ', obs, 'Cancelado: ' || p_motivo)
  where id = p_corte_id and status = 'Programado';
  if not found then raise exception 'Só é possível cancelar pedidos de corte ainda não cortados.'; end if;
  perform mali._audit('cancelar_corte', 'cortes', p_corte_id::text, jsonb_build_object('motivo', p_motivo));
end $$;

create or replace function mali.estornar_corte(p_corte_id uuid, p_motivo text) returns void
language plpgsql security definer set search_path to '' as $$
begin
  perform mali.exigir_perfil('supervisor');
  perform 1 from mali.cortes where id = p_corte_id and status = 'Cortado' for update;
  if not found then raise exception 'Corte não está cortado.'; end if;
  if exists (select 1 from mali.envios e join mali.sublotes s on s.id = e.sublote_id where s.corte_id = p_corte_id) then
    raise exception 'Há sublotes enviados para facção. Exclua os envios antes.'; end if;
  if exists (select 1 from mali.etapas t join mali.sublotes s on s.id = t.sublote_id where s.corte_id = p_corte_id and t.inicio is not null) then
    raise exception 'A estamparia deste corte já começou.'; end if;
  delete from mali.etapas where sublote_id in (select id from mali.sublotes where corte_id = p_corte_id);
  delete from mali.sublotes where corte_id = p_corte_id;
  update mali.cortes set status = 'Programado', etiquetas = null, cortado_em = null, cortado_por = null where id = p_corte_id;
  perform mali._audit('estornar_corte', 'cortes', p_corte_id::text, jsonb_build_object('motivo', p_motivo));
end $$;

create or replace function mali.excluir_corte(p_corte_id uuid, p_motivo text) returns void
language plpgsql security definer set search_path to '' as $$
begin
  perform mali.exigir_perfil('supervisor');
  delete from mali.cortes where id = p_corte_id and status in ('Programado','Cancelado');
  if not found then raise exception 'Só é possível excluir pedidos de corte não cortados (estorne antes).'; end if;
  perform mali._audit('excluir_corte', 'cortes', p_corte_id::text, jsonb_build_object('motivo', p_motivo));
end $$;

-- ================= Facção =================
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
    if f.interna then v_val := 0; end if;
    if v_val < 0 then raise exception 'Valor inválido.'; end if;
    insert into mali.envios(remessa_id, sublote_id, faccao_id, produto_id, cor_id, tamanho_id, lote, qtd, valor_unit, previsao)
    values (v_rem, s.id, p_faccao_id, s.produto_id, s.cor_id, s.tamanho_id, s.codigo, v_qtd, v_val, v_prev);
    update mali.sublotes set qtd_saldo = qtd_saldo - v_qtd where id = s.id;
    v_tot_q := v_tot_q + v_qtd; v_tot_v := v_tot_v + v_qtd * v_val;
  end loop;
  perform mali._audit('enviar_faccao', 'remessas', v_rem::text, jsonb_build_object('faccao', f.nome, 'qtd', v_tot_q, 'valor', v_tot_v));
  return jsonb_build_object('remessa_id', v_rem, 'ja_processado', false, 'qtd_total', v_tot_q, 'valor_total', round(v_tot_v, 2));
end $$;

create or replace function mali._pendente_envio(p_envio uuid) returns int
language sql stable security invoker set search_path to '' as $$
  select e.qtd - coalesce((select sum(r.qtd + r.qtd_defeito) from mali.retornos r where r.envio_id = e.id), 0)::int
  from mali.envios e where e.id = p_envio;
$$;

create or replace function mali.registrar_retorno(p_envio_id uuid, p_qtd int, p_defeito int, p_proximo text,
  p_data date default null, p_obs text default null) returns uuid
language plpgsql security definer set search_path to '' as $$
declare e record; v_id uuid; v_pend int;
begin
  perform mali.exigir_perfil('faccao');
  select * into e from mali.envios where id = p_envio_id for update;
  if not found then raise exception 'Envio não encontrado.'; end if;
  if e.data_retorno is not null then raise exception 'Este envio já foi finalizado.'; end if;
  p_qtd := coalesce(p_qtd,0); p_defeito := coalesce(p_defeito,0);
  if p_qtd < 0 or p_defeito < 0 or p_qtd + p_defeito = 0 then raise exception 'Informe a quantidade retornada.'; end if;
  if p_proximo not in ('ESTAMPARIA','FINALIZAÇÃO','INSPEÇÃO','ESTOQUE') then raise exception 'Próximo processo inválido.'; end if;
  v_pend := mali._pendente_envio(e.id);
  if p_qtd + p_defeito > v_pend then raise exception 'Quantidade maior que o pendente (pendente: %).', v_pend; end if;
  insert into mali.retornos(envio_id, data_retorno, qtd, qtd_defeito, proximo, valor_unit, obs)
  values (e.id, coalesce(p_data, mali.hoje()), p_qtd, p_defeito, p_proximo, e.valor_unit, p_obs) returning id into v_id;
  perform mali._encaminhar(p_proximo, e.sublote_id, 'RETORNO', v_id, e.faccao_id, p_qtd);
  if p_defeito > 0 then
    insert into mali.consertos(origem, origem_id, sublote_id, faccao_id, qtd, valor_unit, obs)
    values ('RETORNO', v_id, e.sublote_id, e.faccao_id, p_defeito, e.valor_unit, p_obs);
  end if;
  if mali._pendente_envio(e.id) = 0 then update mali.envios set data_retorno = coalesce(p_data, mali.hoje()) where id = e.id; end if;
  perform mali._audit('registrar_retorno', 'retornos', v_id::text, jsonb_build_object('envio', e.id, 'qtd', p_qtd, 'defeito', p_defeito, 'proximo', p_proximo));
  return v_id;
end $$;

create or replace function mali.excluir_retorno(p_retorno_id uuid, p_motivo text) returns void
language plpgsql security definer set search_path to '' as $$
declare r record; e record;
begin
  perform mali.exigir_perfil('supervisor');
  select * into r from mali.retornos where id = p_retorno_id for update;
  if not found then raise exception 'Retorno não encontrado.'; end if;
  if r.fechamento_id is not null then raise exception 'Retorno já pago. Estorne o fechamento antes.'; end if;
  if exists (select 1 from mali.consertos where origem = 'RETORNO' and origem_id = r.id and (recebido_em is not null or fechamento_id is not null)) then
    raise exception 'O conserto deste retorno já foi recebido.'; end if;
  select * into e from mali.envios where id = r.envio_id;
  perform mali._desfazer_encaminhamento(r.proximo, e.sublote_id, r.id, r.qtd);
  delete from mali.consertos where origem = 'RETORNO' and origem_id = r.id;
  delete from mali.retornos where id = r.id;
  update mali.envios set data_retorno = null where id = e.id;
  perform mali._audit('excluir_retorno', 'retornos', r.id::text, jsonb_build_object('motivo', p_motivo, 'qtd', r.qtd));
end $$;

create or replace function mali.excluir_envio(p_envio_id uuid, p_motivo text) returns void
language plpgsql security definer set search_path to '' as $$
declare e record;
begin
  perform mali.exigir_perfil('supervisor');
  select * into e from mali.envios where id = p_envio_id for update;
  if not found then raise exception 'Envio não encontrado.'; end if;
  if exists (select 1 from mali.retornos where envio_id = e.id) then raise exception 'Este envio já tem retorno. Exclua os retornos antes.'; end if;
  if exists (select 1 from mali.apontamentos where envio_id = e.id) then raise exception 'Este envio já tem apontamentos de produção.'; end if;
  update mali.sublotes set qtd_saldo = qtd_saldo + e.qtd where id = e.sublote_id;
  delete from mali.envios where id = e.id;
  delete from mali.remessas r where r.id = e.remessa_id and not exists (select 1 from mali.envios x where x.remessa_id = r.id);
  perform mali._audit('excluir_envio', 'envios', e.id::text, jsonb_build_object('motivo', p_motivo, 'qtd', e.qtd, 'lote', e.lote));
end $$;

-- Finaliza um envio com saldo pendente (peças perdidas / não devolvidas)
create or replace function mali.finalizar_envio(p_envio_id uuid, p_motivo text) returns void
language plpgsql security definer set search_path to '' as $$
begin
  perform mali.exigir_perfil('faccao');
  update mali.envios set data_retorno = mali.hoje(), ocorrencia = concat_ws(' | ', ocorrencia, 'Finalizado: ' || p_motivo)
  where id = p_envio_id and data_retorno is null;
  if not found then raise exception 'Envio não encontrado ou já finalizado.'; end if;
  perform mali._audit('finalizar_envio', 'envios', p_envio_id::text, jsonb_build_object('motivo', p_motivo, 'pendente', mali._pendente_envio(p_envio_id)));
end $$;

create or replace function mali.reabrir_envio(p_envio_id uuid) returns void
language plpgsql security definer set search_path to '' as $$
begin
  perform mali.exigir_perfil('supervisor');
  if mali._pendente_envio(p_envio_id) = 0 then raise exception 'Envio sem saldo pendente; não há o que reabrir.'; end if;
  update mali.envios set data_retorno = null where id = p_envio_id;
  perform mali._audit('reabrir_envio', 'envios', p_envio_id::text, null);
end $$;

create or replace function mali.registrar_ocorrencia(p_envio_id uuid, p_texto text) returns void
language plpgsql security definer set search_path to '' as $$
begin
  perform mali.exigir_perfil('faccao');
  update mali.envios set ocorrencia = nullif(trim(p_texto),'') where id = p_envio_id;
  perform mali._audit('ocorrencia', 'envios', p_envio_id::text, jsonb_build_object('texto', p_texto));
end $$;

create or replace function mali.editar_remessa(p_remessa_id uuid, p_previsao date, p_aviamentos jsonb, p_obs text) returns void
language plpgsql security definer set search_path to '' as $$
declare av jsonb := coalesce(p_aviamentos,'{}'::jsonb);
begin
  perform mali.exigir_perfil('faccao');
  update mali.remessas set previsao = p_previsao, obs = p_obs, vies = (av->>'vies')::numeric, fio = (av->>'fio')::numeric,
    linha = (av->>'linha')::numeric, elastico = (av->>'elastico')::numeric, alca = (av->>'alca')::numeric, etiqueta = (av->>'etiqueta')::numeric
  where id = p_remessa_id;
  update mali.envios set previsao = p_previsao where remessa_id = p_remessa_id and data_retorno is null;
  perform mali._audit('editar_remessa', 'remessas', p_remessa_id::text, null);
end $$;

-- ================= Consertos =================
create or replace function mali.receber_conserto(p_conserto_id uuid, p_qtd int, p_perda int, p_proximo text, p_obs text default null) returns void
language plpgsql security definer set search_path to '' as $$
declare c record;
begin
  perform mali.exigir_perfil('faccao');
  select * into c from mali.consertos where id = p_conserto_id for update;
  if not found then raise exception 'Conserto não encontrado.'; end if;
  if c.recebido_em is not null then raise exception 'Conserto já recebido.'; end if;
  p_qtd := coalesce(p_qtd,0); p_perda := coalesce(p_perda,0);
  if p_qtd < 0 or p_perda < 0 or p_qtd + p_perda <> c.qtd then raise exception 'Recebidas + perdidas deve ser igual a % peças.', c.qtd; end if;
  if p_proximo not in ('ESTAMPARIA','FINALIZAÇÃO','INSPEÇÃO','ESTOQUE') then raise exception 'Próximo processo inválido.'; end if;
  update mali.consertos set recebido_em = mali.hoje(), qtd_recebida = p_qtd, qtd_perda = p_perda, obs = concat_ws(' | ', obs, p_obs) where id = c.id;
  perform mali._encaminhar(p_proximo, c.sublote_id, 'CONSERTO', c.id, c.faccao_id, p_qtd);
  perform mali._audit('receber_conserto', 'consertos', c.id::text, jsonb_build_object('qtd', p_qtd, 'perda', p_perda, 'proximo', p_proximo));
end $$;

create or replace function mali.desfazer_recebimento_conserto(p_conserto_id uuid) returns void
language plpgsql security definer set search_path to '' as $$
declare c record; v_dest text;
begin
  perform mali.exigir_perfil('supervisor');
  select * into c from mali.consertos where id = p_conserto_id for update;
  if c.recebido_em is null then raise exception 'Conserto ainda não recebido.'; end if;
  if c.fechamento_id is not null then raise exception 'Conserto já pago. Estorne o fechamento antes.'; end if;
  select tipo into v_dest from mali.etapas where origem_id = c.id limit 1;
  if v_dest is null and exists (select 1 from mali.estoque_mov where origem_id = c.id) then v_dest := 'ESTOQUE'; end if;
  if v_dest is not null then perform mali._desfazer_encaminhamento(v_dest, c.sublote_id, c.id, c.qtd_recebida); end if;
  update mali.consertos set recebido_em = null, qtd_recebida = null, qtd_perda = null where id = c.id;
  perform mali._audit('desfazer_conserto', 'consertos', c.id::text, null);
end $$;

-- ================= Etapas (estamparia, finalização, inspeção) =================
create or replace function mali._perfil_etapa(p_tipo text) returns text
language sql immutable set search_path to '' as $$
  select case p_tipo when 'ESTAMPARIA' then 'estamparia' else 'qualidade' end;
$$;

create or replace function mali.iniciar_etapa(p_etapa_id uuid, p_responsavel text default null) returns void
language plpgsql security definer set search_path to '' as $$
declare t record;
begin
  select * into t from mali.etapas where id = p_etapa_id for update;
  if not found then raise exception 'Etapa não encontrada.'; end if;
  perform mali.exigir_perfil(mali._perfil_etapa(t.tipo));
  if t.inicio is not null then raise exception 'Etapa já iniciada.'; end if;
  update mali.etapas set inicio = now(), inicio_por = auth.uid(), responsavel = coalesce(nullif(trim(p_responsavel),''), responsavel) where id = t.id;
  perform mali._audit('iniciar_etapa', 'etapas', t.id::text, jsonb_build_object('tipo', t.tipo));
end $$;

create or replace function mali.concluir_etapa(p_etapa_id uuid, p_aprovada int, p_conserto int, p_perda int, p_destino text,
  p_faccao_conserto bigint default null, p_obs text default null) returns void
language plpgsql security definer set search_path to '' as $$
declare t record; v_fac bigint;
begin
  select * into t from mali.etapas where id = p_etapa_id for update;
  if not found then raise exception 'Etapa não encontrada.'; end if;
  perform mali.exigir_perfil(mali._perfil_etapa(t.tipo));
  if t.fim is not null then raise exception 'Etapa já concluída.'; end if;
  p_aprovada := coalesce(p_aprovada,0); p_conserto := coalesce(p_conserto,0); p_perda := coalesce(p_perda,0);
  if p_aprovada < 0 or p_conserto < 0 or p_perda < 0 or p_aprovada + p_conserto + p_perda <> t.qtd then
    raise exception 'Aprovadas + conserto + perda deve somar % peças.', t.qtd; end if;
  if p_aprovada > 0 then
    if p_destino is null or p_destino = t.tipo then raise exception 'Escolha o destino das peças aprovadas.'; end if;
    if p_destino = 'FACÇÃO' and t.origem <> 'CORTE' then raise exception 'Somente a estamparia antes da costura pode liberar para facção.'; end if;
    if p_destino not in ('FACÇÃO','ESTAMPARIA','FINALIZAÇÃO','INSPEÇÃO','ESTOQUE') then raise exception 'Destino inválido.'; end if;
  end if;
  if p_conserto > 0 then
    v_fac := coalesce(p_faccao_conserto, t.faccao_id);
    if v_fac is null then raise exception 'Informe a facção que fará o conserto.'; end if;
  end if;
  update mali.etapas set fim = now(), fim_por = auth.uid(), inicio = coalesce(inicio, now()), inicio_por = coalesce(inicio_por, auth.uid()),
    qtd_aprovada = p_aprovada, qtd_conserto = p_conserto, qtd_perda = p_perda,
    destino = case when p_aprovada > 0 then p_destino end, obs = concat_ws(' | ', obs, nullif(trim(p_obs),''))
  where id = t.id;
  perform mali._encaminhar(p_destino, t.sublote_id, 'ETAPA', t.id, t.faccao_id, p_aprovada);
  if p_conserto > 0 then
    insert into mali.consertos(origem, origem_id, sublote_id, faccao_id, qtd, valor_unit, obs)
    values ('ETAPA', t.id, t.sublote_id, v_fac, p_conserto, 0, p_obs);
  end if;
  perform mali._audit('concluir_etapa', 'etapas', t.id::text,
    jsonb_build_object('tipo', t.tipo, 'aprovada', p_aprovada, 'conserto', p_conserto, 'perda', p_perda, 'destino', p_destino));
end $$;

create or replace function mali.estornar_etapa(p_etapa_id uuid, p_motivo text) returns void
language plpgsql security definer set search_path to '' as $$
declare t record;
begin
  perform mali.exigir_perfil('supervisor');
  select * into t from mali.etapas where id = p_etapa_id for update;
  if not found then raise exception 'Etapa não encontrada.'; end if;
  if t.fim is null then
    update mali.etapas set inicio = null, inicio_por = null where id = t.id;
  else
    if exists (select 1 from mali.consertos where origem = 'ETAPA' and origem_id = t.id and recebido_em is not null) then
      raise exception 'O conserto gerado por esta etapa já foi recebido.'; end if;
    perform mali._desfazer_encaminhamento(t.destino, t.sublote_id, t.id, t.qtd_aprovada);
    delete from mali.consertos where origem = 'ETAPA' and origem_id = t.id;
    update mali.etapas set fim = null, fim_por = null, qtd_aprovada = null, qtd_conserto = null, qtd_perda = null, destino = null where id = t.id;
  end if;
  perform mali._audit('estornar_etapa', 'etapas', t.id::text, jsonb_build_object('motivo', p_motivo));
end $$;

-- ================= Estoque =================
create or replace function mali.ajustar_estoque(p_produto_id bigint, p_cor_id bigint, p_tamanho_id bigint, p_qtd int, p_obs text) returns void
language plpgsql security definer set search_path to '' as $$
begin
  perform mali.exigir_perfil('estoque');
  if coalesce(p_qtd,0) = 0 then raise exception 'Informe a quantidade do ajuste.'; end if;
  if coalesce(trim(p_obs),'') = '' then raise exception 'Informe o motivo do ajuste.'; end if;
  perform pg_advisory_xact_lock(hashtext('mali.estoque.' || p_produto_id || '.' || p_cor_id || '.' || p_tamanho_id));
  if mali._saldo_estoque(p_produto_id, p_cor_id, p_tamanho_id) + p_qtd < 0 then raise exception 'O estoque ficaria negativo.'; end if;
  insert into mali.estoque_mov(tipo, origem, produto_id, cor_id, tamanho_id, qtd, obs)
  values ('AJUSTE', 'AJUSTE', p_produto_id, p_cor_id, p_tamanho_id, p_qtd, p_obs);
  perform mali._audit('ajustar_estoque', 'estoque_mov', null, jsonb_build_object('produto', p_produto_id, 'cor', p_cor_id, 'tamanho', p_tamanho_id, 'qtd', p_qtd, 'obs', p_obs));
end $$;

-- ================= OP de estamparia (a partir do estoque) =================
create or replace function mali.criar_op_estamparia(p_produto_id bigint, p_cor_id bigint, p_tamanho_id bigint, p_qtd int,
  p_estampa text, p_previsao date default null, p_pedido_id uuid default null, p_obs text default null) returns uuid
language plpgsql security definer set search_path to '' as $$
declare v_id uuid;
begin
  if not (mali.tem_perfil('estamparia') or mali.tem_perfil('estoque')) then raise exception 'Acesso negado.' using errcode = '42501'; end if;
  if coalesce(p_qtd,0) <= 0 then raise exception 'Quantidade inválida.'; end if;
  perform pg_advisory_xact_lock(hashtext('mali.estoque.' || p_produto_id || '.' || p_cor_id || '.' || p_tamanho_id));
  if mali._saldo_estoque(p_produto_id, p_cor_id, p_tamanho_id) < p_qtd then raise exception 'Saldo insuficiente em estoque.'; end if;
  insert into mali.ops_estamparia(previsao, produto_id, cor_id, tamanho_id, qtd, estampa, pedido_id, obs)
  values (p_previsao, p_produto_id, p_cor_id, p_tamanho_id, p_qtd, p_estampa, p_pedido_id, p_obs) returning id into v_id;
  insert into mali.estoque_mov(tipo, origem, origem_id, produto_id, cor_id, tamanho_id, qtd, pedido_id, obs)
  values ('SAÍDA', 'ESTAMPARIA', v_id, p_produto_id, p_cor_id, p_tamanho_id, p_qtd, p_pedido_id, 'OP estamparia ' || coalesce(p_estampa,''));
  perform mali._audit('criar_op_estamparia', 'ops_estamparia', v_id::text, jsonb_build_object('qtd', p_qtd));
  return v_id;
end $$;

create or replace function mali.concluir_op_estamparia(p_op_id uuid, p_qtd int, p_perda int) returns void
language plpgsql security definer set search_path to '' as $$
declare o record;
begin
  perform mali.exigir_perfil('estamparia');
  select * into o from mali.ops_estamparia where id = p_op_id for update;
  if not found then raise exception 'OP não encontrada.'; end if;
  if o.retorno_em is not null then raise exception 'OP já concluída.'; end if;
  p_qtd := coalesce(p_qtd,0); p_perda := coalesce(p_perda,0);
  if p_qtd < 0 or p_perda < 0 or p_qtd + p_perda <> o.qtd then raise exception 'Retorno + perda deve ser igual a % peças.', o.qtd; end if;
  update mali.ops_estamparia set retorno_em = now(), qtd_retorno = p_qtd, qtd_perda = p_perda where id = o.id;
  if p_qtd > 0 then
    insert into mali.estoque_mov(tipo, origem, origem_id, produto_id, cor_id, tamanho_id, qtd, pedido_id, obs)
    values ('ENTRADA', 'ESTAMPARIA', o.id, o.produto_id, o.cor_id, o.tamanho_id, p_qtd, o.pedido_id, 'Retorno OP estamparia ' || o.numero);
  end if;
  perform mali._audit('concluir_op_estamparia', 'ops_estamparia', o.id::text, jsonb_build_object('qtd', p_qtd, 'perda', p_perda));
end $$;

create or replace function mali.cancelar_op_estamparia(p_op_id uuid, p_motivo text) returns void
language plpgsql security definer set search_path to '' as $$
declare o record;
begin
  perform mali.exigir_perfil('supervisor');
  select * into o from mali.ops_estamparia where id = p_op_id for update;
  if not found then raise exception 'OP não encontrada.'; end if;
  if o.retorno_em is not null then
    perform mali._desfazer_entrada(o.id);
    update mali.ops_estamparia set retorno_em = null, qtd_retorno = null, qtd_perda = null where id = o.id;
  else
    delete from mali.estoque_mov where origem_id = o.id and tipo = 'SAÍDA';
    delete from mali.ops_estamparia where id = o.id;
  end if;
  perform mali._audit('cancelar_op_estamparia', 'ops_estamparia', o.id::text, jsonb_build_object('motivo', p_motivo));
end $$;

-- ================= Expedição =================
create or replace function mali.criar_expedicao(p_qtd int, p_pedido_item_id uuid default null, p_produto_id bigint default null,
  p_cor_id bigint default null, p_tamanho_id bigint default null, p_cliente_id bigint default null, p_obs text default null) returns uuid
language plpgsql security definer set search_path to '' as $$
declare i record; v_id uuid; v_pend int;
begin
  perform mali.exigir_perfil('estoque');
  if coalesce(p_qtd,0) <= 0 then raise exception 'Quantidade inválida.'; end if;
  if p_pedido_item_id is not null then
    select pi.*, p.cliente_id, p.status into i from mali.pedido_itens pi join mali.pedidos p on p.id = pi.pedido_id where pi.id = p_pedido_item_id for update of pi;
    if not found then raise exception 'Item de pedido não encontrado.'; end if;
    if i.status <> 'Aberto' then raise exception 'Pedido não está aberto.'; end if;
    v_pend := i.qtd - i.qtd_entregue - coalesce((select sum(qtd) from mali.expedicoes where pedido_item_id = i.id and liberado_em is null and cancelado_em is null),0);
    if p_qtd > v_pend then raise exception 'Quantidade maior que o pendente do pedido (%).', v_pend; end if;
    insert into mali.expedicoes(pedido_item_id, pedido_id, cliente_id, produto_id, cor_id, tamanho_id, qtd, obs)
    values (i.id, i.pedido_id, i.cliente_id, i.produto_id, i.cor_id, i.tamanho_id, p_qtd, p_obs) returning id into v_id;
  else
    if p_produto_id is null or p_cor_id is null or p_tamanho_id is null then raise exception 'Informe produto, cor e tamanho.'; end if;
    insert into mali.expedicoes(cliente_id, produto_id, cor_id, tamanho_id, qtd, obs)
    values (p_cliente_id, p_produto_id, p_cor_id, p_tamanho_id, p_qtd, p_obs) returning id into v_id;
  end if;
  perform mali._audit('criar_expedicao', 'expedicoes', v_id::text, jsonb_build_object('qtd', p_qtd));
  return v_id;
end $$;

create or replace function mali.embalagem(p_expedicao_id uuid, p_acao text) returns void
language plpgsql security definer set search_path to '' as $$
begin
  perform mali.exigir_perfil('estoque');
  if p_acao = 'iniciar' then
    update mali.expedicoes set embalagem_inicio = now() where id = p_expedicao_id and embalagem_inicio is null and cancelado_em is null and liberado_em is null;
  elsif p_acao = 'finalizar' then
    update mali.expedicoes set embalagem_fim = now(), embalagem_inicio = coalesce(embalagem_inicio, now())
    where id = p_expedicao_id and embalagem_fim is null and cancelado_em is null and liberado_em is null;
  else raise exception 'Ação inválida.'; end if;
  if not found then raise exception 'Expedição não está disponível para esta ação.'; end if;
end $$;

create or replace function mali.liberar_expedicao(p_expedicao_id uuid) returns void
language plpgsql security definer set search_path to '' as $$
declare x record;
begin
  perform mali.exigir_perfil('estoque');
  select * into x from mali.expedicoes where id = p_expedicao_id for update;
  if not found or x.cancelado_em is not null then raise exception 'Expedição não encontrada.'; end if;
  if x.liberado_em is not null then raise exception 'Expedição já liberada.'; end if;
  perform pg_advisory_xact_lock(hashtext('mali.estoque.' || x.produto_id || '.' || x.cor_id || '.' || x.tamanho_id));
  if mali._saldo_estoque(x.produto_id, x.cor_id, x.tamanho_id) < x.qtd then raise exception 'Saldo insuficiente em estoque.'; end if;
  update mali.expedicoes set liberado_em = now(), embalagem_inicio = coalesce(embalagem_inicio, now()), embalagem_fim = coalesce(embalagem_fim, now()) where id = x.id;
  insert into mali.estoque_mov(tipo, origem, origem_id, produto_id, cor_id, tamanho_id, qtd, pedido_id, cliente_id, obs)
  values ('SAÍDA', 'EXPEDIÇÃO', x.id, x.produto_id, x.cor_id, x.tamanho_id, x.qtd, x.pedido_id, x.cliente_id, 'Expedição ' || x.numero);
  if x.pedido_item_id is not null then
    update mali.pedido_itens set qtd_entregue = qtd_entregue + x.qtd where id = x.pedido_item_id;
    if not exists (select 1 from mali.pedido_itens where pedido_id = x.pedido_id and qtd_entregue < qtd) then
      update mali.pedidos set status = 'Entregue' where id = x.pedido_id;
    end if;
  end if;
  perform mali._audit('liberar_expedicao', 'expedicoes', x.id::text, jsonb_build_object('qtd', x.qtd));
end $$;

create or replace function mali.cancelar_expedicao(p_expedicao_id uuid, p_motivo text) returns void
language plpgsql security definer set search_path to '' as $$
declare x record;
begin
  perform mali.exigir_perfil('estoque');
  select * into x from mali.expedicoes where id = p_expedicao_id for update;
  if not found or x.cancelado_em is not null then raise exception 'Expedição não encontrada.'; end if;
  if x.liberado_em is not null then
    perform mali.exigir_perfil('supervisor');
    delete from mali.estoque_mov where origem_id = x.id and tipo = 'SAÍDA';
    if x.pedido_item_id is not null then
      update mali.pedido_itens set qtd_entregue = qtd_entregue - x.qtd where id = x.pedido_item_id;
      update mali.pedidos set status = 'Aberto' where id = x.pedido_id and status = 'Entregue';
    end if;
  end if;
  update mali.expedicoes set cancelado_em = now(), obs = concat_ws(' | ', obs, 'Cancelada: ' || p_motivo) where id = x.id;
  perform mali._audit('cancelar_expedicao', 'expedicoes', x.id::text, jsonb_build_object('motivo', p_motivo, 'estava_liberada', x.liberado_em is not null));
end $$;

-- ================= Produção interna =================
create or replace function mali.iniciar_apontamento(p_operador_id bigint, p_envio_id uuid, p_processo_id bigint) returns uuid
language plpgsql security definer set search_path to '' as $$
declare e record; v_id uuid; v_tempo numeric;
begin
  perform mali.exigir_perfil('producao');
  select en.*, f.interna into e from mali.envios en join mali.faccoes f on f.id = en.faccao_id where en.id = p_envio_id;
  if not found then raise exception 'Lote não encontrado.'; end if;
  if not e.interna then raise exception 'Este lote não está na produção interna.'; end if;
  if e.data_retorno is not null then raise exception 'Este lote já foi finalizado.'; end if;
  if not exists (select 1 from mali.operadores where id = p_operador_id and ativo) then raise exception 'Operador inválido.'; end if;
  if exists (select 1 from mali.apontamentos where operador_id = p_operador_id and fim is null) then
    raise exception 'Este operador já tem uma operação em andamento. Finalize antes de começar outra.'; end if;
  select tempo_seg into v_tempo from mali.produto_processos where produto_id = e.produto_id and processo_id = p_processo_id;
  if v_tempo is null then raise exception 'Este processo não faz parte do roteiro do produto.'; end if;
  insert into mali.apontamentos(operador_id, envio_id, processo_id, tempo_seg) values (p_operador_id, e.id, p_processo_id, v_tempo) returning id into v_id;
  return v_id;
end $$;

create or replace function mali.finalizar_apontamento(p_apontamento_id uuid, p_qtd int) returns void
language plpgsql security definer set search_path to '' as $$
declare a record; v_feito int; v_lote int;
begin
  perform mali.exigir_perfil('producao');
  select * into a from mali.apontamentos where id = p_apontamento_id for update;
  if not found then raise exception 'Apontamento não encontrado.'; end if;
  if a.fim is not null then raise exception 'Apontamento já finalizado.'; end if;
  if coalesce(p_qtd,0) <= 0 then raise exception 'Informe a quantidade produzida.'; end if;
  select qtd into v_lote from mali.envios where id = a.envio_id;
  select coalesce(sum(qtd),0) into v_feito from mali.apontamentos where envio_id = a.envio_id and processo_id = a.processo_id and fim is not null;
  if v_feito + p_qtd > v_lote then raise exception 'Quantidade maior que o restante desta operação no lote (restam %).', v_lote - v_feito; end if;
  update mali.apontamentos set fim = now(), qtd = p_qtd where id = a.id;
  -- encerra pausa aberta do operador, se houver
  update mali.pausas set fim = now() where operador_id = a.operador_id and fim is null;
end $$;

create or replace function mali.cancelar_apontamento(p_apontamento_id uuid) returns void
language plpgsql security definer set search_path to '' as $$
begin
  perform mali.exigir_perfil('producao');
  delete from mali.apontamentos where id = p_apontamento_id and fim is null;
  if not found then
    perform mali.exigir_perfil('supervisor');
    delete from mali.apontamentos where id = p_apontamento_id;
  end if;
  perform mali._audit('cancelar_apontamento', 'apontamentos', p_apontamento_id::text, null);
end $$;

create or replace function mali.iniciar_pausa(p_operador_id bigint, p_motivo_id bigint, p_obs text default null) returns uuid
language plpgsql security definer set search_path to '' as $$
declare v_id uuid;
begin
  perform mali.exigir_perfil('producao');
  if exists (select 1 from mali.pausas where operador_id = p_operador_id and fim is null) then raise exception 'Operador já está em pausa.'; end if;
  insert into mali.pausas(operador_id, motivo_id, obs) values (p_operador_id, p_motivo_id, p_obs) returning id into v_id;
  return v_id;
end $$;

create or replace function mali.encerrar_pausa(p_pausa_id uuid) returns void
language plpgsql security definer set search_path to '' as $$
begin
  perform mali.exigir_perfil('producao');
  update mali.pausas set fim = now() where id = p_pausa_id and fim is null;
  if not found then raise exception 'Pausa não encontrada ou já encerrada.'; end if;
end $$;

-- ================= Fechamento de facção =================
create or replace function mali.registrar_fechamento(p_faccao_id bigint, p_retornos uuid[], p_consertos uuid[],
  p_desconto numeric default 0, p_data date default null, p_obs text default null) returns uuid
language plpgsql security definer set search_path to '' as $$
declare v_id uuid; r record; v_bruto numeric := 0; v_n int := 0;
begin
  perform mali.exigir_perfil('financeiro');
  if coalesce(array_length(p_retornos,1),0) + coalesce(array_length(p_consertos,1),0) = 0 then raise exception 'Selecione ao menos um item.'; end if;
  insert into mali.fechamentos(faccao_id, data, desconto, obs, pix)
  values (p_faccao_id, coalesce(p_data, mali.hoje()), coalesce(p_desconto,0), p_obs, (select pix from mali.faccoes where id = p_faccao_id))
  returning id into v_id;
  for r in select rt.* from mali.retornos rt join mali.envios e on e.id = rt.envio_id
           where rt.id = any(coalesce(p_retornos,'{}')) and e.faccao_id = p_faccao_id for update of rt loop
    if r.fechamento_id is not null then raise exception 'Um dos retornos já foi pago.'; end if;
    if r.qtd > 0 then
      insert into mali.fechamento_itens(fechamento_id, tipo, ref_id, qtd, valor_unit, valor) values (v_id, 'RETORNO', r.id, r.qtd, r.valor_unit, round(r.qtd * r.valor_unit, 2));
      v_bruto := v_bruto + round(r.qtd * r.valor_unit, 2);
    end if;
    update mali.retornos set fechamento_id = v_id where id = r.id; v_n := v_n + 1;
  end loop;
  for r in select * from mali.consertos where id = any(coalesce(p_consertos,'{}')) and faccao_id = p_faccao_id for update loop
    if r.fechamento_id is not null then raise exception 'Um dos consertos já foi pago.'; end if;
    if r.recebido_em is null then raise exception 'Só é possível pagar consertos já recebidos.'; end if;
    if r.qtd_recebida > 0 and r.valor_unit > 0 then
      insert into mali.fechamento_itens(fechamento_id, tipo, ref_id, qtd, valor_unit, valor) values (v_id, 'CONSERTO', r.id, r.qtd_recebida, r.valor_unit, round(r.qtd_recebida * r.valor_unit, 2));
      v_bruto := v_bruto + round(r.qtd_recebida * r.valor_unit, 2);
    end if;
    update mali.consertos set fechamento_id = v_id where id = r.id; v_n := v_n + 1;
  end loop;
  if v_n <> coalesce(array_length(p_retornos,1),0) + coalesce(array_length(p_consertos,1),0) then raise exception 'Itens inválidos para esta facção.'; end if;
  if coalesce(p_desconto,0) < 0 or p_desconto > v_bruto then raise exception 'Desconto inválido.'; end if;
  update mali.fechamentos set total_bruto = v_bruto, total = v_bruto - coalesce(p_desconto,0) where id = v_id;
  perform mali._audit('registrar_fechamento', 'fechamentos', v_id::text, jsonb_build_object('faccao', p_faccao_id, 'total', v_bruto - coalesce(p_desconto,0)));
  return v_id;
end $$;

create or replace function mali.estornar_fechamento(p_fechamento_id uuid, p_motivo text) returns void
language plpgsql security definer set search_path to '' as $$
begin
  perform mali.exigir_perfil('financeiro');
  update mali.retornos set fechamento_id = null where fechamento_id = p_fechamento_id;
  update mali.consertos set fechamento_id = null where fechamento_id = p_fechamento_id;
  delete from mali.fechamentos where id = p_fechamento_id;
  if not found then raise exception 'Fechamento não encontrado.'; end if;
  perform mali._audit('estornar_fechamento', 'fechamentos', p_fechamento_id::text, jsonb_build_object('motivo', p_motivo));
end $$;

-- ================= Roteiro do produto =================
create or replace function mali.salvar_roteiro(p_produto_id bigint, p_itens jsonb) returns void
language plpgsql security definer set search_path to '' as $$
declare it jsonb; v_proc bigint; v_seq int := 0;
begin
  perform mali.exigir_perfil('cadastros');
  delete from mali.produto_processos where produto_id = p_produto_id;
  for it in select * from jsonb_array_elements(coalesce(p_itens,'[]')) loop
    v_seq := v_seq + 1;
    v_proc := nullif(it->>'processo_id','')::bigint;
    if v_proc is null then
      if coalesce(trim(it->>'processo'),'') = '' then raise exception 'Processo sem nome na linha %.', v_seq; end if;
      insert into mali.processos(nome) values (upper(trim(it->>'processo'))) on conflict (nome) do update set ativo = true returning id into v_proc;
    end if;
    insert into mali.produto_processos(produto_id, processo_id, sequencia, tempo_seg)
    values (p_produto_id, v_proc, v_seq, coalesce(nullif(it->>'tempo_seg','')::numeric, 0))
    on conflict (produto_id, processo_id) do update set sequencia = excluded.sequencia, tempo_seg = excluded.tempo_seg;
  end loop;
  perform mali._audit('salvar_roteiro', 'produto_processos', p_produto_id::text, jsonb_build_object('itens', v_seq));
end $$;
