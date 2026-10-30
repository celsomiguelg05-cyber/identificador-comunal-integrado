-- Pruebas del padrón comunal. Correr después de 00_stub_supabase.sql y la migración.
\set ON_ERROR_STOP 1
\pset format unaligned
\pset tuples_only on

-- Usuarios y operadores de prueba (como dueño de la base)
insert into public.comunidades (id, nombre) values ('CHI', 'Chiyax');
insert into auth.users (id, email) values
 ('00000000-0000-0000-0000-00000000000a', 'admin@pxt'),
 ('00000000-0000-0000-0000-00000000000d', 'directiva@pxt'),
 ('00000000-0000-0000-0000-00000000000b', 'operadorA@pxt'),
 ('00000000-0000-0000-0000-00000000000c', 'consulta@pxt'),
 ('00000000-0000-0000-0000-0000000000ff', 'operador@chi');
insert into public.operadores (user_id, comunidad_id, nombre, rol) values
 ('00000000-0000-0000-0000-00000000000a', 'PXT', 'Admin', 'admin'),
 ('00000000-0000-0000-0000-00000000000d', 'PXT', 'Directiva', 'directiva'),
 ('00000000-0000-0000-0000-00000000000b', 'PXT', 'Operador A', 'operador'),
 ('00000000-0000-0000-0000-00000000000c', 'PXT', 'Consulta', 'consulta'),
 ('00000000-0000-0000-0000-0000000000ff', 'CHI', 'Operador Chiyax', 'operador');
insert into public.comunidad_secretos (comunidad_id, hmac_qr) values ('PXT', :'master');

create or replace function pg_temp.como(p uuid) returns void language sql as $$
  select set_config('request.jwt.claims', json_build_object('sub', p, 'role', 'authenticated')::text, false) $$;

-- ===== 1. El celular A sube su lote (formato IndexedDB, horas en ms) =====
select pg_temp.como('00000000-0000-0000-0000-00000000000b');
set role authenticated;
\echo '1. primer lote del celular A'
select public.sync_subir('PXT', 'cel-A', $j${
 "people":[
  {"id":"PXT-0001","nombres":"Juana","apellidos":"Tzunún Batz","nacimiento":"1980-05-02","sector":"Centro","oficio":"Tejedora","telefono":"5555-0001","foto":"data:image/jpeg;base64,AAAA","ver":1,"estado":"activo","anulados":[],"creado":1761268800000},
  {"id":"PXT-0002","nombres":"Pedro","apellidos":"Batz","nacimiento":"1975-01-10","sector":"Chuixchimal","oficio":"Agricultor","ver":2,"estado":"activo","anulados":[{"ver":1,"fecha":1761268900000}],"creado":1761268800000},
  {"id":"PXT-0003","nombres":"María","apellidos":"Ixcoy","ver":1,"estado":"activo","anulados":[],"creado":1761268800000},
  {"id":"PXT-0004","nombres":"Diego","apellidos":"Chuc","ver":1,"estado":"baja","anulados":[],"creado":1761268800000},
  {"id":"CHI-0001","nombres":"Intruso","ver":1,"estado":"activo","anulados":[]}],
 "assemblies":[{"id":"asm1","nombre":"Asamblea general","fecha":"2025-10-24","abierta":true,"abierta_en":1761300000000,"cerrada_en":null}],
 "marks":[
  {"id":"m1","asamblea":"asm1","persona":"PXT-0001","tipo":"entrada","hora":1761300600000,"via":"carne","motivo":""},
  {"id":"m2","asamblea":"asm1","persona":"PXT-0002","tipo":"entrada","hora":1761300700000,"via":"carne","motivo":""},
  {"id":"m3","asamblea":"asm1","persona":"PXT-0001","tipo":"salida","hora":1761310000000,"via":"carne","motivo":""},
  {"id":"m4","asamblea":"asm1","persona":"PXT-9999","tipo":"entrada","hora":1761300800000,"via":"manual","motivo":"x"}],
 "incidents":[{"id":"i1","asamblea":"asm1","persona":"PXT-0002","tipo":"anulado","detalle":"Presentó carné nº1","hora":1761300650000},
              {"id":"i2","asamblea":"asm1","persona":"PXT-0003","tipo":"vencido","detalle":"captura","hora":1761300660000},
              {"id":"i3","asamblea":"asm1","persona":"ZZZ","tipo":"rarisimo","detalle":"?","hora":1761300670000}]
}$j$::jsonb);

