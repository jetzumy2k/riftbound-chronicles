"""
Builds the creature meshes (authoring aid, not shipped; PLAN.md D-52):

    python tools/creatures/build.py [name ...]

For each creature: build/creatures/<Name>.gltf (import in Studio with
File > Import 3D, then follow docs/DEVELOPMENT.md "Creature meshes"),
build/creatures/<Name>.png (shaded preview) and the skeleton data the game
animates with, written to src/shared/Animation/CreatureMeshes.luau.

Sizes are studs at creature size 1, ground at y = 0, facing -Z.
"""
import json, math, os, sys
import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import sculpt as S  # noqa: E402
import emit_lua  # noqa: E402

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "build", "creatures")

P = S.v3
RC = S.RoundCone
EL = S.Ellipsoid


def mirror(x, sides=(-1, 1)):
    return [(s, "L" if s < 0 else "R") for s in sides]


# ---------------------------------------------------------------------------
# Shared parts
# ---------------------------------------------------------------------------


def canine_head(c, sk, parent, tag, base, yaw=0.0, scale=1.0, fangs=True):
    """
    A canine head on a neck: `base` is where the neck leaves the body,
    `yaw` turns the whole neck and head (radians). Bones Neck{tag},
    Head{tag}, Jaw{tag}.
    """
    r = S.rot_y(yaw)

    def at(x, y, z):
        return base + r @ (P(x, y, z) * scale)

    neck = sk.add(f"Neck{tag}", parent, at(0, 0, 0))
    head = sk.add(f"Head{tag}", neck, at(0, 0.62, -0.55))
    jaw = sk.add(f"Jaw{tag}", head, at(0, 0.42, -0.72))
    n, h, j = neck.name, head.name, jaw.name
    s = scale
    # Neck: thick at the shoulders, narrowing to the skull.
    c.add(RC(at(0, -0.1, 0.25), at(0, 0.6, -0.5), 0.5 * s, 0.34 * s, n, blend=0.2 * s))
    c.add(EL(at(0, 0.3, 0.05), P(0.38, 0.42, 0.5) * s, n, blend=0.2 * s, rot=r))
    # Skull, cheeks, brow.
    c.add(EL(at(0, 0.72, -0.62), P(0.34, 0.31, 0.4) * s, h, blend=0.12 * s, rot=r))
    for side in (-1, 1):
        c.add(EL(at(side * 0.19, 0.6, -0.78), P(0.19, 0.18, 0.22) * s, h, blend=0.1 * s, rot=r))
    c.add(EL(at(0, 0.82, -0.88), P(0.28, 0.1, 0.14) * s, h, blend=0.08 * s, rot=r))
    # Muzzle tapering to the nose.
    c.add(RC(at(0, 0.64, -0.9), at(0, 0.56, -1.48), 0.22 * s, 0.12 * s, h, blend=0.12 * s))
    c.add(EL(at(0, 0.6, -1.55), P(0.09, 0.07, 0.07) * s, h, "Dark", blend=0.03 * s, rot=r))
    # Lower jaw on its own bone (it opens to bite / howl / roar).
    c.add(RC(at(0, 0.42, -0.8), at(0, 0.42, -1.38), 0.15 * s, 0.085 * s, j, "Under", blend=0.04 * s))
    # Pointed ears.
    for side in (-1, 1):
        c.add(RC(at(side * 0.19, 0.92, -0.5), at(side * 0.27, 1.32, -0.42), 0.12 * s, 0.015 * s, h, "Dark", blend=0.05 * s))
    if fangs:
        for side in (-1, 1):
            c.add(RC(at(side * 0.09, 0.5, -1.3), at(side * 0.09, 0.34, -1.33), 0.035 * s, 0.008 * s, h, "Horn", blend=0.0))
    for side in (-1, 1):
        c.solid(EL(at(side * 0.16, 0.73, -0.98), P(0.065, 0.05, 0.045) * s, h, "Eye", rot=r))
    return neck, head, jaw


