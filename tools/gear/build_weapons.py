"""
Sculpted weapons and shields (equipment overhaul stage 2, PLAN.md D-69;
authoring aid, not shipped).

Each weapon family is sculpted from signed-distance shapes (bevelled blade
profiles, rounded boxes, rings, tapered capsules, ellipsoids), meshed with
surface nets (tools/creatures/sculpt.py) and written as a static glTF:

    python tools/gear/build_weapons.py [Family ...]

-> build/gear/<Family>.gltf and build/gear/<Family>.png (preview), then in
Studio: File > Import 3D the .gltf (units: studs), select the imported
model in the Workspace, right-click > Save to File as
src/server/GearModels/<Family>.rbxm.

Frame: the grip (where the hand closes) at the origin, +Y toward the tip,
blades flat in the XY plane (faces +-Z, edges +-X). Shields: the face
toward -Z, the arm strap at the origin. Three tiny marker meshes ("Grip"
at the origin, "GripY" at +Y, "GripX" at +X) let the game rebuild this
frame whatever the importer does to the model's position or rotation.

MeshParts are named by region; the game reads the name:
    <Role>[_T2|_T3][_Angel|_Devil]
Role picks the material and colour (Steel blade, Gold trim, Leather, Wood,
Horn, Cloth, Glow = rarity colour); _T2 / _T3 pieces only show from that
tier; _Angel / _Devil only for that realm.
"""
import base64, json, math, os, sys
import numpy as np

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "creatures"))
from sculpt import (  # noqa: E402
    RoundCone,
    Ellipsoid,
    smin,
    surface_nets,
    quads_to_tris,
    vertex_normals,
    taubin,
    render_preview,
    rot_x,
    rot_y,
    rot_z,
)

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "build", "gear")
MAX_TRIS = 19000

PALETTE = {
    "Steel": (0.78, 0.8, 0.85),
    "Gold": (0.86, 0.68, 0.32),
    "Leather": (0.36, 0.22, 0.13),
    "Wood": (0.45, 0.3, 0.18),
    "Horn": (0.85, 0.8, 0.7),
    "Cloth": (0.5, 0.12, 0.14),
    "Glow": (0.45, 0.8, 1.0),
    "Grip": (1, 0, 1),
    "GripY": (1, 0, 1),
    "GripX": (1, 0, 1),
}


def P(x, y, z=0.0):
    return np.array([x, y, z], dtype=np.float64)


# ---------------------------------------------------------------------------
# Shapes
# ---------------------------------------------------------------------------


class Shape:
    def __init__(self, region, blend):
        self.region = region
        self.blend = blend
        self.bone = "W"


class Blade(Shape):
    """
    A flat profile (polygon in the local XY plane) with bevelled edges: the
    half thickness ramps from `edge` at the outline to `core` over `bevel`
    studs inward, so blades have a ridge and crisp (but not paper-thin)
    edges.
    """

    def __init__(self, points, core, bevel, edge, region, origin=(0, 0, 0), rot=None, blend=0.0):
        super().__init__(region, blend)
        self.pts = np.asarray(points, float)
        self.core, self.bevel, self.edge = core, bevel, edge
        self.origin = np.asarray(origin, float)
        self.rot = np.eye(3) if rot is None else np.asarray(rot, float)

    def sdf(self, p):
        q = (p - self.origin) @ self.rot
        x, y, z = q[:, 0], q[:, 1], q[:, 2]
        a = self.pts
        b = np.roll(a, -1, 0)
        dist = np.full(len(q), np.inf)
        inside = np.zeros(len(q), bool)
        for (ax, ay), (bx, by) in zip(a, b):
            ex, ey = bx - ax, by - ay
            px, py = x - ax, y - ay
            h = np.clip((px * ex + py * ey) / (ex * ex + ey * ey), 0, 1)
            dx, dy = px - ex * h, py - ey * h
            dist = np.minimum(dist, np.sqrt(dx * dx + dy * dy))
            cross = ((ay > y) != (by > y)) & (x < (bx - ax) * (y - ay) / np.where(by - ay == 0, 1e-9, by - ay) + ax)
            inside ^= cross
        d = np.where(inside, -dist, dist)
        half = self.edge + (self.core - self.edge) * np.clip(-d / self.bevel, 0, 1)
        inner = np.maximum(d, np.abs(z) - half)
        outer = np.sqrt(np.maximum(d, 0) ** 2 + np.maximum(np.abs(z) - self.edge, 0) ** 2)
        return np.where(d < 0, inner, outer)

    def bounds(self):
        lo2, hi2 = self.pts.min(0), self.pts.max(0)
        corners = np.array([[x, y, z] for x in (lo2[0], hi2[0]) for y in (lo2[1], hi2[1]) for z in (-self.core, self.core)])
        w = corners @ self.rot.T + self.origin
        return w.min(0), w.max(0)