do $$ begin
  assert (select count(*) from public.moradores) = 4, 'deben quedar 4 moradores (CHI rechazado)';
  assert (select foto_path from public.moradores where id='PXT-0001') = 'PXT/PXT-0001.jpg', 'foto_path por defecto';
  assert (select string_agg(ver||estado, ',' order by ver) from public.carnes where morador_id='PXT-0002') = '1anulado,2vigente', 'reposición';
  assert (select count(*) from public.carnes where morador_id='PXT-0004' and estado='vigente') = 0, 'baja sin carné vigente';
  assert (select count(*) from public.marcajes) = 3, 'm4 rechazado (persona desconocida)';
  assert (select tipo from public.incidentes where id='i3') = 'otro', 'tipo desconocido -> otro';
  assert (select detalle from public.incidentes where id='i3') like '[rarisimo]%', 'conserva tipo original';
  assert (select tipo from public.incidentes where id='i2') = 'vencido', 'acepta vencido';
end $$;
\echo '   OK'

\echo '2. reintento del mismo lote (idempotente)'
select (public.sync_subir('PXT', 'cel-A', $j${"marks":[{"id":"m1","asamblea":"asm1","persona":"PXT-0001","tipo":"entrada","hora":1761300600000,"via":"carne"}],
 "incidents":[{"id":"i1","asamblea":"asm1","persona":"PXT-0002","tipo":"anulado","detalle":"Presentó carné nº1","hora":1761300650000}]}$j$::jsonb))->>'ok';
do $$ begin
  assert (select count(*) from public.marcajes) = 3, 'sin duplicados';
  assert (select count(*) from public.incidentes where origen='celular') = 3, 'sin incidentes duplicados';
end $$;
\echo '   OK'

-- ===== 3. Celular B estuvo sin señal y marcó a Juana ANTES que A =====
\echo '3. doble marcaje entre celulares'
select public.sync_subir('PXT', 'cel-B', $j${"marks":[
  {"id":"b1","asamblea":"asm1","persona":"PXT-0001","tipo":"entrada","hora":1761300500000,"via":"digital"},
  {"id":"b2","asamblea":"asm1","persona":"PXT-0002","tipo":"entrada","hora":1761309999000,"via":"carne"}]}$j$::jsonb);
do $$ begin
  assert (select valido from public.marcajes where id='b1'), 'b1 (más temprano) queda válido';
  assert not (select valido from public.marcajes where id='m1'), 'm1 queda invalidado';
  assert not (select valido from public.marcajes where id='b2'), 'b2 (más tarde) invalidado';
  assert (select count(*) from public.incidentes where tipo='doble' and origen='servidor') = 2, 'dos incidentes doble';
  assert (select count(*) from public.marcajes where valido and asamblea_id='asm1' and morador_id='PXT-0001' and tipo='entrada') = 1;
end $$;
\echo '   OK'

\echo '4. sync_bajar y cursor'
select jsonb_array_length(x->'people') || ' personas, ' || jsonb_array_length(x->'marks') || ' marcajes, cursor ' || (x->>'cursor')
  from (select public.sync_bajar('PXT', null) x) s;
select (x->'people'->1->'anulados')::text from (select public.sync_bajar('PXT', null) x) s;
do $$ declare c bigint; x jsonb; begin
  c := (public.sync_bajar('PXT', null)->>'cursor')::bigint;
  x := public.sync_bajar('PXT', c);
  assert jsonb_array_length(x->'people') + jsonb_array_length(x->'marks') + jsonb_array_length(x->'incidents') + jsonb_array_length(x->'assemblies') = 0, 'nada nuevo';
  assert (x->>'cursor')::bigint = c, 'cursor estable';
end $$;
\echo '   OK'

\echo '5. reposición posterior desde otro celular + celular viejo con carné 1'
select (public.sync_subir('PXT', 'cel-B', $j${"people":[{"id":"PXT-0001","nombres":"Juana","apellidos":"Tzunún Batz","ver":2,"estado":"activo","anulados":[{"ver":1,"fecha":1761400000000}]}]}$j$::jsonb))->>'ok';
select (public.sync_subir('PXT', 'cel-A', $j${"people":[{"id":"PXT-0001","nombres":"JUANA VIEJA","ver":1,"estado":"activo","anulados":[]}]}$j$::jsonb))->>'ok';
do $$ begin
  assert (select ver from public.moradores where id='PXT-0001') = 2, 'no retrocede el carné';
  assert (select nombres from public.moradores where id='PXT-0001') = 'Juana', 'dato viejo no pisa';
  assert (select string_agg(ver||estado, ',' order by ver) from public.carnes where morador_id='PXT-0001') = '1anulado,2vigente';
