-- MALI — Parte 2: tabelas da operação

-- ---------- Pedidos ----------
create table mali.pedidos (
  id uuid primary key default gen_random_uuid(),
  numero int not null unique,
  data date not null default mali.hoje(),
  cliente_id bigint not null references mali.clientes(id),
  entrega date,
  status text not null default 'Aberto' check (status in ('Aberto','Entregue','Cancelado')),
  obs text,
  criado_em timestamptz not null default now(),
  criado_por uuid default auth.uid()
);

create table mali.pedido_itens (
  id uuid primary key default gen_random_uuid(),
  pedido_id uuid not null references mali.pedidos(id) on delete cascade,
  produto_id bigint not null references mali.produtos(id),
  cor_id bigint not null references mali.cores(id),
  tamanho_id bigint not null references mali.tamanhos(id),
  qtd int not null check (qtd > 0),
  qtd_entregue int not null default 0 check (qtd_entregue >= 0),
  estampa text, tag text, obs text
);
create index on mali.pedido_itens(pedido_id);

-- ---------- Corte ----------
create table mali.cortes (
  id uuid primary key default gen_random_uuid(),
  numero int not null,
  mes date not null,
  lote text not null unique,
  data timestamptz not null default now(),
  produto_id bigint not null references mali.produtos(id),
  pedido_id uuid references mali.pedidos(id),
  destino text not null default 'PRODUÇÃO' check (destino in ('PRODUÇÃO','ESTAMPARIA')), -- ESTAMPARIA = estampa antes de costurar
  status text not null default 'Programado' check (status in ('Programado','Cortado','Cancelado')),
  obs text,
  etiquetas jsonb,
  cortado_em timestamptz, cortado_por uuid,
  criado_em timestamptz not null default now(),
  criado_por uuid default auth.uid(),
  unique (mes, numero)
);

create table mali.corte_cores (
  corte_id uuid not null references mali.cortes(id) on delete cascade,
  posicao int not null,
  cor_id bigint not null references mali.cores(id),
  folhas int not null check (folhas > 0),
  primary key (corte_id, posicao)
);

create table mali.corte_tamanhos (
  corte_id uuid not null references mali.cortes(id) on delete cascade,
  posicao int not null,
  tamanho_id bigint not null references mali.tamanhos(id),
  riscos int not null check (riscos > 0),
  primary key (corte_id, posicao)
);

-- Sublote = uma cor × um tamanho de um corte
create table mali.sublotes (
  id uuid primary key default gen_random_uuid(),
  codigo text not null unique,
  lote text not null,
  corte_id uuid not null references mali.cortes(id) on delete cascade,
  produto_id bigint not null references mali.produtos(id),
  cor_id bigint not null references mali.cores(id),
  tamanho_id bigint not null references mali.tamanhos(id),
  pedido_id uuid references mali.pedidos(id),
  qtd_cortada int not null check (qtd_cortada > 0),
  qtd_saldo int not null check (qtd_saldo >= 0),  -- disponível para enviar à facção
  criado_em timestamptz not null default now()
);
create index on mali.sublotes(corte_id);

-- ---------- Facção ----------
create table mali.remessas (
  id uuid primary key default gen_random_uuid(),
  token text not null unique,
  numero int generated always as identity,
  faccao_id bigint not null references mali.faccoes(id),
  data timestamptz not null default now(),
  previsao date,
  -- aviamentos enviados junto
  vies numeric(10,2), fio numeric(10,2), linha numeric(10,2), elastico numeric(10,2), alca numeric(10,2), etiqueta numeric(10,2),
  obs text,
  criado_por uuid default auth.uid()
);

