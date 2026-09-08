# Independent review — side-profile attachment defect

**Historical checkpoint:** the final combined acceptance and current 7.2/10 score are recorded in [iteration_08_final.md](iteration_08_final.md). Earlier scores and open findings below describe their original review stages.

8 September 2026. **Current full-request score revised to 7.0/10.** Visuals 6.0, usability 7.5, simulation depth 7.0, breadth 7.0, reliability 7.5; weighted result 6.95, rounded to 7.0. This revises the earlier 7.2 using new evidence of an existing defect, rather than claiming the gameplay regressed.

The model agent rendered the approved v16 Blender source in strict side profile. The critic directly inspected that diagnostic, preserved in `art/screenshots/profile_iteration_08/v16_strict_profile_before.png`. It reveals substantial geometry attachment problems that front portraits and the earlier activity-camera angles concealed:

- The lips float entirely clear of the face surface.
- The brow floats above the forehead.
- The nose projects across a large empty gap below its root, with the flat midface failing to support a coherent facial silhouette.
- The crop hairstyle's front locks include detached strips and visibly separated roots.

These are authored baseline geometry defects, not inferred animation or import problems. Earlier static-art acceptance was too narrowly based on front/three-quarter evidence. The successful gameplay, age/school save, birthday presentation, desk-clearance and shared-chair results remain valid, but those checks cannot certify the unseen sides of the character artwork.

## Required next correction

Treat the facial profile as one continuous sculpted volume. Build a coherent midface/muzzle and nose attachment, embed the lips and brow roots against the actual skin surface, and attach hair roots. Simply pushing separate features backward into a flat face would hide gaps without creating a convincing profile.

Acceptance requires strict left and right profiles, both three-quarter views, front view, and expression/identity extrema. The correction must retain closed eyelids, neutral and smiling mouths, and consistent attachment through character customization and the supported ages. Actual in-game close views should follow the Blender studies before final promotion.

The staging grip morphs were separately accepted for propagation after their static thumb-web cleanup and cross-age inspection. That approval does not certify utensil orientation/contact or override this baseline face defect. Original artwork and broader customization still need iteration; a 10/10 claim is not supported.

## Staged adult surface repair — static checkpoint

The model agent's revision-2 adult surface candidate has now been independently viewed in neutral right profile and three-quarter, identity left profile, smile three-quarter, Blink right profile, combined extreme-smile both profiles, and combined extreme-Blink three-quarter. Viewed evidence and image hashes are preserved in `art/screenshots/profile_iteration_08/adult_surface_candidate/`.

The prior detached lips/brows are now joined visually to a continuous facial silhouette; the nose connects through an actual midface volume, nostril patches no longer project as loose slivers, and the crop roots overlap the scalp cap. Blink closes fully in the inspected views without exposed catchlights. Identity/expression combinations retain those attachments. This adult static attachment gate is accepted.

Profile eyes remain rounded and broad-jaw extrema show angular cheek/jaw transitions; these are remaining sculpt quality limitations. Other ages, Bob/Curls profiles, actual imported Godot poses, and final mouth/utensil contact remain separate gates. The production score remains **7.0/10** until the staged repairs pass those checks and are promoted.
