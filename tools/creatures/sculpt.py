"""
Creature sculpting toolkit (authoring aid, not shipped; PLAN.md D-52).

Creatures are sculpted from signed-distance primitives (tapered capsules,
ellipsoids) blended with a smooth union, so the skin is one continuous
surface instead of separate balls. Each primitive belongs to a bone (for
skinning) and a region (for colour / material in game). The surface is
extracted with surface nets, smoothed, skinned (up to 4 bones per vertex,
weights from how close each bone's primitives are) and written as glTF
(.gltf with embedded buffers) for Studio's 3D Importer (File > Import 3D).

Coordinates are Roblox studs at size 1: Y up, the creature faces -Z, the
ground at y = 0.

Usage: see tools/creatures/build.py.
"""
import base64, json, math
import numpy as np

# ---------------------------------------------------------------------------
# Math helpers
# ---------------------------------------------------------------------------


def v3(x, y, z):
    return np.array([x, y, z], dtype=np.float64)


def rot_x(a):
    c, s = math.cos(a), math.sin(a)
    return np.array([[1, 0, 0], [0, c, -s], [0, s, c]], dtype=np.float64)


def rot_y(a):
    c, s = math.cos(a), math.sin(a)
    return np.array([[c, 0, s], [0, 1, 0], [-s, 0, c]], dtype=np.float64)


def rot_z(a):
    c, s = math.cos(a), math.sin(a)
    return np.array([[c, -s, 0], [s, c, 0], [0, 0, 1]], dtype=np.float64)


def quat_from_matrix(m):
    t = m[0, 0] + m[1, 1] + m[2, 2]
    if t > 0:
        s = math.sqrt(t + 1.0) * 2
        w = 0.25 * s
        x = (m[2, 1] - m[1, 2]) / s
        y = (m[0, 2] - m[2, 0]) / s
        z = (m[1, 0] - m[0, 1]) / s
    elif m[0, 0] > m[1, 1] and m[0, 0] > m[2, 2]:
        s = math.sqrt(1.0 + m[0, 0] - m[1, 1] - m[2, 2]) * 2
        w = (m[2, 1] - m[1, 2]) / s
        x = 0.25 * s
        y = (m[0, 1] + m[1, 0]) / s
        z = (m[0, 2] + m[2, 0]) / s
    elif m[1, 1] > m[2, 2]:
        s = math.sqrt(1.0 + m[1, 1] - m[0, 0] - m[2, 2]) * 2
        w = (m[0, 2] - m[2, 0]) / s
        x = (m[0, 1] + m[1, 0]) / s
        y = 0.25 * s
        z = (m[1, 2] + m[2, 1]) / s
    else:
        s = math.sqrt(1.0 + m[2, 2] - m[0, 0] - m[1, 1]) * 2
        w = (m[1, 0] - m[0, 1]) / s
        x = (m[0, 2] + m[2, 0]) / s
        y = (m[1, 2] + m[2, 1]) / s
        z = 0.25 * s
    q = np.array([x, y, z, w])
    return q / np.linalg.norm(q)


# ---------------------------------------------------------------------------
# Skeleton
# ---------------------------------------------------------------------------


class Bone:
    """A joint: `pos` and `rot` are global (bind pose)."""

    def __init__(self, name, parent, pos, rot=None):
        self.name = name
        self.parent = parent
        self.pos = np.asarray(pos, dtype=np.float64)
        self.rot = np.eye(3) if rot is None else np.asarray(rot, dtype=np.float64)

    def local(self):
        """Translation and rotation relative to the parent bone."""
        if self.parent is None:
            return self.pos.copy(), self.rot.copy()
        prot = self.parent.rot
        t = prot.T @ (self.pos - self.parent.pos)
        r = prot.T @ self.rot
        return t, r


