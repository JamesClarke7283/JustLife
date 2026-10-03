# Lifecycle implementation checkpoint

`LifeLifecycle` owns age labels, original stage durations, legacy migration and save validation. `LifeSim.lifecycle` stores fractional stage progress, short/normal/long pace, automatic birthdays and chronological transition history. Normal stage lengths are 20/21/28/42/28 days for child/teen/young adult/adult/elder; short is half and long four times those durations. These are JustLife balance choices, not a claim about current Sims 4 tuning.

The simulation advances age by elapsed game minutes. Pause and disabled automatic birthdays stop that progress. Changing pace preserves the fraction of the current stage, and sequential birthdays preserve traits, skills and relationships. An explicit birthday is a queued 45-minute fridge activity costing ℒ30. Its confirmation states the next stage before queuing; cancellation of the confirmation preserves age and money. The actor holds an original Blender cake, blows out its candles and applauds. Independent normal-game evidence verifies the held cake, three lit candles, extinguished flames, applause and eventual age change; see `REVIEWS/iteration_07_presentation.md`.

`age_stage` describes chronological appearance. `life_stage` continues to express existing adult/minor/unknown interaction eligibility. Child and teen map to minor; young adult, adult and elder map to adult. Household birthdays update reciprocal eligibility, emit `member_age_changed`, and refresh the affected actor and portrait. Old adult saves migrate to young adult; old minor saves migrate to teen without granting adult eligibility. Invalid or inconsistent age/history data is rejected before the live household is changed.

Public controls: **Creator → Age**, **Esc → Life settings**, and **My Lifelet → Celebrate a birthday**. Creator age options become available only when the actor reports support for their authored models. UI cameras can use actor-local portrait center and display height. Children need a teen or adult in their household to move in.

This is an incomplete lifecycle checkpoint. Newborns, infants, toddlers, birth/adoption, parenting interactions, death and inheritance remain required work. An elder whose stage has run its course reaches the farewell dialog and passes on (`LifeLifecycle.due_to_pass_on`, `LifeSim.pass_on`). Schooling has a separate persistent module. This checkpoint does not establish full generational gameplay or a 10/10 rating.

Validation: `tests/test_lifecycle.gd` initially passed 27 assertions alongside all 259 pre-existing simulation/progression/household/story/save/relationship/family assertions. The independent school playthrough later passed 116 rendered/restart checks for public child/adult creation, real homework/classes, child-to-teen birthday/model replacement and school history persistence; see `REVIEWS/iteration_07.md`. The boundary review adds 62 adversarial checks for delayed actions, target mutation, birthday races and save observers. Late birthday enrollment defers the first possible class to the following day while permitting that evening's homework; 22 focused enrollment checks cover old-save migration and calendar validation.

## The day a stage began

Rules tied to how long someone has been a teenager or an elder count calendar days, so they keep counting when automatic birthdays are off. `LifeLifecycle.days_in_stage(state, stage, day)` answers in whole days. It reads the newest of two records: the `day` of the last birthday in `history` that reached the stage, and `lifecycle.stage_day`, an optional key the sim writes the first time it ticks or is saved (the household sets the shared clock only after a Lifelet is created), at every birthday and when Change Age picks a stage. A save from before `stage_day` takes it from its history when it loads; a Lifelet created partway through a stage with no history is dated from the stage progress. `LifeLifecycle.scaled_days(normal_days, lifespan)` scales an age-tied number of days with the lifespan setting (short is half, long is four times); fixed spans such as a seven-day course do not use it. `LifeLifecycle.milestone_text(first_name, stage)` is the centre-banner wording: "Kit is now a teenager!".

Change Age on the farewell dialog (`LifeSim.cancel_pending_passing`) rewrites the birthday history (`history_after_change`) and starts a fresh school record that keeps earlier terms, so the save always loads. It runs the same `_on_stage_entered(previous, next, source)` hook as a birthday, with source `"change_age"`, and sends no milestone.

## Milestones and the centre banner

`LifeSim.celebrate_birthday(start_next_action, source)` takes a source word (`"auto"` when the lifespan clock runs out, `"cake"` for the paid fridge celebration) and keeps it in `last_birthday_source`. It leaves a hospital stay, a prison sentence and a driving lesson running instead of calling the Lifelet home, calls `_on_stage_entered` for features that begin with a stage, and sends `LifeSim.milestone(kind, data)`. A feature that has its own milestone sends it with `LifeSim._emit_milestone(kind, data)`. The household relays that as `LifeHousehold.member_milestone(member_id, kind, data)`, never while a save is being restored; `age_changed` and `member_age_changed` keep their two and three arguments. A birthday also posts the "Many happy returns" card to the post box.

`LifeAnnouncements` (`scripts/announcements.gd`, `main.announcements`) turns each milestone into what the player sees, one at a time, only in the house and with no pausing menu open, and drops everything waiting when a game is loaded:

| Kind | What the player sees |
| --- | --- |
| `birthday` | Grand banner and fanfare: "<First> is now <a child / a teenager / a young adult / an adult / an elder>!" for every stage change, automatic or paid. |
| `retired` | Grand banner: "<Full name> is now retired". |
| `retirement_eligible` | Corner notice and a letter. |
| `driving_introduced` | Card banner (no streamers, no fanfare) and a letter. |
| `driving_licensed` | Grand banner. |
| `pension` | Corner notice with the amount. |

`data.text` replaces the default notice or detail line. `LifeMilestoneCelebration` (`scripts/milestone_celebration.gd`) is the banner itself: a centred card, 240 streamers and confetti bursting from the bottom corners, and one fanfare player, all mouse-transparent and gone after seven seconds. `CelebrationAudio` makes the fanfare, the birthday melody (the public-domain 1893 tune, notes only) and an eight-second party loop from arithmetic, built once on a worker thread. `LifePartyMusic` plays the birthday tune and the party loop, turns the theme down by volume (never pauses it), follows the Sound and Music switches and holds still while the household is paused.
