"""
Erzeugt server-icon.png (64x64 PNG) - ein kawaii Grasblock fuer den Minecraft-Server.
Wird mit 4x Supersampling gerendert und sauber heruntergerechnet.
"""
from PIL import Image, ImageDraw

S = 4                      # Supersampling
W = H = 64 * S

# --- Farbpalette (harmonisiert, weich & suess) ---
GRASS_LIGHT = (124, 205,  84)
GRASS       = (104, 184,  64)
GRASS_DARK  = ( 84, 156,  50)
GRASS_EDGE  = ( 70, 134,  42)
DIRT_LIGHT  = (150, 110,  76)
DIRT        = (126,  89,  62)
DIRT_DARK   = ( 99,  68,  47)
OUTLINE     = ( 56,  36,  24)
EYE         = ( 46,  28,  18)
WHITE       = (255, 255, 255)
BLUSH       = (247, 146, 162)
BLUSH_SOFT  = (252, 186, 196)
MOUTH       = ( 96,  60,  44)
SPARKLE     = (255, 252, 214)

img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
d = ImageDraw.Draw(img)


def sc(v):
    """Zahl in Super-Sampling-Einheiten umrechnen."""
    return v * S


def ellipse(x0, y0, x1, y1, fill, outline=None, width=0):
    d.ellipse([sc(x0), sc(y0), sc(x1), sc(y1)], fill=fill,
              outline=outline, width=int(width * S))


def rect(x0, y0, x1, y1, fill):
    d.rectangle([sc(x0), sc(y0), sc(x1), sc(y1)], fill=fill)


def rounded(x0, y0, x1, y1, r, fill):
    d.rounded_rectangle([sc(x0), sc(y0), sc(x1), sc(y1)], radius=sc(r), fill=fill)


# --- Block-Koerper (leicht abgerundet) ---
L, R, T, B = 3, 60, 5, 60
rounded(L, T, R, B, r=3, fill=OUTLINE)
rounded(L + 1, T + 1, R - 1, B - 1, r=3, fill=DIRT)

# --- Gras-Schicht oben ---
GRASS_BOTTOM = 25
d.rounded_rectangle([sc(L + 1), sc(T + 1), sc(R - 1), sc(GRASS_BOTTOM)],
                    radius=sc(3), fill=GRASS)
rect(L + 1, T + 6, R - 1, GRASS_BOTTOM, GRASS)

# Gras-Lichtkante ganz oben (Glanz)
rect(L + 1, T + 1, R - 1, T + 3, GRASS_LIGHT)
# dunkler Abschluss an der Unterkante
rect(L + 1, GRASS_BOTTOM - 2, R - 1, GRASS_BOTTOM, GRASS_DARK)

# --- Gras-Tropfen an der Unterkante (organischer Rand) ---
drips = [(9, 4), (16, 6), (23, 3), (30, 7), (37, 4), (44, 6), (51, 3)]
for x, h in drips:
    rect(x, GRASS_BOTTOM, x + 4, GRASS_BOTTOM + h, GRASS)
    ellipse(x - 0.5, GRASS_BOTTOM + h - 2.5, x + 4.5, GRASS_BOTTOM + h + 2.5, GRASS)
    rect(x, GRASS_BOTTOM, x + 4, GRASS_BOTTOM + 1, GRASS_DARK)

# --- Erdkuerner / Struktur ---
specks = [(10, 36), (18, 44), (26, 40), (35, 50), (43, 42), (52, 47),
          (14, 52), (30, 56), (47, 55), (38, 34), (8, 47), (55, 37),
          (22, 33), (45, 50), (33, 45), (17, 48)]
for x, y in specks:
    rect(x, y, x + 3, y + 3, DIRT_LIGHT)
for x, y in [(13, 39), (29, 36), (41, 46), (50, 41), (21, 50)]:
    rect(x, y, x + 3, y + 2, DIRT_DARK)

# --- Kawaii-Gesicht ---
EYE_TOP, EYE_BOT = 31, 43
for cx in (23, 41):
    ellipse(cx - 5, EYE_TOP, cx + 5, EYE_BOT, EYE)
    # grosse Lichtreflexe -> niedlich
    ellipse(cx - 3.5, EYE_TOP + 1.5, cx - 0.5, EYE_TOP + 5, WHITE)
    ellipse(cx + 1, EYE_BOT - 4.5, cx + 3.5, EYE_BOT - 2, WHITE)

# Wangenrot
for cx in (12, 52):
    ellipse(cx - 6, 44, cx + 6, 51, BLUSH_SOFT)
    ellipse(cx - 4, 45, cx + 4, 50, BLUSH)

# Mauls (kleines w / lachender Bogen)
d.arc([sc(26), sc(43), sc(38), sc(52)], start=15, end=165, fill=MOUTH, width=int(1.6 * S))
# Zaehnchen-Linie
rect(30, 46, 34, 47, WHITE)

# --- Glitzer auf dem Gras ---
for x, y, r in [(9, 11, 2.2), (54, 14, 1.8), (32, 9, 2.0)]:
    ellipse(x - r, y - r, x + r, y + r, SPARKLE)

img = img.resize((64, 64), Image.LANCZOS)
img.save(r"C:\minecraftai\server\server-icon.png", "PNG")
print("server-icon.png erstellt: 64x64,", img.size)
