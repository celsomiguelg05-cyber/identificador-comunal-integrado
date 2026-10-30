-- =====================================================================
-- Multas completas: tardanza, rechazo de convenios, catálogo de
-- infracciones que edita la directiva, hora de inicio y tolerancia de
-- asambleas y faenas, y multas en la sincronización de celulares.
-- =====================================================================

-- ---------------------------------------------------------------------
-- Asambleas y faenas: hora de inicio y tolerancia para la tardanza
-- ---------------------------------------------------------------------
alter table public.asambleas
  add column inicio      time,
  add column tolerancia  int not null default 15 check (tolerancia between 0 and 240),
  add column multa_tardanza numeric(10,2);
comment on column public.asambleas.inicio is 'Hora local (Guatemala) de inicio. Entrada después de inicio + tolerancia = tardanza.';

-- ---------------------------------------------------------------------
-- Catálogo de infracciones (montos que fija la directiva)
-- ---------------------------------------------------------------------
create table public.infracciones (
  comunidad_id  text not null references public.comunidades(id),
  codigo        text not null check (codigo ~ '^[a-z0-9_]{2,40}$'),
  nombre        text not null,
  monto         numeric(10,2) not null check (monto >= 0),
  activo        boolean not null default true,
  orden         int not null default 0,
  actualizado   timestamptz not null default now(),
  cambio        bigint not null default 0,
  primary key (comunidad_id, codigo)
);
create trigger t_cambio before insert or update on public.infracciones for each row execute function app_private.marcar_cambio();
create trigger t_bitacora after insert or update or delete on public.infracciones for each row execute function app_private.bitacora();

alter table public.infracciones enable row level security;
revoke all on public.infracciones from anon, authenticated;
grant select, insert, update on public.infracciones to authenticated;
create policy infracciones_ver on public.infracciones for select to authenticated
  using (comunidad_id = (select app_private.mi_comunidad()));
create policy infracciones_crear on public.infracciones for insert to authenticated
  with check ((select app_private.tengo_rol(comunidad_id, array['admin','directiva'])));
create policy infracciones_editar on public.infracciones for update to authenticated
  using ((select app_private.tengo_rol(comunidad_id, array['admin','directiva'])))
  with check ((select app_private.tengo_rol(comunidad_id, array['admin','directiva'])));

insert into public.infracciones (comunidad_id, codigo, nombre, monto, orden) values
  ('PXT', 'inasistencia', 'Falta a asamblea',                 50, 1),
  ('PXT', 'tardanza',     'Llegar tarde',                      10, 2),
  ('PXT', 'sin_salida',   'Irse sin marcar salida',            25, 3),
  ('PXT', 'faena',        'Falta a faena',                     75, 4),
  ('PXT', 'convenio',     'Rechazar un convenio comunal',     100, 5),
  ('PXT', 'otro',         'Otra (monto se escribe cada vez)',   0, 6)
on conflict do nothing;

-- ---------------------------------------------------------------------
-- Multas: nuevos motivos, ids generados en el celular, código del catálogo
-- ---------------------------------------------------------------------
alter table public.multas drop constraint multas_motivo_check;
alter table public.multas add constraint multas_motivo_check check (motivo in
  ('inasistencia','tardanza','sin_salida','sin_entrada','faena','convenio','otro'));
drop view public.v_solvencia;   -- depende del tipo de multas.id; se recrea abajo
alter table public.multas alter column id drop default;
alter table public.multas alter column id type text using id::text;
alter table public.multas alter column id set default gen_random_uuid()::text;
alter table public.multas
  add column infraccion     text,      -- código del catálogo cuando no es un motivo fijo
  add column dispositivo_id text;

create view public.v_solvencia with (security_invoker = true) as
select m.comunidad_id, m.id as morador_id, m.nombres, m.apellidos, m.estado,
       count(mu.id) filter (where mu.estado = 'pendiente') as multas_pendientes,
       coalesce(sum(mu.monto) filter (where mu.estado = 'pendiente'), 0)::numeric(10,2) as total_pendiente,
       count(mu.id) filter (where mu.estado = 'pendiente') = 0 as solvente
  from public.moradores m
  left join public.multas mu on mu.morador_id = m.id
 group by m.comunidad_id, m.id;
grant select on public.v_solvencia to authenticated;

-- ---------------------------------------------------------------------
-- Asistencia con tardanza
-- ---------------------------------------------------------------------
create or replace view public.v_asistencia with (security_invoker = true) as
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
            else 'ausente' end as estado,
       coalesce(e.hora > ((a.fecha + a.inicio) at time zone 'America/Guatemala')
                         + make_interval(mins => a.tolerancia), false) as tarde,
       greatest(0, round(extract(epoch from (e.hora - ((a.fecha + a.inicio) at time zone 'America/Guatemala'))) / 60))::int
         as minutos_tarde
  from universo u
  join public.asambleas a on a.id = u.asamblea_id
  join public.moradores m on m.id = u.morador_id
  left join public.marcajes e on e.asamblea_id = u.asamblea_id and e.morador_id = u.morador_id and e.tipo = 'entrada' and e.valido
  left join public.marcajes s on s.asamblea_id = u.asamblea_id and s.morador_id = u.morador_id and s.tipo = 'salida' and s.valido;

