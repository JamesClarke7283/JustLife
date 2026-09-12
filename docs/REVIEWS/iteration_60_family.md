# Iteration 60 — family, bodies and honest paths

12 September 2026. Build from the working tree at commits `30c946a`, `0ed78d4`, `e5c063b`, `aaf7796`, `045c9e4`, `b484128`, `97dad05`. Reviewed with headless suites, the rendered two-floor suite, the rendered neighbourhood suite, the rendered family probe and the frame probe.

| Dimension | Weight | Score | Movement and evidence |
|---|---:|---:|---|
| Visual and character quality | 20% | 8.0 | The flat paddle hair locks became rounded tapered tubes across every family (Bob/Long/Waves × adult/child/teen/elder, 144 meshes) and the hood cowl seated onto the shoulders, closing the black sliver gaps visible in every frontal view (`evidence/hair60/`, 80 before/after captures). A new original baby family joins them: rounded infant forms in the same matte style, crawling on hands and knees at 0.55 m (`evidence/baby60/`, `evidence/family60/08_baby_crawling.png`). |
| Usability and flow | 15% | 8.0 | Pressing **Upper** in Build & buy with no slab now starts the Floor tool itself and explains the two-opposite-bearing-walls rule; an unsupported rectangle names the fix, and a purchased upper floor invites the Stairs step. The second-storey walkthrough is in the player guide. Bed sharing, Try for Baby, the pregnancy countdown moodlet and the baby creator all read through the ordinary menus. |
| Simulation and interaction depth | 25% | 8.3 | Partners sleep on the two halves of one bed and outsiders are refused it. Try for Baby conceives a three-day pregnancy that survives save/load and birth resolves through the household clock, opening the baby creator. Residents now keep the shared body gap everywhere they walk and yield aside when a member is held up; walkers that meet furniture the planner wrongly called walkable learn the edge and detour. |
| Creative breadth and sustained play | 25% | 8.0 | Catalogue 39 → 42 (storybook reading nook, teatime coffee table, reading arc lamp), and the household can now grow a new life stage end to end: partner → bed sharing → Try for Baby → pregnancy → birth → named baby → crawling → child. |
| Reliability and delivery | 15% | 7.8 | The rendered neighbourhood suite went from 13 runtime errors to 0 (plus a clean resume stage) after the travel-stall fixes; the two-floor suite is 3/3 stages with 0 problems; 12/12 resident suites pass. Frame pacing is unchanged and still misses the 33 ms p95 budget on heavy frames — measured honestly below. |

Weighted mean **8.0** (iteration 59: 7.6).

## What was fixed, and what it cost

- **Body clipping and stalls (user-reported three times).** Residents moved with raw `move_toward`, walking through the household; they now use the same `_step_clear` gap test as everyone else, abandon an occupied waypoint, yield one body-width aside when a member's live route is held up, and the bare-lot boarding walk refuses steps into a gap. Members' own anti-deadlock valve (squeeze through a body) now tries a real detour around the body first, so open-floor encounters never overlap.
- **The endless studio trip.** A boarder whose route detoured around the whole building because the doorway was crowded stayed in boarding for 333+ seconds. Boarders now re-plan when they stop making straight-line progress, and a one-minute watchdog puts anyone still out into the car so a transition can never hold the household hostage. Root cause of the earlier misbehaviour: the structure-learning branch I added treated courtesy refusals as structure refusals and looped; it now only learns when walls or furniture genuinely refuse while bodies do not.
- **Pathfinding (user: "maybe improve pathfinding so they don't get stuck").** A refused step now penalizes the graph edges under it for 45 seconds and the next route detours around the corridor (`tests/test_route_learning.gd`: 14.36 m → 16.80 m → restored). This is what stops a Lifelet pressing into a chair forever.
- **A silent engine failure worth recording.** `_activity_resources` assigned an untyped `Array` into `Array[String]`, which aborts the function at runtime with only a script error and returns `[]` — invisibly breaking every resource conflict check. This masked the bed occupancy gate and would have masked any future bed/seat work. Fixed by copying the ids element-wise.
- **Suite hygiene.** The neighbourhood suite had been stale since 8 September: it still expected instant travel from before the boarding cinematic and assumed two lane neighbours rather than four. It now waits for the arrival and counts the roster dynamically. The two-floor runner classified the engine's documented static texture finalize notice as a problem; it now records that exact notice separately and still fails on any other warning, error or failed check.

## Measurements and limits

- Frame probe (60 s, very fast, 3 runs, unchanged settings): p50 16.4 ms, p90 20.2–31.8 ms, p95 38.1–54.0 ms, p99 ~60 ms. Run-to-run spread on identical settings is ±8 ms at p95, which is larger than the deltas measured for MSAA off (p95 46) and shadow 2048→1024 (p95 38); no setting change is claimed on that evidence. The stable cost is the heavy-frame band, where the scene submits 2,600–3,400 draw calls in a frame. The remaining work is structural (per-Lifelet draw-call count), not a settings knob. The 33 ms p95 budget stays open and is reported as such.
- No rendered capture shows the cover beat from a close camera; the capture is a wide lot view with the quilt visible over the pair.
- The baby's own clothing is a romper shell; it holds nothing with a closed fist (no authored grip morphs).
- Pregnancy is deliberately simple: a moodlet countdown, no hospital trip, no player-visible fetus or gender reveal before birth.

## Verification at this revision

| Suite | Result |
|---|---|
| `test_baby_stage` | 51 checks, 0 failures |
| `test_make_baby` | 53 checks, 0 failures |
| `test_shared_bed` | 7 checks, 0 failures |
| `test_living_v60` | 35 checks, 0 failures |
| `test_second_storey_guide` | 10 checks, 0 failures |
| `test_resident_body_gap` | 5 checks, 0 failures |
| `test_route_learning` | 6 checks, 0 failures |
| `test_doorway_yield` | 10 checks, 0 failures |
| `test_actor` | 612 checks, 0 failures |
| `run_public_twofloor.py` | import 0 / public 0 / resume 0 problems |
| `run_playthrough.py --suite neighborhood` | exit 0, 0 runtime errors, resume 0 |
| `run_playthrough.py --suite home` | exit 0, 0 runtime errors |
| `run_neighborhood_checks.py` | 12/12 suites PASS |
| `probe_family60.gd` (rendered) | 11 checks, 0 failures, 8 captures |
| `probe_frames.gd` (rendered) | p50 16.4 / p90 20.2–31.8 / p95 38.1–54.0 / p99 60.3 |

**Decision: iterate.** 10/10 remains open; the frame budget and character close-up detail are the largest honest gaps.
