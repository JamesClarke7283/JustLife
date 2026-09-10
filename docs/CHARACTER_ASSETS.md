# JustLife original character assets

Original geometry and artwork authored in Blender for JustLife. The exported assets contain no meshes, textures or screenshots from The Sims.

## Files and integration status

The four adult game models and their editable source include the accepted clothing, lip and Crop revisions, eye-depth and lid-attachment refinement, chin/mouth support, fuller lip surfaces and the current casual hem/trouser and shoulder-weight refinement. They retain the revision 18 rig, surface revision 2 and accepted hands. The eight teen and elder GLBs and their two editable sources remain v18. The child source and four child GLBs retain that rig and anatomy with the bounded casual-shirt, Bob grouping and lower-detail hem refinements. The repository keeps the production assets, editable sources and required generator inputs. Duplicate `*_surface_grip*`, older `*_rig*` and age `*_grip*` candidates, renders and historical `art/iterations` archives remain local and are excluded from Git:

| File | Intended use |
| --- | --- |
| `assets/models/character.glb` | Detailed standard adult frame for the creator |
| `assets/models/character_broad.glb` | Detailed adult frame with 12% broader horizontal proportions |
| `assets/models/character_lod.glb` | Standard frame for the live camera |
| `assets/models/character_broad_lod.glb` | Broad frame for the live camera |
| `art/characters.blend` | Editable current rig, garments, hair, expressions and portrait studio |
| `tools/adult_casual_drape/` | Current adult garment stage from the pinned fuller-lip source; reproduces the two native stages and all four model exports |
| `tools/adult_lip_volume/` | Accepted fuller adult lips from the pinned chin/support stage, with native/material and exact export guards |
| `tools/adult_face_volume/` | Accepted adult chin/support and Smile stage from the pinned eye source |
| `tools/adult_eyes/` | Accepted adult eye/lid authoring stage and shared native/export helpers |
| `tools/sculpt_clothing.py` | Earlier adult garment authoring from immutable v18 input; uses the adjacent trouser helper, per-variant export worker and exact output verifier |
| `tools/create_characters.py` | Historical v18 generator and unchanged teen/elder authoring pipeline |
| `tools/child_shirt_v31/` | Accepted child casual-shirt stage, retained as historical authoring and preservation tooling |
| `tools/child_bob_v36/` | Current child Bob source from the accepted shirt stage, fresh native protection, pinned input extraction and guarded Bob-only standard-LOD transfer |
| `art/characters_child.blend`, `characters_teen.blend`, `characters_elder.blend` | Editable current age variants |
| `art/source/grip_v3/` | Four immutable Blender inputs preserving accepted hand meshes and grip morphs |
| `art/source/character_production_hashes.json` | Current hashes of sixteen production GLBs and four editable character sources |
| `art/source/character_v18_production_hashes.json` | Historical v18 hashes, retained unchanged for provenance and older studies |
| `art/source/clothing_v22/` | Immutable adult v18 input, current garment manifest and reproduction instructions |
| `art/experiments/hair_v19/` | Unpromoted hair study, portable generator and editable adult/child candidates |

All sixteen paths retain the reviewed surface repair and hand grips. The historical v18 promotion followed 8,464 actual Godot scene/asset checks, 1,456 actor/contact checks, and independent static and combined creator/profile/cooking/snack/child-birthday review. Actor source `ef20e62accd5fdf8fc1c493985bdd1d8d6c2249bfd079ff5a45f4a16f9f7defb` was promoted with them. Exact historical v18 asset/source hashes are in `art/source/character_v18_production_hashes.json`; the previous twenty production files remain in the local `art/iterations/before_surface_v18_promotion` archive. The optional `rig_preview` setting selects older experimental rig paths when present and otherwise retains the standard production model.