-- ---------------------------------------------------------------------
-- Cálculo de multas de una asamblea o faena (sin revisar permisos).
-- Montos: lo que se pase > lo guardado en la asamblea > el catálogo.
-- Ausente -> inasistencia (faena si el evento es faena); entrada después
-- de inicio + tolerancia -> tardanza; sin salida -> sin_salida.
-- ---------------------------------------------------------------------
create or replace function app_private.calcular_multas(p_asamblea text,
                                                       p_monto_falta numeric default null,
                                                       p_monto_sin_salida numeric default null,
                                                       p_monto_tardanza numeric default null,
                                                       p_usuario uuid default null)
returns int
language plpgsql security definer set search_path = '' as $$
declare v_a public.asambleas; v_n int;
begin
  select * into v_a from public.asambleas where id = p_asamblea;
  if not found then raise exception 'Asamblea no existe'; end if;
  if v_a.tipo = 'reunion' and p_monto_falta is null and v_a.multa_falta is null then
    return 0;   -- las reuniones de comité no multan salvo que se indique monto
  end if;

  update public.asambleas a set
    multa_falta      = coalesce(p_monto_falta, a.multa_falta,
                         (select monto from public.infracciones i where i.comunidad_id = a.comunidad_id and i.activo
                            and i.codigo = case when a.tipo = 'faena' then 'faena' else 'inasistencia' end)),
    multa_sin_salida = coalesce(p_monto_sin_salida, a.multa_sin_salida,
                         (select monto from public.infracciones i where i.comunidad_id = a.comunidad_id and i.activo and i.codigo = 'sin_salida')),
    multa_tardanza   = coalesce(p_monto_tardanza, a.multa_tardanza,
                         (select monto from public.infracciones i where i.comunidad_id = a.comunidad_id and i.activo and i.codigo = 'tardanza'))
   where a.id = p_asamblea
   returning * into v_a;

  with faltas as (
    select v.comunidad_id, v.morador_id, v.asamblea_id, v.asamblea, v.fecha,
           case when v.estado = 'ausente' and v.tipo_evento = 'faena' then 'faena'
                when v.estado = 'ausente' then 'inasistencia'
                else v.estado end as motivo,
           case when v.estado = 'ausente' then v_a.multa_falta else v_a.multa_sin_salida end as monto,
           null::int as minutos_tarde
      from public.v_asistencia v
     where v.asamblea_id = p_asamblea and v.estado in ('ausente','sin_salida','sin_entrada')
    union all
    select v.comunidad_id, v.morador_id, v.asamblea_id, v.asamblea, v.fecha,
           'tardanza', v_a.multa_tardanza, v.minutos_tarde
      from public.v_asistencia v
     where v.asamblea_id = p_asamblea and v.tarde and v_a.inicio is not null
  )
  insert into public.multas (comunidad_id, morador_id, asamblea_id, motivo, monto, descripcion, creada_por)
  select f.comunidad_id, f.morador_id, f.asamblea_id, f.motivo, f.monto,
         format('%s del %s', f.asamblea, to_char(f.fecha, 'DD/MM/YYYY'))
           || case when f.minutos_tarde is not null then format(' (%s min tarde)', f.minutos_tarde) else '' end,
         p_usuario
    from faltas f
    join public.moradores m on m.id = f.morador_id
   where m.obligado and m.estado = 'activo' and coalesce(f.monto, 0) > 0
  on conflict (asamblea_id, morador_id, motivo) where asamblea_id is not null do nothing;
  get diagnostics v_n = row_count;
  return v_n;
end $$;
revoke execute on function app_private.calcular_multas(text, numeric, numeric, numeric, uuid) from public, anon, authenticated;

drop function public.generar_multas(text, numeric, numeric);
create function public.generar_multas(p_asamblea text,
                                      p_monto_falta numeric default null,
                                      p_monto_sin_salida numeric default null,
                                      p_monto_tardanza numeric default null)
returns int
language plpgsql security definer set search_path = '' as $$
declare v_a public.asambleas;
begin
  select * into v_a from public.asambleas where id = p_asamblea;
  if not found then raise exception 'Asamblea no existe'; end if;
  if not app_private.tengo_rol(v_a.comunidad_id, array['admin','directiva']) then
    raise exception 'Solo la directiva genera multas' using errcode = '42501';
  end if;
  if v_a.abierta then raise exception 'Primero cierre la asamblea'; end if;
  return app_private.calcular_multas(p_asamblea, p_monto_falta, p_monto_sin_salida, p_monto_tardanza, auth.uid());
