# Hair lock v60 — rounded tapered locks and seated hoodie hood

Re-authors the flat-paddle hair locks (`Hair_Bob_Lock.*`, `Hair_Long_Lock.*`,
`Hair_Waves_Lock.*`, twelve meshes per style in every age family) into rounded
tapered tubes, and seats the hoodie cowl onto the shell shoulders so no
background sliver shows between hood and shoulders. It replaces the paddle
boards (four straight elliptical rings with hard flat end caps) with convex
cross-sections that taper to a soft rounded pole tip plus a slight
deterministic droop, twist and sway; the cowl's lower fabric is pressed at
least eight millimetres into the untouched shell surface. Reference for the
target look: the Sims 4 hair study of 2026-08-25 (soft rounded lobes, tapered
tips) — the geometry itself is original JustLife work.

Run from the repository root:

```sh
python3 tools/hair_lock_v60/generate.py --repository . --output dist/hair_lock_v60 --apply
```

The tool extracts the pinned baseline blends from the commit recorded in
`manifest.json` (the working-tree files must hash-identical or the run is
refused), authors candidate blends in fresh bounded Blender processes, exports
all sixteen GLBs through the exact `tools/create_wardrobe.py` export steps
(rest pose, zeroed morphs, broad x-scale, live-LOD decimation with caps 0.12,
leg pieces 0.38, everything else 0.22), records every input/output hash in the
output `RECEIPT.json`, renders before/after evidence into `evidence/hair60/`,
and — only with `--apply` — copies candidates into the working tree,
re-qualifies `art/source/character_production_hashes.json` and the adult PINS
in `tools/verify_character_exports.py`, then re-runs that verifier and one
`tools/export_character_variant.py` reproduction. Running the tool a second
time refuses by design: the applied tree no longer matches the pinned inputs.

Preservation guarantees, asserted per family inside `author.py`:

- Exactly 37 objects change: the 36 locks and `Outfit_Hoodie_Hood`. Every other
  object's digest (geometry, UVs, weights, shape keys, modifiers, transforms,
  materials, visibility) is byte-compared before and after.
- Lock roots are untouched: the root ring keeps the original local vertices
  exactly; frames, spine, taper and droop derive from each lock's own measured
  rings (Catmull-Rom resampling, parallel-transported frames, per-lock
  deterministic seed from the object name).
- Locks stay within budget: 73 vertices / 73 faces per lock against the
  original 48/38 (both ≤ 2×). Object names, parents, `Hair` material, the
  `SurfaceUV` layer, smooth shading and the modifier stack (Bob's level-2
  subsurf; the others raw) are unchanged; no shape keys or vertex groups are
  added — locks remain rigid to the Head pivot exactly as before.
- The hood keeps its 392 vertices and qualified skin weights; seating moves
  lower fabric along the nearest shell normal (full press while hovering below
  6 cm, smooth blend out to 12 cm or 4.5 cm lateral distance), and the shell is
  never touched. Every fully-seated vertex ends at least 8 mm inside the shell.

Verified per family: 423 (431 elder) objects unchanged, hood seat depth, GLB
lock-node survival in all four variants per family (decimation may shrink the
tubes but never annihilate them), sixteen export hashes recorded, and
before/after renders for front, three-quarter, walk, arms-out, arms-forward
plus a 30°-side 60 mm collar close-up.

Known limitations: the tube cross-section keeps each lock's root aspect ratio,
so very flat roots stay slightly oval; the cowl's open side ends remain open
(the shell now fills them from below); the droop/twist parameters are static
authoring constants, not simulated cloth.
