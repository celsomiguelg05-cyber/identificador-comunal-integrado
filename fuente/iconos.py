# Genera los íconos de las dos apps instalables (se corre una vez; los PNG quedan en app/ y mi-carne/)
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
raiz = Path(__file__).resolve().parent.parent
FUENTE = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"
IND, TER, BLANCO = (47, 58, 143), (181, 83, 47), (255, 255, 255)

def control(n):
    im = Image.new("RGB", (n, n), IND); d = ImageDraw.Draw(im)
    d.rectangle([0, int(n * .84), n, n], fill=TER)
    f = ImageFont.truetype(FUENTE, int(n * .30))
    d.text((n / 2, n * .45), "PXT", font=f, fill=BLANCO, anchor="mm")
    return im

def miembro(n):
    im = Image.new("RGB", (n, n), IND); d = ImageDraw.Draw(im)
    s = n * .5; x0 = (n - s) / 2; y0 = n * .2; c = s / 7
    d.rounded_rectangle([x0 - c, y0 - c, x0 + s + c, y0 + s + c], radius=c, fill=BLANCO)
    patron = ["1110111", "1010001", "1110101", "0001010", "1101111", "1000101", "1110111"]
    for r, fila in enumerate(patron):
        for k, v in enumerate(fila):
            if v == "1": d.rectangle([x0 + k * c, y0 + r * c, x0 + (k + 1) * c - 1, y0 + (r + 1) * c - 1], fill=IND)
    d.rectangle([0, int(n * .84), n, n], fill=TER)
    return im

for carpeta, dibujo in [("app", control), ("mi-carne", miembro)]:
    for n in (192, 512):
        dibujo(n).save(raiz / carpeta / f"icono-{n}.png")
print("íconos listos")
