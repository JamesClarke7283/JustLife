# JustLife independent review — iteration 02

Review date: 8 September 2026. Reviewed source: the household/grounding checkpoint copied into `/tmp/justlife-playthrough-cpt8w4br`, rerun with the strengthened harness in `/tmp/justlife-playthrough-ro416j_n`. Source hashes, actual renderer captures, state evidence and logs are preserved in `art/screenshots/playthrough_iteration_02/`. This review excludes later shared-project edits and the separately staged character rig.

## Current full-request score: 6.0 / 10

| Dimension | Score | Evidence and limit |
|---|---:|---|
| Visual and character quality | 6.5 | Cohesive original house/UI art, improved actual sofa/bed/shower contact, readable interior after foreground trees fade. The rendered character still has assembled joints, a rigid face and limited outfit expression. |
| Usability and flow | 6.5 | Creator → home → household works; selection, queue cancellation, building and resume have been exercised. Household chips overlap, some cancellation symbols disappear in ellipses, and some creator copy overflows. Physical hit-testing of every UI control remains unverified. |
| Simulation and interaction depth | 6 | Two independently controlled people act concurrently, share money, retain individual skills/needs and act autonomously overnight. Spatial actions, paid cooking and persistent relationships have observed effects. Broad occupation/social concurrency, varied life outcomes and complex progression still need more depth and testing. |
| Creative breadth and sustained play | 5 | Multiple household members and real rooms/walls/openings materially improve the playable scope. The reviewed runtime still offers limited identity/outfit variety, a small furnishing collection and a narrow neighborhood experience. Family/aging and travel flow are absent from this checkpoint. |
| Reliability and delivery | 6.5 | The rendered public-flow suite passes, including restart and one full simulated day. This is good evidence for this slice, not proof of extensive multi-day stability, eight-person performance or complete device/window support. |

The weighted result uses the established rubric without changing the target to a small demo. The original review's 4.7 estimate was provisional; this is stronger evidence of a coherent playable slice. **It is not 10/10 or full Sims-like parity.**

## What was actually verified

The isolated Godot 4.7.2 run used Forward+ on the available NVIDIA RTX 5090 and a 1440 × 900 viewport. Import alone was headless. Gameplay used a real renderer, actual frame processing and viewport captures. The test did not teleport either Lifelet, call simulation tick directly or pretend arrival. Button signals exercised production callbacks; mouse events and pointer placement exercised build input.

**164 first-process assertions and 30 fresh-process assertions passed, with zero engine/script error lines.** Twenty-two PNG captures and both structured reports accompany this review.

- Rowan and Ellis were created through public creator controls with distinct names, body frames, hair and colors. Household chips switched selection while preserving the first person's route and queue.
- Rowan cooked, showered and conversed while Ellis read. Both completed activities through actual walking and processing. Cooking charged ℒ25 at activity start, hygiene recovered, friendship increased and reading skill stayed with Ellis. The wallet remained shared.
- Pause froze clock, needs and movement. Eight long-label queued activities remained scrollable and were cancelled through their own controls.
- A valid mouse purchase added a ℒ45 plant. An overlapping purchase changed neither funds nor layout. A 2 × 1.5 m room created four walls and a floor for ℒ421; its doorway cost ℒ90. Overlapping room construction was rejected without state changes. Floor finish persisted.
- Rowan sat on the sofa and lay on the bed. These are real active poses, not manually staged positions.
- The household saved during a **charged ℒ25 cooking action** with reading queued after it. Same-process and fresh-process loading restored both members' identities, individual needs, skills, relationships and positions, along with money/time, lot, flooring, construction, furnishing placement and queue progress/payment. Resuming the paid action did not charge another ℒ25.
- After resuming, both people completed autonomous activities and the household reached **Day 2, 08:00**. Observed autonomous completions included socializing, toilet use, snacks, showering and sleeping. Needs remained in bounds and the shared clock advanced consistently. Evening and next-morning captures show the daylight change.

## Corrections confirmed during this review

