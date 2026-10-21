"""Color math for the theme catalog: hex, OKLCH (Björn Ottosson's OKLab),
WCAG contrast, and the lightness nudge that makes a color readable on a
background without changing its hue (plan 15, phase A)."""
import math


def rgb(hex_color):
    return [int(hex_color[i:i + 2], 16) / 255 for i in (1, 3, 5)]


def hex_of(channels):
    return "#" + "".join(f"{round(min(max(c, 0), 1) * 255):02x}" for c in channels)


def mix(a, b, t):
    """a moved a fraction t toward b."""
    return hex_of([x + (y - x) * t for x, y in zip(rgb(a), rgb(b))])


def _linear(c):
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def _encode(c):
    return 12.92 * c if c <= 0.0031308 else 1.055 * c ** (1 / 2.4) - 0.055


def luminance(hex_color):
    r, g, b = [_linear(c) for c in rgb(hex_color)]
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def contrast(a, b):
    """WCAG 2 contrast ratio, 1 to 21."""
    la, lb = sorted([luminance(a), luminance(b)], reverse=True)
    return (la + 0.05) / (lb + 0.05)


def is_dark(hex_color):
    return luminance(hex_color) < 0.18


def to_oklch(hex_color):
    r, g, b = [_linear(c) for c in rgb(hex_color)]
    l_ = (0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b) ** (1 / 3)
    m_ = (0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b) ** (1 / 3)
    s_ = (0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b) ** (1 / 3)
    L = 0.2104542553 * l_ + 0.7936177850 * m_ - 0.0040720468 * s_
    a = 1.9779984951 * l_ - 2.4285922050 * m_ + 0.4505937099 * s_
    bb = 0.0259040371 * l_ + 0.7827717662 * m_ - 0.8086757660 * s_
    return L, math.hypot(a, bb), math.degrees(math.atan2(bb, a)) % 360


def from_oklch(L, C, H):
    """OKLCH -> hex; chroma is reduced until the color fits in sRGB."""
    for _ in range(40):
        a, b = C * math.cos(math.radians(H)), C * math.sin(math.radians(H))
        l_ = (L + 0.3963377774 * a + 0.2158037573 * b) ** 3
        m_ = (L - 0.1055613458 * a - 0.0638541728 * b) ** 3
        s_ = (L - 0.0894841775 * a - 1.2914855480 * b) ** 3
        lin = (4.0767416621 * l_ - 3.3077115913 * m_ + 0.2309699292 * s_,
               -1.2684380046 * l_ + 2.6097574011 * m_ - 0.3413193965 * s_,
               -0.0041960863 * l_ - 0.7034186147 * m_ + 1.7076147010 * s_)
        if all(-0.001 <= c <= 1.001 for c in lin) or C < 0.001:
            return hex_of([_encode(min(max(c, 0), 1)) for c in lin])
        C *= 0.9
    return hex_of([_encode(min(max(c, 0), 1)) for c in lin])


def oklch_text(text):
    """CSS "oklch(L C H)" -> hex."""
    L, C, H = [float(x) for x in text[6:-1].split("/")[0].split()[:3]]
    return from_oklch(L, C, H)


def readable(color, background, ratio):
    """`color`, its OKLCH lightness moved away from `background` in small
    steps until the contrast reaches `ratio`; None if it never does."""
    if contrast(color, background) >= ratio:
        return color
    L, C, H = to_oklch(color)
    step = 0.01 if is_dark(background) else -0.01
    while 0 <= L <= 1:
        L += step
        candidate = from_oklch(min(max(L, 0), 1), C, H)
        if contrast(candidate, background) >= ratio:
            return candidate
    return None
