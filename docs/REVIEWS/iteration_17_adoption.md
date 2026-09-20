# Iteration 17 — school-age adoption

**Independent verdict: accept this bounded adoption implementation for integration. Full-game quality remains 7.2/10.** The phone now lets an eligible household review three original school-age candidates, choose one or two adult guardians, cancel without changing the household, or confirm one ℒ1,000 adoption. The child physically arrives, becomes selectable, retains real family links and joins the existing school/homework system. This is one family-growth path, not complete lifecycle or reference-game parity.

## Reviewed evidence

- **Combined oven/adoption public flow:** `dist/test-work/justlife-playthrough-7xi52qo_`, **75 first-process + 59 fresh-process checks**, both exit zero with clean logs. I inspected the harness, terminal state, school telemetry and screenshots, and verified all 294 recorded source hashes. The declared fixture disables autonomy before the checkpoint and grants the guardian Cooking XP 450 to unlock harvest bake. The ensuing phone, candidate, guardian, cancellation, confirmation, selection, save/load and activity choices use public controls and ordinary frame processing; clock, position and paid-progress values are not fabricated.
- **Existing paid work is preserved:** adoption occurs during the guardian's actual harvest-bake loading phase. Canceling the review and appending the child preserve paid elapsed time 18.2485653 and the full body/tray/joint transforms, with zero maximum joint-transform error. A paused named save made during the child's actual short arrival walk restores in a fresh process with the child selected and the guardian still at paid elapsed 19.4389393, again with zero maximum joint-transform error. Door state and exclusive held/interior dish ownership survive. The previously queued reading instruction remains; actual callbacks then finish the guardian's cook, serve, eat and read, the child's arrival and its separate reading. Confirmation charges ℒ1,000 once; neither arrival nor restart charges it again.
- **Real new-member routine:** autonomy resumes overnight. The child departs for the next due school day, records one on-time attendance with no phantom missed day, physically returns at approximately Day 2 15:09, and completes a new current-day homework assignment. Final state at Day 2 16:37 has `attended=1`, `missed=0`, `late_minutes=0`, `homework=2`, `last_homework_day=2`, and empty child action/away state. The earlier overnight homework alone cannot satisfy this final gate. The final child remains unsettled with fun around 20.64; this is not evidence that all needs or autonomous schedules are polished.
- **Family presentation:** the reviewed parent and child family views show Morgan→Taylor and Morgan+Jamie→Wren as distinct directed connections, with correct Parent/Parent/Sibling labels from Wren's view. Separate ports and outlined curves remove the prior false common junction. These four-member views do not establish readability of every possible eight-member/multigeneration arrangement.
- **Controlled merged-source checks:** `adoption_initial.log` **122/0**, `adoption_arrival_initial.log` **18/0**, `oven_controller_initial.log` **69/0**, all clean. I reviewed their source/logs. Coverage includes transaction atomicity, retained action identity, duplicate receipt defense, malformed history/arrival metadata, legacy optional queues, capacity/funds/calendar boundaries, blocked arrival/rerouting, cancellation and synchronous later-action routing. These are controlled tests; they do not replace rendered movement evidence. Earlier independent adversarial probes reproduced and then verified rejection of unrelated-action adoption metadata and history lacking its explicit family graph.

## Actual small-window follow-up

The two images named `*_960` in the combined run are **1440×900 logical captures**. Their earlier small-window qualification is explicitly rejected; they cannot establish physical 960-pixel readability.

The final focused public UI run is `dist/test-work/justlife-playthrough-w4s0u5c3`: **43/0**, exit zero, clean import/runtime logs. Root Window size, native client size and saved image dimensions each assert **960×600**. I verified its 294 source hashes and viewed both actual-size images. Larger, darker candidate traits, the optional-guardian caption and the complete three-line review explanation are readable without clipping; candidate choices, selector, fee, cancel and confirm fit. Public cancellation preserves the full household and paid oven pose. The tiny decorative caption and existing background HUD remain small; this is adoption decision-text acceptance, not general small-window accessibility certification.

Only `adoption_flow.gd` typography/contrast differs from the combined gameplay run: subtitle/body 16→18, traits 12→16 with darker text, optional-guardian caption 13→17. No payment, routing or state logic changes. The complete combined flow was not repeated after this presentation-only adjustment.

## Final source identity and limits

The final focused source matches the private integration candidate. These four runtime files are unchanged from the 75+59 combined flow:

| File | SHA-256 |
| --- | --- |
| `scripts/adoption.gd` | `20267c692e6acec225a920e2eaa08811a50ac4c28767781d39c432f0f72205d7` |
| `scripts/household.gd` | `8874f132f825572dea51d1a60a6884107555e246ae05f6dc4ada6591434b506f` |
| `scripts/life_sim.gd` | `ff65b774eedd4513bafbf094313d1983a11f9b0c18373dbe88796f5eb16a8f89` |
| `scripts/main.gd` | `82ed2f8adb8bc9c0a950ad9347729190923a266505776dc5c5ca2e97d3890bbd` |

Final `scripts/adoption_flow.gd`: `cd6e7a9e4994afbf2e4723f2d175756123b57fd782e59249ec2250cd6d2e10c9`. The merge preserves the b4d4b32 oven actor, world, meal-flow, sequence module and production models; no hair study is included.

The earlier `justlife-playthrough-a8lsplr3` remains **56/0 first stage, 44/1 resume** with an unexplained school-return timeout. Its old harness lacks terminal clock/route evidence. Neither the clean exact-checkpoint replay `qg8d72su` nor this combined run explains or fixes that failure. The combined diagnostic retains the same 60-second gate and observes a successful return in 7.985 wall seconds / 8.023 engine process-delta seconds; those are different measurements, not performance certification.

This review does not establish multiday school robustness, collision-free arrival through crowds, every household layout, a packaged release, infant/toddler care, births, death/inheritance or move-out family persistence. Character appearance and social acting remain major full-goal gaps. The bounded feature adds a useful family transition without earning a new full-scope score.

## Packaged-release addendum

The subsequent root-run Linux package probe completes **45 checks with zero failures**, using Forward+ on the recorded NVIDIA GeForce RTX 5090. I inspected its clean import/export/runtime logs, new probe diff and actual `03c_adoption_review.png`. The panel displays the eligible guardian, optional second guardian, fee and complete explanation without clipping. The added probe checks three available candidates, an enabled review confirmation, unchanged household/funds after cancellation, and successful image capture. It does **not** confirm an adoption, walk the child home or repeat the school/save scenario inside the executable.

Receipt: `art/screenshots/adoption_iteration_17/packaged_release`. I verified all **104** recorded runtime/asset hashes against both the current shared source and frozen `dist/build_snapshots/justlife-release-yydns02g`; all **46 GLBs** remain unchanged from b4d4b32. Canonical `dist/JustLife/JustLife.x86_64` SHA-256 matches the manifest: `d203754c76e72fae1544a80571684e4038c7fd5126bb8f9208ebed76f4c2afc0`. The release-probe script is `d07631f48f495d23ffa03a3416f611c64636a93219b42621c6fc0c4c5891f9d6`.

This establishes the recorded executable's bounded launch/UI/save-library smoke test and adoption-review cancellation behavior. It does not expand the earlier gameplay evidence into full packaged-game certification or change the 7.2/10 full-game score.
