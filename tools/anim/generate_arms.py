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

GRIP = {
    "Warrior": -110,
    "Healer": -90,
    "Archer": -90,
    "Mage": -160,
    # Weapon profiles (D-69): long swords / hammers / battle axes and daggers
    # in the forward grip, the staff straight across the fist, the crossbow
    # along the fingers (trigger hand).
    "TwoHand": -110,
    "Staff": -90,
    "Dagger": -110,
    "Crossbow": -160,
}
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


# --- Skill clips (Phase 5, D-45) -------------------------------------------
def rel(x, y, z):
    """A hand point in the upper-body frame (turns with Root / Waist)."""
    def f(body):
        Rw, waist = frame(body)
        return waist + Rw @ V(x, y, z)
    return f


def reldir(x, y, z):
    """A weapon direction in the upper-body frame."""
    def f(body):
        Rw, _ = frame(body)
        return Rw @ V(x, y, z)
    return f


# Warrior: spin, slam, brace, roar.
T("Warrior.spin.coil", "Warrior_SkillSpin", 0.12, "Right", "Warrior", rel(1.8, 0.4, 0.6), reldir(0.5, -0.2, 0.85), [30, -30, 70, 40, -20])
for i, t in enumerate((0.3, 0.45, 0.6)):
    T(f"Warrior.spin.{i}", "Warrior_SkillSpin", t, "Right", "Warrior", rel(2.6, 1.0, -0.4), reldir(1, 0.05, -0.25), [20, 0, 95, 8, -10])
T("Warrior.slam.crouch", "Warrior_SkillSlam", 0.16, "Right", "Warrior", rel(1.0, -0.6, 1.0), reldir(0, -0.3, 1), [-30, 0, 20, 30, 0])
T("Warrior.slam.air", "Warrior_SkillSlam", 0.36, "Right", "Warrior", rel(0.6, 3.4, 0.3), reldir(0, -0.45, 0.9), [168, 0, 18, 46, -36])
T("Warrior.slam.hit", "Warrior_SkillSlam", 0.5, "Right", "Warrior", at(0.4, -1.4, -2.5), V(0, -0.75, -0.66), [70, 0, 6, 4, -60])
T("Warrior.slam.settle", "Warrior_SkillSlam", 0.72, "Right", "Warrior", at(0.4, -1.3, -2.4), V(0, -0.75, -0.66), [66, 0, 6, 6, -56])
for i, t in enumerate((0.18, 0.3, 0.6)):
    T(f"Warrior.brace.{i}", "Warrior_SkillBrace", t, "Right", "Warrior", rel(0.5, 1.0, -1.3), reldir(-1, 0.2, -0.1), [70, 40, 30, 70, -20])
T("Warrior.roar.gather", "Warrior_SkillRoar", 0.16, "Right", "Warrior", rel(0.9, 0.8, -0.8), reldir(0, 1, 0.2), [40, 0, 10, 100, -20])
for i, t in enumerate((0.36, 0.62)):
    T(f"Warrior.roar.wide{i}", "Warrior_SkillRoar", t, "Right", "Warrior", rel(2.5, 2.0, -0.2), reldir(0.5, 0.85, -0.1), [30, 0, 110, 20, -30])

# Healer: raise, plant.
T("Healer.raise.low", "Healer_SkillRaise", 0.2, "Right", "Healer", rel(0.9, 0.9, -1.0), reldir(0, 1, 0.1), [60, 0, 10, 80, 0])
for i, t in enumerate((0.45, 0.68)):
    T(f"Healer.raise.top{i}", "Healer_SkillRaise", t, "Right", "Healer", rel(0.4, 3.3, -0.5), reldir(0, 1, 0), [150, 0, 8, 30, -80])
    T(f"Healer.raise.topL{i}", "Healer_SkillRaise", t, "Left", "Healer", rel(-0.3, 2.9, -0.5), None, [145, 0, -10, 36, 0])