class Skeleton:
    def __init__(self):
        self.bones = []
        self.by_name = {}

    def add(self, name, parent, pos, rot=None):
        p = self.by_name[parent] if isinstance(parent, str) else parent
        b = Bone(name, p, pos, rot)
        self.bones.append(b)
        self.by_name[name] = b
        return b

    def __getitem__(self, name):
        return self.by_name[name]

    def chain_down(self, names, parent, points, splay=0.0):
        """
        A limb whose bones point down their local -Y: bone i sits at
        points[i] and the next joint lies at (0, -L, 0) in its frame. Bones
        bend about local X (pitch in the limb's plane, which is yawed by
        `splay` radians). Returns the bones and their rest angles (from
        vertical, relative to the previous bone, radians).
        """
        bones, angles = [], []
        plane = rot_y(splay)
        prev_abs = 0.0
        p = parent
        for i, name in enumerate(names):
            a, b = np.asarray(points[i], float), np.asarray(points[i + 1], float)
            d = plane.T @ (b - a)  # into the limb plane: x across, -z forward
            # Angle from straight down towards forward (-Z), as CFrame.Angles(a, 0, 0).
            ang = math.atan2(-d[2], -d[1])
            rot = plane @ rot_x(ang)
            bone = self.add(name, p, a, rot)
            bones.append(bone)
            angles.append(ang - prev_abs)
            prev_abs = ang
            p = bone
        return bones, angles


# ---------------------------------------------------------------------------
# Primitives (signed distance, vectorised over (N, 3) points)
# ---------------------------------------------------------------------------


class Prim:
    def __init__(self, bone, region, blend):
        self.bone = bone
        self.region = region
        self.blend = blend


class RoundCone(Prim):
    """Capsule from a (radius ra) to b (radius rb), smooth taper."""

    def __init__(self, a, b, ra, rb, bone, region="Hide", blend=0.15):
        super().__init__(bone, region, blend)
        self.a, self.b = np.asarray(a, float), np.asarray(b, float)
        self.ra, self.rb = ra, rb

    def sdf(self, p):
        ba = self.b - self.a
        l2 = float(ba @ ba)
        rr = self.ra - self.rb
        a2 = l2 - rr * rr
        il2 = 1.0 / l2
        pa = p - self.a
        y = pa @ ba
        z = y - l2
        xv = pa * l2 - np.outer(y, ba)
        x2 = np.einsum("ij,ij->i", xv, xv)
        y2 = y * y * l2
        z2 = z * z * l2
        k = np.sign(rr) * rr * rr * x2
        out = np.empty(len(p))
        c1 = np.sign(z) * a2 * z2 > k
        c2 = np.sign(y) * a2 * y2 < k
        c3 = ~(c1 | c2)
        out[c1] = np.sqrt(x2[c1] + z2[c1]) * il2 - self.rb
        out[c2] = np.sqrt(x2[c2] + y2[c2]) * il2 - self.ra
        out[c3] = (np.sqrt(x2[c3] * a2 * il2) + y[c3] * rr) * il2 - self.ra
        return out

    def bounds(self):
        r = max(self.ra, self.rb)
        return np.minimum(self.a, self.b) - r, np.maximum(self.a, self.b) + r


class Ellipsoid(Prim):
    def __init__(self, c, r, bone, region="Hide", blend=0.15, rot=None):
        super().__init__(bone, region, blend)
        self.c = np.asarray(c, float)
        self.r = np.asarray(r, float)
        self.rot = np.eye(3) if rot is None else np.asarray(rot, float)

    def sdf(self, p):
        q = (p - self.c) @ self.rot  # into local frame
        k0 = np.linalg.norm(q / self.r, axis=1)
        k1 = np.linalg.norm(q / (self.r * self.r), axis=1)
        return k0 * (k0 - 1.0) / np.maximum(k1, 1e-9)

    def bounds(self):
        m = np.max(self.r)
        return self.c - m, self.c + m


def smin(a, b, k):
    """Polynomial smooth minimum (blend radius k)."""
    if k <= 0:
        return np.minimum(a, b)
    h = np.clip(0.5 + 0.5 * (b - a) / k, 0.0, 1.0)
    return b * (1 - h) + a * h - k * h * (1 - h)


# ---------------------------------------------------------------------------
# Surface extraction: naive surface nets
# ---------------------------------------------------------------------------


