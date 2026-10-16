"""
Renders the capitals dumped by tools/world/dump_capitals.luau
(authoring aid, not shipped):

    lune run tools/world/dump_capitals > build/capitals.json
    python tools/world/render_capitals.py build/capitals.json build/capitals

For each capital: a top view and two elevations (looking along the city's
forward axis and from the side), parts drawn as filled projected boxes,
painter-sorted by depth, in their real colours.
"""
import json, os, sys
import numpy as np
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import Polygon

CORNERS = np.array([[sx, sy, sz] for sx in (-.5, .5) for sy in (-.5, .5) for sz in (-.5, .5)])


def hull(points):
    pts = sorted(set(map(tuple, np.round(points, 4))))
    if len(pts) < 3:
        return np.array(pts)
    def cross(o, a, b):
        return (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0])
    lower, upper = [], []
    for p in pts:
        while len(lower) >= 2 and cross(lower[-2], lower[-1], p) <= 0:
            lower.pop()
        lower.append(p)
    for p in reversed(pts):
        while len(upper) >= 2 and cross(upper[-2], upper[-1], p) <= 0:
            upper.pop()
        upper.append(p)
    return np.array(lower[:-1] + upper[:-1])


# Points on a unit sphere (radius 0.5) for drawing ellipsoids.
_u = np.linspace(0, np.pi, 9)
_v = np.linspace(0, 2 * np.pi, 16)
SPHERE = 0.5 * np.array([[np.sin(a) * np.cos(b), np.cos(a), np.sin(a) * np.sin(b)] for a in _u for b in _v])


def corners(p):
    if p["shape"] == "Ellipsoid":
        R = np.array([p["x"], p["y"], p["z"]]).T
        return np.array(p["c"]) + (SPHERE * np.array(p["s"])) @ R.T
    R = np.array([p["x"], p["y"], p["z"]]).T
    s = np.array(p["s"])
    if p["shape"] == "Cylinder":
        pass
    return np.array(p["c"]) + (CORNERS * s) @ R.T


def render(name, data, out):
    parts = data["parts"]
    cx, cy, cz = data["center"]
    if "half" in data:
        h = data["half"]
        views = [
            ("top", lambda v: (v[:, 0], v[:, 2]), lambda v: v[:, 1].max(), (cx, cz), h),
            ("elevation (from the side)", lambda v: (v[:, 2], v[:, 1]), lambda v: -v[:, 0].mean(), (cz, cy + h * 0.3), h),
            ("elevation (from the front)", lambda v: (v[:, 0], v[:, 1]), lambda v: v[:, 2].mean(), (cx, cy + h * 0.3), h),
        ]
    else:
      views = [
        ("top", lambda v: (v[:, 0], v[:, 2]), lambda v: v[:, 1].max(), (cx, cz + (300 if name == "Devil" else -300)), 700),
        ("elevation (looking along Z)", lambda v: (v[:, 0], v[:, 1]), lambda v: -v[:, 2].mean() * (1 if name == "Devil" else -1), (cx, cy + 40), 260),
        ("elevation (looking along X)", lambda v: (v[:, 2], v[:, 1]), lambda v: v[:, 0].mean(), (cz, cy + 40), 260),
      ]
    fig, axes = plt.subplots(1, 3, figsize=(30, 11))
    for ax, (title, proj, depth, (ox, oy), half) in zip(axes, views):
        items = []
        for p in parts:
            if p["t"] >= 0.95:
                continue
            v = corners(p)
            items.append((depth(v), v, p))
        items.sort(key=lambda it: it[0])
        for _, v, p in items:
            x, y = proj(v)
            h = hull(np.stack([x, y], 1))
            if len(h) < 3:
                continue
            col = p["col"]
            alpha = max(0.15, 1 - p["t"])
            ax.add_patch(Polygon(h, closed=True, facecolor=col, edgecolor=(0, 0, 0, 0.25), lw=0.3, alpha=alpha))
        ax.set_xlim(ox - half, ox + half)
        ax.set_ylim(oy - half * (0.5 if title != "top" else 1), oy + half * (1.0 if title != "top" else 1))
        ax.set_aspect("equal")
        ax.set_facecolor({"Angel": "#87a8d0", "Devil": "#40100c"}.get(name, "#20242c"))
        ax.set_title(f"{name}: {title}")
    fig.suptitle(f"{name} capital — {data['count']} parts")
    fig.tight_layout()
    fig.savefig(os.path.join(out, f"{name}.png"), dpi=55)
    plt.close(fig)


def main():
    data = json.load(open(sys.argv[1]))
    out = sys.argv[2]
    os.makedirs(out, exist_ok=True)
    for name, cap in data.items():
        render(name, cap, out)
        print("rendered", name, cap["count"], "parts")


if __name__ == "__main__":
    main()
