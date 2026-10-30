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


# ---------------------------------------------------------------------------
# Batch B (D-57): insects, spiders, golems, knights, lions, the chimera
# ---------------------------------------------------------------------------


def along(a, b, up=(0.0, 1.0, 0.0)):
    """Rotation whose local Z runs from a to b and local Y is as near `up` as it can be."""
    z = np.asarray(b, float) - np.asarray(a, float)
    z /= np.linalg.norm(z)
    x = np.cross(np.asarray(up, float), z)
    if np.linalg.norm(x) < 1e-6:
        x = np.cross((1.0, 0.0, 0.0), z)
    x /= np.linalg.norm(x)
    y = np.cross(z, x)
    return np.stack([x, y, z], 1)


def splay_leg(c, sk, parent, name, hip, lean, side, knee, ankle, tip, radii, extra, spikes=0):
    """
    An insect / spider leg reaching out sideways: `lean` degrees from
    straight ahead (90 = out to the side), mirrored by `side`. knee, ankle
    and tip are (out, height) in the leg's plane, out measured from the hip.
    """
    yaw = math.radians(-side * lean)
    o = P(-math.sin(yaw), 0, -math.cos(yaw))
    flat = P(hip[0], 0, hip[2])
    pts = [hip] + [flat + o * out + P(0, y, 0) for out, y in (knee, ankle, tip)]
    bones, angles = sk.chain_down([name, name + "b", name + "c"], parent, pts, splay=yaw)
    a, b, cc = bones
    r0, r1, r2, r3 = radii
    c.add(RC(pts[0], pts[1], r0, r1, a.name, blend=0.08))
    c.add(EL(pts[1], P(r1, r1, r1) * 1.25, b.name, "Dark", blend=0.04))
    c.add(RC(pts[1], pts[2], r1 * 0.95, r2, b.name, blend=0.03))
    c.add(EL(pts[2], P(r2, r2, r2) * 1.2, cc.name, "Dark", blend=0.03))
    c.add(RC(pts[2], pts[3], r2, r3, cc.name, "Dark", blend=0.02))
    c.add(RC(pts[3], pts[3] + o * 0.12 + P(0, -0.05, 0), r3, 0.008, cc.name, "Horn", blend=0.0))
    # Spines along the shin.
    for k in range(spikes):
        t = (k + 1) / (spikes + 1)
        q = pts[1] + (pts[2] - pts[1]) * t
        c.add(RC(q, q + o * 0.05 + P(0, 0.16, 0) + (pts[1] - pts[2]) * 0.08, r1 * 0.35, 0.01, b.name, "Horn", blend=0.0))
    return (pts, angles, 1, yaw, extra)


def beetle():
    """A heavy horned beetle / scarab: a domed shell over six jointed legs."""
    sk = S.Skeleton()
    c = S.Creature("Beetle", sk, step=0.064)
    body = sk.add("Body", None, P(0, 1.0, 0))
    head = sk.add("Head", body, P(0, 1.02, -1.2))
    mands = {side: sk.add(f"Mand{tag}", head, P(side * 0.24, 0.84, -1.76)) for side, tag in mirror(None)}
    # Pronotum (the shield behind the head) and the two wing cases.
    c.add(EL(P(0, 1.2, -0.75), P(0.95, 0.52, 0.58), "Body", blend=0.1))
    c.add(EL(P(0, 1.42, -0.85), P(0.62, 0.3, 0.42), "Body", blend=0.12))
    for side in (-1, 1):
        c.add(EL(P(side * 0.43, 1.24, 0.5), P(0.6, 0.66, 1.32), "Body", blend=0.04))
    # The dark rim round the shell.
    c.add(EL(P(0, 0.98, 0.45), P(1.05, 0.26, 1.36), "Body", "Dark", blend=0.03))
    c.add(EL(P(0, 0.76, 0.1), P(0.78, 0.3, 1.25), "Body", "Under", blend=0.06))
    # Glowing spots down the wing cases.
    for side in (-1, 1):
        for z in (-0.15, 0.45, 1.05):
            dz = (z - 0.5) / 1.32
            y = 1.24 + 0.66 * math.sqrt(max(0.0, 1 - (0.12 / 0.6) ** 2 - dz * dz)) - 0.04
            c.add(EL(P(side * 0.55, y, z), P(0.13, 0.07, 0.17), "Body", "Glow", blend=0.02))
    # Head: clypeus, a curved horn, eyes, clubbed antennae, mandibles.
    c.add(EL(P(0, 1.0, -1.35), P(0.5, 0.36, 0.4), "Head", blend=0.1))
    c.add(EL(P(0, 0.94, -1.68), P(0.36, 0.18, 0.2), "Head", "Dark", blend=0.05))
    c.add(RC(P(0, 1.16, -1.5), P(0, 1.56, -1.95), 0.17, 0.11, "Head", "Horn", blend=0.06))
    c.add(RC(P(0, 1.56, -1.95), P(0, 2.02, -1.82), 0.11, 0.02, "Head", "Horn", blend=0.0))
    for side, tag in mirror(None):
        c.solid(EL(P(side * 0.37, 1.08, -1.52), P(0.1, 0.11, 0.1), "Head", "Eye"))
        c.add(RC(P(side * 0.2, 1.2, -1.7), P(side * 0.45, 1.55, -2.12), 0.035, 0.025, "Head", "Dark", blend=0.0))
        c.add(EL(P(side * 0.47, 1.58, -2.16), P(0.07, 0.07, 0.1), "Head", "Dark", blend=0.0))
        m = mands[side].name
        c.add(RC(P(side * 0.24, 0.84, -1.76), P(side * 0.2, 0.8, -2.08), 0.1, 0.065, m, "Horn", blend=0.02))
        c.add(RC(P(side * 0.2, 0.8, -2.08), P(side * 0.04, 0.78, -2.24), 0.065, 0.015, m, "Horn", blend=0.0))
    # Six legs in alternating tripods (1, 4, 5 and 2, 3, 6).
    legs = {}
    for row, (z, lean) in enumerate(((-0.72, 40), (0.05, 90), (0.8, 140))):
        for side, tag in mirror(None):
            index = row * 2 + (1 if side < 0 else 2)
            phase = 0.0 if index in (1, 4, 5) else 0.5
            extra = {"phases": (phase, phase, phase), "front": row == 0, "side": side}
            legs[f"Leg{index}"] = splay_leg(
                c, sk, "Body", f"Leg{index}", P(side * 0.62, 0.85, z), lean, side,
                (0.85, 1.38), (1.95, 0.38), (2.15, 0.12), (0.2, 0.15, 0.09, 0.045), extra, spikes=2,
            )
    return c, {"plan": "Hexapod", "legs": legs, "heads": [""]}


def spider():
    """A great spider: eight long legs arched high over a glowing-marked abdomen."""
    sk = S.Skeleton()
    c = S.Creature("Spider", sk, step=0.078)
    body = sk.add("Body", None, P(0, 1.15, -0.3))
    head = sk.add("Head", body, P(0, 1.2, -0.95))
    sk.add("Abdomen", body, P(0, 1.3, 0.35))
    mands = {side: sk.add(f"Mand{tag}", head, P(side * 0.16, 1.1, -1.25)) for side, tag in mirror(None)}
    # Cephalothorax and head.
    c.add(EL(P(0, 1.18, -0.4), P(0.72, 0.4, 0.8), "Body", blend=0.1))
    c.add(EL(P(0, 1.36, -0.55), P(0.5, 0.28, 0.55), "Body", blend=0.12))
    c.add(EL(P(0, 0.92, -0.4), P(0.55, 0.2, 0.62), "Body", "Under", blend=0.06))
    c.add(EL(P(0, 1.25, -1.0), P(0.46, 0.34, 0.36), "Head", blend=0.1))
    # Eight eyes.
    for side in (-1, 1):
        for x, y, z, r in ((0.13, 1.38, -1.3, 0.085), (0.3, 1.42, -1.2, 0.06), (0.12, 1.55, -1.13, 0.05), (0.31, 1.52, -1.0, 0.045)):
            c.solid(EL(P(side * x, y, z), P(r, r, r), "Head", "Eye"))
    # Chelicerae with fangs, and the pedipalps.
    for side, tag in mirror(None):
        m = mands[side].name
        c.add(RC(P(side * 0.15, 1.12, -1.24), P(side * 0.17, 0.84, -1.42), 0.13, 0.09, m, blend=0.05))
        c.add(RC(P(side * 0.17, 0.84, -1.42), P(side * 0.07, 0.6, -1.36), 0.06, 0.01, m, "Horn", blend=0.0))
        c.add(RC(P(side * 0.3, 1.05, -1.18), P(side * 0.45, 0.88, -1.58), 0.075, 0.055, "Head", blend=0.03))
        c.add(RC(P(side * 0.45, 0.88, -1.58), P(side * 0.4, 0.58, -1.74), 0.055, 0.04, "Head", "Dark", blend=0.0))
    # Waist and the big abdomen with glowing chevrons and spinnerets.
    c.add(RC(P(0, 1.2, 0.25), P(0, 1.35, 0.55), 0.22, 0.26, "Abdomen", blend=0.1))
    c.add(EL(P(0, 1.6, 1.4), P(1.0, 0.88, 1.2), "Abdomen", blend=0.15))
    c.add(EL(P(0, 1.22, 1.35), P(0.7, 0.45, 0.9), "Abdomen", "Under", blend=0.08))
    for i in range(4):
        z = 0.85 + i * 0.38
        dz = (z - 1.4) / 1.2
        y = 1.6 + 0.88 * math.sqrt(max(0.0, 1 - dz * dz)) - 0.03
        c.add(EL(P(0, y, z), P(0.5 - 0.08 * i, 0.06, 0.1), "Abdomen", "Glow" if i % 2 == 0 else "Dark", blend=0.02))
        for side in (-1, 1):
            c.add(EL(P(side * (0.55 - 0.06 * i), y - 0.18, z + 0.08), P(0.12, 0.05, 0.08), "Abdomen", "Dark", blend=0.02))
    c.add(RC(P(0, 1.28, 2.5), P(0, 1.22, 2.72), 0.12, 0.05, "Abdomen", "Dark", blend=0.04))
    # Eight legs, alternating tetrapods (L1 R2 L3 R4 / R1 L2 R3 L4).
    legs = {}
    for row, (z, lean) in enumerate(((-0.72, 28), (-0.45, 68), (-0.16, 112), (0.12, 150))):
        for side, tag in mirror(None):
            index = row * 2 + (1 if side < 0 else 2)
            phase = 0.0 if index in (1, 4, 5, 8) else 0.5
            extra = {"phases": (phase, phase, phase), "front": row == 0, "side": side}
            legs[f"Leg{index}"] = splay_leg(
                c, sk, "Body", f"Leg{index}", P(side * 0.55, 1.12, z), lean, side,
                (1.15, 2.25), (2.55, 0.45), (2.75, 0.12), (0.14, 0.12, 0.07, 0.03), extra, spikes=3,
            )
    return c, {"plan": "Octopod", "legs": legs, "heads": [""]}


def biped_legs(c, sk, body, x, hip_y, knee_y, ankle_y, thick, foot):
    """Two legs, knee forward; the foot bone stands straight down to the sole."""
    legs = {}
    for side, tag in mirror(None):
        px = side * x
        # Knees well bent at rest: room to stride and to bob over the feet.
        pts = [P(px, hip_y, 0), P(px * 1.05, knee_y, -0.4), P(px * 1.05, ankle_y, 0.08), P(px * 1.05, 0.12, 0.08)]
        bones, angles = sk.chain_down([f"Leg{tag}", f"Leg{tag}b", f"Leg{tag}c"], body, pts)
        phase = 0.0 if side < 0 else 0.5
        legs[f"Leg{tag}"] = (pts, angles, 1, 0.0, {"phases": (phase, phase, phase), "front": False, "side": side})
        foot(side, px * 1.05, pts, [b.name for b in bones], thick)
    return legs