create table mali.envios (
  id uuid primary key default gen_random_uuid(),
  remessa_id uuid not null references mali.remessas(id) on delete cascade,
  sublote_id uuid not null references mali.sublotes(id),
  faccao_id bigint not null references mali.faccoes(id),
  produto_id bigint not null references mali.produtos(id),
  cor_id bigint not null references mali.cores(id),
  tamanho_id bigint not null references mali.tamanhos(id),
  lote text not null,
  qtd int not null check (qtd > 0),
  valor_unit numeric(12,2) not null default 0 check (valor_unit >= 0),
  previsao date,
  data_retorno date,          -- preenchido quando tudo voltou (ou finalizado manualmente)
  ocorrencia text,
  criado_em timestamptz not null default now()
);
create index on mali.envios(sublote_id);
create index on mali.envios(faccao_id) where data_retorno is null;

-- Destinos depois do retorno / de uma etapa
-- FACÇÃO (só para estamparia antes da costura), ESTAMPARIA, FINALIZAÇÃO, INSPEÇÃO, ESTOQUE
create table mali.retornos (
  id uuid primary key default gen_random_uuid(),
  envio_id uuid not null references mali.envios(id),
  data_retorno date not null default mali.hoje(),
  qtd int not null check (qtd >= 0),             -- peças boas
  qtd_defeito int not null default 0 check (qtd_defeito >= 0), -- voltam para conserto
  proximo text not null check (proximo in ('ESTAMPARIA','FINALIZAÇÃO','INSPEÇÃO','ESTOQUE')),
  valor_unit numeric(12,2) not null default 0,
  obs text,
  fechamento_id uuid,
  criado_em timestamptz not null default now(),
  criado_por uuid default auth.uid(),
  check (qtd + qtd_defeito > 0)
);
create index on mali.retornos(envio_id);

-- Etapas internas: estamparia, finalização e inspeção
create table mali.etapas (
  id uuid primary key default gen_random_uuid(),
  tipo text not null check (tipo in ('ESTAMPARIA','FINALIZAÇÃO','INSPEÇÃO')),
  sublote_id uuid not null references mali.sublotes(id),
  origem text not null check (origem in ('CORTE','RETORNO','CONSERTO','ETAPA')),
  origem_id uuid,
  faccao_id bigint references mali.faccoes(id),  -- facção de onde as peças vieram (para mandar conserto)
  qtd int not null check (qtd > 0),
  criado_em timestamptz not null default now(),
  inicio timestamptz, inicio_por uuid,
  fim timestamptz, fim_por uuid,
  qtd_aprovada int, qtd_conserto int, qtd_perda int,
  destino text check (destino in ('FACÇÃO','ESTAMPARIA','FINALIZAÇÃO','INSPEÇÃO','ESTOQUE')),
  responsavel text,
  obs text
);
create index on mali.etapas(tipo) where fim is null;
create index on mali.etapas(sublote_id);
create index on mali.etapas(origem_id);

create table mali.consertos (
  id uuid primary key default gen_random_uuid(),
  origem text not null check (origem in ('RETORNO','ETAPA')),
  origem_id uuid not null,
  sublote_id uuid not null references mali.sublotes(id),
  faccao_id bigint not null references mali.faccoes(id),
  qtd int not null check (qtd > 0),
  valor_unit numeric(12,2) not null default 0,   -- conserto de retorno é pago quando volta consertado
  enviado_em date not null default mali.hoje(),
  recebido_em date,
  qtd_recebida int,
  qtd_perda int,
  obs text,
  fechamento_id uuid,
  criado_em timestamptz not null default now()
);

-- ---------- Fechamento (pagamento de facções) ----------
create table mali.fechamentos (
  id uuid primary key default gen_random_uuid(),
  numero int generated always as identity,
  faccao_id bigint not null references mali.faccoes(id),
  data date not null default mali.hoje(),
  total_bruto numeric(12,2) not null default 0,
  desconto numeric(12,2) not null default 0,
  total numeric(12,2) not null default 0,
  pix text,
  obs text,
  criado_em timestamptz not null default now(),
  criado_por uuid default auth.uid()
);

