# Identificador comunal integrado

Carné comunal de Paxtocá, Totonicapán. Sustituye el ticket de papel de las asambleas por un carné con código QR y foto, y lleva las multas de la comunidad. **Versión demo con datos inventados.**

| Ruta | Qué es |
|---|---|
| `/` | Página pública del proyecto |
| `/app/` | **Control Comunal** (directiva y operadores): padrón con foto, carnés para imprimir, escaneo de entrada y salida, reporte, multas (infracciones y montos, asignar, cobrar con recibo, condonar, anular, solvencia) |
| `/mi-carne/` | **Mi Carné** (miembro): carné con QR que cambia cada 30 segundos, su asistencia y sus multas |
| `fuente/` | Código fuente (`python3 fuente/construir.py` regenera `app/` y `mi-carne/`) |

**Dónde se usa cada una**

- **Control Comunal va en una laptop.** Abra `/app/` en Chrome o Edge y toque el ícono de instalar en la barra de direcciones (o menú ⋮ → «Instalar Control Comunal»). La cámara de la laptop escanea los carnés. En un celular también funciona, pero solo para emergencias.
- **Mi Carné va en el celular del vecino.** Abra `/mi-carne/` en Chrome para Android y elija menú ⋮ → «Instalar app» (o «Agregar a pantalla principal»).

Las dos funcionan sin internet después de abrirlas una vez.

**Sonidos.** Las dos apps suenan con tonos suaves de marimba (hechos en el momento, sin archivos de audio): carné válido, entrada o salida registrada, avisos, carné falso, multa cobrada, abrir y cerrar la asamblea. El botón de la bocina los apaga; en Control también está en Ajustes › Sonidos, con un botón para escucharlos.

Creado por Tecnoiagt · https://www.tecnoiagt.com
