\set ON_ERROR_STOP 1
insert into auth.users(id,email) values ('00000000-0000-0000-0000-000000000001','adm@x.com');
set role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000001',false);
select mali.bootstrap_admin('Admin');
select mali.status_sistema();
insert into mali.clientes(nome) values ('MALI');
insert into mali.cores(nome) values ('PRETO'),('ROSA');
insert into mali.tamanhos(nome,ordem) values ('P',1),('M',2);
insert into mali.produtos(nome, valor_faccao) values ('TOP CAROL', 1.6);
insert into mali.faccoes(nome) values ('Fac A');
insert into mali.faccoes(nome, interna) values ('PRODUÇÃO INTERNA', true);
insert into mali.operadores(nome) values ('Daniela');
insert into mali.motivos_parada(nome) values ('Café');
select mali.salvar_roteiro(1, '[{"processo":"FECHAR LATERAL","tempo_seg":30},{"processo":"EMBALAR","tempo_seg":10}]');
-- pedido
select mali.salvar_pedido(null, 1, null, mali.hoje()+10, 'teste', '[{"produto_id":1,"cor_id":1,"tamanho_id":1,"qtd":20},{"produto_id":1,"cor_id":2,"tamanho_id":2,"qtd":10}]') as ped \gset
select numero, status, qtd_total from mali.v_pedidos;
-- corte
select mali.criar_corte(1,'PRODUÇÃO','[{"cor_id":1,"folhas":10},{"cor_id":2,"folhas":5}]','[{"tamanho_id":1,"riscos":2},{"tamanho_id":2,"riscos":2}]', :'ped') as corte \gset
select lote,total_pecas,status from mali.v_cortes;
select (mali.confirmar_corte(:'corte'))->>'mensagem';
select codigo, cor, tamanho, qtd_cortada, status from mali.v_sublotes order by codigo;
-- envio para facção externa e interna
select id as s1 from mali.sublotes where codigo like '%.1' \gset
select id as s2 from mali.sublotes where codigo like '%.21' \gset
select mali.enviar_faccao(1, jsonb_build_array(jsonb_build_object('sublote_id',:'s1','qtd',20)), 'tok_abcdefghijkl', null, '{"fio":2}');
select mali.enviar_faccao(2, jsonb_build_array(jsonb_build_object('sublote_id',:'s2','qtd',10)), 'tok_abcdefghijk2');
select faccao, lote, qtd, valor_unit, saldo, atraso from mali.v_envios order by faccao;
-- retorno parcial com defeito -> inspeção
select id as e1 from mali.envios where sublote_id = :'s1' \gset
select mali.registrar_retorno(:'e1', 15, 2, 'INSPEÇÃO') as r1 \gset
select saldo from mali.v_envios where id = :'e1';
select id as et from mali.etapas where origem_id = :'r1' \gset
select mali.iniciar_etapa(:'et','Ana');
select mali.concluir_etapa(:'et', 14, 1, 0, 'ESTOQUE');
select produto,cor,tamanho,saldo from mali.v_estoque;
-- conserto recebido
select id as c1 from mali.consertos where origem='RETORNO' \gset
select mali.receber_conserto(:'c1', 2, 0, 'ESTOQUE');
select codigo, status, na_faccao, em_etapa, em_conserto, no_estoque from mali.v_sublotes where id = :'s1';
-- restante do envio
select mali.registrar_retorno(:'e1', 3, 0, 'ESTOQUE');
select data_retorno is not null as finalizado from mali.envios where id = :'e1';
-- produção interna
select id as e2 from mali.envios where sublote_id = :'s2' \gset
select id as p1 from mali.processos where nome='FECHAR LATERAL' \gset
select mali.iniciar_apontamento(1, :'e2', :'p1') as ap \gset
select mali.finalizar_apontamento(:'ap', 10);
select lote, roteiro from mali.v_lotes_internos;
select operador, pecas, min_padrao from mali.v_eficiencia_dia;
-- expedição do pedido
select id as it1 from mali.pedido_itens where cor_id=1 \gset
select mali.criar_expedicao(18, :'it1') as x1 \gset
select mali.embalagem(:'x1','iniciar');
select mali.liberar_expedicao(:'x1');
select pendente, qtd_entregue, saldo_estoque from mali.v_pedido_itens where id = :'it1';
-- OP estamparia
select mali.criar_op_estamparia(1,1,1,1,'FLOR') as op \gset
select mali.concluir_op_estamparia(:'op',1,0);
select saldo from mali.v_estoque;
-- fechamento
select array_agg(id) as rets from mali.retornos \gset
select array_agg(id) as cons from mali.consertos where recebido_em is not null \gset
select mali.registrar_fechamento(1, :'rets'::uuid[], :'cons'::uuid[], 1) as fe \gset
select faccao, total_bruto, desconto, total, itens from mali.v_fechamentos;
select mali.painel();
-- estornos
select mali.estornar_fechamento(:'fe','teste');
select mali.cancelar_expedicao(:'x1','teste');
select saldo from mali.v_estoque;
-- segurança: helper interno não pode ser chamado
\set ON_ERROR_STOP 0
select mali._encaminhar('ESTOQUE', :'s1', 'X', gen_random_uuid(), null, 100);
