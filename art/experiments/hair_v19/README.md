# Unpromoted Bob and Curls study

This is hair revision 19, study revision 14, based on the reviewed production-v18 characters. Adult and child editable candidates are maintained here. **It is an unpromoted six-image directional checkpoint.** Independent review records the remaining art issues in [iteration 12](../../../docs/REVIEWS/iteration_12_hair.md). Read `REVIEW.md` for the diagnosis, exact images and remaining artistic concerns; `source_manifest.json` records current provenance.

The Bob retains its asymmetric silhouette with regular surface topology and an inward/upward inner edge. The front/left Curls region studies separate tapered overlapping locks over a close-fitting undercoat; the rear retains r13 relief as a control. The shared recolorable hair material keeps its original colors with a more restrained highlight response. Non-hair geometry, morphs and skin weights are preserved exactly.

Build each editable candidate and excluded GLB from the repository root:

```sh
blender --background -t 4 --python-exit-code 1 --python art/experiments/hair_v19/create_hair_v19.py -- --age adult --skip-render --export
blender --background -t 4 --python-exit-code 1 --python art/experiments/hair_v19/create_hair_v19.py -- --age child --skip-render --export
```

The canonical six-image checkpoint uses:

```sh
blender --background -t 4 --python-exit-code 1 --python art/experiments/hair_v19/render_hair_review.py -- --age child --styles bob --views left right
blender --background -t 4 --python-exit-code 1 --python art/experiments/hair_v19/render_hair_review.py -- --age adult --styles curls --views front creator
blender --background -t 4 --python-exit-code 1 --python art/experiments/hair_v19/render_hair_review.py -- --age child --styles curls --views left
blender --background -t 4 --python-exit-code 1 --python art/experiments/hair_v19/render_hair_review.py -- --age adult --styles bob --views creator
```

The renderer records separate reports for each selected style/view set, preserving provenance across these bounded calls. The studio setup matches r13; a creator filename describes full-body camera distance, not the actual Godot creator.

`python art/experiments/hair_v19/verify_hair_assets.py` performs a fresh private Godot import and compares both candidates with production. The current run passed 2,120 checks, preserving 105 adult and 121 child non-hair meshes. Builds require all source inputs to match `art/source/character_v18_production_hashes.json` and reuse the accepted age functions in `tools/create_characters.py` without executing that generator.

Current rendered PNGs, detailed reports and `evidence/` are ignored local output. The exact r13 source/manifest/export archive remains in `evidence/r13_before_r14/`. No teen/elder expansion, extreme-morph gallery, recolor review, production LOD or in-game action coverage has been performed for r14. Further work should follow the independent critique of this six-image checkpoint.
