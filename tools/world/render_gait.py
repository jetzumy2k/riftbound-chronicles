"""
Side-view strip of the gait snapshots written by tools/world/check_gait.luau
(authoring aid, not shipped):

    lune run tools/world/check_gait RiftWolf 16 build/gait/wolf.json
    python tools/world/render_gait.py build/gait/wolf.json build/gait/wolf.png

Parts are drawn as projected, depth-sorted hulls in their colours, with the
ground line, so planted feet, knee bends and body motion are easy to read.
"""
import json, os, sys
import numpy as np
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import Polygon

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from render_capitals import corners, hull  # noqa: E402


def main():
    data = json.load(open(sys.argv[1]))["Gait"]
    parts = [p for p in data["parts"] if p["t"] < 0.95]
    items = []
    lo_z, hi_z, hi_y = 1e9, -1e9, 0
    for p in parts:
        v = corners(p)
        lo_z, hi_z = min(lo_z, v[:, 2].min()), max(hi_z, v[:, 2].max())
        hi_y = max(hi_y, v[:, 1].max())
        # Viewed from +X: nearer parts (larger X) drawn last.
        items.append((v[:, 0].mean(), v, p))
    items.sort(key=lambda it: it[0])
    width = hi_z - lo_z
    fig, ax = plt.subplots(figsize=(min(40, 4 + width * 0.9), 4 + hi_y * 0.5))
    for _, v, p in items:
        h = hull(np.stack([v[:, 2], v[:, 1]], 1))
        if len(h) < 3:
            continue
        ax.add_patch(Polygon(h, closed=True, facecolor=p["col"], edgecolor=(0, 0, 0, 0.3), lw=0.3))
    ax.axhline(0, color="#7a6a50", lw=2)
    ax.set_xlim(lo_z - 1, hi_z + 1)
    ax.set_ylim(-0.5, hi_y + 1)
    ax.set_aspect("equal")
    ax.set_facecolor("#20242c")
    ax.invert_xaxis()  # forward (-Z) to the left
    fig.tight_layout()
    fig.savefig(sys.argv[2], dpi=60)


if __name__ == "__main__":
    main()