def golem():
    """A hulking stone golem: boulder shoulders, a sunken head, huge fists, a glowing core."""
    sk = S.Skeleton()
    c = S.Creature("Golem", sk, step=0.088)
    rng = np.random.default_rng(7)
    body = sk.add("Body", None, P(0, 2.5, 0))
    head = sk.add("Head", body, P(0, 4.5, -0.45))
    sk.add("Jaw", head, P(0, 4.5, -0.75))
    arms = {}
    for side, tag in mirror(None):
        arm = sk.add(f"Arm{tag}", body, P(side * 1.45, 4.1, 0.05))
        arms[side] = (arm, sk.add(f"Arm{tag}2", arm, P(side * 1.68, 2.95, 0.0)))

    def plates(centre, radii, bone, count, region="Hide", size=1.0, front=False):
        """Flat slabs of stone over an ellipsoid: a craggy, faceted surface."""
        for _ in range(count):
            d = rng.normal(size=3)
            if front:
                d[2] = -abs(d[2]) - 0.6
            d /= np.linalg.norm(d)
            # On the surface: half of each slab stands proud of it.
            q = centre + d * radii * 1.02
            k = size * rng.uniform(0.75, 1.2)
            c.add(EL(q, P(0.42, 0.34, 0.16) * k, bone, region, blend=0.025, rot=along(q, q + d, up=(0.0, 1.0, 0.0001))))

    # Torso: pelvis, belly, a massive chest and a hunched back, built of
    # slabs (low blends keep the edges of the stones).
    core = [
        (P(0, 2.6, 0.05), P(0.92, 0.52, 0.6)),
        (P(0, 3.2, -0.05), P(0.95, 0.65, 0.7)),
        (P(0, 3.92, -0.1), P(1.2, 0.72, 0.85)),
        (P(0, 4.2, 0.35), P(1.0, 0.6, 0.7)),
    ]
    for centre, radii in core:
        c.add(EL(centre, radii, "Body", blend=0.12))
    plates(P(0, 3.92, -0.1), P(1.2, 0.72, 0.85), "Body", 16)
    plates(P(0, 3.2, -0.05), P(0.95, 0.65, 0.7), "Body", 8)
    plates(P(0, 4.2, 0.35), P(1.0, 0.6, 0.7), "Body", 8)
    # Slabs of darker stone over the chest and belly, a glowing core and cracks.
    for side in (-1, 1):
        c.add(EL(P(side * 0.55, 4.0, -0.88), P(0.5, 0.45, 0.14), "Body", "Dark", blend=0.03,
                 rot=S.rot_y(side * math.radians(20))))
        c.add(EL(P(side * 0.42, 3.08, -0.7), P(0.4, 0.3, 0.12), "Body", "Dark", blend=0.03,
                 rot=S.rot_y(side * math.radians(16))))
    c.add(EL(P(0, 3.72, -0.96), P(0.26, 0.32, 0.14), "Body", "Glow", blend=0.02))
    for a, b in ((P(0, 3.72, -0.95), P(-0.55, 3.28, -0.8)), (P(0, 3.72, -0.95), P(0.5, 3.35, -0.82)),
                 (P(0, 3.72, -0.95), P(0.1, 4.3, -0.86)), (P(-0.55, 3.28, -0.8), P(-0.75, 2.88, -0.6))):
        c.add(RC(a, b, 0.05, 0.03, "Body", "Glow", blend=0.0))
    # A blocky head jutting from between the shoulders: heavy brow, glowing
    # eyes, a slab of a jaw.
    c.add(EL(P(0, 4.62, -0.28), P(0.5, 0.35, 0.45), "Body", blend=0.1))
    c.add(EL(P(0, 4.78, -0.62), P(0.46, 0.4, 0.42), "Head", blend=0.08))
    plates(P(0, 4.78, -0.62), P(0.46, 0.4, 0.42), "Head", 5, size=0.6)
    c.add(EL(P(0, 4.98, -0.95), P(0.5, 0.13, 0.17), "Head", "Dark", blend=0.03))
    for side in (-1, 1):
        c.solid(EL(P(side * 0.19, 4.82, -0.99), P(0.1, 0.065, 0.06), "Head", "Eye"))
    c.add(EL(P(0, 4.5, -0.88), P(0.4, 0.18, 0.28), "Jaw", "Dark", blend=0.04))
    # Arms: boulder shoulders, long arms, forearms swelling into huge fists.
    for side, (arm, fore) in arms.items():
        x = side
        c.add(EL(P(x * 1.55, 4.3, 0.0), P(0.66, 0.58, 0.66), arm.name, blend=0.1))
        plates(P(x * 1.55, 4.3, 0.0), P(0.66, 0.58, 0.66), arm.name, 7, size=0.9)
        c.add(RC(P(x * 1.45, 4.1, 0.05), P(x * 1.68, 2.95, 0.0), 0.46, 0.4, arm.name, blend=0.08))
        c.add(EL(P(x * 1.68, 2.95, 0.0), P(0.42, 0.4, 0.42), fore.name, "Dark", blend=0.05))
        c.add(RC(P(x * 1.68, 2.95, 0.0), P(x * 1.72, 1.85, -0.12), 0.42, 0.52, fore.name, blend=0.05))
        plates(P(x * 1.7, 2.4, -0.06), P(0.45, 0.6, 0.45), fore.name, 6, size=0.75)
        c.add(EL(P(x * 1.74, 1.52, -0.16), P(0.6, 0.55, 0.62), fore.name, "Dark", blend=0.06))
        for dz in (-0.25, 0.0, 0.25):
            c.add(EL(P(x * 1.76 + dz * 0.6, 1.32, -0.66), P(0.17, 0.16, 0.16), fore.name, "Dark", blend=0.03))
        # Crystal spikes (Spikes trait) on the shoulders.
        c.group([
            RC(P(x * 1.6, 4.7, 0.1), P(x * 1.98, 5.45, 0.32), 0.2, 0.02, arm.name, "Spikes", blend=0.03),
            RC(P(x * 1.92, 4.5, -0.15), P(x * 2.42, 5.0, -0.1), 0.15, 0.02, arm.name, "Spikes", blend=0.03),
            RC(P(x * 1.35, 4.62, 0.45), P(x * 1.5, 5.15, 0.85), 0.14, 0.02, arm.name, "Spikes", blend=0.03),
        ])
    c.group([
        RC(P(dx, 4.62, 0.62), P(dx * 1.3, 5.3 - abs(dx) * 0.4, 1.0), 0.18 - abs(dx) * 0.05, 0.02, "Body", "Spikes", blend=0.03)
        for dx in (-0.55, 0.0, 0.55)
    ])

    def foot(side, px, pts, names, thick):
        a, b, f = names
        plates((pts[0] + pts[1]) / 2, P(0.5, 0.55, 0.5), a, 5, size=0.8)
        c.add(RC(pts[0], pts[1], 0.58, 0.46, a, blend=0.18))
        c.add(EL(pts[1] + P(0, 0, -0.1), P(0.42, 0.38, 0.38), b, "Dark", blend=0.05))
        c.add(RC(pts[1], pts[2], 0.46, 0.42, b, blend=0.05))
        c.add(EL(P(px, 0.3, -0.15), P(0.48, 0.3, 0.64), f, "Dark", blend=0.06))
        for dx in (-0.25, 0.0, 0.25):
            c.add(EL(P(px + dx, 0.2, -0.72), P(0.15, 0.15, 0.16), f, "Dark", blend=0.04))

    legs = biped_legs(c, sk, body, 0.62, 2.4, 1.3, 0.45, 1.0, foot)
    return c, {"plan": "Biped", "legs": legs, "heads": [""]}


def knight():
    """An armoured knight: plate over mail, a horned / crested helm, sword and shield."""
    sk = S.Skeleton()
    c = S.Creature("Knight", sk, step=0.06)
    body = sk.add("Body", None, P(0, 2.45, 0))
    head = sk.add("Head", body, P(0, 4.2, -0.05))
    arms = {}
    for side, tag in mirror(None):
        arm = sk.add(f"Arm{tag}", body, P(side * 0.95, 3.95, 0.0))
        arms[side] = (arm, sk.add(f"Arm{tag}2", arm, P(side * 1.05, 2.98, 0.05)))
    # Waist, mail, breastplate with a keel and a glowing sigil, gorget.
    c.add(EL(P(0, 2.55, 0), P(0.6, 0.38, 0.42), "Body", "Dark", blend=0.15))
    c.add(EL(P(0, 3.0, 0), P(0.62, 0.45, 0.42), "Body", "Dark", blend=0.15))
    c.add(EL(P(0, 3.55, -0.06), P(0.84, 0.62, 0.55), "Body", "Metal", blend=0.12))
    c.add(EL(P(0, 3.15, -0.12), P(0.66, 0.32, 0.46), "Body", "Metal", blend=0.06))
    c.add(RC(P(0, 3.98, -0.56), P(0, 3.1, -0.5), 0.06, 0.04, "Body", "Metal", blend=0.03))
    c.add(EL(P(0, 3.6, -0.6), P(0.16, 0.2, 0.05), "Body", "Glow", blend=0.0))
    c.add(EL(P(0, 4.02, 0), P(0.46, 0.22, 0.4), "Body", "Metal", blend=0.08))
    # Faulds and tassets over the hips; a belt.
    c.add(EL(P(0, 2.5, -0.06), P(0.7, 0.3, 0.5), "Body", "Metal", blend=0.05))
    for side in (-1, 1):
        c.add(EL(P(side * 0.44, 2.22, -0.18), P(0.26, 0.32, 0.12), "Body", "Metal", blend=0.03))
    c.add(EL(P(0, 2.74, 0), P(0.66, 0.07, 0.46), "Body", "Horn", blend=0.02))
    # A cloak hanging from the shoulders.
    c.add(EL(P(0, 3.0, 0.6), P(0.85, 1.25, 0.1), "Body", "Cloth", blend=0.05, rot=S.rot_x(math.radians(-8))))
    # Helm: dome, face plate, a glowing visor slit, crest and plume.
    c.add(EL(P(0, 4.38, -0.08), P(0.36, 0.42, 0.4), "Head", "Metal", blend=0.08))
    c.add(EL(P(0, 4.3, -0.3), P(0.3, 0.32, 0.22), "Head", "Metal", blend=0.05))
    c.solid(EL(P(0, 4.4, -0.5), P(0.22, 0.035, 0.06), "Head", "Eye"))
    c.add(RC(P(0, 4.8, -0.32), P(0, 4.85, 0.3), 0.07, 0.05, "Head", "Metal", blend=0.04))
    c.add(RC(P(0, 4.85, 0.1), P(0, 4.55, 0.78), 0.12, 0.04, "Head", "Cloth", blend=0.03))
    # Bull horns on the helm (Horns trait).
    horns = []
    for side in (-1, 1):
        horns += [
            RC(P(side * 0.3, 4.52, -0.1), P(side * 0.72, 4.72, -0.2), 0.11, 0.075, "Head", "Horns", blend=0.03),
            RC(P(side * 0.72, 4.72, -0.2), P(side * 0.84, 5.12, -0.36), 0.075, 0.015, "Head", "Horns", blend=0.02),
        ]
    c.group(horns)
    # Arms: layered pauldrons, mail sleeves, vambraces and gauntlets.
    for side, (arm, fore) in arms.items():
        x = side
        c.add(EL(P(x * 1.0, 4.05, 0), P(0.46, 0.26, 0.46), arm.name, "Metal", blend=0.05,
                 rot=S.rot_z(x * math.radians(-22))))
        c.add(EL(P(x * 1.12, 3.84, 0), P(0.4, 0.2, 0.44), arm.name, "Metal", blend=0.03,
                 rot=S.rot_z(x * math.radians(-32))))
        c.add(RC(P(x * 1.05, 4.3, 0), P(x * 1.15, 4.75, 0.05), 0.08, 0.01, arm.name, "Horn", blend=0.02))
        c.add(RC(P(x * 0.98, 3.95, 0), P(x * 1.05, 2.98, 0.05), 0.22, 0.19, arm.name, "Dark", blend=0.08))
        c.add(EL(P(x * 1.05, 2.98, 0.05), P(0.2, 0.2, 0.2), fore.name, "Metal", blend=0.03))
        c.add(RC(P(x * 1.05, 2.98, 0.05), P(x * 1.08, 2.2, -0.08), 0.21, 0.18, fore.name, "Metal", blend=0.05))
        c.add(EL(P(x * 1.08, 2.04, -0.12), P(0.2, 0.22, 0.22), fore.name, "Metal", blend=0.05))
    # Shield on the left forearm, sword in the right hand.
    left = arms[-1][1].name
    right = arms[1][1].name
    c.add(EL(P(-1.34, 2.62, -0.08), P(0.08, 0.82, 0.62), left, "Metal", blend=0.02))
    c.add(EL(P(-1.42, 2.62, -0.08), P(0.06, 0.24, 0.24), left, "Glow", blend=0.0))
    c.add(EL(P(-1.4, 2.62, -0.08), P(0.06, 0.72, 0.54), left, "Dark", blend=0.0))
    guard, tip = P(1.08, 1.92, -0.3), P(1.1, 0.58, -1.32)
    mid = (guard + tip) / 2
    c.add(RC(P(1.08, 2.25, -0.08), P(1.08, 1.95, -0.26), 0.055, 0.05, right, "Dark", blend=0.0))
    c.add(RC(P(0.86, 1.94, -0.3), P(1.3, 1.94, -0.3), 0.06, 0.06, right, "Horn", blend=0.0))
    c.add(EL(mid, P(0.07, 0.16, float(np.linalg.norm(tip - guard)) / 2), right, "Blade", blend=0.0,
             rot=along(guard, tip, up=(1.0, 0.0, 0.0))))
    c.add(RC(guard + (tip - guard) * 0.05 + P(-0.05, 0, 0), guard + (tip - guard) * 0.75 + P(-0.05, 0, 0), 0.035, 0.02,
             right, "Glow", blend=0.0))

    def foot(side, px, pts, names, thick):
        a, b, f = names
        c.add(RC(pts[0], pts[1], 0.3, 0.24, a, "Dark", blend=0.1))
        c.add(EL(P(px, 1.88, -0.12), P(0.28, 0.42, 0.24), a, "Metal", blend=0.03))
        c.add(EL(pts[1] + P(0, 0, -0.1), P(0.22, 0.2, 0.18), b, "Metal", blend=0.03))
        c.add(RC(pts[1] + P(0, 0, -0.22), pts[1] + P(0, 0.05, -0.42), 0.06, 0.01, b, "Horn", blend=0.0))
        c.add(RC(pts[1], pts[2], 0.25, 0.2, b, "Metal", blend=0.05))
        c.add(EL(P(px, 0.24, -0.18), P(0.24, 0.17, 0.48), f, "Metal", blend=0.04))

    legs = biped_legs(c, sk, body, 0.42, 2.35, 1.3, 0.42, 1.0, foot)
    return c, {"plan": "Biped", "legs": legs, "heads": [""]}


def feline_head(c, sk, parent, tag, base, yaw=0.0, scale=1.0):
    """A big cat's head: round skull, short broad muzzle, nose pad, round ears."""
    r = S.rot_y(yaw)

    def at(x, y, z):
        return base + r @ (P(x, y, z) * scale)

    neck = sk.add(f"Neck{tag}", parent, at(0, 0, 0))
    head = sk.add(f"Head{tag}", neck, at(0, 0.58, -0.5))
    jaw = sk.add(f"Jaw{tag}", head, at(0, 0.36, -0.68))
    n, h, j = neck.name, head.name, jaw.name
    s = scale
    c.add(RC(at(0, -0.1, 0.25), at(0, 0.58, -0.45), 0.56 * s, 0.4 * s, n, blend=0.2 * s))
    c.add(EL(at(0, 0.7, -0.62), P(0.43, 0.4, 0.43) * s, h, blend=0.12 * s, rot=r))
    for side in (-1, 1):
        c.add(EL(at(side * 0.25, 0.56, -0.82), P(0.22, 0.2, 0.22) * s, h, blend=0.1 * s, rot=r))
        c.add(EL(at(side * 0.31, 1.0, -0.5), P(0.12, 0.12, 0.06) * s, h, "Dark", blend=0.04 * s, rot=r))
        c.add(EL(at(side * 0.1, 0.53, -1.2), P(0.12, 0.1, 0.09) * s, h, "Under", blend=0.04 * s, rot=r))
        c.add(RC(at(side * 0.08, 0.45, -1.17), at(side * 0.08, 0.3, -1.19), 0.032 * s, 0.008 * s, h, "Horn", blend=0.0))
        c.solid(EL(at(side * 0.18, 0.77, -0.99), P(0.065, 0.048, 0.04) * s, h, "Eye", rot=r))
    c.add(EL(at(0, 0.82, -0.86), P(0.35, 0.1, 0.16) * s, h, blend=0.08 * s, rot=r))
    c.add(EL(at(0, 0.56, -1.04), P(0.28, 0.21, 0.25) * s, h, blend=0.1 * s, rot=r))
    c.add(RC(at(0, 0.8, -0.82), at(0, 0.68, -1.18), 0.14 * s, 0.11 * s, h, blend=0.08 * s))
    c.add(EL(at(0, 0.68, -1.25), P(0.11, 0.07, 0.05) * s, h, "Dark", blend=0.02 * s, rot=r))
    c.add(RC(at(0, 0.38, -0.8), at(0, 0.37, -1.12), 0.16 * s, 0.12 * s, j, "Under", blend=0.04 * s))
    return neck, head, jaw