Reproduce the adult clothing stage using the explicit six-thread authoring and fresh single-thread export command in [the garment source guide](../art/source/clothing_v22/README.md). It writes a new output directory, keeps the immutable v18 input separate, and verifies that stage's exact qualified output. Its four adult GLBs reproduced byte for byte in the documented Blender environment. The 361 recorded editable-source object facts also matched; unrelated addon/modifier notices remain in the local logs. That command predates subsequent face/hair work; use the current adult source guide below to reproduce the final models.

The older `blender --background --python tools/create_characters.py -- --surface-repair` command regenerates historical v18 adult candidates; it does **not** reproduce current adult clothing. Add `--age child`, `--age teen` or `--age elder` for the historical age pipeline; the child result predates the current shirt and Bob refinements. Its `--promote` flag replaces that stage’s four GLBs and editable source, so use it only after reviewing the intended stage replacement. Running without `--surface-repair` retains the earlier sculpt pipeline for historical comparison. This separate Blender process creates its own scene and leaves any other open Blender session untouched. All default morph values are explicitly zeroed before and after export. All exported mesh primitives have UVs, including the untextured morph meshes, for clean Godot tangent generation.

## Fuller adult lips (review iteration 48)

Both lip surfaces now have more height and taper into the existing corners, with their depth refitted to the supporting head. Only the two lip meshes and seam change. The head/chin, mouth width, corners, contact anchor, rig, topology and materials remain fixed. Neutral and smiling front and three-quarter views show a modest improvement; the dark lower contour and angular profile tip remain visible.

[The current adult source guide](../tools/adult_lip_volume/README.md) reproduces this stage from the pinned accepted chin/support Blend. A fresh six-process run reproduced all three authored reports and four GLBs exactly, and a native reopen matched all 362 object records and material values. Native container bytes differ only in two inherited library-reference path fields in the diagnosed relocation; the generator records container equality separately from its strict geometry/native/export checks. [Review 48](REVIEWS/iteration_48_adult_lips.md) records 30 matched Creator views, six paused Live pairs and full/LOD feeding checks. Independent review accepts the bounded lip improvement; the scoped face assessment remains about 5.5/10 and the full-game quality goal remains open.

## Adult chin and mouth support (review iteration 47)

The current lower face has more chin projection and a smoother transition beneath the lips. The original head, lips and seam receive the neutral shape and shared Smile field; the mouth landmark follows the measured seam center to `[0, .054, .118866]` in Head-local Godot coordinates. Existing topology, UVs, rig and unrelated character parts stay fixed. The slightly angular underside, outlined lips and faint Smile crease remain visible limitations.

[The chin/support source guide](../tools/adult_face_volume/README.md) reproduces that stage's neutral authoring, native measurement, Smile/anchor finish and four exports from the pinned eye-stage input. A fresh eight-process run reproduced all five stage files byte for byte and verified all 362 recorded native object facts and material values. Blender startup and exporter diagnostics remain in the retained logs. [Review 47](REVIEWS/iteration_47_adult_lower_face.md) records the matched Creator and paused Live views, full/LOD feeding contact, narrow decoded sparse-count changes and independent acceptance of that bounded improvement. Its saved source is the input to the current lip stage above.

## Adult eye depth and eyelid attachment (review iteration 44)

The adult eyes have less profile protrusion, a more open neutral lid margin and upper lid roots blended into the supporting head surface. Only ten eye pieces, two upper lids and the local orbital head mask change. The final pass preserves all unrelated decoded model payloads, the rig, materials, contact landmarks and other age families. Angular closed corner creases, horizontal lid bands and the lower seam remain visible limitations.

[The eye-stage source guide](../tools/adult_eyes/README.md) reproduces that stage's two sculpts and four exports from a pinned Git input into a new output directory. All four stage GLBs reproduced byte for byte; the newly saved native file had exact recorded object/material facts, while its container bytes differed. That reviewed source is the input to the current lower-face stage above. [The review](REVIEWS/iteration_44_adult_eyes.md) records matched Creator, LOD and paused Live views, controller checks and remaining limitations. These checks do not replace a full-game review or qualify arbitrary facial motion.