def surface_nets(field, origin, step):
    """field: (nx, ny, nz) SDF samples. Returns vertices (V,3), quads (Q,4)."""
    nx, ny, nz = field.shape
    inside = field < 0
    # Cells: corners (i..i+1, j..j+1, k..k+1).
    c = np.zeros((nx - 1, ny - 1, nz - 1), dtype=np.int8)
    for dx in (0, 1):
        for dy in (0, 1):
            for dz in (0, 1):
                c += inside[dx : nx - 1 + dx, dy : ny - 1 + dy, dz : nz - 1 + dz]
    active = (c > 0) & (c < 8)
    idx = -np.ones(active.shape, dtype=np.int64)
    cells = np.argwhere(active)
    idx[active] = np.arange(len(cells))
    # Vertex = mean of edge crossings in the cell.
    acc = np.zeros((len(cells), 3))
    cnt = np.zeros(len(cells))
    corners = [(dx, dy, dz) for dx in (0, 1) for dy in (0, 1) for dz in (0, 1)]
    edges = [(a, b) for a in range(8) for b in range(a + 1, 8) if sum(abs(np.subtract(corners[a], corners[b]))) == 1]
    ci, cj, ck = cells[:, 0], cells[:, 1], cells[:, 2]
    for a, b in edges:
        pa, pb = corners[a], corners[b]
        fa = field[ci + pa[0], cj + pa[1], ck + pa[2]]
        fb = field[ci + pb[0], cj + pb[1], ck + pb[2]]
        cross = (fa < 0) != (fb < 0)
        t = np.where(cross, fa / np.where(cross, fa - fb, 1), 0)
        pos = np.stack([ci + pa[0] + t * (pb[0] - pa[0]), cj + pa[1] + t * (pb[1] - pa[1]), ck + pa[2] + t * (pb[2] - pa[2])], 1)
        acc[cross] += pos[cross]
        cnt[cross] += 1
    verts = acc / cnt[:, None]
    verts = origin + verts * step
    # Quads: for each grid edge with a sign change, join the 4 cells around it.
    quads = []
    for axis in range(3):
        sl0 = [slice(None)] * 3
        sl1 = [slice(None)] * 3
        sl0[axis] = slice(0, -1)
        sl1[axis] = slice(1, None)
        a = inside[tuple(sl0)]
        b = inside[tuple(sl1)]
        diff = a != b
        pts = np.argwhere(diff)
        flip = a[diff]  # inside -> outside along +axis
        o1, o2 = [ax for ax in range(3) if ax != axis]
        # Cells sharing this edge: offsets 0/-1 on the two other axes.
        ok = (pts[:, o1] > 0) & (pts[:, o2] > 0) & (pts[:, o1] < [nx, ny, nz][o1] - 1) & (pts[:, o2] < [nx, ny, nz][o2] - 1)
        pts, flip = pts[ok], flip[ok]

        def cell(d1, d2):
            q = pts.copy()
            q[:, o1] -= d1
            q[:, o2] -= d2
            return idx[q[:, 0], q[:, 1], q[:, 2]]

        v00, v10, v11, v01 = cell(1, 1), cell(0, 1), cell(0, 0), cell(1, 0)
        quad = np.stack([v00, v10, v11, v01], 1)
        quad[~flip] = quad[~flip][:, ::-1]
        if axis == 1:
            quad = quad[:, ::-1]
        quads.append(quad)
    quads = np.concatenate(quads)
    quads = quads[(quads >= 0).all(1)]
    return verts, quads


def quads_to_tris(quads, verts):
    # Split along the shorter diagonal.
    a, b, c, d = quads.T
    d1 = np.linalg.norm(verts[a] - verts[c], axis=1)
    d2 = np.linalg.norm(verts[b] - verts[d], axis=1)
    t1 = np.where((d1 <= d2)[:, None], np.stack([a, b, c], 1), np.stack([a, b, d], 1))
    t2 = np.where((d1 <= d2)[:, None], np.stack([a, c, d], 1), np.stack([b, c, d], 1))
    return np.concatenate([t1, t2])


def vertex_normals(verts, tris):
    n = np.zeros_like(verts)
    fn = np.cross(verts[tris[:, 1]] - verts[tris[:, 0]], verts[tris[:, 2]] - verts[tris[:, 0]])
    for i in range(3):
        np.add.at(n, tris[:, i], fn)
    l = np.linalg.norm(n, axis=1, keepdims=True)
    return n / np.maximum(l, 1e-12)


