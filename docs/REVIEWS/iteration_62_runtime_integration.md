# Iteration 62 — runtime integration checkpoint

14 September 2026. This is a working-art checkpoint, not release acceptance.
Production native sources and exported age families have not been replaced by
these previews. Screenshots below are retained in `evidence/portrait_v62/`.

## Directional bob surface

Actual Godot preview input:
`art/experiments/bob_v62/strands_ready_models/character.glb`, SHA-256
`4514503798e4329d2b4e82f3ecf925b008d5b755b7165b7c968b9ed68bb68756`.
The temporary runtime slot was `assets/models/character_rig.glb`. `Hair_Bob`
is hairstyle **1**; hairstyle 5 is `Hair_Buzz`.

Viewed `character62_bob_surface_front.png`, `three_quarter.png`, `back.png`,
`blonde.png`, `red.png` and `grey.png` (all share the first filename prefix).
The actual actor-local Bob material received the requested hex values
`ccb178`, `ad5636`, and `c9c7be`; the maps remain present when recolouring.
Rendering used native 3D resolution, MSAA 4X, and the new studio lights.

The independent hair-only review is `iteration_62_bob_surface_critic.md`:
**7/10**, versus the preceding 6.5. The back now has directional flow, but
larger clump hierarchy, tapered tips and less regular striping still need work.
The first diagnostic captures named `character62_textured_bob_*` selected
Buzz by mistake and are **not** evidence for this Bob review. The maintained
render probe now resolves both hairstyles by name and checks visible roots.

## Joined eye sockets

Actual Godot preview input:
`art/experiments/portrait_v62/welded_models/character.glb`, SHA-256
`940a9b102738e127b1c37512ff368415fb9ac11d23ee7b7b8c1ea4c92801e511`.
This snapshot has eight identity controls and the original hair, not the
later eleven-control/Bob composition.

Viewed `character62_welded_eye_front.png`, `three_quarter.png`, `macro.png`,
`blink.png`, and `maximum_blink.png` (shared first filename prefix).
`_update_expression(0, "sleep", 1)` closed the actual imported morphs without
body animation. Maximum here means the four legacy identity controls at 1,
not every later control. Eyes no longer look like white capsules attached in
front of the skin; full Blink did not expose white globe gaps in these views.

Closed corners still pinch. `character62_welded_blink_unshadowed.png` repeats
the maximum case with only the key's shadows disabled. The wedges persist,
so shadow-map tuning is not the fix. The face author is revising the closed
surface separately; native zero-leakage checks do not prove visual smoothness.

This import also produced `UVs are required to generate tangents` errors.
The author located missing UVs on the new lash ribbons. The private creator
test run `/tmp/justlife-character-quality-dtyhi8wh` correctly failed its import
gate despite Godot exiting 0. Do not report its UI tests as passed: they never
ran. A corrected source needs a fresh clean import before this gate can pass.

## Creator and remaining gates

The earlier private creator run `/tmp/justlife-character-quality-dvnm2c5d`
passed 70 checks with an exact source-match receipt. It covered grouped
controls, signed domains, hidden-group reset, studio render settings and their
restoration on leaving. Subsequent changes tighten the Face camera from 1.37 m
to 1.10 m (age-scaled) and add a dedicated brow-material recolour path. These
new changes passed syntax checks, but need the next clean private test run
and final-family visual verification. The framing pilot is
`character62_face_framing_candidate.png`.

The separate eleven-control welded composition passed 70 native cases and
51,264 closed-globe samples (`evidence/identity_shape_v62/verify_welded_a.json`),
but those results do not cover the later closed-corner surface revision.

Still required: combine the accepted geometry/material passes; review the
same-style six-face lineup again; verify every age, frame and LOD; inspect
expressions, contact animation and styling ranges; refine the other hair and
wardrobe defects; run the creator-to-home path on actual production exports;
and obtain an independent final quality review. Current evidence does not
support a 10/10 character or finished-game claim.

## Follow-up: corrected orbital surface

`characters_orbit_c.blend` (SHA-256
`867f478c8ab49b6218778b3189e987a1877b878a71de2b9b8b31ce87d57a35d9`)
and `orbit_c_models/character.glb` (SHA-256
`0c5c37c94be3f2a7eaf43dc481dfa7931991c0224b7ebd0ab6e979e4fecd9b44`)
correct the closed patch and add usable lash UVs and a separate Brows material.
Actual Godot captures `character62_orbit_c_blink.png` and
`character62_orbit_c_open.png` show smooth closure without the earlier corner
wedges. Grey hair retains slightly darker brows. The editor error query was
empty after import and playtest. These remain eight-control, original-hair
previews, not a review of the final combined character.

Fresh private run `/tmp/justlife-character-quality-gwuppwfa` passed its clean
import and **82 creator checks**, with `tested_source_matches_current: true`.
This supersedes the earlier pending creator-test statement, not the separate
production-family/animation gates. The new checks also verify that changing
face proportions does not shift the closer camera. A front Bun framing pilot
is retained as `character62_face_framing_bun.png`.

