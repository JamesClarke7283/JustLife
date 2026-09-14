# Portrait revision 62

This revision develops original character face artwork in editable Blender
candidates. The initial iris/brow repair preserves topology; the later orbital
pass deliberately replaces the head's eye topology while preserving hierarchy,
rig, contact landmarks and every pre-existing morph name. Nothing in this tool
directory promotes assets to production automatically.

Two measurable defects motivated the work:

- Revision 61 resized iris, limbal ring and pupil `Mesh.vertices` but left their
  `Basis` and other shape keys unchanged. The evaluated/exported visible shape
  therefore retained the large iris. Source mesh/Basis differences reached
  5.95 mm.
- Both adult eyebrow ribbons were completely behind the forehead surface:
  729 out of 729 vertices per eyebrow, at depths of 0.54–1.51 mm.

`author.py` reconstructs circular iris outlines against the real sclera BVH
for every existing eye morph, rather than moving flat discs independently.
The adult iris has a 18.95 mm diameter, a 20.6 mm limbal outline and an 8.34 mm
pupil. A small catchlight follows the same surface. Eyebrow ribbons are fitted
0.4–1 mm above each corresponding head morph. All changed raw mesh vertices
are synchronized exactly with `Basis` before saving.

The tool scales from each family's actual eye and eyebrow dimensions, so it
can run on adult, child, teen and elder sources. It always requires a separate
candidate output path. It can also compose on top of an independently revised
hair source because its only geometry ownership is ten eye/brow objects.

```sh
blender -b --threads 2 --python tools/portrait_v62/author.py -- \
  --source art/characters.blend \
  --output art/experiments/portrait_v62/characters.blend \
  --report evidence/portrait_v62/adult_author.json

blender -b --threads 1 --python tools/portrait_v62/verify_native.py -- \
  --baseline art/characters.blend \
  --candidate art/experiments/portrait_v62/characters.blend \
  --report evidence/portrait_v62/adult_verify.json
```

Export each variant in a fresh Blender process with
`tools/portrait_v62/export_variant.py` using the new candidate's SHA-256. That
exporter preserves the existing broad and live-detail variant conventions.
The adult candidate GLB was checked to retain all nine global morph names:
Blink, Eye_Spacing, Face_Round, Hand_Grip_L, Hand_Grip_R, Jaw_Strong, Nose_Wide,
Sit and Smile.

Visual acceptance belongs to the actual Godot creator and life cameras;
Blender macros are useful diagnostic evidence but are not a quality score.

## Identity and orbital stages

`identity.py` adds signed `Nose_Length`, `Lip_Fullness`, `Brow_Arch` and
`Chin_Length`, neutral0 and range[-1,1], to all five age families. Infant
amplitudes are deliberately smaller. `verify_identity.py` checks neutral and
existing-key preservation and13 signed endpoint/combination cases per family.
The missing infant native source was reconstructed with its exact released
generator and validated against the decoded released GLB: identical indexed
triangle connectivity/material/scene metadata, maximum vertex difference
5.77 micrometres. See `verify_baby_restoration.py` and its evidence receipt;
this is not a claim of byte-identical export.

`socket.py --weld --relaxed-blink` is the reviewed later pipeline:

- Each eye layer shares one rigid identity translation. This removes inherited
  globe shear and mismatched iris/lid contact under combined sliders.
- Sclera/iris assemblies are seated deeper, scaled from measured globe width.
- `socket_weld.py` clips the inherited frontal head socket and stitches the new
  almond aperture into the actual shared head boundary. There is no separate
  overlaid skin collar, no duplicated seam, and no flat-shaded face normals.
- The paired64-point aperture closes exactly. A fitted curved surface derived
  from surrounding skin avoids the pointed canthus wedges of the first trial.
- Two fine upper-lash ribbons have explicit UVs. The welded head has projected
  face UVs. Brows alone receive a separate `Brows` copy of their material so
  runtime can tint them independently of pale hairstyles.

The stable adult8-control handoff is
`art/experiments/portrait_v62/characters_orbit_c.blend`, SHA256
`867f478c8ab49b6218778b3189e987a1877b878a71de2b9b8b31ce87d57a35d9`.
Its preview lives separately in `orbit_c_models/character.glb`. Root composes
the three additional proportion keys and accepted Bob on separate sources.
The normalized native replacement is `characters_orbit_d.blend`, SHA256
`e976fb9aa1b918cf1b1c70cd4746764bcb54eba38656faf012286ec907bcafa2`.
It clears four accidentally active newly created keys. Evaluated comparison
in neutral export pose covers431 mesh/curve objects and reports exactly0.0m
maximum world-vertex change between c/d; its source head scale is preserved.

`verify_socket.py` checks fullBlink skin coverage, closed seam continuity,
manifold shared socket boundaries, and globe occlusion outside the opening at
neutral and halfBlink with old/new identity extrema. `verify_orbit_scope.py`
checks exact unrelated-object/rig preservation, scoped material changes, raw
mesh/Basis parity, zero morph values, smooth faces and nonempty UVs.
`--extended-identity` adds all eight mixed-sign new3 corners in four old
identity contexts, checking open/half/full Blink against actual apertures.

`finalize_native.py` saves a separate native output, zeroes morph values and
matches the released export convention by clearing pose-bone Euler rotations
only. It preserves and checks authored bone location/scale and all object
transforms; it never resets a full pose matrix. Its before/after data digest
guards mesh, morph, topology, UV, weight and material assignments.
`verify_neutral_equivalence.py` additionally compares evaluated world-space
vertices at neutral export pose, so raw-data equality cannot conceal altered
skeletal proportions.

Infants have a different lens-style eye construction. Their iris fitting uses
thin separated surfaces to avoid UV-sphere front/back z-fighting, reduced
vertical sclera extent, a taller age-appropriate aperture, and a shallower
depth offset. Never substitute adult aperture ratios without visual review.

No numerical geometry test establishes10/10 visual quality. Actual Godot
front/three-quarter/open/closed images and independent criticism remain the
acceptance gates; all intermediate failed candidates remain diagnostic only.
