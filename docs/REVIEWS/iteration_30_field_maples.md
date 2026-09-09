# Original field maple trees

9 September 2026. The independent critic accepts this incremental replacement after directly inspecting twelve actual images: six baseline views and six matching candidate views. The new trees have visible branching and unequal connected crowns. They replace the repeated procedural spheres in Home, park and neighboring homes. This review does not raise the whole-game score.

The two original Blender trees retain the existing tree root positions and camera-fading behavior. Coordinate-derived variant and rotation choices consume no random numbers. Only tree materials enable their authored vertex colors. Each tree has two immediate meshes and 2,440 full-detail triangles, compared with eight meshes and 2,304 triangles previously.

The first imported candidate showed dark jagged canopy marks. Four controlled diagnostic frames isolated generated canopy LOD shadow silhouettes: removing shadows or forcing full detail removed the marks; removing only the optimized shadow mesh did not. The accepted import settings disable generated LODs only on the canopies. Branch LODs, optimized shadow meshes, shadow casting and foreground fading remain. Fresh imported branch buffers and all seven LOD thresholds/indices match exactly; canopy attribute vertices and oriented triangles match exactly despite importer reordering.

The final matched comparison covers Home, its opposite camera orbit, Build, park, Maya's home and Leo's home at 1440×900 in Forward+. It records 684 assertions with no failures and exact recorded non-tree state, actors, lighting, camera, random state, tree roots and fade conditions. Baseline and candidate capture runs completed cleanly with six images each. These are controlled, paused art fixtures with direct venue setup; they do not prove native input or a complete travel sequence. Root independently checked 196 evidence pins across the handoff and linked freezes, and directly inspected the corrected Home and Leo frames. The critic inspected all twelve frames.

Fresh portable generation reproduces both GLB files byte for byte. Recorded native Blender source values match across 26 objects and two materials; the resaved Blender container bytes differ. All four exported meshes are closed manifold volumes with consistent winding, positive volume and no degenerate faces. The qualified editable source is preserved. The three Blender processes exited successfully but their logs retain existing optional-addon registration tracebacks, the unavailable optional MeshOptimizer bridge notice and deprecation output; they are not described as clean logs.

Matched sequential measurements on the RTX 5090 retain complete distributions. Home/Park GPU rendering medians were 0.4065/0.292 ms, compared with 0.409/0.295 ms previously. CPU rendering medians were 3.8495/1.1665 ms, compared with 3.4785/1.1475 ms: Home increased by 0.371 ms. Reported draw calls declined from 4,028/1,763 to 3,896/1,663. This is no claim of an overall performance improvement or performance on other hardware.

The broad variant still has a smooth umbrella-shaped crown and a horizontal lower shelf, especially beside Maya and Leo's homes. The critic records this as a remaining art limitation. Other camera distances and lighting angles are not exhaustively covered.

Local evidence:

- `dist/test-work/trees-v29-canopy-lod-final-wb209qis/HANDOFF.md`, SHA-256 `d1ef67c18eab76a9e59f4deee072e137abfbf1d8bf0c333ad64d4c8849a56dd2`; its freeze is `fac56db890329b08654f6eea2b57734c3ad860a4e6b8a3402841a7d565d3c0f5`.
- `dist/test-work/trees-v29-matched-canopy-final-7zmcz3kx/VISUAL_FROZEN.json`, SHA-256 `461fa6e13f769098fbbf7d57daec792e0a24605a20c7466bcc3eb13feca16a03`.
- `dist/test-work/tree-final-critic-v29-1suh_q59/REVIEW.md`, SHA-256 `af5c44765451d69ae84453cfa1ce497e5bcd209bdcc83b9cbf963c2f6bfa8268`.
- `dist/game-work/tree_promotion_receipt.json` records root's exact source integration. Current combined source and exported-package qualification remain separate from the earlier matched art study.

The integrated trees and camera/UI changes then passed fresh import and the existing rendered menu suite with 88 assertions, zero failures or diagnostics, seven actual images and no input drift. Root verified its 1,715 frozen pins and exact match to all 1,077 canonical files before the review-document additions. The combined HUD and confirmation show the new trees with their materials intact. See [the camera review](iteration_29_camera_clarity.md) for the precise signal-driven scope and `dist/game-work/combined_ui_tree_qualification_receipt.json` for root's receipt. Exported-package qualification remains separate.