The eleven-control composition on corrected c passed the full **70 native
cases**, recorded in `evidence/portrait_v62/integrated_identity_verify.json`.
The original reviewed Bob surface is being assembled on that source. Extended
open/half/full-Blink checks, final export and new controlled portraits remain
required for the assembled result.

## Eleven-control integrated runtime and generated household

The combined adult source `art/experiments/integrated_v62/adult_ready.blend`
has SHA-256 `7869cf347f68d868e89bc8b8cfd29e8f3227a5cb0c623afa5e68bdcaa29a354a`.
Its exported `models/character.glb` has SHA-256
`a256a78ed2a0075e7e73de91c1f033d3baeac647d40c57c8e66b4305f107fdb0`.
The export receipt confirms eleven measured mouth offsets, neutral morph
weights and one skin. The extended socket run completed successfully on this
exact source: `evidence/portrait_v62/integrated_socket_verify.json` covers 36
identity contexts at open, half and full Blink, with no tested globe exposure.

The actual creator loaded this model in the ignored rig-preview slot. Runtime
queries resolved all eleven feature keys. `character62_integrated_first.png`
shows the neutral Bob portrait. `character62_generated_00_front.png` through
`05_front.png`, with matching `three_quarter` views, show six profiles created
by the real Surprise-me/Add-Lifelet methods. Original profiles and the fixed
comparison styling are retained in `integrated_generated_profiles.json`.
All six comparisons use Buzz5, the same frame/build/height, complexion, eye
colour and shirt, isolating facial geometry from styling.

Fresh independent review: `iteration_62_integrated_generated_critic.md` gives
**6.5/10 character art, 6/10 individuality and 8/10 creator presentation**.
This is an improvement, not release acceptance. The critic viewed all thirteen
portraits and identified repeated cheek/chin pinches, insufficient eye/profile
variety, the thick-cap Buzz and inflated shirt joins as outstanding defects.

Surface diagnostics on the frozen fifth profile show Blink0, Smile0 and an
identity head rotation. Disabling the key's shadows does not remove the dents;
raising the head LOD bias to128 produces the identical screenshot. Native head
inspection finds all polygons smooth, no sharp edges, no custom normals and no
normal map in the runtime skin material. The head surface itself therefore
needs investigation, not an unsupported shadow-map or texture workaround.
Separate cheek/chin, Buzz and shirt art candidates are being developed. A
portable original vertex-colour material pass is also candidate-only pending
export and real-runtime visual review. Production families remain unchanged.

## Recolourable surface integration and cheek/chin repair

Original surface candidate `art/experiments/skin_surface_v62/adult_surface_a.blend`
has SHA-256 `3281f8997aa5650fbe624cf593b56c3975ee1d66e13d7ac9f3b1a03d4053a800`;
its GLB is `models_a/character.glb`, SHA-256
`fde8763313abd9c095601fde162471eefdab39ad42766a130c0361f3058eb342`.
The original vertex paint adds restrained complexion zones, iris pigment
variation and off-white sclerae. It uses no external imagery. The binary export
comparison confirms **2,017 unchanged geometry/morph accessors**, unchanged
transforms/contacts/skin and unchanged unowned materials. Five meshes carry the
expected nonuniform `COLOR_0` arrays (`evidence/skin_surface_v62/export_a.json`).

Actual Godot inspection found that the imported materials left
`vertex_color_use_as_albedo` false despite retaining every colour. The actor now
explicitly enables the three authored surface roles and keeps their colors
linear. The initially captured `skin_surface_a`, `enabled` and `reloaded` images
did **not** yet use vertex colors: reloading the running script retained its old
source. A fresh playtest confirmed the new source and true activation flags.
The valid viewed captures are `character62_skin_surface_active.png`,
`character62_skin_surface_fair.png` and `character62_skin_surface_deep.png`.
This material pass retains the preceding geometry and its outstanding dents.

First private actor run `/tmp/justlife-character-quality-qmelat1v` reported
122 failures: 120 came from incorrectly testing dynamically attached utensil/
book materials as imported character materials, and two assumed Blender's
`.001` names survived Godot's name sanitization. The test now scopes material
ownership to the imported scene and checks both eyes by their material role,
including full colour-array coverage. The rejected receipt is retained.
Fresh isolated run `/tmp/justlife-character-quality-z5eqtsc2` passes **1,993
adult-candidate integration checks plus82 creator checks**, with exact current
source hashes. It covers actor-local recolouring, eleven controls and mouth
landmarks, pose/contact logic and creator render-state restoration. It is not
the separate production/all-family release gate.