## Child casual-shirt shoulders (review iteration 34)

The child casual shirt has lower sleeve crowns and a gentler shoulder join. Only positions on `Outfit_Casual_Shirt` (`Top_Blouse`) change: 2,678 of 6,002 native vertices, at most 10.360 mm. All 881 vertices within 9 mm of the retained collar, placket and cuff surfaces remain exact. The other 361 native objects, anatomy/face/hair, all UVs, rig weights and metadata remain exact. A separately approved `Hair_shadow.use_fake_user` false-to-true flag keeps that unused original material through a normal editable-source save; all material contents remain unchanged.

[The portable source guide](../tools/child_shirt_v31/README.md) describes extraction of the five pinned former assets from local Git history and generation into a new directory. Four fresh single-thread exports supply the authored shirt, then guarded accessor transfer keeps every other decoded mesh exact. This is necessary because an unchanged standard child LOD export drifted in seven unrelated hair U values. Only the shirt's derived LOD tessellation changes: 1,859 to 1,848 vertices, with 2,640 triangles retained; the detailed shirt retains 7,083 vertices and 12,000 triangles. All four final GLBs reproduce byte for byte in the documented Blender environment.

The final visual gate separates 18 contextual Creator/Live/seated pairs from six isolated actual carry/stair rig inspection pairs. The isolated frames hide scene geometry after placing the held pose and dish, and establish garment visibility at those poses only. Occluded earlier camera compositions remain rejected visual evidence. The change is modest; the broad-frame sculpted join and small profile improvement remain limitations. There is no arbitrary-pose or cloth-simulation guarantee and no new family-wide or whole-game art score. [The review](REVIEWS/iteration_34_child_shirt.md) records the scoped verdict and evidence.

## Child Bob grouping and taper (review iteration 36)

The child's Bob now uses connected shallow side flow and a curved lower cut instead of six similar hanging tubes. Its swept fringe remains exact. The stage changes only positions on the cap, 12 locks and 12 dependent detail meshes; the other 337 native objects, face/anatomy, rig, shirt, other hair families and shared materials remain exact. Native polygons, UVs, weights, morph data and metadata are protected. A final cap-only pass changes 383 vertices below Z1.05 while preserving the upper cap and all other objects relative to the grouped source.

[The current child source guide](../tools/child_bob_v36/README.md) extracts five pinned accepted inputs from local Git history and reproduces the two native stages and four GLBs in a new directory. Fresh read-only native signatures protect the populated editable scene and recorded authored data. All four final GLBs match the reviewed bytes in the documented Blender environment. Native container bytes may vary with save provenance. The standard LOD uses a guarded transfer of only the 25 freshly Blender-authored Bob primitives into the accepted GLB because raw export reproduces unrelated Crop UV drift. All 314 other decoded mesh records and protected-only sharing remain exact; owned derived triangulation and alias changes are recorded explicitly.

Independent review accepts four neutral default pairs plus 16 broader pairs covering both supported body extremes, combined maximum identity, full/LOD ear/nape views and four ordinary friendly head/face samples. Creator LOD is a disclosed inspection override. Live retains production-selected LOD and supported public camera controls, with approximately 35-pixel unobstructed heads; it demonstrates ordinary-distance motion appearance only. Both broader strict Godot receipts retain the shared verbose RGB8 startup warning despite 139 capture assertions and six audio drains passing per side.

The rear remains smooth and heavy, and dark angular LOD hem pinches are visible in close rear obliques. Their cause is unproven. These are accepted limitations of this incremental change, with no arbitrary-pose guarantee or overall score uplift. [Review 36](REVIEWS/iteration_36_child_bob.md) records exact scope, reproduction and retained failures.

## Adult garment revision 22

