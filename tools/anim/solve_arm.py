"""
Arm IK helper for authoring AnimationClips (authoring aid, not shipped).

Finds Shoulder (x, y, z), Elbow x and Wrist x so the hand reaches a target
point and the held weapon points a target direction, given the body pose
(Root / Waist). Targets are in the character's frame (faces -Z, +X right,
+Y up, origin at the hips). Prints Luau-ready joint values.

    from solve_arm import solve
    solve(side="Right", grip=-110, body={"Root": {...}, "Waist": {...}},
          hand=(x, y, z), direction=(x, y, z))
"""
import math, sys
import numpy as np
from scipy.optimize import minimize
sys.path.insert(0, __file__.rsplit("\\", 1)[0].rsplit("/", 1)[0])
from render_clips import rx, ry, rz, joint, grip as grip_dir

def arm_chain(body, side, sh, el, wr, gdeg, wy=0.0, wz=0.0):
    Rr, pr = joint(body, "Root")
    root = np.array([0, -0.2, 0]) + pr
    Rw = Rr @ joint(body, "Waist")[0]
    waist = root + Rr @ np.array([0, 0.2, 0])
    sx = 1 if side == "Right" else -1
    shoulder = waist + Rw @ np.array([1.0 * sx, 1.2, 0])
    R1 = Rw @ rx(math.radians(sh[0])) @ ry(math.radians(sh[1])) @ rz(math.radians(sh[2]))
    elbow = shoulder + R1 @ np.array([0, -1.1, 0])
    R2 = R1 @ rx(math.radians(el))
    wrist = elbow + R2 @ np.array([0, -1.0, 0])
    R3 = R2 @ rx(math.radians(wr)) @ ry(math.radians(wy)) @ rz(math.radians(wz))
    hand = wrist + R3 @ np.array([0, -0.25, 0])
    return hand, R3 @ grip_dir(gdeg)

def solve(side, grip, body, hand, direction, wdir=1.0, whand=1.0, start=None, quiet=False, stiff=0.0004):
    """`start` = hand-authored guess [sx, sy, sz, elbow, wrist]; solutions stay near it."""
    target = np.array(hand, float)
    tdir = np.array(direction, float); tdir /= np.linalg.norm(tdir)
    sx = 1 if side == "Right" else -1
    def cost(v):
        sh = (v[0], v[1], v[2]); el, wr = v[3], v[4]
        h, d = arm_chain(body, side, sh, el, wr, grip, v[5], v[6])
        c = whand * np.sum((h - target) ** 2) + wdir * 4 * (1 - d @ tdir)
        # Joint comfort limits.
        c += 0.02 * max(0, -el) ** 2 + 0.02 * max(0, el - 150) ** 2
        c += 0.02 * max(0, abs(wr) - 60) ** 2
        c += 0.002 * max(0, abs(v[1]) - 70) ** 2
        c += 0.02 * max(0, abs(v[5]) - 80) ** 2 + 0.02 * max(0, abs(v[6]) - 30) ** 2
        c += 0.00002 * (v[0] ** 2 + v[1] ** 2 + v[2] ** 2 + el ** 2 + 2 * wr ** 2)
        if start is not None:
            c += stiff * sum((a - b) ** 2 for a, b in zip(v[:5], start[:5]))
            c += stiff * 0.25 * (v[5] ** 2 + v[6] ** 2)
        return c
    best = None
    if start is not None and len(start) == 5:
        start = list(start) + [0, 0]
    seeds = []
    if start:
        # Nelder-Mead barely moves parameters that start at exactly 0.
        for twist in (-50, 0.5, 50):
            seeds.append([a if abs(a) > 1e-3 else 5.0 for a in start[:6]] + [3.0])
            seeds[-1][5] = twist
        for i in range(4):
            seeds[-1 - 0][:5] = [a if abs(a) > 1e-3 else 5.0 for a in start[:5]]
    rng = np.random.default_rng(1)
    for _ in range(0 if start else 40):
        seeds.append([rng.uniform(-40, 180), rng.uniform(-60, 60), sx * rng.uniform(-40, 100), rng.uniform(0, 140), rng.uniform(-60, 40), 0, 0])
    for s in seeds:
        r = minimize(cost, s, method="Nelder-Mead", options={"maxiter": 4000, "xatol": 0.1, "fatol": 1e-6})
        if best is None or r.fun < best.fun:
            best = r
    v = best.x
    h, d = arm_chain(body, side, v[:3], v[3], v[4], grip, v[5], v[6])
    out = {
        f"{side}Shoulder": {"x": round(v[0]), "y": round(v[1]), "z": round(v[2])},
        f"{side}Elbow": {"x": round(v[3])},
        f"{side}Wrist": {"x": round(v[4]), "y": round(v[5]), "z": round(v[6])},
    }
    if not quiet:
        print(f"-- hand err {np.linalg.norm(h - target):.2f} studs, dir err {math.degrees(math.acos(max(-1, min(1, d @ tdir)))):.0f} deg")
        for k, val in out.items():
            print(f"\t{k} = {{ " + ", ".join(f"{a} = {b}" for a, b in val.items() if b != 0 or a == 'x') + " },")
    return out
