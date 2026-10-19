"""
Checks every sound id in src/shared/Definitions/CreatureSounds.luau against
Roblox's asset API (authoring aid, not shipped; PLAN.md D-62): each must be
an Audio asset published by ProSoundEffects or Roblox, i.e. from the
licensed Creator Store library. Needs network access.

    python tools/creatures/check_sounds.py
"""
import json, os, re, sys, time, urllib.request

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
ALLOWED = {7462895450: "ProSoundEffects", 1: "Roblox"}


def details(asset_id):
    url = f"https://economy.roblox.com/v2/assets/{asset_id}/details"
    for _ in range(3):
        try:
            request = urllib.request.Request(url, headers={"User-Agent": "riftbound-check-sounds"})
            with urllib.request.urlopen(request, timeout=20) as response:
                return json.loads(response.read())
        except Exception:
            time.sleep(1.5)
    return None


def main():
    path = os.path.join(ROOT, "src", "shared", "Definitions", "CreatureSounds.luau")
    ids = sorted({int(x) for x in re.findall(r"sound\((\d+),", open(path, encoding="utf-8").read())})
    bad = 0
    for asset_id in ids:
        d = details(asset_id)
        ok = d is not None and d.get("AssetTypeId") == 3 and d["Creator"]["Id"] in ALLOWED
        bad += 0 if ok else 1
        name = d.get("Name") if d else "(no response)"
        creator = d["Creator"]["Name"] if d else ""
        print(f"{'ok  ' if ok else 'FAIL'} {asset_id} {name} [{creator}]")
    print(f"{len(ids)} sounds checked: {bad} failed")
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