def big_mane(c, base, bone, chest):
    """A lion's mane: a full ruff round the head and down the chest."""
    c.add(EL(base + P(0, 0.5, -0.25), P(0.78, 0.86, 0.58), bone, "Mane", blend=0.16))
    c.add(EL(P(0, 2.55, -1.3), P(0.7, 0.7, 0.55), chest, "Mane", blend=0.2))
    shaggy_ruff(c, base + P(0, 0.45, -0.05), 0.0, bone, radius=0.62, length=0.55, count=11, glow_every=0)
    for i in range(7):
        a = math.pi * (0.2 + 0.6 * i / 6)
        d = P(math.cos(a) * 0.55, -math.sin(a) * 0.45, 0)
        c.add(RC(base + P(0, 0.2, -0.45) + d, base + P(0, 0.05, -0.2) + d * 1.5 + P(0, -0.3, 0.2), 0.12, 0.02,
                 bone, "Mane", blend=0.035))


def feathered_wings(c, sk, chest, at=P(0.45, 3.0, -0.75), size=1.0):
    """Folded / spread feathered wings (WingL / WingL2 ...): one optional group each."""
    for side, tag in mirror(None):
        x = side
        root = P(x * at[0], at[1], at[2])
        elbow, tip = root + P(x * 1.45, 0.7, 0.2) * size, root + P(x * 2.95, 0.95, 0.55) * size
        w1 = sk.add(f"Wing{tag}", chest, root)
        w2 = sk.add(f"Wing{tag}2", w1, elbow)
        # One mesh per wing ("Wing" / "Wing2": the game reads both as Wing),
        # each under the importer's triangle limit.
        region = "Wing" if side < 0 else "Wing2"
        prims = [
            RC(root, elbow, 0.17, 0.11, w1.name, region, blend=0.08),
            RC(elbow, tip, 0.11, 0.04, w2.name, region, blend=0.06),
        ]
        # Coverts along the arm, then long flight feathers, overlapping.
        for row, count, reach, width in ((0, 12, 0.45, 0.24), (1, 16, 1.0, 0.22)):
            for i in range(count):
                t = (i + 0.5) / count
                bone = w1.name if t < 0.4 else w2.name
                q = root + (elbow - root) * (t / 0.4) if t < 0.4 else elbow + (tip - elbow) * ((t - 0.4) / 0.6)
                length = (reach * (0.75 + 0.55 * math.sin(t * math.pi * 0.85)) if row else reach) * size
                back = q + P(x * 0.18 * t * row, -0.12 - 0.22 * t * row, length + 0.1)
                prims.append(EL((q + back) / 2 + P(0, -0.03 * row, 0), P(0.085, width * size, length / 2 + 0.1), bone, region,
                                blend=0.03, rot=along(q, back, up=(x, 0.0, 0.0))))
        c.group(prims)


def lion_body(c, sk, mane_glow=False):
    body, chest, hips = canine_torso(c, sk, deep=1.05, bulk=1.15)
    base = P(0, 2.75, -1.45)
    feline_head(c, sk, chest, "", base)
    big_mane(c, base, "Neck", chest.name)
    legs = quad_legs(c, sk, chest, hips, front_x=0.6, hind_x=0.58, thick=1.25, paw=1.4)
    return body, chest, hips, legs


def lion():
    """A great maned lion; optional feathered wings (Sphinx) or a scorpion sting (Manticore)."""
    sk = S.Skeleton()
    c = S.Creature("Lion", sk, step=0.07)
    body, chest, hips, legs = lion_body(c, sk)
    # A long tail that hangs and curls up at the end.
    pts = [P(0, 2.6, 1.62), P(0, 2.25, 2.25), P(0, 1.65, 2.75), P(0, 1.25, 3.2), P(0, 1.3, 3.75)]
    names = ["Tail", "Tail2", "Tail3", "Tail4"]
    prev = hips
    for i, n in enumerate(names):
        prev = sk.add(n, prev, pts[i])
    radii = [0.15, 0.12, 0.1, 0.085, 0.075]
    for i, n in enumerate(names):
        c.add(RC(pts[i], pts[i + 1], radii[i], radii[i + 1], n, blend=0.1 if i == 0 else 0.0))
    # Tuft (lions) or a segmented sting (Manticore, SerpentTail trait).
    c.group([EL(P(0, 1.33, 3.85), P(0.17, 0.18, 0.3), "Tail4", "Tuft", blend=0.05)])
    sting = []
    for i in range(1, 4):
        q = (pts[i] + pts[i + 1]) / 2
        sting.append(EL(q + P(0, 0.04, 0), P(0.19, 0.17, 0.24), names[i], "Sting", blend=0.04))
    sting += [
        EL(P(0, 1.4, 3.85), P(0.2, 0.2, 0.24), "Tail4", "Sting", blend=0.05),
        RC(P(0, 1.45, 3.95), P(0, 1.95, 3.75), 0.13, 0.03, "Tail4", "Sting", blend=0.03),
        RC(P(0, 1.95, 3.75), P(0, 2.05, 3.45), 0.03, 0.006, "Tail4", "Horn", blend=0.0),
    ]
    c.group(sting)
    feathered_wings(c, sk, chest)
    lion_horns(c, P(0, 2.75, -1.45), "Head")
    return c, {"plan": "Quadruped", "legs": legs, "heads": [""], "tail": names}


def goat_head(c, sk, parent, tag, base):
    """A goat's head rising on its own neck: long face, beard, swept-back ridged horns."""
    neck = sk.add(f"Neck{tag}", parent, base)
    hp = base + P(0, 0.85, -0.3)
    head = sk.add(f"Head{tag}", neck, hp)
    jaw = sk.add(f"Jaw{tag}", head, hp + P(0, -0.15, -0.35))
    n, h, j = neck.name, head.name, jaw.name
    c.add(RC(base + P(0, -0.15, 0.1), hp + P(0, 0.05, 0.05), 0.34, 0.22, n, blend=0.15))
    c.add(EL(hp + P(0, 0.12, -0.15), P(0.25, 0.27, 0.3), h, blend=0.1))
    c.add(RC(hp + P(0, 0.1, -0.3), hp + P(0, -0.12, -0.78), 0.18, 0.1, h, blend=0.08))
    c.add(EL(hp + P(0, -0.13, -0.8), P(0.1, 0.07, 0.06), h, "Dark", blend=0.02))
    c.add(RC(hp + P(0, -0.2, -0.4), hp + P(0, -0.24, -0.72), 0.1, 0.06, j, "Under", blend=0.03))
    c.add(RC(hp + P(0, -0.3, -0.55), hp + P(0, -0.7, -0.5), 0.09, 0.02, j, "Mane", blend=0.03))
    for side in (-1, 1):
        c.add(RC(hp + P(side * 0.2, 0.18, -0.05), hp + P(side * 0.55, 0.1, 0.05), 0.08, 0.03, h, "Dark", blend=0.03))
        c.solid(EL(hp + P(side * 0.2, 0.18, -0.3), P(0.06, 0.04, 0.05), h, "Eye"))
    horns = []
    for side in (-1, 1):
        prev, r = hp + P(side * 0.12, 0.3, -0.12), 0.11
        for k in range(1, 7):
            a = k / 6 * math.pi * 1.1
            q = hp + P(side * (0.12 + 0.07 * k), 0.3 + math.sin(a) * 0.45, -0.12 + (1 - math.cos(a)) * 0.38)
            horns.append(RC(prev, q, r, r * 0.82, h, "Horns", blend=0.02))
            horns.append(EL(prev, P(r, r, r) * 1.12, h, "Horns", blend=0.02))
            prev, r = q, r * 0.82
    c.group(horns)
    return neck, head, jaw


def bat_wings(c, sk, chest, at=P(0.45, 3.0, -0.6), size=1.0, thick=1.0):
    """Leathery wings: an arm, three fingers and membranes between them."""
    for side, tag in mirror(None):
        x = side
        root = P(x * at[0], at[1], at[2])

        def off(dx, dy, dz):
            return root + P(x * dx, dy, dz) * size

        elbow = off(1.45, 0.75, 0.15)
        w1 = sk.add(f"Wing{tag}", chest, root)
        w2 = sk.add(f"Wing{tag}2", w1, elbow)
        tips = [off(3.05, 0.4, 0.8), off(2.45, -0.25, 1.55), off(1.45, -0.45, 1.85)]
        region = "Wing" if side < 0 else "Wing2"
        prims = [RC(root, elbow, 0.16 * thick, 0.11 * thick, w1.name, region, blend=0.06),
                 EL(elbow, P(0.13, 0.13, 0.13) * thick, w2.name, "Horn", blend=0.03)]
        for t in tips:
            prims.append(RC(elbow, t, 0.08 * thick, 0.02 * thick, w2.name, region, blend=0.04))
            prims.append(RC(t, t + (t - elbow) * 0.12, 0.03 * thick, 0.005, w2.name, "Horn", blend=0.0))
        # Membranes: thin panels between the body, the fingers and the arm.
        corners = [root + P(0, -0.1, 0.5) * size] + tips[::-1]
        for a, b in zip(corners[:-1], corners[1:]):
            centre = (a + b + elbow) / 3
            normal = np.cross(a - elbow, b - elbow)
            normal /= np.linalg.norm(normal)
            ax = (a + b) / 2 - elbow
            ax /= np.linalg.norm(ax)
            bx = np.cross(normal, ax)
            rot = np.stack([bx, normal, ax], 1)
            span = float(np.linalg.norm(b - a)) * 0.55
            depth = float(np.linalg.norm((a + b) / 2 - elbow)) * 0.62
            prims.append(EL(centre, P(span, 0.085, depth), w2.name, region, blend=0.05, rot=rot))
        c.group(prims)


def chimera():
    """Lion, goat and serpent in one: a maned lion with a goat's head on its back, a snake for a tail, bat wings."""
    sk = S.Skeleton()
    c = S.Creature("Chimera", sk, step=0.075)
    body, chest, hips, legs = lion_body(c, sk)
    goat_head(c, sk, body, "G", P(0, 3.15, -0.05))
    # The tail is a serpent: thick, banded, ending in a fanged head (TailHead).
    pts = [P(0, 2.6, 1.6), P(0, 2.35, 2.3), P(0, 1.95, 2.95), P(0, 1.75, 3.6), P(0, 1.95, 4.15)]
    names = ["Tail", "Tail2", "Tail3", "Tail4"]
    prev = hips
    for i, n in enumerate(names):
        prev = sk.add(n, prev, pts[i])
    tail_head = sk.add("TailHead", prev, pts[4])
    radii = [0.24, 0.21, 0.18, 0.16, 0.15]
    for i, n in enumerate(names):
        c.add(RC(pts[i], pts[i + 1], radii[i], radii[i + 1], n, blend=0.12 if i == 0 else 0.0))
        c.add(RC(pts[i] + P(0, -radii[i] * 0.5, 0), pts[i + 1] + P(0, -radii[i + 1] * 0.5, 0), radii[i] * 0.55,
                 radii[i + 1] * 0.55, n, "Under", blend=0.02))
        mid = (pts[i] + pts[i + 1]) / 2
        c.add(EL(mid + P(0, radii[i] * 0.75, 0), P(radii[i] * 0.5, radii[i] * 0.22, radii[i] * 0.7), n, "Dark", blend=0.0))
    th = tail_head.name
    hp = pts[4]
    c.add(EL(hp + P(0, 0.12, 0.05), P(0.24, 0.17, 0.3), th, blend=0.06))
    c.add(RC(hp + P(0, 0.14, 0.2), hp + P(0, 0.08, 0.6), 0.2, 0.1, th, blend=0.06))
    for side in (-1, 1):
        c.solid(EL(hp + P(side * 0.17, 0.22, 0.3), P(0.05, 0.045, 0.05), th, "Eye"))
        c.add(RC(hp + P(side * 0.07, 0.02, 0.55), hp + P(side * 0.07, -0.14, 0.58), 0.03, 0.008, th, "Horn", blend=0.0))
    bat_wings(c, sk, chest)
    return c, {"plan": "Quadruped", "legs": legs, "heads": ["", "G"], "tail": names}


# ---------------------------------------------------------------------------
# Batch C (D-58): dragons, griffins, steeds, the bat, the harpy, the gorgon,
# the sprite
# ---------------------------------------------------------------------------


def lion_horns(c, base, bone):
    """Two short curved horns (Horns trait: Nian)."""
    horns = []
    for side in (-1, 1):
        prev, r = base + P(side * 0.22, 1.02, -0.62), 0.1
        for k in range(1, 5):
            a = k / 4 * math.pi * 0.7
            q = base + P(side * (0.22 + 0.1 * k), 1.02 + math.sin(a) * 0.38, -0.62 + (1 - math.cos(a)) * 0.45)
            horns.append(RC(prev, q, r, r * 0.78, bone, "Horns", blend=0.02))
            prev, r = q, r * 0.78
    c.group(horns)


def reptile_torso(c, sk, bulk=1.0):
    """A dragon's barrel: Body / Chest / Hips where the canine legs expect them, plated belly, spined back."""
    body = sk.add("Body", None, P(0, 2.35, 0))
    chest = sk.add("Chest", body, P(0, 2.4, -0.9))
    hips = sk.add("Hips", body, P(0, 2.35, 0.95))
    b = bulk
    c.add(EL(P(0, 2.35, 0), P(0.9 * b, 0.82, 1.35), "Body", blend=0.25))
    c.add(EL(P(0, 2.5, -0.95), P(0.95 * b, 0.86, 0.85), "Chest", blend=0.25))
    c.add(EL(P(0, 2.35, 1.0), P(0.85 * b, 0.76, 0.8), "Hips", blend=0.25))
    for i in range(7):
        z = -1.35 + i * 0.42
        bone = "Chest" if z < -0.5 else ("Body" if z < 0.6 else "Hips")
        c.add(EL(P(0, 1.62 + abs(z) * 0.06, z), P(0.6 * b, 0.12, 0.2), bone, "Under", blend=0.05))
    for i in range(8):
        z = -1.4 + i * 0.4
        bone = "Chest" if z < -0.5 else ("Body" if z < 0.6 else "Hips")
        c.add(RC(P(0, 3.08 - abs(z) * 0.05, z), P(0, 3.5 - abs(z) * 0.1, z + 0.28), 0.13, 0.015, bone, "Horn", blend=0.05))
    return body, chest, hips


