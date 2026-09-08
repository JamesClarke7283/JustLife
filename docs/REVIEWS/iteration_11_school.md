# Iteration 11 — independent off-lot school candidate review

**Decision: reject this exact candidate for promotion.** Its directed school departure/save/return path works in the inspected fixture, but the completed household week regresses into severe autonomy starvation and household insolvency. A successful single school trip cannot outweigh that sustained-play failure. The accepted production full-request rating remains **7.2/10** under the original rubric; this unpromoted candidate earns no production-score credit and does not approach 10.

This report records a completed failed experiment, not an unfinished run. Subsequent repairs require new frozen evidence and must not overwrite the meaning of the rejection below.

## Exact evidence

The directed fixture `/tmp/justlife-playthrough-x6o5_r0i` and full weekday fixture `/tmp/justlife-playthrough-_zn0wt4a` have matching relevant product files, independently hashed against their `source_snapshot.json` manifests:

| File | SHA-256 |
| --- | --- |
| `scripts/life_sim.gd` | `fd00d9a0686eeb97d231ff7b5052699912de9fef7d935ee583accfa2434b95bd` |
| `scripts/main.gd` | `c712fa101eaa98ad2872a29f0bda2a02d200795ecfbc76a80bc89774239fd411` |
| `scripts/world.gd` | `d51f3459fb5edcae799e3354cb6891ef7b8d37c473de6f93b275e50d1f897cd7` |

The executed directed harness SHA-256 is `49ee3e3349d7aef68a151e4bc0da976d9b63318b5f6c2a7f5de069bd9173b997`; the week harness is `7eed9d9e6d2117f0d795efd298d1c6daa57c9485f7ce7c3ee04994dc1d5a8af0`. The critic inspected both harnesses, relevant controller/simulation/world code, school completion and save validation, both directed result/log files, and the week's raw `audit_resume.json`, derived summary and result/log files. These are author-run rendered fixtures independently examined by the critic, not an unscripted critic playthrough.

Directly viewed the corrected directed fixture's six `art/offlot_school/05_walking_to_school.png` through `10_early_return_home.png` images, and the failed week's `art/autonomy_week/day_08_lowest_needs.png`. An earlier candidate's away screenshot was inspected for context but is not substituted for the exact corrected fixture. Static images support visual claims; source, executed harness and recorded states support the behavior claims.

## Directed trip: demonstrated behavior

**48 first-process and 42 restart checks pass**, with no warnings or runtime error lines in those directed gameplay logs. Public creation makes a child/adult household. The school button queues departure before the child is away; actual movement reaches the registered sidewalk point around 08:25 before hiding the actor. The child is then excluded from home social targets and its pick collision layer is zero. The adult remains visible at home.

The named save retains the exact school phase, departure time, exit, expected 15:00 return and unrewarded education state. Fresh-process load leaves the child away with no phantom home body. Ordinary accelerated frame processing reaches 15:00 and records attendance once before the physical return walk. The child reappears at the sidewalk, walks into the front garden and becomes a home interaction target again. The arrival emits one completed `school_day`, without a second attendance reward. The normal branch ends with attendance 1; the independent early-return branch reloads the saved morning, uses “Come home early,” walks back, and ends with attendance 0.

The costs of the day are meaningful in this fixture: the child leaves with approximately 83.7 energy and 60.7 fun, and arrives home with 46.5 energy and 24.5 fun. Hunger ends near 64.9 and bladder near 77.4; school provides some food/bathroom/social recovery while normal need decay continues. This verifies one directed starting condition, not that the autonomous preparation policy keeps a full household healthy.

The selected pupil's HUD clearly names the school, says “At school · Back 15:00,” disables home homework while away and changes to “Coming home from school.” Early return explicitly warns that attendance was not earned. This is a useful original foundation for off-lot responsibilities.

## Completed week: blocking regression

The week reaches **Day 8 08:00**. First process: **127 checks pass**. Restart: **166 checks, 11 failures**. The failures are explicit harness quality assertions, including useful-action starvation, prolonged stationary routing, missing adult work and incomplete school attendance; they must not be described as a clean passing run merely because the application kept rendering. The logs show these assertion errors, rather than a separate script exception being used as the explanation.