class RoundBox(Shape):
    def __init__(self, center, half, radius, region, rot=None, blend=0.0):
        super().__init__(region, blend)
        self.c = np.asarray(center, float)
        self.h = np.asarray(half, float)
        self.r = radius
        self.rot = np.eye(3) if rot is None else np.asarray(rot, float)

    def sdf(self, p):
        q = np.abs((p - self.c) @ self.rot) - (self.h - self.r)
        return np.linalg.norm(np.maximum(q, 0), axis=1) + np.minimum(q.max(1), 0) - self.r

    def bounds(self):
        m = np.linalg.norm(self.h)
        return self.c - m, self.c + m


class Torus(Shape):
    """A ring of radius R (tube r) in the local XZ plane."""

    def __init__(self, center, R, r, region, rot=None, blend=0.0):
        super().__init__(region, blend)
        self.c = np.asarray(center, float)
        self.R, self.r = R, r
        self.rot = np.eye(3) if rot is None else np.asarray(rot, float)

    def sdf(self, p):
        q = (p - self.c) @ self.rot
        qx = np.sqrt(q[:, 0] ** 2 + q[:, 2] ** 2) - self.R
        return np.sqrt(qx * qx + q[:, 1] ** 2) - self.r

    def bounds(self):
        m = self.R + self.r
        return self.c - m, self.c + m


def cone(a, b, ra, rb, region, blend=0.04):
    return RoundCone(P(*a), P(*b), ra, rb, "W", region, blend)


def ball(c, r, region, blend=0.04, rot=None):
    r = (r, r, r) if np.isscalar(r) else r
    return Ellipsoid(P(*c), np.asarray(r, float), "W", region, blend, rot)


def chain(points, r0, r1, region, blend=0.03):
    """Tapered capsules along a polyline (curved guards, limbs, horns)."""
    out = []
    n = len(points) - 1
    for i in range(n):
        ra = r0 + (r1 - r0) * i / n
        rb = r0 + (r1 - r0) * (i + 1) / n
        out.append(cone(points[i], points[i + 1], ra, rb, region, blend))
    return out


# ---------------------------------------------------------------------------
# Gear: shapes -> region meshes -> static glTF
# ---------------------------------------------------------------------------


class Gear:
    def __init__(self, name, step=0.03):
        self.name = name
        self.step = step
        self.base = []
        self.groups = []

    def add(self, *shapes):
        for s in shapes:
            if isinstance(s, list):
                self.base.extend(s)
            else:
                self.base.append(s)

    def group(self, *shapes):
        """A separate surface (an ornament the game can hide by tier / realm)."""
        flat = []
        for s in shapes:
            flat.extend(s if isinstance(s, list) else [s])
        self.groups.append(flat)

    def _mesh(self, shapes):
        step = self.step
        lo = np.min([s.bounds()[0] for s in shapes], axis=0) - 3 * step
        hi = np.max([s.bounds()[1] for s in shapes], axis=0) + 3 * step
        shape = np.ceil((hi - lo) / step).astype(int) + 1
        axes = [lo[i] + np.arange(shape[i]) * step for i in range(3)]
        pts = np.stack(np.meshgrid(*axes, indexing="ij"), -1).reshape(-1, 3)
        d = None
        for s in shapes:
            v = s.sdf(pts)
            d = v if d is None else smin(d, v, s.blend)
        verts, quads = surface_nets(d.reshape(shape), lo, step)
        tris = quads_to_tris(quads, verts)
        verts = taubin(verts, tris, iterations=1)
        near = np.stack([s.sdf(verts) for s in shapes], 1)
        region = np.array([s.region for s in shapes])[np.argmin(near, 1)]
        return verts, tris, region

    def build(self):
        meshes = {}
        for shapes in [self.base] + self.groups:
            if not shapes:
                continue
            verts, tris, region = self._mesh(shapes)
            tri_region = region[tris[:, 0]]
            for r in sorted(set(tri_region)):
                t = tris[tri_region == r]
                used = np.unique(t)
                remap = -np.ones(len(verts), dtype=np.int64)
                remap[used] = np.arange(len(used))
                v, tt = verts[used], remap[t]
                if r in meshes:
                    pv, pt = meshes[r]
                    meshes[r] = (np.concatenate([pv, v]), np.concatenate([pt, tt + len(pv)]))
                else:
                    meshes[r] = (v, tt)
        # Grip markers: tiny boxes at the origin, +Y and +X.
        for name, at in (("Grip", P(0, 0, 0)), ("GripY", P(0, 1, 0)), ("GripX", P(1, 0, 0))):
            meshes[name] = cube(at, 0.03)
        out = []
        for name, (v, t) in meshes.items():
            n = vertex_normals(v, t)
            ax = np.argmax(np.abs(n), 1)
            uv = np.where((ax == 0)[:, None], v[:, [2, 1]], np.where((ax == 1)[:, None], v[:, [0, 2]], v[:, [0, 1]])) * 0.5
            out.append((name, v, n, uv, t))
        return out

    def export(self):
        os.makedirs(OUT, exist_ok=True)
        meshes = self.build()
        write_static_gltf(os.path.join(OUT, f"{self.name}.gltf"), meshes, self.name)
        dummy = [(n, v, nn, uv, t, None, None) for n, v, nn, uv, t in meshes if not n.startswith("Grip")]
        render_preview(os.path.join(OUT, f"{self.name}.png"), dummy, self.name, PALETTE)
        tris = {n: len(t) for n, v, nn, uv, t in meshes}
        worst = max(tris.values())
        assert worst <= MAX_TRIS, f"{self.name}: a region has {worst} triangles (max {MAX_TRIS})"
        return tris


