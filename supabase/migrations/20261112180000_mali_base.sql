-- MALI — Gestão de Produção
-- Parte 1: schema, usuários/perfis, auditoria e cadastros

create schema if not exists mali;
grant usage on schema mali to authenticated;

create or replace function mali.hoje() returns date
language sql stable set search_path to '' as $$
  select (now() at time zone 'America/Sao_Paulo')::date;
$$;

-- ---------- Usuários e perfis ----------
-- perfis: admin, supervisor, cadastros, comercial, corte, faccao, producao, estamparia, qualidade, estoque, financeiro
create table mali.usuarios (
  id uuid primary key references auth.users(id) on delete cascade,
  nome text not null,
  email text,
  perfis text[] not null default '{}',
  ativo boolean not null default true,
  criado_em timestamptz not null default now()
);

create table mali.auditoria (
  id bigint generated always as identity primary key,
  em timestamptz not null default now(),
  usuario_id uuid default auth.uid(),
  acao text not null,
  tabela text,
  registro text,
  dados jsonb
);

create or replace function mali.eh_usuario() returns boolean
language sql stable security definer set search_path to '' as $$
  select exists (select 1 from mali.usuarios u where u.id = auth.uid() and u.ativo);
$$;

create or replace function mali.tem_perfil(p text) returns boolean
language sql stable security definer set search_path to '' as $$
  select exists (select 1 from mali.usuarios u
                 where u.id = auth.uid() and u.ativo
                   and ('admin' = any(u.perfis) or p = any(u.perfis)));
$$;

create or replace function mali.exigir_perfil(p text) returns void
language plpgsql stable security definer set search_path to '' as $$
begin
  if not mali.tem_perfil(p) then
    raise exception 'Acesso negado: esta ação exige o perfil "%".', p using errcode = '42501';
  end if;
end $$;

create or replace function mali._audit(p_acao text, p_tabela text, p_registro text, p_dados jsonb) returns void
language sql security definer set search_path to '' as $$
  insert into mali.auditoria(acao, tabela, registro, dados) values (p_acao, p_tabela, p_registro, p_dados);
$$;

create or replace function mali.status_sistema() returns jsonb
language sql stable security definer set search_path to '' as $$
  select jsonb_build_object(
    'tem_admin', exists (select 1 from mali.usuarios),
    'usuario', (select jsonb_build_object('nome', u.nome, 'perfis', u.perfis, 'ativo', u.ativo)
                from mali.usuarios u where u.id = auth.uid()));
$$;

create or replace function mali.bootstrap_admin(p_nome text) returns void
language plpgsql security definer set search_path to '' as $$
begin
  if auth.uid() is null then raise exception 'Faça login primeiro.'; end if;
  perform pg_advisory_xact_lock(hashtext('mali.bootstrap'));
  if exists (select 1 from mali.usuarios) then raise exception 'Já existe administrador configurado.'; end if;
  insert into mali.usuarios(id, nome, email, perfis)
  select auth.uid(), p_nome, u.email, array['admin'] from auth.users u where u.id = auth.uid();
end $$;

-- Contas criadas no Auth que ainda não foram liberadas (para a tela de Usuários)
create or replace function mali.contas_pendentes() returns table(id uuid, email text, criado_em timestamptz)
language plpgsql stable security definer set search_path to '' as $$
begin
  perform mali.exigir_perfil('admin');
  return query select u.id, u.email::text, u.created_at from auth.users u
    where not exists (select 1 from mali.usuarios m where m.id = u.id) order by u.created_at desc limit 200;
end $$;

create or replace function mali.salvar_usuario(p_id uuid, p_nome text, p_perfis text[], p_ativo boolean) returns void
language plpgsql security definer set search_path to '' as $$
declare v_validos text[] := array['admin','supervisor','cadastros','comercial','corte','faccao','producao','estamparia','qualidade','estoque','financeiro'];
begin
  perform mali.exigir_perfil('admin');
  if exists (select 1 from unnest(p_perfis) x where x <> all(v_validos)) then raise exception 'Perfil inválido.'; end if;
  if p_id = auth.uid() and (not p_ativo or not ('admin' = any(p_perfis))) then
    raise exception 'Você não pode remover o seu próprio acesso de administrador.'; end if;
  insert into mali.usuarios(id, nome, email, perfis, ativo)
  select p_id, p_nome, u.email, p_perfis, p_ativo from auth.users u where u.id = p_id
  on conflict (id) do update set nome = excluded.nome, perfis = excluded.perfis, ativo = excluded.ativo;
  if not found then raise exception 'Conta não encontrada.'; end if;
  perform mali._audit('salvar_usuario', 'usuarios', p_id::text, jsonb_build_object('perfis', p_perfis, 'ativo', p_ativo));
