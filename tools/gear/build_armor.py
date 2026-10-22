"""
Sculpted armor and jewellery (equipment overhaul stage 3, PLAN.md D-71;
authoring aid, not shipped).

One model per class and slot (Warrior / Healer / Archer / Mage x Helm,
Shoulders, Chest, Hands, Legs, Boots) and three jewellery models
(Necklace, Earrings, Ring):

    python tools/gear/build_armor.py [Name ...]

Needs numpy, matplotlib and fast-simplification (pip install
fast-simplification): each model is decimated to about 12k triangles so a
full set stays light on phones.

-> build/armor/<Name>.gltf (+ .png preview). In Studio: File > Import 3D
(units: studs), then Save to File as src/server/GearModels/<Name>.rbxm
(the same folder as the weapons).

Every piece belongs to one body part and is sculpted in that part's
**unit box**: the part's bounding box mapped to -0.5 .. 0.5 on each axis
(X right, Y up, the character facing -Z). The game stretches each piece
by the real part's size and welds it there, so the armor fits whatever
the body's proportions. MeshParts are named

    <Role>@<Part>[_T2|_T3][_Angel|_Devil]

Role picks the material and colour (Steel, Gold, Leather, Cloth, Wood,
Horn, Glow = rarity colour); Part is the R15 part ("UpperTorso",
"LeftUpperArm", ... or "Hand" for a ring, worn on the ring's side); _T2 /
_T3 pieces show from that tier, _Angel / _Devil only for that realm.
Markers "Grip" (origin), "GripY" (+Y) and "GripX" (+X) give the unit
frame back whatever the importer does.
"""
import math, os, sys
import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from build_weapons import (  # noqa: E402
    Shape,
    Blade,
    RoundBox,
    Torus,
    cone,
    ball,
    chain,
    cube,
    write_static_gltf,
    P,
    smin,
    surface_nets,
    quads_to_tris,
    taubin,
    vertex_normals,
    render_preview,
    rot_x,
    rot_y,
    rot_z,
)

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "build", "armor")
MAX_TRIS = 19000
# Triangle budget per model after decimation (a full set stays mobile-
# friendly); regions under SMALL triangles are left as they are.
BUDGET = 12000
SMALL = 600
STEP = 0.034

PALETTE = {
    "Steel": (0.74, 0.76, 0.82),
    "Gold": (0.86, 0.68, 0.32),
    "Leather": (0.38, 0.24, 0.14),
    "Cloth": (0.55, 0.14, 0.16),
    "Wood": (0.45, 0.3, 0.18),
    "Horn": (0.85, 0.8, 0.7),
    "Glow": (0.45, 0.8, 1.0),
}

# Preview only: where each part's unit box is drawn.
PREVIEW_AT = {
    "Head": (0, 3.1, 0),
    "UpperTorso": (0, 1.6, 0),
    "LowerTorso": (0, 0.5, 0),
    "RightUpperArm": (1.4, 1.7, 0),
    "RightLowerArm": (1.4, 0.6, 0),
    "RightHand": (1.4, -0.3, 0),
    "LeftUpperArm": (-1.4, 1.7, 0),
    "LeftLowerArm": (-1.4, 0.6, 0),
    "LeftHand": (-1.4, -0.3, 0),
    "Hand": (2.6, -0.3, 0),
    "RightUpperLeg": (0.5, -0.7, 0),
    "RightLowerLeg": (0.5, -1.9, 0),
    "RightFoot": (0.5, -2.9, 0),
    "LeftUpperLeg": (-0.5, -0.7, 0),
    "LeftLowerLeg": (-0.5, -1.9, 0),
    "LeftFoot": (-0.5, -2.9, 0),
}


class Shell(Shape):
    """
    A hollow ellipsoid `thickness` thick, optionally cut by half-spaces:
    each clip (normal, offset) keeps the side where normal . p <= offset.
    """

    def __init__(self, center, radii, thickness, region, clips=(), blend=0.0):
        super().__init__(region, blend)
        self.c = np.asarray(center, float)
        self.r = np.asarray(radii, float)
        self.t = thickness
        self.clips = [(np.asarray(n, float) / np.linalg.norm(n), d) for n, d in clips]

    def _ell(self, q, r):
        k0 = np.linalg.norm(q / r, axis=1)
        k1 = np.linalg.norm(q / (r * r), axis=1)
        return k0 * (k0 - 1.0) / np.maximum(k1, 1e-9)

    def sdf(self, p):
        q = p - self.c
        outer = self._ell(q, self.r + self.t / 2)
        inner = self._ell(q, np.maximum(self.r - self.t / 2, 1e-3))
        d = np.maximum(outer, -inner)
        for n, off in self.clips:
            d = np.maximum(d, p @ n - off)
        return d

    def bounds(self):
        m = self.r + self.t
        return self.c - m, self.c + m


