# Iteration 47 — adult chin and mouth support

The adult lower face had a receding chin and thin lip pieces projecting from a
relatively flat surface. The revised original artwork gives the chin broader
support, smooths its transition into the mouth, and fits rounded lip sections to
the actual head surface. A shared Smile field carries the head, lips and seam
together. Both adult frames and their lower-detail models use this correction;
young adults share these assets.

The neutral stage owns only `Skin_Head_continuous`, `Lips_Upper_soft`,
`Lips_Lower_soft` and `Lips_Smile_seam`. It preserves topology, materials, rig,
weights, key metadata and the protected upper face. Existing mesh/Basis offsets
and relative identity/Blink vectors receive the same quantized translation,
with 45 relative-vector and 31 mesh/Basis subtraction differences explicitly
recorded from float32 rounding, at most 7.45 and 3.73 local nanometres. The finish
stage replaces only those four Smile targets and transports the mouth contact
anchor from `[0, .054, .115128]` to `[0, .054, .118866]`.

## Source and reproduction

The reviewed editable source is `art/characters.blend`, SHA-256
`5b88ef9f415be618ce1586b49ea51a5086ddc660a460430b1752ce6e3ae2c42e`.
The [portable authoring guide](../../tools/adult_face_volume/README.md) starts
from the pinned production input at commit
`0c108161dffa361c9ebf1d812757d8389b548351`, or the same standalone Blend. It
reuses the maintained adult-eye source, native-verification and export helpers,
with separate private Blender processes and unchanged `HOME`.

Native seam ring vertices 384–391 define the anchor transport and measured Smile
guide. The guide uses the measured center and endpoint rises; its quadratic curve
approximates the intermediate seam within the shared mouth band. The source
contract pins the native object/material values and all four exported models.

The relocated generator completes all eight stages with exit code zero and
reproduces all five art files byte for byte, including the native Blend and all
four GLBs. The fresh native check also matches all 362 object records and the
material contract; input and tool hashes remain unchanged. Logs retain known
local addon startup, MeshOptimizer and armature export diagnostics, so these
successful Blender logs are not described as clean.

## Qualification

The matched current-runtime Creator matrix passes **3,027/0 per side**, with
30 views each across both adult frames, default and combined identity controls,
front/profile/three-quarter views, blink and Smile. Complete recorded controls,
camera, lighting, pose, morph weights and clocks differ only at the deliberately
changed mouth-anchor depth. Actual images establish the visible change.

The six paired Live views pass **615/0 per side** using the same fixed home and
production-selected detail. Friendly animation and natural blink are manually
stepped while the household remains paused. Recorded layout, camera, pose,
control and trace values differ only at the mouth anchor. This checks ordinary
viewing distance; it does not demonstrate a completed conversation or gameplay
activity.

A fresh native reopen verifies all **362 recorded objects**, the usable scene
and complete recorded material values. Each of the four GLBs preserves **335
unrelated mesh payloads**, with the four face meshes explicitly owned. The first
strict decoded comparison remains **1,768 checks / 12 failures**: twelve owned
head morph sparse-storage counts changed. Each new stored count was independently
shown to equal its actual nonzero decoded rows; full accessor counts and every
other schema field remain exact. A separate comparator allowing only those
twelve recorded count pairs passes **1,808/0**. It does not waive unrelated
geometry or schema changes.

The lips' derived export indices change at unchanged counts. Their native
polygon/loop chains and the pinned Blender exporter remain exact; decoded GLBs
alone do not establish native quad correspondence.

The unchanged maintained snack/grip gate passes **60/0**, and the fork gate at
the actual model anchor passes **40/0** across all four variants. It records
348 fixed samples per variant: cycle minima are approximately 10.004–10.005 mm
for fork-to-mouth distance and 2.475–2.476 mm for food return, inside the existing
25 mm and 45 mm bounds. These are cycle minima, not continuous contact or proof
of a completed meal. Godot import/contact logs are clean; Blender diagnostics
remain retained separately.

## Review and limits

Independent visual review accepts this bounded chin/support increment at about
**5.5/10 for the scoped face design**. Compared with rejected local trials, the
sharp chin shelf, under-lip dimples and diagonal cheek marks are materially
reduced. Outlined lips, a
pointed lip edge, a slightly angular underside and a faint Smile cheek crease
remain; the earlier closed-eyelid creases also remain visible. Zero projected
sign reversals across the examined lip triangles is not a complete
self-intersection proof.

Earlier face trials, failed decoded comparisons and raw evidence stay in local
`dist/test-work`; they are not production assets. This increment changes adult
artwork and its authoring tools, with no simulation policy or packaged-release
claim. The historical comprehensive game score remains **7.2/10**, and the
full-game 10/10 goal remains open.