def taubin(verts, tris, iterations=6, lam=0.5, mu=-0.53):
    """Smoothing that does not shrink the shape."""
    nbr_sum = np.zeros_like(verts)
    deg = np.zeros(len(verts))
    edges = np.concatenate([tris[:, [0, 1]], tris[:, [1, 2]], tris[:, [2, 0]]])
    edges = np.concatenate([edges, edges[:, ::-1]])
    for _ in range(iterations):
        for f in (lam, mu):
            nbr_sum[:] = 0
            deg[:] = 0
            np.add.at(nbr_sum, edges[:, 0], verts[edges[:, 1]])
            np.add.at(deg, edges[:, 0], 1)
            avg = nbr_sum / np.maximum(deg, 1)[:, None]
            verts = verts + f * (avg - verts)
    return verts


# ---------------------------------------------------------------------------
# Creature: primitives + skeleton -> skinned, regioned mesh -> glTF
# ---------------------------------------------------------------------------


class Creature:
    def __init__(self, name, skeleton, step=0.06):
        self.name = name
        self.skeleton = skeleton
        self.prims = []
        self.solids = []  # hard-unioned pieces (eyes): never blended
        self.step = step

    def add(self, prim):
        self.prims.append(prim)
        return prim

    def solid(self, prim):
        self.solids.append(prim)
        return prim

    def group(self, prims):
        """
        Pieces blended with each other but not with the body: their own
        surface (and MeshPart per region), so the game can remove them
        (optional wings, stingers, horns) without leaving a hole.
        """
        self.solids.append(list(prims))
        return prims

    def _field(self, pts, prims):
        d = None
        for prim in prims:
            s = prim.sdf(pts)
            d = s if d is None else smin(d, s, prim.blend)
        return d

    def build(self):
        step = self.step
        meshes = []
        # The body (blended) and each solid / group separately (own region /
        # mesh), each sampled over its own bounds.
        groups = [("blend", self.prims)] + [("solid", s if isinstance(s, list) else [s]) for s in self.solids]
        for kind, prims in groups:
            lo = np.min([p.bounds()[0] for p in prims], axis=0) - 0.3
            hi = np.max([p.bounds()[1] for p in prims], axis=0) + 0.3
            shape = np.ceil((hi - lo) / step).astype(int) + 1
            gx, gy, gz = [lo[i] + np.arange(shape[i]) * step for i in range(3)]
            pts = np.stack(np.meshgrid(gx, gy, gz, indexing="ij"), -1).reshape(-1, 3)
            field = self._field(pts, prims).reshape(shape)
            verts, quads = surface_nets(field, lo, step)
            tris = quads_to_tris(quads, verts)
            verts = taubin(verts, tris, iterations=4 if kind == "blend" else 2)
            meshes.append((prims, verts, tris))
        return meshes

    def skin_and_regions(self, prims, verts):
        """Per-vertex bone weights (top 4) and region from the primitives."""
        bone_index = {b.name: i for i, b in enumerate(self.skeleton.bones)}
        d = np.stack([p.sdf(verts) for p in prims], 1)  # (V, P)
        region = np.array([p.region for p in prims])[np.argmin(d, 1)]
        # Influence falls off with distance from each primitive's surface.
        infl = np.exp(-np.maximum(d, 0) / 0.08) * (d < 0.35)
        nb = len(self.skeleton.bones)
        w = np.zeros((len(verts), nb))
        for j, p in enumerate(prims):
            w[:, bone_index[p.bone]] += infl[:, j]
        nearest = np.argmin(d, 1)
        for j, p in enumerate(prims):
            m = nearest == j
            w[m, bone_index[p.bone]] += 1e-3
        order = np.argsort(-w, 1)[:, :4]
        top = np.take_along_axis(w, order, 1)
        top = top / np.maximum(top.sum(1, keepdims=True), 1e-12)
        return order.astype(np.uint16), top.astype(np.float32), region

    def export(self, path, preview=None):
        meshes = self.build()
        out_meshes = []  # (name, verts, normals, uvs, tris, joints, weights)
        for prims, verts, tris in meshes:
            joints, weights, region = self.skin_and_regions(prims, verts)
            # Split into one mesh per region (each becomes a MeshPart).
            tri_region = region[tris[:, 0]]
            for r in sorted(set(tri_region)):
                t = tris[tri_region == r]
                used = np.unique(t)
                remap = -np.ones(len(verts), dtype=np.int64)
                remap[used] = np.arange(len(used))
                v = verts[used]
                tt = remap[t]
                n = vertex_normals(v, tt)
                # Box-projected UVs (material textures tile across the skin).
                ax = np.argmax(np.abs(n), 1)
                uv = np.where(
                    (ax == 0)[:, None], v[:, [2, 1]], np.where((ax == 1)[:, None], v[:, [0, 2]], v[:, [0, 1]])
                ) * 0.5
                # One mesh per region: merge with an earlier piece of the
                # same region (eyes, claws...), so each region is one MeshPart.
                for k, m in enumerate(out_meshes):
                    if m[0] == r:
                        base = len(m[1])
                        out_meshes[k] = (
                            r,
                            np.concatenate([m[1], v]),
                            np.concatenate([m[2], n]),
                            np.concatenate([m[3], uv]),
                            np.concatenate([m[4], tt + base]),
                            np.concatenate([m[5], joints[used]]),
                            np.concatenate([m[6], weights[used]]),
                        )
                        break
                else:
                    out_meshes.append((r, v, n, uv, tt, joints[used], weights[used]))
        write_gltf(path, self.skeleton, out_meshes)
        if preview:
            render_preview(preview, out_meshes, self.name)
        tris = sum(len(m[4]) for m in out_meshes)
        return {m[0]: len(m[4]) for m in out_meshes}, tris