def dragon_head(c, sk, chest, base):
    """A long neck rising to a horned, frilled dragon's head with a toothed jaw."""
    neck = sk.add("Neck", chest, base)
    hp = base + P(0, 1.15, -0.85)
    head = sk.add("Head", neck, hp)
    jaw = sk.add("Jaw", head, hp + P(0, -0.2, -0.3))
    n, h, j = neck.name, head.name, jaw.name
    # The neck: an S of tapering segments, spines along the crest.
    pts = [base + P(0, -0.2, 0.25), base + P(0, 0.35, -0.2), base + P(0, 0.85, -0.55), hp + P(0, -0.05, 0.1)]
    radii = [0.62, 0.5, 0.42, 0.36]
    for k in range(3):
        c.add(RC(pts[k], pts[k + 1], radii[k], radii[k + 1], n, blend=0.18))
        c.add(RC(pts[k] + P(0, -radii[k] * 0.5, -0.12), pts[k + 1] + P(0, -radii[k + 1] * 0.5, -0.12), radii[k] * 0.5,
                 radii[k + 1] * 0.5, n, "Under", blend=0.04))
        q = (pts[k] + pts[k + 1]) / 2
        c.add(RC(q + P(0, radii[k] * 0.8, 0.1), q + P(0, radii[k] * 0.8 + 0.4, 0.35), 0.1, 0.012, n, "Horn", blend=0.04))
    # Skull, brow ridges, a long snout with nostrils, teeth, eyes.
    c.add(EL(hp + P(0, 0.1, -0.15), P(0.4, 0.34, 0.45), h, blend=0.12))
    c.add(RC(hp + P(0, 0.08, -0.4), hp + P(0, -0.05, -1.25), 0.3, 0.17, h, blend=0.1))
    for side in (-1, 1):
        c.add(EL(hp + P(side * 0.24, 0.3, -0.42), P(0.15, 0.08, 0.3), h, "Dark", blend=0.04))
        c.solid(EL(hp + P(side * 0.27, 0.22, -0.52), P(0.07, 0.055, 0.08), h, "Eye"))
        c.add(EL(hp + P(side * 0.1, 0.04, -1.25), P(0.05, 0.04, 0.04), h, "Dark", blend=0.01))
        for k in range(4):
            z = -0.55 - k * 0.18
            c.add(RC(hp + P(side * 0.2 * (1 - k * 0.12), -0.12, z), hp + P(side * 0.2 * (1 - k * 0.12), -0.3, z - 0.02),
                     0.03, 0.006, h, "Horn", blend=0.0))
        # Swept-back frills behind the jaw.
        c.add(EL(hp + P(side * 0.42, 0.05, 0.2), P(0.05, 0.3, 0.38), h, "Wing", blend=0.04,
                 rot=S.rot_y(side * math.radians(-30)) @ S.rot_x(math.radians(-25))))
    c.add(RC(hp + P(0, -0.2, -0.35), hp + P(0, -0.24, -1.15), 0.2, 0.11, j, "Under", blend=0.04))
    # Horns (Horns trait): two long swept-back horns and a nose horn.
    horns = [RC(hp + P(0, 0.12, -1.0), hp + P(0, 0.42, -0.95), 0.08, 0.01, h, "Horns", blend=0.02)]
    for side in (-1, 1):
        prev, r = hp + P(side * 0.25, 0.35, -0.1), 0.13
        for k in range(1, 6):
            q = hp + P(side * (0.25 + 0.06 * k), 0.35 + 0.17 * k - 0.012 * k * k, -0.1 + 0.24 * k)
            horns.append(RC(prev, q, r, r * 0.8, h, "Horns", blend=0.02))
            prev, r = q, r * 0.8
    c.group(horns)
    return neck, head, jaw


def long_tail(c, sk, hips, pts, radii, prefix_spines=True, region="Hide"):
    names = ["Tail"] + [f"Tail{i + 2}" for i in range(len(pts) - 2)]
    prev = hips
    for i, n in enumerate(names):
        prev = sk.add(n, prev, pts[i])
    for i, n in enumerate(names):
        c.add(RC(pts[i], pts[i + 1], radii[i], radii[i + 1], n, region, blend=0.15 if i == 0 else 0.0))
        c.add(RC(pts[i] + P(0, -radii[i] * 0.5, 0), pts[i + 1] + P(0, -radii[i + 1] * 0.5, 0), radii[i] * 0.55,
                 radii[i + 1] * 0.55, n, "Under", blend=0.02))
        if prefix_spines:
            q = (pts[i] + pts[i + 1]) / 2
            r = (radii[i] + radii[i + 1]) / 2
            c.add(RC(q + P(0, r * 0.8, -0.1), q + P(0, r * 0.8 + 0.3 * r / radii[0] + 0.08, 0.15), 0.1 * r / radii[0] + 0.03,
                     0.008, n, "Horn", blend=0.03))
    return names, prev


def dragon():
    """A great dragon: horned head on a long neck, bat wings, plated belly, a spined tail ending in a blade."""
    sk = S.Skeleton()
    c = S.Creature("Dragon", sk, step=0.085)
    body, chest, hips = reptile_torso(c, sk, bulk=1.05)
    dragon_head(c, sk, chest, P(0, 2.95, -1.5))
    legs = quad_legs(c, sk, chest, hips, front_x=0.72, hind_x=0.68, thick=1.35, paw=1.35)
    pts = [P(0, 2.45, 1.65), P(0, 2.2, 2.6), P(0, 1.75, 3.55), P(0, 1.25, 4.45), P(0, 0.85, 5.3), P(0, 0.6, 6.1), P(0, 0.5, 6.8)]
    radii = [0.6, 0.5, 0.4, 0.31, 0.22, 0.14, 0.06]
    tail, last = long_tail(c, sk, hips, pts, radii)
    # A spade-shaped blade at the tip.
    c.add(EL(P(0, 0.55, 6.9), P(0.38, 0.06, 0.3), last.name, "Horn", blend=0.03))
    bat_wings(c, sk, chest, at=P(0.5, 3.15, -0.75), size=1.45, thick=1.4)
    return c, {"plan": "Quadruped", "legs": legs, "heads": [""], "tail": tail}


def eagle_head(c, sk, chest, base):
    """An eagle's head: feathered neck ruff, hooked beak (lower beak on the jaw), fierce brow, feathered crest."""
    neck = sk.add("Neck", chest, base)
    hp = base + P(0, 0.62, -0.5)
    head = sk.add("Head", neck, hp)
    jaw = sk.add("Jaw", head, hp + P(0, -0.08, -0.4))
    n, h, j = neck.name, head.name, jaw.name
    c.add(RC(base + P(0, -0.1, 0.25), hp + P(0, 0.0, 0.05), 0.55, 0.36, n, blend=0.2))
    c.add(EL(hp + P(0, 0.1, -0.12), P(0.36, 0.36, 0.42), h, blend=0.12))
    c.add(EL(hp + P(0, 0.26, -0.38), P(0.3, 0.09, 0.2), h, "Dark", blend=0.04))
    # The beak: a broad base narrowing to a hooked tip.
    c.add(RC(hp + P(0, 0.08, -0.42), hp + P(0, 0.02, -0.82), 0.17, 0.1, h, "Horn", blend=0.05))
    c.add(RC(hp + P(0, 0.02, -0.82), hp + P(0, -0.18, -0.95), 0.1, 0.02, h, "Horn", blend=0.03))
    c.add(RC(hp + P(0, -0.12, -0.45), hp + P(0, -0.12, -0.78), 0.11, 0.04, j, "Horn", blend=0.03))
    for side in (-1, 1):
        c.solid(EL(hp + P(side * 0.25, 0.16, -0.4), P(0.075, 0.07, 0.07), h, "Eye"))
    # Crest feathers sweeping back, and a ruff of feathers round the neck.
    for k, dx in enumerate((-0.16, 0.0, 0.16)):
        c.add(RC(hp + P(dx, 0.35, -0.05), hp + P(dx * 1.6, 0.55 + (0.12 if dx == 0 else 0), 0.65), 0.08, 0.015, h, "Mane", blend=0.03))
    shaggy_ruff(c, base + P(0, 0.25, 0.05), 0.0, n, radius=0.55, length=0.55, count=11, glow_every=0)
    return neck, head, jaw


def lion_tail(c, sk, hips, tuft=True):
    pts = [P(0, 2.6, 1.62), P(0, 2.25, 2.25), P(0, 1.65, 2.75), P(0, 1.25, 3.2), P(0, 1.3, 3.75)]
    names = ["Tail", "Tail2", "Tail3", "Tail4"]
    prev = hips
    for i, n in enumerate(names):
        prev = sk.add(n, prev, pts[i])
    radii = [0.15, 0.12, 0.1, 0.085, 0.075]
    for i, n in enumerate(names):
        c.add(RC(pts[i], pts[i + 1], radii[i], radii[i + 1], n, blend=0.1 if i == 0 else 0.0))
    if tuft:
        c.add(EL(P(0, 1.33, 3.85), P(0.17, 0.18, 0.3), "Tail4", "Mane", blend=0.05))
    return names


def griffin():
    """Eagle before, lion behind: a feathered head and great wings on a lion's body."""
    sk = S.Skeleton()
    c = S.Creature("Griffin", sk, step=0.072)
    body, chest, hips = canine_torso(c, sk, deep=1.05, bulk=1.08)
    eagle_head(c, sk, chest, P(0, 2.75, -1.45))
    # Feathers over the chest and shoulders.
    c.add(EL(P(0, 2.45, -1.25), P(0.66, 0.62, 0.5), "Chest", "Mane", blend=0.15))
    legs = quad_legs(c, sk, chest, hips, front_x=0.6, hind_x=0.58, thick=1.18, paw=1.3)
    tail = lion_tail(c, sk, hips)
    feathered_wings(c, sk, chest, at=P(0.45, 3.05, -0.8), size=1.15)
    return c, {"plan": "Quadruped", "legs": legs, "heads": [""], "tail": tail}


def steed():
    """A horse / stag: long legs ending in hooves, an arched neck with a flowing mane; optional antlers and wings."""
    sk = S.Skeleton()
    c = S.Creature("Steed", sk, step=0.072)
    body = sk.add("Body", None, P(0, 3.0, 0))
    chest = sk.add("Chest", body, P(0, 3.05, -1.0))
    hips = sk.add("Hips", body, P(0, 3.0, 1.05))
    c.add(EL(P(0, 3.0, 0), P(0.72, 0.78, 1.45), "Body", blend=0.25))
    c.add(EL(P(0, 3.05, -1.0), P(0.72, 0.88, 0.75), "Chest", blend=0.25))
    c.add(EL(P(0, 3.08, 1.05), P(0.76, 0.78, 0.78), "Hips", blend=0.25))
    c.add(EL(P(0, 2.45, -0.1), P(0.5, 0.3, 1.0), "Body", "Under", blend=0.1))
    legs = {}
    for side, tag in mirror(None):
        x = side * 0.48
        pts = [P(x, 2.75, -1.12), P(x, 1.9, -0.72), P(x, 0.5, -1.1), P(x, 0.12, -1.15)]
        bones, angles = sk.chain_down([f"LegF{tag}", f"LegF{tag}b", f"LegF{tag}c"], chest, pts)
        legs[f"LegF{tag}"] = (pts, angles, -1, 0.0)
        a, b, f = bones
        c.add(EL(P(x * 0.95, 2.95, -1.1), P(0.24, 0.55, 0.4), chest.name, blend=0.2))
        c.add(RC(pts[0], pts[1], 0.27, 0.17, a.name, blend=0.15))
        c.add(RC(pts[1], pts[2], 0.14, 0.1, b.name, blend=0.06))
        c.add(EL(pts[1] + P(0, -0.55, 0.0), P(0.13, 0.12, 0.13), b.name, blend=0.06))
        c.add(RC(pts[2], pts[3], 0.1, 0.12, f.name, blend=0.04))
        c.add(RC(P(x, 0.28, -1.17), P(x, 0.06, -1.22), 0.16, 0.18, f.name, "Dark", blend=0.03))
        c.add(RC(P(x, 0.62, -1.02), P(x, 0.3, -0.98), 0.12, 0.15, f.name, "Dark", blend=0.03))
    for side, tag in mirror(None):
        x = side * 0.5
        pts = [P(x, 2.9, 1.1), P(x, 2.0, 0.55), P(x, 1.05, 1.42), P(x, 0.12, 1.2)]
        bones, angles = sk.chain_down([f"LegB{tag}", f"LegB{tag}b", f"LegB{tag}c"], hips, pts)
        legs[f"LegB{tag}"] = (pts, angles, 1, 0.0)
        a, b, f = bones
        c.add(RC(pts[0], pts[1], 0.42, 0.2, a.name, blend=0.2))
        c.add(EL(P(x * 0.9, 2.55, 1.1), P(0.3, 0.55, 0.45), a.name, blend=0.15))
        c.add(RC(pts[1], pts[2], 0.18, 0.11, b.name, blend=0.06))
        c.add(RC(pts[2], pts[3], 0.1, 0.12, f.name, blend=0.04))
        c.add(RC(P(x, 0.28, 1.2), P(x, 0.06, 1.15), 0.16, 0.18, f.name, "Dark", blend=0.03))
        c.add(RC(P(x, 0.62, 1.25), P(x, 0.3, 1.2), 0.12, 0.15, f.name, "Dark", blend=0.03))
    # An arched neck to a long head.
    base = P(0, 3.45, -1.45)
    neck = sk.add("Neck", chest, base)
    hp = base + P(0, 1.05, -0.55)
    head = sk.add("Head", neck, hp)
    jaw = sk.add("Jaw", head, hp + P(0, -0.42, -0.42))
    c.add(RC(base + P(0, -0.35, 0.3), base + P(0, 0.45, -0.25), 0.55, 0.38, neck.name, blend=0.2))
    c.add(RC(base + P(0, 0.45, -0.25), hp + P(0, 0.0, 0.05), 0.38, 0.3, neck.name, blend=0.15))
    c.add(EL(hp + P(0, 0.02, -0.1), P(0.27, 0.3, 0.36), head.name, blend=0.12))
    c.add(RC(hp + P(0, -0.05, -0.3), hp + P(0, -0.45, -0.85), 0.22, 0.17, head.name, blend=0.1))
    c.add(EL(hp + P(0, -0.5, -0.9), P(0.18, 0.15, 0.15), head.name, "Dark", blend=0.05))
    c.add(RC(hp + P(0, -0.42, -0.4), hp + P(0, -0.58, -0.78), 0.13, 0.1, jaw.name, "Under", blend=0.04))
    for side in (-1, 1):
        c.solid(EL(hp + P(side * 0.25, 0.04, -0.3), P(0.06, 0.06, 0.07), head.name, "Eye"))
        c.add(RC(hp + P(side * 0.14, 0.28, 0.0), hp + P(side * 0.2, 0.62, 0.05), 0.07, 0.015, head.name, "Dark", blend=0.03))
        c.add(EL(hp + P(side * 0.08, -0.47, -1.03), P(0.035, 0.03, 0.02), head.name, "Dark", blend=0.01))
    # Mane down the crest of the neck and a forelock.
    for k in range(9):
        t = k / 8
        q = (base + P(0, 0.35, 0.2)) * (1 - t) + (hp + P(0, 0.3, 0.12)) * t
        c.add(RC(q, q + P(0, 0.05, 0.42) + P(0, -0.12, 0) * (1 - t), 0.14, 0.03, neck.name if t < 0.85 else head.name,
                 "Mane", blend=0.04))
    c.add(RC(hp + P(0, 0.35, -0.08), hp + P(0, 0.05, -0.45), 0.1, 0.02, head.name, "Mane", blend=0.03))
    # Antlers (Horns trait: Peryton).
    antlers = []
    for side in (-1, 1):
        root = hp + P(side * 0.15, 0.3, 0.02)
        main = [root, root + P(side * 0.25, 0.45, 0.1), root + P(side * 0.45, 0.9, 0.05), root + P(side * 0.5, 1.35, -0.1)]
        for k in range(3):
            antlers.append(RC(main[k], main[k + 1], 0.1 - 0.015 * k, 0.085 - 0.015 * k, head.name, "Horns", blend=0.02))
            tine = main[k + 1]
            antlers.append(RC(tine, tine + P(side * 0.05, 0.32, -0.22), 0.065, 0.035, head.name, "Horns", blend=0.02))
    c.group(antlers)
    # A flowing tail.
    tail_pts = [P(0, 3.35, 1.7), P(0, 3.0, 2.15), P(0, 2.2, 2.45), P(0, 1.35, 2.5)]
    names = ["Tail", "Tail2", "Tail3"]
    prev = hips
    for i, n in enumerate(names):
        prev = sk.add(n, prev, tail_pts[i])
        c.add(RC(tail_pts[i], tail_pts[i + 1], 0.16 + 0.06 * i, 0.2 + 0.05 * i, n, "Mane", blend=0.08 if i == 0 else 0.03))
    feathered_wings(c, sk, chest, at=P(0.45, 3.65, -0.8), size=1.1)
    return c, {"plan": "Quadruped", "legs": legs, "heads": [""], "tail": names}