class Tube(Shape):
    """A hollow vertical cylinder (sleeves, bracers, greaves) along Y."""

    def __init__(self, center, rx, rz, height, thickness, region, taper=0.0, blend=0.0):
        super().__init__(region, blend)
        self.c = np.asarray(center, float)
        self.rx, self.rz, self.h, self.t, self.taper = rx, rz, height, thickness, taper

    def sdf(self, p):
        q = p - self.c
        k = 1.0 - self.taper * np.clip(q[:, 1] / self.h + 0.5, 0, 1)
        rx, rz = self.rx * k, self.rz * k
        rad = np.sqrt((q[:, 0] / rx) ** 2 + (q[:, 2] / rz) ** 2)
        mid = (rx + rz) / 2
        ring = np.abs((rad - 1.0) * mid) - self.t / 2
        cap = np.abs(q[:, 1]) - self.h / 2
        return np.maximum(ring, cap)

    def bounds(self):
        m = np.array([self.rx + self.t, self.h / 2, self.rz + self.t])
        return self.c - m, self.c + m


def mirror_x(shapes):
    """Mirrored copies (left side from right side) of simple shapes."""
    out = []
    for s in shapes:
        out.append(Mirrored(s))
    return out


class Mirrored(Shape):
    def __init__(self, inner):
        super().__init__(inner.region, inner.blend)
        self.inner = inner

    def sdf(self, p):
        q = p.copy()
        q[:, 0] = -q[:, 0]
        return self.inner.sdf(q)

    def bounds(self):
        lo, hi = self.inner.bounds()
        return np.array([-hi[0], lo[1], lo[2]]), np.array([-lo[0], hi[1], hi[2]])


class Armor:
    """Pieces per body part, each part meshed in its own unit box."""

    def __init__(self, name):
        self.name = name
        self.parts = {}  # part -> {"base": [...], "groups": [[...], ...]}

    def _slot(self, part):
        return self.parts.setdefault(part, {"base": [], "groups": []})

    def add(self, part, *shapes):
        slot = self._slot(part)
        for s in shapes:
            slot["base"].extend(s if isinstance(s, list) else [s])

    def group(self, part, *shapes):
        flat = []
        for s in shapes:
            flat.extend(s if isinstance(s, list) else [s])
        self._slot(part)["groups"].append(flat)

    def both(self, part, shapes, ornament=False):
        """Right-side shapes on Right<part> and mirrored on Left<part>."""
        for side, ss in (("Right", shapes), ("Left", mirror_x(shapes))):
            if ornament:
                self.group(side + part, ss)
            else:
                self.add(side + part, ss)

    step = STEP

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
        if len(quads) == 0:
            return None
        tris = quads_to_tris(quads, verts)
        verts = taubin(verts, tris, iterations=2)
        near = np.stack([s.sdf(verts) for s in shapes], 1)
        region = np.array([s.region for s in shapes])[np.argmin(near, 1)]
        return verts, tris, region

    def build(self):
        meshes = {}
        for part, slot in self.parts.items():
            for shapes in [slot["base"]] + slot["groups"]:
                if not shapes:
                    continue
                got = self._mesh(shapes)
                if got is None:
                    continue
                verts, tris, region = got
                tri_region = region[tris[:, 0]]
                for r in sorted(set(tri_region)):
                    role, _, suffix = r.partition("_")
                    name = f"{role}@{part}" + (f"_{suffix}" if suffix else "")
                    t = tris[tri_region == r]
                    used = np.unique(t)
                    remap = -np.ones(len(verts), dtype=np.int64)
                    remap[used] = np.arange(len(used))
                    v, tt = verts[used], remap[t]
                    if name in meshes:
                        pv, pt, _ = meshes[name]
                        meshes[name] = (np.concatenate([pv, v]), np.concatenate([pt, tt + len(pv)]), part)
                    else:
                        meshes[name] = (v, tt, part)
        out = []
        for name, (v, t, part) in meshes.items():
            n = vertex_normals(v, t)
            ax = np.argmax(np.abs(n), 1)
            uv = np.where((ax == 0)[:, None], v[:, [2, 1]], np.where((ax == 1)[:, None], v[:, [0, 2]], v[:, [0, 1]])) * 0.5
            out.append((name, v, n, uv, t, part))
        return out

    def export(self):
        os.makedirs(OUT, exist_ok=True)
        # Coarsen the sampling until every region fits Roblox's mesh limit.
        while True:
            built = self.build()
            if max(len(t) for _, _, _, _, t, _ in built) <= MAX_TRIS:
                break
            self.step *= 1.15
        built = decimate(built)
        meshes = [(n, v, nn, uv, t) for n, v, nn, uv, t, _ in built]
        for name, at in (("Grip", P(0, 0, 0)), ("GripY", P(0, 1, 0)), ("GripX", P(1, 0, 0))):
            cv, ct = cube(at, 0.02)
            meshes.append((name, cv, vertex_normals(cv, ct), np.zeros((len(cv), 2)), ct))
        write_static_gltf(os.path.join(OUT, f"{self.name}.gltf"), meshes, self.name)
        preview = []
        for n, v, nn, uv, t, part in built:
            role = n.split("@")[0]
            preview.append((role, v + np.asarray(PREVIEW_AT.get(part, (0, 0, 0))), nn, uv, t, None, None))
        render_preview(os.path.join(OUT, f"{self.name}.png"), preview, self.name, PALETTE)
        tris = {n: len(t) for n, v, nn, uv, t in meshes}
        worst = max(tris.values())
        assert worst <= MAX_TRIS, f"{self.name}: a region has {worst} triangles (max {MAX_TRIS})"
        return sum(v for k, v in tris.items() if not k.startswith("Grip"))


