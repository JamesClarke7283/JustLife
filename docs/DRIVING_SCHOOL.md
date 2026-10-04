# Driving school

How a Lifelet learns to drive: the rules, the record the Lifelet keeps, the car and the walk, and what a save holds.

## The rules (`scripts/driving_school.gd`, `LifeDrivingSchool`)

Pure functions with no nodes, clock or wallet. A Lifelet keeps a small record and asks these functions what it means.

* **Who holds a licence from the start.** A Lifelet created as a young adult, an adult or an elder. A save from before licences has no record, so it is built from the Lifelet's age when it loads: licensed from young adult up, unlicensed below. Only a Lifelet who grows up through the teen stage has to learn.
* **When lessons open.** After 20 days as a teenager, counted from the child-to-teen birthday by `LifeLifecycle.days_in_stage` (or from stage progress for a Lifelet created partway through the stage), or on becoming a young adult, whichever is first. The 20 scales with the lifespan setting like every age-tied threshold (`LifeLifecycle.scaled_days`): 10 on a short life, 80 on a long one. Days are calendar days, so they keep counting while automatic birthdays are off.
* **Theory.** One 60-minute **Learn to drive** study session counts for one day, never two on the same day, until seven different days are done. The seven days are fixed at every lifespan. The finishing notice counts as the first reminder.
* **Practical lessons.** Five 90-minute lessons, free, at most one a day, all inside a 14-day course that starts at the first lesson (the course ends on `first lesson day + 13`). The fifth lesson passes the test. If the course's days run out with fewer than five, the lessons start over and the theory is kept.
* **When a lesson may start.** Weekdays 16:00 to 19:30 (after the school bus has gone) and Saturday and Sunday 09:00 to 18:00. Day 1 is a Monday.
* **Booking.** One booking is held at a time (booking again replaces it): the next after-school 16:00, the next Saturday 10:00 or the next Sunday 10:00, each inside a week. A booking is due from its time until 30 minutes later; after that it is given up with a notice. A lesson that has left uses the booking up.
* **Reminders.** Every three days once the theory is done, at 16:00 on a weekday and 09:30 at the weekend, never while a lesson is booked, the Lifelet is away or a lesson was taken that day.
* **What the licence does.** `drive_to_work` is refused without one (so autonomy walks them to work), and in a home with its own car `LifeResidents.begin_trip` needs a licensed Lifelet in the party (`driver_error`; the party pickers grey the Go button with the reason). The town's shared car at the kerb needs no driver. A licensed teenager counts as a driver.

## The Lifelet's record (`LifeSim.driving`)

An optional save key `"driving"`, validated by `LifeDrivingSchool.validate` before anything is adopted and migrated (ints converted from JSON floats) by `migrate`. It does not depend on the Lifelet's age, because Change Age on the farewell dialog can move the age. Change Age gives a fresh record for the new stage (`_on_stage_entered` with source `change_age`); a birthday keeps it.

| key | meaning |
| --- | --- |
| `version` | 1 |
| `licensed`, `licensed_day` | whether they hold a licence; the day the fifth lesson passed (0 for a Lifelet who held one from the start) |
| `introduced_day` | the day the "you can learn to drive" notice was given (0 until then) |
| `theory_days`, `last_theory_day` | 0 to 7 study days and the last one |
| `lesson_days` | the day of each lesson, in order; the number of lessons is its size |
| `last_reminder_day` | the last reminder, or the day the theory finished |
| `booking` | `{}` or `{day, minutes}` |

`LifeSim.driving_status()` is the line the age label's tooltip adds ("Can learn to drive in 3 days", "Learner driver · theory 3 of 7 days", "Learner driver · lessons 2 of 5 · course ends day 43", "Driving licence held"). `LifeSim` runs `_advance_driving` once a minute: the "introduce" notice (07:00 on the day lessons open, once), reminders, giving up a missed booking and the course lapse. The notice and the licence go out as `milestone` kinds `driving_introduced` and `driving_licensed`, which `LifeAnnouncements` shows (a card banner with a letter, and the big celebration).