def cube(c, h):
    corners = np.array([[x, y, z] for x in (-h, h) for y in (-h, h) for z in (-h, h)]) + c
    faces = [(0, 1, 3, 2), (4, 6, 7, 5), (0, 4, 5, 1), (2, 3, 7, 6), (0, 2, 6, 4), (1, 5, 7, 3)]
    tris = []
    for a, b, cc, d in faces:
        tris += [(a, b, cc), (a, cc, d)]
    return corners, np.array(tris)


def write_static_gltf(path, meshes, name):
    buf = bytearray()
    views, accessors = [], []

    def add(arr, comp, typ, target=None, minmax=False):
        nonlocal buf
        while len(buf) % 4:
            buf.append(0)
        data = arr.tobytes()
        view = {"buffer": 0, "byteOffset": len(buf), "byteLength": len(data)}
        if target:
            view["target"] = target
        views.append(view)
        buf += data
        acc = {"bufferView": len(views) - 1, "componentType": comp, "count": len(arr), "type": typ}
        if minmax:
            acc["min"] = arr.min(0).tolist()
            acc["max"] = arr.max(0).tolist()
        accessors.append(acc)
        return len(accessors) - 1

    gl_meshes, nodes = [], []
    for region, v, n, uv, t in meshes:
        prim = {
            "attributes": {
                "POSITION": add(v.astype(np.float32), 5126, "VEC3", 34962, True),
                "NORMAL": add(n.astype(np.float32), 5126, "VEC3", 34962),
                "TEXCOORD_0": add(uv.astype(np.float32), 5126, "VEC2", 34962),
            },
            "indices": add(t.astype(np.uint32).reshape(-1), 5125, "SCALAR", 34963),
        }
        gl_meshes.append({"name": region, "primitives": [prim]})
        nodes.append({"name": region, "mesh": len(gl_meshes) - 1})
    root = {"name": name, "children": list(range(len(nodes)))}
    nodes.append(root)
    gltf = {
        "asset": {"version": "2.0", "generator": "riftbound tools/gear/build_weapons.py"},
        "scene": 0,
        "scenes": [{"nodes": [len(nodes) - 1]}],
        "nodes": nodes,
        "meshes": gl_meshes,
        "accessors": accessors,
        "bufferViews": views,
        "buffers": [{"byteLength": len(buf), "uri": "data:application/octet-stream;base64," + base64.b64encode(bytes(buf)).decode()}],
    }
    with open(path, "w") as f:
        json.dump(gltf, f)


# ---------------------------------------------------------------------------
# Shared pieces
# ---------------------------------------------------------------------------


def wrapped_grip(g, y0, y1, r, region="Leather", rings=True):
    g.add(cone((0, y0, 0), (0, y1, 0), r, r * 0.95, region, 0.0))
    if rings:
        y = y0 + 0.08
        while y < y1 - 0.05:
            g.add(Torus(P(0, y, 0), r, 0.022, region, blend=0.02))
            y += 0.13


def pommel(g, y, r=0.17):
    g.add(ball((0, y, 0), (r, r * 1.2, r), "Gold", 0.03))
    g.add(ball((0, y - r * 1.1, 0), r * 0.42, "Glow", 0.0))