end $$;
revoke execute on function public.generar_multas(text, numeric, numeric, numeric) from public, anon;
grant execute on function public.generar_multas(text, numeric, numeric, numeric) to authenticated;

-- ---------------------------------------------------------------------
-- Sincronización: multas, infracciones e inicio/tolerancia
-- ---------------------------------------------------------------------
-- Aplica en el servidor la parte nueva del lote. sync_subir la llama al final.
create or replace function app_private.sync_subir_multas(p_comunidad text, p_dispositivo text, p_lote jsonb)
returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  r jsonb; v_rec int := 0; v_rech jsonb := '[]'::jsonb;
  v_directiva boolean := app_private.tengo_rol(p_comunidad, array['admin','directiva']);
  v_motivo text; v_prev public.multas; v_estado text;
begin
  -- Inicio y tolerancia de asambleas que vienen en el mismo lote
  for r in select * from jsonb_array_elements(coalesce(p_lote->'assemblies', '[]'::jsonb)) loop
    update public.asambleas set
      inicio     = coalesce(nullif(r->>'inicio', '')::time, inicio),
      tolerancia = coalesce((r->>'tolerancia')::int, tolerancia)
     where id = r->>'id' and comunidad_id = p_comunidad
       and (r ? 'inicio' or r ? 'tolerancia');
  end loop;

  -- Catálogo de infracciones (solo directiva)
  for r in select * from jsonb_array_elements(coalesce(p_lote->'infracciones', '[]'::jsonb)) loop
    begin
      if not v_directiva then raise exception 'solo la directiva edita el catálogo'; end if;
      insert into public.infracciones (comunidad_id, codigo, nombre, monto, activo, orden)
      values (p_comunidad, r->>'codigo', coalesce(nullif(trim(r->>'nombre'), ''), r->>'codigo'),
              (r->>'monto')::numeric, coalesce((r->>'activo')::boolean, true), coalesce((r->>'orden')::int, 0))
      on conflict (comunidad_id, codigo) do update set
        nombre = excluded.nombre, monto = excluded.monto, activo = excluded.activo,
        orden = excluded.orden, actualizado = now();
      v_rec := v_rec + 1;
    exception when others then
      v_rech := v_rech || jsonb_build_object('tabla', 'infracciones', 'id', r->>'codigo', 'motivo', sqlerrm);
    end;
  end loop;

  -- Multas (solo directiva). Pagada, condonada y anulada son definitivas.
  for r in select * from jsonb_array_elements(coalesce(p_lote->'multas', '[]'::jsonb)) loop
    begin
      if not v_directiva then raise exception 'solo la directiva registra multas'; end if;
      if not exists (select 1 from public.moradores where id = r->>'persona' and comunidad_id = p_comunidad) then
        raise exception 'persona desconocida';
      end if;
      v_motivo := case when r->>'motivo' in ('inasistencia','tardanza','sin_salida','sin_entrada','faena','convenio')
                       then r->>'motivo' else 'otro' end;
      v_estado := case when r->>'estado' in ('pendiente','pagada','condonada','anulada') then r->>'estado' else 'pendiente' end;
      select * into v_prev from public.multas where id = r->>'id' for update;

      if not found then
        insert into public.multas (id, comunidad_id, morador_id, asamblea_id, motivo, infraccion, descripcion, monto,
                                   estado, creada, creada_por, pagada_en, recibo, cobrada_por, nota, dispositivo_id)
        values (r->>'id', p_comunidad, r->>'persona',
                (select id from public.asambleas where id = r->>'asamblea' and comunidad_id = p_comunidad),
                v_motivo, case when v_motivo = 'otro' then nullif(r->>'motivo', '') end,
                nullif(r->>'descripcion', ''), (r->>'monto')::numeric, v_estado,
                coalesce(app_private.ms_a_fecha(r->'creada'), now()), auth.uid(),
                case when v_estado = 'pagada' then coalesce(app_private.ms_a_fecha(r->'pagada_en'), now()) end,
                nullif(r->>'recibo', ''), case when v_estado = 'pagada' then auth.uid() end,
                nullif(r->>'nota', ''), p_dispositivo)
        on conflict (asamblea_id, morador_id, motivo) where asamblea_id is not null do nothing;
        if not found then
          raise exception 'ya existe una multa por % en esa asamblea', v_motivo;
        end if;
      elsif v_prev.comunidad_id <> p_comunidad then
        raise exception 'id de otra comunidad';
      elsif v_prev.estado = 'pendiente' then
        update public.multas set
          monto       = coalesce((r->>'monto')::numeric, monto),
          descripcion = coalesce(nullif(r->>'descripcion', ''), descripcion),
          estado      = v_estado,
          pagada_en   = case when v_estado = 'pagada' then coalesce(app_private.ms_a_fecha(r->'pagada_en'), now()) end,
          recibo      = coalesce(nullif(r->>'recibo', ''), recibo),
          cobrada_por = case when v_estado = 'pagada' then auth.uid() end,
          nota        = coalesce(nullif(r->>'nota', ''), nota),
          dispositivo_id = p_dispositivo
         where id = v_prev.id;
      elsif v_estado <> v_prev.estado then
        raise exception 'la multa ya está % y no se puede cambiar a %', v_prev.estado, v_estado;
      end if;
      v_rec := v_rec + 1;
    exception when others then
      v_rech := v_rech || jsonb_build_object('tabla', 'multas', 'id', r->>'id', 'motivo', sqlerrm);
    end;
  end loop;

  return jsonb_build_object('recibidos', v_rec, 'rechazados', v_rech);
