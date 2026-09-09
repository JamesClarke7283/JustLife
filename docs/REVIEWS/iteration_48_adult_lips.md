# Iteration 48 — fuller adult lips

The adult mouth had thin lip surfaces that read as an outline from the front.
The revised original artwork gives both lip surfaces more height, tapers them
back into the existing corners and refits their depth to the supporting head.
The gain is modest but visible in neutral and smiling front and three-quarter
views. It applies to both adult frames and their live-game detail models;
young adults share these assets.

Only `Lips_Upper_soft`, `Lips_Lower_soft` and `Lips_Smile_seam` change. The head,
chin, upper face, mouth width, corner positions and contact landmark remain
fixed. A common vertical map expands the lips around the actual joined-rim
curve, with scale 1.45 centrally and a smooth taper to 1 at the corners. Central
upper and lower heights become approximately 6.319 and 7.907 mm. Depth uses the
old lip field at original coordinates and the supporting head Basis at the new
height. Both shell sheets receive the same coordinate mapping.

The seam sections shrink to 24% of their previous height and depth while all
97 native-local ring means remain exact. Float32 transformed world means are
recorded separately; their small rounding differences are not corrected by
moving extra vertices. The center ring and Head-local Godot mouth anchor
`[0, .054, .118866]` remain fixed. Independent mesh and shape-key coordinates
receive the same displacement, with zero relative-key and mesh/Basis rounding
rows in this candidate. The existing shared Smile field remains exact when
reevaluated at the old and new vertices.

## Source

The reviewed editable source is `art/characters.blend`, SHA-256
`2a181222579a14efebf1cbe4bc99ea7719cbe3d53152e7127192c9f7b1820933`.
The [portable source guide](../../tools/adult_lip_volume/README.md) starts from
the accepted chin/support source at commit
`fc58f69af1aea13ab4b501af7b4ee452464e1fcb`, or its identical standalone Blend.
It reuses the existing native/export and Smile helpers.

The first relocated run stopped after authoring because native container bytes
differed, although all three authored geometry/object reports were exact. A
fresh read-only reopen also matched all 362 objects and recorded materials.
Decoded comparison found only two mesh library-reference filepath fields
changed by an added parent-directory segment. All other decoded bytes remained
exact. The original failed run remains retained. The revised generator
records the native byte comparison separately, requires all three report hashes
and the fresh native/material contract, passes the observed source hash to each
export, and protects that source against later changes. Runtime GLB hashes stay
strict.

The fresh revised six-process run completed with exit code zero throughout.
All three authored reports and all four GLBs reproduced byte for byte. The
reopened native source matched all 362 object records and recorded materials;
its container hash matched the same diagnosed relocation above, with byte
equality to the original source explicitly false. Inputs and shared helpers
remained unchanged. Each process used six private data/config/cache/temp roots
with `HOME` unchanged.

## Qualification

Three disjoint Creator captures contain 8, 4 and 18 views, completing the same
30-view matrix used for the preceding accepted face. They pass **817/0**,
**417/0** and **1,827/0** respectively; repeated setup accounts for the differing
check totals. Every complete sample record equals its corresponding accepted
baseline record, including controls, pose, morphs, camera, lighting and clock.
The matrix covers both frames, default and combined maximum identities,
neutral, half/full blink, Smile, both profiles and three-quarter views.

Six paired Live views pass **615/0** with the production-selected detail and
same home fixture. The full report bytes equal the preceding accepted Live
report. Actual screenshots show appearance at ordinary viewing distance.
The household is paused while friendly animation and natural blink are stepped;
this does not establish a completed conversation or gameplay activity.

A fresh native reopen matches **362 object records**, the usable scene and all
recorded material values. The four-variant decoded comparison passes
**1,656/0**, with **336 unrelated meshes** exact per variant. Head, materials,
rig, anchor, hierarchy, accessor schema and sharing stay exact. Only the three
owned meshes change. The lips' derived export triangulation changes at unchanged
counts; native polygon/loop chains remain exact. No new sparse-count or other
exception is needed.

The maintained snack/grip check passes **60/0**, and the fork check using the
actual authored anchor passes **40/0** across all four models. Its 1,392 fixed
samples and complete report are byte-identical to the accepted preceding
contact result: fork-to-mouth cycle minima are about 10.004–10.005 mm and food
return minima 2.475–2.476 mm, within the existing 25 and 45 mm bounds. These are
sampled cycle minima, not continuous contact or proof of a complete meal.
Godot import, capture and contact logs are clean. Blender logs retain known
addon startup, MeshOptimizer and armature export diagnostics.

## Review and limits

Independent review accepts this bounded lip increment after directly viewing
all 30 paired Creator samples and six Live pairs. The scoped face score stays
about **5.5/10**. The historical comprehensive game score remains **7.2/10**;
this art pass does not establish a new whole-game score or finish the 10/10
goal. The conspicuous convex ear pads are the next ranked form target.


The dark lower contour, small angular projecting tip and abrupt profile return
remain visible. Existing closed-lid creases, ear forms and the slightly angular
lower face also need work. The examined lip triangles have no projected flips,
collapse or greater-than-90-degree normal reversal; 39 seam projection-only
sign changes are separately retained. These diagnostics and positive sampled
shell clearances are not a complete self-intersection proof.

The earlier depth-only trial did not show a clear improvement and remains
unpromoted. Raw studies, failed attempts and screenshots stay local under
`dist/test-work`, outside production assets. This increment changes artwork
and authoring tools. The separate morning-preparation policy experiment stays
private: earlier school departure did not solve adult lateness. No packaged
release or full-game 10/10 claim is made.