## The lesson absence (`LifeSim.begin_driving_lesson`, `_tick_lesson_away`)

A lesson is a saved `driving_lesson` action at the neighbourhood exit. It is the front action while the controller plays the car and the walk. When the car has left, the controller calls `begin_driving_lesson`, which re-checks the rules (not the window: a lesson that has left is not turned back because the window closed on the way), uses up the booking and makes the absence:

`away_state = {version, activity: "driving_lesson", phase: "away", departure_day, departure_minutes, return_day (same day), return_minutes (departure + 90), exit_id: "lot_exit", exit_position, age_stage, lesson (the number of this lesson), completed, ended_at}`

The lesson's own clock accrues time and effects while away. At 90 minutes `_tick_lesson_away` credits the lesson (so a save on the walk home keeps it), adds the "Behind the wheel" mood, and on the fifth lesson licenses the Lifelet. Cancelling while away, or a new day, brings them home early through `request_return_home` and counts nothing. A birthday never cuts a lesson short (`BIRTHDAY_HOLD_ACTIVITIES`). `DrivingSchool.lesson_away_error` is the save check: the lesson is the front action, 90 minutes long, credited in `lesson_days` only once completed, never before the theory.

## The car and the walk (`scripts/driving_lesson.gd`, `scripts/lesson_car.gd`)

`LifeDrivingLesson` is owned by the main controller as `driving_lesson`, beside `work_commute`, and plays one lesson at a time through a phase record saved on the action as `action.lesson`:

`arrive` (the car drives in along the road to the kerb spot, using `LifeVehicleDrive.kerb_path(true)`), `walk` (the learner walks to the front door of the car), `board` (`LifeCarEntry`: door, seat, close), `depart` (`kerb_path(false)`; at its end the lesson absence begins), `away` (nothing visible), `return` (the car arrives again), `exit` (`tick_exit`), `back` (the learner walks in through the front door by `work_commute.front_route`, while the empty car drives away as an orphan).

* **The kerb rule.** The car waits, out of sight and with the lesson not moving, while `LifeSchoolBus.active.phase != "gone"`, a birth arrival is running or an earlier lesson car is still leaving. Trips and house moves are refused while a lesson is running (`running()`).
* **The car** is the household's Juniper model (`LifeLessonCar.build`) in the school's blue, with a white board and red L (plain boxes, no font) on the bonnet and the boot lid and a four-sided L sign on the roof. `LifeLessonCar.active` is the car on the lot, and `LifeVehiclePlanner.scene_from_world` adds it to the street obstacles so household cars wait for it.
* **Requests and bookings.** `request(member_id, give_way)` checks the household can take a lesson now and queues it; the panel's **Have a lesson now** passes `give_way` when everything queued is the learner's own choosing, so a pastime is put aside as for a booking, while a player-queued plan is still asked about first. `consider_bookings()` runs every live frame: a due booking cancels a pastime (never a duty, ritual, need break or shared action: see `KEEPS` and `LifeSim.homework_enforcement_blocked`) and requests the lesson.
* **Saves.** The car is not saved. It is rebuilt from the phase and its time, and the learner's position is checked by `cabin_position_matches` and the journey record (`journey_state.gd` and `traversal.gd` treat the lesson's walk like a commute's). Saves in every phase load and carry on (`tests/test_driving_lesson_car.gd`). `LifeDrivingLesson.save_error` validates the record.

## Priorities

A lesson that has left or is due to start soon wins over the teenage homework curfew: `LifeSim.HOMEWORK_YIELDS` lists `driving_lesson`, and `_enforce_mandatory_homework` also steps aside for a queued lesson or a booking due within 45 minutes. Homework can still be done after the lesson (it is allowed until 23:00). Leaving for school or work and a running birthday ritual are never interrupted by a booking; the booking waits out its 30 minutes of grace.

## Not done

A booked lesson is not on the phone calendar (the calendar's filters are fixed at school, work and birthdays); a pending booking shows in the booking panel.