def decimate(built):
    """Quadric decimation (fast-simplification) down to BUDGET triangles."""
    import fast_simplification

    total = sum(len(t) for _, _, _, _, t, _ in built)
    if total <= BUDGET:
        return built
    out = []
    for name, v, n, uv, t, part in built:
        if len(t) < SMALL:
            out.append((name, v, n, uv, t, part))
            continue
        share = max(SMALL, int(BUDGET * len(t) / total))
        reduction = min(0.92, max(0.0, 1 - share / len(t)))
        if reduction <= 0.05:
            out.append((name, v, n, uv, t, part))
            continue
        v2, t2 = fast_simplification.simplify(v.astype(np.float32), t.astype(np.int32), target_reduction=reduction)
        v2 = v2.astype(np.float64)
        t2 = t2.astype(np.int64)
        n2 = vertex_normals(v2, t2)
        ax = np.argmax(np.abs(n2), 1)
        uv2 = np.where((ax == 0)[:, None], v2[:, [2, 1]], np.where((ax == 1)[:, None], v2[:, [0, 2]], v2[:, [0, 1]])) * 0.5
        out.append((name, v2, n2, uv2, t2, part))
    return out


# ---------------------------------------------------------------------------
# Shared pieces (unit-box coordinates)
# ---------------------------------------------------------------------------

UP = (0, 1, 0)
DOWN = (0, -1, 0)
FRONT = (0, 0, -1)
BACK = (0, 0, 1)


def rivets(points, r, region="Gold"):
    return [ball(p, r, region, 0.0) for p in points]


def gem(at, r, flat=0.5):
    return ball(at, (r, r, r * flat), "Glow", 0.0)


def realm_pair(armor, part, at, spread, size, mirror=True, tilt=35):
    """Tier-3 realm ornaments: small feathered blades (Angel) / horns (Devil)."""
    feather = [(0, 0), (0.06, 0.08), (0.05, 0.42), (0, 0.52), (-0.04, 0.4), (-0.05, 0.08)]
    for sx in ((-1, 1) if mirror else (1,)):
        base = P(at[0] + sx * spread, at[1], at[2])
        rot = rot_z(math.radians(-sx * tilt))
        armor.group(part, Blade([(x * size, y * size) for x, y in feather], 0.04, 0.05, 0.026, "Gold_T3_Angel", base, rot.T))
        horn = [base, base + P(sx * 0.12 * size, 0.18 * size, 0), base + P(sx * 0.16 * size, 0.4 * size, 0.04)]
        armor.group(part, chain(horn, 0.06 * size, 0.015, "Horn_T3_Devil"))


# ---------------------------------------------------------------------------
# Warrior: plate
# ---------------------------------------------------------------------------


def warrior_helm():
    a = Armor("Warrior_Helm")
    # Open-faced dome over the head, cut above the brow at the front.
    a.add("Head", Shell((0, 0.06, 0.02), (0.6, 0.6, 0.62), 0.07, "Steel", clips=[((0, -1, 0), 0.05), ((0, -0.55, -1), 0.28)]))
    a.add("Head", Torus(P(0, 0.08, 0.02), 0.6, 0.035, "Gold"))
    # Cheek guards and nape guard.
    for sx in (-1, 1):
        a.add("Head", RoundBox(P(sx * 0.56, -0.18, -0.04), P(0.04, 0.24, 0.26), 0.03, "Steel", blend=0.02))
    a.add("Head", Shell((0, -0.05, 0.05), (0.6, 0.55, 0.6), 0.06, "Steel", clips=[((0, 0, -1), -0.25), ((0, 1, 0), 0.0)]))
    a.add("Head", rivets([P(sx * 0.55, 0.05, -0.2) for sx in (-1, 1)], 0.03))
    # Tier 2: a ridge crest and glowing brow band.
    a.group("Head", RoundBox(P(0, 0.62, 0.05), P(0.04, 0.12, 0.45), 0.03, "Steel_T2"))
    a.group("Head", Torus(P(0, 0.14, 0.02), 0.615, 0.018, "Glow_T2"))
    realm_pair(a, "Head", (0, 0.35, 0.05), 0.6, 0.9)
    return a