def bat_head(c, sk, chest, base):
    """A bat's head: great pointed ears, a nose leaf, a short muzzle full of fangs."""
    neck = sk.add("Neck", chest, base)
    hp = base + P(0, 0.55, -0.45)
    head = sk.add("Head", neck, hp)
    jaw = sk.add("Jaw", head, hp + P(0, -0.15, -0.3))
    c.add(RC(base + P(0, -0.1, 0.25), hp + P(0, 0.0, 0.05), 0.52, 0.36, neck.name, blend=0.2))
    c.add(EL(hp + P(0, 0.08, -0.12), P(0.38, 0.34, 0.36), head.name, blend=0.12))
    c.add(RC(hp + P(0, 0.0, -0.35), hp + P(0, -0.05, -0.68), 0.2, 0.14, head.name, blend=0.08))
    c.add(EL(hp + P(0, 0.12, -0.7), P(0.09, 0.14, 0.04), head.name, "Dark", blend=0.03))
    c.add(RC(hp + P(0, -0.2, -0.35), hp + P(0, -0.22, -0.62), 0.13, 0.08, jaw.name, "Under", blend=0.03))
    for side in (-1, 1):
        c.add(EL(hp + P(side * 0.3, 0.6, 0.0), P(0.1, 0.42, 0.2), head.name, "Dark", blend=0.05,
                 rot=S.rot_z(side * math.radians(-22))))
        c.solid(EL(hp + P(side * 0.2, 0.15, -0.42), P(0.07, 0.06, 0.06), head.name, "Eye"))
        c.add(RC(hp + P(side * 0.09, -0.1, -0.6), hp + P(side * 0.09, -0.32, -0.62), 0.04, 0.008, head.name, "Horn", blend=0.0))
    return neck, head, jaw


def bat():
    """A wolf-sized death bat: hound's frame, great ears, leathery wings, spines (Spikes trait)."""
    sk = S.Skeleton()
    c = S.Creature("Bat", sk, step=0.072)
    body, chest, hips = canine_torso(c, sk, deep=1.0, bulk=1.05)
    bat_head(c, sk, chest, P(0, 2.75, -1.45))
    legs = quad_legs(c, sk, chest, hips, thick=1.05, paw=1.1)
    tail = bushy_tail(c, sk, hips, thick=0.55)
    bat_wings(c, sk, chest, at=P(0.45, 3.0, -0.7), size=1.25, thick=1.1)
    c.group([
        RC(P(0, 2.98 - i * 0.04, -0.6 + i * 0.4), P(0, 3.55 - i * 0.08, -0.35 + i * 0.4), 0.13, 0.015,
           "Chest" if i < 2 else ("Body" if i < 4 else "Hips"), "Spikes", blend=0.03)
        for i in range(6)
    ])
    return c, {"plan": "Quadruped", "legs": legs, "heads": [""], "tail": tail}


def harpy():
    """The harpy queen: an armoured, feather-cloaked bird-woman with wings along her arms and taloned feet."""
    sk = S.Skeleton()
    c = S.Creature("Harpy", sk, step=0.055)
    body = sk.add("Body", None, P(0, 2.4, 0))
    head = sk.add("Head", body, P(0, 4.0, -0.05))
    arms = {}
    for side, tag in mirror(None):
        arm = sk.add(f"Arm{tag}", body, P(side * 0.6, 3.7, 0.0))
        arms[side] = (arm, sk.add(f"Arm{tag}2", arm, P(side * 0.82, 2.85, 0.05)))
    # Slim feathered body, a breastplate, a feathered skirt.
    c.add(EL(P(0, 2.5, 0.05), P(0.42, 0.35, 0.32), "Body", blend=0.12))
    c.add(EL(P(0, 3.0, 0.0), P(0.36, 0.42, 0.28), "Body", blend=0.12))
    c.add(EL(P(0, 3.45, -0.02), P(0.5, 0.4, 0.34), "Body", "Metal", blend=0.1))
    c.add(EL(P(0, 3.45, -0.32), P(0.1, 0.12, 0.04), "Body", "Glow", blend=0.0))
    for k in range(10):
        a = (k / 9 - 0.5) * math.pi * 1.6
        d = P(math.sin(a), 0, -math.cos(a)) * 0.4
        c.add(EL(P(0, 2.2, 0.05) + d, P(0.12, 0.38, 0.07), "Body", "Mane", blend=0.03,
                 rot=S.rot_y(a) @ S.rot_x(math.radians(-14))))
    # Tail feathers fanning behind.
    for k in range(5):
        a = (k / 4 - 0.5) * 1.2
        c.add(EL(P(math.sin(a) * 0.5, 2.25, 0.75), P(0.11, 0.05, 0.55), "Body", "Mane", blend=0.02,
                 rot=S.rot_y(a) @ S.rot_x(math.radians(25))))
    # Head: a feathered helm with a glowing visor, a crest and trailing plumes.
    c.add(EL(P(0, 3.85, 0.0), P(0.16, 0.2, 0.15), "Body", blend=0.08))
    c.add(EL(P(0, 4.22, -0.05), P(0.28, 0.32, 0.3), "Head", blend=0.08))
    c.add(EL(P(0, 4.28, -0.12), P(0.3, 0.26, 0.28), "Head", "Metal", blend=0.04))
    c.solid(EL(P(0, 4.22, -0.38), P(0.18, 0.035, 0.05), "Head", "Eye"))
    c.add(RC(P(0, 4.15, -0.38), P(0, 3.98, -0.46), 0.06, 0.02, "Head", "Horn", blend=0.02))
    for k, dx in enumerate((-0.18, -0.06, 0.06, 0.18)):
        c.add(RC(P(dx, 4.45, -0.05), P(dx * 2.2, 4.75 - abs(dx), 0.7), 0.07, 0.015, "Head", "Mane", blend=0.03))
        c.add(RC(P(dx, 4.2, 0.2), P(dx * 1.4, 3.35, 0.55), 0.07, 0.02, "Head", "Mane", blend=0.03))
    # Arms: slender, with wings of long feathers along them (Wings trait).
    for side, (arm, fore) in arms.items():
        x = side
        c.add(EL(P(x * 0.58, 3.74, 0), P(0.17, 0.11, 0.17), arm.name, "Metal", blend=0.04))
        c.add(RC(P(x * 0.6, 3.7, 0), P(x * 0.82, 2.85, 0.05), 0.12, 0.1, arm.name, blend=0.06))
        c.add(RC(P(x * 0.82, 2.85, 0.05), P(x * 0.88, 2.1, -0.1), 0.1, 0.08, fore.name, "Metal", blend=0.04))
        for k in range(3):
            c.add(RC(P(x * 0.88, 2.1, -0.1), P(x * (0.85 + 0.06 * (k - 1)), 1.85, -0.25), 0.04, 0.008, fore.name, "Horn", blend=0.02))
        wing = []
        for k in range(12):
            t = (k + 0.5) / 12
            bone = arm.name if t < 0.5 else fore.name
            q = P(x * 0.6, 3.7, 0) * (1 - t) + P(x * 0.88, 2.1, -0.1) * t
            length = 0.8 + 0.7 * math.sin(t * math.pi * 0.9)
            out = q + P(x * length * 0.8, -0.15, length * 0.55)
            wing.append(EL((q + out) / 2, P(0.075, 0.13, length / 2 + 0.08), bone, "Wing" if side < 0 else "Wing2", blend=0.03,
                           rot=along(q, out, up=(0.0, 1.0, 0.0))))
        c.group(wing)

    def foot(side, px, pts, names, thick):
        a, b, f = names
        c.add(RC(pts[0], pts[1], 0.24, 0.17, a, "Mane", blend=0.1))
        c.add(RC(pts[1], pts[2], 0.1, 0.07, b, "Dark", blend=0.04))
        c.add(RC(pts[2], pts[3], 0.07, 0.07, f, "Dark", blend=0.03))
        for k in (-1, 0, 1):
            tip = P(px + k * 0.15, 0.05, -0.32)
            c.add(RC(P(px, 0.12, 0.05), tip, 0.05, 0.035, f, "Dark", blend=0.02))
            c.add(RC(tip, tip + P(0, -0.04, -0.12), 0.035, 0.006, f, "Horn", blend=0.0))
        c.add(RC(P(px, 0.12, 0.08), P(px, 0.05, 0.35), 0.04, 0.01, f, "Horn", blend=0.0))

    legs = biped_legs(c, sk, body, 0.28, 2.3, 1.3, 0.42, 1.0, foot)
    return c, {"plan": "Biped", "legs": legs, "heads": [""]}


def gorgon():
    """The gorgon: an armoured torso rising from a serpent's body, a crown of snakes for hair."""
    sk = S.Skeleton()
    c = S.Creature("Gorgon", sk, step=0.07)
    body = sk.add("Body", None, P(0, 0.6, 0))
    c.add(EL(P(0, 0.65, 0.1), P(0.72, 0.6, 0.95), "Body", blend=0.15))
    c.add(EL(P(0, 0.32, 0.1), P(0.52, 0.22, 0.85), "Body", "Under", blend=0.02))
    # The torso rises as the serpent's "neck": waist, ribs, chest.
    pts = [P(0, 0.9, -0.5), P(0, 1.9, -0.72), P(0, 2.85, -0.82), P(0, 3.45, -0.85)]
    names = ["Neck", "NeckB", "NeckC"]
    prev = body
    for i, n in enumerate(names):
        prev = sk.add(n, prev, pts[i])
    c.add(RC(pts[0] + P(0, -0.3, 0.3), pts[1], 0.6, 0.42, "Neck", blend=0.15))
    c.add(RC(pts[0] + P(0, -0.2, -0.32), pts[1] + P(0, 0, -0.28), 0.32, 0.22, "Neck", "Under", blend=0.04))
    c.add(RC(pts[1], pts[2], 0.4, 0.44, "NeckB", blend=0.1))
    c.add(EL(pts[2] + P(0, 0.0, 0.02), P(0.55, 0.4, 0.36), "NeckC", "Metal", blend=0.08))
    c.add(EL(pts[2] + P(0, 0.02, -0.34), P(0.12, 0.14, 0.05), "NeckC", "Glow", blend=0.0))
    c.add(EL(pts[1] + P(0, 0.35, 0.0), P(0.5, 0.12, 0.38), "NeckB", "Horn", blend=0.02))
    head = sk.add("Head", "NeckC", pts[3])
    sk.add("Jaw", head, pts[3] + P(0, 0.05, -0.25))
    c.add(RC(pts[2] + P(0, 0.3, 0), pts[3] + P(0, 0.05, 0), 0.16, 0.14, "NeckC", blend=0.06))
    c.add(EL(pts[3] + P(0, 0.3, -0.02), P(0.27, 0.32, 0.28), "Head", blend=0.08))
    c.add(EL(pts[3] + P(0, 0.42, -0.04), P(0.3, 0.22, 0.3), "Head", "Metal", blend=0.04))
    c.solid(EL(pts[3] + P(0, 0.3, -0.3), P(0.17, 0.035, 0.05), "Head", "Eye"))
    # Snakes for hair: each curls out and down, ending in a little head.
    for k in range(9):
        a = (k / 8 - 0.5) * math.pi * 1.5
        d = P(math.sin(a), 0, math.cos(a))
        r0 = pts[3] + P(0, 0.5, 0.02) + d * 0.18
        mid = r0 + d * 0.35 + P(0, 0.25, 0)
        tip = mid + d * 0.3 + P(0, -0.25, 0)
        c.add(RC(r0, mid, 0.06, 0.05, "Head", "Dark", blend=0.02))
        c.add(RC(mid, tip, 0.05, 0.04, "Head", "Dark", blend=0.0))
        c.add(EL(tip + d * 0.05, P(0.07, 0.05, 0.07), "Head", "Glow" if k % 3 == 1 else "Dark", blend=0.01))
    # Arms with bracers and claws.
    for side, tag in mirror(None):
        x = side
        arm = sk.add(f"Arm{tag}", "NeckC", P(x * 0.55, 3.05, -0.82))
        fore = sk.add(f"Arm{tag}2", arm, P(x * 0.72, 2.3, -0.85))
        c.add(EL(P(x * 0.55, 3.08, -0.82), P(0.22, 0.17, 0.22), arm.name, "Metal", blend=0.05))
        c.add(RC(P(x * 0.55, 3.05, -0.82), P(x * 0.72, 2.3, -0.85), 0.12, 0.1, arm.name, blend=0.06))
        c.add(RC(P(x * 0.72, 2.3, -0.85), P(x * 0.78, 1.6, -1.0), 0.11, 0.09, fore.name, "Metal", blend=0.04))
        for k in (-1, 0, 1):
            c.add(RC(P(x * 0.78, 1.6, -1.0), P(x * (0.78 + 0.06 * k), 1.38, -1.1), 0.04, 0.008, fore.name, "Horn", blend=0.02))
    # The serpent body trailing behind.
    segs = []
    prev = body
    count = 10
    spts, radii = [P(0, 0.62, 0.6)], [0.68]
    z = 0.6
    for i in range(1, count + 1):
        t = i / count
        z += 1.0 - 0.3 * t
        spts.append(P(0, 0.08 + 0.54 * (1 - t) ** 0.8, z))
        radii.append(0.07 + 0.61 * (1 - t) ** 0.85)
    for i in range(count):
        name = f"Seg{i + 1}"
        prev = sk.add(name, prev, spts[i])
        segs.append(name)
        c.add(RC(spts[i], spts[i + 1], radii[i], radii[i + 1], name, blend=0.0))
        c.add(RC(spts[i] + P(0, -radii[i] * 0.5, 0), spts[i + 1] + P(0, -radii[i + 1] * 0.5, 0), radii[i] * 0.52,
                 radii[i + 1] * 0.52, name, "Under", blend=0.02))
        if i % 2 == 0 and i < count - 1:
            mid = (spts[i] + spts[i + 1]) / 2
            rr = (radii[i] + radii[i + 1]) / 2
            c.add(EL(mid + P(0, rr * 0.8, 0), P(rr * 0.45, rr * 0.2, rr * 0.6), name, "Dark", blend=0.0))
    return c, {"plan": "Serpent", "heads": [""], "necks": {"": names}, "segments": segs}