end $$;
\echo '   OK'
reset role;

-- ===== 6. Aislamiento entre comunidades y roles =====
\echo '6. aislamiento y roles'
select pg_temp.como('00000000-0000-0000-0000-0000000000ff');
set role authenticated;
do $$ begin
  assert (select count(*) from public.moradores) = 0, 'Chiyax no ve Paxtocá';
  assert (select count(*) from public.marcajes) = 0;
  begin perform public.sync_subir('PXT', 'cel-X', '{}'); assert false, 'debió fallar';
  exception when insufficient_privilege then null; end;
  begin perform public.sync_bajar('PXT'); assert false, 'debió fallar';
  exception when insufficient_privilege then null; end;
  begin perform public.sync_subir('CHI', 'cel-A', '{}'); assert false, 'celular de otra comunidad';
  exception when insufficient_privilege then null; end;
  begin insert into public.moradores (id, comunidad_id, nombres) values ('PXT-0099','PXT','x'); assert false;
  exception when insufficient_privilege then null; end;
end $$;
reset role;
select pg_temp.como('00000000-0000-0000-0000-00000000000c');
set role authenticated;
do $$ begin
  assert (select count(*) from public.moradores) = 4, 'consulta lee';
  assert jsonb_array_length(public.sync_bajar('PXT')->'people') = 4, 'consulta baja datos';
  begin perform public.sync_subir('PXT', 'cel-C', '{}'); assert false;
  exception when insufficient_privilege then null; end;
  assert (select count(*) from public.comunidad_secretos) = 0, 'consulta no ve secretos';
  assert (select count(*) from public.auditoria) = 0, 'consulta no ve bitácora';
  update public.moradores set nombres='x';
end $$;
reset role;
do $$ begin assert (select count(*) from public.moradores where nombres='x') = 0, 'consulta no edita'; end $$;
select pg_temp.como('00000000-0000-0000-0000-00000000000b');
set role authenticated;
do $$ declare n int; begin
  assert (select count(*) from public.comunidad_secretos) = 1, 'operador ve secreto QR';
  update public.moradores set nombres='x' where id='PXT-0003';
  get diagnostics n = row_count;
  assert n = 0, 'operador no edita moradores directo';
  begin update public.marcajes set valido=false; assert false;
  exception when insufficient_privilege then null; end;
  begin delete from public.marcajes; assert false;
  exception when insufficient_privilege then null; end;
end $$;
reset role;
\echo '   OK'

\echo '7. marcajes inmutables aun para el dueño'
do $$ begin
  begin update public.marcajes set hora = now() where id='b1'; assert false;
  exception when insufficient_privilege then null; end;
  begin delete from public.marcajes where id='b1'; assert false;
  exception when insufficient_privilege then null; end;
end $$;
\echo '   OK'

-- ===== 8. Cierre y multas =====
\echo '8. cierre, multas, solvencia y trámites'
select pg_temp.como('00000000-0000-0000-0000-00000000000b');
set role authenticated;
do $$ begin
  begin perform public.generar_multas('asm1', 25, 10); assert false, 'operador no multa';
  exception when insufficient_privilege then null; end;
end $$;
select (public.sync_subir('PXT', 'cel-A', $j${"assemblies":[{"id":"asm1","nombre":"Asamblea general","fecha":"2025-10-24","abierta":false,"abierta_en":1761300000000,"cerrada_en":1761312000000}]}$j$::jsonb))->>'ok';
-- un celular atrasado la manda abierta: debe seguir cerrada
select (public.sync_subir('PXT', 'cel-B', $j${"assemblies":[{"id":"asm1","nombre":"Asamblea general","fecha":"2025-10-24","abierta":true,"abierta_en":1761300000000,"cerrada_en":null}]}$j$::jsonb))->>'ok';
reset role;
update public.moradores set creado = '2025-10-01' ;
select pg_temp.como('00000000-0000-0000-0000-00000000000d');
set role authenticated;
select * from public.v_asistencia where asamblea_id='asm1' order by morador_id;
update public.moradores set telefono='5555-0003' where id='PXT-0003';
select 'multas generadas: ' || public.generar_multas('asm1', 25, 10);
select 'segunda vez: ' || public.generar_multas('asm1', 25, 10);
select morador_id, motivo, monto from public.multas order by morador_id;
do $$ begin
  assert not (select abierta from public.asambleas where id='asm1'), 'sigue cerrada';
  assert (select count(*) from public.multas) = 2, '0002 sin salida y 0003 ausente; 0001 completo; 0004 baja';
  assert (select motivo from public.multas where morador_id='PXT-0003') = 'inasistencia';
  assert (select motivo from public.multas where morador_id='PXT-0002') = 'sin_salida';