def quad_legs(c, sk, chest, hips, front_x=0.55, hind_x=0.55, thick=1.0, paw=1.0, claws=True):
    """Dog / cat legs: elbow back, stifle forward, hock back."""
    legs = {}
    t = thick
    for side, tag in mirror(None):
        x = side * front_x
        pts = [P(x, 2.05, -1.05), P(x, 1.3, -0.55), P(x, 0.42, -1.0), P(x, 0.12, -1.1)]
        bones, angles = sk.chain_down([f"LegF{tag}", f"LegF{tag}b", f"LegF{tag}c"], chest, pts)
        legs[f"LegF{tag}"] = (pts, angles, -1, 0.0)
        a, b, cc = bones
        c.add(EL(P(x * 0.92, 2.3, -1.0), P(0.22, 0.5, 0.36) * t, chest.name, blend=0.2))
        c.add(RC(pts[0], pts[1], 0.27 * t, 0.16 * t, a.name, blend=0.15))
        c.add(RC(pts[1], pts[2], 0.15 * t, 0.085 * t, b.name, blend=0.08))
        c.add(RC(pts[2], pts[3], 0.085 * t, 0.08 * t, cc.name, "Dark", blend=0.05))
        c.add(EL(P(x, 0.1, -1.17), P(0.13, 0.09, 0.17) * paw, cc.name, "Dark", blend=0.06))
        if claws:
            for dx in (-0.07, 0, 0.07):
                c.add(RC(P(x + dx * paw, 0.08, -1.28), P(x + dx * paw, 0.02, -1.36), 0.03, 0.008, cc.name, "Horn", blend=0.0))
    for side, tag in mirror(None):
        x = side * hind_x
        pts = [P(x, 2.2, 1.0), P(x, 1.3, 0.62), P(x, 0.62, 1.25), P(x, 0.12, 1.08)]
        bones, angles = sk.chain_down([f"LegB{tag}", f"LegB{tag}b", f"LegB{tag}c"], hips, pts)
        legs[f"LegB{tag}"] = (pts, angles, 1, 0.0)
        a, b, cc = bones
        c.add(RC(pts[0], pts[1], 0.42 * t, 0.19 * t, a.name, blend=0.2))
        c.add(EL(P(x * 0.86, 1.85, 1.0), P(0.27, 0.5, 0.42) * t, a.name, blend=0.15))
        c.add(RC(pts[1], pts[2], 0.17 * t, 0.085 * t, b.name, blend=0.08))
        c.add(RC(pts[2], pts[3], 0.08 * t, 0.075 * t, cc.name, "Dark", blend=0.05))
        c.add(EL(P(x, 0.1, 1.03), P(0.12, 0.09, 0.16) * paw, cc.name, "Dark", blend=0.06))
        if claws:
            for dx in (-0.065, 0, 0.065):
                c.add(RC(P(x + dx * paw, 0.08, 0.9), P(x + dx * paw, 0.02, 0.83), 0.028, 0.008, cc.name, "Horn", blend=0.0))
    return legs


def canine_torso(c, sk, deep=1.0, bulk=1.0):
    body = sk.add("Body", None, P(0, 2.35, 0))
    chest = sk.add("Chest", body, P(0, 2.4, -0.9))
    hips = sk.add("Hips", body, P(0, 2.35, 0.95))
    d, b = deep, bulk
    # Deep chest and withers.
    c.add(EL(P(0, 2.3 - 0.05 * d, -0.85), P(0.62 * b, 0.78 * d, 0.85), chest.name, blend=0.25))
    c.add(EL(P(0, 2.78, -0.95), P(0.45 * b, 0.35, 0.6), chest.name, blend=0.25))
    c.add(EL(P(0, 2.0, -1.45), P(0.36 * b, 0.45 * d, 0.3), chest.name, "Under", blend=0.2))
    # Ribs to a tucked waist.
    c.add(RC(P(0, 2.35, -0.7), P(0, 2.48, 0.55), 0.68 * b, 0.47 * b, body.name, blend=0.25))
    c.add(EL(P(0, 1.98, -0.55), P(0.42 * b, 0.32, 0.85), body.name, blend=0.2))
    # Loins and rump.
    c.add(RC(P(0, 2.48, 0.55), P(0, 2.42, 1.2), 0.5 * b, 0.55 * b, hips.name, blend=0.2))
    c.add(EL(P(0, 2.45, 1.2), P(0.56 * b, 0.55, 0.55), hips.name, blend=0.2))
    return body, chest, hips