def realm_wings(g, at, spread, size=1.0, up=0.0):
    """Tier-3 ornaments either side: feathered blades (Angel) / horns (Devil)."""
    for sx in (-1, 1):
        base = at + P(sx * spread, 0, 0)
        feather = [(0, 0), (0.09, 0.12), (0.07, 0.62), (0, 0.78), (-0.06, 0.6), (-0.07, 0.12)]
        rot = rot_z(math.radians(-sx * (40 + up)))
        g.group(
            Blade([(x * size, y * size) for x, y in feather], 0.05, 0.08, 0.02, "Gold_T3_Angel", base, rot.T),
            Blade(
                [(x * size * 0.8, y * size * 0.8) for x, y in feather],
                0.05,
                0.08,
                0.02,
                "Gold_T3_Angel",
                base + P(sx * 0.1, -0.05, 0),
                rot_z(math.radians(-sx * (62 + up))).T,
            ),
        )
        horn = [base + P(sx * 0.05 * size, 0, 0), base + P(sx * 0.25 * size, 0.25 * size, 0), base + P(sx * 0.32 * size, 0.55 * size, 0.06), base + P(sx * 0.22 * size, 0.75 * size, 0.1)]
        g.group(chain(horn, 0.08 * size, 0.02, "Horn_T3_Devil"))


def edge_glow(g, points, r=0.03, region="Glow"):
    g.add(chain(points, r, r, region, 0.0))


# ---------------------------------------------------------------------------
# Weapons
# ---------------------------------------------------------------------------


def sword_like(name, grip=(-0.55, 0.45), blade=None, guard=0.8, core=0.09, width=0.27, step=0.03, rune=(0.9, 2.8)):
    g = Gear(name, step)
    wrapped_grip(g, grip[0], grip[1], 0.1)
    pommel(g, grip[0] - 0.12)
    gy = grip[1] + 0.08
    # Swept cross guard with a central block.
    g.add(chain([(-guard, gy + 0.12, 0), (-guard * 0.55, gy, 0), (guard * 0.55, gy, 0), (guard, gy + 0.12, 0)], 0.09, 0.11, "Gold", 0.04))
    g.add(RoundBox(P(0, gy, 0), P(0.2, 0.12, 0.13), 0.04, "Gold", blend=0.03))
    g.add(ball((0, gy, -0.12), (0.08, 0.08, 0.04), "Glow", 0.0), ball((0, gy, 0.12), (0.08, 0.08, 0.04), "Glow", 0.0))
    g.add(Blade(blade, core, 0.16, 0.025, "Steel"))
    # Rune line down the ridge, on both faces.
    g.add(RoundBox(P(0, (rune[0] + rune[1]) / 2, 0), P(0.035, (rune[1] - rune[0]) / 2, core + 0.012), 0.02, "Glow"))
    # Tier 2: guard finials and a ricasso collar.
    g.group(ball((-guard - 0.04, gy + 0.16, 0), 0.09, "Gold_T2"), ball((guard + 0.04, gy + 0.16, 0), 0.09, "Gold_T2"))
    g.group(RoundBox(P(0, gy + 0.26, 0), P(width * 0.95, 0.06, core + 0.03), 0.03, "Gold_T2"))
    realm_wings(g, P(0, gy + 0.05, 0), guard * 0.75, 0.8)
    return g


def blade_profile(base_y, length, width, tip=0.55, leaf=0.04):
    """Symmetric blade: straight body widening slightly (leaf) then a point."""
    top = base_y + length
    w = width
    right = [(w * 0.92, base_y), (w + leaf, base_y + length * 0.55), (w * 0.8, top - tip), (0, top)]
    left = [(-x, y) for x, y in reversed(right[:-1])]
    return right + left


def sword():
    return sword_like("Sword", blade=blade_profile(0.62, 3.5, 0.31, tip=0.6, leaf=0.06), core=0.1, width=0.33)


def greatsword():
    return sword_like(
        "Greatsword", grip=(-1.05, 0.5), blade=blade_profile(0.68, 4.9, 0.44, tip=0.8, leaf=0.05), guard=1.15, core=0.12, width=0.46, step=0.038, rune=(1.0, 4.0)
    )


def dagger():
    g = Gear("Dagger", 0.025)
    wrapped_grip(g, -0.35, 0.3, 0.09)
    pommel(g, -0.46, 0.13)
    g.add(chain([(-0.42, 0.44, 0), (-0.22, 0.36, 0), (0.22, 0.36, 0), (0.42, 0.44, 0)], 0.06, 0.08, "Gold", 0.03))
    g.add(RoundBox(P(0, 0.37, 0), P(0.14, 0.08, 0.1), 0.03, "Gold", blend=0.02))
    # A broad leaf blade with a slight curve.
    prof = [(0.18, 0.45), (0.24, 0.95), (0.17, 1.55), (0.02, 2.0), (-0.12, 1.6), (-0.2, 0.95), (-0.17, 0.45)]
    g.add(Blade(prof, 0.075, 0.12, 0.022, "Steel"))
    g.add(RoundBox(P(0, 1.05, 0), P(0.025, 0.45, 0.085), 0.015, "Glow"))
    g.group(ball((-0.46, 0.48, 0), 0.07, "Gold_T2"), ball((0.46, 0.48, 0), 0.07, "Gold_T2"))
    realm_wings(g, P(0, 0.4, 0), 0.32, 0.55)
    return g