The casual shirt has a clearer shoulder and sleeve transition. Shared trousers now use a continuous waist/crotch/leg surface, with the original pocket trim transferred and skinned to it. A local rear/rear-side cardigan hem adjustment clears the overlap found during the oven and seated review. Jacket upper geometry, all protected body/face/hair/hand geometry and the rig/contact metadata remain unchanged. New trousers and pockets retain the transferred Sit corrective.

The independent garment score is **7.5/10**, with explicit pose, cloth and hardware limits in [the review](REVIEWS/iteration_22_clothing.md). This is an adult clothing improvement; the latest full-game score remains 7.2/10. The rejected garment versions and export failures remain local evidence.

## Coordinate and animation contract

Front is **Godot +Z**, up is **+Y**, feet are at approximately zero, and adult height is about 1.76 m. Blender source is Z-up and faces -Y. The outer node is `Character`; a broad frame has outer X scale 1.12. The current adult proportion pass reduces head/hair/detail scale to 0.91 around the unchanged Head pivot, blends the continuous neck into that change, and enlarges palms/fingers with a blended wrist transition. The Head accessory empty therefore has scale 0.91; its corresponding skeleton bone keeps identity rest scale. All furniture/limb hinge positions below remain unchanged.

`LifeRig` imports as one `Skeleton3D` and one skin. Every bone has **identity global rest rotation in Godot**; procedural rotations use the same axes as the legacy pivot empties. Godot may append `_2` or another numbered suffix to bone names when resolving collisions with the corresponding empty nodes. Resolve both the exact name and numbered variants.

| Bone | Parent bone | Godot rest head position, metres |
| --- | --- | --- |
| Root | — | `(0, 0, 0)` |
| Spine | Root | `(0, 1.10, 0)` |
| Head | Spine | `(0, 1.458, -0.005)` |
| Arm_L / Arm_R | Spine | `(±0.180, 1.361, 0)` |
| Forearm_L / Forearm_R | corresponding Arm | `(±0.244, 1.087, -0.007)` |
| Leg_L / Leg_R | Root | `(±0.078, 0.922, -0.012)` |
| Shin_L / Shin_R | corresponding Leg | `(±0.087, 0.548, -0.012)` |

The existing `Head`, `Arm_L/R`, `Forearm_L/R`, `Leg_L/R` and `Shin_L/R` empty nodes remain for rigid attachments, hair, eyes, footwear and props. Apply matching rotations to both the bone and its empty. Hip height is 0.922 m; sitting lowers the actor relative to the furniture seat and bends hips and knees around their actual hinges. Grounding and furniture contact are handled by `LifeActor`.

The continuous head/neck, upper arms/forearms/hands, trousers, casual shirt and jacket are skinned surfaces with blended vertex weights. They use linear blend skinning, matching Godot. The `Sit` corrective relaxes cloth around seated hips and knees. There are no embedded animation clips: the game drives walk, idle, gesture, sit and sleep poses procedurally.

## Age variants and contact landmarks

Child, teen and elder assets use the same skeleton, hair, outfit and morph contracts, with independently placed rest landmarks and continuous anatomy changes. Their file families are `character_child.glb`, `character_child_lod.glb`, `character_child_broad.glb`, `character_child_broad_lod.glb`; replace `child` with `teen` or `elder` for the other stages. `young_adult` and `adult` use the ordinary adult paths. Regenerate the historical v18 stage candidate with `blender --background -t 8 --python tools/create_characters.py -- --surface-repair --age child` (or `teen` / `elder`). Append `--preview-only` to export all four variants and render only full-body/face portraits when a small material refinement does not need a repeated full pose sheet. Reviewed editable sources are `art/characters_child.blend`, `characters_teen.blend` and `characters_elder.blend`; new candidates use the corresponding `characters_child_surface.blend` names until promotion.