end $$;
insert into public.tramites (comunidad_id, morador_id, tipo, folio) values ('PXT','PXT-0003','constancia_residencia', 0);
update public.multas set estado='pagada', pagada_en=now(), recibo='R-001' where morador_id='PXT-0003';
insert into public.tramites (comunidad_id, morador_id, tipo, folio) values ('PXT','PXT-0003','solvencia', 0);
select folio, tipo, solvente_al_solicitar from public.tramites order by folio;
do $$ begin
  assert (select array_agg(folio order by folio) from public.tramites) = array[1,2], 'folios correlativos';
  assert (select array_agg(solvente_al_solicitar order by folio) from public.tramites) = array[false,true], 'solvencia';
  assert (select solvente from public.v_solvencia where morador_id='PXT-0002') = false;
end $$;
reset role;
\echo '   OK'

\echo '9. fotos en Storage'
select pg_temp.como('00000000-0000-0000-0000-00000000000b');
set role authenticated;
insert into storage.objects (bucket_id, name) values ('fotos', 'PXT/PXT-0001.jpg');
do $$ begin
  begin insert into storage.objects (bucket_id, name) values ('fotos', 'CHI/CHI-0001.jpg'); assert false;
  exception when insufficient_privilege then null; end;
end $$;
reset role;
select pg_temp.como('00000000-0000-0000-0000-0000000000ff');
set role authenticated;
do $$ begin assert (select count(*) from storage.objects) = 0, 'Chiyax no ve fotos de Paxtocá'; end $$;
reset role;
\echo '   OK'

\echo '10. verificación pública (anon)'
set role anon;
select public.verificar_carne('CC1|PXT-0002|2|firma')::text;
select public.verificar_carne('CC1|PXT-0002|1|firma')->>'estado';
select public.verificar_carne('CC1|PXT-0004|1|firma')->>'estado';
select public.verificar_carne('basura')::text;
select (public.verificar_carne(:'qr2')->>'codigo_rotativo_ok') as cc2_bueno;
select (public.verificar_carne(:'qr2malo')->>'codigo_rotativo_ok') as cc2_malo;
do $$ begin
  begin perform count(*) from public.moradores; assert false, 'anon no lee tablas';
  exception when insufficient_privilege then null; end;
  begin perform public.sync_bajar('PXT'); assert false;
  exception when insufficient_privilege then null; end;
end $$;
reset role;
\echo '   OK'

-- ===== 11. Multas completas: tardanza, convenios, catálogo, sincronización =====
\echo '11. tardanza, convenios, catálogo y multas por sincronización'
select pg_temp.como('00000000-0000-0000-0000-00000000000b');
set role authenticated;
-- operador: asamblea con hora de inicio 08:00 y 10 min de tolerancia (hora Guatemala = UTC-6)
select (public.sync_subir('PXT', 'cel-A', $j${
 "assemblies":[{"id":"asm2","nombre":"Asamblea de noviembre","fecha":"2026-11-01","inicio":"08:00","tolerancia":10,"abierta":true,"abierta_en":1793541600000}],
 "marks":[
  {"id":"n1","asamblea":"asm2","persona":"PXT-0001","tipo":"entrada","hora":1793541900000,"via":"carne"},
  {"id":"n2","asamblea":"asm2","persona":"PXT-0002","tipo":"entrada","hora":1793543400000,"via":"carne"},
  {"id":"n3","asamblea":"asm2","persona":"PXT-0001","tipo":"salida","hora":1793552400000,"via":"carne"},
  {"id":"n4","asamblea":"asm2","persona":"PXT-0002","tipo":"salida","hora":1793552400000,"via":"carne"}]}$j$::jsonb))->>'ok';