end $$;
revoke execute on function app_private.sync_subir_multas(text, text, jsonb) from public, anon, authenticated;

-- sync_subir: igual que antes, más multas e infracciones al final.
alter function public.sync_subir(text, text, jsonb) rename to sync_subir_base;
revoke execute on function public.sync_subir_base(text, text, jsonb) from public, anon, authenticated;
alter function public.sync_subir_base(text, text, jsonb) set schema app_private;

create function public.sync_subir(p_comunidad text, p_dispositivo text, p_lote jsonb)
returns jsonb
language plpgsql security definer set search_path = '' as $$
declare v_base jsonb; v_extra jsonb; v_rech jsonb;
begin
  v_base := app_private.sync_subir_base(p_comunidad, p_dispositivo, p_lote);
  v_extra := app_private.sync_subir_multas(p_comunidad, p_dispositivo, p_lote);
  v_rech := (v_base->'rechazados') || (v_extra->'rechazados');
  return jsonb_build_object('ok', jsonb_array_length(v_rech) = 0,
                            'recibidos', (v_base->>'recibidos')::int + (v_extra->>'recibidos')::int,
                            'rechazados', v_rech, 'dobles', v_base->'dobles');
end $$;
revoke execute on function public.sync_subir(text, text, jsonb) from public, anon;
grant execute on function public.sync_subir(text, text, jsonb) to authenticated;

-- sync_bajar: igual que antes, más multas, infracciones e inicio/tolerancia.
alter function public.sync_bajar(text, bigint) rename to sync_bajar_base;
revoke execute on function public.sync_bajar_base(text, bigint) from public, anon, authenticated;
alter function public.sync_bajar_base(text, bigint) set schema app_private;

create function public.sync_bajar(p_comunidad text, p_desde bigint default null)
returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare v_desde bigint := coalesce(p_desde, 0); v jsonb;
begin
  v := app_private.sync_bajar_base(p_comunidad, p_desde);   -- revisa permisos
  return v
    || jsonb_build_object(
      'assemblies', (select coalesce(jsonb_agg(x || jsonb_build_object(
                        'inicio', to_char(a.inicio, 'HH24:MI'), 'tolerancia', a.tolerancia)), '[]'::jsonb)
                       from jsonb_array_elements(v->'assemblies') x
                       join public.asambleas a on a.id = x->>'id'),
      'multas', (select coalesce(jsonb_agg(jsonb_build_object(
          'id', mu.id, 'persona', mu.morador_id, 'asamblea', mu.asamblea_id,
          'motivo', coalesce(mu.infraccion, mu.motivo), 'descripcion', mu.descripcion,
          'monto', mu.monto, 'estado', mu.estado,
          'creada', app_private.fecha_a_ms(mu.creada), 'pagada_en', app_private.fecha_a_ms(mu.pagada_en),
          'recibo', mu.recibo, 'nota', mu.nota) order by mu.creada), '[]'::jsonb)
        from public.multas mu where mu.comunidad_id = p_comunidad and mu.cambio > v_desde),
      'infracciones', (select coalesce(jsonb_agg(jsonb_build_object(
          'codigo', i.codigo, 'nombre', i.nombre, 'monto', i.monto, 'activo', i.activo, 'orden', i.orden)
          order by i.orden, i.codigo), '[]'::jsonb)
        from public.infracciones i where i.comunidad_id = p_comunidad),
      'cursor', greatest((v->>'cursor')::bigint,
         coalesce((select max(cambio) from public.multas where comunidad_id = p_comunidad), 0),
         coalesce((select max(cambio) from public.infracciones where comunidad_id = p_comunidad), 0)));
end $$;
revoke execute on function public.sync_bajar(text, bigint) from public, anon;
grant execute on function public.sync_bajar(text, bigint) to authenticated;