def bushy_tail(c, sk, hips, start=P(0, 2.5, 1.62), thick=1.0):
    pts = [start, start + P(0, -0.25, 0.45), start + P(0, -0.65, 0.78), start + P(0, -1.05, 0.95), start + P(0, -1.4, 1.0)]
    names = ["Tail", "Tail2", "Tail3", "Tail4"]
    prev = hips
    for i, n in enumerate(names):
        prev = sk.add(n, prev, pts[i])
    radii = [0.16, 0.21, 0.2, 0.15, 0.05]
    for i, n in enumerate(names):
        region = "Dark" if i == 3 else "Hide"
        c.add(RC(pts[i], pts[i + 1], radii[i] * thick, radii[i + 1] * thick, n, region, blend=0.12 if i == 0 else 0.0))
    return names


# ---------------------------------------------------------------------------
# Creatures
# ---------------------------------------------------------------------------


def hound():
    sk = S.Skeleton()
    c = S.Creature("Hound", sk, step=0.07)
    body, chest, hips = canine_torso(c, sk)
    canine_head(c, sk, chest, "", P(0, 2.7, -1.45))
    legs = quad_legs(c, sk, chest, hips)
    tail = bushy_tail(c, sk, hips)
    return c, {"plan": "Quadruped", "legs": legs, "heads": [""], "tail": tail}


def shaggy_ruff(c, base, yaw, bone, radius=0.45, length=0.75, count=9, glow_every=3):
    """Tufts of fur radiating back from a neck base; some tipped with embers."""
    r = S.rot_y(yaw)
    for i in range(count):
        a = math.pi * (0.05 + 0.9 * i / (count - 1))  # over the top half and sides
        d = r @ P(math.cos(a) * radius, math.sin(a) * radius * 0.9, 0.0)
        tip = d * 1.5 + r @ P(0, 0.12, length)
        c.add(RC(base + d * 0.8, base + tip, 0.13, 0.02, bone, "Mane", blend=0.035))
        # A second, shorter lock between each pair.
        if i < count - 1:
            a2 = a + math.pi * 0.45 / (count - 1)
            d2 = r @ P(math.cos(a2) * radius, math.sin(a2) * radius * 0.9, 0.0)
            c.add(RC(base + d2 * 0.8, base + d2 * 1.35 + r @ P(0, 0.05, length * 0.7), 0.1, 0.02, bone, "Mane", blend=0.035))
        if glow_every and i % glow_every == 1:
            c.add(RC(base + tip * 0.85, base + tip * 1.08, 0.06, 0.01, bone, "Glow", blend=0.02))


def cerberus():
    sk = S.Skeleton()
    c = S.Creature("Cerberus", sk, step=0.078)
    body, chest, hips = canine_torso(c, sk, deep=1.1, bulk=1.2)
    # Three necks fan out of a broad chest; the side heads turn outward.
    necks = [("", P(0, 2.9, -1.5), 0.0, 1.0), ("L", P(-0.78, 2.62, -1.28), math.radians(38), 0.9),
             ("R", P(0.78, 2.62, -1.28), math.radians(-38), 0.9)]
    for tag, base, yaw, scale in necks:
        canine_head(c, sk, chest, tag, base, yaw, scale)
        shaggy_ruff(c, base + S.rot_y(yaw) @ P(0, 0.2, 0.25), yaw, f"Neck{tag}", radius=0.42 * scale)
    # Spines down the back.
    for i in range(6):
        z = -0.5 + i * 0.36
        bone = "Chest" if z < -0.3 else ("Body" if z < 0.55 else "Hips")
        c.add(RC(P(0, 2.95 - i * 0.04, z), P(0, 3.45 - i * 0.07, z + 0.3), 0.12, 0.015, bone, "Horn", blend=0.05))
    legs = quad_legs(c, sk, chest, hips, front_x=0.62, hind_x=0.6, thick=1.18, paw=1.2)
    tail = bushy_tail(c, sk, hips, thick=0.9)
    return c, {"plan": "Quadruped", "legs": legs, "heads": ["", "L", "R"], "tail": tail}