def sprite():
    """A rift sprite: a glowing crystal heart in a shell of shards, petal wings, trailing wisps."""
    sk = S.Skeleton()
    c = S.Creature("Sprite", sk, step=0.04)
    body = sk.add("Body", None, P(0, 2.2, 0))
    c.add(EL(P(0, 2.2, 0), P(0.32, 0.38, 0.32), "Body", "Glow", blend=0.05))
    rng = np.random.default_rng(3)
    for k in range(9):
        d = rng.normal(size=3)
        d[1] = abs(d[1]) * 0.4 + (0.3 if k < 5 else -0.5)
        d /= np.linalg.norm(d)
        q = P(0, 2.2, 0) + d * 0.3
        c.add(RC(q - d * 0.1, q + d * (0.32 + 0.12 * (k % 3)), 0.11, 0.025, "Body", "Petal", blend=0.02))
    # Wisps trailing below.
    for k in range(5):
        a = k / 5 * math.pi * 2
        q = P(math.cos(a) * 0.15, 1.95, math.sin(a) * 0.15)
        c.add(RC(q, q + P(math.cos(a) * 0.25, -0.75 - 0.15 * (k % 2), math.sin(a) * 0.25 + 0.15), 0.08, 0.035, "Body", "Glow",
                 blend=0.04))
    # Petal wings on WingL / WingR (they flap about Y).
    for side, tag in mirror(None):
        x = side
        w = sk.add(f"Wing{tag}", body, P(x * 0.25, 2.35, 0.12))
        for k, (dy, length) in enumerate(((0.25, 0.85), (-0.2, 0.6))):
            a = P(x * 0.25, 2.35, 0.12)
            b = a + P(x * length, dy + 0.15, 0.2)
            c.add(EL((a + b) / 2, P(0.045, 0.16 + 0.05 * (1 - k), length / 2), w.name, "Petal", blend=0.02,
                     rot=along(a, b, up=(0.0, 0.0, 1.0))))
    return c, {"plan": "Sprite", "heads": []}


# ---------------------------------------------------------------------------
# The undead of the Abyssal Spire (PLAN.md D-133): five humanoid shapes on
# the knight's bones (Body, Head, ArmL/ArmL2, ArmR/ArmR2, LegL.., LegR..),
# so the biped animator drives them all. Non-graphic: clean bone, rags and
# armour, glowing eyes; no wounds or gore.
# ---------------------------------------------------------------------------


def humanoid_arms(sk, body, shoulder, elbow):
    """ArmL/ArmL2 and ArmR/ArmR2 from one side's shoulder and elbow (x > 0)."""
    arms = {}
    for side, tag in mirror(None):
        s = P(side * shoulder[0], shoulder[1], shoulder[2])
        e = P(side * elbow[0], elbow[1], elbow[2])
        arm = sk.add(f"Arm{tag}", body, s)
        arms[side] = (arm, sk.add(f"Arm{tag}2", arm, e))
    return arms


def sword(c, bone, grip, tip, width=0.16, glow=True):
    """A straight blade from a hand at `grip` towards `tip`: pommel, guard, blade, rune channel."""
    d = (tip - grip) / float(np.linalg.norm(tip - grip))
    guard = grip + d * 0.14
    c.add(RC(grip - d * 0.22, guard, 0.05, 0.05, bone, "Dark", blend=0.0))
    c.add(EL(grip - d * 0.26, P(0.06, 0.06, 0.06), bone, "Horn", blend=0.0))
    across = np.cross(d, P(0, 0, 1.0))
    if np.linalg.norm(across) < 1e-3:
        across = P(1.0, 0, 0)
    across = across / np.linalg.norm(across)
    c.add(RC(guard - across * 0.24, guard + across * 0.24, 0.05, 0.05, bone, "Horn", blend=0.0))
    length = float(np.linalg.norm(tip - guard))
    c.add(EL((guard + tip) / 2, P(0.05, width, length / 2), bone, "Blade", blend=0.0,
             rot=along(guard, tip, up=tuple(across))))
    if glow:
        c.add(RC(guard + (tip - guard) * 0.06, guard + (tip - guard) * 0.72, 0.03, 0.018, bone, "Glow", blend=0.0))


def skull(c, bone, jaw_bone, centre, size=1.0, helm=False):
    """A clean, cartoon-proportioned skull facing -Z with glowing eye points."""
    x0, y0, z0 = centre
    k = size
    c.add(EL(P(x0, y0, z0), P(0.27, 0.29, 0.31) * k, bone, "Horn", blend=0.06))
    c.add(EL(P(x0, y0 - 0.14 * k, z0 - 0.17 * k), P(0.22, 0.19, 0.18) * k, bone, "Horn", blend=0.06))
    c.add(EL(P(x0, y0 + 0.0, z0 - 0.28 * k), P(0.24, 0.06, 0.07) * k, bone, "Horn", blend=0.04))
    for side in (-1, 1):
        c.add(EL(P(x0 + side * 0.1 * k, y0 - 0.08 * k, z0 - 0.3 * k), P(0.078, 0.07, 0.04) * k, bone, "Dark", blend=0.01))
        c.solid(EL(P(x0 + side * 0.1 * k, y0 - 0.08 * k, z0 - 0.335 * k), P(0.045, 0.03, 0.02) * k, bone, "Glow"))
        # Cheekbones.
        c.add(EL(P(x0 + side * 0.17 * k, y0 - 0.17 * k, z0 - 0.2 * k), P(0.07, 0.05, 0.08) * k, bone, "Horn", blend=0.03))
    c.add(EL(P(x0, y0 - 0.19 * k, z0 - 0.34 * k), P(0.035, 0.05, 0.02) * k, bone, "Dark", blend=0.0))
    c.add(EL(P(x0, y0 - 0.3 * k, z0 - 0.28 * k), P(0.13, 0.035, 0.05) * k, bone, "Horn", blend=0.01))
    c.add(EL(P(x0, y0 - 0.39 * k, z0 - 0.2 * k), P(0.16, 0.06, 0.13) * k, jaw_bone, "Horn", blend=0.03))
    c.add(EL(P(x0, y0 - 0.34 * k, z0 - 0.3 * k), P(0.12, 0.03, 0.04) * k, jaw_bone, "Horn", blend=0.01))
    if helm:
        # A dented half-helm with a nose guard (Metal: rusty steel in the creature's tint).
        c.add(EL(P(x0, y0 + 0.1 * k, z0 + 0.01 * k), P(0.3, 0.2, 0.34) * k, bone, "Metal", blend=0.02))
        c.add(RC(P(x0, y0 + 0.12 * k, z0 - 0.33 * k), P(x0, y0 - 0.12 * k, z0 - 0.36 * k), 0.03 * k, 0.025 * k,
                 bone, "Metal", blend=0.0))
        c.add(EL(P(x0, y0 + 0.02 * k, z0 + 0.02 * k), P(0.32, 0.03, 0.35) * k, bone, "Dark", blend=0.0))


def skeleton():
    """A skeleton soldier: clean bones, a dented half-helm, round shield and notched sword."""
    sk = S.Skeleton()
    c = S.Creature("Skeleton", sk, step=0.04)
    body = sk.add("Body", None, P(0, 2.4, 0))
    head = sk.add("Head", body, P(0, 4.12, -0.02))
    jaw = sk.add("Jaw", head, P(0, 4.12, -0.2))
    arms = humanoid_arms(sk, body, (0.68, 3.95, 0.0), (0.82, 2.98, 0.05))
    # Pelvis and spine.
    c.add(EL(P(0, 2.45, 0.0), P(0.36, 0.17, 0.2), "Body", "Horn", blend=0.04))
    for side in (-1, 1):
        c.add(EL(P(side * 0.24, 2.58, 0.03), P(0.16, 0.17, 0.09), "Body", "Horn", blend=0.03,
                 rot=S.rot_z(side * math.radians(25))))
    c.add(RC(P(0, 2.55, 0.12), P(0, 3.98, 0.08), 0.045, 0.045, "Body", "Horn", blend=0.02))
    for i in range(10):
        y = 2.62 + i * 0.145
        c.add(EL(P(0, y, 0.13), P(0.075, 0.05, 0.07), "Body", "Horn", blend=0.02))
    # Ribcage: five ribs curving from the spine to the breastbone.
    for i, (y, rx) in enumerate(((3.72, 0.36), (3.58, 0.42), (3.44, 0.45), (3.3, 0.43), (3.16, 0.38))):
        for side in (-1, 1):
            pts = []
            for j in range(8):
                t = (j / 7) * math.pi * 0.86
                pts.append(P(side * rx * math.sin(t), y - 0.1 * math.sin(t / 2), -0.05 + 0.22 * math.cos(t)))
            for a, b in zip(pts, pts[1:]):
                c.add(RC(a, b, 0.038, 0.036, "Body", "Horn", blend=0.015))
    c.add(RC(P(0, 3.8, -0.27), P(0, 3.1, -0.24), 0.05, 0.035, "Body", "Horn", blend=0.02))
    # Collarbones, shoulder blades, neck.
    for side in (-1, 1):
        c.add(RC(P(0, 3.95, -0.16), P(side * 0.64, 4.0, -0.02), 0.045, 0.04, "Body", "Horn", blend=0.02))
        c.add(EL(P(side * 0.33, 3.72, 0.2), P(0.19, 0.24, 0.04), "Body", "Horn", blend=0.02))
    c.add(RC(P(0, 3.95, 0.05), P(0, 4.15, -0.01), 0.06, 0.055, "Body", "Horn", blend=0.03))
    skull(c, head.name, jaw.name, (0, 4.42, -0.02), helm=True)
    # A leather belt and a ragged loincloth; a pauldron on the shield shoulder.
    c.add(EL(P(0, 2.62, 0.0), P(0.39, 0.05, 0.25), "Body", "Dark", blend=0.0))
    c.add(EL(P(0, 2.25, -0.2), P(0.2, 0.32, 0.03), "Body", "Cloth", blend=0.0))
    c.add(EL(P(0, 2.25, 0.22), P(0.22, 0.34, 0.03), "Body", "Cloth", blend=0.0))
    left, right = arms[-1], arms[1]
    c.add(EL(P(-0.72, 4.03, 0), P(0.26, 0.13, 0.26), left[0].name, "Metal", blend=0.02, rot=S.rot_z(math.radians(22))))
    for side, (arm, fore) in arms.items():
        x = side
        c.add(EL(P(x * 0.68, 3.95, 0), P(0.09, 0.09, 0.09), arm.name, "Horn", blend=0.03))
        c.add(RC(P(x * 0.68, 3.92, 0), P(x * 0.82, 3.0, 0.05), 0.065, 0.055, arm.name, "Horn", blend=0.02))
        c.add(EL(P(x * 0.82, 2.98, 0.05), P(0.075, 0.075, 0.075), fore.name, "Horn", blend=0.03))
        for dx in (-0.035, 0.035):
            c.add(RC(P(x * 0.82 + dx, 2.95, 0.05), P(x * 0.86 + dx, 2.2, -0.1), 0.04, 0.035, fore.name, "Horn", blend=0.015))
        c.add(EL(P(x * 0.87, 2.08, -0.14), P(0.075, 0.1, 0.075), fore.name, "Horn", blend=0.03))
    # Round shield on the left forearm; a notched sword in the right hand.
    c.add(EL(P(-1.06, 2.6, -0.1), P(0.06, 0.5, 0.5), left[1].name, "Metal", blend=0.0))
    c.add(EL(P(-1.1, 2.6, -0.1), P(0.05, 0.42, 0.42), left[1].name, "Dark", blend=0.0))
    c.add(EL(P(-1.14, 2.6, -0.1), P(0.06, 0.12, 0.12), left[1].name, "Glow", blend=0.0))
    sword(c, right[1].name, P(0.87, 2.05, -0.2), P(0.9, 0.85, -1.2), width=0.13)

    def foot(side, px, pts, names, thick):
        a, b, f = names
        c.add(EL(pts[0] + P(0, 0.02, 0), P(0.08, 0.08, 0.08), a, "Horn", blend=0.03))
        c.add(RC(pts[0], pts[1], 0.075, 0.06, a, "Horn", blend=0.02))
        c.add(EL(pts[1] + P(0, 0.0, -0.07), P(0.085, 0.085, 0.07), b, "Horn", blend=0.03))
        c.add(RC(pts[1], pts[2], 0.055, 0.045, b, "Horn", blend=0.02))
        c.add(RC(pts[1] + P(side * 0.05, 0, 0.03), pts[2] + P(side * 0.05, 0, 0.0), 0.035, 0.03, b, "Horn", blend=0.015))
        c.add(RC(pts[2], P(px, 0.14, -0.06), 0.05, 0.06, f, "Horn", blend=0.03))
        c.add(EL(P(px, 0.12, -0.12), P(0.1, 0.07, 0.22), f, "Horn", blend=0.03))
        for dx in (-0.06, 0.0, 0.06):
            c.add(RC(P(px + dx, 0.08, -0.28), P(px + dx, 0.05, -0.4), 0.035, 0.03, f, "Horn", blend=0.01))

    legs = biped_legs(c, sk, body, 0.24, 2.35, 1.3, 0.42, 1.0, foot)
    return c, {"plan": "Biped", "legs": legs, "heads": [""]}


