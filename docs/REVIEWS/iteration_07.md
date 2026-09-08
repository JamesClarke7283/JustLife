# Independent review — child creation, school and growing into a teen

8 September 2026. **Bounded milestone accepted; full-request score: 7.2/10.** Visuals 7.0, usability 7.5, simulation depth 7.0, creative breadth 7.0, reliability 7.5. The rubric weights yield 7.15, rounded to 7.2. The increase reflects an actually connected child→school→teen→saved-history flow. It does not award untested generational depth or Sims 4 parity.

The later child-want, wording, birthday-presentation and desk-contact corrections are documented in `iteration_07_presentation.md`; its final 39-check desk inspection accepts the corrected default-child pose. The original snapshot findings below are retained as historical evidence.

## Build and evidence

The frozen source is `/tmp/justlife-school-source-zglmdxt0`. `tests/test_school_playthrough.gd` ran using `tests/run_playthrough.py --suite school` in `/tmp/justlife-playthrough-etfrqdme` with the actual 1440×900 Forward+ renderer and private user data. **82 first-process plus 34 fresh-process checks passed; zero engine/script errors.** Fourteen screenshots, both reports, logs and exact source/model hashes are preserved in `art/screenshots/school_iteration_07/`.

The harness emits production UI signals and allows normal game frames to route and complete activities. It never teleports the Lifelet, advances time directly, calls the arrival callback, or changes age state. Autonomy is disabled after move-in so the selected tasks remain deterministic. Inspection cameras show the child at the desk; the ordinary game camera is restored afterward. Audio is disabled. These checks are not comprehensive keyboard/mouse accessibility or frame-pacing certification.

## What passed

- Creator's visible age selector chooses Child for Robin Reed and Adult for Morgan Reed. The preview and live actor load the authored child asset, with child stature; Morgan retains the adult stage. The child face view and creation controls remain legible.
- Both enter Willow Cottage. Robin's School tab presents Willow School and the initial grade C/zero-class record.
- The public Homework control queues an actual desk action. Robin walks to the desk, sits and completes the assignment. Partial work grants no completed assignment. Completion adds logic learning and prepares the next class.
- Online classes queue and complete through actual normal-speed processing. Partial work grants no attendance. A completed class records one attendance, consumes the prepared assignment once, grants the stronger prepared-class learning benefit and costs energy. Neither school activity invents wages or fees.
- Pausing freezes class progress and the child's activity transform. The School buttons reflect unavailable repeat activities, and the public record reflects the class and assignment.
- The birthday dialog correctly describes becoming a teen. Actual birthday completion costs 30, creates one child→teen history entry and replaces the live child model with the authored teen model. The HUD updates to Morrow Secondary.
- Primary school history preserves the actual attendance and labels the one-class record as incomplete; it does not invent a graduation. Secondary counters begin afresh while the primary record remains accessible in My Lifelet.
- Named save followed by a fresh process restores age, model selection, exact schooling counters/dates/archived records and lifecycle history/progress, alongside the tested household profiles, needs, funds, skills, relationships, positions and home state. The restored School and School history screens show the correct records.

The separate 62-check adversarial component review documents the fixed time-boundary, furniture-mutation and birthday-save races in `iteration_06_education.md`.

## Visual and usability assessment

The child is visibly smaller relative to ordinary furniture and the adult in the home, rather than a relabeled adult. Creator framing adjusts to the child, the face is readable and the portrait changes with the teen transition. The UI keeps age, school, grade and homework status visible without adding an overcrowded panel. Both school dialogs fit at 1440×900.

The seated body pose is coherent, but the child does not actually reach the keyboard. The hands stop short in the inspected images. Follow-up anatomy/anchor analysis confirms a real reach limit: the keyboard is approximately 0.695m ahead of the seated hips while the child's arm chain is approximately 0.35m. The IK clamps rather than reaching the target. A legitimate forward chair position and torso lean need an independent close-view follow-up. Navigation and learning pass; physical hand contact does not yet.

The birthday now has a visible held cake and purposeful arm pose at the fridge, correcting the earlier idle-only presentation. The ordinary camera screenshot establishes that the prop appears in actual play. It does not establish every blow-out/applause phase, cake grip or candle contact in close view. A fuller shared celebration remains a worthwhile interaction improvement.

Two concrete issues are visible in this snapshot:

1. The School record uses “1 classes attended” and “1 assignments.” Singular counts need singular nouns. Root has acknowledged the correction; this frozen run precedes it.
2. The child's pinned first wish still asks for cooking, despite child cooking being unavailable. A child should receive a reachable opening want. Root has identified a snack-based replacement; that later source change is not credited as tested here.

## Remaining scope

This pass exercises one child, one adult, one class and an intentionally early birthday. It does not demonstrate repeated attendance through an earned graduation, school friends/events, parent helping with homework, autonomy across several school days, teen-to-adult gameplay, elder creation/use, pregnancy, babies/toddlers or a full generational household. Child and teen school actions currently share one laptop activity presentation. Three hair groups, a small wardrobe and a few face controls remain far below the requested character/customization breadth. The foundation is more capable and coherent, but the full target remains in progress.