T("Healer.plant.lift", "Healer_SkillPlant", 0.18, "Right", "Healer", at(1.2, 3.0, -0.6), V(0, 1, 0.05), [128, 0, 14, 26, -64])
for i, t in enumerate((0.4, 0.62)):
    T(f"Healer.plant.hit{i}", "Healer_SkillPlant", t, "Right", "Healer", at(0.8, 0.1, -1.5), V(0, 1, 0), [44, 0, 14, 46, 0])

# Archer: volley into the sky (bow aimed up and ahead).
SKY_AIM = V(0, 0.8, -0.6) / np.linalg.norm(V(0, 0.8, -0.6))


def sky_bow(body):
    return shoulder(body, "Left") + 2.3 * SKY_AIM


for key, t, phase in (("nock", 0.16, "nock"), ("draw", 0.42, "draw"), ("aim", 0.5, "draw"), ("release", 0.56, "release")):
    T(f"Archer.sky.{key}.bow", "Archer_SkillSky", t, "Left", "Archer", sky_bow, V(0, 0.6, 0.8), [140, 0, -50, 4, 0])
    if phase == "nock":
        hand, start = (lambda body: sky_bow(body) + V(0.35, -0.3, 0.4)), [110, 0, -30, 46, 0]
    elif phase == "draw":
        hand, start = anchor, [6, -24, 88, 138, 0]
    else:
        hand, start = (lambda body: anchor(body) + V(0.45, 0.15, 0.9)), [4, -46, 96, 64, -20]
    T(f"Archer.sky.{key}.string", "Archer_SkillSky", t, "Right", "Archer", hand, None, start)

# Mage: channel overhead, push.
for i, t in enumerate((0.26, 0.5)):
    T(f"Mage.channel.up{i}", "Mage_SkillChannel", t, "Right", "Mage", rel(0.5, 3.2, -0.6), reldir(0, 1, -0.1), [150, 0, 14, 30, 0])
for i, t in enumerate((0.62, 0.82)):
    T(f"Mage.channel.thrust{i}", "Mage_SkillChannel", t, "Right", "Mage", at(0.7, 1.4, -2.5), V(0.05, 0.2, -1), [100, 0, 10, 6, -20])
T("Mage.push.pull", "Mage_SkillPush", 0.16, "Right", "Mage", rel(0.6, 0.9, -0.6), reldir(0, 0.6, -0.8), [50, 0, 20, 110, -10])
for i, t in enumerate((0.34, 0.56)):
    T(f"Mage.push.hit{i}", "Mage_SkillPush", t, "Right", "Mage", at(0.6, 0.9, -2.5), V(0, 0.1, -1), [92, 0, 6, 6, -20])


# --- Weapon profiles (equipment overhaul, D-69) -----------------------------
# Hand targets in the upper-body frame (they turn with Root / Waist). Two-
# handed grips: the second hand is placed along the weapon from the first.


def unit(v):
    v = np.asarray(v, float)
    return v / np.linalg.norm(v)


def guess(side, hand):
    y = hand[1]
    if y > 2.0:
        g = [150, 0, 15, 40, -30]
    elif y > 0.6:
        g = [80, 0, 10, 45, -20]
    else:
        g = [35, 0, 10, 55, 0]
    if side == "Left":
        g = [g[0], g[1], -g[2], g[3], 0]
    return g


def grip2(prefix, name, clip, t, grip, hand, direction, offset, left_extra=(0, 0, 0)):
    """Right hand on the grip, left hand `offset` studs along the weapon."""
    T(f"{prefix}.{name}", clip, t, "Right", grip, rel(*hand), reldir(*direction), guess("Right", hand))

    # Resolved in main() from where the right hand and weapon actually ended
    # up, so the second hand closes on the weapon itself.
    approx = np.asarray(hand) + offset * unit(direction)
    T(f"{prefix}L.{name}", clip, t, "Left", grip, ("follow", f"{prefix}.{name}", offset, left_extra), None, guess("Left", approx))


def grip1(prefix, name, clip, t, grip, hand, direction):
    T(f"{prefix}.{name}", clip, t, "Right", grip, rel(*hand), reldir(*direction), guess("Right", hand))


