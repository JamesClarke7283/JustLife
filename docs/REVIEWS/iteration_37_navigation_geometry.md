# Iteration 37 — navigation rebuild response

Moving a furnishing repeatedly reconstructed floor, wall, stair and support rectangles for every point and connection of two navigation graphs. A real played-household sample took about 3.6 seconds to lift an existing plant and another 3.6 seconds to place it. Navigation now derives those rectangles once per detached rebuild. It publishes geometry with the accepted graph and preserves both on a rejected rebuild. Graph construction also avoids checking endpoints a second time after they have already been admitted; public segment queries still validate both endpoints and the complete intervening bounds.

This changes no route ordering, graph admission, body clearance, construction transaction or save format. Validation still builds the detached candidate and the live world graph separately. There is no persistent query-result cache or skipped transaction validation.

## Geometry and regression evidence

The private exact differential retained the original navigation implementation, changing only its class name and self-load path so that its detached rebuild also uses the original implementation. Seven finite fixtures cover empty terrain, supported two-storey floors, all four stair orientations and an actual played four-member household. Comparison includes ordered point IDs, positions, weights, disabled flags, ordered connection arrays, location and stair maps, state, obstacles and generation.

All 67 assertions passed with clean import and execution. Their internal samples include 31,836 point queries with three distinct footprints, 53,060 segment queries and 170 complete route dictionaries, including deterministic ties and temporary body exclusions. Those samples are not separate gameplay scenarios. Rejected structure/obstacle rebuilds preserve prior query results and graph state; valid rebuilds replace geometry. This is finite equivalence evidence, not a formal proof for every possible house.

Fifteen maintained architecture, Build, protection, stair-controller and waiting processes passed 858 assertions with no engine warnings or errors. Source and copied inputs remained exact. That runner isolated saves and three XDG paths, but inherited its parent temporary directory. The maintained runner now also assigns a private `TMPDIR`; the earlier result is not relabeled as five-variable isolation.

Ten additional maintained public-query checks cover custom footprint axes, a blocked segment with clear endpoints, floor locality, failed rebuild preservation and successful obstacle/upper-floor removal. A separate current-source run, including the accepted child Bob artwork, passed all seven architecture processes: **613 assertions**, clean import/execution, unchanged inputs and all five private environment paths. These controls exercise public behavior rather than inspect derived cache arrays.

## Actual rendered response

Both observations load the same genuinely played four-member named save, use the same pre-Bob artwork and select Ground through its public control. Only `lot_navigation.gd` differs among their 240 production inputs. The sample uses Godot 4.7.2, Forward+/Vulkan, 1440×900, RTX 5090 and Ryzen 7 5700G. Agent-owned engine/Blender work was idle during the rendered candidate window; the user's editor remained untouched. This is not a claim that every machine process was idle.

| Public command | Original dispatch / next draw, ms | Revised dispatch / next draw, ms |
| --- | ---: | ---: |
| Open Build | 37.578 / 90.740 | 34.807 / 85.194 |
| Lift existing plant | 3658.333 / 3756.925 | 624.834 / 719.785 |
| Place the same plant | 3607.959 / 3626.014 | 639.052 / 655.941 |
| Return to Live | 188.820 / 244.974 | 188.227 / 245.720 |

The actual transaction moved `item_13` from approximately `(-.05,.16,4.15)` to `(-.8,.16,4.15)` without changing funds or the clock during Build. These times include instrumentation and synchronous new-node input guards. Subsequent tree input exclusion is measured separately; invocation-to-draw includes that work and probe scheduling. Commands use public signals, not native pointer input. Polled keyboard/pointer reads have explicit private overrides; normal simulation processes actual frame deltas.

The original receipt remains failed at **17 checks / 1 failure** because its probe incorrectly expected aggregate household speed to become zero in Build. Production instead gates household processing on Live mode. The revised probe uses nonmutating member state, explicit household data and a detached physical snapshot. Exact before/after equality across four ordinary Build frames passes both after opening Build and after committing the move. No production pause logic changed and no original failure was discarded.

The candidate passed **18 checks / 0 failures**, with clean import and rendered execution. All 646 raw post-draw intervals remain recorded, including commands, intermediate snapshots and transitions. Root inspected the actual final image. Interval median / 95th percentile / maximum were:

| Series | Intervals | Revised interval, ms |
| --- | ---: | ---: |
| Live before edit | 300 | 20.660 / 26.340 / 30.282 |
| First Live frames after edit | 30 | 21.586 / 25.541 / 27.759 |
| Following Live frames | 300 | 22.060 / 25.190 / 65.337 |

Frame intervals include pacing and scheduling. Reported viewport CPU/GPU timings are rendering-only measurements and are not guaranteed to align with the same interval; they are not summed into total frame time. Real elapsed-time simulation reaches different moments in the two runs. The result supports a substantial reduction in this furniture-edit hitch, still about 0.63 seconds per operation. It does not establish a universal FPS improvement, native input latency, other hardware performance or sustained household health.

## Retained evidence and limits

Private work is under `dist/test-work/navigation-geometry-cache-5pr4ufdm/`. The exact qualification freeze is `5f43dacad2eb1d904c62159ed437f4d353b47860a3aef516537142a1073ac0ce` (2,368 pins). The rendered comparison freeze is `959c43de1841513476da5770cad381e0e69da6c7eba157e6bd20e2d4ec5fa001` (498 pins). `CURRENT_SOURCE_FROZEN_R1.json` retains the current-source logs and corrects an earlier summary-only arithmetic typo; all seven raw suite counts are unchanged. Independent navigation qualification review is `navigation-cache-qualified-critic-f1f0ov9e/REVIEW.md`, SHA-256 `f982dd63939a979e8184df0cd6ae8f8457f29d55d713ef7ae0320edad5cb3977`.

The rendered study uses the separately qualified private courtesy/pedestrian composition. This commit contains only the navigation optimization, its public-query controls, runner isolation and this report. The original and revised probes, failed receipts, old implementation, raw captures and profiler data remain ignored evidence. No duplicate baseline implementation or generated test project is added to the source tree.

Long household approaches, meal cancellation loops, missed attendance and depleted needs remain separate open behavior issues. This change does not raise the overall game score or establish 10/10 quality.
