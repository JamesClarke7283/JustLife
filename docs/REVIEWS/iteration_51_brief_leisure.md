# Iteration 51 — brief leisure before a scheduled day

Lifelets can spend a work morning recovering Fun with a long paid canvas. When a school/work preparation duty has an available target, non-Bookworms now try Relax (40 minutes), Read or Watch (60), then Paint (90). Bookworms retain their original reading preference. This uses existing eligibility, preparation-window, deferral and excluded-target rules. Outside that context the normal order remains. An available target does not guarantee a short physical route.

Only the shared Fun recommendation changes. Existing controllers may ask for it when initially choosing or legitimately reconsidering an activity. Urgency thresholds, physical readiness projection, paid activity protection, durations, prices, player instructions and navigation remain unchanged. Painting is still available through player choice or as a fallback.

## Observed day and tradeoffs

The candidate loads the same actual Day 2 08:08.4 checkpoint as the current clock/courtesy baseline. Initial state, decoded save, nine inherited commands and the first 37 complete trace rows match. At 08:23.6 Rowan chooses Relax instead of Paint. Relax physically begins at 08:32.4 and completes at 09:12.4. After further recovery and travel, Rowan enters work at 11:56.4 and earns ℒ114 at 17:00 for the remaining 303.6 minutes. This is genuine late attendance, not punctual arrival or a full-length shift. Both children still complete school.

The day is not uniformly better. Rowan reaches zero Fun for 59.2 sampled game minutes, beginning during work at 16:23.6 and ending after return with painting at 17:22.8. A later paid painting session produces 22.8 minutes at zero Hygiene before Shower recovery, matching the same mechanism and timings previously observed in Ellis. Ellis instead has 40.8 minutes at zero Fun while waiting at home for occupied painting and eventually choosing Read; minimum Energy falls from 12.325 to 9.305. Casey's existing 36.4-minute zero-Fun episode remains.

Some journeys also take longer: Ellis's sampled approach time rises from 160.8 to 194.4 game minutes and Casey's from 81.2 to 162.8, including 39.2 minutes in furnishing queues. Rowan's longest exactly stationary nonwaiting Paint approach grows from 21.2 to 40 minutes the next morning, then resolves and completes. These observations do not establish a navigation improvement.

Final household funds rise from ℒ1,741 to ℒ2,060 in this one continuation. The ℒ319 difference comprises ℒ116 additional work pay, ℒ35 net painting proceeds, ℒ8 less snack expenditure and ℒ160 other wallet income alongside two new Friend wants. Both ledgers reconcile; the whole difference is not a wage increase.

## Verification and scope

The full-day replay completes its existing 36 assertions without runtime diagnostics or input drift. Six focused policy component outcomes total 691 passing checks, including the new 40-check brief-leisure component, existing queue/paid recovery/calendar controls and the corrected school component. These are component scenarios with supplied arrivals; the separate day trace establishes actual travel and attendance.

The first component group remains a recorded failure: the maintained school test reported 181 checks and two failures. An unchanged current-game baseline reproduces those exact failures. Its old fixture expected cooking alone to restore hunger and choose sleep/toilet afterward, despite the existing separate cooking/eating mechanics. The correction retains its original 20+25 minutes, once-only ingredient charge, save/resume and empty-queue checks, and asserts that hunger remains zero until eating and Snack is the next most urgent recovery. The corrected school test passes 181/0 separately; the original whole group was not rerun or relabeled green. Runtime meal behavior is unchanged.

The portable `python3 tests/run_prework_recovery.py` runner also passes its isolated 40-check suite after a clean import, with source/copy hashes and terminal counts verified. It reuses the same test; these are not 40 additional scenarios.

Independent review accepts this bounded responsibility preference with the stated needs and traffic costs. There is no new whole-game score. Artwork is unchanged; the separate garment candidate remains held for its inherited raised-arm deformation defects.