# Two-handed: the left hand below the right, toward the pommel.
TH_KEYS = [
    ("hold", "TwoHand_Idle", 0, (0.35, 0.35, -1.15), (-0.2, 0.8, -0.55)),
    ("a1.windup", "TwoHand_Attack1", 0.18, (0.85, 2.2, 0.35), (-0.15, 0.35, 0.92)),
    ("a1.hit", "TwoHand_Attack1", 0.3, (-0.15, 0.5, -1.55), (-0.55, -0.4, -0.73)),
    ("a1.follow", "TwoHand_Attack1", 0.42, (-0.9, 0.3, -1.0), (-0.85, -0.35, 0.35)),
    ("a2.windup", "TwoHand_Attack2", 0.18, (1.2, 1.1, 0.1), (0.45, 0.15, 0.88)),
    ("a2.hit", "TwoHand_Attack2", 0.3, (0.0, 1.0, -1.55), (-0.95, 0.05, -0.3)),
    ("a2.follow", "TwoHand_Attack2", 0.44, (-1.1, 1.0, -0.7), (-0.55, 0.05, 0.83)),
    ("a3.raise", "TwoHand_Attack3", 0.26, (0.2, 2.4, 0.2), (0, 0.25, 0.97)),
    ("a3.hang", "TwoHand_Attack3", 0.36, (0.2, 2.5, 0.3), (0, 0.05, 1)),
    ("a3.hit", "TwoHand_Attack3", 0.46, (0.1, 0.3, -1.55), (0, -0.5, -0.87)),
    ("a3.settle", "TwoHand_Attack3", 0.6, (0.1, 0.25, -1.5), (0, -0.55, -0.83)),
]
for name, clip, t, hand, direction in TH_KEYS:
    grip2("TwoHand", name, clip, t, "TwoHand", hand, direction, -0.55)

# Staff: the left hand above the right, up the shaft.
STAFF_KEYS = [
    ("hold", "Staff_Idle", 0, (0.6, 0.55, -0.85), (-0.45, 0.85, -0.2)),
    ("a1.draw", "Staff_Attack1", 0.14, (0.75, 0.7, 0.1), (0, 0.08, -1)),
    ("a1.hit", "Staff_Attack1", 0.27, (0.3, 0.85, -0.95), (0, 0.08, -1)),
    ("a1.follow", "Staff_Attack1", 0.36, (0.3, 0.85, -0.95), (0, 0.08, -1)),
    ("a2.windup", "Staff_Attack2", 0.15, (0.8, 0.8, -0.2), (0.55, 0.1, 0.83)),
    ("a2.hit", "Staff_Attack2", 0.28, (0.25, 0.9, -1.0), (-0.98, 0.05, -0.2)),
    ("a2.follow", "Staff_Attack2", 0.4, (-0.35, 0.9, -0.8), (-0.6, 0.05, 0.8)),
    ("a3.raise", "Staff_Attack3", 0.26, (0.3, 2.1, -0.45), (0, 1, 0.1)),
    ("a3.top", "Staff_Attack3", 0.42, (0.3, 2.15, -0.45), (0, 1, 0.1)),
    ("a3.slam", "Staff_Attack3", 0.5, (0.3, 0.75, -1.0), (0, -0.6, -0.8)),
    ("a3.settle", "Staff_Attack3", 0.66, (0.3, 0.7, -1.0), (0, -0.6, -0.8)),
]
for name, clip, t, hand, direction in STAFF_KEYS:
    grip2("Staff", name, clip, t, "Staff", hand, direction, 0.65)

