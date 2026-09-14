# Adult Tee and Casual shoulder tailoring candidate

This bounded original-art stage changes vertex positions only on
`Outfit_Tee_Shirt` and `Outfit_Casual_Shirt`. Both input meshes have 6,002
vertices, identical geometry, no shape keys and an ARMATURE modifier. Shipped
sources/assets and Godot scripts are not edited. The author accepts a fresh
copy of the final composed adult face/hair source, so it can be reused after
those independent stages are accepted.

The input measurements are in `evidence/garment_v62/source_inspection.json`.
The initial source SHA-256 is
`b4b5b722b486fa757dcc0e034d27eb80ce4658bf2c79f1b045dffb9a6753d049`.
The actual shirt top contour has a sharp shoulder drop followed by a flatter
sleeve crown. This stage targets that large-scale form, not surface noise.

## Correction and preservation

- Measure the top silhouette using triangle/plane intersections between the
  actual collar-width and arm-joint landmarks. Relax the uneven shoulder
  profile toward a continuous, gently sloping transition.
- The default is contour-only. Optional neighbor fairing and radial sleeve
  reduction remain explicit experimental arguments, not accepted defaults.
  Candidate A's stronger settings failed the pose/clearance gate and are not
  suitable for promotion; its failure receipt is retained.
- Smooth the measured displacement field and constrain it against the actual
  upper-arm skin surface. Existing tight contacts limit inward motion. A
  smoothly faded local triangle barrier protects the thin armhole triangles
  while the larger shoulder dome is reshaped. These are candidate operations;
  the separate fresh-file verifier still decides whether they succeeded.
- Keep all shirt vertices within 9 mm of collar, placket, cuff and hem surfaces
  exactly unchanged; fade the correction outside that zone. The measured
  initial source has 1,151 such vertices per shirt. Lower drape is also fixed.
- Preserve topology, UVs, weights, material assignments, rig, transforms,
  properties, trims, other outfits, skin/head/hair and all non-owned objects.
  The existing child-shirt source-facts helper provides the exact native
  witness; its files are not modified by this stage.

```sh
blender -b --threads 1 --python tools/garment_v62/inspect.py -- \
  --source art/characters.blend \
  --report evidence/garment_v62/source_inspection.json

env OPENBLAS_NUM_THREADS=1 OMP_NUM_THREADS=1 \
  blender -b --threads 1 --python-exit-code 1 --python tools/garment_v62/author.py -- \
  --source art/characters.blend \
  --output art/experiments/garment_v62/characters_shirt_next.blend \
  --report evidence/garment_v62/author_next.json

env OPENBLAS_NUM_THREADS=1 OMP_NUM_THREADS=1 \
  blender -b --threads 1 --python-exit-code 1 --python tools/garment_v62/verify.py -- \
  --baseline art/characters.blend \
  --candidate art/experiments/garment_v62/characters_shirt_next.blend \
  --report evidence/garment_v62/verify_next.json
```

The author refuses to overwrite a candidate or source and requires the exact
original shirt geometry hash, preventing accidental double application.
Verification reopens
both files independently, verifies exact protected data and pinned vertices,
then evaluates the real weighted armature in rest, walking arm swing, forward
reach, arms-out and one-arm-raised poses. It checks triangle orientation/area
against the same source pose and measures new or worsened upper-arm exposure.
Any existing source exposure is reported separately. This is not cloth
simulation or an arbitrary-pose guarantee. JSON failure receipts are retained.

## Matched visual comparison

```sh
blender -b --threads 1 --python-exit-code 1 --python tools/garment_v62/render.py -- \
  --source art/characters.blend --paired \
  --output evidence/garment_v62/baseline.png

blender -b --threads 1 --python-exit-code 1 --python tools/garment_v62/render.py -- \
  --source art/experiments/garment_v62/characters_shirt_next.blend --paired \
  --output evidence/garment_v62/candidate_next.png
```

The diagnostic changes only the unsaved render scene: identical neutral cloth,
camera, lighting and pose expose form differences. `--outfit Casual` shows its
retained placket/collar; `--pose` accepts the tested pose names. A numerical
pass alone is not visual acceptance. Review native pairs and the eventual
Godot import honestly before promoting anything. Run at most one heavy job
from this stage and coordinate rendering with the eye/hair work on the shared
machine. Never run Godot CLI against the live project for these tests.

## Retained evidence and current status

- A: stronger mesh fairing and sleeve contraction. Failed all five pose cases
  for both shirts. The rest pose had 447 new exposed upper-arm samples and two
  source-normal reversals. Retained as a rejected experiment, not a result.
- B: contour-only first revision. Preservation passed, but the rest pose still
  had 37 new exposed samples (up to 1.35 mm) and one source-normal reversal.
  `diagnose_b.json` records the actual affected vertices: the outer cap had
  only about 0.8–1.6 mm of source clearance, and the proposed contour lowered it
  2–4 mm. The narrow back-armhole triangle also needed a local safety limit.
- C: code adds the skin-surface constraint, smooth displacement field, local
  triangle barrier, and a shoulder slope starting nearer the actual collar.
  Its first author process ended with SIGTERM (exit 143) before saving any
  candidate. `author_c_interrupted.json` records this. After root lifted the
  temporary relaunch hold, author session 95805 completed with exit 0 and
  saved `characters_shirt_c.blend`, SHA-256
  `408045a4ac7f23d2c89028b6619f1f6f2159fda19540b771db47b00a6f914089`.
  The source, 458 other objects, and all owned topology/UV/weights/material
  assignments remained exact. Each shirt has 1,719 changed vertices, with a
  maximum 8.13 mm movement; 38 vertices were limited by actual skin clearance.
- C's fresh verifier session 80350 exited 1. Rest, reach and arms-out passed;
  walking has one source-normal reversal per shirt, and one-arm-raised has
  one newly exposed upper-arm skin sample per shirt (about 1.97 mm).
  `verify_c.json` retains all four failure entries. C is not accepted.
- Pending, untested work: `pose_safety.py` and its `author.py` integration
  add local limits derived from actual original/proposed ARMATURE evaluations
  in the same five poses. The files compile, but this code has never run
  natively and its output has not been verified. `render_pair.py` is also
  prepared but unrun; it generates sequential baseline/candidate views and
  checks saved matching camera, light, world and diagnostic-material settings.

## Stop/checkpoint

Root relayed the user's request to finish up. No D/next candidate or garment
render has been launched. No native job from this stage remains live. Preserve
the C artifact, all A/B/C failed receipts and the pending code for a future
explicitly resumed pass. The sample commands above use fresh `next` filenames
and are future instructions, not commands run during this checkpoint.

The original source remains unchanged. No garment has been promoted and no
matched garment render has been run yet. A/B/C are frozen artifact receipts of
earlier algorithm versions; the current author includes the untested pose-aware
refinement and is not claimed to reproduce those earlier candidate bytes.
