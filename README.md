# Identificador comunal integrado

Carné comunal de Paxtocá, Totonicapán. Sustituye el ticket de papel de las asambleas por un carné con código QR y foto. **Versión demo con datos inventados.**

| Ruta | Qué es |
|---|---|
| `/` | Página pública del proyecto |
| `/app/` | App del operador: padrón con foto, carnés para imprimir, escaneo de entrada y salida, reporte |
| `/mi-carne/` | Carné del morador en su celular, con QR que cambia cada 30 segundos |
| `fuente/` | Código fuente de la app (`python3 fuente/construir.py` regenera `app/` y `mi-carne/`) |

La app funciona sin internet y guarda los datos en el celular. Con una base Supabase configurada en Ajustes, sincroniza entre celulares.

Creado por Tecnoiagt · https://www.tecnoiagt.com