create table mali.fechamento_itens (
  id bigint generated always as identity primary key,
  fechamento_id uuid not null references mali.fechamentos(id) on delete cascade,
  tipo text not null check (tipo in ('RETORNO','CONSERTO')),
  ref_id uuid not null,
  qtd int not null,
  valor_unit numeric(12,2) not null,
  valor numeric(12,2) not null,
  unique (tipo, ref_id)
);
alter table mali.retornos add constraint retornos_fechamento_fk foreign key (fechamento_id) references mali.fechamentos(id) on delete set null;
alter table mali.consertos add constraint consertos_fechamento_fk foreign key (fechamento_id) references mali.fechamentos(id) on delete set null;

-- ---------- Estoque ----------
create table mali.estoque_mov (
  id uuid primary key default gen_random_uuid(),
  em timestamptz not null default now(),
  tipo text not null check (tipo in ('ENTRADA','SAÍDA','AJUSTE')),
  origem text not null check (origem in ('PRODUÇÃO','EXPEDIÇÃO','ESTAMPARIA','AJUSTE','DEVOLUÇÃO')),
  origem_id uuid,
  produto_id bigint not null references mali.produtos(id),
  cor_id bigint not null references mali.cores(id),
  tamanho_id bigint not null references mali.tamanhos(id),
  qtd int not null check (qtd <> 0),   -- ENTRADA/SAÍDA sempre positivo; AJUSTE com sinal
  lote text,
  pedido_id uuid references mali.pedidos(id),
  cliente_id bigint references mali.clientes(id),
  obs text,
  usuario_id uuid default auth.uid(),
  check (tipo = 'AJUSTE' or qtd > 0)
);
create index on mali.estoque_mov(produto_id, cor_id, tamanho_id);
create index on mali.estoque_mov(origem_id);
create index on mali.estoque_mov(lote);

-- OP de estamparia a partir do estoque
create table mali.ops_estamparia (
  id uuid primary key default gen_random_uuid(),
  numero int generated always as identity,
  data timestamptz not null default now(),
  previsao date,
  produto_id bigint not null references mali.produtos(id),
  cor_id bigint not null references mali.cores(id),
  tamanho_id bigint not null references mali.tamanhos(id),
  qtd int not null check (qtd > 0),
  estampa text,
  pedido_id uuid references mali.pedidos(id),
  obs text,
  retorno_em timestamptz,
  qtd_retorno int,
  qtd_perda int,
  criado_por uuid default auth.uid()
);

-- ---------- Expedição ----------
create table mali.expedicoes (
  id uuid primary key default gen_random_uuid(),
  numero int generated always as identity,
  criado_em timestamptz not null default now(),
  pedido_item_id uuid references mali.pedido_itens(id),
  pedido_id uuid references mali.pedidos(id),
  cliente_id bigint references mali.clientes(id),
  produto_id bigint not null references mali.produtos(id),
  cor_id bigint not null references mali.cores(id),
  tamanho_id bigint not null references mali.tamanhos(id),
  qtd int not null check (qtd > 0),
  embalagem_inicio timestamptz,
  embalagem_fim timestamptz,
  liberado_em timestamptz,
  cancelado_em timestamptz,
  obs text,
  criado_por uuid default auth.uid()
);

-- ---------- Produção interna ----------
create table mali.apontamentos (
  id uuid primary key default gen_random_uuid(),
  operador_id bigint not null references mali.operadores(id),
  envio_id uuid not null references mali.envios(id),
  processo_id bigint not null references mali.processos(id),
  tempo_seg numeric(10,2) not null default 0,   -- tempo padrão por peça no momento do apontamento
  qtd int,
  inicio timestamptz not null default now(),
  fim timestamptz,
  obs text,
  criado_por uuid default auth.uid()
);
create unique index apontamento_aberto_por_operador on mali.apontamentos(operador_id) where fim is null;
create index on mali.apontamentos(envio_id, processo_id);

create table mali.pausas (
  id uuid primary key default gen_random_uuid(),
  operador_id bigint not null references mali.operadores(id),
  motivo_id bigint not null references mali.motivos_parada(id),
  inicio timestamptz not null default now(),
  fim timestamptz,
  obs text,
  criado_por uuid default auth.uid()
);
create unique index pausa_aberta_por_operador on mali.pausas(operador_id) where fim is null;
