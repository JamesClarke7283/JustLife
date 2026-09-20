# Iteration 13 — recipe selection and preparation

8 September 2026. **The independent critic accepts this bounded recipe milestone for promotion.** The full-request score remains **7.2/10**, with the original 10/10 goal open. The recipe art is approximately 7/10; no full-game quality increase is claimed.

## Accepted behavior

The cookbook shows actual original dish previews, servings, price, time and skill requirements. Garden skillet remains Cooking 1, four servings, ℒ25 and 45 minutes. Herb garden pasta requires Cooking 2, makes four for ℒ32 in 50 minutes. Harvest vegetable bake requires Cooking 4, makes eight for ℒ52 in 70 minutes. Invalid, unavailable or unaffordable recipes cannot start. Ingredients are paid once on arrival, with funds checked again for queued work. Paid partial cooking resumes even with no remaining funds; saves validate recipe, cost, experience, phase and progress before changing the current household.

The original Blender source, generator and four exported GLBs are maintained under `art/recipes/`, `tools/` and `assets/models/`. Each recipe carries its own serving dish, plate and remaining portions through serving, refrigeration and eating. Pasta folds and seasons in a bowl; bake uses seasoning and a two-handed tray pose. The existing garden dish and fork are unchanged.

## Evidence

The final public run is `dist/test-work/justlife-playthrough-u1blnig1`: **57 first-process checks and 28 fresh-restart checks**, both exit 0, with no runtime errors or warnings. The critic independently inspected the harness, reports, logs and seven key images, checked all 244 frozen manifest hashes, and confirmed the promoted five runtime scripts and four GLBs match. The input helper emits the world object-click signal and presses actual menu buttons; it does not physically aim the mouse at every object. Level 4 uses explicit fixture XP, so this is not natural long-term progression evidence.

The final cookbook previews fit their rows at camera size 0.42, with readable locked and unlocked states. The bake is saved at 54.3988 of 70 minutes with ℒ2476, then resumes and serves eight without a second debit. The fridge lists three pasta portions and eight bake portions; selecting pasta consumes only pasta and uses its own plate model. The rendered screenshots demonstrate ordinary cooking, seasoning, serving and dining, while small fingers remain hard to judge at the household camera scale.

The controlled recipe suite passes **103 checks** (`dist/game-work/recipes-xh8o3g51/test_recipes_revalidated.log`). Independent malformed-save and paid-resume checks pass **12/12** in `/tmp/justlife-recipe-critic-state-_vf4iwsn`. That review first found an unpaid partial-action bypass through queued/approach phases; the rejected evidence remains, and the corrected validator rejects it atomically. Existing meal-state and autonomous-eating checks pass **101 and 45**, respectively; the latter retains two ObjectDB teardown warnings and supplies no rendering evidence.

The exact repaired art passes **32 Blender reopen and 42 Godot import checks**. The initial pasta inner shell produced visible triangular patches; the repaired single ceramic shell renders cleanly. The bake has deeper filling and an irregular top, but remains visibly constructed. The critic rated pasta 7.5/10 and bake 6.5/10 in `/tmp/justlife-recipe-critic-r2-5ahvopif/CRITIC_REVIEW.md`.

The exact actor and repaired props pass **120 preparation checks across 435 sampled transforms**, including three adult body/frame configurations, pause, transitions and cleanup. `dist/art-work/cooking-repaired-check-ve1p6zhm/` retains source hashes and evidence. The bake's higher Food target is followed without an actor change; measured maximum shaker-axis error is 1.705°, with 9.001mm tray grip offset. These sampled bounds/segment tests do not prove full mesh collision freedom or natural acting. Before committing, the maintained preparation harness was changed to write under `user://recipe_preparation` and rerun against the final sanitized build source: 120 checks pass, with two ObjectDB teardown warnings retained. The 103-check recipe suite also passes again with a clean log. Final logs are in `art/screenshots/recipes_iteration_13/final_harness/`.

## Limits and retained failures

The oven does not open or perform insertion/removal, and preparation uses already-cooked-looking food. Ingredient inventories, gardening, cooking mishaps and wider recipes remain unfinished. Character acting and the wider wardrobe/build catalogue still fall short of the request.

The first two public attempts are retained at `dist/test-work/justlife-playthrough-j4b633lk` and `dist/test-work/justlife-playthrough-8023h7vd`. They exposed an oversized preview and two harness mistakes: passing minutes to a normalized-progress predicate and comparing decoded JSON numbers to GDScript numeric types without normalization. A load diagnostic overwrote the second run's resume report; its original runtime log and aggregate failed result remain. The final independent run above passes after the documented corrections.

A separate three-day, eight-member baseline (`dist/test-work/justlife-playthrough-lfkuzc0s`) completed all due school/work attendance and consumed all 16 servings, but exposed floating standing plates, overlapping dishes and no autonomous washing. Its first stage passed 156 checks; eight restart assertions were over-strict about controller-rebuilt queue phases. A load-only diagnostic passed 46 checks. This baseline is limited evidence, not an accepted dense-household milestone. The subsequent private placement patch is excluded from this commit: review found an orphaned carried plate during autonomy replanning and incomplete footprint support near walls/floor edges. Those fixes require their own integration gate.

The maintained package record in `docs/RELEASE_VERIFICATION.md` identifies the exact executable separately from the historical public-flow evidence.
