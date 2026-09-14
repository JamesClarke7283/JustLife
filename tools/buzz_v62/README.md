# Buzz close-crop candidate, iteration 62

Candidate-only native work; no production Blender/GLB, game script, or runtime
changes are made by these tools. No copied textures or outside pixels are used.

## Source and scope

The inspected adult source is
`art/experiments/integrated_v62/adult_ready.blend`, SHA-256
`7869cf347f68d868e89bc8b8cfd29e8f3227a5cb0c623afa5e68bdcaa29a354a`.
The prior Buzz was a shortened Crop cap with a 7 mm Solidify modifier. Its
evaluated crown stood 21.08 mm above the head. The replacement follows the
actual evaluated scalp, with a maximum crown rise of 3.25 mm and an invisible
margin behind the alpha density boundary. The actual opaque skin under it
remains independently recolorable; the texture contains no skin color.

`author.py` replaces only the original `Hair_Buzz` descendants, preserving the
root attachment. It verifies exact fingerprints for all 433 non-Buzz objects.
The new cap contains 2,612 vertices / 5,042 faces, no shell modifier, and four
scalp-coupled identity keys: `Face_Round`, `Jaw_Strong`, `Eye_Spacing`, and
`Face_Length`. Actor discovery already recognizes these keys. Buzz has no
additional runtime root expansion, unlike Bob.

Candidate A is `art/experiments/buzz_v62/candidate_a.blend`, SHA-256
`121b6cd0066205c297614f6724b5c359bc85d59d4ae3f38c82ceff3373159cd0`.
Its nine neutral/extreme/mixed morph cases have zero penetrating vertices
(0.1 mm numerical tolerance), minimum positive signed clearance 0.111 mm, and
maximum scalp-coupling error 0.12 micrometres. The report is
`art/experiments/buzz_v62/candidate_a_verify.json`.

## Material refinement

Matched native A evidence is in
`art/experiments/buzz_v62/render_a/{baseline,candidate}`. The silhouette is much
closer to a genuine cropped cut, but A's harmonic grain has an unwanted woven
micro-pattern in the temple fade. `restyle.py` refines material/maps only and
requires exact fingerprints for every scene object, including the Buzz mesh,
UVs, material assignment name, and all keys. It writes B into a distinct
`art/experiments/buzz_v62/refined` directory, preserving A's external images.

The current `surface.py` uses 110,000 seeded randomly scattered short follicle
strokes, variable length/width/direction, and rank-based coverage. The UV seam
wraps periodically, while follicles have no regular placement grid. The front
transition and temple-point length also receive small density-only changes.
Shader maps remain original packed 2,048 × 1,024 PNG images.

B is `art/experiments/buzz_v62/refined/candidate_b.blend`, SHA-256
`ea1c0e53c4ef2ed6f4da3932401fae3b07953b48e9a392cebb758761f9334ec7`.
The material-only restyle exited successfully and preserved all 434 object
fingerprints. Matched B front/three-quarter frames in `refined/render_b` were
opened and inspected after a clean render exit. B removes the woven fade
pattern and softens the pointed temple; fine grain is subtle at the 480 px
denoised evidence scale. No GLB export or runtime acceptance is implied.

The current `author.py` can compose the revised style directly onto a later
adult native source using that source's measured scalp and supplied SHA. Its
new patch selection may differ from A/B near the invisible material margin
because the optical hairline was softened. Run `verify.py` on that newly
authored composition; do not transfer A's clearance report to changed geometry.

## Runtime review contract

The new material is `Hair_Buzz_Surface`, recolor role `Hair`. The root actor
needs this exact material name added to its existing hair recolor mapping
before runtime evaluation. Image alpha feeds a Math Round node, recognized by
the installed Blender glTF exporter as `MASK` with cutoff 0.5. The tone image
is multiplied by the hair base-color factor using the portable Mix node.

Native clearance and renders are not proof of Godot import, mip behavior,
anti-aliasing, or recolor. Those must be reviewed after an accepted candidate
export. Never run Godot CLI inspection in the live project: its MCP autoload
can replace the root agent's runtime registry. Use an isolated project with
autoloads removed and separate XDG data for any command-line import test.

`render.py` makes read-only evidence using the shared native Bob studio with
the exact `Hair_Buzz` and `Outfit_Tee` groups selected. Its ancestry filter
retains eyebrow objects; no source file is saved by rendering.

## Frozen fair-surface B integration

Root requested composition onto
`art/experiments/skin_surface_v62/adult_fair_surface_b.blend`, SHA-256
`6447b13ae4080253fbd68e2c1e0b99e869123e7cb8e984123c5e82388e17c507`.
All outputs are isolated under `art/experiments/buzz_v62/integrated_fair_b`:

- `ready.blend`: `01ade04129a1a9056eeb1c83afe2e838abe433e45c088699b3fa026144d5dd81`
- `models/character.glb`: `4f610bde352ad06d1dcf5c4a10bcc5829e042032d7472fa1ca7137e11c6ca5ff`
- `author_report.json`, `clearance.json`, `neutralize.json`,
  `native_preservation.json`, `export_preservation.json`, `export_receipt.json`.

The current optical boundary selects a 2,604-vertex / 5,028-face patch; this is
not assumed equivalent to the earlier 2,612-vertex patch. All nine actual
composition cases were rerun and passed: no penetrations, minimum signed
clearance +0.111 mm, maximum scalp-coupling error 0.12 micrometres. Fresh-open
native comparison proves all 433 non-Buzz objects and 25 non-Buzz materials
exact, including five vertex-color layers, all custom properties, eleven
identity controls, mouth metadata, shader nodes/links and packed image bytes.
Neutralization only reset the new cap Basis value; root scale is (1,1,1).

The actual GLB was compared to root's exact fair-B export, SHA-256
`3629de835cef45343f520c9be070896ad2520164e74b98235fd2512674756738`:
403 non-Buzz meshes and 2,018 decoded accessors are byte-exact, including all
five `COLOR_0` surfaces. Non-Buzz materials, node transforms, extras and skin
data are exact. The actual Buzz material exports as MASK, cutoff 0.5, with a
recolorable base factor, packed stubble/normal/roughness textures and four
neutral scalp morphs.

Receipts: author session 25780 exit 0; clearance session 21255 exit 0;
neutralize + fresh-open preservation + export session 69114 exit 0; binary
GLB comparison session 8634 exit 0. An earlier pre-save checker call failed
on a Blender StringProperty API difference; it wrote no candidate. The
guard was corrected and native invocations now include `--python-exit-code 1`.
The source-inspection script is named `inspect_source.py` to avoid shadowing
Python's standard `inspect` module during standalone verification.

Root owns actual Godot import/recolor/AA review. No production asset or live
Godot state was written by this composition/export sequence.
