# Iteration 38 — floor placement query cost

Finding a place to set down food repeatedly enumerated the entire navigation grid and rebuilt the same physical floor transforms for every candidate corner. The meal controller now reuses ordered default-footprint candidates for the actual navigation instance, generation, grid region and floor. Bodies, existing dishes, furnishings and physical support remain live checks. Failed navigation rebuilds retain the previous graph and its valid candidates; legacy grids bypass this cache because their cells can change without a generation change.

Physical floor transforms are collected once within each synchronous placement query. They are never cached across queries, so changed mesh visibility, transforms and floor layouts are observed immediately. The original off-grid position remains the first candidate before the unchanged distance sort; equal-distance ordering, full dish support and saved food coordinates retain their existing behavior.

This is a query optimization. It does not change food ownership, nutrition, cancellation, resource queues, walking speed or the save format. The separately diagnosed repeated cancellation of an owned meal remains a different change.

## Validation

The private original implementation differs only in its class declaration. Exact differential comparisons passed **228 assertions** with clean execution. Finite fixtures cover both floors, unsupported and outside positions, rotated/scaled floor surfaces, live bodies and food, successful and rejected rebuilds, navigation-instance/generation/region changes, temporarily disabled route points and mutable legacy cells. Another **20 assertions** verify a genuinely blocked origin with distinct, viable, equally distant alternatives for plates and platters, including cold and warm queries. These are bounded equivalence checks, not a proof for every possible layout.

The maintained floor suite adds 16 behavioral assertions in 66 inserted lines while preserving its original 96 checks. It observes actual placement results after body/food movement, physical floor hiding/restoration, real furnishing addition/removal, rejected world validation, replacement navigation at the same numeric generation and a legacy cell change. Three deliberately broken private runtimes each omit one cache safeguard: generation, instance identity or the legacy bypass. Each fails exactly its intended assertion, with the other 111 passing. Those negative receipts remain failed and are not included in a positive pass total.

On the current source, including the committed navigation optimization and child Bob artwork, all seven architecture processes passed **629 assertions**, with clean import/execution and unchanged source/copied inputs. Saves, configuration, cache and temporary files use five private environment paths. A separate inherited sanitation support fixture passed **29 assertions** with clean import/execution: supported edge accidents, floor demolition protection, actual upper-floor cleanup and cooked-food custody through a canceled stair crossing. Its private wrapper adds recursive GUI/all-four Node input exclusion, including new nodes and every yield; the existing assertions and fixture remain unchanged.

Earlier evidence remains intact: a first differential harness failed to parse; an initial support teardown reported two unidentified ObjectDB leaks; a sanitation invocation correctly refused the wrong private path; and the first saved-state trace detected re-enabled Node input processing after reconstruction. The corrected trace excludes all four Node input modes recursively, on new nodes and around yields. The final maintained legacy test also replaces a failed fixture assumption with its own temporary actor. These are harness corrections, not retrospective passes for the earlier runs.

## Controlled saved-state timing

The comparison loads the same actual named save, `life_1788951101795_688290719`, produced by the retained four-member three-day playthrough. Its SHA-256 is `161caa5c7a0e90153018b61288d7898537c49c18bc5180fd66b54ab24fe0f069`. The 1,113 probe inputs differ only in `meal_flow.gd`; neither the navigation optimization nor the owned-meal cancellation guard is overlaid in this timing pair.

Both fresh loads pass **19 assertions**. Their complete recorded reports are exactly equal after removing only the 30 measured `cpu_us` scalars. Each runs ten paused and twenty advancing ordinary `main._process(.05)` calls. Household state, queues, food, sanitation, bodies and journeys remain in the reports.

| Measured advancing call | Original | Candidate |
| --- | ---: | ---: |
| Median | 330.311 ms | 129.706 ms |
| Mean | 340.935 ms | 140.937 ms |
| Minimum / maximum | 306.560 / 555.817 ms | 122.484 / 244.865 ms |

The advancing-call median is 60.7% lower in this short sequential sample. Paused-call medians were 5.811 ms and 8.767 ms respectively. Agent-owned measured engine work was coordinated; the user's editor, Blender UI and desktop processes remained uncontrolled and untouched. These are instrumented headless controller-call times, not rendered frame rates, universal performance guarantees or evidence that the underlying long-play behavior is fixed.

## Evidence and integration scope

The runtime proposal is `83226d9ca798f3b6d17d082c61d4b3ffa982af8e806823972c5145f9ef3fc33c`. Private qualification is retained under `dist/test-work/meal-floor-query-x4vh3m9_/`, frozen by `f3f8ac8b7a07372c276150b898e9e22166ab01cfb9a1cf96166d7f6917625e62` (81 pins). The maintained-test handoff is `meal-floor-maintained-nu9dy_6u/`, frozen by `bbf89d9d6c6b919cbfd08be4608b5f1e6ac7114317e53ba9ae6bad11c1638184` (57 pins). Root verified all 57 test pins and the critic's 19 final maintained-test pins before copying the two allowlisted source files.

Current-source integration is `dist/test-work/meal-query-current-3147drph/`, frozen by `fe6577b29ea70bf8fa1adebd0bc1252edb309d7217dbec9cd44344bfff3d473c` (926 pins). It begins at commit `6d88a6fbee1b92fcf63a69a395d56bf311db10f9` with only the nominated runtime and test overlaid. It adds no private courtesy, pedestrian, busy-resource or owned-meal code. Generated projects, duplicated original implementations, faulted runtimes and raw reports remain ignored evidence.

The independent review remains under `meal-floor-query-critic-j4cq9hcz/`, including the exact-trace and maintained-test addenda. This optimization does not raise the whole-game rating or establish 10/10 quality. Sustained household contention, attendance and needs still require the separate behavior work and a new composed playthrough.
