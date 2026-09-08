# JustLife original character assets

Original geometry and artwork authored in Blender for JustLife. The exported assets contain no meshes, textures or screenshots from The Sims.

## Files and integration status

Revision 18 (surface revision 2) is promoted to all sixteen standard adult, child, teen and elder game paths. The repository keeps the production assets, editable sources and required generator inputs. Duplicate `*_surface_grip*`, older `*_rig*` and age `*_grip*` candidates, renders and historical `art/iterations` archives remain local and are excluded from Git:

| File | Intended use |
| --- | --- |
| `assets/models/character.glb` | Detailed standard adult frame for the creator |
| `assets/models/character_broad.glb` | Detailed adult frame with 12% broader horizontal proportions |
| `assets/models/character_lod.glb` | Standard frame for the live camera |
| `assets/models/character_broad_lod.glb` | Broad frame for the live camera |
| `art/characters.blend` | Editable current rig, garments, hair, expressions and portrait studio |
| `tools/create_characters.py` | Procedural generator, including export and pose renders |
| `art/characters_child.blend`, `characters_teen.blend`, `characters_elder.blend` | Editable current age variants |
| `art/source/grip_v3/` | Four immutable Blender inputs preserving accepted hand meshes and grip morphs |
| `art/source/character_v18_production_hashes.json` | Hashes of the sixteen promoted GLBs and four editable character sources |
| `art/experiments/hair_v19/` | Unpromoted hair study, portable generator and editable adult/child candidates |

The standard adult paths and the twelve corresponding child/teen/elder paths contain the reviewed surface repair and hand grips. Promotion followed 8,464 actual Godot scene/asset checks, 1,456 actor/contact checks, and independent static and combined creator/profile/cooking/snack/child-birthday review. Actor source `ef20e62accd5fdf8fc1c493985bdd1d8d6c2249bfd079ff5a45f4a16f9f7defb` was promoted with them. Exact standard asset/source hashes are in `art/source/character_v18_production_hashes.json`; the previous twenty production files remain in the local `art/iterations/before_surface_v18_promotion` archive. The optional `rig_preview` setting selects older experimental rig paths when present and otherwise retains the standard production model.

Regenerate the current adult candidate using `blender --background --python tools/create_characters.py -- --surface-repair`. Add `--age child`, `--age teen` or `--age elder` for those stages. Append `--promote` only after the resulting candidate passes review; it atomically replaces that stage’s four standard GLBs and editable source. Running without `--surface-repair` retains the earlier sculpt pipeline for historical comparison. This separate Blender process creates its own scene and leaves any other open Blender session untouched. All default morph values are explicitly zeroed before and after export. All exported mesh primitives have UVs, including the untextured morph meshes, for clean Godot tangent generation.

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

Child, teen and elder assets use the same skeleton, hair, outfit and morph contracts, with independently placed rest landmarks and continuous anatomy changes. Their file families are `character_child.glb`, `character_child_lod.glb`, `character_child_broad.glb`, `character_child_broad_lod.glb`; replace `child` with `teen` or `elder` for the other stages. `young_adult` and `adult` use the ordinary adult paths. Regenerate the current stage candidate with `blender --background -t 8 --python tools/create_characters.py -- --surface-repair --age child` (or `teen` / `elder`). Append `--preview-only` to export all four variants and render only full-body/face portraits when a small material refinement does not need a repeated full pose sheet. Reviewed editable sources are `art/characters_child.blend`, `characters_teen.blend` and `characters_elder.blend`; new candidates use the corresponding `characters_child_surface.blend` names until promotion.

| Stage | Approximate height | Hip hinge | Knee hinge | Head pivot height | Anatomy |
| --- | --- | --- | --- | --- | --- |
| Child | 1.18 m | 0.580 m | 0.335 m | 0.925 m | Shorter limbs, larger relative head, softer and shorter lower face, straighter trunk |
| Teen | 1.55 m | 0.810 m | 0.480 m | 1.274 m | Lighter adolescent frame with its own shoulder, elbow and limb lengths |
| Elder | 1.72 m | 0.912 m | 0.545 m | 1.425 m | Mild forward shoulder/head posture, cheek/jowl and facial-fold changes, gray hair default |

These stages bake all attachment scales to one, including `Head`. Their global bone rest bases remain identity and exactly match the retained pivot positions. The adult retains its documented Head scale of 0.91. Treat the profile height slider as a relative multiplier on the selected stage, not a replacement for its authored proportions.

The exporter writes contact data as glTF `extras` on `Character`. Godot imports it as **one dictionary**, accessed with `character.get_meta("extras", {})`. Its keys include `age_stage`, `age_revision`, `height_m`, `hip_height`, `knee_height`, `head_height`, and `bone_landmarks`. `mouth_anchor` is a three-number array in Godot coordinates local to the Head pivot. `palm_anchor_l` and `palm_anchor_r` are arrays local to the matching Forearm pivots. Convert these arrays to `Vector3` and use each pivot's transform to find its world contact point. The elder also provides `default_hair_color`; this is a suggested default that remains recolorable. Elder brows use `Hair_shadow` for clearer expression. Fine facial creases reuse `Ear_detail`, with barycentrically attached Blink/Smile/identity deltas, so they follow both facial customization and skin recoloring. Read the actual exported dictionary rather than copying constants, as facial refinements can adjust mouth contact slightly.

