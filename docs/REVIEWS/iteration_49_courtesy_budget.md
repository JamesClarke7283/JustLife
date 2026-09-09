# Iteration 49 — use the full sidestep search budget

Two Lifelets walking toward each other could remain stuck even when a safe sidestep was available. The selector stopped after twelve candidate positions. Its actual limit is twenty-four hypothetical route queries, but a two-person blockage uses only one query per position. The early cutoff left half that budget unused.

The selector now visits sorted candidate positions until it spends the existing query budget. Each position still considers at most two eligible beneficiaries. Body clearance, swept movement, complete passing paths, distance ranking and deterministic ties are unchanged. It installs and saves the same ordinary, stair, walk and current-floor courtesy contracts. This fixes a missed local recovery opportunity; it does not guarantee every household layout will remain free of congestion.

## Actual household observation

The evidence starts with the original four-member morning checkpoint and runs a complete autonomous day. The paired projects use the same candidate one-minute clock, car conversion, architecture, needs, queues and nine inherited player commands. Only the courtesy runtime and a read-only trace observer differ. This is a clock-one study, not a claim that the old six-minute clock produces this exact overnight sequence.

The first 2,720 complete sampled rows are equal. At game minute 3016.8, the original search's first twelve evaluated pairs are all incomplete. The new search spends twenty-four queries and selects candidate rank seventeen: Morgan steps one metre to `(4, .16, -.75)`, allowing Rowan a complete 3.308-metre path to the toilet. Morgan reaches the holding position at 3017.6; Rowan arrives at 3019.6; Morgan's hold releases on Rowan's actual route retirement. Morgan then reaches the original snack destination at 3028.0.

Both original instructions and route identities remain exact on every approach sample until arrival. Each activity completes once after its original fifteen game minutes: Rowan at member clock 3034.8 and Morgan at 3043.2. The maximum sampled physical step through arrival is 0.640000105 m at a nominal 0.64 m step. The minimum sampled pair separation during that interval is 0.746854 m. No rescue command, repositioning, need reset, paid-progress edit or deadline change is used.

The former 168.4/167.6-game-minute stationary toilet/snack approaches disappear in this replay. The largest remaining stationary approaches for these two Lifelets are earlier painting approaches of 21.2/19.6 minutes. Other autonomous routine limitations remain; this is not a full-game quality score.

## Validation boundary

The full-day process and import are clean, with 36 existing checks passing and no source or named-fixture drift. The diagnostic predecessor independently enumerated all twenty-seven admissible positions at the actual unchanged blockage, identifying successful alternatives beyond the old cutoff while preserving raw game, helper and graph state. The replay then demonstrates an actual completed recovery through the same live prefix.

The three unchanged maintained suites pass **1,461/0**: ordinary courtesy 200/0, stair/walk beneficiaries 906/0 and current-floor passage 355/0. They cover 31 successful gameplay processes and three clean imports on the combined clock-one, car-conversion and query-budget runtime. Source/copy inputs and phase logs were reverified after completion.

The new maintained `python3 tests/run_courtesy_query_budget.py` component passes **40/0**. It exercises production selection with explicitly stubbed eligibility, geometry and route answers: late success, all-failed/out-of-budget answers, the two-peer limit and ownership/path association. Its portable runner was actually executed in a fresh isolated project. The separate natural replay supplies real movement and completion evidence.

Character artwork is unchanged by this runtime update. These targeted results do not establish the broader 10/10 quality goal.
