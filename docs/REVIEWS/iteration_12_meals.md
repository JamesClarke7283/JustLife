# Iteration 12 — shared meals

**Independent verdict: accept this bounded meal milestone for promotion, with the visual limitation below.** It improves the household loop through persistent food and distinct diners. The directional meal-gesture study scores **7/10**; the last accepted full-game score remains **7.2/10** under the unchanged original rubric. This review does not establish complete reference-game breadth or feature parity.

## What is accepted

Cooking the implemented garden skillet creates **four servings** and charges its ingredients once. The cook carries and serves a dish; household members collect individual plates and eat at different chairs. Partial plates survive named save/restart, finished portions leave dirty dishes, remaining servings can be carried to the fridge, the leftovers picker exposes their count/freshness, and washing removes the chosen plate.

The serving dish, individual plate, fork and food are original Blender assets. Editable `art/meals/garden_supper.blend`, `tools/create_meal_props.py`, the three exported meal GLBs and their manifest preserve the artwork's source. This meal-art work does not replace the existing v18 character models.

## Evidence actually reviewed

The final combined public run is `/tmp/justlife-playthrough-1bioe8v4`. I inspected its harness, first/restart reports and logs, build/meal/leftover renders, raw contact samples, and saved build checkpoints. **100 first-process checks and 26 fresh-restart checks pass**, with both processes exiting 0 and no runtime warnings/errors in those logs. These are assertions within one directed household scenario, not 126 independent play sessions.

The harness uses ordinary frame processing and public UI signals, including actual mouse placement and Escape input for furniture editing. Household autonomy is disabled and close-up cameras are set directly. Lifting then canceling the table move preserves the exact food and queue dictionaries. Committing chair/table moves retains plate identities, ownership and partial progress; normal playback reseats both diners without an extra serving or charge. Fresh restart finishes both meals, retains two leftovers, consumes one further serving, and washes only one dirty plate. The paused `09_chair_moved_plate_in_hand` image shows pending reseating; it alone does not prove walking grip quality.

I independently recomputed the **36 actual eating-frame samples**: 20 adult and 16 child.

| Measurement | Adult | Child |
| --- | ---: | ---: |
| Maximum actor-anchor / rendered-plate mismatch | 0 mm | 0 mm |
| Plate underside above imported tabletop | 2.00 mm | 2.00 mm |
| Closest fork tip to mouth | 10.89 mm | 8.58 mm |
| Closest fork tip to defined food point | 6.32 mm | 37.60 mm |

Closest distances establish reaching each target during the sampled motion; they do not certify every frame, finger, garment or utensil intersection.

The maintained self-contained `tests/test_meal_state.gd` passes **101 assertions**, exit 0, without runtime warnings/errors. Its exact test SHA is `44951441404e0b39b3d54a192cfafcbf68b074c4c78bf524c27e25b91bdc8a7b`. `/tmp/justlife-meal-state-maintained-x8punbg_/diagnostic_manifest.json` retains source hashes, test, report and log. It covers last-serving conservation, carrier/storer exclusion, seated/carried/unowned partial JSON continuation with only remaining nutrition, malformed ownership/progress/count/rotation/support rejection and atomic restore, future cancellation, expiry without completing the next painting, transport metadata and save-overwrite protection, and spoiled surface/fridge clearing. It uses controlled time/arrival and a minimal world; it supplies no renderer/navigation evidence.

The public run's `source_snapshot.json` pins all executed files. Its core matches the state-tested source (`life_sim` `18f44d4b…`, `meals` `ca7b3502…`, `meal_flow` `b0fe4f5a…`, `household` `59f92a4a…`, `world` `f553a33f…`). Later differences are the independently reviewed pending-table/UI-reference guards in `main` `f2e0b818…` and actor `ebe4623e…`; those are exercised by the public run and separate gesture study, respectively.

## Art verdict and remaining scope

I inspected all five matched baseline/revised gesture views in `/tmp/justlife-meal-gesture-37cs7mi5/evidence/`. Bent supporting elbows and hands meeting the actual platter/plate ends improve the old rigid reach. The free hand still hovers near the rim, expressions and synchronized bite timing appear mechanical, and small finger contacts remain difficult to assess. The controlled study's 1,392 samples support its contact/forearm-clearance measurements; fixed animation stepping and hidden UI do not establish public flow or locomotion quality.

**The initial reviewed study and public close-ups retained a stippled arm-like pattern around the supporting forearm and tabletop. Its cause was unresolved at that gate.** The initial claim that a longer settling capture removed it was retracted: supplied revised and settled `adults_bite.png` files are byte-identical, SHA `16c37b3d2b4c2fafe8837f06fcca2ee19405c58930353445dddc8eb00a42ea10`. That settling comparison supplies no evidence of a fix or a capture-only cause. The independent follow-up below provides the subsequent repair evidence.

Dense-household meal contention, a combined multi-day meal/school/work run, full customization extremes, and wider recipe/catalog coverage remain unverified or unfinished. Only the four-serving garden skillet's complete public loop is demonstrated. Natural spoil timing, all furniture-removal paths and every animation transition are not covered by this public scenario. These limits remain part of the original full-game goal; no 10/10 claim is earned here.

## Shadow follow-up before packaging

The critic independently accepted reducing `sun.light_angular_distance` from **3.0° to 0.5°**. Matched baseline/0.5°/0° captures in `dist/diagnostics/meal_shadow_angle_ywynvaha/` retain the same geometry, pose, camera, lighting energy, SSAO and enabled sun shadows. The conspicuous stippled second forearm/table silhouette disappears at 0.5°, while chair/table/floor cast shadows remain. The tradeoff is sharper, more pronounced sunlight; small jagged edges remain on distant wall/floor shadows. Eight directed checks pass, without runtime warnings/errors.

The 0.5° image SHA is `1d56a88cdb917126eb7f626c1a537a09c14fb84af7bf84e62e475fca133efa79`; the unchanged baseline is the `16c37b3d…` image above. The preceding toggle diagnostic retained the pattern with SSAO off and removed it with sun shadows off. This supports the sun's soft-shadow rendering as the source of the pictured pattern. It does not establish an engine defect or general hardware diagnosis. One fixed pose/camera does not prove animated stability, other camera scales/lighting or performance. The patch changes no simulation or character geometry and earns no new art/full-game score. Earlier public-run hashes remain historical; the final package manifest pins the revised world script.
