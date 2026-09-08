# Iteration 11 — independent hair r13 study review

**Decision: retain the improved Bob direction, continue refinement, and do not promote this bundle yet.** The adult/child studio study earns **Bob 7/10** and **Curls 6/10** for the inspected artistic result against the requested character-quality target. These are explicitly hair-study scores, not a replacement rubric or a full-game rating. Production still uses v18; the last full-request weighted score remains **7.2/10**, with the original dimensions and weights in `docs/QUALITY_RUBRIC.md`. Neither this study nor the game merits 10.

## Evidence and provenance

Reviewed `art/experiments/hair_v19/REVIEW.md`, `source_manifest.json`, all four r13 render-preservation reports, and the Godot import verifier and its execution log. Independently recomputed the six current source/generator hashes and both candidate GLB hashes: all match the manifest. All **20 production v18 file hashes remain unchanged**. The gallery contains the stated 32 r13 and 20 baseline PNGs; the four render reports record the correct current adult/child source hashes, 900-pixel images and 40 Cycles samples.

The editable adult source SHA-256 is `48f5e213a88612caaa3d7890d92078d5dd5cfb299d5352b1d1737b02f43419aa`; child is `f648f3b0e96a69143872270b1f77187bd3298d11b9c896dfa6cdfac0d7e4cb50`. Export hashes are adult `f3dc07c0117c4264912eeb0a587173f4e4274aafd817dbb9e66b8054404be9c8` and child `79982c03ac63431f4ad7bce691ed827f6e96324c6284a72a4cefe305c67280ab`.

Direct visual inspection covered these selected views, rather than claiming every gallery image was examined:

- Matched v18/r13 adult Bob front and three-quarter, child Bob left and right, adult Curls front and child Curls left.
- Matched v18/r13 adult full-body `creator` views for both styles, plus both child r13 `creator` views.
- Additional r13 adult Curls right; adult Bob front and child Bob left at broad frame plus maximum identity morphs; child Curls right at those maxima.

The root of those image names is `art/experiments/hair_v19/`; filenames follow the handoff's `r13_<age>_<style>_<view>[_broad_identity_max].png` pattern. The import log reports **2,120 checks, zero failures**. Source inspection confirms checks of imported non-hair vertices/skin arrays, transforms, morph names/neutral values and skeleton rests. That author-run contract check is useful compatibility evidence, not a rendered action test or proof of good hair topology. The study also reports exact preservation of 105 adult and 121 child non-hair meshes; this critic did not rerun Blender generation.

## What improved

The Bob now has an identifiable asymmetrical haircut: a diagonal fringe, a long side and a visibly tucked side. Its continuous surface and silhouette work at full-body framing. Compared with the old repeated hanging tubes and separate fringe piece, this is a substantial improvement in coherent form. The inspected profiles show an intentional ear opening and no older crown projections. The selected maximum-morph views show no gross hair/face crossing; that is limited visual clearance evidence, not complete morph validation.

Curls gains a coherent short-hair mass and more deliberate direction around the head. The inspected r13 views lack the earlier crown spikes and the baseline's obvious repeated beads. Its hooked sections retain a curly identity better than the earlier wavy experiment. These are real improvements, but the medium-scale surface treatment remains unresolved.

## Defects and next acceptance conditions

| Priority | Observed defect and consequence | Checkable next result |
| --- | --- | --- |
| P1 | Curls still reads as shiny embossed loops on a molded shell. Large O/S-shaped ridges appear carved into or spread across one surface, especially in `r13_adult_curls_front.png` and `r13_child_curls_left.png`. The result lacks convincing lock growth, overlap and taper. | Reshape a smaller number of readable curl groups with credible roots, overlaps and tapered ends; vary their depth and direction without repeating glyph-like grooves. Compare neutral front, both profiles and full-body views under the same lighting before acceptance. |
| P1 | Curls has conspicuous black gaps beneath its temple edges. These remain visible in both full-body creator images, so this is not only an extreme close-up concern. Bob has a similarly hollow, hard-edged underside at the nape and fringe in the child right profile. These boundaries make the hair read as a rigid cap. | Fit the inner boundary and transition into sideburn/temple/nape forms. Preserve intentional hairstyle clearance while removing the continuous hollow rim impression. Verify both profiles, front, light recolors and actual game lighting. |
| P2 | Broad smooth highlights and uneven shallow relief make the Bob look glossy and molded, despite its improved shape. Curls has the same material issue, magnified by its wide ridges. | Refine the geometry and highlight response together. Keep a clear large silhouette, restrained directional detail and consistent surface finish at portrait and full-body scales. A roughness change alone cannot fix the curl structure. |
| P2 | Tiny dark notches persist in the neutral child left profiles: Bob near image coordinate (305, 285), Curls near (332, 275), in the 900 × 900 PNGs. They look like surface pinches or discontinuities. A screenshot does not establish whether the cause is topology, normals or self-shadow. | Inspect those exact surface regions and confirm the diagnosis with mesh/normal inspection and a short lit turntable. The revised profiles should lose the isolated dark flecks without hiding them through camera choice. |

The exaggerated face/body shape in a maximum-identity image is not attributed to this hair patch: the non-hair source is preserved and a matched maximum baseline gallery was not supplied.

## Verification boundary

Adult and child studio rendering is the demonstrated scope. A file named `creator` is a studio full-body camera, **not the actual Godot creator**. Teen/elder variants, production LODs, hair recoloring, actual creator selection, ordinary live-camera rendering, action transitions and furniture/food/social contact remain unverified for r13. Those must be checked before a complete replacement can be accepted. No source, runtime, assets or distribution artifact was promoted by this review.

The next pass should preserve the Bob's new silhouette, repair its surface and boundary treatment, and solve Curls' lock structure before multiplying variants. Compatibility counts cannot substitute for those visible improvements or broaden the full-game score.

For the next bounded art pass, fix the child Bob's visible notch and hollow fringe/nape edge first, and rebuild one Curls temple-to-crown region with actual overlapping tapered locks before extending that treatment around the head. The smallest useful rerender set is **six matched images**: child Bob left and right, adult Curls front, child Curls left, and the adult full-body creator view of each style. Reuse the current cameras, material colors and lighting so the defect fixes are comparable. This is a directional checkpoint; repeat the full age/profile/extreme and in-game coverage only after it clears.