def mace():
    g = Gear("Mace", 0.03)
    wrapped_grip(g, -0.55, 0.45, 0.1)
    pommel(g, -0.68, 0.14)
    g.add(cone((0, 0.45, 0), (0, 1.75, 0), 0.085, 0.1, "Gold", 0.02))
    g.add(Torus(P(0, 1.0, 0), 0.1, 0.03, "Gold", blend=0.02))
    hy = 2.05
    g.add(ball((0, hy, 0), (0.3, 0.38, 0.3), "Steel", 0.05))
    # Six flanges around the head.
    for i in range(6):
        a = math.radians(i * 60)
        rot = rot_y(a)
        fl = [(0.0, -0.34), (0.46, -0.2), (0.52, 0.14), (0.0, 0.4)]
        g.add(Blade(fl, 0.08, 0.12, 0.035, "Steel", P(0, hy, 0), rot.T, blend=0.03))
    g.add(Torus(P(0, hy - 0.42, 0), 0.16, 0.05, "Gold", blend=0.02), Torus(P(0, hy - 0.5, 0), 0.13, 0.035, "Glow"))
    g.add(ball((0, hy + 0.05, 0), (0.12, 0.12, 0.12), "Gold", 0.0))
    g.add(cone((0, hy + 0.3, 0), (0, hy + 0.62, 0), 0.08, 0.01, "Steel", 0.03))
    g.group(*[cone((0.25 * math.cos(math.radians(i * 60 + 30)), hy, 0.25 * math.sin(math.radians(i * 60 + 30))), (0.62 * math.cos(math.radians(i * 60 + 30)), hy, 0.62 * math.sin(math.radians(i * 60 + 30))), 0.09, 0.03, "Steel_T2", 0.0) for i in range(6)])
    realm_wings(g, P(0, hy - 0.35, 0), 0.22, 0.6)
    return g


def axe_head(g, cy, size, side=-1, region="Steel"):
    """A crescent axe blade on one side of the haft (side -1 = -X)."""
    s = size
    prof = [(0.05, -0.18), (0.55, -0.34), (0.95, -0.62), (1.08, -0.1), (1.12, 0.28), (0.95, 0.68), (0.55, 0.32), (0.05, 0.2)]
    pts = [(side * x * s, y * s) for x, y in prof]
    if side > 0:
        pts = list(reversed(pts))
    g.add(Blade(pts, 0.09 * s, 0.22 * s, 0.025, region, P(0, cy, 0)))
    edge = [P(side * 0.98 * s, cy - 0.6 * s), P(side * 1.11 * s, cy - 0.05 * s), P(side * 1.08 * s, cy + 0.32 * s), P(side * 0.92 * s, cy + 0.64 * s)]
    edge_glow(g, edge, 0.025)


def axe():
    g = Gear("Axe", 0.03)
    g.add(cone((0, -0.75, 0), (0, 2.45, 0), 0.1, 0.085, "Wood", 0.0))
    wrapped_grip(g, -0.6, 0.35, 0.105)
    hy = 2.05
    g.add(RoundBox(P(0, hy, 0), P(0.17, 0.3, 0.13), 0.04, "Gold", blend=0.03))
    axe_head(g, hy, 0.85)
    # Back spike (poll).
    g.add(cone((0.12, hy, 0), (0.48, hy + 0.04, 0), 0.09, 0.02, "Steel", 0.02))
    g.group(Torus(P(0, hy - 0.42, 0), 0.11, 0.035, "Gold_T2"), Torus(P(0, hy + 0.42, 0), 0.1, 0.035, "Gold_T2"))
    realm_wings(g, P(0, hy + 0.35, 0), 0.15, 0.55)
    return g


def war_hammer():
    g = Gear("WarHammer", 0.035)
    g.add(cone((0, -1.65, 0), (0, 3.0, 0), 0.12, 0.11, "Wood", 0.0))
    wrapped_grip(g, -1.0, 0.65, 0.125)
    g.add(ball((0, -1.72, 0), (0.15, 0.2, 0.15), "Gold", 0.03))
    hy = 3.25
    g.add(RoundBox(P(0, hy, 0), P(0.78, 0.4, 0.4), 0.08, "Steel", blend=0.0))
    for sx in (-1, 1):
        g.add(RoundBox(P(sx * 0.82, hy, 0), P(0.1, 0.48, 0.48), 0.05, "Gold", blend=0.02))
    g.add(RoundBox(P(0, hy, 0), P(0.8, 0.06, 0.42), 0.02, "Glow"))
    g.add(RoundBox(P(0, hy - 0.46, 0), P(0.2, 0.1, 0.2), 0.04, "Gold", blend=0.02))
    g.group(cone((0, hy + 0.38, 0), (0, hy + 0.95, 0), 0.13, 0.02, "Steel_T2", 0.0))
    realm_wings(g, P(0, hy - 0.2, 0), 0.6, 0.75)
    return g


