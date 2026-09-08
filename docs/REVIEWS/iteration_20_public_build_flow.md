# Iteration 20 — public two-storey flow

The independent review accepts this bounded functional slice at **8/10**, with
**7/10 for the inspected visuals**. It does not revise the full-game score.

An actual rendered game creates two different male/female Lifelets, selects
A Fresh Canvas, then purchases the full upper floor, original staircase,
bookcase and plant through the public controls. The household pays the normal
prices from its advertised §4,500. A Lifelet climbs the real staircase and reads
upstairs. The public save picker writes that activity, and the household descends
to its car, visits the library and returns with its original building intact.
A separate process loads the untouched upstairs checkpoint through the save
picker, resumes the reading naturally and takes another car trip.

The producer passes 69 assertions and fresh consumer 16, with both processes
exiting successfully without engine warnings or errors. These 85 assertions
include button availability and captures; they are not 85 gameplay scenarios.
No building records, actor positions, funds, time or needs are injected. Autonomy
is disabled for the finite test, and camera framing is controlled. UI buttons
emit production signals; construction, furnishing and interaction clicks use
actual viewport input, with pointer positions recorded.

Evidence is retained at `dist/test-work/justlife-playthrough-twofloor-coeizlgj`.
All 206 original source inputs remain exact against staging. The private copy
has 205 byte-identical inputs and an explicitly reproduced project configuration
with only MCP/autoload/editor sections removed. Seven actual runtime images
and the two process reports are pinned in `public_verification_receipt.json`.
The initial headless diagnostic used the wrong viewport size; its failed
evidence remains under `attempt01`. Correcting only the harness's window size
made the headless building preflight pass 26 assertions.

Independent review:
`dist/test-work/public-twofloor-critic-hbz7itdn/PUBLIC_TWOFLOOR_CRITIC_REVIEW.md`,
SHA-256 `f30b7f82547d418e8decfde73b5f3371046a051e8de2510897302dcfaf3e38da`.
The critic inspected all seven images and exact source/log evidence, with no
additional execution or blocker found. Successful stairs placement left an
overlapping repeat-placement preview, and canonical wood floors looked plain
beside the starter boards. Both are assigned separate polish changes.

The example deliberately buys an open upper floor with two furnishings; it is
not a finished two-storey house design. This snapshot predates the upstairs
sanitation port and requires a combined replay after that integration. The
maintained entry point is `python tests/run_public_twofloor.py`.

## Final combined replay

The combined source includes floor-aware sanitation, saved-target validation, the supported mop pose, wood materials and cleared stair-placement feedback. The full rendered producer passes **70/0** and its fresh consumer **16/0**, with no engine warnings, errors or changes to 214 source/copy inputs. Evidence is `dist/test-work/justlife-playthrough-twofloor-9d_m038g`. The extra producer assertion checks that successful stair placement clears the repeat-placement ghost. Root inspected the final stairs, upstairs reading and fresh-load captures.

The independent updated public-flow review accepts this slice at **8/10**: `dist/test-work/public-twofloor-critic-6u9x_pph/PUBLIC_TWOFLOOR_REVIEW.md`, SHA-256 `ce5a80e3ce844d69f1746b622befb08529a151ea34eaffdfc113779ae262b3dd`. It verifies all seven actual images and the exact input manifests. Its precise-state claim covers building records, funds, names, floor and continued reading; the capture helper itself temporarily pauses, so the image alone is not proof of a paused load.

A separate fresh-consumer addendum addresses that gap before taking a screenshot: loaded speed is the saved zero, and the reading target, phase and elapsed progress match the original decoded slot. It passes **18/0 clean** at `dist/test-work/justlife-playthrough-twofloor-state-zrx3jzzx`, using a private copy of the untouched producer save. All original save bytes and copied inputs remain unchanged. The maintained fresh consumer includes those two assertions. This does not claim exact root-vector or animation-phase equality, nor that the open upper-floor fixture is a finished house.