def viper_head(c, sk, parent, tag, at_fn, crest=True, scale=1.0):
    """
    A broad viper head (bones Head{tag}, Jaw{tag}): wide jaw hinges, flat
    skull, brow ridges, fangs, a forked tongue; optional crown and frills.
    `at_fn(x, y, z)` maps head-local points (head joint at the origin,
    facing -Z) into the world.
    """
    s = scale
    at = at_fn
    head = sk.add(f"Head{tag}", parent, at(0, 0, 0))
    jaw = sk.add(f"Jaw{tag}", head, at(0, -0.14, -0.05))
    h, j = head.name, jaw.name
    c.add(EL(at(0, 0.05, -0.3), P(0.42, 0.23, 0.45) * s, h, blend=0.1 * s))
    c.add(RC(at(0, 0.06, -0.45), at(0, 0.0, -1.0), 0.3 * s, 0.14 * s, h, blend=0.1 * s))
    for side in (-1, 1):
        c.add(EL(at(side * 0.3, -0.05, -0.15), P(0.2, 0.17, 0.26) * s, h, blend=0.1 * s))
        c.add(EL(at(side * 0.22, 0.2, -0.5), P(0.12, 0.07, 0.24) * s, h, "Dark", blend=0.04 * s))
        c.solid(EL(at(side * 0.31, 0.12, -0.56), P(0.075, 0.065, 0.08) * s, h, "Eye"))
        c.add(RC(at(side * 0.12, -0.08, -0.85), at(side * 0.12, -0.32, -0.88), 0.045 * s, 0.01 * s, h, "Horn", blend=0.0))
    c.add(RC(at(0, -0.12, -0.2), at(0, -0.14, -0.9), 0.22 * s, 0.1 * s, j, "Under", blend=0.04 * s))
    # Forked tongue.
    c.add(RC(at(0, -0.08, -0.85), at(0, -0.1, -1.15), 0.03 * s, 0.02 * s, j, "Glow", blend=0.0))
    for side in (-1, 1):
        c.add(RC(at(0, -0.1, -1.15), at(side * 0.06, -0.1, -1.28), 0.02 * s, 0.006 * s, j, "Glow", blend=0.0))
    if crest:
        for i, x in enumerate((-0.22, 0, 0.22)):
            tall = 0.75 if x == 0 else 0.55
            c.add(RC(at(x, 0.2, -0.2 + abs(x) * 0.4), at(x * 1.4, 0.2 + tall, 0.25), 0.07 * s, 0.012 * s, h, "Glow", blend=0.03 * s))
        for side in (-1, 1):
            c.add(EL(at(side * 0.45, 0.1, 0.05), P(0.06, 0.38, 0.32) * s, h, "Horn", blend=0.05 * s,
                     rot=S.rot_z(side * math.radians(-35))))
    return head, jaw


def serpent_neck(c, sk, parent, tag, base, yaw, height, radius, crest, scale=1.0, swan=False):
    """
    A raised neck (Neck{tag}, NeckB{tag}, NeckC{tag}) and viper head: a
    cobra's forward rise, or (swan) an S that leans back before the head
    reaches forward.
    """
    r = S.rot_y(yaw)
    shape = (
        (P(0, 0, 0), P(0, 0.38 * height, -0.6), P(0, 0.78 * height, -0.4), P(0, 1.05 * height, -0.85))
        if swan
        else (P(0, 0, 0), P(0, 0.45 * height, -0.75), P(0, 0.85 * height, -0.95), P(0, 1.08 * height, -1.35))
    )
    pts = [base + r @ (p * scale) for p in shape]
    names = [f"Neck{tag}", f"NeckB{tag}", f"NeckC{tag}"]
    prev = parent
    for i, n in enumerate(names):
        prev = sk.add(n, prev, pts[i])
    radii = [radius, radius * 0.88, radius * 0.78, radius * 0.72]
    for i, n in enumerate(names):
        c.add(RC(pts[i], pts[i + 1], radii[i], radii[i + 1], n, blend=0.0 if i > 0 else 0.12))
        # Belly scales up the front of the neck.
        mid = (pts[i] + pts[i + 1]) / 2
        c.add(RC(pts[i] + r @ P(0, 0, -radii[i] * 0.55), pts[i + 1] + r @ P(0, 0, -radii[i + 1] * 0.55),
                 radii[i] * 0.55, radii[i + 1] * 0.55, n, "Under", blend=0.04))
    viper_head(c, sk, prev, tag, lambda x, y, z: pts[3] + r @ (P(x, y, z) * scale), crest, scale)
    return names


