# JustLife independent review — eight Lifelets, town travel and named saves

Review date: 8 September 2026. Main checkpoint: `/tmp/justlife-playthrough-ee2ka19i`, frozen after the v11 character rig, new main menu/save library, household spacing, wrapped text and ceiling cutaway fixes. Later production edits are excluded. Evidence and exact script/model hashes are in `art/screenshots/neighborhood_iteration_03/`; independent menu-edge and bench evidence are in `menu_edges_iteration_03_initial/` and `bench_iteration_03/` under the same screenshots directory.

## Full-request score: 6.7 / 10

| Dimension | Score | Evidence and limit |
|---|---:|---|
| Visual and character quality | 7.0 | Continuous rigged characters and three visibly distinct outfits now work in the game; cutaway interiors keep reading/painting visible. The original art is coherent. Hands, shoulder contours, neutral eyelids and activity expression still look simplified. |
| Usability and flow | 6.5 | Main menu, creation, eight-person selection, move-in, map, Stories and named-save loading form a connected flow. Normal copy and chips fit. Long valid household names break save-dialog and HUD bounds, and queue cards remain low contrast. |
| Simulation and interaction depth | 6.5 | Household independence, spatial activities, exact time/cost/need consequences, story rewards and paid-action restart work in rendered play. Interaction presentation and the variety of consequential social/career outcomes remain limited. |
| Creative breadth and sustained play | 6.5 | Eight people, three outfit silhouettes, public park/library/studio, player remodeling and daily story decisions offer a broader playable loop. The requested family/aging experience and extensive identity, building and progression variety remain substantial gaps. |
| Reliability and delivery | 7.0 | All 317 neighborhood assertions pass, including a fresh-process named-save restart and exact eight-person/home-state restoration. The observed eight-person idle view now runs near 60 fps. Long-name UI failures remain, and broad multi-day/device/export coverage is still missing. |

The weighted mean is 6.675, rounded to **6.7** using the unchanged rubric. This is a stronger playable game than the previous checkpoint. It does not meet the rubric's 9–10 anchors or the full requested breadth.

## What changed and was actually verified

The rendered public-flow suite passes **237 first-process assertions and 80 fresh-process assertions**, with **zero engine/script error lines**. It uses an isolated project and private userdata, actual Forward+ rendering at 1440 × 900, production button signals, actual build mouse input and real frame processing. It does not teleport actors or call the simulation tick directly. Thirty screenshots, state reports and logs accompany the run.

The full neighborhood sequence from `iteration_03_initial.md` passes again: creator → eight individually named Lifelets → chosen home → purchase/invalid purchase → real room/wall/door/floor editing → park/library/studio travel → routed public activities → Day 2 decision with verified costs/needs/XP/friendship → charged painting with reading queued → save away → close/restart → load actual studio → resume without duplicate charge → return to the exact remodeled home.

This checkpoint additionally exercises **New game** from the main menu, chooses Casual/Jacket/Cardigan outfits across the household, writes a chosen slot name through **Save as new**, and reloads through **Saved lives → Load selected life** in a fresh process. Individual saved appearance comparisons now include outfit, eye, body/height and face fields when present. The run did not move the new face sliders, so it verifies their stored default values rather than the full slider range or visible identity variety.

All eight creator/live/returned-home chips fit without overlap. Normal wardrobe, map and story descriptions wrap inside their intended panels. The map also scales to the tested 1120 × 700 window. Speed captures now retain the selected actual speed, in addition to checking the selected-state controls. Ceiling beams no longer obscure the reading Lifelet or painter in cutaway mode.

The promoted character visibly changes with outfit selection and has continuous limbs. A separate targeted bench playthrough used normal speed, allowed half the activity to complete, then paused and turned the camera by 90 degrees. Its side view proves horizontal thighs and bent knees on the seat. Recorded diagnostics show an empty route, seat anchor, Sit value 1, approximately −90° thigh and +90° shin rotations. The earlier frontal view was misleading; **there is no confirmed bench pose or rig scheduling defect**. Nineteen targeted checks passed without error.

