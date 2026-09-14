# Native proportion identity candidate

Candidate-only authoring for `Face_Length`, `Mouth_Width`, and `Nose_Bridge`.
These are relative shape keys, neutral `0`, signed range `[-1, 1]`. No shipped
asset or Godot script is modified by these tools.

`common.py` derives all field positions from the actual world-space sclera,
nostril geometry, validated closed mouth-seam ring, and head bounds. The adult
central seam ring is discovered as vertices 384–391, not assumed for infants.

- `Face_Length` changes the lower-face vertical distance below the eye plane
  by 12%. It fades before the orbital region, behind the anterior face, and
  toward the measured neck join. The nose, lips, ear details and jewelry use
  exactly the same field as their supporting skin.
- `Mouth_Width` changes lip width by 24%, with a broad, smooth cheek support
  region. It is not a separate detached scaling of the lips.
- `Nose_Bridge` changes the bridge profile by 9% of measured inter-pupillary
  distance. Its longitudinal field is zero at the measured nostril center and
  above the eye plane; its lateral field fades before the inner sclera.

The amplitude factors for adult/elder, teen, child and infant are respectively
1, 0.85, 0.65 and 0.35. The same script can be applied to all five frozen native
age sources. Adult acceptance comes first; an untested age is not claimed valid.

## Mouth animation metadata

`Character.mouth_anchor` remains exactly unchanged. The new dictionary custom
property `Character.mouth_identity_offsets` contains each of the eleven
lowercase morph keys, including all eight prior controls. Each value is the
actual target-minus-Basis mean of the central seam ring, transformed into
**Godot Head-local `(x, z, -y)`** coordinates. Runtime mouth effect/animation
anchors can add `sum(weight * offset)` to the existing neutral anchor.

The coordinates are deliberately not rounded to authoring landmarks. Head
local scale differs from Blender world scale, so these are not interchangeable.
Unknown or absent shape keys contribute an exact zero offset. Existing morphs
and the Basis remain untouched.

## Author and verify

```sh
blender -b --threads 2 --python tools/identity_shape_v62/author.py -- \
  --source art/experiments/portrait_v62/characters_identity.blend \
  --output art/experiments/identity_shape_v62/characters_shape_c.blend \
  --report evidence/identity_shape_v62/author_c.json

blender -b --threads 2 --python tools/identity_shape_v62/verify.py -- \
  --baseline art/experiments/portrait_v62/characters_identity.blend \
  --candidate art/experiments/identity_shape_v62/characters_shape_c.blend \
  --report evidence/identity_shape_v62/verify_c.json
```

Authoring refuses to overwrite an existing candidate. Verification checks all
objects, neutral vertices, topology, UVs, material assignments, rig, skin
weights, hair and old shape-key geometry/settings for exact preservation. It
also checks the three new controls against the shared field on every affected
skin/detail vertex, validates all eleven mouth offsets, and tests six signed
endpoints plus all eight new-control corners against five old-pose contexts
(46 cases total). Every affected mesh is checked for triangle orientation and
collapse. Brows are compared with their old-pose skin depth; actual upper/lower
lip contact pairs and near-head lip rim samples are measured for separation.
JSON failure receipts are retained. These tests are geometry gates, not a
visual-quality score.

## Same-camera visual evidence

```sh
blender -b --threads 2 --python tools/identity_shape_v62/render.py -- \
  --source art/experiments/identity_shape_v62/characters_shape_c.blend \
  --output evidence/identity_shape_v62/neutral_front.png

blender -b --threads 2 --python tools/identity_shape_v62/render.py -- \
  --source art/experiments/identity_shape_v62/characters_shape_c.blend \
  --output evidence/identity_shape_v62/long_wide_bridge.png --angle 30 \
  --values Face_Length=1,Mouth_Width=1,Nose_Bridge=1
```

All images use the same lighting, framing and material configuration, with
hairstyle geometry hidden so facial changes cannot be confused with restyling.
The render script never saves the modified scene. After native checks pass,
use the existing hash-pinned `tools/portrait_v62/export_variant.py` to export a
fresh adult preview directory. Exported glTF extras must retain the metadata.

## Welded eye composition

The author also accepts the final eight-control welded socket source. It
recognizes the head's `orbit_inner_0/1` and `orbit_shared_0/1` native index
properties. The existing measured fields are exactly zero at the actual inner
aperture; authoring now asserts that fact before making any change. The outer
collar remains part of the continuous head and receives the same smooth field
as adjacent facial skin. No entire-head or object-name freeze is used.
These aperture indices describe native Blender topology only: glTF export can
split or reorder vertices, so they must not be interpreted as Godot vertex IDs.

```sh
blender -b --threads 2 --python tools/identity_shape_v62/author.py -- \
  --source art/experiments/portrait_v62/characters_socket_welded.blend \
  --output art/experiments/identity_shape_v62/characters_welded_shape_a.blend \
  --report evidence/identity_shape_v62/author_welded_a.json

blender -b --threads 2 --python tools/identity_shape_v62/verify.py -- \
  --baseline art/experiments/portrait_v62/characters_socket_welded.blend \
  --candidate art/experiments/identity_shape_v62/characters_welded_shape_a.blend \
  --report evidence/identity_shape_v62/verify_welded_a.json
```

Welded verification adds the eight new-control corners against each prior
identity extreme with full Blink (70 cases total). Every case asserts that
the actual aperture vertices are unchanged by the new controls. Full-Blink
cases also check paired inner-ring closure and cast a 41×25 ray grid at each
globe to detect any exposed sclera. Native target arrays are composed in
float64 for fast, vectorized orientation checks; all preservation checks
still compare exact stored native float32 geometry. These checking operations
never save or mutate the scene. Run only one heavy job at a time on the shared
machine, coordinating with the eye and age-family hair authoring work.
