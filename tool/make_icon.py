"""Draws the Ghee launcher icon: a route line shaped like a "G" that
pulls in at a stop. Run from the repo root, then
`dart run flutter_launcher_icons`."""
import math
from PIL import Image, ImageDraw

S = 4  # supersampling
N = 1024 * S
TOP, BOTTOM = (200, 245, 70), (150, 215, 30)
LINE, STOP = (18, 66, 44, 255), (255, 255, 255, 255)


def background():
    img = Image.new('RGBA', (N, N))
    d = ImageDraw.Draw(img)
    for y in range(N):
        t = y / (N - 1)
        d.line(
            [(0, y), (N, y)],
            fill=tuple(round(a + (b - a) * t) for a, b in zip(TOP, BOTTOM)) + (255,),
        )
    return img


def mark(scale):
    img = Image.new('RGBA', (N, N), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    c = N / 2
    r, w = 270 * S * scale, 116 * S * scale
    box = [c - r - w / 2, c - r - w / 2, c + r + w / 2, c + r + w / 2]
    end = 312
    d.arc(box, 0, end, fill=LINE, width=round(w))
    a = math.radians(end)
    for x, y in [(c + r * math.cos(a), c + r * math.sin(a)), (c + r, c)]:
        d.ellipse([x - w / 2, y - w / 2, x + w / 2, y + w / 2], fill=LINE)
    stop = c + 10 * S * scale
    d.rectangle([stop, c - w / 2, c + r, c + w / 2], fill=LINE)
    for rad, fill in [(96 * S * scale, LINE), (52 * S * scale, STOP)]:
        d.ellipse([stop - rad, c - rad, stop + rad, c + rad], fill=fill)
    return img


def save(img, path):
    img.resize((1024, 1024), Image.LANCZOS).save(path, optimize=True)


save(Image.alpha_composite(background(), mark(1.0)), 'assets/icon/icon.png')
save(mark(0.62), 'assets/icon/icon_foreground.png')
