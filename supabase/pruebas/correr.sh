#!/usr/bin/env bash
# Corre las pruebas en un PostgreSQL local (no toca Supabase).
# Uso (desde la raíz del repo): PGHOST=/var/tmp/pg PGPORT=5433 PGUSER=postgres bash supabase/pruebas/correr.sh
set -euo pipefail
cd "$(dirname "$0")/.."
J=$(node pruebas/qr2.mjs)
get() { echo "$J" | node -pe "JSON.parse(require('fs').readFileSync(0)).$1"; }
P="psql -v ON_ERROR_STOP=1 -q"
$P -c 'drop database if exists padron_prueba' -c 'create database padron_prueba'
$P -d padron_prueba -f pruebas/00_stub_supabase.sql
for f in migrations/*.sql; do $P -d padron_prueba -f "$f"; done
$P -d padron_prueba -v master="$(get master)" -v qr2="$(get qr)" -v qr2malo="$(get malo)" -f pruebas/01_pruebas.sql
