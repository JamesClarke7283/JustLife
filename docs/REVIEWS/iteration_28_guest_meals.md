# Guest meals — bounded acceptance

Date: 9 September 2026. This record summarizes the implementation evidence, root's independent regression work, and critic_v26's independent review. The critic closed its three concrete findings; it did not raise the whole-game score of **7.2/10**.

A welcomed neighbor can join the public **Call everyone to eat** action, physically collect one portion, reserve a ground-floor chair or standing place, eat, and return to the visit. The existing food ledger records custody and shared company. The household can wash the resulting plate. Goodbye keeps custody until supported setdown succeeds, including a saved five-game-minute retry. The original visit deadline keeps running.

## Review findings and corrections

1. A blocked guest could retain an unclaimed pickup offer after the source dish disappeared, producing an invalid named save. Ordinary source mutations now reconcile the offer immediately; final integrity evidence exercises actual household Discard and immediate saving.
2. A malformed save could place a seated guest's portion on another otherwise valid table. Physical admission now validates the actual chair-derived host, offset and position before adopting the state; the test verifies rejection without changing the current world.
3. Standing Goodbye could display a waist-height plate with relaxed arms. The guest now retains the holding pose throughout release and retry. The critic inspected all three replacement captures, including close and 960-pixel views, and verified fresh-process paused restoration.

Home-visit and meal records advance to version 2 while preserving version-1 compatibility. The independent resident catalogue retains Maya and Leo's exact profiles and the public controller alias. Reading this metadata without loading the resident controller resolves a measured script dependency leak; it does not change resident behavior.

## Evidence

The immutable final runtime is `review_v3`, eleven files pinned by SHA-256 `3f4ba0f01a1097c299abb2d3e9d715b4104cc61fa9e10337a255ca1f503a3f74`. The local handoff is `dist/test-work/guest-meal-source-8_k_0kvc/handoff`; its freeze hash is `154066a40b6178088b232f64eae96a82be0b9e0d285844c86c478be7664c79d8`. Root verified all 41 handoff artifacts, 244 retained evidence files and the 30 promotion files before integration, preserving 1,025 other tracked inputs. The private root receipt is `dist/game-work/guest_meal_promotion_receipt.json`.

Final-source focused integrity passed **19 checks / 0 failures**. Standing release producer and separate-process retry passed **9/0 and 7/0**. The critic checked their runtime, harness, log and clean receipt hashes. The corrected Forward+ Goodbye capture passed **5/0**, with three inspected images; its affected pose/controller code matches final source, while the later catalogue extraction is explicitly outside that capture's input boundary.

Earlier qualified revisions cover canonical and legacy lifecycle **44/0** each with separate-process **36/0** checks, standing lifecycle/restoration **44/0 and 36/0**, resource/deadline controls **44/0**, real shared company and concurrent paid cooking **23/0** with fresh restore **7/0**, and paused Build movement/deletion **13/0**. Six seated and five coherent standing predecessor images remain evidence for their recorded source. The rejected standing Goodbye image is retained. These are assertion counts, not separate gameplay scenarios; they are not all reruns of final source.

Root independently ran the unchanged floor-level meal suite against final source after catalogue extraction: **96/0**, fresh import and verbose shutdown both clean. Its log SHA-256 `f6b41e6b7e6cc748b6d3b18d08820f62277f9d6b6c0fa700be8fe8f6dcd93c49` exactly matches the clean baseline log. The standalone maintained guest runner's curated dependency import also completed cleanly; full wrapper execution is separate from the retained per-phase runs.

## Retained failures and limits

The engine's full-precision JSON codec changes some encoded float64 values by one ULP. Byte-level reproduction is retained. Persistence checks compare authoritative values exactly with the decoded data on disk and separately validate typed physical projection. No tolerance widening or bit-identical binary round-trip claim was used. Ordinary paused presentation no longer overwrites saved food coordinates; explicit Build edits and resumed simulation still reconcile them.

Root's detached baseline comparison exposed older fixture limitations on both revisions: meal-state returned 101/0 with five missing `TestWorld.navigation` script errors; standing admission returned 11/0 with two ObjectDB leaks; meal placement returned the same five fixture/service-arrival failures among 49 checks. These are not clean passes. A separate candidate-only floor shutdown leak was reproduced, isolated and resolved through the catalogue change. Earlier failures involving source custody, physical support, pause reconciliation, codec precision and fixture timing remain in the handoff evidence.

Scope is one invited guest and one portion from a fresh, placed ground-floor serving dish. There is no separate guest needs model, party system, cooking autonomy, storage pickup or upper-floor visiting. The source UI captures used the earlier character asset baseline; they qualify interaction presentation rather than the current Crop artwork. Exported-binary qualification is recorded separately in `docs/RELEASE_VERIFICATION.md` when completed.

## Maintained fixture repair

The three detached fixtures were then corrected against the same `bce9269` runtime. Meal-state now supplies the real navigation/construction/floor-support contract and passes **101/0** cleanly. Standing admission waits for actual weak-reference release of its audio resources before quitting and passes **12/0**. Placement validates the selected standing route, explicitly supplies physical arrival in its controlled fixture, and uses the same teardown check; it passes **54/0**. The additional counts are route/reservation/teardown assertions. All original assertion calls and tolerances remain unchanged, and all production code/assets are exact. This is fixture repair, not new gameplay or motion evidence.

The original errors and leaks remain archived alongside the clean candidate at `dist/test-work/detached-meal-fixtures-bce9269-wq6eji2j`. Its handoff freeze is `1179f3d775d7c131a6008b61c94cbbbcc99ea7d0ea4da7b783f4394e4d805874`. Root reviewed the patch and verified all nine frozen artifacts and 33 evidence files before copying only the three maintained tests. The promotion receipt is `dist/game-work/meal_fixture_promotion_receipt.json`.

## Final maintained runner and package

Root subsequently ran `python3 tests/run_guest_meals.py` end-to-end on exact committed `bce9269`: clean import plus sixteen directed gameplay/fresh-process phases, **382 assertions, zero failures, no diagnostics or input drift**. All 242 copied source inputs match that commit. The complete receipt and each log/report are pinned in `dist/test-work/guest-meal-check-z51e2ruq/COMPLETED.json` (SHA-256 `24e4ba38da7ecd62b694c19d7f1363fb81c3d2c6b534113b261abe6cb5b781c9`). This closes the wrapper/dependency/order qualification gap; it does not add rendered or native-input evidence. The separately qualified Linux package is published and recorded in `docs/RELEASE_VERIFICATION.md`.