def serpent():
    sk = S.Skeleton()
    c = S.Creature("Serpent", sk, step=0.085)
    body = sk.add("Body", None, P(0, 0.55, 0))
    # The chest lies on the ground; the neck rises in an S.
    c.add(EL(P(0, 0.62, 0.1), P(0.7, 0.58, 0.95), "Body", blend=0.15))
    c.add(EL(P(0, 0.3, 0.1), P(0.5, 0.22, 0.85), "Body", "Under", blend=0.02))
    neck = serpent_neck(c, sk, body, "", P(0, 0.85, -0.55), 0.0, 2.0, 0.56, crest=True, scale=1.2)
    # Trailing body: tapering segments along +Z.
    segs = []
    prev = body
    z = 0.6
    count = 12
    pts = [P(0, 0.62, 0.6)]
    radii = [0.7]
    for i in range(1, count + 1):
        t = i / count
        z += 1.05 - 0.35 * t
        pts.append(P(0, 0.08 + 0.54 * (1 - t) ** 0.8, z))
        radii.append(0.07 + 0.63 * (1 - t) ** 0.85)
    for i in range(count):
        name = f"Seg{i + 1}"
        prev = sk.add(name, prev, pts[i])
        segs.append(name)
        # Consecutive segments meet exactly: a plain union (a smooth blend
        # would bulge at every joint).
        c.add(RC(pts[i], pts[i + 1], radii[i], radii[i + 1], name, blend=0.0))
        # Belly plates along the ground side.
        c.add(RC(pts[i] + P(0, -radii[i] * 0.5, 0), pts[i + 1] + P(0, -radii[i + 1] * 0.5, 0),
                 radii[i] * 0.52, radii[i + 1] * 0.52, name, "Under", blend=0.02))
        # Diamond markings down the back.
        if i % 2 == 0 and i < count - 1:
            mid = (pts[i] + pts[i + 1]) / 2
            rr = (radii[i] + radii[i + 1]) / 2
            c.add(EL(mid + P(0, rr * 0.8, 0), P(rr * 0.45, rr * 0.2, rr * 0.6), name, "Dark", blend=0.0))
    return c, {"plan": "Serpent", "heads": [""], "necks": {"": neck}, "segments": segs}


