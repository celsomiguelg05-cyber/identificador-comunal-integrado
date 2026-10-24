-- =====================================================================
-- Padrón comunal: carné comunal de Paxtocá (Totonicapán)
-- Moradores, carnés, asambleas y faenas, marcajes, incidentes, multas,
-- trámites, operadores y bitácora. Sincronización sin conexión por RPC.
--
-- Reglas:
--   * Cada operador pertenece a UNA comunidad y solo ve los datos de ella.
--   * Roles: admin > directiva > operador > consulta.
--   * Marcajes e incidentes nunca se borran ni se editan (solo se invalidan
--     o se marcan revisados). Moradores se dan de baja, no se borran.
--   * La llave privada de firma de carnés NO vive aquí.
-- =====================================================================

create extension if not exists pgcrypto with schema extensions;

create schema if not exists app_private;
revoke all on schema app_private from public;
grant usage on schema app_private to authenticated;

-- Secuencia global de cambios: cursor de sincronización
create sequence app_private.cambio_seq;
grant usage on sequence app_private.cambio_seq to authenticated;

-- ---------------------------------------------------------------------
-- Tablas
-- ---------------------------------------------------------------------

create table public.comunidades (
  id            text primary key check (id ~ '^[A-Z]{2,5}$'),
  nombre        text not null,
  municipio     text not null default 'Totonicapán',
  departamento  text not null default 'Totonicapán',
  llave_publica jsonb,                       -- JWK ECDSA P-256 para verificar carnés CC1
  config        jsonb not null default '{}'::jsonb,
  creada        timestamptz not null default now()
);
comment on table public.comunidades is 'Cada comunidad o cantón del municipio. Los datos de una comunidad son suyos.';

create table public.comunidad_secretos (
  comunidad_id  text primary key references public.comunidades(id) on delete cascade,
  hmac_qr       text,                        -- secreto maestro del QR rotativo CC2 (base64url, 32 bytes)
  actualizado   timestamptz not null default now()
);
comment on table public.comunidad_secretos is 'Secretos que necesitan los celulares que escanean. Solo admin, directiva y operador.';

create table public.operadores (
  user_id       uuid primary key references auth.users(id) on delete cascade,
  comunidad_id  text not null references public.comunidades(id),
  nombre        text not null,
  rol           text not null default 'operador'
                check (rol in ('admin','directiva','operador','consulta')),
  activo        boolean not null default true,
  creado        timestamptz not null default now()
);

create table public.dispositivos (
  id            text primary key,
  comunidad_id  text not null references public.comunidades(id),
  operador_id   uuid references public.operadores(user_id) on delete set null,
  nombre        text,
  primer_sync   timestamptz not null default now(),
  ultimo_sync   timestamptz not null default now()
);

create table public.moradores (
  id            text primary key,              -- 'PXT-0001'
  comunidad_id  text not null references public.comunidades(id),
  nombres       text not null,
  apellidos     text not null default '',
  dpi           text,
  nacimiento    date,
  sexo          text check (sexo in ('F','M')),
  sector        text,
  hogar         text,                          -- código de hogar / familia, opcional
  oficio        text,
  telefono      text,
  foto_path     text,                          -- Storage: fotos/PXT/PXT-0001.jpg
  ver           int not null default 1 check (ver >= 1),   -- nº de carné vigente
  estado        text not null default 'activo' check (estado in ('activo','baja')),
  obligado      boolean not null default true, -- obligado a asistir a asambleas y faenas
  creado        timestamptz not null default now(),
  actualizado   timestamptz not null default now(),
  actualizado_por uuid,
  dispositivo_id text,
  cambio        bigint not null default 0,
  constraint moradores_id_prefijo check (id like comunidad_id || '-%')
);
create unique index moradores_dpi_uq on public.moradores (comunidad_id, dpi) where dpi is not null;
create index moradores_comunidad_idx on public.moradores (comunidad_id, cambio);

create table public.carnes (
  id            bigint generated always as identity primary key,
  comunidad_id  text not null references public.comunidades(id),
  morador_id    text not null references public.moradores(id),
  ver           int not null,
  estado        text not null default 'vigente' check (estado in ('vigente','anulado')),
  emitido       timestamptz not null default now(),
  anulado_en    timestamptz,
  motivo        text,
  cambio        bigint not null default 0,
  unique (morador_id, ver)
);
-- Un solo carné vigente por persona: el anterior queda anulado al reponer.
create unique index carnes_un_vigente on public.carnes (morador_id) where estado = 'vigente';
create index carnes_comunidad_idx on public.carnes (comunidad_id, cambio);

create table public.asambleas (
  id            text primary key,              -- generado en el celular
  comunidad_id  text not null references public.comunidades(id),
  tipo          text not null default 'asamblea' check (tipo in ('asamblea','faena','reunion')),
  nombre        text not null,
  fecha         date not null,
  lugar         text,
  abierta       boolean not null default true,
  abierta_en    timestamptz,
  cerrada_en    timestamptz,
  multa_falta      numeric(10,2),              -- monto por inasistencia (opcional)
  multa_sin_salida numeric(10,2),              -- monto por irse sin marcar salida (opcional)
  creado        timestamptz not null default now(),
  dispositivo_id text,
  cambio        bigint not null default 0
);
comment on column public.asambleas.tipo is 'Las faenas usan el mismo control de entrada y salida que las asambleas.';
create index asambleas_comunidad_idx on public.asambleas (comunidad_id, fecha desc);
create index asambleas_cambio_idx on public.asambleas (comunidad_id, cambio);

