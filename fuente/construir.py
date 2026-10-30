# Arma app/ y mi-carne/ como aplicaciones web instalables: incrusta las librerías QR y el código común,
# y escribe el manifiesto y el service worker (funcionan sin internet después de la primera visita)
import json, time
from pathlib import Path
raiz = Path(__file__).resolve().parent
libs = (raiz / "qrcode.min.js").read_text() + "\n" + (raiz / "jsQR.min.js").read_text()
comun = (raiz / "comun.js").read_text()
version = time.strftime("%Y%m%d%H%M")

APPS = [
    ("app.html", "app", "Control Comunal Paxtocá", "Control", "Registro, carnés, asistencia y multas de la comunidad"),
    ("mi-carne.html", "mi-carne", "Mi Carné Comunal", "Mi carné", "Carné del morador con QR, asistencia y multas"),
]
SW = """const CACHE = "%s-%s";
const ARCHIVOS = ["./", "./manifest.webmanifest", "./icono-192.png", "./icono-512.png"];
self.addEventListener("install", e => { e.waitUntil(caches.open(CACHE).then(c => c.addAll(ARCHIVOS)).then(() => self.skipWaiting())); });
self.addEventListener("activate", e => { e.waitUntil(caches.keys().then(ks => Promise.all(ks.filter(k => k !== CACHE).map(k => caches.delete(k)))).then(() => self.clients.claim())); });
/* Primero la red (para recibir la versión nueva); sin señal, lo guardado */
self.addEventListener("fetch", e => {
  const u = new URL(e.request.url);
  if (e.request.method !== "GET" || u.origin !== location.origin) return;
  e.respondWith(fetch(e.request).then(r => { const copia = r.clone(); caches.open(CACHE).then(c => c.put(e.request, copia)); return r; })
    .catch(() => caches.match(e.request, { ignoreSearch: true }).then(r => r || caches.match("./"))));
});
"""
for fuente, carpeta, nombre, corto, descripcion in APPS:
    destino = raiz.parent / carpeta
    cabeza = ('<!doctype html><html lang="es"><head><meta charset="utf-8">'
              '<meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">'
              '<link rel="manifest" href="manifest.webmanifest"><link rel="icon" href="icono-192.png">'
              '<link rel="apple-touch-icon" href="icono-192.png"><meta name="mobile-web-app-capable" content="yes">'
              '<style>:root{padding-top:env(safe-area-inset-top,0px);padding-bottom:env(safe-area-inset-bottom,0px)}'
              'body{margin:0}img{max-width:100%}[hidden]{display:none!important}</style></head><body>')
    registro = ('<script>if ("serviceWorker" in navigator && location.protocol === "https:") '
                'navigator.serviceWorker.register("sw.js").catch(() => {});</script>')
    html = (raiz / fuente).read_text().replace("/*LIBS*/", libs).replace("/*COMUN*/", comun)
    (destino / "index.html").write_text(cabeza + html + registro + "</body></html>")
    (destino / "manifest.webmanifest").write_text(json.dumps({
        "name": nombre, "short_name": corto, "description": descripcion, "lang": "es",
        "start_url": "./", "scope": "./", "display": "standalone", "orientation": "portrait",
        "background_color": "#f2f3f8", "theme_color": "#2f3a8f",
        "icons": [{"src": f"icono-{n}.png", "sizes": f"{n}x{n}", "type": "image/png", "purpose": "any maskable"} for n in (192, 512)],
    }, ensure_ascii=False, indent=2))
    (destino / "sw.js").write_text(SW % (carpeta, version))
    print("listo", carpeta)
