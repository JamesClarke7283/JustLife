# Hair v19 / study r14 directional checkpoint

**Unpromoted; independently reviewed.** Production remains v18. The [iteration 12 review](../../../docs/REVIEWS/iteration_12_hair.md) rates these six views at Bob 7/10 and Curls 5.5/10. The full-game score remains 7.2/10. All build, render and import-verification processes have completed.

## Exactly six matched images

- `r14_child_bob_left.png`
- `r14_child_bob_right.png`
- `r14_adult_curls_front.png`
- `r14_child_curls_left.png`
- `r14_adult_bob_creator.png`
- `r14_adult_curls_creator.png`

These use the existing r13 cameras, lighting, colors, 900×900 resolution and 40 Cycles samples. The four selection-specific `r14_*_review_preservation.json` files record each source hash, camera and light setup. All captured source hashes match the current editable files. These are Blender studio views, including the full-body images called creator; they are not Godot gameplay screenshots.

## Diagnosis and changes

Raycasts into the exact cited child left-view neighborhoods found no open/nonmanifold edges or degenerate faces. Local face-to-corner-normal deviations reached 35.1° in Bob and 68.8° in Curls, including very narrow collapsed faces. The r13 generator combined high-frequency relief with collapse decimation; this produced localized shading pinches. Its concentric inner envelope also displaced the fringe inner edge downward and left the shell separated from the head.

r14 preserves the asymmetric Bob silhouette but uses regular 64×160 surface topology, lower-frequency restrained relief, and an inward/upward fitted inner lip. The cited patch's maximum normal deviation is now 3.7°. The front/left Curls region has a closer undercoat plus separate solid tapered lock groups with buried roots, changing depth and overlapping ends. The corresponding base patch's deviation is 1.2°; that number describes the base, not the new overlaid locks. The rear Curls relief remains an r13 control outside this directional study.

The original base colors and recolorable material names are preserved. Hair roughness is at least 0.79 and specular IOR level 0.27. These existing shared hair materials also serve the experimental brows/crop; their geometry is unchanged. The material adjustment accompanies structural changes and is not offered as a substitute for them.

## Current visual limits

The isolated Bob fleck is absent in the inspected matched left image, and the large asymmetry remains. A dark underside is still visible at the right fringe/nape; the fitted lip has not demonstrated final resolution of that artistic concern. Curls now has real overlap and taper rather than embossed O/S relief in the study region, but its broad pointed groups may read as leaf-like tufts and leave conspicuous gaps above the undercoat. Independent critique confirms the Bob edge remains unfinished and finds the Curls treatment reads as broad pointed leaves or ribbons over a smooth cap.

The critique accepts this as a reproducible experimental checkpoint, with further geometry work required before promotion. No further ages, views, extremes, recolors or game integration should be inferred from these six images.

## Preservation and provenance

`source_manifest.json` pins the current six maintained source/generator files and both excluded candidate GLBs. All 20 hashes in `art/source/character_v18_production_hashes.json` were recomputed and remain unchanged. The builds preserved 105 adult and 121 child non-hair meshes, including topology, coordinates, morphs, weights and transforms. Fresh isolated Godot 4.7.2 verification passed 2,120 checks with zero failures, comparing imported non-hair vertex/bone/weight arrays, morph contracts and skeleton rests. This compatibility evidence does not establish artistic acceptance.

Exact r13 editable sources, source manifest, generators, handoffs and both candidate exports are preserved in ignored `evidence/r13_before_r14/`, with an archive checksum manifest. Geometry diagnostics and completed build/render/import logs are also under ignored `evidence/`. Production assets, shared game scripts, accepted review documents and remote branches were not changed by this study.
