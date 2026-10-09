#!/usr/bin/env python3
"""Generate the gallery's complete memories using only Python's standard library.

Tiles 0..15 hold four asymmetric 16x16 sprites (four consecutive tiles each).
ASCII 32..126 are 8x8 text tiles. Tiles 224..255 are backgrounds/borders.
Pixel zero is transparent; sprites use 1..15 so the same image fits any bank.
"""
import argparse
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
# Five columns by seven rows. Missing punctuation is rendered as a question mark.
FONT = {
    " ": ["00000"] * 7,
    "A": ["01110","10001","10001","11111","10001","10001","10001"],
    "B": ["11110","10001","10001","11110","10001","10001","11110"],
    "C": ["01111","10000","10000","10000","10000","10000","01111"],
    "D": ["11110","10001","10001","10001","10001","10001","11110"],
    "E": ["11111","10000","10000","11110","10000","10000","11111"],
    "F": ["11111","10000","10000","11110","10000","10000","10000"],
    "G": ["01111","10000","10000","10111","10001","10001","01111"],
    "H": ["10001","10001","10001","11111","10001","10001","10001"],
    "I": ["11111","00100","00100","00100","00100","00100","11111"],
    "J": ["00111","00010","00010","00010","10010","10010","01100"],
    "K": ["10001","10010","10100","11000","10100","10010","10001"],
    "L": ["10000","10000","10000","10000","10000","10000","11111"],
    "M": ["10001","11011","10101","10101","10001","10001","10001"],
    "N": ["10001","11001","10101","10011","10001","10001","10001"],
    "O": ["01110","10001","10001","10001","10001","10001","01110"],
    "P": ["11110","10001","10001","11110","10000","10000","10000"],
    "Q": ["01110","10001","10001","10001","10101","10010","01101"],
    "R": ["11110","10001","10001","11110","10100","10010","10001"],
    "S": ["01111","10000","10000","01110","00001","00001","11110"],
    "T": ["11111","00100","00100","00100","00100","00100","00100"],
    "U": ["10001","10001","10001","10001","10001","10001","01110"],
    "V": ["10001","10001","10001","10001","10001","01010","00100"],
    "W": ["10001","10001","10001","10101","10101","10101","01010"],
    "X": ["10001","10001","01010","00100","01010","10001","10001"],
    "Y": ["10001","10001","01010","00100","00100","00100","00100"],
    "Z": ["11111","00001","00010","00100","01000","10000","11111"],
    "0": ["01110","10001","10011","10101","11001","10001","01110"],
    "1": ["00100","01100","00100","00100","00100","00100","01110"],
    "2": ["01110","10001","00001","00010","00100","01000","11111"],
    "3": ["11110","00001","00001","01110","00001","00001","11110"],
    "4": ["00010","00110","01010","10010","11111","00010","00010"],
    "5": ["11111","10000","10000","11110","00001","00001","11110"],
    "6": ["01110","10000","10000","11110","10001","10001","01110"],
    "7": ["11111","00001","00010","00100","01000","01000","01000"],
    "8": ["01110","10001","10001","01110","10001","10001","01110"],
    "9": ["01110","10001","10001","01111","00001","00001","01110"],
    "-": ["00000","00000","00000","11111","00000","00000","00000"],
    "/": ["00001","00010","00010","00100","01000","01000","10000"],
    ":": ["00000","00100","00100","00000","00100","00100","00000"],
    "=": ["00000","00000","11111","00000","11111","00000","00000"],
    "+": ["00000","00100","00100","11111","00100","00100","00000"],
    ".": ["00000","00000","00000","00000","00000","00100","00100"],
    ">": ["10000","01000","00100","00010","00100","01000","10000"],
    "?": ["01110","10001","00001","00010","00100","00000","00100"],
}


def rgb565(rgb):
    r, g, b = rgb
    return ((r >> 3) << 11) | ((g >> 2) << 5) | (b >> 3)