create table public.marcajes (
  id            text primary key,              -- generado en el celular
  comunidad_id  text not null references public.comunidades(id),
  asamblea_id   text not null references public.asambleas(id),
  morador_id    text not null references public.moradores(id),
  tipo          text not null check (tipo in ('entrada','salida')),
  hora          timestamptz not null,
  via           text not null default 'carne' check (via in ('carne','digital','manual')),
  motivo        text not null default '',
  valido        boolean not null default true,
  invalidado_por text,                         -- id del marcaje que quedó válido
  invalidado_en timestamptz,
  dispositivo_id text,
  operador_id   uuid,
  recibido      timestamptz not null default now(),
  cambio        bigint not null default 0
);
-- Antitrampa: un solo marcaje válido de entrada y uno de salida por persona y asamblea,
-- aunque dos celulares sin conexión marquen a la misma persona.
create unique index marcajes_un_valido on public.marcajes (asamblea_id, morador_id, tipo) where valido;
create index marcajes_asamblea_idx on public.marcajes (asamblea_id, morador_id);
create index marcajes_cambio_idx on public.marcajes (comunidad_id, cambio);

create table public.incidentes (
  id            text primary key,
  comunidad_id  text not null references public.comunidades(id),
  asamblea_id   text references public.asambleas(id),
  persona       text,                          -- lo que se escaneó, aunque no exista
  morador_id    text references public.moradores(id),
  tipo          text not null check (tipo in
                  ('firma','anulado','doble','suplantacion','sin_entrada','baja','vencido','otro')),
  detalle       text not null default '',
  hora          timestamptz not null,
  origen        text not null default 'celular' check (origen in ('celular','servidor','panel')),
  revisado      boolean not null default false,
  revisado_por  uuid,
  nota          text,
  dispositivo_id text,
  cambio        bigint not null default 0
);
create index incidentes_asamblea_idx on public.incidentes (asamblea_id);
create index incidentes_cambio_idx on public.incidentes (comunidad_id, cambio);

create table public.multas (
  id            uuid primary key default gen_random_uuid(),
  comunidad_id  text not null references public.comunidades(id),
  morador_id    text not null references public.moradores(id),
  asamblea_id   text references public.asambleas(id),
  motivo        text not null check (motivo in ('inasistencia','sin_salida','sin_entrada','faena','otro')),
  descripcion   text,
  monto         numeric(10,2) not null check (monto > 0),
  estado        text not null default 'pendiente'
                check (estado in ('pendiente','pagada','condonada','anulada')),
  creada        timestamptz not null default now(),
  creada_por    uuid,
  pagada_en     timestamptz,
  recibo        text,
  cobrada_por   uuid,
  nota          text,
  cambio        bigint not null default 0,
  constraint multas_pago_coherente check (estado <> 'pagada' or pagada_en is not null)
);
create unique index multas_una_por_evento on public.multas (asamblea_id, morador_id, motivo)
  where asamblea_id is not null;
create index multas_morador_idx on public.multas (morador_id, estado);

create table public.tramites (
  id            uuid primary key default gen_random_uuid(),
  comunidad_id  text not null references public.comunidades(id),
  folio         int not null,
  morador_id    text not null references public.moradores(id),
  tipo          text not null check (tipo in
                  ('constancia_residencia','solvencia','carta_aval','reposicion_carne','otro')),
  descripcion   text,
  estado        text not null default 'solicitado'
                check (estado in ('solicitado','aprobado','entregado','rechazado')),
  solvente_al_solicitar boolean,
  monto         numeric(10,2) not null default 0 check (monto >= 0),
  creado        timestamptz not null default now(),
  creado_por    uuid,
  resuelto_en   timestamptz,
  resuelto_por  uuid,
  nota          text,
  cambio        bigint not null default 0,
  unique (comunidad_id, folio)
);
create index tramites_morador_idx on public.tramites (morador_id);

create table public.auditoria (
  id            bigint generated always as identity primary key,
  comunidad_id  text,
  tabla         text not null,
  registro_id   text not null,
  accion        text not null,
  antes         jsonb,
  despues       jsonb,
  usuario       uuid,
  cuando        timestamptz not null default now()
);
create index auditoria_comunidad_idx on public.auditoria (comunidad_id, cuando desc);

-- ---------------------------------------------------------------------
-- Funciones de apoyo (no expuestas por la API)
-- ---------------------------------------------------------------------

create or replace function app_private.mi_comunidad() returns text
language sql stable security definer set search_path = '' as $$
  select comunidad_id from public.operadores where user_id = auth.uid() and activo
$$;

create or replace function app_private.tengo_rol(p_comunidad text, p_roles text[]) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.operadores
                  where user_id = auth.uid() and activo
                    and comunidad_id = p_comunidad and rol = any(p_roles))
$$;

create or replace function app_private.marcar_cambio() returns trigger
language plpgsql set search_path = '' as $$
begin
  new.cambio := nextval('app_private.cambio_seq');
  return new;
end $$;

create or replace function app_private.tocar_actualizado() returns trigger
language plpgsql set search_path = '' as $$
begin
  new.actualizado := now();
  new.actualizado_por := coalesce(auth.uid(), new.actualizado_por);
  return new;
end $$;

create or replace function app_private.bitacora() returns trigger
language plpgsql security definer set search_path = '' as $$
declare v_row jsonb := to_jsonb(coalesce(new, old));
begin
  insert into public.auditoria (comunidad_id, tabla, registro_id, accion, antes, despues, usuario)
  values (v_row->>'comunidad_id', tg_table_name,
          coalesce(v_row->>'id', v_row->>'user_id', v_row->>'comunidad_id'), lower(tg_op),
          case when tg_op <> 'INSERT' then to_jsonb(old) end,
          case when tg_op <> 'DELETE' then to_jsonb(new) end,
          auth.uid());
  return coalesce(new, old);
end $$;

