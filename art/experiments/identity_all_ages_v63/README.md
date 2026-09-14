# Eleven face controls on every age family, iteration 63

Editable sources produced by this pass. They are the inputs that were promoted
to `art/characters_child.blend`, `art/characters_teen.blend` and
`art/characters_elder.blend`. The adult family is not here: it comes from
`art/experiments/buzz_v62/integrated_fair_b/ready.blend`.

Each `*_full.blend` carries all eleven identity controls. The `*_identity.json`
and `*_shape.json` receipts record the measured anchors (eye plane, nostril
centres, mouth seam ring and half-width, head floor) and every affected
vertex count and displacement.

| File | SHA-256 of `*_full.blend` |
| --- | --- |
| `child_full.blend` | `24ae97623b170b322967180894a4607a96c024e63a37fb6e87404ef24122b845` |
| `teen_full.blend` | `707230c79687ab8ad5b927253bf1d97f93020e448163ac5b94545d1863aac4aa` |
| `elder_full.blend` | `ed6275dfa6f1f9d2427211d0b7b215370e74c3591985cb6ec711fe62ef6f55cd` |
| `baby_full.blend` | `ddc542b7ab365ac5b55058340150be98cfae4b2eafa6ff9275be8f634cca987b` |

## Reproduce a family

The two stages are sequential and each refuses to overwrite an existing output.

```sh
# 1. The four signed lower-face controls, at that family's measured amplitude.
blender -b --threads 2 --python tools/portrait_v62/identity.py -- \
  --source art/characters_child.blend \
  --output /tmp/child_identity.blend --report /tmp/child_identity.json

# 2. The three proportion controls from the same family's measured geometry.
blender -b --threads 2 --python tools/identity_shape_v62/author.py -- \
  --source /tmp/child_identity.blend \
  --output /tmp/child_full.blend --report /tmp/child_shape.json

# 3. Export the four variants with the released family conventions.
SHA=$(sha256sum /tmp/child_full.blend | cut -d' ' -f1)
for v in character_child character_child_broad character_child_lod character_child_broad_lod; do
  blender -b --threads 2 --python tools/portrait_v62/export_variant.py -- \
    --source /tmp/child_full.blend --source-sha256 "$SHA" \
    --output-root /tmp/child_export --variant "$v"
done
```

`child`/`teen`/`elder` amplitude scales are 0.8656, 0.9188 and 0.9984 for the
first stage and 0.65, 0.85 and 1.0 for the second; the tools read both from the
family's own geometry rather than from a constant.

## The baby

The released infant source is not in the repository. Reconstruct it first, then
run the same two stages (the tools apply the infant amplitude of 0.35 and the
infant's own seam ring and anchors), then repair UVs, then export
`character_baby{,_broad,_lod,_broad_lod}`:

```sh
blender -b --threads 2 --python tools/portrait_v62/restore_baby_source.py -- \
  --output /tmp/baby_source

blender -b --threads 2 --python tools/portrait_v62/identity.py -- \
  --source /tmp/baby_source/characters_baby.blend \
  --output /tmp/baby_identity.blend --report /tmp/baby_identity.json

blender -b --threads 2 --python tools/identity_shape_v62/author.py -- \
  --source /tmp/baby_identity.blend \
  --output /tmp/baby_full.blend --report /tmp/baby_shape.json

blender -b --threads 2 --python tools/ensure_candidate_uvs.py -- \
  --source /tmp/baby_full.blend \
  --output /tmp/baby_uv.blend --report /tmp/baby_uv.json
```

## Two defects this work exposed, and their fixes

1. **`Face_Length` collapsed to nothing on the infant.** The field fades toward
   the neck between `head_lowest_world_z` and `mouth.z - face_height * 0.45`.
   For the infant those invert, and the negative-width band zeroed the field at
   every vertex, so the author skipped the key. `tools/identity_shape_v62/common.py`
   now treats an empty or inverted band as a step, and clamps the neck band to
   `max(upper, head_low)`. Re-authoring child, teen and elder after the fix
   reproduced their files **byte for byte**, so no accepted family was disturbed.
2. **The infant brows shipped without UVs.** The released baby generator calls
   its own `ensure_uvs()`; a candidate authored through this chain does not, and
   Godot's importer then reported *"UVs are required to generate tangents"* and
   the character runner's import gate failed the whole run.
   `tools/ensure_candidate_uvs.py` applies the generator's own projection rule to
   meshes that have no UV layer and leaves every existing UV untouched.

The verification that these sources satisfy the runtime contract is
`python3 tests/run_character_quality.py --render probe_character62` — 5,178
checks, 0 failures. See [the iteration 63 review](../../docs/REVIEWS/iteration_63_identity_controls.md).
