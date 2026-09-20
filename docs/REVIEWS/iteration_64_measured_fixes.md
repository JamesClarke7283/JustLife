# Iteration 64 — baseline critic findings, measured and fixed

15 September 2026. Branch `wip/justlife`, off `main` @ `60b4ceb`.

This pass exists because the game had accumulated a lot of asserted quality and
very little measured quality. Two independent critic passes read the rendered
build, and every defect they could evidence was either fixed and re-measured or
recorded as knowingly open. Nothing here claims a 10/10; the honest trajectory is
**4.7 → 6.6** with named gaps still open.

## The two independent passes

| Pass | Weighted score | Visual | Usability | Mechanics | Breadth | Reliability |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Baseline (pre-fix build) | **4.7** | 4 | 5 | 5 | 5 | 4 |
| Follow-up (this branch) | **6.6** | 6 | 7 | 7 | 6 | 7 |

The rubric is `docs/QUALITY_RUBRIC.md`; the reviewer read the tour screenshots
directly and checked each claim against code and evidence.

## What the baseline found, and what happened to it

| # | Baseline defect | Outcome |
| --- | --- | --- |
| 1 | Housemate interaction panel rendered as an empty card | **Fixed.** The panel really worked; `show_interactions` read `item.label`, `item.kind` and `item.id` unguarded, so a caller passing a member id without a label aborted mid-draw. The panel normalises those keys, and `probe_tour.gd` now opens it with a genuine pointer press instead of a hand-built dictionary. |
| 2 | The tour reported a clean pass in a run that logged a `SCRIPT ERROR` | **Fixed.** The harness installs an `OS` logger and fails on any engine error: 49 checks, 0 errors. |
| 3 | The interface filled only ~75% of a wider window; modals sat off-centre | **Fixed.** `_fit_interface` scales to the canvas height and centres the design; spanning screens use the real canvas width. Rendered at six window shapes from 1280×614 to 2560×1080. |
| 4 | The multi-resolution evidence was three copies of one frame | **Fixed.** Six genuinely different sizes, verified by pixel dimensions. |
| 5 | No save/resume evidence (the rubric caps at 5 without it) | **Fixed.** Two separate processes: one plays, buys, saves; a fresh one loads and confirms 11 facts off disk. The cap no longer applies. |
| 6 | The action queue strip was empty in every capture | **Fixed.** It was drawn as a bare `HBoxContainer` at y=650, floating over the 3D scene. It is now a labelled "Next up" card, only present while something is queued, and each chip names its target. |
| 7 | Character art placeholder-grade at close range | **Partly open.** Hands remain fused mitts; garment seams remain absent. See `evidence/hands_iteration/`. |
| 8 | World breadth was one house and menu text | **Fixed as a demonstration.** Three distinct starter lots (28/25/5 items, with the third advertising ℒ4,500 against ℒ2,500) and three distinct venues via real travel, all measured. |
| 9 | No simulation outcomes ever shown changing | **Fixed.** Needs decay and recover, skills level, mood derives, a full game day runs unattended, and a promotion moves a requirement from unmet to met. |
| 10 | Build & buy never showed money moving or a rejection | **Fixed.** A purchase debits exactly its price, Undo refunds, an illegal point is refused with a reason, an unaffordable item names the shortfall. |

## Two real bugs the first pass could not see

Both were found by tools written during this pass, not by inspection:

- **The Build & buy Storage button could not be clicked.** It occupied x 266–371
  while the catalogue `ScrollContainer` begins at x=292 and stops mouse input, so
  75% of the button — including its own centre — was dead. Ground and Upper shared
  the same column.
- **The live HUD Rewards button could not be clicked.** It overlapped
  *Cancel action* by 64 px, and *Cancel action* is drawn later, so it swallowed the
  right half of Rewards including its centre.

Both are now x-positioned to their own columns, and `probe_ui_overlap.gd`
(36 screens, nine sample points per control, emulating Godot's own picking) plus
`probe_click_reach.gd` (real `push_input` presses) guard the class.

## A methodology error this pass made, and corrected

The directory first published as the tour baseline had been overwritten with
post-fix captures, so it did not contain the defects it was cited for. The true
pre-fix set is committed as `evidence/tour_prefix_baseline/`, its empty panel
verified by pixel count (64 non-white pixels against 22,586 in the fixed set),
and `evidence/README.md` records every set's build. `evidence/transcripts/`
holds the console output of all eleven probes.

## Still open, and unflattering

1. **Adult hands** are fused mitts: 14.2 mm finger pitch, 55.5 mm four-finger span
   against a real hand's ~85 mm. A bounded study exists and is not promoted.
2. **Garments** are smooth shells with no sleeve hem, seam or fold, so clothing
   reads as colour rather than fabric.
3. **No single artifact spans several game days.** One full day is measured; bills
   and multi-day autonomy are not.
4. **Character acting** in ordinary play is unmeasured beyond walk, sit and sleep.
5. **No packaged-binary acceptance** at this revision; the release probe was not
   re-run.
6. **Performance** was not re-measured on this branch.
7. **The 10/10 target is not met.** A 6.6 is a strong, verified slice, not parity
   with a commercial life simulation.
