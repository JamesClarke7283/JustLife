# Adult Crop source26 with identity clearance

This original adult hairstyle keeps the accepted asymmetric front sweep, contours the cap around the ears and nape, and uses feathered crown/side flow whose borders blend into the shared cap. The final local clearance stage gives the combined-maximum head identity room beneath the lower cap. Only14 Crop meshes change from the accepted face-v23 source: the cap and two sideburns have coordinate edits; six Crown and five Part_fan meshes rebuild topology and SurfaceUV. Every front sweep mesh, face/morph, garment, rig and shared material remains protected. Teen, child and elder assets are unchanged.

Reproduce with ordinary Python and Blender5.2.1 LTS, build9e2066aef7ef, into a fresh empty output directory:

```sh
python tools/crop_v26/generate.py --output-root /absolute/new/output
```

The default immutable input is `art/source/crop_v26/characters_face_v23.blend`, exact accepted face-v23 source SHAe8e9d64944d4640659fad856a42cb46858a3a59b8a6e5db84cbd31d2cc6ce3fd. The driver writes `seed/`, `feathered/` and `final/` native stages and audit sidecars. Each stage starts in a fresh t6 Blender process. Only the final stage exports, with each of four adult variants in a separate fresh t1 process. The output artwork is under `final/art/` and `final/assets/models/`. No private path, previous failed output, historical generator or binary repair is required.

Each stage checks the pinned input byte hash or exact recorded native signature before editing and the expected source signature after editing. The final cap envelope changes316 vertices horizontally in its last four rows, preserving every vertex height, original modifiers, topology and UV. It samples the actual combined-maximum identity at the idle/friendly expression values against detailed and production-ratio .12 LOD cap surfaces. This corrects the previously visible behind-ear scalp intrusion. The sampled positive clearance supports the correction; actual rendered identity and acting checks remain necessary when changing this geometry.

The complete pipeline reproduced all four final GLBs byte-for-byte. Freshly saved .blend containers differ from the exact qualified editable source, while fresh read-only checks verify the recorded object/geometry/UV/rig/morph/material facts of each native stage. `manifest.json` records both container hashes and the final production hashes. This is same-environment source-value reproduction, not a cross-version guarantee or a claim about every Blender RNA field.

`verify_exports.py` compares the full artwork change to accepted exports; `verify_clearance_exports.py` protects every mesh except the cap for the final local stage. Both compare exact decoded accessors by named mesh and semantic consumer. Eight detailed flow meshes share one identical index accessor, eliminating seven numeric table entries. Protected sharing and every protected decoded value remain exact. Rebuilt topology/UV allowances are limited to the11 flow meshes; cap/sideburn derived geometry has a separate scope. The clearance-only detailed cap keeps exact UVs and indices; LOD cap vertex/UV count changes2173→2159 while index count10782 is retained. No float or triangle-order tolerance is used.

The rejected pre-clearance source passed default views but failed the combined-maximum head endpoint. Its proofs and unsuccessful positional/JSON comparison attempts remain preserved privately and summarized in the manifest. The corrected26-frame review accepted this as an incremental improvement, with modest rear/temple flare and lower-edge LOD shading ripples remaining. The bounded Crop score is7.5/10; this does not imply the whole game reached10/10. Keep the extreme-envelope coverage when refining those limits.

Blender logs retain the installed cattrs addon-registration traceback and normal exporter notices. These did not prevent the explicitly successful author/export and source verification processes. Large private screenshots and diagnostic logs are excluded from the source tree.
