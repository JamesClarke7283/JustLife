# Bob surface revision 62 — experimental authoring pass

The source Bob consists of a scalp cap, five thick fringe tubes, twelve free
locks and twelve decorative curves. The visible flat lock roots and repeated
pointed ends made the near side read as separate hanging rods in the actual
Godot creator capture `character62_no_shadows.png`.

`author.py` replaces only the descendants of `Hair_Bob` with an original
continuous bob shell and three unequal, shallow surface sweeps. The cut has a
high side part, a longer left face frame, a tucked right side and a graduated
nape. The surface channels remain shallow and continuous from the crown.
The upper front hairline is seated against the current head geometry using a
BVH raycast, so the front rim cannot float away from the forehead like a hood.

The first experimental `characters.blend` is rejected: its radial interpolation
produced a temple shoulder and excessive forehead clearance. `revised.blend`
uses a continuous-slope radial profile and the scalp-contact correction.

The original author uses an adult design coordinate frame, transforms it into
the existing `Hair_Bob` local space, and preserves that group's head attachment
and source material. Without `--fit-family` it retains the reviewed legacy
adult fit. The optional measured family fitting pipeline is described below.

```sh
blender -b --threads 2 --python tools/bob_v62/author.py -- \
  --input art/characters.blend \
  --output art/experiments/bob_v62/revised.blend \
  --report art/experiments/bob_v62/revised_report.json

blender -b --threads 2 --python tools/bob_v62/render.py -- \
  --source art/experiments/bob_v62/revised.blend \
  --output art/experiments/bob_v62/render_revised \
  --views front,three_quarter,back
```

The report certifies that 430 objects outside the old Bob descendants are
unchanged, checking transforms, parenting, visibility, geometry, materials,
UVs, skin weights and shape keys. The four newly authored meshes retain a
`SurfaceUV` layer and use the existing `Hair` material. Each has a closed inward
shell, including the hairline and lower cut. Render tools never save a source.

No production Blender source or GLB is replaced by this workflow. After visual
approval, the parent task must combine the authoring pass with the face source,
export the normal/broad/LOD variants and validate actual Godot behavior. The
node and primitive counts intentionally change, so old byte pins are not a
valid substitute for this review.

## Combined adult handoff

`art/experiments/bob_v62/combined.blend` applies the same author to the stable
`portrait_v62/characters_identity.blend` eight-control face candidate. Its full
adult runtime export is `combined_models/character.glb` within this experiment.
The candidate deliberately predates the next eyelid pass.

`verify_export.py` compares resolved triangle attributes and morphs against the
identity-only GLB, independent of accessor offsets and changed node indices.
The checked handoff preserves **426 nodes, 400 primitives, 108 morph targets,
all their materials and the skeleton exactly** outside the Bob subtree; see
`art/experiments/bob_v62/export_preservation.json`. The native source report
separately preserves all 430 non-Bob scene objects.

```sh
python3 tools/bob_v62/verify_export.py \
  --before art/experiments/portrait_v62/identity_models/character.glb \
  --after art/experiments/bob_v62/combined_models/character.glb \
  --report art/experiments/bob_v62/export_preservation.json
```

Matched front and three-quarter evidence is in `render_before/` and
`render_revised/`. An independent visual check favored this shell's continuous
roots and asymmetrical silhouette; broad material highlights and relatively
parallel secondary ridges still need real-game critique before further detail.

## Directional strand surface

The next reviewed candidate is `art/experiments/bob_v62/strands_ready.blend`,
with its full adult GLB in `strands_ready_models/character.glb`. `surface.py`
adds original uneven curved strand groups, finer grain, less than 0.5 mm of
physical relief, a varying roughness map and restrained specular response.
The entire hem/hairline boundary and crown pole stay byte-identical. A corrected
UV wrap and shared scalp UVs keep the cap and three sweeps visually coherent.

All three 2048 × 1024 maps are generated from periodic mathematical fields
inside Blender and packed in the source. No outside image pixels are used.
The tone map is grayscale so the player's hair color remains independent.
Only the new `Hair_Bob_Surface` material uses these maps; the original `Hair`
material and every other style remain exact. The runtime recolor mapping must
treat `Hair_Bob_Surface` like `Hair` (root has added that mapping).

```sh
blender -b --threads 2 --python tools/bob_v62/surface.py -- \
  --input art/experiments/bob_v62/combined.blend \
  --output art/experiments/bob_v62/strands_ready.blend \
  --report art/experiments/bob_v62/strands_ready_report.json
```

For a later face source, first run `author.py`, then `surface.py`. Do not apply
`surface.py` repeatedly to the same finished Bob; it fails before mutation to
prevent accumulated relief. A material left unused by `author.py` can be
replaced safely without changing any other object or material assignment.

