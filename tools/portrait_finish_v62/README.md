# Local cheek and chin finish — candidate B

This is a candidate-only repair of the integrated adult's continuous head
surface. It does not promote production assets, change body art or materials,
or establish a 10/10 visual verdict.

The actual creator showed repeated diagonal cheek marks and a small V-like
chin notch with shadows disabled. A matched native render reproduced the
chin mark. Pixel-to-triangle probing located an 18.4 mm incident edge in the
sparse chin patch around vertices 7839/7830/7834. The first 10 mm fit was too
local; an 18 mm neighborhood spanning the patch removed the sharp notch in
the matched crisp-light render.

`author.py` fits local quadratic surfaces to existing head neighborhoods and
uses the same linear fairing operator on Basis and every supported target.
Its smooth mask protects mouth support, the nasal core, the complete orbital
region and nonfrontal/upper skin. Object structure, topology, UVs, color
attributes, materials and skin weights remain unchanged. Native anchors and
all non-head geometry are untouched. This remains composable with a separate
skin-material/vertex-color pass.

```sh
OPENBLAS_NUM_THREADS=1 blender -b --threads 2 --python-exit-code 1 \
  --python tools/portrait_finish_v62/author.py -- \
  --source art/experiments/integrated_v62/adult_ready.blend \
  --output art/experiments/portrait_finish_v62/adult_b.blend \
  --report evidence/portrait_finish_v62/author_b.json \
  --radius .018 --iterations 6
```

Frozen source B SHA256:
`f818081b2a0da0f51f938f093ac2950bcab63d397242707422b214113c1b5ee3`.
Maximum neutral displacement is 1.68 mm; the measured chin-notch vertices
receive approximately 0.2–0.3 mm local corrections. The existing broad
identity fields remain recognizable rather than being replaced with a new
common face.

Matched evidence:

- `evidence/portrait_finish_v62/baseline_three_quarter.png`
- `evidence/portrait_finish_v62/candidate_b_three_quarter.png`
- `evidence/portrait_finish_v62/pixel_surfaces.json`
- `evidence/portrait_finish_v62/verify_b.json`

The focused check verifies 433 protected non-head objects, 7,708 exact
protected head vertices, unchanged contact/anchor data and twelve head-surface
states, including the six actual generated profiles. It reports zero flipped
or collapsed triangles. Native B is visibly cleaner; actual Godot comparison
across the same six faces remains the integration acceptance gate.

`render.py --profiles evidence/portrait_v62/integrated_generated_profiles.json
--profile-index 5` can reproduce a generated face with the same diagnostic
camera and lighting. Render-only scene filtering and lights are not saved
into the candidate source.

## Runtime follow-up

The integrated B runtime comparison did retain a small under-chin mark,
including on the neutral hero. `diagnose_export.py` now decodes the actual
GLB position and normal targets and compares their additive result against
angle-weighted normals recomputed from the posed triangle mesh. Coincident
UV/color seam duplicates are merged for this smooth head. Run it with
`python3 -P` because the neighboring Blender inspection helper is named
`inspect.py`.

`evidence/portrait_finish_v62/export_normals_b.json` shows that the affected
304-vertex chin region is not suffering a large additive-normal mismatch:
neutral maximum 0.0051 degrees; generated profile 05 median 0.030 degrees and
maximum 0.75 degrees. This rules out that particular explanation for the
mark, not every renderer difference. The original native camera was +25
degrees, opposite the runtime profile's view; side and illumination must
also be matched before accepting a follow-up geometry repair.

The new optional `author.py --region chin` restricts a further fit to the
under-chin transition. The default lower-face behavior and frozen B remain
unchanged. A new candidate still requires matched visual inspection and
source preservation verification before integration.

## Checkpoint — user requested wrap-up

No further chin candidate has been authored. The optional chin-only code is
prepared but **not visually accepted or promoted**. Production assets and
runtime scripts were not changed by this follow-up. No face-art native job
is live; the last process inventory shows only the pre-existing GUI Blender
PID 1953.

The exact-camera native render (session **22557**) was terminated with exit
**143** before saving an image. It was not relaunched. In particular,
`evidence/portrait_finish_v62/combined_b_profile05_runtime_camera.png`
**does not exist** and must not be cited as evidence.

The successfully saved `combined_b_profile05.png` uses the old +25-degree
diagnostic camera. It shows smoother native cheeks/chin, but is not a
matched runtime-side verdict. Actual runtime evidence inspected was:

- `evidence/portrait_v62/character62_fair_b_hero.png`
- `evidence/portrait_v62/character62_fair_b_00_front.png`
- `evidence/portrait_v62/character62_fair_b_05_three_quarter.png`
- `evidence/portrait_v62/character62_generated_05_three_quarter.png`

Those images show accepted cheek improvement but a remaining under-chin
mark. The normal diagnostic also found no other skinned Skin/Body/Tee/Casual
mesh overlapping that chin region. It does not prove the absence of every
possible runtime artifact; the measured normal differences simply do not
explain the mark.

Read-only integrated source used for this investigation:
`art/experiments/skin_surface_v62/adult_fair_surface_b.blend`, verified SHA256
`6447b13ae4080253fbd68e2c1e0b99e869123e7cb8e984123c5e82388e17c507`.
Actual measured GLB:
`art/experiments/skin_surface_v62/models_fair_b/character.glb`, verified SHA256
`3629de835cef45343f520c9be070896ad2520164e74b98235fd2512674756738`.

For future continuation, the measured creator profile05 camera uses actor
yaw +0.68 radians (38.961 degrees), perspective vertical FOV32, camera
origin Godot `(0, 1.589439869, 1.108649969)`, looking at
`(0, 1.534439921, .008650001)`: 2.862 degrees downward. The helper now accepts
`--focus-world`, `--perspective-distance`, `--fov`, `--elevation`,
`--resolution`, `--samples` and `--studio-yaw` to reproduce the geometry view
and source studio light directions. Blender energy values are diagnostic,
not claimed Godot illumination parity. First obtain that matched frame,
then consider the bounded chin-only fit and repeat preservation checks.
