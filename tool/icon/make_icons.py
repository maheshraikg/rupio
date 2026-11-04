"""Builds every Rupio icon from store/icon-source.png (white wallet with a
green tab on black, 1254 px square).

The source is separated into clean white and green layers (removing the
noise of the generated image), recentred, and drawn again at each size:

  store/icon-512.png            Google Play icon (full-bleed square)
  android .../mipmap-*/         legacy launcher icon, adaptive foreground,
                                background and monochrome (themed) layers
  android .../drawable-*/       white status-bar notification icon

Run from the rupeetrack folder:  python3 tool/icon/make_icons.py
"""
import pathlib

from PIL import Image, ImageDraw

ROOT = pathlib.Path(__file__).resolve().parents[2]
RES = ROOT / 'android/app/src/main/res'
SRC = ROOT / 'store/icon-source.png'
WHITE = (255, 255, 255)
GREEN = (54, 228, 122)
BG = (0, 0, 0)


def layers():
    """Alpha masks (L images) of the white parts and the green parts."""
    im = Image.open(SRC).convert('RGB')
    w, h = im.size
    aw = Image.new('L', (w, h))
    ag = Image.new('L', (w, h))
    src, pw, pg = im.load(), aw.load(), ag.load()
    for y in range(h):
        for x in range(w):
            r, g, _ = src[x, y]
            # pixel = a_w * WHITE + a_g * GREEN (+ black): solve with R and G.
            a_g = max(0.0, min(1.0, (g - r) / (GREEN[1] - GREEN[0])))
            a_w = max(0.0, min(1.0 - a_g, (r - GREEN[0] * a_g) / 255))
            if a_w < 0.03:
                a_w = 0.0
            pw[x, y] = int(a_w * 255 + 0.5)
            pg[x, y] = int(a_g * 255 + 0.5)
    return aw, ag


def glyph(aw, ag, mono=False):
    """The wallet as RGBA on transparent, cropped to its bounding box."""
    w, h = aw.size
    out = Image.new('RGBA', (w, h), (0, 0, 0, 0))
    white = Image.new('RGBA', (w, h), WHITE + (255,))
    green = Image.new('RGBA', (w, h), (WHITE if mono else GREEN) + (255,))
    out.paste(white, (0, 0), aw)
    out.paste(green, (0, 0), ag)
    # alpha = a_w + a_g
    a = Image.new('L', (w, h))
    pa, pw, pg = a.load(), aw.load(), ag.load()
    for y in range(h):
        for x in range(w):
            pa[x, y] = min(255, pw[x, y] + pg[x, y])
    out.putalpha(a)
    box = a.point(lambda v: 255 if v > 128 else 0).getbbox()
    return out.crop(box)


def place(g, size, width_frac, bg=None, radius=0.0):
    """g scaled to width_frac of a size x size canvas, centred."""
    canvas = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    if bg is not None:
        d = ImageDraw.Draw(canvas)
        if radius:
            d.rounded_rectangle((0, 0, size - 1, size - 1),
                                radius=int(size * radius), fill=bg + (255,))
        else:
            d.rectangle((0, 0, size, size), fill=bg + (255,))
    gw = max(1, round(size * width_frac))
    gh = max(1, round(g.height * gw / g.width))
    small = g.resize((gw, gh), Image.LANCZOS)
    canvas.alpha_composite(small, ((size - gw) // 2, (size - gh) // 2))
    return canvas


def main():
    aw, ag = layers()
    g = glyph(aw, ag)
    mono = glyph(aw, ag, mono=True)
    (ROOT / 'store').mkdir(exist_ok=True)
    place(g, 512, 0.60, bg=BG).convert('RGB').save(ROOT / 'store/icon-512.png')
    densities = {'mdpi': 1, 'hdpi': 1.5, 'xhdpi': 2, 'xxhdpi': 3, 'xxxhdpi': 4}
    for name, k in densities.items():
        mip = RES / f'mipmap-{name}'
        place(g, round(48 * k), 0.60, bg=BG, radius=0.22).save(mip / 'ic_launcher.png')
        # Adaptive layers are 108 dp; the wallet stays inside the 66 dp
        # safe circle.
        s = round(108 * k)
        place(g, s, 0.435).save(mip / 'ic_launcher_foreground.png')
        place(mono, s, 0.435).save(mip / 'ic_launcher_monochrome.png')
        Image.new('RGB', (s, s), BG).save(mip / 'ic_launcher_background.png')
        draw = RES / f'drawable-{name}'
        draw.mkdir(exist_ok=True)
        place(mono, round(24 * k), 0.84).save(draw / 'ic_stat_rupio.png')
    print('icons written')


if __name__ == '__main__':
    main()