def warrior_shoulders():
    a = Armor("Warrior_Shoulders")
    # Layered pauldrons over each upper arm (authored on the right arm).
    plates = [
        Shell((0.08, 0.32, 0), (0.78, 0.38, 0.72), 0.07, "Steel", clips=[((0, -1, 0), -0.1)]),
        Shell((0.12, 0.1, 0), (0.72, 0.3, 0.68), 0.06, "Steel", clips=[((0, -1, 0), 0.08)]),
        Torus(P(0.08, 0.18, 0), 0.74, 0.03, "Gold"),
    ]
    a.both("UpperArm", plates)
    a.both("UpperArm", rivets([P(0.55, 0.3, -0.35), P(0.55, 0.3, 0.35)], 0.04))
    a.both("UpperArm", [Shell((0.15, -0.08, 0), (0.66, 0.26, 0.62), 0.05, "Steel_T2", clips=[((0, -1, 0), 0.22)])], ornament=True)
    a.both("UpperArm", [Torus(P(0.1, 0.0, 0), 0.68, 0.02, "Glow_T2")], ornament=True)
    for side in ("Right", "Left"):
        sx = 1 if side == "Right" else -1
        realm_pair(a, side + "UpperArm", (sx * 0.4, 0.5, 0), 0.0, 1.1, mirror=False, tilt=sx * 30)
    return a


def warrior_chest():
    a = Armor("Warrior_Chest")
    a.add("UpperTorso", Shell((0, 0.02, -0.02), (0.62, 0.6, 0.66), 0.08, "Steel", clips=[((0, 1, 0), 0.55)]))
    # Central ridge, crest gem, gorget.
    a.add("UpperTorso", Blade([(0, 0.4), (0.05, 0.1), (0, -0.45), (-0.05, 0.1)], 0.04, 0.04, 0.015, "Steel", P(0, 0, -0.66), rot_x(0).T, blend=0.03))
    a.add("UpperTorso", gem(P(0, 0.12, -0.7), 0.08))
    a.add("UpperTorso", Torus(P(0, 0.5, 0), 0.42, 0.06, "Gold", blend=0.02))
    # Abdomen plates on the lower torso.
    for i, y in enumerate((0.25, 0.0, -0.25)):
        a.add("LowerTorso", Shell((0, y, -0.02), (0.6 - i * 0.02, 0.2, 0.64), 0.06, "Steel", clips=[((0, 1, 0), y + 0.17), ((0, -1, 0), -y + 0.12)]))
    a.add("LowerTorso", Torus(P(0, 0.42, 0), 0.6, 0.04, "Leather", blend=0.02))
    # Tier 2: gold trim lines, a cape at the back.
    a.group("UpperTorso", Torus(P(0, -0.42, 0), 0.6, 0.025, "Gold_T2"), Torus(P(0, 0.38, 0), 0.55, 0.02, "Glow_T2"))
    a.group("UpperTorso", Blade([(-0.5, 0.45), (0.5, 0.45), (0.56, -1.6), (-0.56, -1.6)], 0.045, 0.07, 0.03, "Cloth_T2", P(0, 0, 0.72)))
    realm_pair(a, "UpperTorso", (0, 0.45, -0.55), 0.35, 0.7, tilt=50)
    return a


def warrior_hands():
    a = Armor("Warrior_Hands")
    a.both("LowerArm", [Tube((0, -0.05, 0), 0.62, 0.62, 0.75, 0.08, "Steel", taper=-0.1)])
    a.both("LowerArm", [Shell((0, 0.42, 0), (0.6, 0.18, 0.6), 0.06, "Steel", blend=0.02)])  # elbow cop
    a.both("LowerArm", [Torus(P(0, -0.38, 0), 0.66, 0.03, "Gold")])
    a.both("Hand", [Shell((0, 0.05, 0), (0.62, 0.62, 0.66), 0.08, "Steel", clips=[((0, -1, 0), 0.3)])])
    a.both("Hand", rivets([P(0, 0.1, -0.62)], 0.05))
    a.both("LowerArm", [Torus(P(0, 0.1, 0), 0.64, 0.02, "Glow_T2")], ornament=True)
    a.both("Hand", [Blade([(-0.3, 0), (0.3, 0), (0.2, -0.3), (-0.2, -0.3)], 0.03, 0.05, 0.012, "Steel_T2", P(0, 0.4, -0.55))], ornament=True)
    return a


def warrior_legs():
    a = Armor("Warrior_Legs")
    # Tassets: front, back and sides, hanging from the lower torso.
    for z, sz in ((-0.62, 1), (0.62, -1)):
        a.add("LowerTorso", Blade([(-0.38, 0.2), (0.38, 0.2), (0.34, -1.1), (-0.34, -1.1)], 0.05, 0.08, 0.02, "Steel", P(0, 0, z)))
        a.add("LowerTorso", chain([P(-0.36, -1.1, z), P(0.36, -1.1, z)], 0.025, 0.025, "Gold", 0.0))
    a.both("UpperLeg", [Shell((0, 0.05, -0.05), (0.62, 0.55, 0.62), 0.07, "Steel", clips=[((0, 0, 1), 0.15)])])
    a.both("LowerLeg", [Tube((0, -0.05, 0), 0.6, 0.62, 0.85, 0.08, "Steel", taper=0.15)])
    a.both("LowerLeg", [Shell((0, 0.45, -0.1), (0.5, 0.24, 0.5), 0.06, "Steel", blend=0.02)])  # knee cop
    a.both("LowerLeg", [Blade([(0, 0.3), (0.04, 0), (0, -0.35), (-0.04, 0)], 0.04, 0.04, 0.026, "Glow", P(0, 0, -0.66))])
    for sx in (-1, 1):
        a.group("LowerTorso", Blade([(-0.06, 0.2), (0.06, 0.2), (0.05, -0.85), (-0.05, -0.85)], 0.05, 0.06, 0.02, "Steel_T2", P(sx * 0.62, 0, 0), rot_y(math.radians(90)).T))
    a.both("UpperLeg", [Torus(P(0, -0.38, 0), 0.6, 0.025, "Gold_T2")], ornament=True)
    return a


