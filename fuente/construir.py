# Arma app/index.html y mi-carne/index.html incrustando las librerías QR (funcionan sin internet)
from pathlib import Path
raiz = Path(__file__).resolve().parent
libs = (raiz / "qrcode.min.js").read_text() + "\n" + (raiz / "jsQR.min.js").read_text()
cabeza = ('<!doctype html><html lang="es"><head><meta charset="utf-8">'
          '<meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">'
          '<style>:root{padding-top:env(safe-area-inset-top,0px);padding-bottom:env(safe-area-inset-bottom,0px)}'
          'body{margin:0}img{max-width:100%}[hidden]{display:none!important}</style></head><body>')
for fuente, destino in [("app.html", "app"), ("mi-carne.html", "mi-carne")]:
    html = (raiz / fuente).read_text().replace("/*LIBS*/", libs)
    (raiz.parent / destino / "index.html").write_text(cabeza + html + "</body></html>")
    print("listo", destino)