def battle_axe():
    g = Gear("BattleAxe", 0.035)
    g.add(cone((0, -1.65, 0), (0, 3.2, 0), 0.11, 0.1, "Wood", 0.0))
    wrapped_grip(g, -1.0, 0.65, 0.115)
    g.add(ball((0, -1.72, 0), (0.14, 0.19, 0.14), "Gold", 0.03))
    hy = 2.55
    g.add(RoundBox(P(0, hy, 0), P(0.2, 0.42, 0.15), 0.05, "Gold", blend=0.03))
    axe_head(g, hy, 1.45)
    g.add(cone((0, hy + 0.4, 0), (0, hy + 1.0, 0), 0.1, 0.02, "Steel", 0.02))
    # Tier 2: the second bit (double axe).
    sub = Gear("tmp", 0.035)
    axe_head(sub, hy, 1.15, side=1, region="Steel_T2")
    g.group(*sub.base)
    realm_wings(g, P(0, hy + 0.45, 0), 0.2, 0.7)
    return g


def polearm():
    g = Gear("Polearm", 0.035)
    g.add(cone((0, -2.65, 0), (0, 3.45, 0), 0.1, 0.095, "Wood", 0.0))
    wrapped_grip(g, -0.6, 0.6, 0.11)
    g.add(cone((0, -2.65, 0), (0, -2.95, 0), 0.11, 0.03, "Gold", 0.02))
    top = 3.45
    g.add(RoundBox(P(0, top, 0), P(0.14, 0.18, 0.14), 0.04, "Gold", blend=0.02))
    leaf = [(0.06, top + 0.1), (0.36, top + 0.7), (0.28, top + 1.55), (0, top + 2.1), (-0.28, top + 1.55), (-0.36, top + 0.7), (-0.06, top + 0.1)]
    g.add(Blade(leaf, 0.1, 0.16, 0.025, "Steel"))
    g.add(RoundBox(P(0, top + 0.95, 0), P(0.03, 0.55, 0.11), 0.015, "Glow"))
    side = [(0.08, top - 0.15), (0.8, top - 0.4), (1.2, top - 0.05), (0.9, top + 0.18), (0.08, top + 0.1)]
    g.group(Blade(side, 0.06, 0.12, 0.02, "Steel_T2"))
    realm_wings(g, P(0, top + 0.05, 0), 0.2, 0.6)
    return g


def staff():
    g = Gear("Staff", 0.035)
    g.add(cone((0, -3.1, 0), (0, 3.15, 0), 0.1, 0.12, "Wood", 0.0))
    for y in (-3.0, -1.0, 0.9, 2.6):
        g.add(Torus(P(0, y, 0), 0.115, 0.035, "Gold", blend=0.02))
    wrapped_grip(g, -0.5, 0.5, 0.115, rings=False)
    head = P(0, 3.75, 0)
    # A crescent cradle holding a glowing crystal orb.
    g.add(Torus(head, 0.52, 0.07, "Gold", rot_x(math.radians(90)).T, blend=0.02))
    g.add(cone((0, 3.15, 0), (0, 3.25, 0), 0.13, 0.15, "Gold", 0.03))
    g.add(ball(head, 0.3, "Glow", 0.0))
    for sx in (-1, 1):
        g.add(cone((sx * 0.1, 3.2, 0), (sx * 0.45, 3.45, 0), 0.06, 0.045, "Gold", 0.02))
    g.group(*chain([head + P(0, 0.52, 0), head + P(0, 0.8, 0)], 0.06, 0.02, "Gold_T2"), ball(head + P(0, 0.85, 0), 0.08, "Glow_T2"))
    realm_wings(g, head + P(0, -0.1, 0), 0.5, 0.8, up=-10)
    return g


def orb():
    g = Gear("Orb", 0.025)
    g.add(ball((0, 0, 0), 0.42, "Glow", 0.0))
    g.add(Torus(P(0, 0, 0), 0.52, 0.04, "Gold", rot_x(math.radians(70)).T))
    g.group(Torus(P(0, 0, 0), 0.58, 0.035, "Gold_T2", (rot_z(math.radians(60)) @ rot_x(math.radians(-20))).T))
    g.group(*chain([P(0, -0.42, 0), P(0, -0.7, 0)], 0.06, 0.01, "Gold_T3_Angel"), *chain([P(0, 0.42, 0), P(0, 0.7, 0)], 0.06, 0.01, "Gold_T3_Angel"))
    g.group(*chain([P(0.3, 0.3, 0), P(0.55, 0.62, 0.05)], 0.06, 0.01, "Horn_T3_Devil"), *chain([P(-0.3, 0.3, 0), P(-0.55, 0.62, 0.05)], 0.06, 0.01, "Horn_T3_Devil"))
    return g