def warrior_boots():
    a = Armor("Warrior_Boots")
    a.both("Foot", [Shell((0, 0.05, -0.05), (0.6, 0.62, 0.64), 0.08, "Steel", clips=[((0, 1, 0), 0.45)])])
    a.both("Foot", [Torus(P(0, 0.42, 0.02), 0.6, 0.035, "Gold")])
    a.both("Foot", [Blade([(-0.25, 0), (0.25, 0), (0.15, -0.2), (-0.15, -0.2)], 0.04, 0.05, 0.026, "Steel_T2", P(0, 0.3, -0.62))], ornament=True)
    a.both("Foot", [Torus(P(0, 0.25, 0.0), 0.61, 0.018, "Glow_T2")], ornament=True)
    return a


# ---------------------------------------------------------------------------
# Healer: robes
# ---------------------------------------------------------------------------


def healer_helm():
    a = Armor("Healer_Helm")
    a.add("Head", Torus(P(0, 0.2, 0.02), 0.59, 0.04, "Gold"))
    a.add("Head", gem(P(0, 0.22, -0.62), 0.08))
    a.add("Head", Blade([(0, 0.0), (0.08, 0.08), (0, 0.2), (-0.08, 0.08)], 0.04, 0.04, 0.026, "Gold", P(0, 0.2, -0.6)))
    a.group("Head", Torus(P(0, 0.24, 0.02), 0.6, 0.015, "Glow_T2"))
    for i in (-1, 0, 1):
        a.group("Head", Blade([(0, 0), (0.04, 0.05), (0, 0.28), (-0.04, 0.05)], 0.035, 0.04, 0.026, "Glow_T3", P(i * 0.18, 0.3, -0.58), rot_z(math.radians(-i * 18)).T))
    realm_pair(a, "Head", (0, 0.3, 0.1), 0.58, 0.6)
    return a


def healer_shoulders():
    a = Armor("Healer_Shoulders")
    a.both("UpperArm", [Shell((0.05, 0.3, 0), (0.7, 0.3, 0.66), 0.05, "Cloth", clips=[((0, -1, 0), -0.12)]), Torus(P(0.05, 0.2, 0), 0.68, 0.03, "Gold")])
    a.both("UpperArm", [gem(P(0.55, 0.32, -0.3), 0.05)])
    a.both("UpperArm", [Torus(P(0.05, 0.12, 0), 0.66, 0.018, "Glow_T2")], ornament=True)
    return a


def healer_chest():
    a = Armor("Healer_Chest")
    a.add("UpperTorso", Shell((0, 0, -0.01), (0.6, 0.6, 0.64), 0.06, "Cloth", clips=[((0, 1, 0), 0.52)]))
    # Mantle collar and the gold centre strip with a gem.
    a.add("UpperTorso", Shell((0, 0.4, 0), (0.7, 0.24, 0.72), 0.06, "Cloth", clips=[((0, -1, 0), -0.25)], blend=0.02))
    a.add("UpperTorso", Torus(P(0, 0.3, 0), 0.7, 0.03, "Gold"))
    a.add("UpperTorso", RoundBox(P(0, -0.05, -0.64), P(0.07, 0.45, 0.025), 0.02, "Gold"))
    a.add("UpperTorso", gem(P(0, 0.18, -0.68), 0.08))
    a.add("LowerTorso", Shell((0, 0, 0), (0.62, 0.5, 0.66), 0.06, "Cloth"))
    a.add("LowerTorso", Torus(P(0, 0.25, 0), 0.64, 0.05, "Gold", blend=0.02))
    a.group("UpperTorso", Torus(P(0, 0.24, 0), 0.71, 0.015, "Glow_T2"))
    a.group("UpperTorso", Blade([(-0.45, 0.4), (0.45, 0.4), (0.5, -1.4), (-0.5, -1.4)], 0.045, 0.07, 0.03, "Cloth_T3", P(0, 0, 0.7)))
    realm_pair(a, "UpperTorso", (0, 0.42, 0.5), 0.3, 0.7, tilt=40)
    return a


def healer_hands():
    a = Armor("Healer_Hands")
    a.both("LowerArm", [Tube((0, -0.2, 0), 0.62, 0.62, 0.4, 0.05, "Cloth", taper=-0.2), Torus(P(0, -0.4, 0), 0.68, 0.03, "Gold")])
    a.both("Hand", [Shell((0, 0.05, 0), (0.6, 0.6, 0.64), 0.05, "Leather", clips=[((0, -1, 0), 0.35)])])
    a.both("LowerArm", [Torus(P(0, -0.3, 0), 0.66, 0.018, "Glow_T2")], ornament=True)
    return a


