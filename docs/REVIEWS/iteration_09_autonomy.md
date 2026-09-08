# Independent review — seven days of household autonomy

8 September 2026. **Current full-request score: 6.7/10.** Sustained play exposes a severe resource-starvation defect that the previous focused flows did not reveal. Four of eight Lifelets stop completing actions by early Day 2, wait for the same bed for the remainder of the week, and remain at zero in all six needs. The previous **7.2/10** in `iteration_08_final.md` is retained as the historical focused checkpoint; it is superseded by this broader observation. Proposed fixes receive no credit until a new rendered week verifies them.

| Dimension | Weight | Score | Evidence and implication |
|---|---:|---:|---|
| Visual and character quality | 20% | 6.6 | The repaired v18 characters and grounded activities remain improvements. Persistent overlapping waiting bodies and tiny overlapping speech text make a busy household harder to read. Hair and expression limitations from the previous review remain. |
| Usability and flow | 15% | 7.4 | Eight portraits, needs, pause/speed, named save/resume and the school record remain usable. “Waiting for Sleep” describes the immediate state but offers no useful explanation of indefinite contention or why an empty sofa is ignored. |
| Simulation and interaction depth | 25% | 6.0 | A four-member subset keeps living while the other four cannot finish an action for 148–153 game hours. Autonomy neither grants fair shared-object access nor reconsiders the blocked bed against critically depleted other needs. Responsibilities and social target choice are also shallow. |
| Creative breadth and sustained play | 25% | 7.1 | Existing ages, family tree, homes, construction, travel and directed school/story systems remain present. The new week adds evidence, not content; its limited autonomous activity variety does not establish a rich long-term family experience. |
| Reliability and delivery | 15% | 6.6 | Consequential state survives a fresh-process midpoint load, and no non-waiting navigation stall was measured. That reliable persistence also preserves the starvation. The actual week finishes, but it is not a clean product acceptance. |

Weighted mean **6.695**, rounded to **6.7**. The original full-request rubric and weights are unchanged. The objective remains open.

## Frozen reproduction and evidence

Accepted release input: `/tmp/justlife-release-family-v18-ohzzzlzd`. Critic source copy: `/tmp/justlife-autonomy-source-dtw3qs33`. Executed isolated project: `/tmp/justlife-playthrough-pfkvqksr`. No production code was edited for this audit. Exact executed script/model hashes, harness copies, reports, logs, screenshots and the complete sampled trace are preserved in **`art/screenshots/autonomy_iteration_09/baseline/`**.

The public creation flow made eight Lifelets spanning Child, Teen, Young adult, Adult and Elder, with a grandparent, parent, co-parent/partner and shared-parent siblings. Appearance and age varied; the test retained the creator's default Maker/Creative/Outgoing/Foodie behavioral choices. It moved them into the unchanged **Willow Cottage, advertised as one bedroom/one bathroom**, with one bed, one computer and §2,500. Autonomy was enabled. Public fast speed ran from **Day 1 08:00 to Day 8 08:00**, with an actual named save, process exit and fresh load at **Day 4 08:00**. The harness did not jump the simulation clock, teleport arrivals, fill needs, add funds or force action completion.

This household deliberately exceeds the starter home's comfortable capacity. That explains contention; it does **not** explain granting the same subset repeated bed turns while others wait almost an entire week, nor ignoring usable nap furniture and other critical needs. A comfortably furnished eight-person control would be additional coverage, not a reason to dismiss this default-flow failure.

The trace samples each member approximately every 15 game minutes, including needs, full queue, approach/wait state, route index and world position. Completion events record member, action, target and simulation time. Daily screenshots show the member with the lowest aggregate needs. `audit_resume.json` contains the combined week; `audit_summary.json` and `members.csv` are derived with `tests/summarize_autonomy.py`.

## P1 — indefinite shared-bed starvation

| Lifelet | Age | Completed actions | Total waiting hours | Last completed action time | Hours without a completion at finish |
|---|---|---:|---:|---|---:|
| Morgan Reed | Adult | 63 | 9.57 | Day 8 07:08 | 0.86 |
| Casey Vale | Adult | 61 | 28.66 | Day 8 05:31 | 2.48 |
| Robin Reed | Child | 58 | 34.71 | Day 8 04:19 | 3.68 |
| Ellis Reed | Elder | 50 | 13.23 | Day 8 01:06 | 6.90 |
| Avery Reed | Teen | 4 | 157.43 | Day 1 23:15 | 152.75 |
| Jamie Reed | Young adult | 4 | 159.51 | Day 2 00:46 | 151.23 |
| Taylor Reed | Child | 4 | 160.02 | Day 2 02:15 | 149.74 |
| Parker Reed | Child | 4 | 160.07 | Day 2 03:45 | 148.24 |