The cheek/chin repair source `art/experiments/portrait_finish_v62/adult_b.blend`
has SHA-256 `f818081b2a0da0f51f938f093ac2950bcab63d397242707422b214113c1b5ee3`.
Matched native renders remove the sharp under-chin notch and soften the cheek
dents. Twelve checked cases retain valid triangles, all433 non-head objects,
7,708 protected head vertices, orbital targets and mouth contacts unchanged.
The material pass has been composed on that source as
`art/experiments/skin_surface_v62/adult_fair_surface_b.blend`, SHA-256
`6447b13ae4080253fbd68e2c1e0b99e869123e7cb8e984123c5e82388e17c507`.
Its actual exported GLB is `skin_surface_v62/models_fair_b/character.glb`,
SHA-256 `3629de835cef45343f520c9be070896ad2520164e74b98235fd2512674756738`.
The eleven-contact export check passed (`evidence/skin_surface_v62/identity_fair_b.json`).
A full editor filesystem scan imported this exact input; targeted file updates
alone had left the older packed scene cached. A fresh playtest produced
`character62_fair_b_hero.png` and the twelve same-profile `fair_b_00` through
`05` front/three-quarter captures. These reuse the original six generated
profiles and fixed styling, not a more flattering rerandomized household.

`iteration_62_fair_b_critic.md` rates the new stills **7/10 character art,
6/10 individuality and 8/10 presentation**. Its reviewer did not author the
fairing/material pass, but did author three earlier identity keys; that
limitation is explicitly disclosed and final identity acceptance still needs
an uninvolved review. The cheek cleanup is retained provisionally. A smaller
central/diagonal chin wedge remains, including in the neutral hero. Neither
native smoothness nor the earlier material-only tests establish combined
acceptance. Direct GLB normal inspection finds neutral chin errors below
0.006 degrees and generated05 below0.75 degrees against the deformed surface,
so another unverified normal-map workaround is not justified.

The revised close-crop is being composed onto this exact source. The actor now
recognizes `Hair_Buzz_Surface` as recolourable hair; corresponding import,
cutout-density and actor-local recolour assertions are added. These new checks
have syntax validation only until the composed candidate is imported and run.
The separate coupled `Eye_Tilt` prototype in `tools/eye_shape_v62/` preserves
the neutral model and adds corrective products for old targets/Blink. It is
not yet a validated, visible creator control or a claim of solved individuality.

## Wrap-up requested by the user

The combined face/material/Buzz source is
`art/experiments/buzz_v62/integrated_fair_b/ready.blend`, SHA-256
`01ade04129a1a9056eeb1c83afe2e838abe433e45c088699b3fa026144d5dd81`.
Its `models/character.glb` is SHA-256
`4f610bde352ad06d1dcf5c4a10bcc5829e042032d7472fa1ca7137e11c6ca5ff`.
Nine native scalp-clearance cases passed; 433 non-Buzz objects and25 materials
are exact, as are403 exported non-Buzz meshes and2,018 decoded accessors.
The five vertex-painted surfaces and eleven mouth-contact metadata entries
remain intact. These are candidate assets, not promoted production families.

The actual creator imported this model in the ignored `character_rig.glb`
review slot. Six full-resolution captures are retained in `evidence/buzz_v62/`:
`character62_buzz_integrated_front.png`, `three_quarter`, `blonde`, `red`,
`grey` and `back` (shared prefix). Root viewed front/three-quarter/blonde/back.
The exact selected hair colour and alpha-scissor material were read back from
the live actor. The raised cap rim is gone; fine grain and the cutout hairline
still need refinement. This is not a new whole-character critic score.

Private run `/tmp/justlife-character-quality-zy0sdk98` passed **2,001 adult
candidate actor checks and82 creator checks**, zero failures and a source-hash
match at completion. The receipt is copied into
`evidence/buzz_v62/quality_results.json`. The clean private import had no errors.
The live editor's first two short-lived refresh clients disconnected; the
existing connector's filesystem refresh eventually imported the new scene.
Three duplicate `reimport` task messages appeared during that live scan; the
fresh playtest had no subsequent editor errors. No editor restart or cache
file replacement was used to claim a successful import.

The eye-tilt native prototype authored successfully, preserving434 old object
states. Source: `art/experiments/eye_shape_v62/tilt_a.blend`, SHA-256
`761f547aab0458423d649da30ff886bb64cbc5c3745812c2aecf26cbb6ed1016`.
Its author receipt is `evidence/eye_shape_v62/author_a.json`. The ninety-case
orbital verifier and four-frame render helper compile but **have not run**;
the prototype is not exported, runtime-wired or promoted. Work stopped at
the user's wrap-up request rather than beginning another native experiment.

Garment C is also unaccepted: three of five checked poses are clean, with a
localized walking triangle turnover and raised-arm skin exposure remaining.
The exact-camera chin diagnostic was terminated before saving a frame; no
new chin candidate or matching visual proof is claimed. The corresponding
art-tool READMEs retain the findings and reproduction paths.

The root's final review playtest was stopped cleanly. Existing GUI Godot and
Blender were left open, and no background art/test jobs remained at wrap-up.
Current character art is not10/10, individuality is not solved, and the
production/all-age/LOD/full-game acceptance gates remain incomplete.