def healer_legs():
    a = Armor("Healer_Legs")
    # Long robe skirt in panels from the waist.
    for i in range(8):
        ang = i / 8 * math.pi * 2
        rot = rot_y(ang)
        a.add("LowerTorso", Blade([(-0.3, 0.1), (0.3, 0.1), (0.38, -2.2), (-0.38, -2.2)], 0.045, 0.06, 0.03, "Cloth", rot @ P(0, 0, -0.66), (rot @ rot_x(math.radians(8))).T))
    a.add("LowerTorso", Torus(P(0, 0.1, 0), 0.68, 0.035, "Gold"))
    a.group("LowerTorso", *[chain([rot_y(i / 8 * math.pi * 2) @ P(-0.36, -2.15, -0.95), rot_y(i / 8 * math.pi * 2) @ P(0.36, -2.15, -0.95)], 0.02, 0.02, "Glow_T2") for i in range(8)])
    return a


def soft_boots(name, tall=False):
    a = Armor(name)
    a.both("Foot", [Shell((0, 0.05, -0.05), (0.58, 0.6, 0.64), 0.07, "Leather", clips=[((0, 1, 0), 0.45)])])
    if tall:
        a.both("LowerLeg", [Tube((0, -0.2, 0), 0.6, 0.6, 0.6, 0.06, "Leather", taper=0.1), Torus(P(0, 0.1, 0), 0.63, 0.03, "Gold")])
    a.both("Foot", [Torus(P(0, 0.4, 0.02), 0.58, 0.025, "Gold")])
    a.both("Foot", [Torus(P(0, 0.3, 0.0), 0.59, 0.015, "Glow_T2")], ornament=True)
    return a


# ---------------------------------------------------------------------------
# Archer: leather
# ---------------------------------------------------------------------------


def archer_helm():
    a = Armor("Archer_Helm")
    # Hood over the head and back, the face left open.
    a.add("Head", Shell((0, 0.06, 0.12), (0.64, 0.64, 0.66), 0.07, "Leather", clips=[((0, 0, -1), 0.4)]))
    a.add("Head", Torus(P(0, 0.05, -0.38), 0.5, 0.03, "Cloth"))
    a.group("Head", Torus(P(0, 0.05, -0.4), 0.51, 0.015, "Glow_T2"))
    a.group("Head", Blade([(0, 0), (0.06, 0.1), (0.05, 0.55), (0, 0.65), (-0.04, 0.5), (-0.05, 0.1)], 0.02, 0.04, 0.01, "Gold_T3", P(0.6, 0.25, 0.2), rot_z(math.radians(-25)).T))
    return a


def archer_shoulders():
    a = Armor("Archer_Shoulders")
    a.add("LeftUpperArm", Mirrored(Shell((0.08, 0.3, 0), (0.74, 0.34, 0.7), 0.06, "Leather", clips=[((0, -1, 0), -0.08)])))
    a.add("LeftUpperArm", Mirrored(Torus(P(0.08, 0.18, 0), 0.72, 0.03, "Gold")))
    a.add("RightUpperArm", Torus(P(0, 0.35, 0), 0.6, 0.04, "Leather"))
    a.group("LeftUpperArm", Mirrored(Torus(P(0.08, 0.1, 0), 0.7, 0.016, "Glow_T2")))
    realm_pair(a, "LeftUpperArm", (-0.4, 0.5, 0), 0.0, 1.0, mirror=False, tilt=-30)
    return a


def archer_chest():
    a = Armor("Archer_Chest")
    a.add("UpperTorso", Shell((0, 0, -0.01), (0.6, 0.6, 0.64), 0.06, "Leather", clips=[((0, 1, 0), 0.52)]))
    # Diagonal strap front and back, collar.
    for z in (-0.66, 0.66):
        a.add("UpperTorso", chain([P(-0.5, 0.45, z), P(0.5, -0.45, z)], 0.04, 0.04, "Leather", 0.0))
    a.add("UpperTorso", gem(P(0, 0, -0.7), 0.06))
    a.add("UpperTorso", Shell((0, 0.45, 0.15), (0.55, 0.22, 0.55), 0.06, "Cloth", clips=[((0, -1, 0), -0.3)], blend=0.02))
    # Quiver on the back with glowing fletches.
    a.add("UpperTorso", cone((-0.25, -0.5, 0.75), (0.3, 0.75, 0.85), 0.16, 0.18, "Leather", 0.0))
    for i in range(4):
        a.add("UpperTorso", ball((0.25 + (i - 1.5) * 0.06, 0.95, 0.88 + (i % 2) * 0.04), (0.04, 0.09, 0.02), "Glow", 0.0))
    a.add("LowerTorso", Shell((0, 0, 0), (0.6, 0.45, 0.64), 0.05, "Leather"))
    a.add("LowerTorso", Torus(P(0, 0.3, 0), 0.62, 0.04, "Gold", blend=0.02))
    a.group("UpperTorso", Blade([(-0.5, 0.45), (0.05, 0.45), (0.0, -1.5), (-0.55, -1.5)], 0.04, 0.06, 0.028, "Cloth_T2", P(0, 0, 0.72)))
    return a