DAGGER_KEYS = [
    ("hold", "Dagger_Idle", 0, (0.8, 0.4, -0.9), (0, 0.5, -0.85)),
    ("a1.cock", "Dagger_Attack1", 0.08, (0.95, 0.95, 0.15), (0, 0.1, -1)),
    ("a1.hit", "Dagger_Attack1", 0.16, (0.45, 1.1, -1.85), (-0.1, 0.05, -1)),
    ("a1.follow", "Dagger_Attack1", 0.24, (0.45, 1.05, -1.8), (-0.1, 0.05, -1)),
    ("a2.windup", "Dagger_Attack2", 0.08, (1.25, 1.35, -0.35), (0.4, 0.55, -0.73)),
    ("a2.hit", "Dagger_Attack2", 0.16, (-0.4, 0.85, -1.4), (-0.9, -0.15, -0.4)),
    ("a2.follow", "Dagger_Attack2", 0.26, (-0.8, 0.8, -1.0), (-0.85, -0.2, 0.45)),
    ("a3.cock", "Dagger_Attack3", 0.12, (0.85, 0.45, 0.2), (0, 0.3, -0.95)),
    ("a3.stab1", "Dagger_Attack3", 0.22, (0.4, 1.05, -1.8), (0, 0, -1)),
    ("a3.pull", "Dagger_Attack3", 0.28, (0.7, 0.8, -0.9), (0, 0.2, -1)),
    ("a3.stab2", "Dagger_Attack3", 0.34, (0.3, 1.0, -1.9), (0, 0, -1)),
    ("a3.settle", "Dagger_Attack3", 0.46, (0.3, 0.95, -1.85), (0, 0, -1)),
]
for name, clip, t, hand, direction in DAGGER_KEYS:
    grip1("Dagger", name, clip, t, "Dagger", hand, direction)

# Crossbow: trigger hand at the grip, left hand under the fore-end.
CB_AIM = ((0.45, 1.55, -0.75), (0, 0, -1))
CB_RECOIL = ((0.5, 1.62, -0.6), (0, 0.15, -0.99))
CB_KEYS = [
    ("hold", "Crossbow_Idle", 0, (0.55, 0.25, -0.75), (-0.5, -0.15, -0.85)),
    ("a1.aim", "Crossbow_Attack1", 0.16) + CB_AIM,
    ("a1.fire", "Crossbow_Attack1", 0.3) + CB_AIM,
    ("a1.recoil", "Crossbow_Attack1", 0.36) + CB_RECOIL,
    ("a2.aim", "Crossbow_Attack2", 0.12) + CB_AIM,
    ("a2.fire", "Crossbow_Attack2", 0.2) + CB_AIM,
    ("a2.recoil", "Crossbow_Attack2", 0.26) + CB_RECOIL,
    ("a3.aim", "Crossbow_Attack3", 0.2) + CB_AIM,
    ("a3.hold", "Crossbow_Attack3", 0.56) + CB_AIM,
    ("a3.recoil", "Crossbow_Attack3", 0.66, (0.5, 1.68, -0.5), (0, 0.22, -0.97)),
]
for name, clip, t, hand, direction in CB_KEYS:
    grip2("Crossbow", name, clip, t, "Crossbow", hand, direction, 0.8, (0, -0.12, 0))
# Reload: crossbow tipped down, the left hand cranks the string back.
grip1("Crossbow", "a3.reload", "Crossbow_Attack3", 0.86, "Crossbow", (0.6, 0.5, -0.85), (0, -0.75, -0.65))
T("CrossbowL.a3.reload", "Crossbow_Attack3", 0.86, "Left", "Crossbow", rel(0.4, 0.95, -0.55), None, [70, 0, -20, 90, 0])


def main():
    clips = json.load(open(sys.argv[1]))
    results = {}
    solved = {}  # id -> (hand point, weapon direction) actually reached
    worst = 0
    for id, clip, t, side, job, hand, direction, start in TARGETS:
        body = body_at(clips, clip, t)
        whand = 1.0
        if isinstance(hand, tuple) and hand[0] == "follow":
            _, lead, offset, extra = hand
            h0, d0 = solved[lead]
            Rw, _ = frame(body)
            target = h0 + offset * d0 + Rw @ V(*extra)
            whand = 4.0
        else:
            target = hand(body)
        aim = direction(body) if callable(direction) else direction
        aim = aim if aim is not None else V(0, 1, 0)
        out = solve(side, GRIP[job], body, tuple(target), tuple(aim),
                    wdir=1.0 if direction is not None else 0.0, whand=whand, start=start, quiet=True)
        v = [out[f"{side}Shoulder"][a] for a in "xyz"] + [out[f"{side}Elbow"]["x"]] + [out[f"{side}Wrist"][a] for a in "xyz"]
        h, d = arm_chain(body, side, v[:3], v[3], v[4], GRIP[job], v[5], v[6])
        solved[id] = (h, d)
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