The critic independently recomputed completion counts and maximum gaps from **385 raw completions and 660 sampled states**, and compared the final education/career/needs state with the summary:

| Member | Useful completions | Longest gap | School attended / missed | Homework | Completed job shifts |
| --- | ---: | ---: | --- | ---: | ---: |
| Morgan Reed | 23 | 107.00 h | — | — | 2 |
| Casey Vale | 16 | 119.64 h | — | — | 0 |
| Robin Reed | 62 | 11.27 h | 1 / 4 | 3 | — |
| Avery Reed | 57 | 8.66 h | 2 / 3 | 3 | — |
| Jamie Reed | 56 | 9.77 h | — | — | 0 |
| Taylor Reed | 62 | 9.90 h | 1 / 4 | 4 | — |
| Parker Reed | 53 | 10.02 h | 2 / 3 | 2 | — |
| Ellis Reed | 56 | 12.05 h | — | — | 1 |

The final wallet is **§0** and **all eight members have hunger 0**. Morgan and Casey finish with **all six needs at 0**. The inspected Day 8 screenshot visibly corroborates Morgan's empty needs and the empty wallet. Several other members still complete actions, so total activity count conceals the collapse; per-member and per-need gates remain essential. By comparison, the accepted iteration 10 week had no sampled critical-need hours and a maximum useful-completion gap of 12.38 hours.

The implementation owner identified urgent-action replanning as a cause. Independent source inspection supports a specific mechanism to investigate: `_reconsider_active_autonomy()` can cancel an active recovery because another need is urgent, then the general chooser can select the same lowest-need recovery again. Raw Day 4 samples show Morgan repeatedly on `snack`, active with **elapsed 0**, while hunger is 0 and energy falls from about 70.5. The critic has requested verification of repeated food charging during those restarts. That financial causal chain is not yet proved by a charge ledger; the observed lost progress, §0 outcome and starvation are established regardless.

## Required repair and next acceptance evidence

1. **P1 — stabilize autonomous recovery and costs.** An active need-recovery action must be allowed to produce progress rather than continually restarting. Reconsideration should choose a materially better feasible action and preserve player plans. Verify a controlled two-urgent-needs case reaches recovery, pays only intended costs, and cannot loop forever through cancel/requeue. Then repeat the same healthy eight-member week with the existing starvation/waiting gates intact. Explain the wallet from real charges and earnings; do not conceal collapse with free need resets or silent wages.
2. **P1 — deliver sustained attendance and workable household responsibilities.** Each healthy pupil must actually attend all five elapsed weekdays and still recover after school. The rejected 1/2/1/2 attendance result does not meet that condition. Homework and adult earnings must remain viable under the same furniture constraints. Diagnose preparation, departure-window and resource contention together. Adult work remains a remote desk activity; even a repaired `job` count will not establish off-lot career fidelity.
3. **P2 — finish the control/presentation details.** Replace “Walking to Go to school” with a natural departure label. Remove the returning queue's ×/cancel promise when cancellation is disabled or a no-op. Update travel copy that currently says the whole household travels and clears activities, since away pupils now retain their sessions. The directed fixture proves the adult stays visible but does not switch to that adult, complete or queue a home action, and switch back while the pupil is away; supply that short control check. Preserve the already accepted speech overlay when integrating this older candidate and use a school-specific return phrase.

A source-only edge was also sent to the implementation owner for reproduction: age advancement runs before away completion in `_step`. An automatic birthday exactly as the clock reaches 15:00 may request an early return whose `ended_at` is at/after the scheduled end, while the save validator rejects an incomplete return at that timestamp. This is an **unverified boundary concern**, not a claimed observed save failure. Resolve it with a focused boundary check before broad save/age acceptance.

## Remaining scope

Away study/social-effort choices, richer school events and progression, coherent off-lot careers, broader child/family routines and character/art/catalogue quality remain incomplete. The candidate does not provide a playable school venue. This review also does not certify household travel during absence, saved return walks, blocked-return recovery, every age/window ratio or a packaged build unless separately demonstrated. Source contains paths for several of those behaviors, but implementation presence is not execution evidence.

**Continue iterating in isolation.** Preserve the successful directed trip as a focused capability and the failed week as a regression record. A future passing week must demonstrate recovery, attendance and finances together before this responsibility candidate can replace accepted production.
