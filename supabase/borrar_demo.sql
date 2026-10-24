-- Borra los datos ficticios de la demo (ids PXT-0001..0080 y los que empiezan con 'demo-').
-- Correr como dueño de la base. Los marcajes no se pueden borrar normalmente; aquí se
-- desactiva ese bloqueo solo durante este script.
begin;
alter table public.marcajes disable trigger t_inmutable;
delete from public.tramites   where morador_id in (select id from public.moradores where id between 'PXT-0001' and 'PXT-0080');
delete from public.multas     where asamblea_id like 'demo-%' or morador_id between 'PXT-0001' and 'PXT-0080';
delete from public.incidentes where id like 'demo-%' or id like 'srv-doble-demo-%' or asamblea_id like 'demo-%'
                              or morador_id between 'PXT-0001' and 'PXT-0080';
delete from public.marcajes   where id like 'demo-%' or asamblea_id like 'demo-%' or morador_id between 'PXT-0001' and 'PXT-0080';
delete from public.asambleas  where id like 'demo-%';
delete from public.carnes     where morador_id between 'PXT-0001' and 'PXT-0080';
delete from public.moradores  where id between 'PXT-0001' and 'PXT-0080';
alter table public.marcajes enable trigger t_inmutable;
commit;
