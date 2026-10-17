"""
Preview sheet for SkillIcons (authoring aid, not shipped).

    lune run tools/icons/dump_icons > build/icons.json
    python tools/icons/render_icons.py build/icons.json build/icons.png [skills]

Draws every motif (or, with `skills`, every skill's icon on its element
background) the way UI/SkillIcon builds it from frames: rotated rounded
bars, dots, rings (stroke inside the outer diameter) and clipped half rings.
"""
import json, math, sys
from PIL import Image, ImageDraw, ImageFont

S = 4  # supersampling


def rgb(c):
    return tuple(int(v) for v in c)


def colours(element):
    main, dark = rgb(element["main"]), rgb(element["dark"])
    return {
        "a": (250, 248, 240),
        "m": main,
        "g": (255, 205, 90),
        "d": dark,
        "bg": tuple(int(d * 0.6 + m * 0.4) for d, m in zip(dark, main)),
    }


def draw_icon(shapes, element, size):
    big = size * S
    pal = colours(element)
    img = Image.new("RGBA", (big, big), pal["d"] + (255,))
    # background gradient dark (bottom) -> blend (top), like the UIGradient
    g = ImageDraw.Draw(img)
    for y in range(big):
        f = y / big
        c = tuple(int(pal["bg"][i] * (1 - f) + pal["d"][i] * f) for i in range(3))
        g.line([(0, y), (big, y)], fill=c + (255,))
    inner = big * 0.8
    off = big * 0.1
    k = inner / 100

    def layer(shape, colour, dx=0.0, dy=0.0):
        lay = Image.new("RGBA", (big, big), (0, 0, 0, 0))
        d = ImageDraw.Draw(lay)
        x, y = off + (shape["x"] + dx) * k, off + (shape["y"] + dy) * k
        kind = shape["kind"]
        if kind == "bar":
            w, h = shape["w"] * k, shape["h"] * k
            rad = min(w, h) * shape.get("round", 0) / 100
            tmp = Image.new("RGBA", (int(w) + 4, int(h) + 4), (0, 0, 0, 0))
            ImageDraw.Draw(tmp).rounded_rectangle([2, 2, 2 + w, 2 + h], radius=rad, fill=colour)
            tmp = tmp.rotate(-shape.get("r", 0), expand=True, resample=Image.BICUBIC)
            lay.alpha_composite(tmp, (int(x - tmp.width / 2), int(y - tmp.height / 2)))
        elif kind == "dot":
            r = shape["d"] * k / 2
            d.ellipse([x - r, y - r, x + r, y + r], fill=colour)
        elif kind in ("ring", "arc"):
            r = shape["d"] * k / 2
            t = shape["t"] * k
            d.ellipse([x - r, y - r, x + r, y + r], outline=colour, width=max(1, int(t)))
            if kind == "arc":
                mask = Image.new("L", (big, big), 0)
                m = ImageDraw.Draw(mask)
                side = shape["side"]
                box = {"Top": [x - r - 2, y - r - 2, x + r + 2, y], "Bottom": [x - r - 2, y, x + r + 2, y + r + 2],
                       "Left": [x - r - 2, y - r - 2, x, y + r + 2], "Right": [x, y - r - 2, x + r + 2, y + r + 2]}[side]
                m.rectangle(box, fill=255)
                # the icon frame clips everything too
                clipped = Image.new("RGBA", (big, big), (0, 0, 0, 0))
                clipped.paste(lay, (0, 0), mask)
                lay = clipped
        return lay

    for shape in shapes:  # drop shadow pass
        img.alpha_composite(layer(shape, (0, 0, 0, 90), 1.6, 2.4))
    for shape in shapes:
        img.alpha_composite(layer(shape, pal[shape["c"]] + (255,)))
    # rounded icon mask
    mask = Image.new("L", (big, big), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, big, big], radius=big * 0.18, fill=255)
    out = Image.new("RGBA", (big, big), (20, 20, 28, 255))
    out.paste(img, (0, 0), mask)
    return out.resize((size, size), Image.LANCZOS)


def main():
    data = json.load(open(sys.argv[1], encoding="utf-8"))
    out = sys.argv[2]
    mode = sys.argv[3] if len(sys.argv) > 3 else "motifs"
    size, pad, label = 96, 10, 16
    if mode == "skills":
        items = [(s["id"], s.get("icon"), s["element"]) for s in data["skills"]]
    else:
        items = [(name, name, "Steel") for name in sorted(data["motifs"])]
    cols = 12
    rows = (len(items) + cols - 1) // cols
    sheet = Image.new("RGB", (cols * (size + pad) + pad, rows * (size + pad + label) + pad), (14, 14, 20))
    draw = ImageDraw.Draw(sheet)
    font = ImageFont.load_default()
    for i, (name, icon, element) in enumerate(items):
        cx, cy = pad + (i % cols) * (size + pad), pad + (i // cols) * (size + pad + label)
        shapes = data["motifs"].get(icon or "", [])
        tile = draw_icon(shapes, data["elements"][element], size)
        sheet.paste(tile, (cx, cy))
        draw.text((cx, cy + size + 2), name[:16], fill=(200, 200, 210), font=font)
    sheet.save(out)
    print(f"wrote {out} ({len(items)} icons)")


if __name__ == "__main__":
    main()
