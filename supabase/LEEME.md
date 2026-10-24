# Padrón comunal (base de datos) — Carné comunal de Paxtocá

Base central en Supabase que recibe lo que registran los celulares de la app del
carné (que funcionan sin internet) y lo junta en un solo padrón.

## Qué guarda

| Tabla | Para qué |
|---|---|
| `comunidades` | Paxtocá (`PXT`) y otras comunidades del municipio. Llave pública de los carnés. |
| `comunidad_secretos` | Secreto del QR rotativo del celular. Solo admin, directiva y operador. |
| `operadores` | Quién entra a la app o al panel y con qué rol. |
| `dispositivos` | Celulares que han sincronizado. |
| `moradores` | El censo: nombre, nacimiento, sector, hogar, oficio, teléfono, foto, carné vigente, activo o baja. |
| `carnes` | Historial de carnés: vigente o anulado (reposición o baja). Solo uno vigente por persona. |
| `asambleas` | Asambleas, **faenas** y reuniones (columna `tipo`). Usan el mismo control de entrada y salida. |
| `marcajes` | Cada entrada y salida. Nunca se borran ni se editan. |
| `incidentes` | Carné anulado, firma falsa, doble marcaje, captura de pantalla, etc. La directiva los marca revisados. |
| `multas` | Inasistencia, sin salida, faena u otra. Pendiente, pagada (con recibo), condonada o anulada. |
| `tramites` | Constancias, solvencias, cartas aval, con folio correlativo y si estaba solvente al pedirlo. |
| `auditoria` | Bitácora de cambios (solo admin). |

Vistas: `v_asistencia` (cada persona en cada asamblea: completo, sin salida, sin entrada, ausente),
`v_resumen_asamblea` y `v_solvencia`.

## Roles

| Rol | Puede |
|---|---|
| `admin` | Todo en su comunidad: operadores, llaves, bitácora. |
| `directiva` | Editar moradores, abrir y cerrar asambleas, generar y cobrar multas, resolver trámites, revisar incidentes. |
| `operador` | Registrar moradores, escanear, sincronizar, pedir trámites. |
| `consulta` | Solo ver. |

Cada operador pertenece a una sola comunidad y no ve nada de otras.

## Antitrampa en el servidor

- **Doble marcaje entre celulares:** si dos celulares sin señal marcan a la misma persona, vale el
  marcaje más temprano; los demás quedan inválidos y se crea un incidente `doble`.
- **Carnés:** un solo carné vigente por persona. Un celular atrasado no puede revivir un carné viejo.
- **Asambleas:** cerrar desde un celular es definitivo; reabrir solo desde el panel.
- **Marcajes:** no se pueden borrar ni cambiar, ni siquiera con acceso total.

## Sincronización (contrato con la app)

```js
// Subir: los objetos tal como están en IndexedDB (horas en milisegundos)
const { data } = await supabase.rpc('sync_subir', {
  p_comunidad: 'PXT', p_dispositivo: idDelCelular,
  p_lote: { people, assemblies, marks, incidents }
});
// data = { ok, recibidos, rechazados: [{tabla, id, motivo}], dobles: [ids de marks invalidados] }

// Bajar: lo que subieron los otros celulares desde el último cursor
const { data: c } = await supabase.rpc('sync_bajar', { p_comunidad: 'PXT', p_desde: cursor });
// c = { people, assemblies, marks, incidents, cursor }  (guardar c.cursor)

// Foto: aparte, a Storage (bucket privado)
await supabase.storage.from('fotos').upload(`PXT/${id}.jpg`, blobJpeg, { upsert: true });
```

Reintentar el mismo lote no duplica nada. La foto en `people.foto` se ignora.
Recomendado: de vez en cuando bajar todo con `p_desde: null`.

## Verificación pública (página web, sin sesión)

`rpc('verificar_carne', { p_qr })` devuelve si el carné está vigente, sin nombres.
Para `CC2` (QR rotativo) el servidor verifica el código. Para `CC1` (impreso) devuelve
`llave_publica` y el navegador verifica la firma ECDSA.

## Instalar en Supabase

1. Aplicar `migrations/20261024000001_padron_comunal.sql`.
2. En Authentication > Providers, desactivar el registro abierto ("Allow new users to sign up").
3. Crear el primer usuario en Authentication > Users y correr `primer_admin.sql`.
4. (Solo demo) Correr `seed_demo.sql`.
5. El admin guarda la llave pública (JWK) en `comunidades.llave_publica` y el secreto del QR
   rotativo en `comunidad_secretos` desde la app. La llave privada de firma **no** se sube.

## Pruebas

`pruebas/correr.sh` (requiere PostgreSQL y Node) crea una base local, aplica la migración y prueba: sincronización
idempotente, doble marcaje, reposición, aislamiento entre comunidades, roles, multas,
solvencia, folios, fotos y verificación del QR rotativo (calculado igual que la app).

## Datos de demostración

`seed_demo.sql` llena la base con datos **inventados**: 80 moradores de Paxtocá
(`PXT-0001` a `PXT-0080`, sin fotos, 2 dados de baja, algunos con carné repuesto), 8 eventos
de junio a octubre de 2026 (asambleas mensuales, 2 faenas y una reunión), 949 marcajes de dos
celulares, 18 incidentes, multas (pagadas con recibo, pendientes y una condonada) y 10 trámites.
`borrar_demo.sql` los quita todos antes de empezar con datos reales.