def zombie():
    """A shambling ghoul: hunched, arms reaching, ragged shirt and trousers, sunken glowing eyes."""
    sk = S.Skeleton()
    c = S.Creature("Zombie", sk, step=0.055)
    body = sk.add("Body", None, P(0, 2.3, 0))
    head = sk.add("Head", body, P(0, 3.78, -0.42))
    jaw = sk.add("Jaw", head, P(0, 3.72, -0.6))
    arms = {}
    reach = {-1: (P(-0.62, 3.55, -0.18), P(-0.68, 3.32, -0.92), P(-0.64, 3.18, -1.62)),
             1: (P(0.62, 3.5, -0.15), P(0.74, 3.0, -0.62), P(0.74, 2.62, -1.25))}
    for side, tag in mirror(None):
        s, e, h = reach[side]
        arm = sk.add(f"Arm{tag}", body, s)
        arms[side] = (arm, sk.add(f"Arm{tag}2", arm, e), s, e, h)
    # Torso leaning forward: belly, chest and a hunched back under a torn shirt.
    c.add(EL(P(0, 2.55, 0.02), P(0.46, 0.36, 0.34), "Body", "Hide", blend=0.12))
    c.add(EL(P(0, 3.15, -0.12), P(0.58, 0.46, 0.4), "Body", "Cloth", blend=0.1, rot=S.rot_x(math.radians(-18))))
    c.add(EL(P(0, 3.5, 0.06), P(0.52, 0.26, 0.36), "Body", "Cloth", blend=0.08))
    # Tears in the shirt showing grey skin; stitched patches.
    for at, r in ((P(0.26, 3.02, -0.5), P(0.15, 0.12, 0.05)), (P(-0.3, 3.34, -0.44), P(0.11, 0.1, 0.05)),
                  (P(0.12, 3.42, 0.38), P(0.14, 0.1, 0.05))):
        c.add(EL(at, r, "Body", "Hide", blend=0.01))
    c.add(EL(P(-0.2, 2.86, -0.5), P(0.13, 0.12, 0.05), "Body", "Under", blend=0.01))
    for k in range(3):
        c.add(RC(P(-0.3 + k * 0.1, 2.95, -0.55), P(-0.28 + k * 0.1, 2.78, -0.55), 0.016, 0.016, "Body", "Horn", blend=0.0))
    # A ragged hem round the waist.
    for k in range(10):
        a = k / 10 * math.pi * 2
        x, z = math.sin(a) * 0.48, math.cos(a) * 0.36 - 0.02
        length = 0.22 + 0.12 * ((k * 7) % 3) / 2
        c.add(RC(P(x, 2.72, z), P(x * 1.05, 2.72 - length, z * 1.05), 0.09, 0.03, "Body", "Cloth", blend=0.02))
    c.add(EL(P(0, 2.4, 0.0), P(0.47, 0.18, 0.34), "Body", "Dark", blend=0.03))
    # Neck and a lolling head: slack jaw, sunken eyes, a few clumps of hair, a stitched brow.
    c.add(RC(P(0, 3.5, -0.18), P(0, 3.78, -0.42), 0.15, 0.13, "Body", "Hide", blend=0.08))
    c.add(EL(P(0, 3.92, -0.5), P(0.26, 0.3, 0.27), head.name, "Hide", blend=0.08))
    c.add(EL(P(0, 3.8, -0.66), P(0.2, 0.15, 0.16), head.name, "Hide", blend=0.06))
    for side in (-1, 1):
        c.add(EL(P(side * 0.1, 3.96, -0.74), P(0.075, 0.06, 0.04), head.name, "Dark", blend=0.01))
        c.solid(EL(P(side * 0.1, 3.96, -0.775), P(0.04, 0.028, 0.02), head.name, "Glow"))
        c.add(EL(P(side * 0.26, 3.9, -0.5), P(0.04, 0.08, 0.06), head.name, "Hide", blend=0.03))
    c.add(EL(P(0, 4.06, -0.74), P(0.2, 0.045, 0.05), head.name, "Dark", blend=0.02))
    c.add(EL(P(0, 3.66, -0.68), P(0.17, 0.08, 0.15), jaw.name, "Hide", blend=0.04))
    c.add(EL(P(0, 3.74, -0.8), P(0.11, 0.035, 0.03), head.name, "Dark", blend=0.0))
    for at in (P(-0.12, 4.2, -0.42), P(0.08, 4.22, -0.36), P(0.18, 4.12, -0.3), P(-0.02, 4.18, -0.24)):
        c.add(EL(at, P(0.11, 0.07, 0.11), head.name, "Dark", blend=0.03))
    c.add(RC(P(-0.14, 4.12, -0.7), P(0.1, 4.16, -0.71), 0.014, 0.014, head.name, "Horn", blend=0.0))
    for k in range(4):
        x = -0.1 + k * 0.065
        c.add(RC(P(x, 4.09, -0.73), P(x, 4.19, -0.69), 0.012, 0.012, head.name, "Horn", blend=0.0))
    # Reaching arms: torn sleeves, grey forearms, a bandaged wrist, bony fingers.
    for side, (arm, fore, s, e, h) in arms.items():
        c.add(EL(s, P(0.2, 0.18, 0.2), arm.name, "Cloth", blend=0.05))
        c.add(RC(s, s + (e - s) * 0.55, 0.15, 0.13, arm.name, "Cloth", blend=0.04))
        c.add(RC(s + (e - s) * 0.5, e, 0.12, 0.11, arm.name, "Hide", blend=0.04))
        c.add(RC(e, h, 0.11, 0.09, fore.name, "Hide", blend=0.04))
        if side < 0:
            for t in (0.55, 0.68, 0.81):
                q = e + (h - e) * t
                c.add(EL(q, P(0.125, 0.125, 0.06), fore.name, "Under", blend=0.01, rot=along(e, h, up=(0.0, 1.0, 0.0))))
        d = (h - e) / float(np.linalg.norm(h - e))
        c.add(EL(h + d * 0.08, P(0.1, 0.07, 0.12), fore.name, "Hide", blend=0.04, rot=along(e, h, up=(0.0, 1.0, 0.0))))
        for k in (-1, 0, 1):
            tip = h + d * 0.36 + P(k * 0.07, -0.08, 0)
            c.add(RC(h + d * 0.14 + P(k * 0.06, 0, 0), tip, 0.035, 0.025, fore.name, "Hide", blend=0.01))
            c.add(EL(tip + d * 0.02, P(0.025, 0.02, 0.03), fore.name, "Dark", blend=0.0))

    def foot(side, px, pts, names, thick):
        a, b, f = names
        c.add(RC(pts[0], pts[1], 0.24, 0.19, a, "Cloth", blend=0.08))
        c.add(RC(pts[1], pts[2] + P(0, 0.25, 0), 0.19, 0.17, b, "Cloth", blend=0.05))
        for k in range(5):
            a2 = k / 5 * math.pi * 2
            q = pts[2] + P(math.sin(a2) * 0.17, 0.3, math.cos(a2) * 0.17)
            c.add(RC(q, q + P(0, -0.14 - 0.05 * (k % 2), 0), 0.06, 0.02, b, "Cloth", blend=0.01))
        c.add(RC(pts[2] + P(0, 0.2, 0), pts[2], 0.1, 0.09, b, "Hide", blend=0.04))
        c.add(RC(pts[2], P(px, 0.2, -0.06), 0.09, 0.12, f, "Hide", blend=0.04))
        c.add(EL(P(px, 0.16, -0.12), P(0.15, 0.12, 0.28), f, "Dark", blend=0.04))

    legs = biped_legs(c, sk, body, 0.3, 2.25, 1.25, 0.42, 1.0, foot)
    return c, {"plan": "Biped", "legs": legs, "heads": [""]}


def dark_plate(c, arms, spikes=True, cape=True):
    """Shared heavy plate for the death knight and the dullahan."""
    c.add(EL(P(0, 2.55, 0), P(0.62, 0.38, 0.44), "Body", "Dark", blend=0.15))
    c.add(EL(P(0, 3.0, 0), P(0.64, 0.46, 0.44), "Body", "Dark", blend=0.15))
    c.add(EL(P(0, 3.58, -0.05), P(0.88, 0.64, 0.57), "Body", "Metal", blend=0.12))
    c.add(EL(P(0, 3.15, -0.13), P(0.68, 0.32, 0.47), "Body", "Metal", blend=0.06))
    # A skull emblem on the breastplate over a glowing core.
    c.add(EL(P(0, 3.62, -0.6), P(0.2, 0.22, 0.06), "Body", "Glow", blend=0.0))
    c.add(EL(P(0, 3.68, -0.63), P(0.13, 0.13, 0.05), "Body", "Horn", blend=0.01))
    for side in (-1, 1):
        c.add(EL(P(side * 0.05, 3.69, -0.675), P(0.035, 0.03, 0.02), "Body", "Dark", blend=0.0))
    c.add(EL(P(0, 2.5, -0.06), P(0.72, 0.3, 0.5), "Body", "Metal", blend=0.05))
    for side in (-1, 1):
        c.add(EL(P(side * 0.45, 2.2, -0.18), P(0.27, 0.34, 0.12), "Body", "Metal", blend=0.03))
    c.add(EL(P(0, 2.74, 0), P(0.68, 0.07, 0.47), "Body", "Horn", blend=0.02))
    # A ragged tabard down the front.
    c.add(EL(P(0, 2.05, -0.5), P(0.26, 0.5, 0.04), "Body", "Cloth", blend=0.0))
    for k in (-1, 0, 1):
        c.add(RC(P(k * 0.15, 1.65, -0.5), P(k * 0.16, 1.42 - 0.08 * abs(k), -0.5), 0.07, 0.02, "Body", "Cloth", blend=0.0))
    if cape:
        # A long tattered cape from the shoulders, its hem in tongues.
        c.add(EL(P(0, 2.7, 0.62), P(0.9, 1.45, 0.08), "Body", "Cloth", blend=0.05, rot=S.rot_x(math.radians(-6))))
        for k in range(7):
            x = -0.72 + k * 0.24
            c.add(RC(P(x, 1.45, 0.75), P(x * 1.05, 0.95 - 0.12 * (k % 3), 0.82), 0.12, 0.03, "Body", "Cloth", blend=0.02))
    for side, (arm, fore) in arms.items():
        x = side
        c.add(EL(P(x * 1.02, 4.08, 0), P(0.5, 0.28, 0.5), arm.name, "Metal", blend=0.05,
                 rot=S.rot_z(x * math.radians(-22))))
        c.add(EL(P(x * 1.15, 3.86, 0), P(0.42, 0.21, 0.46), arm.name, "Metal", blend=0.03,
                 rot=S.rot_z(x * math.radians(-32))))
        if spikes:
            for dz, h in ((-0.22, 0.5), (0.0, 0.62), (0.22, 0.5)):
                c.add(RC(P(x * 1.05, 4.3, dz), P(x * 1.22, 4.3 + h, dz * 1.2), 0.085, 0.01, arm.name, "Dark", blend=0.02))
        c.add(RC(P(x * 0.98, 3.95, 0), P(x * 1.05, 2.98, 0.05), 0.23, 0.2, arm.name, "Dark", blend=0.08))
        c.add(EL(P(x * 1.05, 2.98, 0.05), P(0.21, 0.21, 0.21), fore.name, "Metal", blend=0.03))
        c.add(RC(P(x * 1.05, 2.98, 0.05), P(x * 1.08, 2.2, -0.08), 0.22, 0.19, fore.name, "Metal", blend=0.05))
        c.add(RC(P(x * 1.1, 2.75, 0.2), P(x * 1.12, 2.55, 0.42), 0.06, 0.01, fore.name, "Dark", blend=0.01))
        c.add(EL(P(x * 1.08, 2.04, -0.12), P(0.21, 0.23, 0.23), fore.name, "Metal", blend=0.05))


def plate_legs(c):
    def foot(side, px, pts, names, thick):
        a, b, f = names
        c.add(RC(pts[0], pts[1], 0.31, 0.25, a, "Dark", blend=0.1))
        c.add(EL(P(px, 1.88, -0.12), P(0.29, 0.43, 0.25), a, "Metal", blend=0.03))
        c.add(EL(pts[1] + P(0, 0, -0.1), P(0.23, 0.21, 0.19), b, "Metal", blend=0.03))
        c.add(RC(pts[1] + P(0, 0, -0.22), pts[1] + P(0, 0.08, -0.48), 0.07, 0.01, b, "Dark", blend=0.0))
        c.add(RC(pts[1], pts[2], 0.26, 0.21, b, "Metal", blend=0.05))
        c.add(EL(P(px, 0.24, -0.18), P(0.25, 0.17, 0.5), f, "Metal", blend=0.04))
        c.add(RC(P(px, 0.24, -0.6), P(px, 0.2, -0.78), 0.08, 0.02, f, "Dark", blend=0.01))
    return foot


def death_knight():
    """A death knight: spiked dark plate, a skull-faced horned helm, a tattered cape and a runed greatsword."""
    sk = S.Skeleton()
    c = S.Creature("DeathKnight", sk, step=0.06)
    body = sk.add("Body", None, P(0, 2.45, 0))
    head = sk.add("Head", body, P(0, 4.2, -0.05))
    arms = humanoid_arms(sk, body, (0.95, 3.95, 0.0), (1.05, 2.98, 0.05))
    dark_plate(c, arms)
    c.add(EL(P(0, 4.04, 0), P(0.48, 0.24, 0.42), "Body", "Metal", blend=0.08))
    # Helm: a dome shaped like a skull, brow ridge, glowing eye slits, cheek
    # guards, a toothed face plate and swept horns (always worn: not the
    # optional Horns region).
    c.add(EL(P(0, 4.4, -0.06), P(0.37, 0.43, 0.41), head.name, "Metal", blend=0.08))
    c.add(EL(P(0, 4.3, -0.32), P(0.3, 0.32, 0.2), head.name, "Metal", blend=0.05))
    c.add(EL(P(0, 4.46, -0.47), P(0.3, 0.06, 0.08), head.name, "Dark", blend=0.02))
    for side in (-1, 1):
        c.solid(EL(P(side * 0.12, 4.38, -0.53), P(0.08, 0.03, 0.04), head.name, "Eye"))
        c.add(EL(P(side * 0.22, 4.16, -0.4), P(0.1, 0.18, 0.12), head.name, "Metal", blend=0.03))
        c.add(RC(P(side * 0.3, 4.6, -0.1), P(side * 0.62, 4.95, 0.1), 0.1, 0.06, head.name, "Dark", blend=0.03))
        c.add(RC(P(side * 0.62, 4.95, 0.1), P(side * 0.7, 5.4, 0.35), 0.06, 0.012, head.name, "Dark", blend=0.02))
    for k in range(5):
        x = -0.12 + k * 0.06
        c.add(RC(P(x, 4.16, -0.5), P(x, 4.04, -0.49), 0.022, 0.016, head.name, "Horn", blend=0.0))
    c.add(RC(P(0, 4.85, -0.3), P(0, 4.9, 0.3), 0.06, 0.05, head.name, "Dark", blend=0.04))
    # A two-handed runeblade, held low and forward in the right hand.
    right = arms[1][1].name
    sword(c, right, P(1.08, 2.05, -0.2), P(1.14, 0.3, -1.7), width=0.2)
    # The left gauntlet cradles cold flame.
    c.add(EL(P(-1.12, 1.82, -0.3), P(0.13, 0.13, 0.13), arms[-1][1].name, "Glow", blend=0.0))
    legs = biped_legs(c, sk, body, 0.42, 2.35, 1.3, 0.42, 1.0, plate_legs(c))
    return c, {"plan": "Biped", "legs": legs, "heads": [""]}