The first public-button run exposed synchronous `.free()` calls that attempted to destroy the emitting button. These left interaction menus and creator/build controls on screen, produced stale-reference errors, and broke cancellation/build flow. Parent fixes to detach children and use `queue_free()` eliminated those errors in the passing checkpoint. State-only controller tests had missed this lifecycle defect; signal-driven testing was necessary.

The unbounded queue now has a horizontal scroll container. The home selection now labels its amount as **household funds after move-in**, matching the balance received. Foreground tree fading makes the shower and nearby active Lifelet visible. Sofa and bed activity anchors now put the body on the furniture rather than floating in front of it.

Two early failed checks were test defects, not game defects: synthetic motion did not move the OS cursor read by the placement preview; a fixed per-frame movement limit mishandled accelerated game time and frame timing. A minimal Godot experiment established the pointer behavior, and a child-process observer now checks movement with the same frame's engine delta. The corrected checks pass without modifying the frozen game snapshot. One transient missing social menu did not recur in the corrected run and is not reported as a confirmed production defect.

## Highest-impact remaining work

### P1 — Finish character and activity presentation

The old character remains visibly segmented at shoulders, wrists and knees, with conspicuous eye rims and a nearly fixed expression. New separately reviewed rig art scores approximately **7/10 for static character art**, with continuous surfaces and three distinct outfit silhouettes, but it is not included in this runtime score. Its seated deformation still needs less pinching at hips/knees, and final eye sockets need softer lower-lid volume.

The corrected anchors establish appropriate gross contact. They do not yet provide expressive transitions, convincing hand contact, cooking/eating props in use, shower water/change-of-clothing presentation, or nuanced conversation. Sleeping still looks stiff and the head is close to the headboard. Accept the new rig only after the same real activities, entry/exit and save/resume are recaptured with it.

### P1 — Make household controls fit their actual minimum size

The live chips request 31-pixel widths at 35-pixel spacing, but the theme expands their minimum size. In the two-person capture, **Ellis's chip partially covers Rowan's**. This is a visible regression introduced with the household UI.

Acceptance: prevent overlap for two through eight members at the target and smaller supported window sizes, retain a clear selected state, and expose the full identity through a portrait/label or tooltip. Do not rely on the nominal `size` when theme padding determines a larger minimum.

### P2 — Restore visible cancellation and compact copy

Long queue labels truncate before the trailing ×, hiding the promised cancellation affordance even though clicking the card works. Keep a separate visible close control or reserve its width before ellipsizing the title. Mark the current speed persistently. The wardrobe description still runs beyond its panel in creator evidence; constrain and wrap it. The relationship footer also sits against the bottom edge with little clearance. Room/wall previews should display their cost before the committing click; the current notice explains the charge afterward.

### P2 — Keep feedback tied to the current activity

“Delicious!” remains above the character during the subsequent shower, and other completion barks survive into unrelated actions. At accelerated time this can span hours of game time. Clear or replace a completion bark when the next activity begins, or scale its lifetime appropriately. New room floors can also retain outdoor decorative stones protruding through them; suppress or relocate decorations covered by construction.

### Continue meaningful breadth and verify it

This checkpoint has a connected household loop rather than one frozen character. It still lacks the requested broad family/aging and neighborhood/travel flow. Creation needs meaningful face/body/outfit variety in actual runtime; building needs more architectural and furnishing choice; progression needs more varied social and career outcomes with legible requirements. The source now contains additional career/mood/memory UI, but this playthrough did not certify those paths.

## Verification limits

This is one household of two people, one chosen home and one simulated day. It does not verify eight-person frame pacing, every career/relationship branch, sustained multi-day economy, every object action, extensive construction/routing combinations, a smaller window, export/install packaging, or audio quality. Audio was deliberately disabled in the harness. The apparent frame pacing was sufficient for the run, but no performance benchmark was recorded.

**Decision: playable household milestone accepted with material limitations; keep iterating.** Next review should prioritize the integrated new rig, household-chip sizing, a different home layout, smaller-window input, and substantive progression or neighborhood flow. A 10 requires the missing requested pillars and much broader verification, not a more generous critic.