| Stage | Approximate height | Hip hinge | Knee hinge | Head pivot height | Anatomy |
| --- | --- | --- | --- | --- | --- |
| Child | 1.18 m | 0.580 m | 0.335 m | 0.925 m | Shorter limbs, larger relative head, softer and shorter lower face, straighter trunk |
| Teen | 1.55 m | 0.810 m | 0.480 m | 1.274 m | Lighter adolescent frame with its own shoulder, elbow and limb lengths |
| Elder | 1.72 m | 0.912 m | 0.545 m | 1.425 m | Mild forward shoulder/head posture, cheek/jowl and facial-fold changes, gray hair default |

These stages bake all attachment scales to one, including `Head`. Their global bone rest bases remain identity and exactly match the retained pivot positions. The adult retains its documented Head scale of 0.91. Treat the profile height slider as a relative multiplier on the selected stage, not a replacement for its authored proportions.

The exporter writes contact data as glTF `extras` on `Character`. Godot imports it as **one dictionary**, accessed with `character.get_meta("extras", {})`. Its keys include `age_stage`, `age_revision`, `height_m`, `hip_height`, `knee_height`, `head_height`, and `bone_landmarks`. `mouth_anchor` is a three-number array in Godot coordinates local to the Head pivot. `palm_anchor_l` and `palm_anchor_r` are arrays local to the matching Forearm pivots. Convert these arrays to `Vector3` and use each pivot's transform to find its world contact point. The elder also provides `default_hair_color`; this is a suggested default that remains recolorable. Elder brows use `Hair_shadow` for clearer expression. Fine facial creases reuse `Ear_detail`, with barycentrically attached Blink/Smile/identity deltas, so they follow both facial customization and skin recoloring. Read the actual exported dictionary rather than copying constants, as facial refinements can adjust mouth contact slightly.

The final child v3, teen v1 and elder v3 imports pass 6,464 direct asset checks across all twelve files: complete skeletons, identity rest rotations, coincident bone/pivot positions, default-neutral expressions, wardrobe presence, valid mesh bounds and usable contact metadata. The critic has accepted child v3 and teen v1 age proportions in a shared-scale family lineup. These checks establish the asset contract; actual actor activity contact requires the separate runtime review. The critic accepts elder v3 as a first functional elder variant, with age-read around 6.5/10; stronger broad cheek/jowl and under-eye forms remain useful later refinements. Child and teen age proportions are accepted at roughly 7.3–7.5 within the current art style. Baby, infant and toddler models are not supplied by these age variants. The former age LODs contained about 64,058, 64,055 and 64,408 visible triangles with Crop/Casual; unchanged v18 surface/grip counts are listed below. Approved source/export snapshots are retained under `art/iterations/character_child_approved`, `character_teen_approved` and `character_elder_approved`.

## Hair and wardrobe

Every variant is included in each GLB. Hide all but the selected hair and outfit after instantiation. Hide matching mesh prefixes recursively as well as container nodes, because skinned meshes can be reparented by the importer.

| Selection | Group / mesh prefix | Shape |
| --- | --- | --- |
| Hair 0 | `Hair_Crop` | Asymmetric swept crop with crown locks and subtle directional surface grooves |
| Hair 1 | `Hair_Bob` | Jaw-length layered bob with swept fringe |
| Hair 2 | `Hair_Curls` | Rounded irregular coils with sculpted ridges |
| Hair 3 | `Hair_Pony` | The Bob cap and fringe with a swept tail and band at the nape |
| Hair 4 | `Hair_Long` | The Bob with its locks lengthened and tapered toward the shoulder blades |
| Hair 5 | `Hair_Buzz` | The Crop cap alone, drawn in tight |
| Outfit 0 | `Outfit_Casual` | Short sleeve shirt, light collar/cuffs and button placket |
| Outfit 1 | `Outfit_Jacket` | Cropped bomber, long sleeves, stand collar, zipper and ribbed edges |
| Outfit 2 | `Outfit_Cardigan` | Longer open V-neck knit over a cream tee, with patch pockets |
| Outfit 3 | `Outfit_Tee` | Plain crew tee from the casual shirt body, cuffs and hem |
| Outfit 4 | `Outfit_Hoodie` | The cropped shell with a full down-hood roll behind the neck, kangaroo pocket and drawstrings |
| Bottom 0 | `Bottom_Continuous_trousers` (+ `Bottom_Cuff` curves) | Shared tailored trousers |
| Bottom 1 | `Bottom_Shorts` (+ `Bottom_Shorts_Cuff`) | The trousers cut above the knee with a folded cuff; `Skin_Leg_continuous` supplies the exposed legs |

