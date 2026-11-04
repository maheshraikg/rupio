"""Store and onboarding graphics, drawn from the raw app screenshots in
store/screenshots/raw/ and the logo:

  store/feature-graphic.png          Google Play feature graphic, 1024 x 500
  store/screenshots/phone/*.png      Play screenshots, 1080 x 1920, each a
                                     headline above the app in a phone frame
  assets/onboarding/*.webp           phone images for the first-run tour

Run from the rupeetrack folder:  python3 tool/store/make_store_graphics.py
"""
import pathlib

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = pathlib.Path(__file__).resolve().parents[2]
FONTS = ROOT / 'assets/fonts'
RAW = ROOT / 'store/screenshots/raw'
GREEN = (54, 228, 122)
WHITE = (255, 255, 255)
GREY = (158, 158, 166)


def font(name, size):
    return ImageFont.truetype(str(FONTS / f'Inter-{name}.otf'), size)


def background(w, h, glow_box):
    bg = Image.new('RGB', (w, h), (6, 6, 7))
    glow = Image.new('L', (w, h), 0)
    ImageDraw.Draw(glow).ellipse(glow_box, fill=90)
    glow = glow.filter(ImageFilter.GaussianBlur(max(w, h) // 9))
    bg.paste(Image.new('RGB', (w, h), (20, 70, 42)), (0, 0), glow)
    return bg.convert('RGBA')


def phone(shot, width):
    """A screenshot in a dark phone frame with a status bar and camera."""
    s = Image.open(shot).convert('RGBA')
    bezel = max(6, width // 26)
    sw = width - 2 * bezel
    sh = round(s.height * sw / s.width)
    s = s.resize((sw, sh), Image.LANCZOS)
    bar = round(sw * 0.075)
    screen = Image.new('RGBA', (sw, sh + bar), (0, 0, 0, 255))
    screen.paste(s, (0, bar))
    d = ImageDraw.Draw(screen)
    fs = max(8, round(bar * 0.42))
    d.text((round(sw * 0.07), round(bar * 0.28)), '9:41', font=font('SemiBold', fs), fill=WHITE)
    # wifi-like dots and a battery on the right
    bx, by, bw, bh = sw - round(sw * 0.14), round(bar * 0.36), round(sw * 0.065), round(bar * 0.3)
    d.rounded_rectangle((bx, by, bx + bw, by + bh), radius=max(1, bh // 4), outline=WHITE, width=max(1, fs // 9))
    d.rectangle((bx + 2, by + 2, bx + round(bw * 0.7), by + bh - 2), fill=WHITE)
    for i in range(3):
        x = bx - round(sw * 0.045) * (i + 1)
        r = max(1, round(bh * 0.18))
        d.ellipse((x - r, by + bh // 2 - r, x + r, by + bh // 2 + r), fill=WHITE)
    h = sh + bar + 2 * bezel
    r = width // 7
    frame = Image.new('RGBA', (width, h), (0, 0, 0, 0))
    fd = ImageDraw.Draw(frame)
    fd.rounded_rectangle((0, 0, width - 1, h - 1), radius=r, fill=(28, 28, 31, 255),
                         outline=(62, 62, 68, 255), width=max(2, width // 160))
    mask = Image.new('L', screen.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, sw - 1, sh + bar - 1), radius=r - bezel, fill=255)
    frame.paste(screen, (bezel, bezel), mask)
    cam = max(3, round(bar * 0.17))
    cx, cy = width // 2, bezel + bar // 2
    fd.ellipse((cx - cam, cy - cam, cx + cam, cy + cam), fill=(18, 18, 20, 255))
    return frame


def drop_shadow(img, blur, alpha=150):
    a = img.split()[3].point(lambda v: alpha if v else 0)
    sh = Image.new('RGBA', img.size, (0, 0, 0, 0))
    sh.putalpha(a)
    pad = blur * 3
    canvas = Image.new('RGBA', (img.width + 2 * pad, img.height + 2 * pad), (0, 0, 0, 0))
    canvas.alpha_composite(sh, (pad, pad))
    return canvas.filter(ImageFilter.GaussianBlur(blur)), pad


def place(base, img, x, y, angle=0, blur=18):
    if angle:
        img = img.rotate(angle, resample=Image.BICUBIC, expand=True)
    sh, pad = drop_shadow(img, blur)
    base.alpha_composite(sh, (x - pad + blur // 3, y - pad + blur * 3 // 4))
    base.alpha_composite(img, (x, y))


def feature_graphic():
    w, h = 1024, 500
    im = background(w, h, (560, 20, 1080, 560))
    place(im, phone(RAW / '5-loans.png', 200), 790, 78, -7)
    place(im, phone(RAW / '1-home.png', 232), 618, 40, 4)
    d = ImageDraw.Draw(im)
    icon = Image.open(ROOT / 'store/icon-512.png').convert('RGBA').resize((64, 64), Image.LANCZOS)
    m = Image.new('L', (64, 64), 0)
    ImageDraw.Draw(m).rounded_rectangle((0, 0, 63, 63), radius=15, fill=255)
    im.paste(icon, (64, 78), m)
    d.text((144, 86), 'Rupio', font=font('Bold', 38), fill=WHITE)
    big = font('ExtraBold', 56)
    d.text((62, 178), 'Know where every', font=big, fill=WHITE)
    d.text((62, 244), 'rupee goes.', font=big, fill=GREEN)
    d.text((64, 336), 'Expenses · Card bills · EMIs · Savings', font=font('Medium', 23), fill=GREY)
    chip = font('SemiBold', 17)
    x = 64
    for label in ['Private & offline', '6 Indian languages', 'Made for India']:
        tw = d.textlength(label, font=chip)
        d.rounded_rectangle((x, 384, x + tw + 28, 418), radius=17, fill=(24, 24, 27), outline=(48, 48, 54))
        d.text((x + 14, 391), label, font=chip, fill=(220, 220, 226))
        x += tw + 40
    im.convert('RGB').save(ROOT / 'store/feature-graphic.png')


# Play screenshots: (raw file, headline, highlighted part). Kept short:
# one headline and the top of one screen, large enough to read.
SHOTS = [
    ('1-home', 'Know where every ', 'rupee goes'),
    ('2-year', 'Your year ', 'at a glance'),
    ('4-insights', 'See where your ', 'income goes'),
    ('5-loans', 'Every EMI, ', 'tracked'),
    ('6-goals', 'Reach every ', 'savings goal'),
    ('7-cards', 'Never miss a ', 'card bill'),
]


def wrap_headline(d, lead, accent, fnt, max_w):
    """Two lines at most: lead words, then the green accent words."""
    lead_words = [(w, WHITE) for w in lead.split()]
    accent_words = [(w, GREEN) for w in accent.split()]
    words = lead_words + accent_words
    if d.textlength(' '.join(x for x, _ in words), font=fnt) <= max_w:
        return [words]
    if (d.textlength(lead.strip(), font=fnt) <= max_w
            and d.textlength(accent.strip(), font=fnt) <= max_w):
        return [lead_words, accent_words]
    lines, cur = [], []
    for word in words:
        trial = ' '.join(x for x, _ in cur + [word])
        if cur and d.textlength(trial, font=fnt) > max_w:
            lines.append(cur)
            cur = [word]
        else:
            cur.append(word)
    lines.append(cur)
    return lines


def store_screenshot(name, lead, accent):
    w, h = 1080, 1920
    im = background(w, h, (-200, 900, 1280, 2300))
    d = ImageDraw.Draw(im)
    big = font('ExtraBold', 92)
    lines = wrap_headline(d, lead, accent, big, w - 140)
    y = 170
    for line in lines:
        text = ' '.join(x for x, _ in line)
        x = (w - d.textlength(text, font=big)) / 2
        for word, color in line:
            d.text((x, y), word, font=big, fill=color)
            x += d.textlength(word + ' ', font=big)
        y += 112
    # A large phone that runs off the bottom edge: only the top of the
    # screen shows, big enough to read.
    ph = phone(RAW / f'{name}.png', 900)
    place(im, ph, (w - ph.width) // 2, y + 90, blur=34)
    return im.convert('RGB')


def main():
    feature_graphic()
    out = ROOT / 'store/screenshots/phone'
    out.mkdir(parents=True, exist_ok=True)
    for old in out.glob('*.png'):
        old.unlink()
    for i, (name, lead, accent) in enumerate(SHOTS, 1):
        store_screenshot(name, lead, accent).save(out / f'{i}-{name.split("-", 1)[1]}.png')
    onb = ROOT / 'assets/onboarding'
    onb.mkdir(parents=True, exist_ok=True)
    for name in ['1-home', '4-insights', '5-loans', '7-cards']:
        phone(RAW / f'{name}.png', 560).save(onb / f'{name}.webp', 'WEBP', quality=86, method=6)
    print('store graphics written')


if __name__ == '__main__':
    main()
