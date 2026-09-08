# Iteration 11 — independent speech presentation review

**Decision: accept the reviewed live-speech presentation repair with the limits below.** The inspected candidate fixes the previously tiny, overlapping completion labels in the reviewed homework scene. Its scope is readable live speech cards, not a new dialogue or audio system. The last full-request weighted score remains **7.2/10** under `docs/QUALITY_RUBRIC.md`. No full-game re-rating or 10/10 claim follows from this one repair.

## Exact reviewed evidence

The root-run rendered fixture is `/tmp/justlife-playthrough-z086ahhk`, frozen from `/tmp/justlife-speech-source-t0sm4kk1`. Its manifest hashes match the independently hashed runtime files, and those three files still match the source candidate at review time:

| File | SHA-256 |
| --- | --- |
| `scripts/activity_bubbles.gd` | `67e7c18bf361eaa745f0d96126504a764131c25a6d985835295072c5411103e5` |
| `scripts/actor.gd` | `e69c37f97f62b81a7ae30021ea52481664cfb8dc3aa9e35bf2ca0b8788dbaa44` |
| `scripts/main.gd` | `c41ad0586184f543401f3ee5e4b5ae5c0c30b2e7452958c60229348f175ff52d` |
| `tests/test_supported_homework_ui.gd` | `8741a769482b5e82398ee17a88d1a64b45a6ec924772a9f0998566d40464e1e1` |

The critic read the new layout source, the actor/controller differences from commit `5e4b2b5`, the executed harness, the source snapshot and both result/log files. **72 first-process and 93 restart checks pass, with no runtime error lines in either gameplay log.** These repeat much of the accepted homework fixture and must not be added up as new feature breadth. The new speech-specific evidence comes from the completion/reframing and presentation checks after the restored pair completes.

Directly inspected PNGs under the run's `art/supported_homework/` directory:

- `05_parenting_progress.png`: actual shared-homework completion, named caregiver/learner messages and visible Parenting progress.
- `06_speech_zoom_18.png`, `06_speech_zoom_30.png`, `06_speech_zoom_7.png`: normal, far and near framing of the actual actors.
- `07_speech_small_window.png`: actual 960 × 600 window, confirmed by both root Window and DisplayServer size checks.
- `08_speech_four_actors.png`: controlled simultaneous text supplied to four existing actors at their real positions. This is a wrapping/placement stress case, not evidence that four people naturally had that conversation.

## Findings

The completion text is now plainly readable at all inspected camera distances. White rounded cards, dark words and a smaller colored speaker name fit the existing interface. Parent and child have distinct, relevant completion phrases. Leader lines terminate just above their animated head positions, and the inspected frames do not show cards covering faces or existing HUD panels. At near zoom one card overlaps part of the caregiver's torso; the face remains visible and this is acceptable temporary speech placement.

At 960 × 600 the words retain approximately 16 physical pixels through compensating font/card scaling. The surrounding HUD remains much smaller; this repair does not establish general small-window accessibility. The longer test sentence wraps over three readable lines without vertical truncation. In the four-actor stress image, **three cards are visible: Alex, Leo and Maya; Blair is omitted** when no candidate position fits. The selected Lifelet remains prioritized. That is a reasonable bounded crowd policy, but it is not proof that every participant remains readable simultaneously. The original crowd assertion's text claiming both homework speakers was inaccurate because it only checked the number of visible cards. The author subsequently corrected the harness: pair checks require both exact member IDs, while crowd checks require the selected member plus at least one other visible card. The critic inspected that source correction; it was not represented as a rerun of the earlier 93-check fixture. The already inspected PNGs support these specific identities.

Source inspection confirms camera projection from `get_portrait_center()`, which follows the animated head joint rather than a fixed standing height. Placement considers all visible actors' head rectangles, existing top-level HUD rectangles and previously placed cards. Speech controls ignore mouse input. The CanvasLayer inserts speech beneath the HUD/overlay, and the old Label3D is suppressed to avoid duplicate tiny text. The head-avoidance region is a fixed logical rectangle, so the inspected zooms support the result; they do not prove avoidance for every extreme camera angle, height, age or future UI arrangement.

The executed fixture verifies paused lifetime, modal hide and restoration, removal when speakers leave the camera, and explicit clearing. Source inspection preserves the actor's existing pause-aware lifetime: elapsed real time decreases only during animated play, and an empty presentation removes the card. The original r3 fixture **did not let that clock expire naturally** after resuming; it called `clear_speech()` instead. The critic requested the focused follow-up described below to close that gap without repeating the full homework loop.

## Natural-expiry follow-up

