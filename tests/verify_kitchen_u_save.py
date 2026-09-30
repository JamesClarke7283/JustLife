#!/usr/bin/env python3
"""Independently verify the persisted output of test_kitchen_u_pointer's U."""
import argparse
import hashlib
import json
import math
from pathlib import Path

EXPECTED = [
    ("corner_counter", 7.575, 0, 0), ("counter", 8.5, 0, 0),
    ("stove", 9.55, 0, 0), ("counter", 10.6, 0, 0),
    ("fridge", 11.575, 0, 0), ("corner_counter", 12.425, 0, 270),
    ("counter", 7.575, .925, 90), ("counter", 7.575, 1.975, 90),
    ("counter", 12.425, .925, 270), ("counter", 12.425, 1.975, 270),
]
SIZES = {"counter": (1.05, .8), "corner_counter": (.8, .8),
         "fridge": (.9, .85), "stove": (1.05, .85)}


def near(a, b):
    return math.isclose(float(a), float(b), abs_tol=1e-5)


def bounds(entry):
    w, d = SIZES[entry["kind"]]
    if round(entry["rotation"] / 90) % 2:
        w, d = d, w
    return (entry["x"] - w/2, entry["z"] - d/2,
            entry["x"] + w/2, entry["z"] + d/2)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--save", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    data = json.loads(args.save.read_text())["data"]
    units = [e for e in data["world"] if str(e.get("id", "")).startswith("placed_")]
    checks = []

    def check(ok, message):
        checks.append({"ok": bool(ok), "message": message})
        print("PASS" if ok else "FAIL", message)

    check(len(units) == 10 and len({e["id"] for e in units}) == 10,
          "Exactly ten distinct purchased IDs survive the disk save")
    ordered = []
    for index, (kind, x, z, angle) in enumerate(EXPECTED):
        matches = [e for e in units if e["kind"] == kind and near(e["x"], x)
                   and near(e["z"], z) and near(e["rotation"] % 360, angle)]
        check(len(matches) == 1, f"Unit {index}: {kind} preserves exact position and rotation")
        if len(matches) != 1:
            continue
        entry = matches[0]
        ordered.append(entry)
        if kind in ("counter", "corner_counter"):
            check(entry.get("style") == "drawers" and entry.get("color") == "c97c66",
                  f"Unit {index}: selected drawer style and terracotta finish survive")
    check(data["funds"] == 18070,
          "Funds retain exactly six cabinets, two 15-Simoleon corners, oven and fridge")
    if len(ordered) == 10:
        rectangles = [bounds(e) for e in ordered]
        for a, b in [(0, 1), (1, 2), (2, 3), (3, 4), (4, 5)]:
            check(near(rectangles[a][2], rectangles[b][0]), f"Saved back join {a}–{b} has zero gap")
        for a, b in [(0, 6), (6, 7), (5, 8), (8, 9)]:
            check(near(rectangles[a][3], rectangles[b][1]), f"Saved U-return join {a}–{b} has zero gap")
        overlap = False
        for i, a in enumerate(rectangles):
            for b in rectangles[i+1:]:
                overlap |= min(a[2], b[2]) - max(a[0], b[0]) > 1e-5 and min(a[3], b[3]) - max(a[1], b[1]) > 1e-5
        check(not overlap, "No saved U footprints overlap")
    report = {"save": str(args.save.resolve()),
              "save_sha256": hashlib.sha256(args.save.read_bytes()).hexdigest(),
              "checks": checks, "failures": [c for c in checks if not c["ok"]],
              "units": ordered,
              "scope": "Independent read-only audit of actual public-purchase disk output; no save modification or simulation."}
    args.output.write_text(json.dumps(report, indent=2))
    print(f"KITCHEN_U_DISK {len(checks)} checks, {len(report['failures'])} failures")
    return 1 if report["failures"] or len(checks) != 30 else 0


if __name__ == "__main__":
    raise SystemExit(main())