Brows also use the `Hair_` prefix. Keep them visible when switching hairstyles. All outfits share low-top sneakers with laces, sole and side accents, and either bottom. `Skin_Leg_continuous` carries a gentle kneecap, recolors with the skin, has no morphs so the live LOD decimates it, and is shown only with shorts; under trousers the actor hides it so it costs nothing.

The second wardrobe set (hair 3–5, outfits 3–4, shorts and leg skin) is added to every age family by `blender -b --python tools/create_wardrobe.py -- --family all --export`. It derives each addition from that family's own accepted geometry, never edits existing objects, removes and rebuilds only its own additions on a rerun, and exports the sixteen game models with the same rest-pose, zeroed-morph, broad-scale and live-LOD decimation steps as `tools/export_character_variant.py`. The earlier reproduction chains reproduce the accepted stages that precede this addition; they do not regenerate the second wardrobe set.

The jacket shell, and the hoodie shell derived from it, were bound with the analytic width blend, so their shoulder caps took partial arm weight wherever they sat over the arm's silhouette and tore open when an arm rose (the stretch and the overhead reach). `blender -b --python tools/shell_shoulder_weights.py -- --family all --save` repeats the reviewed casual-shirt repair on both shells of every family: it finds the armpit seam as the highest cut under which the shell splits into two sleeves and a torso, seeds the lower sleeves as arm and the central torso and collar as body, protects shell vertices within 30 mm of fully upper-arm skin as arm, solves a harmonic field with inverse-edge-length weights across the shoulder band, and keeps the authored spine and elbow fractions. Run it before `tools/create_wardrobe.py --export`, which rebuilds the hoodie from the repaired jacket shell. `--render DIR --raise 150` writes a before/after render of the hoodie with the left arm raised for each family.

## Facial and corrective morphs

Morphs can occur on several meshes. Cache and set every mesh exposing the requested target; changing only the head will detach features. Values are in **0..1**, with neutral **0**.

| Target | Behavior |
| --- | --- |
| `Blink` | Actual upper lid closure, small lower socket motion and globe/iris retreat |
| `Smile` | Lip and mouth-corner lift, coordinated with nearby facial skin and the mouth seam |
| `Sit` | Pose-space cloth correction, intended for seated poses only |
| `Face_Round` | Fuller cheeks and a gently rounder lower face |
| `Jaw_Strong` | Broader lower jaw and more forward chin plane |
| `Nose_Wide` | Wider nose tip and alar wings, with aligned nostrils |
| `Eye_Spacing` | Modestly wider eye spacing, including lids, globes and brows |

Identity morphs share continuous displacement fields across the head and its facial details. Neutral, each individual maximum, all four maxima together, maximum plus blink, and maximum plus smile are rendered for clipping inspection. Avoid applying `Sit` during walking or bed sleep. The actor gently widens the Bob hair container with `scale.x *= 1 + 0.04 * Face_Round + 0.03 * Jaw_Strong` to retain cheek/ear clearance at combined maxima.

## Hand grips and preserved revision 17 candidates

The promoted revision 18 includes independent `Hand_Grip_L` and `Hand_Grip_R` targets to the corresponding continuous arm meshes. Values are **0..1**, with exact original neutral geometry at zero. Full grip curls all four fingers and opposes the thumb; the pose corrects the web and knuckle base without changing the wrist rest. Each arm retains its full 9,000-triangle topology in the live LOD so the hand morph remains stable, increasing the visible adult LOD count by about 14,000 triangles.

