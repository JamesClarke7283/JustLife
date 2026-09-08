# Independent review — life settings, birthdays and garden correction

Review date: 8 September 2026. **Bounded milestone accepted; full-request score retained at 7.0/10.** The new controls and corrections work in the exercised flow. Broader ages, schooling, parenting and long-term progression are not inferred from this checkpoint.

## Frozen build and evidence

The source is `/tmp/justlife-lifecycle-source-z7xb46x4`: current stable main/world/household/lifecycle and promoted v16 models, with the explicitly designated stable `life_sim.gd` from `/tmp/justlife-household-integration/scripts/`. Concurrent education integration and unfinished child/teen/elder artwork are excluded.

`tests/test_lifecycle_playthrough.gd`, run with `tests/run_playthrough.py --suite lifecycle`, produced **97 first-process and 44 fresh-process passing checks**, with **zero engine/script errors**. All 141 checks used the real Forward+ renderer in the isolated `/tmp/justlife-playthrough-9_11ux10` project with private save data. Evidence, 11 screenshots, logs and source/model hashes are preserved in `art/screenshots/lifecycle_iteration_06/`.

The harness invokes production UI signals and lets the application process actual movement and activities. It does not teleport the Lifelet to the birthday destination or force an age transition. These are callback and gameplay checks, not exhaustive mouse/keyboard accessibility certification. Audio is disabled.

## Verified behavior

Three young-adult Lifelets moved into Willow Cottage, with Ari's partner Bea and sibling Cy configured through Connections.

- Life settings exposes Short, Normal and Long, plus Automatic birthdays. Opening it pauses the household. Editing Long/off then Cancel preserves the existing Normal/on settings and restores the prior speed.
- Apply changes all three members. Short/off and Long/off both work. Disabling automatic birthdays allows the clock to run while fractional age stays unchanged. Changing lifespan preserves that existing progress. Opening settings from pause returns to pause.
- My Lifelet displays the current age and paused-aging state. Keep this age preserves the profile, funds and queue.
- Confirming Celebrate queues the birthday. While paused, neither age nor money changes. At normal speed, Ari walks to the fridge and pays exactly 30 when the activity starts. Age remains Young adult while it runs.
- Actual completion advances Ari to Adult, refreshes the actor profile and HUD, records exactly one adjacent-stage birthday, and retains traits, skills and relationships. The other two Lifelets remain young adults.
- A named save and fresh-process load retain every member's age, fractional progress, lifespan, automatic-aging setting and birthday history, alongside the previously checked consequential household state. The public settings panel shows the restored Long/off values and My Lifelet shows Adult.
- People and All relationships now share the same order: partner, sibling, then acquaintances. This order remains the same after named-save serialization and a fresh restart. The inconsistency from iteration 05 is corrected.

## Rendered assessment

The settings and birthday dialogs fit cleanly at 1440×900. Explanatory text, choices and buttons remain distinct, and the personal panel communicates the age change.

The garden correction is convincing. A close in-world inspection shows stems reaching the lawn, leaf pairs and recognizable flower heads. The old floating peach/cream capsules are gone. The scene contains 24 plant clumps across the two front beds. The close plant view is an inspection camera, while the ordinary home screenshots show the correction at gameplay scale.

Two concrete refinements remain:

1. **Give birthdays visible presentation.** During the active birthday Ari stands at the fridge with an idle pose. There is no visible celebration or birthday prop in this checkpoint. A distinct gesture/event sequence and an appropriate location would make the meaningful state transition feel like an occasion.
2. **Correct the birthday sentence.** The dialog currently says “become a adult.” Use “an adult” or wording that works for every stage.

This pass does not exercise an automatic birthday after several elapsed game days, creation or furniture use by children/teens/elders, school attendance, parenting or a complete generational story. Developer tests and staged renders for those areas are useful supporting work, but they are outside this independent runtime result. The lifecycle control foundation is accepted without claiming the full family/aging pillar is finished.