def archer_hands():
    a = Armor("Archer_Hands")
    a.both("LowerArm", [Tube((0, -0.05, 0), 0.6, 0.6, 0.7, 0.06, "Leather", taper=-0.1)])
    for y in (-0.25, 0.1):
        a.both("LowerArm", [Torus(P(0, y, 0), 0.63, 0.025, "Leather")])
    a.both("Hand", [Shell((0, 0.05, 0), (0.6, 0.6, 0.64), 0.05, "Leather", clips=[((0, -1, 0), 0.3)])])
    a.both("LowerArm", [RoundBox(P(0, -0.05, -0.62), P(0.2, 0.25, 0.03), 0.02, "Gold_T2")], ornament=True)
    return a


def archer_legs():
    a = Armor("Archer_Legs")
    a.add("LowerTorso", Shell((0, -0.1, 0), (0.6, 0.45, 0.62), 0.05, "Cloth"))
    a.both("UpperLeg", [Tube((0, 0, 0), 0.6, 0.6, 0.95, 0.05, "Cloth")])
    a.both("LowerLeg", [Shell((0, 0.35, -0.12), (0.45, 0.26, 0.45), 0.05, "Leather")])
    a.both("UpperLeg", [RoundBox(P(0.55, 0, 0), P(0.06, 0.25, 0.2), 0.03, "Leather", blend=0.02)])  # thigh pouch
    a.both("LowerLeg", [Torus(P(0, 0.2, 0), 0.6, 0.015, "Glow_T2")], ornament=True)
    return a


# ---------------------------------------------------------------------------
# Mage: arcane coat
# ---------------------------------------------------------------------------


def mage_helm():
    a = Armor("Mage_Helm")
    # A wide-brimmed pointed hat leaning back.
    a.add("Head", Shell((0, 0.38, 0), (1.05, 0.08, 1.05), 0.05, "Cloth", clips=[((0, -1, 0), -0.36)]))
    pts = [P(0, 0.4, 0), P(0, 0.75, 0.05), P(0, 1.05, 0.18), P(0, 1.3, 0.38)]
    a.add("Head", chain(pts, 0.55, 0.04, "Cloth", 0.06))
    a.add("Head", Torus(P(0, 0.48, 0), 0.54, 0.04, "Gold", blend=0.02))
    a.group("Head", Torus(P(0, 0.56, 0), 0.5, 0.015, "Glow_T2"))
    a.group("Head", ball(pts[-1] + P(0, 0.05, 0.03), 0.07, "Glow_T3", 0.0))
    return a


def mage_shoulders():
    a = Armor("Mage_Shoulders")
    a.both("UpperArm", [Shell((0.06, 0.3, 0), (0.7, 0.3, 0.66), 0.05, "Cloth", clips=[((0, -1, 0), -0.1)]), Torus(P(0.06, 0.2, 0), 0.68, 0.025, "Glow")])
    a.both("UpperArm", [gem(P(0.62, 0.3, 0), 0.05)], ornament=True)
    return a


def mage_chest():
    a = Armor("Mage_Chest")
    a.add("UpperTorso", Shell((0, 0, -0.01), (0.6, 0.6, 0.64), 0.06, "Cloth", clips=[((0, 1, 0), 0.52)]))
    for sx in (-1, 1):
        a.add("UpperTorso", RoundBox(P(sx * 0.14, -0.02, -0.63), P(0.04, 0.48, 0.025), 0.015, "Gold"))
    a.add("UpperTorso", gem(P(0, 0.2, -0.68), 0.08))
    a.add("LowerTorso", Shell((0, 0, 0), (0.62, 0.48, 0.66), 0.06, "Cloth"))
    a.add("LowerTorso", Torus(P(0, 0.28, 0), 0.64, 0.05, "Leather", blend=0.02))
    # Tier 2: a high arcane collar; tier 3: a back cape.
    for sx in (-1, 1):
        a.group("UpperTorso", Blade([(-0.18, 0), (0.18, 0), (0.22, 0.42), (-0.14, 0.38)], 0.045, 0.06, 0.03, "Cloth_T2", P(sx * 0.2, 0.5, 0.3), (rot_y(math.radians(sx * 22)) @ rot_x(math.radians(-12))).T))
    a.group("UpperTorso", Torus(P(0, 0.45, 0.1), 0.45, 0.015, "Glow_T2"))
    a.group("UpperTorso", Blade([(-0.48, 0.42), (0.48, 0.42), (0.52, -1.5), (-0.52, -1.5)], 0.045, 0.07, 0.03, "Cloth_T3", P(0, 0, 0.72)))
    return a