Generate an adult candidate with `blender --background -t 8 --python tools/create_characters.py -- --grip --preview-only`. It uses the four existing `*_rig*` staging model paths and saves `art/characters_grip.blend`. For an age candidate, add `--age child` (or `teen` / `elder`): output stems are `character_child_grip` and `character_child_broad_grip`, each with a detailed `.glb` and `_lod.glb`; the editable source is `art/characters_child_grip.blend`. These candidate paths leave the approved standard models and age sources unchanged. Each export now publishes a complete temporary GLB with an atomic file replacement to avoid partial editor imports.

Optional `extras.grip_anchor_l` and `extras.grip_anchor_r` give the enclosed-object center in the matching Forearm pivot's local Godot coordinates. Interpolate a held object's anchor from `palm_anchor_*` to `grip_anchor_*` using that hand's grip amount; use the same interpolated point for inverse-kinematic targeting. The full grip encloses a small handle across the palm, along Forearm-local X. The actor must still align the actual utensil direction with the grasp; center contact alone cannot guarantee a convincing hold.

The critic accepts grip v3 geometry and its reviewed runtime use, with minor partial-grip web pinches still visible at extreme close-up. Raw GLB checks verify exact neutral arm vertex sets against approved v16 and zero default morph values. The twelve age grip candidates pass a clean isolated import and 6,536 contract checks, while raw comparisons prove exact neutral hands across all four age families. The unchanged grip meshes are included in promoted revision 18 after actual cooking/eating/cake contact review. Grip study renders use the `art/character_grip_v3_hand_*.png` prefix.

## Surface attachment repair (promoted revision 18)

`--surface-repair` generates a separate candidate with continuous midface, philtrum and chin support; lips, brows and nostrils conform to the actual evaluated skin surface. Eye details follow the globe curvature, with a modest recess, and crop clumps overlap the scalp envelope. It includes the accepted v3 grip, whose arm mesh blocks are loaded from the tracked, immutable `art/source/grip_v3/characters[_age]_grip.blend` sources. Their hashes are recorded in that directory's `manifest.json`. This keeps the face-only repair from changing hand topology through a repeated voxel-remesh/decimation pass. The generator does not require the local historical iteration archive.

Candidate stems are `character_adult_surface_grip` and `character_adult_broad_surface_grip`, with detailed `.glb` and `_lod.glb` files; replace `adult` with `child`, `teen` or `elder` for those stages. Sources are `art/characters_adult_surface.blend` and the corresponding age names. These staging paths preserve the original revision 17 candidates. Their reviewed bytes have now been copied to the sixteen standard production paths, with the four corresponding editable sources promoted as well. `extras.surface_revision` identifies the repair pass; `mouth_anchor` is derived from the new lip surface and is authoritative for activity contact.

Revision 2 attachment galleries cover both strict profiles, three-quarter views, neutral and combined identity/Smile/Blink extremes across all four age families. Seventy-two evaluated-mesh distance checks pass; the adult brows stay within 1.13 mm of the head, nostrils within 0.51 mm, and the intentionally raised lip volumes within 3.32 mm. All sixteen GLBs instantiate and pass 8,464 direct Godot asset checks, and the actor integration passes 1,456 pose/contact checks. Exact raw comparisons preserve every accepted hand position, skin weight and grip displacement across all ages. The complete historical snapshot remains in the local `art/iterations/character_surface_v18` archive; the compact production hashes are tracked in `art/source/character_v18_production_hashes.json`.