def wand():
    g = Gear("Wand", 0.022)
    g.add(cone((0, -0.4, 0), (0, 1.55, 0), 0.075, 0.05, "Wood", 0.0))
    for y in (-0.35, 0.35, 1.0):
        g.add(Torus(P(0, y, 0), 0.07, 0.022, "Gold", blend=0.01))
    g.add(cone((0, 1.5, 0), (0, 1.62, 0), 0.06, 0.08, "Gold", 0.02))
    crystal = [(0.0, 1.6), (0.1, 1.82), (0.06, 2.12), (0.0, 2.25), (-0.06, 2.12), (-0.1, 1.82)]
    g.add(Blade(crystal, 0.09, 0.08, 0.03, "Glow"))
    g.group(*[cone((0, 1.62, 0), (0.14 * math.cos(math.radians(a)), 1.85, 0.14 * math.sin(math.radians(a))), 0.025, 0.01, "Gold_T2", 0.0) for a in (0, 120, 240)])
    realm_wings(g, P(0, 1.55, 0), 0.08, 0.35)
    return g


def tome():
    g = Gear("Tome", 0.025)
    g.add(RoundBox(P(0, 0, 0), P(0.48, 0.62, 0.17), 0.04, "Leather"))
    g.add(RoundBox(P(0.03, 0, 0), P(0.44, 0.58, 0.19), 0.02, "Cloth"))
    g.add(RoundBox(P(-0.47, 0, 0), P(0.06, 0.62, 0.19), 0.04, "Leather", blend=0.02))
    g.add(Torus(P(0, 0, -0.2), 0.22, 0.03, "Glow", rot_x(math.radians(90)).T))
    g.add(ball((0, 0, -0.2), (0.08, 0.08, 0.04), "Glow", 0.0))
    for cx in (-1, 1):
        for cy in (-1, 1):
            g.group(RoundBox(P(cx * 0.42, cy * 0.56, 0), P(0.08, 0.08, 0.2), 0.02, "Gold_T2"))
    g.group(RoundBox(P(0.48, 0, 0), P(0.04, 0.12, 0.08), 0.02, "Gold_T2"))
    return g


def bow():
    g = Gear("Bow", 0.025)
    pts = []
    for i in range(13):
        t = i / 12 * 2 - 1
        # Recurve: limbs curve back, tips flick forward.
        z = 0.6 * t * t - 0.18 * t ** 4 - 0.12 * max(0, abs(t) - 0.85) * 6
        pts.append(P(0, t * 2.45, z))
    limbs = []
    for i in range(12):
        ta = abs(i / 12 * 2 - 1)
        tb = abs((i + 1) / 12 * 2 - 1)
        limbs.append(cone(pts[i], pts[i + 1], 0.13 - 0.07 * ta, 0.13 - 0.07 * tb, "Wood", 0.03))
    g.add(limbs)
    g.add(cone((0, -0.35, 0.02), (0, 0.35, 0.02), 0.14, 0.14, "Leather", 0.02))
    g.add(Torus(P(0, -0.38, 0.02), 0.14, 0.035, "Gold"), Torus(P(0, 0.38, 0.02), 0.14, 0.035, "Gold"))
    g.add(cone(pts[0], pts[-1], 0.028, 0.028, "Glow", 0.0))
    for end in (pts[0], pts[-1]):
        g.add(ball(end, 0.07, "Gold", 0.02))
    # Tier 2: metal limb guards; tier 3: realm ornaments at the grip.
    g.group(*[cone(pts[i], pts[i + 1], 0.09, 0.09, "Gold_T2", 0.02) for i in (2, 9)])
    realm_wings(g, P(0, 0.5, 0.05), 0.12, 0.5)
    return g