-- Doble marcaje entre celulares: gana el marcaje con la hora más temprana.
create or replace function app_private.resolver_doble_marcaje() returns trigger
language plpgsql security definer set search_path = '' as $$
declare v_previo public.marcajes;
begin
  if not new.valido then return new; end if;
  select * into v_previo from public.marcajes
   where asamblea_id = new.asamblea_id and morador_id = new.morador_id
     and tipo = new.tipo and valido
   for update;
  if not found then return new; end if;

  if v_previo.hora <= new.hora then
    new.valido := false;
    new.invalidado_por := v_previo.id;
    new.invalidado_en := now();
    insert into public.incidentes (id, comunidad_id, asamblea_id, persona, morador_id, tipo, detalle, hora, origen, dispositivo_id)
    values ('srv-doble-' || new.id, new.comunidad_id, new.asamblea_id, new.morador_id, new.morador_id, 'doble',
            format('%s repetida desde otro celular (%s). Vale la de %s.', new.tipo,
                   coalesce(new.dispositivo_id, '?'), to_char(v_previo.hora at time zone 'America/Guatemala', 'HH24:MI:SS')),
            new.hora, 'servidor', new.dispositivo_id)
    on conflict (id) do nothing;
  else
    update public.marcajes
       set valido = false, invalidado_por = new.id, invalidado_en = now()
     where id = v_previo.id;
    insert into public.incidentes (id, comunidad_id, asamblea_id, persona, morador_id, tipo, detalle, hora, origen, dispositivo_id)
    values ('srv-doble-' || v_previo.id, new.comunidad_id, new.asamblea_id, new.morador_id, new.morador_id, 'doble',
            format('%s repetida desde otro celular (%s). Vale la de %s.', new.tipo,
                   coalesce(v_previo.dispositivo_id, '?'), to_char(new.hora at time zone 'America/Guatemala', 'HH24:MI:SS')),
            v_previo.hora, 'servidor', v_previo.dispositivo_id)
    on conflict (id) do nothing;
  end if;
  return new;
end $$;

-- Marcajes: solo se puede cambiar la validez, nunca la persona, hora o tipo.
create or replace function app_private.marcaje_inmutable() returns trigger
language plpgsql set search_path = '' as $$
begin
  if tg_op = 'DELETE' then
    raise exception 'Los marcajes no se borran; se invalidan.' using errcode = '42501';
  end if;
  if (new.asamblea_id, new.morador_id, new.tipo, new.hora, new.via, new.comunidad_id)
     is distinct from (old.asamblea_id, old.morador_id, old.tipo, old.hora, old.via, old.comunidad_id) then
    raise exception 'Un marcaje no se puede modificar.' using errcode = '42501';
  end if;
  return new;
end $$;

create or replace function app_private.folio_tramite() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  perform pg_advisory_xact_lock(hashtext('folio:' || new.comunidad_id));
  select coalesce(max(folio), 0) + 1 into new.folio from public.tramites where comunidad_id = new.comunidad_id;
  select not exists (select 1 from public.multas
                      where morador_id = new.morador_id and estado = 'pendiente')
    into new.solvente_al_solicitar;
  new.creado_por := coalesce(auth.uid(), new.creado_por);
  return new;
end $$;

