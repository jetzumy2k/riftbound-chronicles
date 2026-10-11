"""
Solves weapon-arm poses for AnimationClips and writes
src/shared/Definitions/AnimationArms.luau (authoring aid, not shipped).

Each target says where a hand should be and which way its weapon should
point at one key of one clip; the body (Root / Waist) is read from that key,
so arms stay correct when the body pose changes. Run from the repo root:

    lune run tools/anim/dump_clips > build/clips.json
    python tools/anim/generate_arms.py build/clips.json

Coordinates: character frame, faces -Z, +X right, +Y up, studs, origin at
the hips (shoulders ~y 1.2, head ~y 2.1, feet ~y -3).
"""
import json, math, sys, os
import numpy as np
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from render_clips import joint
from solve_arm import solve, arm_chain

GRIP = {"Warrior": -110, "Healer": -90, "Archer": -90, "Mage": -160}
OUT = "src/shared/Definitions/AnimationArms.luau"


def body_at(clips, clip, t):
    for key in clips[clip]["keys"]:
        if abs(key["t"] - t) < 1e-6:
            pose = key["pose"]
            return {k: pose[k] for k in ("Root", "Waist") if k in pose}
    raise KeyError(f"{clip} has no key at t={t}")


def frame(body):
    Rr, pr = joint(body, "Root")
    root = np.array([0, -0.2, 0]) + pr
    Rw = Rr @ joint(body, "Waist")[0]
    waist = root + Rr @ np.array([0, 0.2, 0])
    return Rw, waist


def shoulder(body, side):
    Rw, waist = frame(body)
    return waist + Rw @ np.array([1.0 if side == "Right" else -1.0, 1.2, 0])


def head(body):
    Rw, waist = frame(body)
    return waist + Rw @ np.array([0, 2.1, 0])


def V(*a):
    return np.array(a, float)


# (id, clip, t, side, job, hand(body) -> point, weapon direction or None, start guess)
TARGETS = []


def T(id, clip, t, side, job, hand, direction, start):
    TARGETS.append((id, clip, t, side, job, hand, direction, start))


def at(*a):
    return lambda body: V(*a)


# Warrior: sword, right hand.
T("Warrior.hold", "Warrior_Idle", 0, "Right", "Warrior", at(0.9, -0.1, -1.3), V(0.05, 0.65, -0.75), [22, 0, 12, 58, -12])
T("Warrior.a1.windup", "Warrior_Attack1", 0.13, "Right", "Warrior", at(1.6, 1.9, 0.6), V(-0.4, 0.2, 1), [70, -20, 72, 82, -40])
T("Warrior.a1.hit", "Warrior_Attack1", 0.21, "Right", "Warrior", at(0.3, 1.0, -2.2), V(-0.75, 0, -0.65), [88, 30, 14, 8, -55])
T("Warrior.a1.follow", "Warrior_Attack1", 0.3, "Right", "Warrior", at(-1.2, 0.9, -1.4), V(-0.95, -0.05, 0.3), [70, 55, -30, 26, -30])
T("Warrior.a2.windup", "Warrior_Attack2", 0.12, "Right", "Warrior", at(-0.9, -0.1, -0.9), V(-0.4, -0.45, 0.8), [40, 40, -42, 74, 10])
T("Warrior.a2.hit", "Warrior_Attack2", 0.2, "Right", "Warrior", at(0.5, 1.4, -2.1), V(0.6, 0.35, -0.7), [100, -20, 40, 10, -45])
T("Warrior.a2.follow", "Warrior_Attack2", 0.3, "Right", "Warrior", at(1.4, 2.8, -0.6), V(0.35, 0.6, 0.7), [140, -30, 70, 24, -30])
T("Warrior.a3.windup", "Warrior_Attack3", 0.24, "Right", "Warrior", at(0.6, 3.4, 0.3), V(0, -0.45, 0.9), [168, 0, 18, 46, -36])
T("Warrior.a3.hang", "Warrior_Attack3", 0.32, "Right", "Warrior", at(0.6, 3.5, 0.45), V(0, -0.6, 0.8), [176, 0, 18, 52, -40])
T("Warrior.a3.hit", "Warrior_Attack3", 0.4, "Right", "Warrior", at(0.4, 0.0, -2.6), V(0, -0.35, -0.94), [72, 0, 6, 2, -52])
T("Warrior.a3.settle", "Warrior_Attack3", 0.52, "Right", "Warrior", at(0.4, -0.2, -2.5), V(0, -0.45, -0.9), [64, 0, 6, 4, -46])