# ---------------------------------------------------------------------------
# glTF writer
# ---------------------------------------------------------------------------


def write_gltf(path, skeleton, meshes):
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

    bones = skeleton.bones
    nodes = []
    for b in bones:
        t, r = b.local()
        node = {"name": b.name, "translation": t.tolist(), "rotation": quat_from_matrix(r).tolist()}
        kids = [i for i, c in enumerate(bones) if c.parent is b]
        if kids:
            node["children"] = kids
        nodes.append(node)
    # Inverse bind matrices (column-major).
    ibm = []
    for b in bones:
        m = np.eye(4)
        m[:3, :3] = b.rot
        m[:3, 3] = b.pos
        ibm.append(np.linalg.inv(m).T.reshape(-1))
    ibm_acc = add(np.array(ibm, dtype=np.float32), 5126, "MAT4")
    skin = {"joints": list(range(len(bones))), "inverseBindMatrices": ibm_acc, "skeleton": 0}
    gl_meshes = []
    mesh_nodes = []
    for name, v, n, uv, t, j, w in meshes:
        prim = {
            "attributes": {
                "POSITION": add(v.astype(np.float32), 5126, "VEC3", 34962, True),
                "NORMAL": add(n.astype(np.float32), 5126, "VEC3", 34962),
                "TEXCOORD_0": add(uv.astype(np.float32), 5126, "VEC2", 34962),
                "JOINTS_0": add(j.astype(np.uint16), 5123, "VEC4", 34962),
                "WEIGHTS_0": add(w.astype(np.float32), 5126, "VEC4", 34962),
            },
            "indices": add(t.astype(np.uint32).reshape(-1), 5125, "SCALAR", 34963),
        }
        gl_meshes.append({"name": name, "primitives": [prim]})
        nodes.append({"name": name, "mesh": len(gl_meshes) - 1, "skin": 0})
        mesh_nodes.append(len(nodes) - 1)
    roots = [i for i, b in enumerate(bones) if b.parent is None]
    gltf = {
        "asset": {"version": "2.0", "generator": "riftbound tools/creatures/sculpt.py"},
        "scene": 0,
        "scenes": [{"nodes": roots + mesh_nodes}],
        "nodes": nodes,
        "meshes": gl_meshes,
        "skins": [skin],
        "accessors": accessors,
        "bufferViews": views,
        "buffers": [
            {
                "byteLength": len(buf),
                "uri": "data:application/octet-stream;base64," + base64.b64encode(bytes(buf)).decode(),
            }
        ],
    }
    with open(path, "w") as f:
        json.dump(gltf, f)