def palette_words():
    bank_colors = [(248,208,32),(248,64,56),(48,224,96),(64,128,248),
                   (248,224,64),(48,224,224),(208,80,248),(248,144,48),
                   (240,240,240),(128,224,64),(248,96,160),(96,160,224),
                   (184,128,64),(128,160,208),(80,96,112),(240,176,216)]
    colors = []
    for bank, color in enumerate(bank_colors):
        for shade in range(16):
            if shade == 0:
                colors.append(0)
            else:
                # The shape carries dark and bright details in every bank.
                scale = 0.35 + 0.65 * ((shade - 1) / 14)
                colors.append(rgb565(tuple(int(c * scale) for c in color)))
    # Bank zero in direct mode deliberately distinguishes the four sprite images.
    for index, rgb in {1:(248,208,32),2:(40,224,232),3:(248,64,56),4:(248,248,248),
                       5:(248,144,32),6:(40,224,96),7:(64,112,248),8:(208,64,240)}.items():
        colors[index] = rgb565(rgb)
    # Reserve E0..EF for the tile font and background, F1..F5 for polygons.
    special = {0xE0:(8,16,32),0xE1:(32,48,64),0xE2:(56,72,88),
               0xE3:(64,96,136),0xE4:(104,80,144),0xE5:(40,120,96),
               0xE6:(144,104,40),0xEF:(248,248,248),0xF0:(0,0,0),
               0xF1:(248,80,64),0xF2:(64,200,248),0xF3:(80,224,128),
               0xF4:(248,184,56),0xF5:(208,96,240),0xFD:(64,104,144),
               0xFE:(136,104,64),0xFF:(248,248,248)}
    for index, rgb in special.items():
        colors[index] = rgb565(rgb)
    return colors


def sprite_pixel(image, x, y):
    # Four different silhouettes; all have an unmistakable top-left landmark and holes.
    if image == 0:  # Arrow pointing right, stem above the centre: asymmetric in X and Y.
        inside = (2 <= x <= 10 and 4 <= y <= 8) or (8 <= x <= 14 and abs(y-7) <= 14-x)
    elif image == 1:  # L-shaped frame with transparent centre.
        inside = (2 <= x <= 5 and 2 <= y <= 13) or (2 <= x <= 13 and 10 <= y <= 13)
    elif image == 2:  # Ring, with an off-centre square eye.
        d = (x-7)**2 + (y-7)**2
        inside = 16 <= d <= 48 or (4 <= x <= 5 and 4 <= y <= 5)
    else:  # Uneven striped kite, with an aperture near its lower tip.
        inside = abs(x-6) + abs(y-7) <= 7 and not (5 <= x <= 7 and 9 <= y <= 11)
    if not inside:
        return 0
    if x <= 4 and y <= 5:
        return 4
    return (1,6,7,8)[image] if (x+y) % 5 else 2


def generate(check=False):
    patterns = [0] * 16384
    for image in range(4):
        for y in range(16):
            for x in range(16):
                tile = image * 4 + (y // 8) * 2 + x // 8
                patterns[tile*64 + (y % 8)*8 + x % 8] = sprite_pixel(image, x, y)
    for code in range(32, 127):
        glyph = FONT.get(chr(code).upper(), FONT["?"])
        for y in range(8):
            for x in range(8):
                ink = y < 7 and 1 <= x <= 5 and glyph[y][x-1] == "1"
                patterns[code*64+y*8+x] = 0xEF if ink else 0xE0
    for tile in range(224, 256):
        for y in range(8):
            for x in range(8):
                if tile == 224:
                    value = 0xE0
                elif tile == 225:
                    value = 0xE2 if x == 0 or y == 0 else 0xE1
                elif tile == 226:
                    value = 0xEF if x in (0, 7) or y in (0, 7) else 0xE2
                else:
                    value = 0xE3 + ((tile-227) % 4) if (x+y) % 4 else 0xE0
                patterns[tile*64+y*8+x] = value
    palette = palette_words()
    rgb888 = [((value >> 11) << 19) | (((value >> 5) & 63) << 10) | ((value & 31) << 3)
              for value in palette]
    tilemap = [224] * 1200
    for y in range(30):
        for x in range(40):
            if x in (0, 39) or y in (0, 29):
                tilemap[y*40+x] = 226
    for x, char in enumerate("PBL2 - GALERIA DE RECURSOS", 3):
        tilemap[40+x] = ord(char)
    out = ROOT / "assets"
    out.mkdir(exist_ok=True)
    for name, data, width in (("tiles", patterns, 2),("palette", rgb888, 6),("tilemap", tilemap, 2)):
        path = out / f"showcase_{name}.hex"
        contents = "".join(f"{value:0{width}X}\n" for value in data)
        if check:
            if not path.exists() or path.read_text(encoding="ascii") != contents:
                raise SystemExit(f"Outdated asset: {path.relative_to(ROOT)}; run this script without --check")
        else:
            path.write_text(contents, encoding="ascii")
        print(f"{path.relative_to(ROOT)}: {len(data)} words")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="Check committed assets without modifying files")
    generate(parser.parse_args().check)