The final four all retain `sleep`, phase `approach`, target **`item_16`**, at **`(3.25, 0.16, 3.0)`**. All six needs first register exactly zero at Day 3 02:51 for Avery/Jamie/Taylor and Day 3 03:22 for Parker, then remain zero in the subsequent samples through Day 8. None finishes a sleep or chooses a nap. There are **25 completed sleeps and zero completed naps** across the whole household.

The bed completion order repeats **Morgan → Ellis → Casey → Robin**: on Day 2 at approximately 01:46, 07:47, 13:48 and 19:48, followed by the same order on Days 3–7. The bed is functioning. The frozen controller admits work based on active occupancy without an arrival-based waiting order; the fixed member update order repeatedly favors earlier entries. Frozen `life_sim.gd` chooses energy candidates in the order `sleep`, then `nap`, and a queued blocked approach does not revisit the selection. Together these observations explain the service starvation. All members' measured maximum **non-waiting stationary approach time is zero**, so this is not a measured pathfinding deadlock.

Midweek save/load preserves the queues, paid progress, positions, family and other consequential state exactly under the existing comparison checks. Starvation resumes unchanged. Funds grow to **§7,978**, excluding inability to afford food as the cause.

**Acceptance:** the same rendered seven-day fixture must let every member continue completing useful actions; no member may go a full game day without a completion while usable recovery objects exist. Record waiting order and alternative choices, and verify that loading preserves fair priority. Add a controlled queue case showing late arrivals cannot repeatedly overtake older waiters. Reconsider critically depleted other needs without discarding explicit player-directed work indiscriminately.

## P2 — waiting characters occupy the same point

At least four indefinitely waiting Lifelets occupy the identical bed approach coordinate, producing a merged body cluster at the foot of the bed. At the final sample six members share that navigation coordinate, although an active sleeper's visual anchor offsets their rendered body; six coincident navigation coordinates must not be confused with six identical rendered poses. Day 4's image shows the waiting cluster, overlapping speech labels, an empty sofa, and Avery's six zero needs beside “Waiting for Sleep.”

**Acceptance:** a contested object should expose distinct waiting positions or another clear spatial/queue presentation, preserve individual selection, and release positions after cancellation or target removal. Test a crowded scene from normal live camera angles, not only close actor renders.

## Sustained-play limitations

All four school-age members finish with **zero classes, zero homework assignments and five missed days**. The school record's Grade D/0% attendance is consistent with what happened; this audit did not find a calendar or grade corruption. Robin, who continues completing need-recovery actions, still never attends school. The frozen autonomy routine selects need actions and does not schedule classes, homework or employment. This is a missing responsibility behavior relative to the requested household experience; directed school flows from previous reviews remain valid.

Completed activity variety is narrow: **74 snacks, 46 friendly chats, 45 toilet uses, 33 paintings, 25 sleeps and 25 showers**. No cooking, naps, reading, television, relaxation, school, homework or job actions complete. Of 46 friendly chats, **44 target `player` and two target `housemate_1`**, showing a strong stable-order bias. Painting income keeps growing while some members are inert. Several adults retain the first fresh-meal want because snacks do not satisfy it; this is an autonomy/progression mismatch, not a claim that the want's directed completion is broken. Three story choices are pending by the end.

**Acceptance:** after basic fairness is fixed, give responsibilities and relationship variety a coherent autonomous policy, with readable priorities and player override. Verify missed/attended school days and learning outcomes across a week, and demonstrate more than repeatedly selecting the first viable action/relative. A shared homework interaction in development is not counted as implemented or accepted by this frozen review.

## Verification limits and next gate

- First process: **127 checks, zero failures**. Resume: **114 checks, two harness failures** after the seven-day simulation and save comparisons completed. The inspection helper looked for exact button text `Stories`, while the UI correctly displayed `Stories · 3`; its subsequent `Back to life` lookup therefore also failed. `run_results.json` honestly retains exit code 1 and these two errors. The image named `day_08_unattended_stories.png` is the HUD, **not** an inspected Stories modal. The final family-tree capture is valid.
- The shared future harness now matches the Stories prefix and adds the missing no-completion-for-a-day quality assertion. The executed historical harness copies are retained. The baseline trace already fails that derived quality gate for four Lifelets; a redundant full rerun solely to change inspection text would add no evidence about the defect.
- Observed process-frame samples have median **19.44 ms**, 95th percentile **35.19 ms** on the available desktop with other work active. These are incidental 1440×900 Forward+ measurements, not a controlled performance or hardware compatibility benchmark.
- No new independent packed-binary, perceived-audio, smaller-window or comfortably provisioned eight-person acceptance is implied.

The next three priorities are **fair resource access plus blocked autonomy reconsideration**, **legible distinct waiting behavior**, and **responsibility/social policies that sustain a family over several days**. Character and catalogue improvements from the previous review remain worthwhile, but the known starvation is the immediate product blocker. Retain this frozen baseline and compare a controlled candidate against the same trace metrics before revising the score upward.