# ---------------------------------------------------------------------------
# Preview
# ---------------------------------------------------------------------------

PREVIEW_COLORS = {
    "Hide": (0.36, 0.33, 0.38),
    "Under": (0.62, 0.58, 0.55),
    "Dark": (0.18, 0.16, 0.19),
    "Horn": (0.88, 0.84, 0.74),
    "Eye": (1.0, 0.55, 0.2),
    "Glow": (1.0, 0.45, 0.15),
    "Scale": (0.3, 0.42, 0.28),
    "Mane": (0.3, 0.12, 0.08),
    "Metal": (0.55, 0.56, 0.6),
    "Blade": (0.82, 0.84, 0.88),
    "Cloth": (0.35, 0.08, 0.1),
    "Wing": (0.28, 0.24, 0.3),
    "Wing2": (0.28, 0.24, 0.3),
    "Tuft": (0.3, 0.12, 0.08),
    "Sting": (0.2, 0.18, 0.16),
    "Spikes": (0.55, 0.85, 0.95),
    "Horns": (0.88, 0.84, 0.74),
    "Petal": (0.6, 0.85, 1.0),
}


def render_preview(path, meshes, title, palette=None):
    import matplotlib

    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    from matplotlib.collections import PolyCollection

    palette = palette or PREVIEW_COLORS
    light = np.array([0.4, 0.8, -0.45])
    light /= np.linalg.norm(light)
    views = [
        ("side", lambda p: p[:, [2, 1]] * [-1, 1], np.array([1.0, 0, 0])),
        ("front 3/4", None, None),
        ("top", lambda p: p[:, [0, 2]] * [1, -1], np.array([0, 1.0, 0])),
    ]
    fig, axes = plt.subplots(1, 3, figsize=(24, 8))
    allv = np.concatenate([m[1] for m in meshes])
    for ax, (label, proj, viewdir) in zip(axes, views):
        polys, cols, depth = [], [], []
        for name, v, n, uv, t, j, w in meshes:
            if label == "front 3/4":
                r = rot_y(math.radians(-35)) @ rot_x(math.radians(-12))
                pv = v @ r.T
                pn = n @ r.T
                p2 = pv[:, [0, 1]]
                dview = pv[:, 2]
                facing = np.array([0, 0, -1.0])
            else:
                pv, pn = v, n
                p2 = proj(v)
                dview = -(v @ viewdir)
                facing = viewdir
            region = name
            base = np.array(palette.get(region, (0.5, 0.5, 0.5)))
            fn = pn[t].mean(1)
            fn /= np.maximum(np.linalg.norm(fn, axis=1, keepdims=True), 1e-9)
            vis = fn @ facing > -0.05
            shade = np.clip(fn @ (light if label != "front 3/4" else (r @ light)), 0, 1)
            emis = 1.0 if region in ("Eye", "Glow") else 0.0
            c = base[None, :] * (0.35 + 0.75 * shade[:, None]) * (1 - emis) + base[None, :] * emis
            for tri, col, dd in zip(p2[t][vis], np.clip(c[vis], 0, 1), dview[t][vis].mean(1)):
                polys.append(tri)
                cols.append(col)
                depth.append(dd)
        order = np.argsort(depth)[::-1]
        pc = PolyCollection([polys[i] for i in order], facecolors=[cols[i] for i in order], edgecolors="none")
        ax.add_collection(pc)
        if polys:
            pts = np.concatenate(polys)
            ax.set_xlim(pts[:, 0].min() - 0.3, pts[:, 0].max() + 0.3)
            ax.set_ylim(pts[:, 1].min() - 0.3, pts[:, 1].max() + 0.3)
        ax.set_aspect("equal")
        ax.set_facecolor("#1d2128")
        ax.set_title(label)
        ax.set_xticks([])
        ax.set_yticks([])
    fig.suptitle(title)
    fig.tight_layout()
    fig.savefig(path, dpi=70)
    plt.close(fig)