def dullahan():
    """The headless knight: plate and a high collar round a flame where its head should be; it carries its helmed head and a scythe."""
    sk = S.Skeleton()
    c = S.Creature("Dullahan", sk, step=0.06)
    body = sk.add("Body", None, P(0, 2.45, 0))
    head = sk.add("Head", body, P(0, 4.1, -0.05))
    arms = humanoid_arms(sk, body, (0.95, 3.95, 0.0), (1.05, 2.98, 0.05))
    dark_plate(c, arms, spikes=False)
    # A high flared collar round an empty neck; soul flame rising from it
    # (on the Head bone, so it sways as the animator turns the "head").
    for k in range(9):
        a = (k / 8 - 0.5) * math.pi * 1.5 + math.pi
        d = P(math.sin(a), 0, math.cos(a))
        c.add(EL(P(0, 4.15, -0.02) + d * 0.36, P(0.13, 0.26, 0.05), "Body", "Metal", blend=0.03,
                 rot=along(P(0, 0, 0), d, up=(0.0, 1.0, 0.0))))
    c.add(EL(P(0, 4.0, -0.02), P(0.36, 0.08, 0.33), "Body", "Dark", blend=0.02))
    c.add(EL(P(0, 4.08, -0.02), P(0.24, 0.07, 0.22), "Body", "Glow", blend=0.0))
    for k, (dx, dz, h) in enumerate(((0, 0, 0.75), (-0.12, -0.06, 0.5), (0.13, -0.05, 0.55), (0.02, 0.12, 0.45),
                                     (-0.08, 0.1, 0.38), (0.1, 0.08, 0.36))):
        base = P(dx, 4.08, -0.02 + dz)
        c.add(RC(base, base + P(dx * 0.6, h, dz * 0.4 + 0.08), 0.1 - 0.008 * k, 0.012, head.name, "Glow", blend=0.03))
    # The helmed head, held at the left hip: closed visor, glowing slit, a crest.
    left = arms[-1][1].name
    hc = P(-1.12, 1.92, -0.48)
    c.add(EL(hc, P(0.3, 0.33, 0.31), left, "Metal", blend=0.05))
    c.add(EL(hc + P(0, -0.06, -0.2), P(0.24, 0.24, 0.16), left, "Metal", blend=0.04))
    c.solid(EL(hc + P(0, 0.03, -0.33), P(0.18, 0.03, 0.05), left, "Eye"))
    c.add(RC(hc + P(0, 0.3, -0.2), hc + P(0, 0.34, 0.28), 0.05, 0.04, left, "Dark", blend=0.03))
    c.add(EL(hc + P(0, -0.32, 0.0), P(0.2, 0.06, 0.2), left, "Glow", blend=0.0))
    # A long scythe in the right hand.
    right = arms[1][1].name
    top, bottom = P(1.1, 4.7, -0.35), P(1.06, 0.35, -0.12)
    c.add(RC(bottom, top, 0.05, 0.05, right, "Dark", blend=0.0))
    for y in (2.4, 1.7):
        c.add(EL(P(1.08, y, -0.22), P(0.07, 0.07, 0.07), right, "Horn", blend=0.0))
    c.add(EL(top + P(0, 0.05, 0), P(0.09, 0.12, 0.09), right, "Metal", blend=0.0))
    prev = top
    for k in range(1, 9):
        t = k / 8
        q = top + P(-0.08 * t, -0.15 * math.sin(t * math.pi) * 0.8 - 0.35 * t * t, -1.45 * t)
        width = 0.2 * (1 - t) + 0.03
        c.add(EL((prev + q) / 2, P(0.035, width, float(np.linalg.norm(q - prev)) / 2 + 0.03), right, "Blade", blend=0.0,
                 rot=along(prev, q, up=(0.0, 1.0, 0.0))))
        prev = q
    c.add(RC(top + P(0, -0.08, -0.1), top + P(-0.06, -0.3, -1.0), 0.025, 0.012, right, "Glow", blend=0.0))
    legs = biped_legs(c, sk, body, 0.42, 2.35, 1.3, 0.42, 1.0, plate_legs(c))
    return c, {"plan": "Biped", "legs": legs, "heads": [""]}


def death_lord():
    """The Death Lord: a towering crowned lich in robes and ornate plate, a skull staff in one hand and soul flame in the other."""
    sk = S.Skeleton()
    c = S.Creature("DeathLord", sk, step=0.06)
    body = sk.add("Body", None, P(0, 2.6, 0))
    head = sk.add("Head", body, P(0, 4.5, -0.05))
    jaw = sk.add("Jaw", head, P(0, 4.5, -0.25))
    arms = {}
    spec = {-1: (P(-1.0, 4.25, 0.0), P(-1.22, 3.25, -0.12), P(-1.3, 2.45, -0.45)),
            1: (P(1.0, 4.25, 0.0), P(1.26, 3.3, -0.25), P(1.3, 2.55, -0.62))}
    for side, tag in mirror(None):
        s, e, h = spec[side]
        arm = sk.add(f"Arm{tag}", body, s)
        arms[side] = (arm, sk.add(f"Arm{tag}2", arm, e), s, e, h)
    # Robed body under ornate plate.
    c.add(EL(P(0, 2.75, 0), P(0.62, 0.42, 0.46), "Body", "Cloth", blend=0.15))
    c.add(EL(P(0, 3.25, 0), P(0.66, 0.5, 0.46), "Body", "Cloth", blend=0.15))
    c.add(EL(P(0, 3.85, -0.04), P(0.9, 0.62, 0.58), "Body", "Metal", blend=0.12))
    c.add(EL(P(0, 3.45, -0.14), P(0.66, 0.36, 0.48), "Body", "Metal", blend=0.06))
    c.add(EL(P(0, 3.85, -0.62), P(0.17, 0.2, 0.06), "Body", "Glow", blend=0.0))
    for side in (-1, 1):
        c.add(RC(P(side * 0.12, 3.85, -0.62), P(side * 0.55, 3.4, -0.5), 0.04, 0.025, "Body", "Horn", blend=0.0))
        c.add(RC(P(side * 0.12, 3.85, -0.62), P(side * 0.6, 4.15, -0.48), 0.04, 0.025, "Body", "Horn", blend=0.0))
    c.add(EL(P(0, 2.82, 0), P(0.66, 0.08, 0.48), "Body", "Horn", blend=0.02))
    # Robe panels front and back (gaps at the sides for the stride), hems in tongues.
    for z, w in ((-0.42, 0.42), (0.4, 0.5)):
        c.add(EL(P(0, 1.85, z), P(w, 0.95, 0.05), "Body", "Cloth", blend=0.02))
        for k in range(5):
            x = -w * 0.8 + k * w * 0.4
            c.add(RC(P(x, 1.05, z), P(x * 1.05, 0.72 - 0.08 * (k % 2), z * 1.08), 0.09, 0.025, "Body", "Cloth", blend=0.01))
        c.add(EL(P(0, 2.6, z), P(w * 1.02, 0.07, 0.06), "Body", "Glow", blend=0.0))
    # A great cape to the ground.
    c.add(EL(P(0, 2.55, 0.66), P(1.05, 2.0, 0.08), "Body", "Cloth", blend=0.05, rot=S.rot_x(math.radians(-5))))
    for k in range(8):
        x = -0.84 + k * 0.24
        c.add(RC(P(x, 0.75, 0.8), P(x * 1.05, 0.25 - 0.08 * (k % 3), 0.86), 0.12, 0.03, "Body", "Cloth", blend=0.02))
    # A high collar fanning behind the head.
    for k in range(7):
        a = (k / 6 - 0.5) * math.pi * 1.1 + math.pi
        d = P(math.sin(a), 0, math.cos(a))
        c.add(EL(P(0, 4.55, 0.02) + d * 0.48 + P(0, 0.15, 0), P(0.16, 0.45, 0.04), "Body", "Metal", blend=0.02,
                 rot=along(P(0, 0, 0), d, up=(0.0, 1.0, 0.0)) @ S.rot_x(math.radians(-12))))
    # Hood, skull face, crown of spikes and gems.
    c.add(EL(P(0, 4.82, 0.08), P(0.44, 0.46, 0.44), head.name, "Cloth", blend=0.06))
    c.add(EL(P(0, 4.6, -0.12), P(0.36, 0.3, 0.3), head.name, "Dark", blend=0.04))
    skull(c, head.name, jaw.name, (0, 4.78, -0.12), size=1.05)
    c.add(EL(P(0, 5.1, -0.02), P(0.42, 0.08, 0.42), head.name, "Metal", blend=0.01))
    for k in range(7):
        a = (k / 7) * math.pi * 2
        d = P(math.sin(a), 0, -math.cos(a))
        base = P(0, 5.12, -0.02) + d * 0.38
        height = 0.55 if k == 0 else (0.38 if k in (1, 6) else 0.28)
        c.add(RC(base, base + P(0, height, 0) + d * 0.08, 0.08, 0.01, head.name, "Metal", blend=0.01))
        if k % 2 == 0:
            c.add(EL(base + d * 0.04 + P(0, 0.02, 0), P(0.05, 0.05, 0.03), head.name, "Glow", blend=0.0))
    # Arms: huge skull-studded pauldrons, sleeves, clawed gauntlets.
    for side, (arm, fore, s, e, h) in arms.items():
        x = side
        c.add(EL(s + P(x * 0.08, 0.12, 0), P(0.56, 0.32, 0.56), arm.name, "Metal", blend=0.05,
                 rot=S.rot_z(x * math.radians(-20))))
        c.add(EL(s + P(x * 0.22, -0.12, 0), P(0.46, 0.22, 0.5), arm.name, "Metal", blend=0.03,
                 rot=S.rot_z(x * math.radians(-30))))
        c.add(EL(s + P(x * 0.18, 0.18, -0.4), P(0.15, 0.15, 0.13), arm.name, "Horn", blend=0.01))
        for dz in (-0.05, 0.05):
            c.add(EL(s + P(x * 0.18 + dz, 0.2, -0.52), P(0.035, 0.035, 0.02), arm.name, "Dark", blend=0.0))
        for dz, hh in ((-0.25, 0.55), (0.05, 0.7), (0.3, 0.5)):
            c.add(RC(s + P(x * 0.12, 0.35, dz), s + P(x * 0.32, 0.35 + hh, dz * 1.2), 0.09, 0.012, arm.name, "Dark", blend=0.02))
        c.add(RC(s, e, 0.24, 0.22, arm.name, "Cloth", blend=0.08))
        c.add(RC(e, h, 0.22, 0.17, fore.name, "Metal", blend=0.05))
        c.add(EL(e + (h - e) * 0.15, P(0.3, 0.12, 0.3), fore.name, "Cloth", blend=0.03))
        c.add(EL(h + P(0, -0.08, -0.04), P(0.17, 0.19, 0.19), fore.name, "Metal", blend=0.04))
        for k in (-1, 0, 1):
            c.add(RC(h + P(k * 0.07, -0.2, -0.1), h + P(k * 0.08, -0.38, -0.2), 0.04, 0.01, fore.name, "Dark", blend=0.01))
    # Soul flame in the left hand; the skull staff in the right.
    lh = arms[-1][4]
    c.add(EL(lh + P(0, -0.12, -0.25), P(0.2, 0.2, 0.2), arms[-1][1].name, "Glow", blend=0.0))
    right = arms[1][1].name
    rh = arms[1][4]
    bottom, top = P(rh[0] + 0.02, 0.2, rh[2] - 0.12), P(rh[0] - 0.02, 5.5, rh[2] + 0.05)
    c.add(RC(bottom, top, 0.06, 0.07, right, "Dark", blend=0.0))
    for y in (1.2, 3.6, 4.6):
        c.add(EL(P(rh[0], y, rh[2] - 0.05), P(0.09, 0.07, 0.09), right, "Metal", blend=0.0))
    head_top = top + P(0, 0.35, 0)
    c.add(EL(head_top, P(0.2, 0.22, 0.2), right, "Glow", blend=0.0))
    for k in range(4):
        a = k / 4 * math.pi * 2 + math.pi / 4
        d = P(math.sin(a), 0, math.cos(a))
        c.add(RC(top + d * 0.08, head_top + d * 0.24 + P(0, 0.25, 0), 0.05, 0.015, right, "Metal", blend=0.01))
    c.add(EL(top + P(0, -0.12, 0), P(0.14, 0.12, 0.14), right, "Horn", blend=0.01))

    def foot(side, px, pts, names, thick):
        a, b, f = names
        c.add(RC(pts[0], pts[1], 0.3, 0.24, a, "Dark", blend=0.1))
        c.add(EL(pts[1] + P(0, 0, -0.1), P(0.22, 0.2, 0.18), b, "Metal", blend=0.03))
        c.add(RC(pts[1], pts[2], 0.25, 0.2, b, "Metal", blend=0.05))
        c.add(EL(P(px, 0.24, -0.18), P(0.25, 0.17, 0.5), f, "Metal", blend=0.04))
        c.add(RC(P(px, 0.24, -0.6), P(px, 0.18, -0.8), 0.08, 0.015, f, "Dark", blend=0.01))

    legs = biped_legs(c, sk, body, 0.4, 2.5, 1.38, 0.45, 1.0, foot)
    return c, {"plan": "Biped", "legs": legs, "heads": [""]}



CREATURES_EXTRA = {
    "Serpent": serpent,
    "Hydra": hydra,
    "Beetle": beetle,
    "Spider": spider,
    "Golem": golem,
    "Knight": knight,
    "Lion": lion,
    "Chimera": chimera,
    "Dragon": dragon,
    "Griffin": griffin,
    "Steed": steed,
    "Bat": bat,
    "Harpy": harpy,
    "Gorgon": gorgon,
    "Sprite": sprite,
    "Skeleton": skeleton,
    "Zombie": zombie,
    "DeathKnight": death_knight,
    "Dullahan": dullahan,
    "DeathLord": death_lord,
}


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
