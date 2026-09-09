# Child Bob grouping and lower-band taper

This bounded original-art stage replaces repeated rounded side locks with connected broad flow and an inward-curved bob hem. It preserves the swept fringe. Only positions on the 25 named meshes in `native_contract.json` may change: `Hair_Bob_Cap`, 12 `Hair_Bob_Lock` meshes and their 12 dependent `Hair_Bob_Strand` details. The details remain editable but are embedded behind the continuous cap; the visible shallow flow is sculpted into that cap. There is no material or shader substitution.

All 337 other native child objects, face/anatomy, rig, shirt and other garments, five Bob fringe meshes, other hair families, shared materials, transforms and metadata remain exact. Native topology, UVs, shape keys and weights are protected even on the owned meshes. The existing unused `Hair_shadow` fake-user flag stays true as inherited from the accepted shirt stage; this stage adds no maintenance exception. Adult, teen, elder and historical child grip variants are outside its scope.

## Reproduction

Use ordinary Python and Blender 5.2.1 LTS build `9e2066aef7ef`. The extractor reads five immutable local Git objects from commit `b5134505ebd76ce3dbfca256f741d24489ca8263`, checking all content hashes. It does not fetch or modify tracked files and has no ignored private-archive dependency. A shallow checkout needs those objects available locally, or equivalent separately archived files with exactly the pinned hashes.

```sh
python tools/child_bob_v36/extract_inputs.py --repository . --output /absolute/new/bob-inputs
python tools/child_bob_v36/generate.py --source /absolute/new/bob-inputs/art/characters_child.blend --baseline-models /absolute/new/bob-inputs/assets/models --output /absolute/new/bob-output
```

The output must be new and cannot contain an input. Separate single-thread Blender processes reopen the baseline, author the connected Bob directly from that baseline, reopen the grouped source, apply the cap-only lower-band taper, and reopen the final source. This pipeline deliberately bypasses the rejected first concept. Exact native signatures guard each accepted stage. The taper changes precisely 383 cap vertices below Z1.05, preserving the upper cap and every other object relative to the grouped stage.

The final editable source opens the populated `Scene` with all 362 objects and the original `Character_Portrait` camera. Its authored-data signature must match the reviewed source; its `.blend` container bytes may differ because of save provenance. The recorded witness covers object geometry/UVs/weights, modifiers, rig, morphs, materials and scene usability; it is not a promise about every Blender RNA field or cross-version serialization.

All four final variants are exported in fresh separate single-thread Blender processes. Raw export bytes and final GLB bytes must each equal the frozen targets. Three finals are direct Blender exports. Standard LOD uses the guarded transfer described below. Final output paths are `art/characters_child.blend` and `assets/models/character_child{,_broad,_lod,_broad_lod}.glb`. Logs, intermediate native sources, raw exports and protection receipts are retained. The driver never promotes outputs.

The installed Blender environment emits a `cattrs` addon-registration traceback despite successful author/export processes. Logs remain available; process results, exact signatures and exact exports establish the reproduction boundary. No claim of clean Blender logs is made.

## Export protection and storage identity

A fresh raw standard child LOD export reproduces unrelated `Hair_Crop_Swept_lock.004` TEXCOORD_0 drift. This raw failure is retained. `transfer_bob.py` copies only the 25 freshly Blender-authored Bob primitives into the original accepted standard LOD. It checks the node/material links and rigid attachment, preserves every protected payload and protected-only sharing group, and then repacks storage. It never repairs UVs, rounds floats or normalizes triangles. The other variants need no transfer.

Each final is compared by named decoded mesh consumer values: all 314 protected mesh records and root/material/rig data remain exact; all 25 owned records exactly match their raw Blender source. Native polygons/UVs stay exact, while Blender-derived triangulation, LOD interpolation and accessor sharing may change only within this declared mesh ownership. Splitting a mixed owned/protected alias is permitted to retain the original protected data. Protected-only sharing remains exact. Numeric accessor IDs are storage addresses, so they are not used as semantic mesh identity. Removed/added alias groups and per-mesh UV/index differences are recorded explicitly.

Historical `tools/create_characters.py` and `tools/child_shirt_v31/generate.py` reproduce earlier child art. Use this bounded pipeline for the Bob source after this stage is accepted.

## Standalone guarded transfer

The pipeline imports `transfer()` directly. For an independent standard-LOD transfer, the standalone command reads the shipped `native_contract.json` schema (`scope.owned_meshes`) and verifies the accepted/raw input hashes for the standard-LOD variant:

```sh
python tools/child_bob_v36/transfer_bob.py --accepted /absolute/bob-inputs/assets/models/character_child_lod.glb --authored /absolute/bob-output/raw_exports/character_child_lod.glb --output /absolute/new/check/character_child_lod.glb --report /absolute/new/check/transfer.json
```

`--contract` can select another copy of the same distributed contract; `--ownership` remains an argument alias and also requires that contract schema. This command supports the standard-LOD transfer; the other three pipeline variants use direct Blender exports. Both destination files must be new, distinct from each other and distinct from every input, including the contract. Input hashes and path collisions are checked before creating output directories. The final output must match its qualified contract hash. The callable transfer implementation used by the reproduced pipeline is unchanged by this standalone argument correction.

## Reviewed visual scope and limitations

Four neutral standard full-detail pairs plus 16 broader matched pairs cover supported standard narrow/short and broad wide/tall endpoints, combined maximum identity, front and opposing ear/nape obliques in full/LOD, and four ordinary friendly head/face motion samples. Creator LOD is an explicit inspection override. Live uses production-selected LOD and supported public camera controls, with approximately 35-pixel unobstructed heads. Live frames establish ordinary-distance appearance, not detailed all-angle clearance, completed conversations, XP or simulation progression. Finite native head/ear-envelope checks are not an exhaustive all-pose solid-intersection guarantee.

The grouped result remains stylized, with a smooth heavy rear and real dark angular LOD hem pinches, strongest in the close left-rear inspections. Their cause has not been established. Independent review accepts this incremental improvement with those residuals; it does not claim they are absent from every Live angle or raise an overall game score.

Both broader Godot strict receipts remain failed for the shared verbose startup RGB8 conversion warning, despite 139 capture assertions and six audio-drain checks passing per side. Earlier rejected ear slits, closed patches, heavy first concepts, the unidentified original two-ObjectDB leak failure, and raw LOD UV failure remain documented in review 36. No warning is suppressed or relabeled clean.