end $$;

-- ---------- Cadastros ----------
create table mali.clientes (
  id bigint generated always as identity primary key,
  nome text not null unique,
  telefone text, documento text, obs text,
  ativo boolean not null default true,
  legado_id text
);

create table mali.cores (
  id bigint generated always as identity primary key,
  nome text not null unique,
  ativo boolean not null default true,
  legado_id text
);

create table mali.tamanhos (
  id bigint generated always as identity primary key,
  nome text not null unique,
  ordem int not null default 0,
  ativo boolean not null default true,
  legado_id text
);

create table mali.produtos (
  id bigint generated always as identity primary key,
  codigo text,
  nome text not null unique,
  foto_url text,
  preco numeric(12,2),                 -- preço de venda / referência
  valor_faccao numeric(12,2),          -- valor pago por peça à facção (padrão do envio)
  estamparia_apos boolean not null default false, -- vai para estamparia depois da produção
  obs text,
  ativo boolean not null default true,
  legado_id text
);

create table mali.faccoes (
  id bigint generated always as identity primary key,
  numero int,
  nome text not null unique,
  endereco text, telefone text, maquinas text, pix text,
  capacidade int,                      -- peças por semana (referência)
  interna boolean not null default false, -- PRODUÇÃO INTERNA
  foto_url text,
  ativo boolean not null default true,
  legado_id text
);

create table mali.operadores (
  id bigint generated always as identity primary key,
  nome text not null unique,
  foto_url text,
  ativo boolean not null default true
);

create table mali.processos (
  id bigint generated always as identity primary key,
  nome text not null unique,
  ativo boolean not null default true,
  legado_id text
);

-- Roteiro: sequência de operações do produto com tempo padrão (segundos por peça)
create table mali.produto_processos (
  id bigint generated always as identity primary key,
  produto_id bigint not null references mali.produtos(id) on delete cascade,
  processo_id bigint not null references mali.processos(id),
  sequencia int not null default 1,
  tempo_seg numeric(10,2) not null default 0 check (tempo_seg >= 0),
  unique (produto_id, processo_id)
);

create table mali.motivos_parada (
  id bigint generated always as identity primary key,
  nome text not null unique,
  duracao_min int,                     -- duração prevista (min), opcional
  produtiva boolean not null default false,
  ativo boolean not null default true
);

create table mali.materias_primas (
  id bigint generated always as identity primary key,
  nome text not null,
  unidade text not null default 'UNIDADE' check (unidade in ('KG','METRO','UNIDADE','ROLO','PACOTE','CONE')),
  tipo text not null default 'AVIAMENTO' check (tipo in ('TECIDO','AVIAMENTO','ACESSÓRIO','EMBALAGEM','OUTRO')),
  valor numeric(12,4) not null default 0,
  rendimento numeric(10,3), largura numeric(10,3), gramatura numeric(10,3),
  fornecedor text,
  ativo boolean not null default true,
  legado_id text
);

-- Ficha do produto (dados de criação/modelagem)
create table mali.fichas_produto (
  produto_id bigint primary key references mali.produtos(id) on delete cascade,
  referencia text, criacao text, pilotagem text,
  grade text,
  foto_frente text, foto_costas text,
  info_corte text, obs text,
  atualizado_em timestamptz not null default now()
);

create table mali.ficha_medidas (
  id bigint generated always as identity primary key,
  produto_id bigint not null references mali.produtos(id) on delete cascade,
  descricao text not null,
  medidas jsonb not null default '{}'::jsonb,  -- {"P":"30","M":"32",...}
  ordem int not null default 0
);

-- Ficha técnica: consumo de matéria-prima por peça
create table mali.ficha_tecnica (
  id bigint generated always as identity primary key,
  produto_id bigint not null references mali.produtos(id) on delete cascade,
  materia_prima_id bigint not null references mali.materias_primas(id),
  consumo numeric(12,4) not null check (consumo > 0),
  obs text,
  unique (produto_id, materia_prima_id)
);