create or replace function app_private.ms_a_fecha(p jsonb) returns timestamptz
language sql immutable set search_path = '' as $$
  select case when p is null or p = 'null'::jsonb then null
              when jsonb_typeof(p) = 'number' then to_timestamp((p #>> '{}')::numeric / 1000)
              else (p #>> '{}')::timestamptz end
$$;

create or replace function app_private.fecha_a_ms(p timestamptz) returns bigint
language sql immutable set search_path = '' as $$
  select (extract(epoch from p) * 1000)::bigint
$$;

-- ---------------------------------------------------------------------
-- Disparadores
-- ---------------------------------------------------------------------
create trigger t_cambio before insert or update on public.moradores  for each row execute function app_private.marcar_cambio();
create trigger t_cambio before insert or update on public.carnes     for each row execute function app_private.marcar_cambio();
create trigger t_cambio before insert or update on public.asambleas  for each row execute function app_private.marcar_cambio();
create trigger t_cambio before insert or update on public.marcajes   for each row execute function app_private.marcar_cambio();
create trigger t_cambio before insert or update on public.incidentes for each row execute function app_private.marcar_cambio();
create trigger t_cambio before insert or update on public.multas     for each row execute function app_private.marcar_cambio();
create trigger t_cambio before insert or update on public.tramites   for each row execute function app_private.marcar_cambio();

create trigger t_actualizado before update on public.moradores for each row execute function app_private.tocar_actualizado();

create trigger t_doble before insert on public.marcajes for each row execute function app_private.resolver_doble_marcaje();
create trigger t_inmutable before update or delete on public.marcajes for each row execute function app_private.marcaje_inmutable();
create trigger t_folio before insert on public.tramites for each row execute function app_private.folio_tramite();

create trigger t_bitacora after insert or update or delete on public.moradores  for each row execute function app_private.bitacora();
create trigger t_bitacora after insert or update or delete on public.carnes     for each row execute function app_private.bitacora();
create trigger t_bitacora after insert or update or delete on public.asambleas  for each row execute function app_private.bitacora();
create trigger t_bitacora after insert or update or delete on public.multas     for each row execute function app_private.bitacora();
create trigger t_bitacora after insert or update or delete on public.tramites   for each row execute function app_private.bitacora();
create trigger t_bitacora after insert or update or delete on public.operadores for each row execute function app_private.bitacora();
create trigger t_bitacora after update on public.incidentes for each row execute function app_private.bitacora();
create trigger t_bitacora after update on public.comunidad_secretos for each row execute function app_private.bitacora();

-- ---------------------------------------------------------------------
-- Vistas (respetan RLS del que consulta)
-- ---------------------------------------------------------------------
create view public.v_asistencia with (security_invoker = true) as
with universo as (
  select a.id as asamblea_id, m.id as morador_id
    from public.asambleas a
    join public.moradores m on m.comunidad_id = a.comunidad_id
   where m.estado = 'activo' and m.obligado and m.creado::date <= a.fecha
  union
  select asamblea_id, morador_id from public.marcajes where valido
)
select a.comunidad_id, a.id as asamblea_id, a.tipo as tipo_evento, a.nombre as asamblea, a.fecha,
       m.id as morador_id, m.nombres, m.apellidos, m.sector,
       e.hora as entrada, s.hora as salida,
       round(extract(epoch from (s.hora - e.hora)) / 60)::int as minutos,
       case when e.hora is not null and s.hora is not null then 'completo'
            when e.hora is not null then 'sin_salida'
            when s.hora is not null then 'sin_entrada'
            else 'ausente' end as estado
  from universo u
  join public.asambleas a on a.id = u.asamblea_id
  join public.moradores m on m.id = u.morador_id
  left join public.marcajes e on e.asamblea_id = u.asamblea_id and e.morador_id = u.morador_id and e.tipo = 'entrada' and e.valido
  left join public.marcajes s on s.asamblea_id = u.asamblea_id and s.morador_id = u.morador_id and s.tipo = 'salida' and s.valido;

create view public.v_solvencia with (security_invoker = true) as
select m.comunidad_id, m.id as morador_id, m.nombres, m.apellidos, m.estado,
       count(mu.id) filter (where mu.estado = 'pendiente') as multas_pendientes,
       coalesce(sum(mu.monto) filter (where mu.estado = 'pendiente'), 0)::numeric(10,2) as total_pendiente,
       count(mu.id) filter (where mu.estado = 'pendiente') = 0 as solvente
  from public.moradores m
  left join public.multas mu on mu.morador_id = m.id
 group by m.comunidad_id, m.id;

create view public.v_resumen_asamblea with (security_invoker = true) as
select comunidad_id, asamblea_id, tipo_evento, asamblea, fecha,
       count(*) as esperados,
       count(*) filter (where estado = 'completo')    as completos,
       count(*) filter (where estado = 'sin_salida')  as sin_salida,
       count(*) filter (where estado = 'sin_entrada') as sin_entrada,
       count(*) filter (where estado = 'ausente')     as ausentes
  from public.v_asistencia
 group by comunidad_id, asamblea_id, tipo_evento, asamblea, fecha;

-- ---------------------------------------------------------------------
-- Seguridad por filas (RLS)
-- ---------------------------------------------------------------------
alter table public.comunidades        enable row level security;
alter table public.comunidad_secretos enable row level security;
alter table public.operadores         enable row level security;
alter table public.dispositivos       enable row level security;
alter table public.moradores          enable row level security;
alter table public.carnes             enable row level security;
alter table public.asambleas          enable row level security;
alter table public.marcajes           enable row level security;
alter table public.incidentes         enable row level security;
alter table public.multas             enable row level security;
alter table public.tramites           enable row level security;
alter table public.auditoria          enable row level security;

-- Solo las tablas de este módulo (no toca otras tablas que existan en el proyecto)
revoke all on public.comunidades, public.comunidad_secretos, public.operadores, public.dispositivos, public.moradores, public.carnes, public.asambleas, public.marcajes, public.incidentes, public.multas, public.tramites, public.auditoria from anon, authenticated;
grant select on public.comunidades, public.comunidad_secretos, public.operadores, public.dispositivos, public.moradores, public.carnes, public.asambleas, public.marcajes, public.incidentes, public.multas, public.tramites, public.auditoria to authenticated;
grant update (nombre, municipio, departamento, llave_publica, config) on public.comunidades to authenticated;
grant insert, update on public.comunidad_secretos to authenticated;
grant insert, update, delete on public.operadores to authenticated;
grant insert, update on public.moradores, public.asambleas to authenticated;
grant update (revisado, revisado_por, nota) on public.incidentes to authenticated;
grant insert, update on public.multas to authenticated;
grant insert, update on public.tramites to authenticated;

-- comunidades
create policy comunidades_ver on public.comunidades for select to authenticated
  using (id = (select app_private.mi_comunidad()));
create policy comunidades_editar on public.comunidades for update to authenticated
  using ((select app_private.tengo_rol(id, array['admin'])))
  with check ((select app_private.tengo_rol(id, array['admin'])));

-- secretos
create policy secretos_ver on public.comunidad_secretos for select to authenticated
  using ((select app_private.tengo_rol(comunidad_id, array['admin','directiva','operador'])));
create policy secretos_crear on public.comunidad_secretos for insert to authenticated
  with check ((select app_private.tengo_rol(comunidad_id, array['admin'])));
create policy secretos_editar on public.comunidad_secretos for update to authenticated
  using ((select app_private.tengo_rol(comunidad_id, array['admin'])))
  with check ((select app_private.tengo_rol(comunidad_id, array['admin'])));

-- operadores: cada quien ve su fila; el admin ve y administra los de su comunidad
create policy operadores_ver on public.operadores for select to authenticated
  using (user_id = (select auth.uid())
         or (select app_private.tengo_rol(comunidad_id, array['admin','directiva'])));
create policy operadores_crear on public.operadores for insert to authenticated
  with check ((select app_private.tengo_rol(comunidad_id, array['admin'])));
create policy operadores_editar on public.operadores for update to authenticated
  using ((select app_private.tengo_rol(comunidad_id, array['admin'])))
  with check ((select app_private.tengo_rol(comunidad_id, array['admin'])));
create policy operadores_borrar on public.operadores for delete to authenticated
  using ((select app_private.tengo_rol(comunidad_id, array['admin'])) and user_id <> (select auth.uid()));

-- lectura para cualquier miembro de la comunidad
create policy dispositivos_ver on public.dispositivos for select to authenticated
  using (comunidad_id = (select app_private.mi_comunidad()));
create policy moradores_ver on public.moradores for select to authenticated
  using (comunidad_id = (select app_private.mi_comunidad()));
create policy carnes_ver on public.carnes for select to authenticated
  using (comunidad_id = (select app_private.mi_comunidad()));
create policy asambleas_ver on public.asambleas for select to authenticated
  using (comunidad_id = (select app_private.mi_comunidad()));
create policy marcajes_ver on public.marcajes for select to authenticated
  using (comunidad_id = (select app_private.mi_comunidad()));
create policy incidentes_ver on public.incidentes for select to authenticated
  using (comunidad_id = (select app_private.mi_comunidad()));
create policy multas_ver on public.multas for select to authenticated
  using (comunidad_id = (select app_private.mi_comunidad()));
create policy tramites_ver on public.tramites for select to authenticated
  using (comunidad_id = (select app_private.mi_comunidad()));
create policy auditoria_ver on public.auditoria for select to authenticated
  using ((select app_private.tengo_rol(comunidad_id, array['admin'])));

-- escritura desde el panel (los celulares escriben por sync_subir)
create policy moradores_crear on public.moradores for insert to authenticated
  with check ((select app_private.tengo_rol(comunidad_id, array['admin','directiva','operador'])));
create policy moradores_editar on public.moradores for update to authenticated
  using ((select app_private.tengo_rol(comunidad_id, array['admin','directiva'])))
  with check ((select app_private.tengo_rol(comunidad_id, array['admin','directiva'])));
create policy asambleas_crear on public.asambleas for insert to authenticated
  with check ((select app_private.tengo_rol(comunidad_id, array['admin','directiva','operador'])));
create policy asambleas_editar on public.asambleas for update to authenticated
  using ((select app_private.tengo_rol(comunidad_id, array['admin','directiva'])))
  with check ((select app_private.tengo_rol(comunidad_id, array['admin','directiva'])));
create policy incidentes_revisar on public.incidentes for update to authenticated
  using ((select app_private.tengo_rol(comunidad_id, array['admin','directiva'])))
  with check ((select app_private.tengo_rol(comunidad_id, array['admin','directiva'])));
create policy multas_crear on public.multas for insert to authenticated
  with check ((select app_private.tengo_rol(comunidad_id, array['admin','directiva'])));
create policy multas_editar on public.multas for update to authenticated
  using ((select app_private.tengo_rol(comunidad_id, array['admin','directiva'])))
  with check ((select app_private.tengo_rol(comunidad_id, array['admin','directiva'])));
create policy tramites_crear on public.tramites for insert to authenticated
  with check ((select app_private.tengo_rol(comunidad_id, array['admin','directiva','operador'])));
create policy tramites_editar on public.tramites for update to authenticated
  using ((select app_private.tengo_rol(comunidad_id, array['admin','directiva'])))
  with check ((select app_private.tengo_rol(comunidad_id, array['admin','directiva'])));

grant select on public.v_asistencia, public.v_solvencia, public.v_resumen_asamblea to authenticated;

-- ---------------------------------------------------------------------
-- RPC de sincronización
-- ---------------------------------------------------------------------

-- Recibe el lote del celular con los objetos tal como están en IndexedDB:
-- {people:[...], assemblies:[...], marks:[...], incidents:[...]}
create or replace function public.sync_subir(p_comunidad text, p_dispositivo text, p_lote jsonb)
returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := auth.uid();
  r jsonb; a jsonb;
  v_rec int := 0;
  v_rech jsonb := '[]'::jsonb;
  v_ver int; v_estado text; v_prev public.moradores;
  v_tipo text; v_via text;
  v_dobles jsonb;
begin
  if not app_private.tengo_rol(p_comunidad, array['admin','directiva','operador']) then
    raise exception 'Sin permiso para sincronizar en %', p_comunidad using errcode = '42501';
  end if;
  if coalesce(p_dispositivo, '') = '' then
    raise exception 'Falta el identificador del celular' using errcode = '22023';
  end if;

  insert into public.dispositivos (id, comunidad_id, operador_id, ultimo_sync)
  values (p_dispositivo, p_comunidad, v_uid, now())
  on conflict (id) do update set ultimo_sync = now(), operador_id = excluded.operador_id
   where public.dispositivos.comunidad_id = p_comunidad;
  if not found then
    raise exception 'El celular % está registrado en otra comunidad', p_dispositivo using errcode = '42501';
  end if;

  -- 1. Moradores ------------------------------------------------------
  for r in select * from jsonb_array_elements(coalesce(p_lote->'people', '[]'::jsonb)) loop
    begin
      if coalesce(r->>'id', '') not like p_comunidad || '-%' then
        raise exception 'id de otra comunidad';
      end if;
      v_ver := greatest(coalesce((r->>'ver')::int, 1), 1);
      v_estado := case when r->>'estado' = 'baja' then 'baja' else 'activo' end;
      select * into v_prev from public.moradores where id = r->>'id' for update;

      if not found then
        insert into public.moradores (id, comunidad_id, nombres, apellidos, dpi, nacimiento, sexo, sector, hogar,
                                      oficio, telefono, foto_path, ver, estado, creado, actualizado_por, dispositivo_id)
        values (r->>'id', p_comunidad, coalesce(nullif(trim(r->>'nombres'), ''), '(sin nombre)'),
                coalesce(r->>'apellidos', ''), nullif(r->>'dpi', ''), nullif(r->>'nacimiento', '')::date,
                nullif(r->>'sexo', ''), nullif(r->>'sector', ''), nullif(r->>'hogar', ''),
                nullif(r->>'oficio', ''), nullif(r->>'telefono', ''),
                coalesce(nullif(r->>'foto_path', ''), p_comunidad || '/' || (r->>'id') || '.jpg'),
                v_ver, v_estado, coalesce(app_private.ms_a_fecha(r->'creado'), now()), v_uid, p_dispositivo);
      elsif v_prev.comunidad_id <> p_comunidad then
        raise exception 'id de otra comunidad';
      else
        -- El carné más nuevo manda. Con el mismo carné, se aceptan los datos que llegan.
        if v_ver >= v_prev.ver then
          update public.moradores set
            nombres    = coalesce(nullif(trim(r->>'nombres'), ''), nombres),
            apellidos  = coalesce(r->>'apellidos', apellidos),
            dpi        = coalesce(nullif(r->>'dpi', ''), dpi),
            nacimiento = coalesce(nullif(r->>'nacimiento', '')::date, nacimiento),
            sexo       = coalesce(nullif(r->>'sexo', ''), sexo),
            sector     = coalesce(nullif(r->>'sector', ''), sector),
            hogar      = coalesce(nullif(r->>'hogar', ''), hogar),
            oficio     = coalesce(nullif(r->>'oficio', ''), oficio),
            telefono   = coalesce(nullif(r->>'telefono', ''), telefono),
            foto_path  = coalesce(nullif(r->>'foto_path', ''), foto_path),
            ver        = v_ver,
            estado     = v_estado,
            dispositivo_id = p_dispositivo
          where id = v_prev.id;
        end if;
        v_ver := greatest(v_ver, v_prev.ver);
        v_estado := case when (r->>'ver')::int >= v_prev.ver then v_estado else v_prev.estado end;
      end if;

      -- Carnés anulados que reporta el celular
      for a in select * from jsonb_array_elements(coalesce(r->'anulados', '[]'::jsonb)) loop
        insert into public.carnes (comunidad_id, morador_id, ver, estado, emitido, anulado_en, motivo)
        values (p_comunidad, r->>'id', (a->>'ver')::int, 'anulado',
                coalesce(app_private.ms_a_fecha(a->'fecha'), now()),
                coalesce(app_private.ms_a_fecha(a->'fecha'), now()), 'reposición')
        on conflict (morador_id, ver) do update
          set estado = 'anulado', anulado_en = coalesce(public.carnes.anulado_en, excluded.anulado_en),
              motivo = coalesce(public.carnes.motivo, excluded.motivo)
          where public.carnes.estado <> 'anulado';
      end loop;

      -- Todo carné anterior al vigente queda anulado
      update public.carnes set estado = 'anulado', anulado_en = now(), motivo = coalesce(motivo, 'reposición')
       where morador_id = r->>'id' and estado = 'vigente' and (ver < v_ver or v_estado = 'baja');

      if v_estado = 'activo' then
        insert into public.carnes (comunidad_id, morador_id, ver, estado)
        values (p_comunidad, r->>'id', v_ver, 'vigente')
        on conflict (morador_id, ver) do nothing;
      else
        update public.carnes set estado = 'anulado', anulado_en = now(), motivo = 'baja'
         where morador_id = r->>'id' and estado = 'vigente';
      end if;
      v_rec := v_rec + 1;
    exception when others then
      v_rech := v_rech || jsonb_build_object('tabla', 'people', 'id', r->>'id', 'motivo', sqlerrm);
    end;
  end loop;

  -- 2. Asambleas y faenas ---------------------------------------------
  for r in select * from jsonb_array_elements(coalesce(p_lote->'assemblies', '[]'::jsonb)) loop
    begin
      insert into public.asambleas (id, comunidad_id, tipo, nombre, fecha, lugar, abierta, abierta_en, cerrada_en, dispositivo_id)
      values (r->>'id', p_comunidad,
              case when r->>'tipo' in ('asamblea','faena','reunion') then r->>'tipo' else 'asamblea' end,
              coalesce(nullif(trim(r->>'nombre'), ''), 'Asamblea'),
              coalesce(nullif(r->>'fecha', '')::date, (now() at time zone 'America/Guatemala')::date),
              nullif(r->>'lugar', ''),
              coalesce((r->>'abierta')::boolean, true),
              app_private.ms_a_fecha(r->'abierta_en'), app_private.ms_a_fecha(r->'cerrada_en'), p_dispositivo)
      on conflict (id) do update set
        nombre     = excluded.nombre,
        -- Cerrar es definitivo desde el celular; reabrir solo desde el panel.
        abierta    = public.asambleas.abierta and excluded.abierta,
        cerrada_en = coalesce(public.asambleas.cerrada_en, excluded.cerrada_en),
        abierta_en = coalesce(public.asambleas.abierta_en, excluded.abierta_en)
      where public.asambleas.comunidad_id = p_comunidad;
      if not found then raise exception 'id de otra comunidad'; end if;
      v_rec := v_rec + 1;
    exception when others then
      v_rech := v_rech || jsonb_build_object('tabla', 'assemblies', 'id', r->>'id', 'motivo', sqlerrm);
    end;
  end loop;

  -- 3. Marcajes (solo se insertan) ------------------------------------
  for r in select * from jsonb_array_elements(coalesce(p_lote->'marks', '[]'::jsonb))
             order by app_private.ms_a_fecha(value->'hora') loop
    begin
      if exists (select 1 from public.marcajes where id = r->>'id') then
        v_rec := v_rec + 1;   -- ya estaba: reintento del mismo lote
        continue;
      end if;
      if not exists (select 1 from public.asambleas where id = r->>'asamblea' and comunidad_id = p_comunidad) then
        raise exception 'asamblea desconocida';
      end if;
      if not exists (select 1 from public.moradores where id = r->>'persona' and comunidad_id = p_comunidad) then
        raise exception 'persona desconocida';
      end if;
      v_tipo := r->>'tipo';
      v_via := case when r->>'via' in ('carne','digital','manual') then r->>'via' else 'carne' end;
      insert into public.marcajes (id, comunidad_id, asamblea_id, morador_id, tipo, hora, via, motivo, dispositivo_id, operador_id)
      values (r->>'id', p_comunidad, r->>'asamblea', r->>'persona', v_tipo,
              app_private.ms_a_fecha(r->'hora'), v_via, coalesce(r->>'motivo', ''), p_dispositivo, v_uid);
      v_rec := v_rec + 1;
    exception when others then
      v_rech := v_rech || jsonb_build_object('tabla', 'marks', 'id', r->>'id', 'motivo', sqlerrm);
    end;
  end loop;

  -- 4. Incidentes (solo se insertan) ----------------------------------
  for r in select * from jsonb_array_elements(coalesce(p_lote->'incidents', '[]'::jsonb)) loop
    begin
      v_tipo := case when r->>'tipo' in ('firma','anulado','doble','suplantacion','sin_entrada','baja','vencido')
                     then r->>'tipo' else 'otro' end;
      insert into public.incidentes (id, comunidad_id, asamblea_id, persona, morador_id, tipo, detalle, hora, dispositivo_id)
      values (r->>'id', p_comunidad,
              (select id from public.asambleas where id = r->>'asamblea' and comunidad_id = p_comunidad),
              r->>'persona',
              (select id from public.moradores where id = r->>'persona' and comunidad_id = p_comunidad),
              v_tipo,
              case when v_tipo = 'otro' and r->>'tipo' is not null
                   then '[' || (r->>'tipo') || '] ' else '' end || coalesce(r->>'detalle', ''),
              coalesce(app_private.ms_a_fecha(r->'hora'), now()), p_dispositivo)
      on conflict (id) do nothing;
      v_rec := v_rec + 1;
    exception when others then
      v_rech := v_rech || jsonb_build_object('tabla', 'incidents', 'id', r->>'id', 'motivo', sqlerrm);
    end;
  end loop;

  -- Marcajes que el servidor invalidó en esta sincronización (doble marcaje)
  select coalesce(jsonb_agg(id), '[]'::jsonb) into v_dobles
    from public.marcajes where comunidad_id = p_comunidad and invalidado_en = now();

  return jsonb_build_object('ok', jsonb_array_length(v_rech) = 0, 'recibidos', v_rec,
                            'rechazados', v_rech, 'dobles', v_dobles);
end $$;

-- Devuelve lo que cambió desde el cursor, en el formato de la app.
create or replace function public.sync_bajar(p_comunidad text, p_desde bigint default null)
returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare v_desde bigint := coalesce(p_desde, 0);
begin
  if not app_private.tengo_rol(p_comunidad, array['admin','directiva','operador','consulta']) then
    raise exception 'Sin permiso para %', p_comunidad using errcode = '42501';
  end if;

  return jsonb_build_object(
    'people', (select coalesce(jsonb_agg(jsonb_build_object(
        'id', m.id, 'nombres', m.nombres, 'apellidos', m.apellidos, 'dpi', m.dpi,
        'nacimiento', m.nacimiento, 'sexo', m.sexo, 'sector', m.sector, 'hogar', m.hogar,
        'oficio', m.oficio, 'telefono', m.telefono, 'foto_path', m.foto_path,
        'ver', m.ver, 'estado', m.estado, 'obligado', m.obligado,
        'anulados', (select coalesce(jsonb_agg(jsonb_build_object('ver', c.ver,
                       'fecha', app_private.fecha_a_ms(c.anulado_en)) order by c.ver), '[]'::jsonb)
                       from public.carnes c where c.morador_id = m.id and c.estado = 'anulado'),
        'creado', app_private.fecha_a_ms(m.creado),
        'actualizado', app_private.fecha_a_ms(m.actualizado)) order by m.id), '[]'::jsonb)
      from public.moradores m
      where m.comunidad_id = p_comunidad
        and (m.cambio > v_desde
             or exists (select 1 from public.carnes c where c.morador_id = m.id and c.cambio > v_desde))),
    'assemblies', (select coalesce(jsonb_agg(jsonb_build_object(
        'id', a.id, 'tipo', a.tipo, 'nombre', a.nombre, 'fecha', a.fecha, 'lugar', a.lugar,
        'abierta', a.abierta, 'abierta_en', app_private.fecha_a_ms(a.abierta_en),
        'cerrada_en', app_private.fecha_a_ms(a.cerrada_en)) order by a.fecha), '[]'::jsonb)
      from public.asambleas a where a.comunidad_id = p_comunidad and a.cambio > v_desde),
    'marks', (select coalesce(jsonb_agg(jsonb_build_object(
        'id', k.id, 'asamblea', k.asamblea_id, 'persona', k.morador_id, 'tipo', k.tipo,
        'hora', app_private.fecha_a_ms(k.hora), 'via', k.via, 'motivo', k.motivo,
        'valido', k.valido, 'dispositivo', k.dispositivo_id) order by k.hora), '[]'::jsonb)
      from public.marcajes k where k.comunidad_id = p_comunidad and k.cambio > v_desde),
    'incidents', (select coalesce(jsonb_agg(jsonb_build_object(
        'id', i.id, 'asamblea', i.asamblea_id, 'persona', i.persona, 'tipo', i.tipo,
        'detalle', i.detalle, 'hora', app_private.fecha_a_ms(i.hora), 'origen', i.origen,
        'revisado', i.revisado) order by i.hora), '[]'::jsonb)
      from public.incidentes i where i.comunidad_id = p_comunidad and i.cambio > v_desde),
    'cursor', greatest(v_desde,
       coalesce((select max(cambio) from public.moradores  where comunidad_id = p_comunidad), 0),
       coalesce((select max(cambio) from public.carnes     where comunidad_id = p_comunidad), 0),
       coalesce((select max(cambio) from public.asambleas  where comunidad_id = p_comunidad), 0),
       coalesce((select max(cambio) from public.marcajes   where comunidad_id = p_comunidad), 0),
       coalesce((select max(cambio) from public.incidentes where comunidad_id = p_comunidad), 0))
  );
end $$;

-- ---------------------------------------------------------------------
-- Multas por asamblea o faena
-- ---------------------------------------------------------------------
create or replace function public.generar_multas(p_asamblea text,
                                                 p_monto_falta numeric default null,
                                                 p_monto_sin_salida numeric default null)
returns int
language plpgsql security definer set search_path = '' as $$
declare v_a public.asambleas; v_n int;
begin
  select * into v_a from public.asambleas where id = p_asamblea;
  if not found then raise exception 'Asamblea no existe'; end if;
  if not app_private.tengo_rol(v_a.comunidad_id, array['admin','directiva']) then
    raise exception 'Solo la directiva genera multas' using errcode = '42501';
  end if;
  if v_a.abierta then raise exception 'Primero cierre la asamblea'; end if;

  update public.asambleas
     set multa_falta = coalesce(p_monto_falta, multa_falta),
         multa_sin_salida = coalesce(p_monto_sin_salida, multa_sin_salida)
   where id = p_asamblea
   returning * into v_a;

  insert into public.multas (comunidad_id, morador_id, asamblea_id, motivo, monto, descripcion, creada_por)
  select v.comunidad_id, v.morador_id, v.asamblea_id,
         case when v.estado = 'ausente' and v.tipo_evento = 'faena' then 'faena'
              when v.estado = 'ausente' then 'inasistencia'
              else v.estado end,
         case when v.estado = 'ausente' then v_a.multa_falta else v_a.multa_sin_salida end,
         format('%s del %s', v.asamblea, to_char(v.fecha, 'DD/MM/YYYY')),
         auth.uid()
    from public.v_asistencia v
    join public.moradores m on m.id = v.morador_id
   where v.asamblea_id = p_asamblea
     and m.obligado and m.estado = 'activo'
     and v.estado in ('ausente','sin_salida','sin_entrada')
     and coalesce(case when v.estado = 'ausente' then v_a.multa_falta else v_a.multa_sin_salida end, 0) > 0
  on conflict (asamblea_id, morador_id, motivo) where asamblea_id is not null do nothing;
  get diagnostics v_n = row_count;
  return v_n;
end $$;

-- ---------------------------------------------------------------------
-- Verificación pública de carnés (página web, sin sesión)
-- No revela nombres: solo si el carné está vigente.
-- CC1 (impreso): la firma ECDSA se verifica en el navegador con llave_publica.
-- CC2 (celular, rotativo): el servidor verifica el HMAC.
-- ---------------------------------------------------------------------
create or replace function public.verificar_carne(p_qr text)
returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_p text[] := string_to_array(p_qr, '|');
  v_id text; v_ver int; v_com text; v_c public.comunidades;
  v_estado_carne text; v_estado_m text;
  v_master bytea; v_secreto bytea; v_paso bigint; v_ahora bigint; v_ok boolean := null;
  v_b64 text;
begin
  if coalesce(array_length(v_p, 1), 0) < 4 or v_p[1] not in ('CC1','CC2') then
    return jsonb_build_object('valido_formato', false);
  end if;
  v_id := v_p[2];
  begin v_ver := v_p[3]::int; exception when others then
    return jsonb_build_object('valido_formato', false); end;
  v_com := split_part(v_id, '-', 1);
  select * into v_c from public.comunidades where id = v_com;
  if not found then return jsonb_build_object('valido_formato', true, 'comunidad', null, 'vigente', false); end if;

  select c.estado, m.estado into v_estado_carne, v_estado_m
    from public.moradores m left join public.carnes c on c.morador_id = m.id and c.ver = v_ver
   where m.id = v_id and m.comunidad_id = v_com;

  if v_p[1] = 'CC2' and array_length(v_p, 1) >= 5 then
    select decode(translate(hmac_qr, '-_', '+/') || repeat('=', (4 - length(hmac_qr) % 4) % 4), 'base64')
      into v_master from public.comunidad_secretos where comunidad_id = v_com;
    if v_master is not null then
      v_secreto := extensions.hmac(convert_to(v_id || '|' || v_ver, 'UTF8'), v_master, 'sha256');
      v_ahora := floor(extract(epoch from now()) / 30);
      begin v_paso := v_p[4]::bigint; exception when others then v_paso := null; end;
      v_ok := false;
      if v_paso is not null and abs(v_paso - v_ahora) <= 1 then
        v_b64 := rtrim(translate(encode(substring(extensions.hmac(
                   convert_to(v_id || '|' || v_ver || '|' || v_paso, 'UTF8'), v_secreto, 'sha256') from 1 for 12),
                   'base64'), '+/', '-_'), '=');
        v_ok := v_b64 = v_p[5];
      end if;
    end if;
  end if;

  return jsonb_build_object(
    'valido_formato', true,
    'comunidad', v_c.nombre,
    'vigente', coalesce(v_estado_carne = 'vigente' and v_estado_m = 'activo', false),
    'estado', case when v_estado_m is null then 'no_registrado'
                   when v_estado_m = 'baja' then 'baja'
                   when v_estado_carne = 'vigente' then 'vigente'
                   else 'anulado' end,
    'codigo_rotativo_ok', v_ok,
    'llave_publica', v_c.llave_publica
  );
end $$;

-- ---------------------------------------------------------------------
-- Permisos de ejecución
-- ---------------------------------------------------------------------
revoke execute on function public.sync_subir(text, text, jsonb), public.sync_bajar(text, bigint),
  public.generar_multas(text, numeric, numeric), public.verificar_carne(text) from public, anon, authenticated;
revoke execute on all functions in schema app_private from public, anon;
grant execute on function app_private.mi_comunidad(), app_private.tengo_rol(text, text[]) to authenticated;
grant execute on function public.sync_subir(text, text, jsonb) to authenticated;
grant execute on function public.sync_bajar(text, bigint) to authenticated;
grant execute on function public.generar_multas(text, numeric, numeric) to authenticated;
grant execute on function public.verificar_carne(text) to anon, authenticated;

-- ---------------------------------------------------------------------
-- Storage: fotos de moradores (privado). Ruta: <COMUNIDAD>/<ID>.jpg
-- ---------------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('fotos', 'fotos', false, 524288, array['image/jpeg','image/webp','image/png'])
on conflict (id) do nothing;

create policy fotos_ver on storage.objects for select to authenticated
  using (bucket_id = 'fotos' and (storage.foldername(name))[1] = (select app_private.mi_comunidad()));
create policy fotos_subir on storage.objects for insert to authenticated
  with check (bucket_id = 'fotos'
              and (select app_private.tengo_rol((storage.foldername(name))[1], array['admin','directiva','operador'])));
create policy fotos_reemplazar on storage.objects for update to authenticated
  using (bucket_id = 'fotos'
         and (select app_private.tengo_rol((storage.foldername(name))[1], array['admin','directiva','operador'])))
  with check (bucket_id = 'fotos'
              and (select app_private.tengo_rol((storage.foldername(name))[1], array['admin','directiva','operador'])));

-- ---------------------------------------------------------------------
-- Datos iniciales
-- ---------------------------------------------------------------------
insert into public.comunidades (id, nombre) values ('PXT', 'Paxtocá')
on conflict (id) do nothing;