def hydra():
    sk = S.Skeleton()
    c = S.Creature("Hydra", sk, step=0.095)
    body = sk.add("Body", None, P(0, 1.6, 0))
    chest = sk.add("Chest", body, P(0, 1.65, -1.0))
    hips = sk.add("Hips", body, P(0, 1.55, 1.0))
    # A heavy, low reptile body with a pale belly.
    c.add(EL(P(0, 1.6, 0), P(1.0, 0.8, 1.55), "Body", blend=0.25))
    c.add(EL(P(0, 1.7, -1.05), P(0.95, 0.78, 0.9), "Chest", blend=0.25))
    c.add(EL(P(0, 1.55, 1.05), P(0.9, 0.72, 0.85), "Hips", blend=0.25))
    c.add(EL(P(0, 1.08, 0), P(0.75, 0.32, 1.45), "Body", "Under", blend=0.05))
    # Spines down the back.
    for i in range(7):
        z = -1.4 + i * 0.45
        bone = "Chest" if z < -0.5 else ("Body" if z < 0.6 else "Hips")
        c.add(RC(P(0, 2.25 - abs(z) * 0.05, z), P(0, 2.7 - abs(z) * 0.1, z + 0.3), 0.13, 0.015, bone, "Horn", blend=0.06))
    # Sprawling legs: upper leg out sideways, knee high, shin down.
    legs = {}
    for side, tag in ((-1, "L"), (1, "R")):
        for row, z, parent, n in ((0, -1.05, chest, "F"), (1, 1.05, hips, "B")):
            x = side
            pts = [P(x * 0.8, 1.45, z), P(x * 1.65, 1.35, z), P(x * 1.85, 0.42, z), P(x * 2.0, 0.12, z)]
            splay = math.radians(90 if side < 0 else -90)
            name = f"Leg{n}{tag}"
            bones, angles = sk.chain_down([name, name + "b", name + "c"], parent, pts, splay=splay)
            legs[name] = (pts, angles, 1, splay)
            a, b, cc = bones
            c.add(RC(pts[0], pts[1], 0.38, 0.24, a.name, blend=0.2))
            c.add(RC(pts[1], pts[2], 0.23, 0.15, b.name, blend=0.0))
            c.add(RC(pts[2], pts[3], 0.15, 0.13, cc.name, "Dark", blend=0.05))
            c.add(EL(pts[3] + P(x * 0.05, 0.0, -0.12), P(0.22, 0.1, 0.28), cc.name, "Dark", blend=0.06))
            for dz in (-0.12, 0.0, 0.12):
                c.add(RC(pts[3] + P(x * 0.05, 0.0, -0.3 + dz * 0.2) + P(dz, 0, 0), pts[3] + P(x * 0.05 + dz, -0.08, -0.48),
                         0.045, 0.01, cc.name, "Horn", blend=0.0))
    # Three necks rise from the chest and fan out.
    necks = {}
    for tag, base, yaw, height in (("L", P(-0.55, 2.0, -1.6), 36, 2.0), ("", P(0, 2.15, -1.8), 0, 2.5),
                                   ("R", P(0.55, 2.0, -1.6), -36, 2.0)):
        necks[tag] = serpent_neck(c, sk, chest, tag, base, math.radians(yaw), height, 0.42, crest=False, scale=0.95, swan=True)
    # A thick tail dragging behind.
    tail = []
    pts = [P(0, 1.45, 1.75), P(0, 1.2, 2.6), P(0, 0.85, 3.5), P(0, 0.55, 4.4), P(0, 0.35, 5.2), P(0, 0.25, 5.9)]
    radii = [0.62, 0.5, 0.38, 0.27, 0.17, 0.06]
    prev = hips
    for i in range(5):
        n = "Tail" if i == 0 else f"Tail{i + 1}"
        prev = sk.add(n, prev, pts[i])
        tail.append(n)
        c.add(RC(pts[i], pts[i + 1], radii[i], radii[i + 1], n, blend=0.2 if i == 0 else 0.0))
        c.add(RC(pts[i] + P(0, radii[i] * 0.7, 0.1), pts[i] + P(0, radii[i] * 0.7 + 0.35, 0.35), 0.1, 0.01, n, "Horn", blend=0.04))
    return c, {"plan": "Sprawler", "legs": legs, "heads": ["", "L", "R"], "necks": necks, "tail": tail}


CREATURES_EXTRA = {"Serpent": serpent, "Hydra": hydra}


CREATURES = {"Hound": hound, "Cerberus": cerberus}
CREATURES.update(CREATURES_EXTRA)


def main():
    os.makedirs(OUT, exist_ok=True)
    names = sys.argv[1:] or list(CREATURES)
    for name in names:
        c, meta = CREATURES[name]()
        counts, total = c.export(os.path.join(OUT, f"{name}.gltf"), os.path.join(OUT, f"{name}.png"))
        print(f"{name}: {total} triangles {counts}")
    # The skeleton data always covers every creature (cheap: no meshing).
    shapes = []
    for name in CREATURES:
        c, meta = CREATURES[name]()
        shapes.append(emit_lua.shape(name, c, meta))
    print("wrote", emit_lua.write(ROOT, shapes))


if __name__ == "__main__":
    main()
