# Iteration 14 — supported dishes and idle spacing

8 September 2026. The independent critic accepts this bounded production repair. The full-game score remains **7.2/10** and the original 10/10 goal is open.

## Behavior

Dishes use supported, unoccupied tabletop footprints, including settings reserved by approaching diners. Finished or canceled standing meals settle on available nearby furniture or a clear measured floor position. Selling their supporting furniture retains the same food and finds support. A waiting autonomous washer releases the matching carried plate before changing activities, preserving later player instructions and a valid save. Idle Lifelets can choose washing after ordinary needs and school/work obligations.

Idle Lifelets also take a short ordinary walk when crowding another person or blocking an arriving activity. The controller preserves existing walks, nonempty activity queues, resource waits, absence and pause. One of two overlapping idle Lifelets yields; someone already moving away does not trigger a second unnecessary walk. This changes movement only, without teleporting or awarding activity benefits.

## Final-source evidence

The final rendered dining run, `dist/test-work/justlife-playthrough-j4yc2p1a`, passes **80 first-process and 29 fresh-restart checks**, with clean import and runtime logs. Four adults cook and eat with two chairs, sell their dining supports through Build & buy, cancel and resume a partial standing meal, save/reload, finish dinner and autonomously wash two plates. The harness uses public object-click signals and menu buttons with real frame processing; it does not physically aim the mouse at every object.

The critic independently verified all 255 frozen hashes, inspected the finished-dinner screenshots and measured minimum settled body-center distances of **0.90139m and 1.11803m**. All four queues and paths were empty at those checkpoints. The final recipe regression, `dist/test-work/justlife-playthrough-jjkqk3pg`, also passes **57 + 28 checks** with clean logs.

Final runtime hashes are recorded in the packaged build manifest. The accepted placement source is `meal_flow.gd` SHA-256 `67abe7cd8f5c5cb843f00a3b05e99710484e22fae9aa017812ca6a32efa53102` and `life_sim.gd` `6925f4cf5519d4c48c51981a2d47fe7592cf9bf181fe3b6f96b0f8c72571bac6`; the courtesy change adds `idle_space.gd` and three small integration seams in `main.gd`. Character geometry and all 46 production GLBs are unchanged.

The controlled courtesy suite passes **14 checks**, including pause, explicit ground walking, queued/active reading, unchanged household state, binding and pair behavior. It retains two ObjectDB teardown warnings. An earlier test found both idle members yielding in one frame; its failed log is preserved in `dist/game-work/idle-space-source-8512zk5f/rejected_pair_yielding.log`. The earlier 80+29 rendered run predates that two-line repair and remains separate evidence.

The placement component suite passes **49 checks** and the independent wall/floor-edge regression **8**. The earlier component run retains two ObjectDB teardown warnings; the maintained 49-check component and 8-check floor suite passed again on the final export snapshot with clean logs. The final 14-check courtesy repeat retains its two teardown warnings. The first critic probes exposed orphaned food after washer replanning and unsupported dish edges; their failed evidence remains under `/tmp/justlife-placement-critic-4c83y28w/rejected_before_repair`. Maintained tests include both regressions. Publication changes only make harness isolation portable, move the floor report under private userdata and identify the dense fixture by its source manifest.

## Sustained household evidence and limits

The separate eight-member, three-day run `dist/test-work/justlife-playthrough-sr9gojbw` uses the placement patch before courtesy. It retains **136 checks with one failure**, followed by **161 passing restart checks**. Day-two cooking waited behind painting and served dinner at 23:07, missing the intended 22:00 partial-meal checkpoint. A separate continuation of that exact save, `justlife-playthrough-cqisnl6j`, passes **74 + 61 checks**: it follows the existing queue until Morgan actually eats part of plate 8, saves at progress 0.0858875, restarts and finishes the portion. This closes the persistence evidence gap without relabeling the original run as passing.

All eight attended three due school/work days. Across 283 samples there were 211 useful completions, an 11.18-hour maximum completion gap and no observed visible unowned-food footprint overlaps. Twelve servings were consumed, but only one plate was washed, leaving eleven dirty. Lateness and critical fun persist; Avery spent approximately 4.87 sampled hours at critical fun, Taylor 1.03. No spoilage occurred. Dinner requests were assisted by public player commands, so this is not wholly autonomous meal planning.

Active eat/eat and eat/nap body overlaps remain. Courtesy addresses idle bodies; its 0.65m center clearance does not prove full mesh separation or prevent crossing paths. Floor support uses rectangle obstacle tests and nine height samples. Setdown remains instantaneous and can select distant floor space when nearby positions are unavailable. Recorded actor-center-to-setdown spans are not measurements of hand or food travel. Cleanup speed, active dining positions, natural handling, character art and the wider game still need work.

The Curls r15 Blender study remains private and unpromoted: the critic rated the inspected hairstyle approximately **5.5/10**, citing padded rolls, applied curl details and exposed smooth cap. Its checkpoint is `dist/art-work/curls-r15-x57l4hcn/art/experiments/hair_v19/`; all production character assets and the maintained r14 experiment remain unchanged.