def mage_hands():
    a = Armor("Mage_Hands")
    a.both("LowerArm", [Tube((0, -0.15, 0), 0.64, 0.64, 0.5, 0.05, "Cloth", taper=-0.3), Torus(P(0, -0.38, 0), 0.75, 0.025, "Glow")])
    a.both("Hand", [Shell((0, 0.05, 0), (0.6, 0.6, 0.64), 0.04, "Leather", clips=[((0, -1, 0), 0.35)])])
    a.both("LowerArm", [Torus(P(0, -0.25, 0), 0.72, 0.015, "Gold_T2")], ornament=True)
    return a


def mage_legs():
    a = Armor("Mage_Legs")
    # An open robe skirt (no front panel).
    for i in range(1, 7):
        ang = i / 7 * math.pi * 2
        rot = rot_y(ang)
        a.add("LowerTorso", Blade([(-0.32, 0.1), (0.32, 0.1), (0.4, -2.1), (-0.4, -2.1)], 0.045, 0.06, 0.03, "Cloth", rot @ P(0, 0, -0.66), (rot @ rot_x(math.radians(9))).T))
    a.add("LowerTorso", Torus(P(0, 0.12, 0), 0.68, 0.035, "Gold"))
    a.both("UpperLeg", [Tube((0, 0, 0), 0.6, 0.6, 0.95, 0.04, "Cloth")])
    a.group("LowerTorso", *[chain([rot_y(i / 7 * math.pi * 2) @ P(-0.38, -2.05, -0.98), rot_y(i / 7 * math.pi * 2) @ P(0.38, -2.05, -0.98)], 0.02, 0.02, "Glow_T2") for i in range(1, 7)])
    return a


# ---------------------------------------------------------------------------
# Jewellery (any class)
# ---------------------------------------------------------------------------


def necklace():
    a = Armor("Necklace")
    # A chain around the neck line and a pendant on the chest.
    a.add("UpperTorso", Torus(P(0, 0.48, -0.05), 0.36, 0.022, "Gold", rot_x(math.radians(-20)).T))
    a.add("UpperTorso", chain([P(-0.25, 0.38, -0.55), P(0, 0.12, -0.68), P(0.25, 0.38, -0.55)], 0.018, 0.018, "Gold", 0.0))
    a.add("UpperTorso", ball((0, 0.02, -0.7), (0.09, 0.11, 0.04), "Glow", 0.0))
    a.group("UpperTorso", Torus(P(0, 0.02, -0.7), 0.11, 0.018, "Gold_T2", rot_x(math.radians(90)).T))
    realm_pair(a, "UpperTorso", (0, 0.05, -0.72), 0.12, 0.35, tilt=60)
    return a


def earrings():
    a = Armor("Earrings")
    for sx in (-1, 1):
        a.add("Head", ball((sx * 0.52, -0.12, 0.02), 0.035, "Gold", 0.0))
        a.add("Head", chain([P(sx * 0.53, -0.14, 0.02), P(sx * 0.54, -0.24, 0.02)], 0.015, 0.015, "Gold", 0.0))
        a.add("Head", ball((sx * 0.54, -0.3, 0.02), (0.045, 0.07, 0.045), "Glow", 0.0))
        a.group("Head", Torus(P(sx * 0.54, -0.3, 0.02), 0.06, 0.012, "Gold_T2", rot_z(math.radians(90)).T))
    return a


def ring():
    a = Armor("Ring")
    a.add("Hand", Torus(P(0, -0.15, 0), 0.6, 0.06, "Gold"))
    a.add("Hand", gem(P(0, -0.15, -0.62), 0.1))
    a.group("Hand", Torus(P(0, -0.15, -0.62), 0.12, 0.025, "Gold_T2", rot_x(math.radians(90)).T))
    return a


BUILDERS = {
    "Warrior_Helm": warrior_helm,
    "Warrior_Shoulders": warrior_shoulders,
    "Warrior_Chest": warrior_chest,
    "Warrior_Hands": warrior_hands,
    "Warrior_Legs": warrior_legs,
    "Warrior_Boots": warrior_boots,
    "Healer_Helm": healer_helm,
    "Healer_Shoulders": healer_shoulders,
    "Healer_Chest": healer_chest,
    "Healer_Hands": healer_hands,
    "Healer_Legs": healer_legs,
    "Healer_Boots": lambda: soft_boots("Healer_Boots"),
    "Archer_Helm": archer_helm,
    "Archer_Shoulders": archer_shoulders,
    "Archer_Chest": archer_chest,
    "Archer_Hands": archer_hands,
    "Archer_Legs": archer_legs,
    "Archer_Boots": lambda: soft_boots("Archer_Boots", tall=True),
    "Mage_Helm": mage_helm,
    "Mage_Shoulders": mage_shoulders,
    "Mage_Chest": mage_chest,
    "Mage_Hands": mage_hands,
    "Mage_Legs": mage_legs,
    "Mage_Boots": lambda: soft_boots("Mage_Boots", tall=True),
    "Necklace": necklace,
    "Earrings": earrings,
    "Ring": ring,
}


def main():
    names = sys.argv[1:] or list(BUILDERS)
    for name in names:
        total = BUILDERS[name]().export()
        print(f"{name}: {total} tris")


if __name__ == "__main__":
    main()
