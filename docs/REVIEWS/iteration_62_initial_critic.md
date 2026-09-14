# Iteration 62 — independent initial character critique

14 September 2026. Scope: character art and its presentation, judged against
polished commercial life-simulation characters. This is a **provisional evidence
review**, not a fresh build acceptance or a full-game score.

The critic read `docs/QUALITY_RUBRIC.md` and the iteration 61 review, then viewed
the actual images in `evidence/character61/`, `evidence/face61/`,
`evidence/hair61/`, `evidence/hands61/`, age portraits in `evidence/face60/`, and
`evidence/resolution61/creator_1440.png`. Existing review scores were not used as
visual evidence. The iteration 61 text identifies several face61 captures as
predating its final iris adjustment, so those images cannot establish the
current build's iris proportions. Fresh Godot portraits and a profile lineup
are required before assigning a current-build score.

## Provisional score from the inspected images

**Character visual quality: 5.5/10.** This is a coherent stylized character
prototype with useful clothing and hair options, but close-up faces and hair
construction still have prominent issues. A 10 requires finished features,
recognizable independent identities, convincing materials and animation, and
verification across the supported appearance range. Stopping iterations does
not satisfy that standard.

| Character facet | Provisional score | Visible basis |
| --- | ---: | --- |
| Face integration and expression | 5.0 | Legible lips and nose, but conspicuous eye/surrounding-skin boundaries and a fixed doll-like expression |
| Hair shape and finish | 5.0 | Recognizable crop, bob and curls; broad overlapping masses and abrupt lock joins in close-up |
| Skin, hair and garment materials | 5.0 | Cohesive colors; largely uniform surface response makes different substances look like similarly colored clay |
| Body, hands and clothing | 6.0 | Complete body and separated fingers, multiple usable outfit silhouettes; stiff stance, inflated sleeve joins and tubular trouser legs |
| Individuality | Unverified | Existing captures mainly change styling on one profile; age images and recolors do not demonstrate a diverse set of adult facial identities |
| Creator presentation | 7.0 | Clear original interface and useful full-body preview; the close-up is crowded against the settings panel and ordinary full-body framing makes facial decisions difficult |

Facet scores are diagnostic judgments, not the five-dimension full-game rubric.
Mechanics, usability in motion, sustained play and reliability are unverified by
this screenshot review.

## Five highest-impact changes

1. **Integrate the eye region into the face.** The creator close-up draws
   attention to exposed eye outlines and hard boundaries around the openings.
   Author a natural upper-lid arc, readable inner corners, subtle lid crease and
   lash/brow definition; keep the iris seated behind the lids at all supported
   eye morphs. Confirm front and three-quarter portraits in Godot for light,
   medium and deep skin, including slider extremes. Iris detail helps only after
   the larger forms read correctly.
2. **Make hair read as continuous styled growth.** The close-ups show large
   plate-like overlaps and joins between the crown and hanging sections.
   Preserve broad stylized locks, but connect them with an intentional part,
   root direction, overlapping taper and varied clump width. Check every style
   from the front, side and back; no blunt shelf joins, scalp gaps or exposed
   internal surfaces. Some Blender probe artifacts may come from visibility
   setup and must be confirmed in the shipped view before being called current
   production defects.
3. **Demonstrate independent facial identities.** Produce a same-lighting,
   same-camera lineup whose characters differ in jaw/chin, cheek width, nose,
   eye set, brows and mouth as well as complexion, age, hairstyle and clothes.
   At least six adult faces should remain distinguishable with the same hair
   and neutral clothing. Portrait presets should form coherent faces rather
   than arbitrary extremes or color substitutions.
4. **Give skin, hair and clothes distinct surface responses.** Keep the game's
   soft stylization, but add controlled skin color variation, a restrained eye
   highlight and limbal transition, directional hair variation, and a finer
   roughness response for fabric. Cloth needs plausible tension/folds at the
   elbow, waist and knee, with clean shoulder and sleeve transitions. Judge
   these changes at the creator's normal zoom as well as close-up.
5. **Improve the body pose and portrait framing.** Relax the shoulders and
   hands, introduce a restrained weight shift, and make the face preview easy
   to inspect without a panel covering the shoulder silhouette. Verify idle,
   walking and reaching poses: the screenshot hand has separated digits, so
   calling it a fused paddle would be inaccurate; the visible polish need is
   better palm/knuckle shaping and less rigid presentation.

## Decision

Iterate. Re-score against fresh, reproducible Godot portraits and a diverse
lineup, then inspect motion and appearance extremes. The commercial 10/10
character target is not met by the evidence reviewed here.

## Fresh Godot baseline received during this review

The critic subsequently inspected
`/home/impulse/.local/share/godot/app_userdata/JustLife/screenshots/character62_before.png`,
captured from the running game with the default Mara profile and Face tab open.
The **5.5/10 baseline is confirmed for the visible character**, subject to the
same unverified individuality and motion limits. The face remains 5.0; the bob
hair is 5.5 at this camera; materials 5.0; visible clothing 6.0. This image is
direct evidence that the oversized green eye discs are present in the current
baseline, rather than an inference from the older face61 images. Brows are not
visibly readable, the cheek/jaw shows hard triangular shading, and the shirt's
shoulder-to-sleeve joins form abrupt lobes. Those are the highest-value issues
to change in the next portrait.

The new Face-tab framing is clearer than the old Look-tab close-up: the model's
head and shoulders sit away from the settings card. Its presentation is 8.0 at
this resolution. The bob has a coherent broad silhouette, so the old Blender
long-hair shelf artifacts are **not** claimed as a confirmed defect of this
fresh bob view.

### Matching three-quarter shadow diagnostic

Two additional actual Godot images were inspected at the same camera:
`character62_before_three_quarter.png` and `character62_no_shadows.png` in the
same screenshots directory. The latter disables the sun's shadows. It removes
the jagged dark fringe below the hairline, the stepped dark patches across the
near cheek/jaw and neck, and the serrated sleeve-to-torso shadow. This is strong
evidence that the most conspicuous triangular-looking facial shading is caused
by shadowing, **not evidence of flat native head normals**. The shadow-disabled
cheek reads reasonably smoothly. Nose and chin still use broad sculpted planes,
but the eye/brow repair is a higher visual priority. Any lighting fix should
retain deliberate depth and contact while removing these artifacts; disabling
all shadows is a diagnostic, not by itself a finished lighting solution.

The angle also establishes a current bob shape defect more precisely: the
near-side clumps begin with abrupt cut root ends against the crown cap, then
end in almost equally spaced, equally long tapered points. The result reads as
a row of separate hanging rods. The large front bang also reads as a distinct
mass placed over the cap. Varying clump width/length and integrating the root
flow is more valuable here than adding tiny strand textures. The inflated
shoulder lobes remain in the shadow-disabled comparison, so those are a
geometry/pose issue rather than the same shadow artifact.