-- el operador no puede tocar multas ni catálogo
select (public.sync_subir('PXT', 'cel-A', $j${"infracciones":[{"codigo":"tardanza","nombre":"Tarde","monto":1}],
  "multas":[{"id":"x1","persona":"PXT-0003","asamblea":null,"motivo":"convenio","monto":100,"estado":"pendiente","creada":1793541600000}]}$j$::jsonb))->'rechazados';
select (public.sync_subir('PXT', 'cel-A', $j${"assemblies":[{"id":"asm2","nombre":"Asamblea de noviembre","fecha":"2026-11-01","abierta":false,"cerrada_en":1793553000000}]}$j$::jsonb))->>'ok';
reset role;
do $$ begin
  assert (select inicio from public.asambleas where id='asm2') = '08:00', 'inicio guardado';
  assert (select tolerancia from public.asambleas where id='asm2') = 10, 'tolerancia guardada';
  assert (select tarde from public.v_asistencia where asamblea_id='asm2' and morador_id='PXT-0002'), 'Pedro llegó 30 min tarde';
  assert not (select tarde from public.v_asistencia where asamblea_id='asm2' and morador_id='PXT-0001'), 'Juana a tiempo (5 min)';
  assert (select count(*) from public.multas where id='x1') = 0, 'operador no crea multas';
  assert (select monto from public.infracciones where codigo='tardanza') = 10, 'operador no cambia catálogo';
end $$;

select pg_temp.como('00000000-0000-0000-0000-00000000000d');
set role authenticated;
-- directiva cambia el monto de la tardanza y agrega una infracción propia
select (public.sync_subir('PXT', 'cel-D', $j${"infracciones":[{"codigo":"tardanza","nombre":"Llegar tarde","monto":7.5},
  {"codigo":"cuota_agua","nombre":"No pagar la cuota de agua","monto":20,"orden":9}]}$j$::jsonb))->>'ok';
select 'multas asm2: ' || public.generar_multas('asm2');
select morador_id, motivo, monto, descripcion from public.multas where asamblea_id='asm2' order by morador_id, motivo;
-- multas desde el celular: convenio, catálogo propio, pago y reintento
select (public.sync_subir('PXT', 'cel-D', $j${"multas":[
  {"id":"c1","persona":"PXT-0003","asamblea":null,"motivo":"convenio","descripcion":"Rechazó el convenio del agua","monto":100,"estado":"pendiente","creada":1793541600000},
  {"id":"c2","persona":"PXT-0001","asamblea":null,"motivo":"cuota_agua","monto":20,"estado":"pagada","creada":1793541600000,"pagada_en":1793600000000,"recibo":"R-0100"}]}$j$::jsonb))->>'ok';
select (public.sync_subir('PXT', 'cel-D', $j${"multas":[{"id":"c1","persona":"PXT-0003","motivo":"convenio","monto":100,"estado":"pagada","pagada_en":1793700000000,"recibo":"R-0101"}]}$j$::jsonb))->>'ok';
select (public.sync_subir('PXT', 'cel-D', $j${"multas":[{"id":"c1","persona":"PXT-0003","motivo":"convenio","monto":100,"estado":"pendiente"}]}$j$::jsonb))->'rechazados';
do $$ declare b jsonb; begin
  assert (select count(*) from public.multas where asamblea_id='asm2' and motivo='tardanza') = 1, 'una tardanza';
  assert (select monto from public.multas where asamblea_id='asm2' and motivo='tardanza') = 7.5, 'monto del catálogo actualizado';
  assert (select motivo from public.multas where asamblea_id='asm2' and morador_id='PXT-0003') = 'inasistencia';
  assert (select estado || recibo from public.multas where id='c1') = 'pagadaR-0101', 'pago desde el celular';
  assert (select motivo || '/' || infraccion from public.multas where id='c2') = 'otro/cuota_agua', 'infracción propia';
  b := public.sync_bajar('PXT', null);
  assert jsonb_array_length(b->'infracciones') = 7, 'baja el catálogo';
  assert exists (select 1 from jsonb_array_elements(b->'multas') x where x->>'id'='c2' and x->>'motivo'='cuota_agua'), 'baja con código del catálogo';
  assert exists (select 1 from jsonb_array_elements(b->'assemblies') x where x->>'id'='asm2' and x->>'inicio'='08:00' and (x->>'tolerancia')::int=10), 'baja inicio y tolerancia';
end $$;
reset role;
\echo '   OK'

select 'bitácora: ' || count(*) || ' registros' from public.auditoria;
\echo 'TODAS LAS PRUEBAS PASARON'
