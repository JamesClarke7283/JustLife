# Iteration 63 — eleven face controls on every production character

14 September 2026. Reviewed the working tree on top of `ed0228e` ("Add household
pets and a background theme"). This is a **verified repair record plus its
evidence**, not a fresh full-game verdict. The full-request dimensions that this
pass does not exercise are explicitly left unverified at the end.

## The defect

The creator's **Face** tab offers eleven sliders and `LifeActor.IDENTITY_KEYS`
lists eleven keys, and `set_face_feature` accepts all eleven. The shipped assets
only contained four. Measured directly from the production GLBs:

| Model | Identity controls before |
| --- | --- |
| `character.glb`, `character_{broad,lod,broad_lod}.glb` | 4/11 |
| `character_{child,teen,elder}*.glb` (9 files) | 4/11 |
| `character_baby*.glb` (4 files) | 4/11 |
| `character_rig.glb` (gitignored review slot) | 11/11 |

`Face_Round`, `Jaw_Strong`, `Eye_Spacing` and `Nose_Wide` existed. `Nose_Length`,
`Lip_Fullness`, `Brow_Arch`, `Chin_Length`, `Face_Length`, `Mouth_Width` and
`Nose_Bridge` did not. `LifeActor._discover_deformation` finds identity morphs
only when the mesh actually exposes them, so those seven sliders wrote into
`profile`, updated the UI, and changed nothing on the model. **Seven of eleven
creator face controls were inert in the running game on every age and every
body frame.** The maintained `tests/probe_character62.gd` already asserted all
eleven, and failed 266 times against the shipped assets.

## What changed

- **Adult (`character.glb`, `character_broad.glb`, `character_lod.glb`,
  `character_broad_lod.glb`)** — promoted from the reviewed iteration-62
  composition `art/experiments/buzz_v62/integrated_fair_b/ready.blend`
  (SHA-256 `01ade04129a1a9056eeb1c83afe2e838abe433e45c088699b3fa026144d5dd81`).
  It carries eleven controls, the welded orbital socket, the recolourable
  vertex-colour complexion pass and the repaired cropped Buzz, and it keeps the
  complete iteration-55 wardrobe set. The three variants the experiment had not
  exported were produced from that same source with
  `tools/portrait_v62/export_variant.py` under the released family conventions.
- **Child, teen, elder (12 files)** — authored from each family's own released
  editable source, not copied from the adult. `tools/portrait_v62/identity.py`
  adds `Nose_Length`, `Lip_Fullness`, `Brow_Arch` and `Chin_Length` at that
  family's measured amplitude scale (elder 1.0, teen 0.92, child 0.87);
  `tools/identity_shape_v62/author.py` adds `Face_Length`, `Mouth_Width` and
  `Nose_Bridge` from the family's own measured seam ring, eye plane and nostril
  centres. Both tools derive every field from the real geometry, so the child's
  shorter lower face and the elder's longer one each get proportionally correct
  displacement.
- **Baby (4 files)** — the released infant source was reconstructed first (it is
  not in the repository), then completed with the same two tools at the infant
  amplitude scale of 0.35 and the infant's own anchors.
- **`tools/identity_shape_v62/common.py`** — one real bug fixed; see below.
- **`tools/ensure_candidate_uvs.py`** — new, described below.

## The authoring bug this exposed

`Face_Length` fades toward the neck between `head_lowest_world_z` and
`mouth.z - face_height * 0.45`. For the infant those two values invert
(`head_low` 0.39326 > the band's upper end 0.38574), because an infant's head is
mostly above its mouth and `head_lowest_world_z` is the *bottom of the head
mesh*, below the mouth. The negative denominator made the smoothstep band
degenerate, so `max(0, eye.z - z) * orbital * neck * front` was zero at every
vertex and `Face_Length` silently produced no geometry — the author then skipped
the key entirely, which is why a key the report listed was absent from the file.

Two minimal changes fix it: `smooth()` now treats an empty or inverted band as a
step rather than a negative-width fade, and the `Face_Length` neck band is
clamped to `max(upper, head_low)` so it cannot invert. **Re-authoring child,
teen and elder after the fix reproduced their files byte for byte** (verified by
SHA-256), so the change cannot have perturbed any already-accepted family. The
infant `Face_Length` now moves 2.198 mm at full slider on the lower lip and
1.112 mm on the nostrils, proportionate to its 0.35 amplitude.

`ensure_candidate_uvs.py` addresses a second real export failure. The released
baby generator calls its own `ensure_uvs()` before export, but a candidate
authored through the portrait/identity chain skips that step, so the infant brow
ribbons reached the exporter with no UV layer. Godot then reported *"UVs are
required to generate tangents"* and the character runner's import gate correctly
**failed the whole run**. The new tool applies the generator's own box-projection
rule to meshes that have no UV layer and never touches a mesh that already has
one; it added exactly two layers (`Hair_Brow_L`, `Hair_Brow_R`, 128 polygons
each) and changed nothing else.

## Verification

| Check | Command | Result |
| --- | --- | --- |
| Character contract, all ages/frames, rendered | `python3 tests/run_character_quality.py --render probe_character62` | **5,178 checks, 0 failures** (was 5,178 with 266 failures, then 84, then 56, then 14) |
| Production asset audit | headless GLB probe, all 20 models | **20/20 have 11/11 controls**; 16 non-baby models also 7/7 wardrobe groups |
| Actor integration | `godot --headless --script res://tests/test_actor.gd` | **4,002 checks, 0 failures** (32 failures on the pre-pass assets) |
| Baby life stage | `test_baby_stage.gd` | **58 checks, 0 failures** (7 failures on the pre-pass assets) |
| Household extras | `test_household_extras.gd` | **48 checks, 0 failures** |
| Music and pets | `test_music_and_pets.gd` | **105 checks, 0 failures** |

The failure progression is direct evidence the defect is gone rather than
masked: 266 → 84 (adult detailed model) → 56 (all four adult variants) → 14
(all age families) → 0 (baby). Rendered portraits for every age and every
identity extreme are in `evidence/character63/` (41 images).

`art/source/character_production_hashes.json` was refreshed for the 16 changed
GLBs, and the four editable sources were promoted to the standard
`art/characters*.blend` paths. `tools/verify_character_exports.py`'s `PINS` were
re-qualified for the four adult variants.

## Limits and what remains unverified

- The seven newly authored controls are verified **structurally and
  functionally** (present on every mesh that should carry them, applied to real
  blend shapes, correct signed range, neutral at zero, and rendered at both
  extremes). They are **not** independently art-reviewed for visual quality at
  every combination on every age.
- No critic has yet re-scored character art against the iteration-62 verdicts
  (5.5–7.0). This pass removes dead controls and promotes already-reviewed adult
  candidates; it is not a claim that the outstanding art criticism — eye-region
  integration, hair clump hierarchy, independent facial identities, material
  separation — has been resolved.
- The full-request rubric dimensions of usability in motion, simulation depth,
  creative breadth and reliability were **not** re-exercised by this pass. The
  latest full-request score remains **7.3/10** (`iteration_55_wardrobe.md`); the
  latest character-art scores remain the iteration-62 set.
- The infant model is a first functional pass at this control set. Its
  proportions were not part of any age-lineup review.

**Decision: the dead-control defect is repaired and verified; continue toward
the full target.**