The root-run `/tmp/justlife-playthrough-speech-lifetime-ccjtvvhx` is archived at `art/screenshots/speech_iteration_11/natural_expiry`. The critic inspected its harness, log and results and directly viewed `01_paused_message.png` and `02_expired_message.png`. Its actor/controller/layout hashes are byte-identical to the reviewed r3 product. The executed `tests/test_speech_lifetime.gd` hash is `23511e4f8b83e7c857d89b3ec34ff169b6cc72cba9599aad1abffc00b68d8f2c`.

**16 checks pass, zero failures and no runtime errors.** The public new-game flow creates a real actor; the harness explicitly supplies a short presentation sentence, waits 3.5 seconds paused, opens/closes the actual menu and then presses play. The ordinary frame loop expires both actor presentation and card within the bounded wait, without calling `clear_speech()` or changing the clock. The two images show the named card while paused and its absence after resumed processing. The test is correctly described as controlled presentation evidence, not a fabricated activity completion.

## Limits and decision

The final six images support visual placement/readability; inspected runtime results support the stated control/state checks. No physical clicking through a speech card was performed, and no perceived-audio judgment is made because sound is disabled by the fixture. This source presentation pass does not cover unscripted household conversation variety, every camera angle/age/window ratio, maximum-length names or all modal types. The later package probe is a separate bounded check, described below. Crowded omission and large cards at far zoom are deliberate presentation tradeoffs, not new simulation depth.

**Limited acceptance:** the inspected visual defect is repaired and the natural-expiry gap is closed. No blocking visible product defect was found in this candidate. The game still requires the substantial character, household routine, catalogue and family-system work identified in the full-scope iteration 10 review. Subsequent source promotion and bounded packaged evidence are recorded separately below.

## Promoted source and packaged delivery follow-up

The three accepted speech runtime files were subsequently promoted to the shared source. The critic independently checked that their hashes remain exactly those in the table above. The maintained `--suite speech_lifetime` run `/tmp/justlife-playthrough-v6cqn_td`, archived at `art/screenshots/speech_iteration_11/registered_lifetime`, also reports **16 checks, zero failures and no runtime warnings/errors** with those same product hashes. Its maintained harness writes `playthrough_results.json` for the runner; this repeat is maintenance verification of the same presentation path, not additional game breadth.

The root built `dist/JustLife-speech-v20-candidate/JustLife.x86_64` from frozen `/tmp/justlife-release-u6ywt6oa`. The critic recomputed the executable SHA-256 as **`22050b4a58910301964623257bccf9828a7efa20a57aa29713bc8391a4b8e102`**, matching `build_manifest.json`, and verified **all 82 source-manifest entries** against the frozen files. Production character assets remain v18; this package does not include the experimental r13 hair.

Both root-run package logs report **32 checks, zero failures**, with no script/engine error lines:

- `/tmp/justlife-release-check-speech-v20-s92gkn2z/runtime.log`.
- `/tmp/justlife-release-check-speech-verbose-eg2_ae4t/runtime.log`.

The critic read the exact `release_probe.gd` and both logs, and directly viewed the first run's `03_live_household.png`, `04_save_picker.png` and `05_delete_confirmation.png`. The save picker identifies the named household; deletion provides a distinct keep choice, identifies the exact save and explains which state is retained. The executed probe checks imported models/audio resources, all selectable age assets, a child/adult household and directed family graph, named saving/loading, lifespan/calendar state, canceled and confirmed deletion, and library resources/travel setup. It disables ordinary controller processing and sound, uses button signals rather than physical pointer clicks, and uses controlled hunger values to verify restoration. Its 32 checks therefore establish bounded package loading/flow/state delivery. They do **not** replay the speech zoom/crowd/lifetime scenarios in the binary or certify unscripted gameplay, perceived audio, long-term stability or full-game parity.

### Unresolved exit-cleanup warning

The first package run ends with **`WARNING: 2 ObjectDB instances were leaked at exit`**. The unchanged verbose repeat ends without that warning; it instead contains four RGB8-to-RGBA8 hardware-conversion warnings. There was no intervening source change. The repeat is **not a demonstrated fix**, and this package must not be described as warning-free.

Treat the intermittent ObjectDB warning as an **unresolved P2 cleanup issue**, accepted as a documented risk for this focused milestone. The available logs do not identify the two objects or establish their ownership. They also do not show a crash, failed save check or increasing memory use during play. Neither a specific source defect nor an engine defect can be assigned from this evidence. The conversion warnings likewise have no demonstrated visual failure in the inspected captures; they remain recorded diagnostics, not a claimed repair.

The next useful diagnostic is to capture object identities on a verbose reproduction and inspect the associated ownership/teardown path. If repeated load/travel cycles retain increasing objects or affect gameplay/save state, raise its priority and investigate before broader reliability acceptance. Closing the warning requires an identified cause with appropriate regression evidence, rather than a single clean repeat or suppression of the log.

**Packaged decision: accept the scoped delivery probe with the unresolved exit warning retained.** This adds no full-game certification or score increase; the full-request rating remains **7.2/10**.