`finalize_surface.py` migrated the first reviewed surface experiment from the
legacy MixRGB node to the equivalent current Mix Color node. The latter lets
Blender export the original default color factor correctly; fresh `surface.py`
runs already use it. Texture samplers clamp at the crown and cut ends. Native
review frames are `render_strands/front.png` and `render_strands/back.png`.

The GLB carries standard embedded albedo, normal and metallic-roughness images.
`inspect_import.gd` checks actual Godot import, including the generated tangent
arrays, enabled normal maps and roughness textures on all four Bob surfaces:

```sh
python3 tools/bob_v62/run_import_inspection.py \
  art/experiments/bob_v62/strands_ready_models/character.glb
```

The wrapper creates a private minimal project without application autoloads or
MCP addons, and uses separate XDG data/config/cache directories. Do not launch
the probe directly inside the live project: headless Godot still loads the
MCP autoload and can replace the live runtime registry.

## Measured age-family fitting

`inspect_families.py` measured the actual `Head`/`Hair_Bob` transforms, old cut
bounds and evaluated skull cross-sections in all five stable identity sources.
The adult skull has a live 0.91 deformation beyond its stored vertex positions;
teen, child and elder are already baked. The baby has a separate wider/shorter
skull and a differently named original Bob cap. A global height scale would be
incorrect for these sources.

`author.py --fit-family` uses `fit.py` to adapt independent X/Y/Z proportions
from three evaluated skull cross-sections and attachment-to-crown height.
It also measures the forward skull offset (important for the elder), seats the
front rim against the actual scalp, and clears the rest of the inner shell.
Surface-normal-aware clearance avoids underestimating thickness at a sloping
forehead. Thickness and physical strand relief follow measured head size. The
continuous hem and UV strand flow are retained. The new fitted adult is a
separate, tighter candidate; it does not silently replace the reviewed adult.

```sh
blender -b --threads 2 --python tools/bob_v62/fit_families.py -- \
  --source-root art/experiments/portrait_v62 \
  --output art/experiments/bob_v62/family_fit_runtime

blender -b --threads 2 --python tools/bob_v62/verify_fits.py -- \
  --root art/experiments/bob_v62/family_fit_runtime \
  --report art/experiments/bob_v62/family_fit_runtime/runtime_morph_clearance.json

blender -b --threads 2 --python tools/bob_v62/render_families.py -- \
  --root art/experiments/bob_v62/family_fit_runtime
```

Each family folder contains `bob_fit.blend`, `bob_surface.blend`, protected
object/rig/shape-key reports, clearance measurements and original packed maps.
The author/surface fingerprints also include bone rest and pose transforms.
`verify_fits.py` checks both sides of the evaluated closed shell at neutral,
round-face, strong-jaw and combined extremes, reproducing the game's existing
Bob X expansion `1 + 0.04 * Face_Round + 0.03 * Jaw_Strong`. The fitted envelope
uses the inverse of that expansion for each case, avoiding double oversizing.
Both tools assert that this contract still matches `scripts/actor.gd`.
The verifier writes its report before failing on any penetration over 0.1 mm.
Render tools are evidence-only and do not save changes to native sources.

The first `family_fit/` candidates were neutral-only diagnostics; their runtime
morph report showed residual temple clipping, so they are not release-ready.
Current corrected candidates are under `family_fit_runtime/` instead.

The corrected five-family run passed all 20 runtime-matched cap checks with
zero penetrating vertices (0.1 mm tolerance) and a closed two-manifold shell
in every case. Minimum signed inner-shell clearance across the four cases:

| Family | Minimum clearance | Protected non-Bob objects |
| --- | ---: | ---: |
| Adult | 1.695 mm | 430 |
| Teen | 1.573 mm | 430 |
| Child | 1.454 mm | 430 |
| Elder | 1.687 mm | 438 |
| Baby | 1.401 mm | 81 |

See `family_fit_runtime/runtime_morph_clearance.json` plus each family's native
author/surface report. This is a fit qualification, not an overall visual
quality score or production approval. No fitted-family GLBs were exported.
Matched 480 px three-quarter views are saved in each adult/child/elder/baby
`renders/` folder. Inspection found continuous roots and cuts, a correctly
forward-positioned elder fit and a separately fitted short/wide baby skull.
These snapshots retain the older identity faces and original outfit visibility;
they are not evidence for the later integrated face/garment work. The original
critic's broad-clump/thick-cut art concerns remain for a later Bob polish pass.
The first family render set also hid `Hair_Brow` through an overly broad
render-only prefix filter. That filter now isolates explicit hairstyle roots,
preserving brows in future portraits; neither native source nor fit QA changed.

To compose with a newer face candidate, run `author.py --fit-family` on that
source, then `surface.py`, then verify and visually inspect again. The fitting
tool changes only new Bob descendants; the `Hair_Bob` root itself is never
scaled or renamed. Parent/source changes require renewed visual and Godot
review, not automatic promotion.

For a single composed source, the same read-only verifier accepts `--source
path/to/candidate.blend --report path/to/report.json` instead of `--root`.