# Healer: staff, right hand (left hand joins for the slam).
T("Healer.hold", "Healer_Idle", 0, "Right", "Healer", at(1.35, -0.4, -0.7), V(0.05, 1, -0.08), [14, 0, 12, 76, 0])
T("Healer.a1.windup", "Healer_Attack1", 0.14, "Right", "Healer", at(1.5, 0.9, 0.3), V(0.1, 0.8, 0.5), [30, 0, 20, 108, 6])
T("Healer.a1.hit", "Healer_Attack1", 0.27, "Right", "Healer", at(0.6, 0.6, -2.2), V(0, 0.55, -0.85), [64, 0, 6, 6, -22])
T("Healer.a1.follow", "Healer_Attack1", 0.36, "Right", "Healer", at(0.5, 0.6, -2.3), V(0, 0.5, -0.87), [68, 0, 4, 4, -26])
T("Healer.a2.raise", "Healer_Attack2", 0.15, "Right", "Healer", at(1.2, 3.0, -0.6), V(0, 1, 0.05), [128, 0, 14, 26, -64])
T("Healer.a2.point", "Healer_Attack2", 0.28, "Right", "Healer", at(0.6, 1.0, -2.3), V(0, -0.2, -1), [84, 0, 6, 2, -60])
T("Healer.a2.follow", "Healer_Attack2", 0.38, "Right", "Healer", at(0.6, 0.9, -2.3), V(0, -0.25, -1), [80, 0, 6, 4, -56])
T("Healer.a3.lift", "Healer_Attack3", 0.26, "Right", "Healer", at(0.5, 3.4, -0.5), V(0, 1, 0), [132, 0, 4, 40, -82])
T("Healer.a3.liftL", "Healer_Attack3", 0.26, "Left", "Healer", at(0.4, 2.5, -0.5), None, [140, 0, 22, 44, 0])
T("Healer.a3.top", "Healer_Attack3", 0.42, "Right", "Healer", at(0.5, 3.6, -0.5), V(0, 1, 0), [136, 0, 4, 42, -84])
T("Healer.a3.topL", "Healer_Attack3", 0.42, "Left", "Healer", at(0.4, 2.7, -0.5), None, [144, 0, 22, 46, 0])
T("Healer.a3.slam", "Healer_Attack3", 0.5, "Right", "Healer", at(0.8, 0.2, -1.4), V(0, 1, 0), [44, 0, 14, 46, 0])
T("Healer.a3.settle", "Healer_Attack3", 0.66, "Right", "Healer", at(0.8, 0.1, -1.4), V(0, 1, 0), [42, 0, 14, 48, 0])

# Mage: wand, right hand.
T("Mage.hold", "Mage_Idle", 0, "Right", "Mage", at(1.2, -0.3, -1.2), V(0.1, -0.35, -0.93), [16, 0, 10, 38, 0])
T("Mage.a1.cock", "Mage_Attack1", 0.1, "Right", "Mage", at(1.4, 2.0, 0.1), V(0, 0.6, 0.8), [104, 0, 26, 112, -20])
T("Mage.a1.flick", "Mage_Attack1", 0.18, "Right", "Mage", at(0.8, 1.1, -2.3), V(-0.1, 0, -1), [86, 0, 2, 2, -12])
T("Mage.a1.follow", "Mage_Attack1", 0.25, "Right", "Mage", at(0.8, 0.9, -2.3), V(-0.1, -0.25, -0.97), [82, 0, 0, 4, 8])
T("Mage.a3.gather", "Mage_Attack3", 0.3, "Right", "Mage", at(0.3, 1.0, -1.3), V(0, 1, -0.1), [54, 0, -22, 104, -10])
T("Mage.a3.hold", "Mage_Attack3", 0.46, "Right", "Mage", at(0.3, 0.95, -1.3), V(0, 1, -0.1), [50, 0, -24, 104, -10])
T("Mage.a3.burst", "Mage_Attack3", 0.56, "Right", "Mage", at(1.0, 1.3, -2.4), V(0.1, 0.1, -1), [92, 0, 18, 4, -30])
T("Mage.a3.follow", "Mage_Attack3", 0.72, "Right", "Mage", at(1.1, 1.3, -2.35), V(0.15, 0.1, -1), [88, 0, 22, 8, -26])

# Archer: bow in the left hand aimed straight at the target (-Z); the string
# hand goes from the bow to the face, and past the ear on release.
T("Archer.hold", "Archer_Idle", 0, "Left", "Archer", at(-1.2, -0.3, -0.8), V(0, 0.85, -0.5), [18, 0, -10, 38, 0])