After twenty warm-up frames, sixty frames of the eight-person idle view averaged **16.57 ms**, with **17.03 ms at the 95th percentile**, approximately 60 frames/s on the current RTX 5090 machine. The earlier 58.7 ms mean did not recur. Asset changes and competing render workloads changed between runs, so this cannot identify the cause of the improvement or establish performance on other machines.

## Independent save edge cases

The separate test `tests/test_menu_edges.gd` ran against the same frozen production checkpoint with eight valid long names, a long valid save title, five independent slots and a deliberately unreadable fixture in isolated test userdata. **76 of 78 assertions passed.** The two failures are confirmed copy/control overlaps. The only error lines are those two intentional failed-check messages.

Verified behavior:

- Whitespace-only save names are refused without creating a file or closing the picker.
- Five **Save as new** operations retain separate readable households.
- Opening delete confirmation changes no files; **Keep save** has default keyboard focus; choosing Keep or pressing Escape preserves all files.
- Explicit **Delete permanently** removes exactly the selected slot while preserving the other saves and the currently playing eight-person household.
- An unreadable local save cannot be loaded through the picker. Its explicit confirmed deletion removes only that fixture and preserves the four remaining valid saves.

The parent also supplied separate rendered menu lifecycle evidence for normal two-person households and overwrite/load/continue paths. Those images were inspected and look coherent. Its 29 state checks are useful supporting evidence, separate from the independent counts above.

## Highest-impact next fixes

### P1 — Keep long household details clear of consequential controls

The creator accepts names up to 36 characters. With eight long valid names, the picker paragraph expands through **Load selected life**. In delete confirmation, the selected title/member details expand through the permanent-deletion warning. See `menu_edges_iteration_03_initial/02_five_saves_eight_long_names.png` and `04_long_household_delete_confirmation.png`.

Use a bounded scroll area or concise member summary with an inspectable complete list. Keep the selected save title, irreversible-action warning and both confirmation controls independently readable. The live HUD also needs a bounded/ellipsized name with a full-name tooltip. Ordinary short names are not sufficient acceptance evidence.

Selecting an older fifth save reconstructs the picker at the top of the list, hiding the selected row again. Preserve scroll position or scroll the selected row into view after reconstruction. The strengthened harness checks this on the next run.

### P2 — Correct queue contrast in the actual tree

The new queue has a persistent separate × and bounded width, but its cards are still dark gray/translucent with dark text in both the reading and painting captures. Assigning `ui.theme` before calling `compact_button` did not resolve the appearance in this checkpoint. Verify the actual instantiated style, potentially applying the compact styling after the button enters the themed tree, and recapture long labels on light and dark world backgrounds.

### Continue activity and identity quality, then broaden sustained play

The new rig is a meaningful improvement, and v12 proportion studies separately look more adult with larger hands. They are not included in this v11 runtime score. Continue toward convincing hand/object contact, distinct activity transitions, expressive conversation, natural neutral eyes and less puffy shoulder/sleeve contours. Reading now holds a visible book, but this and painting still have limited motion variety.

Two-letter household chips can be identical for several names; tooltips recover identity, but portraits or a more distinguishable fallback would make multi-person control easier. Complete public testing of the face sliders and broader appearance combinations.

The requested family/aging experience, richer building/landscaping, social/career consequence variety and sustained multi-day play remain the largest breadth limits. These cannot be closed by a more favorable screenshot score.

## Decision and verification limits

**Accept the neighborhood/rig/named-save milestone with material limits; keep iterating.** This review covers one home remodel, three public venues, one daily decision, named saving/loading, eight-person selection and a targeted seated activity. It does not certify every physical button hit target, every story/social/career branch, all face sliders, eight-person autonomy, extensive routing/build combinations, several-day economy, family/aging, audio, distributable exports or other devices. The earlier two-person review separately exercised overnight autonomy and cooking/shower/social/sleep; those activities should be recaptured with the new rig before claiming the old verification fully carries forward.
