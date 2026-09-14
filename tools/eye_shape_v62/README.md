# Coupled eye-shape prototype

This candidate adds a signed `Eye_Tilt` control, not a finished eye redesign.
Measured orbital centres define a local ten-degree rotation. The eye layers,
lid margins and lashes move together, and the deformation fades into the face.
Neutral geometry, old shape targets, materials, paint, UVs and rig are exact.
No runtime or production family is replaced by these tools.

The initial prototype is canthal tilt only. Eye-opening and lid-contour variety
remain outstanding; stretching an iris vertically is not an acceptable shortcut
for a larger aperture.

## Corrective contract

Every existing target that intersects the orbital field receives a relative
`Corrective__Eye_Tilt__SOURCE` target when its displacement is nonzero. Its
runtime weight must be `eye_tilt * source_weight`. This includes blinking;
applying only the neutral tilt target would break the closed lid seam.
The root exports this mapping as `orbital_correctives` metadata. Negative tilt
uses the inverse affine displacement; its tiny second-order scale difference
is covered by native and visual tests, not represented as exact inverse rotation.

`author.py` requires an exact source hash and refuses an existing output.
`verify.py` compares all retained object states and checks ninety actual mixed
identity/Blink cases for affine composition, head triangle validity and globe
occlusion outside the aperture. These checks do not establish visual quality,
material import or correct live runtime application of the corrective weights.

Run both in background Blender with `--python-exit-code 1` and a single native
job at a time. Inputs use `--source`, `--source-sha256`, `--output`, `--report`;
verification uses `--baseline`, `--candidate`, `--author-report`, `--profiles`
and `--report`. Keep native diagnostic renders and actual creator screenshots
as separate evidence, and review front/three-quarter and full Blink before
considering any production promotion.

## Saved checkpoint

Authoring completed with exit0. `art/experiments/eye_shape_v62/tilt_a.blend`
has SHA-256 `761f547aab0458423d649da30ff886bb64cbc5c3745812c2aecf26cbb6ed1016`;
the434 old object-state fingerprints remain exact. The author receipt is
`evidence/eye_shape_v62/author_a.json`. Ten source targets require corrective
products, including Blink, Smile, Eye_Spacing and Face_Round.

The user asked to wrap up before native verification or rendering began.
`verify.py` and `render.py` only have Python compile checks so far; do not
describe their ninety cases or four images as completed. No runtime support,
creator slider, generated-profile field or production export is present for
this prototype. The previously tested eleven-control candidate is unchanged.
