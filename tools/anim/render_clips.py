"""
Stick-figure contact sheets for AnimationClips (authoring aid, not shipped).

    lune run tools/anim/dump_clips > build/clips.json
    python tools/anim/render_clips.py build/clips.json build/clips [ClipName ...]

Each clip becomes one PNG: a row per key, with side / front / top views.
Joint math matches Roblox: rotation = CFrame.Angles(x, y, z) = Rx * Ry * Rz,
applied in the parent joint's frame; the character faces -Z.
Approximate R15 proportions; weapons use the OutfitBuilder grips.
"""
import json, math, os, sys
import numpy as np
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

def rx(a):
    c, s = math.cos(a), math.sin(a)
    return np.array([[1, 0, 0], [0, c, -s], [0, s, c]])
def ry(a):
    c, s = math.cos(a), math.sin(a)
    return np.array([[c, 0, s], [0, 1, 0], [-s, 0, c]])
def rz(a):
    c, s = math.cos(a), math.sin(a)
    return np.array([[c, -s, 0], [s, c, 0], [0, 0, 1]])

def joint(pose, name):
    v = pose.get(name, {})
    R = rx(math.radians(v.get("x", 0))) @ ry(math.radians(v.get("y", 0))) @ rz(math.radians(v.get("z", 0)))
    p = np.array([v.get("px", 0), v.get("py", 0), v.get("pz", 0)])
    return R, p

# Weapon direction in the hand frame (+Y toward the elbow) and extent.
def grip(deg):
    a = math.radians(deg)
    return np.array([0, math.cos(a), math.sin(a)])
WEAPONS = {
    "Warrior": ("Right", grip(-110), -0.6, 5.0, "#d0d8ff"),
    "Healer": ("Right", grip(-90), -3.1, 3.6, "#c89a5a"),
    "Archer": ("Left", grip(-90), -2.5, 2.5, "#7ad06a"),
    "Mage": ("Right", grip(-160), -0.4, 2.0, "#c070ff"),
}

def skeleton(pose, job):
    segs = []
    Rr, pr = joint(pose, "Root")
    root = np.array([0, -0.2, 0]) + pr
    def at(R, base, off):
        return base + R @ np.array(off)
    # Legs
    for side, sx in (("Left", -1), ("Right", 1)):
        Rh, _ = joint(pose, side + "Hip")
        hip = at(Rr, root, [0.5 * sx, -0.4, 0])
        R1 = Rr @ Rh
        knee = at(R1, hip, [0, -1.2, 0])
        R2 = R1 @ joint(pose, side + "Knee")[0]
        ankle = at(R2, knee, [0, -1.2, 0])
        R3 = R2 @ joint(pose, side + "Ankle")[0]
        toe = at(R3, ankle, [0, -0.15, -0.6])
        c = "#3060c0" if side == "Left" else "#c03030"
        segs += [(hip, knee, c, 3), (knee, ankle, c, 3), (ankle, toe, c, 2)]
    Rw = Rr @ joint(pose, "Waist")[0]
    waist = at(Rr, root, [0, 0.2, 0])
    neck = at(Rw, waist, [0, 1.4, 0])
    segs.append((root, waist, "#444", 4))
    segs.append((waist, neck, "#444", 6))
    hipL = at(Rr, root, [-0.5, -0.4, 0]); hipR = at(Rr, root, [0.5, -0.4, 0])
    segs.append((hipL, hipR, "#444", 4))
    Rn = Rw @ joint(pose, "Neck")[0]
    head = at(Rn, neck, [0, 0.7, 0])
    nose = at(Rn, head, [0, 0, -0.6])
    segs.append((neck, head, "#444", 3))
    segs.append((head, nose, "#e08000", 3))
    weapon_side, wdir, w0, w1, wc = WEAPONS.get(job, (None, None, 0, 0, None))
    for side, sx in (("Left", -1), ("Right", 1)):
        sh = at(Rw, waist, [1.0 * sx, 1.2, 0])
        R1 = Rw @ joint(pose, side + "Shoulder")[0]
        elbow = at(R1, sh, [0, -1.1, 0])
        R2 = R1 @ joint(pose, side + "Elbow")[0]
        wrist = at(R2, elbow, [0, -1.0, 0])
        R3 = R2 @ joint(pose, side + "Wrist")[0]
        hand = at(R3, wrist, [0, -0.25, 0])
        c = "#3060c0" if side == "Left" else "#c03030"
        segs += [(neck, sh, "#444", 3), (sh, elbow, c, 3), (elbow, wrist, c, 3), (wrist, hand, c, 4)]
        if side == weapon_side:
            d = R3 @ wdir
            segs.append((hand + d * w0, hand + d * w1, wc, 3))
            segs.append((hand + d * (w1 - 0.3), hand + d * w1, "#000", 4))
    return segs, head

VIEWS = [
    ("side (facing right)", lambda p: (-p[2], p[1])),
    ("front", lambda p: (-p[0], p[1])),
    ("top (facing up)", lambda p: (-p[0], -p[2])),
]

def render(name, clip, job, out):
    keys = clip["keys"]
    fig, axes = plt.subplots(len(keys), 3, figsize=(9, 3 * len(keys)))
    if len(keys) == 1:
        axes = [axes]
    for row, key in enumerate(keys):
        segs, head = skeleton(key["pose"], job)
        for col, (title, proj) in enumerate(VIEWS):
            ax = axes[row][col]
            for a, b, c, w in segs:
                pa, pb = proj(a), proj(b)
                ax.plot([pa[0], pb[0]], [pa[1], pb[1]], color=c, lw=w, solid_capstyle="round")
            hx, hy = proj(head)
            ax.add_patch(plt.Circle((hx, hy), 0.55, fill=False, color="#444", lw=2))
            if col < 2:
                ax.axhline(-3.0, color="#999", lw=1)  # floor at rest
            ax.set_xlim(-5.5, 5.5); ax.set_ylim(-5.5 if col == 2 else -3.6, 5.5 if col == 2 else 6.5)
            ax.set_aspect("equal"); ax.set_xticks([]); ax.set_yticks([])
            if row == 0:
                ax.set_title(title, fontsize=9)
            if col == 0:
                marks = [m for m, t in clip["markers"].items() if abs(t - key["t"]) < 1e-6]
                ax.set_ylabel(f"t={key['t']:.2f} {key['ease']}" + (f"  <{','.join(marks)}>" if marks else ""), fontsize=9)
    fig.suptitle(name, fontsize=12)
    fig.tight_layout()
    fig.savefig(os.path.join(out, name + ".png"), dpi=60)
    plt.close(fig)

def main():
    clips = json.load(open(sys.argv[1]))
    out = sys.argv[2]
    os.makedirs(out, exist_ok=True)
    wanted = sys.argv[3:] or sorted(clips)
    for name in wanted:
        job = name.split("_")[0] if "_" in name else "Warrior"
        render(name, clips[name], job, out)
        print("rendered", name)

if __name__ == "__main__":
    main()