def bow_hand(body):
    aim = V(0, 0.04, -1)
    return shoulder(body, "Left") + 2.3 * aim / np.linalg.norm(aim)


def anchor(body):
    return head(body) + V(0.2, -0.45, 0.05)


ARCHER_KEYS = [
    ("a1.nock", "Archer_Attack1", 0.12, "nock"),
    ("a1.draw", "Archer_Attack1", 0.25, "draw"),
    ("a1.aim", "Archer_Attack1", 0.3, "draw"),
    ("a1.release", "Archer_Attack1", 0.36, "release"),
    ("a2.nock", "Archer_Attack2", 0, "nock"),
    ("a2.draw", "Archer_Attack2", 0.19, "draw"),
    ("a2.aim", "Archer_Attack2", 0.24, "draw"),
    ("a2.release", "Archer_Attack2", 0.3, "release"),
    ("a3.nock", "Archer_Attack3", 0.16, "nock"),
    ("a3.draw", "Archer_Attack3", 0.46, "draw"),
    ("a3.aim", "Archer_Attack3", 0.62, "draw"),
    ("a3.release", "Archer_Attack3", 0.7, "release"),
]
for key, clip, t, phase in ARCHER_KEYS:
    T(f"Archer.{key}.bow", clip, t, "Left", "Archer", bow_hand, V(0, 1, 0.05), [90, 0, -64, 4, 0])
    if phase == "nock":
        hand, start = (lambda body: bow_hand(body) + V(0.35, -0.05, 0.6)), [84, 0, -36, 46, 0]
    elif phase == "draw":
        hand, start = anchor, [6, -24, 88, 138, 0]
    else:
        hand, start = (lambda body: anchor(body) + V(0.45, 0.15, 0.9)), [4, -46, 96, 64, -20]
    T(f"Archer.{key}.string", clip, t, "Right", "Archer", hand, None, start)


def main():
    clips = json.load(open(sys.argv[1]))
    results = {}
    worst = 0
    for id, clip, t, side, job, hand, direction, start in TARGETS:
        body = body_at(clips, clip, t)
        target = hand(body)
        aim = direction if direction is not None else V(0, 1, 0)
        out = solve(side, GRIP[job], body, tuple(target), tuple(aim),
                    wdir=1.0 if direction is not None else 0.0, start=start, quiet=True)
        v = [out[f"{side}Shoulder"][a] for a in "xyz"] + [out[f"{side}Elbow"]["x"]] + [out[f"{side}Wrist"][a] for a in "xyz"]
        h, d = arm_chain(body, side, v[:3], v[3], v[4], GRIP[job], v[5], v[6])
        err = np.linalg.norm(h - target)
        derr = math.degrees(math.acos(max(-1, min(1, d @ (aim / np.linalg.norm(aim)))))) if direction is not None else 0
        worst = max(worst, err)
        print(f"{id:24s} hand {err:4.2f} studs  aim {derr:3.0f} deg   {v}")
        results.setdefault(id, {}).update(out)
    keymap = {}
    for id, clip, t, side, job, hand, direction, start in TARGETS:
        if not id.endswith(".hold"):
            ids = keymap.setdefault(clip, {}).setdefault(f"{t:.3f}", [])
            if id not in ids:
                ids.append(id)
    lines = [
        "--!strict",
        "-- GENERATED by tools/anim/generate_arms.py; do not edit by hand.",
        "-- Solved weapon-arm joint angles (degrees). `Poses` by id; `Keys` maps",
        "-- clip -> key time -> pose ids merged into that key by AnimationClips.",
        "return table.freeze({",
        "	Poses = {",
    ]
    for id in sorted(results):
        lines.append(f'		["{id}"] = {{')
        for jname in sorted(results[id]):
            vals = ", ".join(f"{a} = {b}" for a, b in results[id][jname].items() if b != 0)
            lines.append(f"			{jname} = {{ {vals} }},")
        lines.append("		},")
    lines.append("	},")
    lines.append("	Keys = {")
    for clip in sorted(keymap):
        lines.append(f"		{clip} = {{")
        for t in sorted(keymap[clip], key=float):
            ids = ", ".join(f'"{i}"' for i in keymap[clip][t])
            lines.append(f'			["{t}"] = {{ {ids} }},')
        lines.append("		},")
    lines.append("	},")
    lines.append("})")
    with open(OUT, "w", newline="\n") as f:
        f.write("\n".join(lines) + "\n")
    print(f"wrote {OUT} ({len(results)} poses, worst hand error {worst:.2f} studs)")


if __name__ == "__main__":
    main()
