# Eye iris v61 — a natural iris proportion

The eye's iris family is authored so large that it fills almost the whole
visible aperture. Measured on the production source: the iris is 0.031 m wide
against a 0.051 m sclera, and the lid opening is about 0.026 m, so the iris
covers roughly **86% of the opening** where a human eye reads as 45–55%. That
oversize disc is the dominant reason the character looks wide-eyed and
unblinking in the creator's Face tab — the "googly" read the iteration 60 and 61
reviews both recorded.

`tools/probe_eye_coverage.py` is what settled the cause. Walking the eyeball in
height bands and comparing the frontmost sclera point with the frontmost
surrounding skin at the same height shows the lid is **already correct**: every
band of the sclera sits 3–12 mm behind the surrounding skin, covered on 11 of 14
bands on the left eye and 12 of 14 on the right. So neither the lid nor the
socket needed work, and the fix is the iris proportion alone.

Run from the repository root:

```sh
python3 tools/eye_iris_v61/generate.py --repository . --output dist/eye_iris_v61 --apply
```

## What it does

Each of the six iris-family discs (`Eyes_Iris_edge`, `Eyes_Iris`, `Eyes_Pupil`,
both sides) is scaled radially toward its own centre by **0.70**, so the limbal
ring, iris and pupil stay concentric. Scaling about each disc's own centre leaves
the layering depth untouched, so the pieces cannot start intersecting.

The catchlight is deliberately **not** scaled: it keeps its authored size, so the
highlight stays readable on the smaller iris rather than shrinking away with it.

Measured result per family (pupil shown; all six discs scale by exactly 0.700):

| Family | Iris radius before | after | Changed objects |
| --- | ---: | ---: | ---: |
| adult | 0.00748 | 0.00523 | 6 |
| child | 0.00660 | 0.00462 | 6 |
| teen | 0.00688 | 0.00481 | 6 |
| elder | 0.00743 | 0.00520 | 6 |

Every disc's centre is preserved to within 2.5e-6 m, which is float32 mesh
storage rounding on coordinates that sit ~1.6 m up. Every other object in the
blend (454 in adult/child/teen, 462 in elder) is byte-compared before and after
across geometry, UVs, weights, shape keys, modifiers, transforms, materials and
visibility.

All four families share the identical eye structure — the same 241-vertex iris
and 922-vertex sclera at the same proportions — so one factor suits every age
stage rather than needing a per-family table.

## Verification

The driver asserts each family's decoded glTF contract against that family's own
qualified export, so the nine face-identity blend shapes (`Blink`, `Eye_Spacing`,
`Face_Round`, `Hand_Grip_L/R`, `Jaw_Strong`, `Nose_Wide`, `Sit`, `Smile`), the
primitive and morph-primitive counts, the material count and the single skin
cannot drift. It then records every hash, and with `--apply` re-qualifies
`art/source/character_production_hashes.json` and the adult decoded PINS in
`tools/verify_character_exports.py`, re-runs that verifier, and reproduces the
qualified adult bytes through the established
`tools/export_character_variant.py` path.

Evidence: `evidence/iris61/` (matched Blender before/after face crops) and the
creator's own Face tab in `evidence/character61/face_close.png`, which is the
view the defect was reported in.

## Known limitations

- The iris now reads at a natural proportion, but it still has no surface detail
  — no fibre striations and only a flat limbal ring. At extreme close-up it is a
  smooth disc rather than a detailed iris.
- The upper-lid boundary remains a hard edge with no crease or lash line, and
  there is still no tear duct. Those are separate defects that this change does
  not address.
