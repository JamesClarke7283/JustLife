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

`art/source/character_production_hashes.json` was refreshed for all twenty
entries (sixteen GLBs and four editable sources) and the four editable sources
were promoted to the standard `art/characters*.blend` paths.
`tools/verify_character_exports.py`'s `PINS` were re-qualified for the four
adult variants. Both records are refreshed together and checked by
`python3 tools/requalify_character_hashes.py`; `--check` exits non-zero on any
staleness.

## Independent critic verdict (added after review)

An independent reviewer that did not author this work inspected all 41 images in
`evidence/character63/` and the changed files. Its verdict:

- **Character art is unchanged at 6.5/10.** It confirmed the headline claim
  ("all twenty production GLBs now carry 11/11 identity morphs where they
  carried 4/11 before, verified from git blobs and per-target displacements")
  and that `combined_maximum` versus `combined_minimum` show the seven former
  dead sliders genuinely reshaping the lower face, mouth and chin. It also
  confirmed the `smooth()` fix and the UV tool are correctly scoped. It found
  no visual improvement to the artwork itself, which matches this review's own
  position: **this pass repairs a functional defect, it does not raise art
  quality.**
- **It raised three defects, all of which are accepted.** Two were real bugs and
  are fixed; the third is documented below.

### 1. Stale `.blend` hashes in the production manifest — real bug, fixed

I refreshed the sixteen GLB entries in
`art/source/character_production_hashes.json` but left the four editable
`.blend` entries at their pre-promotion values, so a manifest whose whole
purpose is to detect exactly that drift was itself wrong
(`art/characters.blend` recorded `b4b5b722…` while the file was `01ade041…`).

**Root cause and prevention.** The repo already has an `--apply` pattern that
refreshes the manifest and the verifier pins together; I hand-edited instead.
`tools/requalify_character_hashes.py` now performs both refreshes in one pass,
verifies what it wrote, and exposes `--check` so a test or CI step can fail on
staleness. It has no bypass: after writing it re-reads both records and returns
non-zero if anything still disagrees.

That tool immediately caught a **second bug of the same class**: I had written
raw SHA-256 values into `tools/verify_character_exports.py`'s `PINS`, but the
verifier compares *semantic digests* (a canonicalised decode), not file hashes.
The tool's `--check` reported all four pins stale, the refresh rewrote them in
the correct form, and `verify_all('assets/models')` now passes for all four
adult variants. Both records are clean under `--check`.

### 2. The adult Bob shell was silently swapped — disclosed

The promoted adult source replaces the previous Bob. Node counts in
`character.glb`: **Bob 31 → 5**, every other group identical (Brow, Buzz,
Cardigan, Casual, Crop, Curls, Ear, Eye, Hoodie, Jacket, Jewelry, Leg, Lip,
Long, Nose, Pony, Shoe, Shorts, Tee, Trousers all unchanged); total nodes
403 → 377. I failed to disclose this in the change summary.

On inspection the new Bob is a **better** integrated mass — `bob_three_quarter.png`
and `bob_front.png` show a single continuous bob, where the iteration-62 critic
described the old construction as "a row of separate hanging rods" with "abrupt
cut root ends against the crown cap". It is recorded here rather than reverted,
but it is a material asset change that should have been named, and it carries no
new independent accept/reject review of its own.

### 3. The infant controls move very little — working as designed, limits stated

The reviewer measured the baby's seven new controls at roughly 0.7–2.1 mm of
displacement and noted this is below one rendered pixel at portrait size. That is
correct and is the intended behaviour: the amplitude chain applies an infant
scale of 0.35 precisely so an infant is not deformed by adult-proportioned
fields, and an infant head is physically small, so a proportionate displacement
is small in absolute terms. `age_baby_face.png` shows a live slider at a
non-zero value, so the controls are wired. It is nonetheless a fair criticism of
*visible* effect: **on the baby these sliders will read subtly at the creator's
normal zoom.** If an infant needs more visible shaping, that requires a larger
infant amplitude and its own art review, which this pass did not do.

## Limits and what remains unverified

- The seven newly authored controls are verified **structurally and
  functionally** (present on every mesh that should carry them, applied to real
  blend shapes, correct signed range, neutral at zero, and rendered at both
  extremes). They are **not** independently art-reviewed for visual quality at
  every combination on every age. On the infant, the proportionate displacement
  is small enough to read subtly at the creator's normal zoom.
- No critic has found character art improved by this pass. The independent
  review places it at **6.5/10, unchanged from iteration 62**, and that is
  accepted: this pass removes dead controls, it does not raise art quality. The
  outstanding criticism — eye-region integration, hair clump hierarchy,
  independent facial identities, material separation, shoulder/sleeve joins —
  is untouched.
- The full-request rubric dimensions of usability in motion, simulation depth,
  creative breadth and reliability were **not** re-exercised by this pass. The
  latest full-request score remains **7.3/10** (`iteration_55_wardrobe.md`).
- The infant model is a first functional pass at this control set. Its
  proportions were not part of any age-lineup review.
- The promoted adult Bob's own accept/reject status was not re-reviewed; it is
  disclosed above with its measured node-count change.

**Decision: the dead-control defect is repaired and verified, and the two
integrity bugs the independent review found are fixed with a guard against
recurrence. Character art is unchanged. Continue toward the full target.**
