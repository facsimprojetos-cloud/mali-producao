#!/bin/sh
# Teste local: recria o banco "t" num Postgres 16 local (porta 5499) e roda o fluxo completo
P="psql -h /tmp -p 5499 -U postgres"
$P -q -c "drop database if exists t" -c "create database t"
cat supabase/migrations/*.sql > /tmp/all.sql
$P -d t -q -v ON_ERROR_STOP=1 -f test/stub_supabase.sql -f /tmp/all.sql && $P -d t -q -f test/fluxo.sql
