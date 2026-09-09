# Test guide

Run commands from the project root with Godot available on `PATH`. Use an existing local `TMPDIR` when temporary storage is limited; `dist/test-work` is ignored build storage. The maintained runners create isolated project copies and private save/user-data folders. Read each runner's options before using a fixture directly.

| Area | Runner | Scope |
| --- | --- | --- |
| Construction, stairs and household ownership | `python tests/run_regressions.py --group architecture --group build --group protection` | Controlled state, routing and transaction checks; [groups and fresh-process cases](REGRESSIONS.md). |
| Public two-storey flow | `python tests/run_public_twofloor.py` | Creator, construction clicks, upstairs activity, named restart and car travel. |
| Sanitation across floors | `python tests/run_sanitation_levels.py` | Wet-patch support, stair custody, named restart and car travel. Add `--capture` for separate rendered picking/paused-mop checks; `--only v2` or `--only car` narrows the run. See [the contract](../docs/SANITATION_API.md). |
| Household and neighborhood | `python tests/run_playthrough.py --suite home` or `--suite neighborhood` | Rendered directed play and fresh-process persistence. |
| Recipes and crowded dining | `python tests/run_playthrough.py --suite recipes` or `--suite meal_placement` | Meal selection, serving, leftovers, furniture edits and paid-action restart. |
| Oven preparation | `python tests/run_oven_playthrough.py` | Loading, closed baking, two paused fresh-process saves, one ingredient charge and later queued reading. |
| Adoption | `python tests/run_playthrough.py --suite adoption --adoption-oven --timeout 300` | Public adoption during paid cooking, mid-arrival restart, school and homework. Add `--adoption-ui-only` for the focused 960×600 candidate/review/cancel flow. |
| Save previews | `python tests/run_save_preview.py --capture` | Same-frame panel cancellation, direct save, public save-as-new, overwrite and deletion. Omit `--capture` for headless state checks; image freshness requires the rendered run. |
| Household calendar | `python tests/run_calendar.py --capture` | Read-only school/work/birthday forecasts, eight-member phone flow, filtering, scrolling, queued-action preservation and pause restoration. Captures include a native 960×600 window. |

Rendered fixtures require a display. Some grant skill XP, set needs, disable autonomy or invoke public button callbacks directly. They exercise the stated paths, not unscripted whole-game play or a general quality score. Individual assertions are not additional gameplay scenarios.

The exploratory `--suite dense_meals --timeout 900` retains a known late-dinner checkpoint failure. Read [the dish-placement review](../docs/REVIEWS/iteration_14_dish_placement.md) before interpreting its results. Later repairs and their narrower evidence remain in their respective reviews. Logs, screenshots, traces and manifests are local evidence; failures and warnings must remain visible when reporting a result.

[Release verification](../docs/RELEASE_VERIFICATION.md) records actual exported-binary checks and separates them from source tests. [Independent reviews](../docs/REVIEWS/) record acceptance decisions and remaining visual or behavioral limits.