The final child v3, teen v1 and elder v3 imports pass 6,464 direct asset checks across all twelve files: complete skeletons, identity rest rotations, coincident bone/pivot positions, default-neutral expressions, wardrobe presence, valid mesh bounds and usable contact metadata. The critic has accepted child v3 and teen v1 age proportions in a shared-scale family lineup. These checks establish the asset contract; actual actor activity contact requires the separate runtime review. The critic accepts elder v3 as a first functional elder variant, with age-read around 6.5/10; stronger broad cheek/jowl and under-eye forms remain useful later refinements. Child and teen age proportions are accepted at roughly 7.3–7.5 within the current art style. Baby, infant and toddler models are not supplied by these age variants. The former age LODs contained about 64,058, 64,055 and 64,408 visible triangles with Crop/Casual; current surface/grip counts are listed below. Approved source/export snapshots are retained under `art/iterations/character_child_approved`, `character_teen_approved` and `character_elder_approved`.

## Hair and wardrobe

Every variant is included in each GLB. Hide all but the selected hair and outfit after instantiation. Hide matching mesh prefixes recursively as well as container nodes, because skinned meshes can be reparented by the importer.

| Selection | Group / mesh prefix | Shape |
| --- | --- | --- |
| Hair 0 | `Hair_Crop` | Asymmetric swept crop with crown locks and subtle directional surface grooves |
| Hair 1 | `Hair_Bob` | Jaw-length layered bob with swept fringe |
| Hair 2 | `Hair_Curls` | Rounded irregular coils with sculpted ridges |
| Outfit 0 | `Outfit_Casual` | Short sleeve shirt, light collar/cuffs and button placket |
| Outfit 1 | `Outfit_Jacket` | Cropped bomber, long sleeves, stand collar, zipper and ribbed edges |
| Outfit 2 | `Outfit_Cardigan` | Longer open V-neck knit over a cream tee, with patch pockets |

Brows also use the `Hair_` prefix. Keep them visible when switching hairstyles. All outfits share tailored trousers and low-top sneakers with laces, sole and side accents.

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

These checks establish attachment, not final artistic polish: bulbous eyes, simple ears, cap-like hair silhouettes, repeated Bob locks, subtle elder anatomy and angular combined jaw extremes remain refinement opportunities. The repaired adult LOD has 83,430 visible triangles with Crop/Casual (126,218 across all stored styles), about 6.3 MB; the child, teen and elder LODs have 82,514, 82,511 and 82,864 visible triangles. Final critic review accepted the age extremes and imported activity views, and all sixteen models are promoted. The full-request game score at that surface-review checkpoint was 7.2/10. The subsequent household-week failure scored 6.7/10; the repaired household review restored 7.2/10, the latest comprehensive verdict in `REVIEWS/iteration_10_final.md`. Attachment acceptance does not imply finished artwork or complete Sims-like gameplay breadth.

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

The detailed assets prioritize the creator. The current adult detailed file has 142,920 visible triangles with Crop hair and the casual shirt. The LOD has 83,430 visible triangles in that configuration, 126,218 across all stored styles, and is about 6.3 MB. Use the LOD assets for the live camera; they reduce ordinary surfaces while preserving morph topology. All hairstyle/outfit variants are stored together, so total exported triangle counts exceed the visible count for one person. Broad-frame variation is horizontal scaling, not independently sculpted anatomy. The v16 hands have contoured palms, individually curved fingers with restrained spacing, and a continuous wrist transition. Fingers have individual modeled forms and independent hand-grip morphs, but no separate finger bones. There is no cloth simulation, facial speech rig, continuous age morphing, infant/toddler anatomy or arbitrary-angle pose guarantee. These remain production improvements rather than claims of finished quality.

A strict side-profile check of the former approved v16 source exposed visible gaps at the lips, brows and some crop-lock roots, plus an overhanging nose underside above a flat midface. The evidence is `art/character_v16_profile_diagnostic.png`. These predated grip and were repaired in the promoted revision 18 through continuous facial volume and surface-bound details. Earlier frontal art scores did not establish profile completeness, which is why both strict profiles are now included in review.

References consulted through Context7: [Blender Object/ray casting](https://docs.blender.org/api/current/bpy.types.Object.html), [mesh API](https://docs.blender.org/api/current/bpy.types.Mesh.html), [dependency graph](https://docs.blender.org/api/current/bpy.types.Depsgraph.html), [glTF exporter](https://docs.blender.org/api/current/bpy.ops.export_scene.html), and [Godot Skeleton3D](https://docs.godotengine.org/en/stable/classes/class_skeleton3d.html).
