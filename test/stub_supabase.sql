do $$ begin if not exists (select 1 from pg_roles where rolname=$q$authenticated$q$) then create role authenticated nologin; create role anon nologin; end if; end $$;
create schema auth;
create table auth.users(id uuid primary key, email text, created_at timestamptz default now());
create or replace function auth.uid() returns uuid language sql stable as $$ select nullif(current_setting('request.jwt.claim.sub', true),'')::uuid $$;
grant usage on schema auth to authenticated; grant execute on function auth.uid() to authenticated;
