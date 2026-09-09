# Adult garment revision 22

This directory preserves the exact accepted v18 adult Blender input and records the original adult clothing revision built from it. The four adult model files use garment revision 22; rig_version18 and surface_revision2 remain unchanged because the rig/contact contract is preserved. Child, teen, and elder files remain the accepted v18 assets recorded in `../character_v18_production_hashes.json`. That historical manifest is not rewritten.

`characters_v18.blend` is immutable input, SHA-256 `bab2d4e1a261a6b12cbf4c913e59a62f05890b06ab5b54cadee07d545588a81f`. Current editable output belongs at `art/characters.blend`. The input must never be replaced with the current output.

## Reproduction

Run a fresh Blender process from the project root with an empty output directory:

```sh
blender --background --factory-startup -t 6 --python-exit-code 2 \
  --python tools/sculpt_clothing.py -- \
  --source art/source/clothing_v22/characters_v18.blend \
  --output-root /absolute/empty-output
```

The qualified environment is Blender 5.2.1 LTS, build `9e2066aef7ef`, glTF exporter 5.2.40. Same-environment reproduction matched the four qualified GLBs byte for byte. Cross-version byte reproduction is not claimed. The driver requires the pinned source, refuses a nonempty output or an output containing the source, and writes only the adult editable Blend, four adult GLBs and audit sidecars. Its owned helpers live beside the driver; the export worker is launched as a separate Blender process for each model.

The qualified workflow authors the source with six Blender threads, then exports each width/detail variant in a fresh single-thread (`-t 1`) Blender process with a neutral pose and evaluated dependency graph. Fresh scene reopen and fresh multithreaded processes alone both showed intermittent crop-lock tessellation differences; those failed outputs are retained locally. A single-thread authoring attempt instead reordered complete trouser vertex/triangle tuples without changing their attributes or geometry. The documented six-thread authoring/single-thread export boundary reproduced all four final model files byte for byte and exact editable-source object facts.

There is no mesh-payload transplant or hair-source edit. The verifier checks complete decoded output values/schema and non-layout metadata against the qualified revision and refuses drift, retaining raw output for diagnosis. This is a same-environment qualification, not a claim of deterministic output on every Blender build. Do not weaken the pins to accept an unreviewed export.

## Authored scope and preservation

The casual Henley gains shaped shoulders, sleeve/armhole transitions and a relaxed hem. Shared trousers use a single continuous waist/crotch/leg mesh; the original two pocket trims are reprojected onto it, skinned and given the same Sit corrective. Therefore the trouser change also affects Jacket and Cardigan outfits. The original CardiganBody lower rear hem is eased locally to cover the fuller trousers during the qualified oven/seated bends: at most 28 mm rearward, 17 mm lower, and 10 mm outward at each rear-side corner. The cardigan front, sleeves and binding, and the entire Jacket upper garment remain unchanged. Detailed hem topology, UVs and weights are exact; its existing LOD reducer changes garment-only rows without increasing its triangle count.

Skin, hair, face, bone transforms, joint weights/grip morphs of protected meshes, appearance controls and broad X width 1.12 are preserved exactly. New trouser weights and Sit displacement are barycentrically transferred from the accepted source after final topology. Blender/glTF filtering of weights at or below 0.0001 and float32 morph rounding are recorded in the independent transfer audit. A stricter global-nearest-surface diagnostic retains its small residual failures; the declared Blender-source transfer and actual exported arithmetic were verified separately. No body-data tolerance was introduced.

The current casual/Crop visible mesh budget is 162,024 triangles detailed and 102,694 in Live, versus 142,920 and 83,430 previously. The increase is 19,104 detailed /19,264 Live, including newly skinned pocket detail. A lower-subdivision LOD is deferred; this revision keeps the pose-qualified geometry.