def crossbow():
    g = Gear("Crossbow", 0.025)
    # Stock along +Y with a shoulder butt, grip below the hand.
    g.add(RoundBox(P(0, 0.75, 0.05), P(0.13, 1.35, 0.15), 0.05, "Wood"))
    g.add(RoundBox(P(0, -0.55, 0.12), P(0.15, 0.25, 0.26), 0.06, "Wood", blend=0.04))
    g.add(cone((0, 0.05, 0.1), (0, -0.35, 0.45), 0.09, 0.08, "Leather", 0.03))
    g.add(RoundBox(P(0, 0.5, 0.2), P(0.05, 0.12, 0.05), 0.02, "Gold"))
    g.add(RoundBox(P(0, 1.95, 0.0), P(0.18, 0.14, 0.18), 0.04, "Gold", blend=0.02))
    prod = []
    for i in range(9):
        t = i / 8 * 2 - 1
        prod.append(P(t * 1.25, 1.95 - 0.32 * t * t, -0.05))
    g.add([cone(prod[i], prod[i + 1], 0.1 - 0.05 * abs(i / 8 * 2 - 1), 0.1 - 0.05 * abs((i + 1) / 8 * 2 - 1), "Steel", 0.03) for i in range(8)])
    nut = P(0, 0.85, 0.0)
    g.add(cone(prod[0], nut, 0.025, 0.025, "Glow", 0.0), cone(prod[-1], nut, 0.025, 0.025, "Glow", 0.0))
    # A loaded bolt with a glowing head.
    g.add(cone((0, 0.85, -0.12), (0, 2.3, -0.12), 0.035, 0.035, "Wood", 0.0))
    g.add(Blade([(0, 2.55), (0.08, 2.32), (0, 2.28), (-0.08, 2.32)], 0.04, 0.05, 0.02, "Glow", P(0, 0, -0.12)))
    g.group(RoundBox(P(0, 1.2, 0.05), P(0.16, 0.06, 0.17), 0.02, "Gold_T2"), RoundBox(P(0, 0.2, 0.05), P(0.16, 0.06, 0.17), 0.02, "Gold_T2"))
    realm_wings(g, P(0, 1.95, -0.05), 0.2, 0.5)
    return g


def shield():
    """Kite shield, face toward -Z, arm strap at the origin."""
    g = Gear("Shield", 0.035)
    kite = [(0, 1.3), (0.8, 1.1), (0.95, 0.4), (0.7, -0.5), (0, -1.45), (-0.7, -0.5), (-0.95, 0.4), (-0.8, 1.1)]
    rot = rot_x(math.radians(4))
    g.add(Blade(kite, 0.12, 0.45, 0.05, "Steel", P(0, 0, -0.3), rot.T))
    inner = [(x * 0.8, y * 0.8 - 0.02) for x, y in kite]
    g.add(Blade(inner, 0.14, 0.3, 0.06, "Cloth", P(0, 0, -0.33), rot.T))
    # Rim following the outline.
    rim = [P(x, y, -0.3) for x, y in kite + [kite[0]]]
    g.add(chain(rim, 0.06, 0.06, "Gold", 0.02))
    g.add(ball((0, 0.1, -0.44), (0.28, 0.28, 0.14), "Gold", 0.03))
    g.add(ball((0, 0.1, -0.56), (0.11, 0.11, 0.06), "Glow", 0.0))
    g.add(chain([P(0, 0.9, -0.42), P(0, 0.42, -0.45)], 0.035, 0.035, "Glow", 0.0), chain([P(0, -0.22, -0.45), P(0, -1.05, -0.4)], 0.035, 0.035, "Glow", 0.0))
    # Arm strap and handle behind.
    g.add(RoundBox(P(0, 0, -0.12), P(0.08, 0.32, 0.1), 0.03, "Leather", blend=0.02))
    g.group(*[ball((sx * 0.62, 0.95, -0.38), 0.07, "Gold_T2") for sx in (-1, 1)], ball((0, -1.15, -0.38), 0.07, "Gold_T2"))
    for sx in (-1, 1):
        wing = [(0, 0), (0.12, 0.1), (0.1, 0.62), (0, 0.72), (-0.08, 0.55), (-0.1, 0.1)]
        g.group(Blade(wing, 0.04, 0.07, 0.02, "Gold_T3_Angel", P(sx * 0.28, 0.25, -0.46), rot_z(math.radians(-sx * 55)).T))
        g.group(chain([P(sx * 0.25, 0.3, -0.46), P(sx * 0.48, 0.55, -0.5), P(sx * 0.52, 0.85, -0.52)], 0.06, 0.015, "Horn_T3_Devil"))
    return g


BUILDERS = {
    "Sword": sword,
    "Greatsword": greatsword,
    "Dagger": dagger,
    "Mace": mace,
    "Axe": axe,
    "WarHammer": war_hammer,
    "BattleAxe": battle_axe,
    "Polearm": polearm,
    "Staff": staff,
    "Orb": orb,
    "Wand": wand,
    "Tome": tome,
    "Bow": bow,
    "Crossbow": crossbow,
    "Shield": shield,
}


def main():
    names = sys.argv[1:] or list(BUILDERS)
    for name in names:
        g = BUILDERS[name]()
        tris = g.export()
        total = sum(v for k, v in tris.items() if not k.startswith("Grip"))
        print(f"{name}: {total} tris; " + ", ".join(f"{k} {v}" for k, v in sorted(tris.items()) if not k.startswith("Grip")))


if __name__ == "__main__":
    main()