These checks establish attachment, not final artistic polish: bulbous eyes, simple ears, cap-like hair silhouettes, repeated Bob locks, subtle elder anatomy and angular combined jaw extremes remain refinement opportunities. The historical v18 adult LOD had 83,430 visible triangles with Crop/Casual (126,218 across all stored styles), about 6.3 MB; the child, teen and elder LODs have 82,514, 82,511 and 82,864 visible triangles. Final critic review accepted the age extremes and imported activity views, and all sixteen models are promoted. The full-request game score at that surface-review checkpoint was 7.2/10. The subsequent household-week failure scored 6.7/10; the repaired household review restored 7.2/10, the latest comprehensive verdict in `REVIEWS/iteration_10_final.md`. Attachment acceptance does not imply finished artwork or complete Sims-like gameplay breadth.

## Material contract

Duplicate material resources per actor instance before recoloring. Exact primary names are `Skin`, `Hair`, `Top`, `Bottom`, `Shoes` and `Eyes`.

- `Hair_highlight`, `Hair_shadow`: subtle strand/root variation; preserve their relative value differences.
- `Top_seam`, `Top_inner`: darker trim and the cream inner layer.
- `Bottom_seam`: pocket and tailored trim shading.
- `Shoes_sole`, `Shoes_accent`: rubber and contrasting panels.
- `Eyes_white`, `Eyes_edge`, `Eyes_pupil`, `Eyes_catchlight`: fixed eye details; recolor only `Eyes` for iris color.
- `Lips`, `Ear_detail`, `Nose_detail`: face accents that should follow skin-tone warmth and value.
- `Jewelry`: studs and small fastenings.

The artwork uses smooth PBR shading and modeled detail. It needs no external textures. Blender palette values are converted from sRGB to linear before export. Use ordinary sRGB `Color` values for Godot material albedo colors.

## Visual verification and limits

Current surface portraits use `art/character_adult_surface_*.png`, with `adult` replaced by `child`, `teen` or `elder` for those stages. They include neutral and combined identity/Smile/Blink left/right profiles and three-quarter views; the complete ninety-image set is archived under `art/iterations/character_surface_v18`. Older wardrobe and pose studies remain under the `art/character_rig_*.png` prefix. A studio walk pose does not apply runtime foot grounding; inspect actual furniture contacts in the game as well.

The detailed assets prioritize the creator. The current adult detailed file has 162,024 visible triangles with Crop hair and the casual shirt. The LOD has 102,694 visible triangles in that configuration, 145,482 across all stored styles, and is about 7.1 MB. This is an increase of 19,104 detailed and 19,264 Live triangles over v18, including skinned pocket trim. The measured eight-adult renderer fixture applies only to the tested RTX 5090 workstation; no general frame-pacing or other-hardware claim follows. Use the LOD assets for the live camera; they reduce ordinary surfaces while preserving morph topology. All hairstyle/outfit variants are stored together, so total exported triangle counts exceed the visible count for one person. Broad-frame variation is horizontal scaling, not independently sculpted anatomy. The v16 hands have contoured palms, individually curved fingers with restrained spacing, and a continuous wrist transition. Fingers have individual modeled forms and independent hand-grip morphs, but no separate finger bones. There is no cloth simulation, facial speech rig, continuous age morphing, infant/toddler anatomy or arbitrary-angle pose guarantee. These remain production improvements rather than claims of finished quality.

A strict side-profile check of the former approved v16 source exposed visible gaps at the lips, brows and some crop-lock roots, plus an overhanging nose underside above a flat midface. The evidence is `art/character_v16_profile_diagnostic.png`. These predated grip and were repaired in the promoted revision 18 through continuous facial volume and surface-bound details. Earlier frontal art scores did not establish profile completeness, which is why both strict profiles are now included in review.

References consulted through Context7: [Blender Object/ray casting](https://docs.blender.org/api/current/bpy.types.Object.html), [mesh API](https://docs.blender.org/api/current/bpy.types.Mesh.html), [dependency graph](https://docs.blender.org/api/current/bpy.types.Depsgraph.html), [glTF exporter](https://docs.blender.org/api/current/bpy.ops.export_scene.html), and [Godot Skeleton3D](https://docs.godotengine.org/en/stable/classes/class_skeleton3d.html).
