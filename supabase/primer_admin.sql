-- Correr UNA vez en el editor SQL de Supabase, después de crear el usuario
-- en Authentication > Users (Add user, marcar "Auto Confirm User").
-- Cambiar el correo y el nombre.
insert into public.operadores (user_id, comunidad_id, nombre, rol)
select id, 'PXT', 'Administrador Paxtocá', 'admin'
  from auth.users where email = 'admin@ejemplo.com';
