# Identificador comunal integrado

Carné comunal de Paxtocá, Totonicapán. Sustituye el ticket de papel de las asambleas por un carné con código QR y foto, y lleva las multas de la comunidad. **Versión demo con datos inventados.**

| Ruta | Qué es |
|---|---|
| `/` | Página pública del proyecto |
| `/app/` | **Control Comunal** (directiva y operadores): padrón con foto, carnés para imprimir, escaneo de entrada y salida, reporte, multas (infracciones y montos, asignar, cobrar con recibo, condonar, anular, solvencia) |
| `/mi-carne/` | **Mi Carné** (miembro): carné con QR que cambia cada 30 segundos, su asistencia y sus multas |
| `fuente/` | Código fuente (`python3 fuente/construir.py` regenera `app/` y `mi-carne/`) |

Las dos se instalan en Android desde Chrome (menú ⋮ → «Instalar app» o «Agregar a pantalla principal») y funcionan sin internet después de abrirlas una vez.

Creado por Tecnoiagt · https://www.tecnoiagt.com
