# Residents and visits

Maya Chen and Leo Morgan retain their existing relationship IDs, `maya` and `leo`. Each has a permanent home destination (`maya_home` and `leo_home`). New towns show Maya walking past the front sidewalk, with Leo at home until his next walk. Residents leave the street between walks, and their hidden actors are excluded from social targets. Pausing and Build mode stop resident motion.

Only a current social approach or active conversation holds a walking resident in place. A later queued conversation does not stop their walk; its destination is refreshed when that action actually starts. Completion and cancellation release the resident. If the resident has already left when a deferred conversation reaches the front, that conversation is canceled without rewards; later instructions keep their own routes. Existing wordless Lifelet voices and social animations are used.

A household can arrange a home visit after any member reaches 20 friendship with its resident. The People panel's **All relationships** list provides **Visit home**, and both addresses appear in **Explore**. Clicking an absent resident's name opens their address rather than targeting an invisible actor. Visitors can use furnishings and talk to the resident; Build & buy remains restricted to the player's own home.

Maya's smaller cottage and Leo's wide bungalow have distinct room arrangements, floors, furniture, landscaping and entrances. Both use the same transparent window system as the player's house. Background houses also use two different exterior configurations.

## Travel

The map states that travel takes the household together and clears current activities. A trip checks everyone is available and a sidewalk route exists before canceling activities. It then walks each household member to the curb, shows an original Blender-authored shared car driving away, changes destinations, and shows the car arriving. The household appears at the destination curb. The simulation advances exactly 15 game minutes per completed journey and restores the chosen speed, including pause.

The temporary `travel` mode keeps saving and other gameplay controls unavailable until arrival. A persistent journey caption explains the current step; Escape does not remove it. This version presents boarding and exiting by hiding/showing Lifelets at the curb. It does not yet animate car doors, seat passengers, or support driving controls.

## Persistence

`world_state.residents` is a version-1 dictionary maintained by `LifeResidents`:

- `locations`: destination IDs mapped to `maya`/`leo` route records.
- Each record: numeric XYZ `position`, `rotation`, integer `direction` (-1 or 1), integer `waypoint` (0–2), nonnegative finite `wait`, and `phase` (`walking`, `home`, or `visiting`, constrained by location).
- Stable profiles and ownership come from `LifeResidents.PEOPLE`, never from save-supplied identities.

The selected household member's shared world state also retains the existing `home_layout` and `venue_layouts`. Saving while visiting therefore preserves the player's own furnished house and all resident locations. Older saves lacking resident records receive compatible defaults; their existing friendships are retained. Malformed resident records are ignored safely, with fresh defaults on attachment.

Resident locations away from the currently displayed lot are retained, not simulated in the background. Only Maya and Leo are currently implemented; richer resident schedules and additional households remain future game work.

## Street passers, pace and passing chat

`LifeStreetLife` (`scripts/street_life.gd`) runs the people and dogs who walk the sidewalk in front of the home: two children, a teen, an adult with a dog on a lead, an elder and a lane dog (`ROSTER`). Each walks the lane between x = -10 and x = 10, keeps right (eastbound on the street side, westbound on the house side), and is on the street only at the hours of their kind of person (`hours` windows in hours of the day; nobody is out between 01:00 and 05:00). Off-duty passers wait out of sight at the end of the lane. `tick(delta, game_speed, minutes, obstacles)` moves them by real seconds, so nothing depends on the old per-game-minute unit.

`LifePedestrianPace` (`scripts/pedestrian_pace.gd`) is the one pace table for everyone on the sidewalk, including the four resident neighbours and home-visit guests: elder 0.75, child 0.95, adult 1.10, teen 1.20 and dog 1.25 m/s at Normal speed (indoor wandering 0.75). Distance walked and the gait clock share one factor (`gait_factor`), so the feet cover the ground the body moves at 1x, 3x and 8x. The gait clock stops at three times its authored rate, so pedestrians' ground speed stops there too (`clock_scale`): at 8x dwell and rest timers still run eight times faster but nobody skates. `LifeStreetBodies` builds and animates the bodies (low-detail models of every age, dogs, a lead between the walker and the dog) and gives each a pick capsule; a click resolves through `LifeWorld.pick_extras` as a `passer` item.

A Lifelet who can see a passer (ground floor, within 18 m, no wall between; `LifePassingChat.targets_for`) gets that passer as a `passer` target and may do: **Wave hello**, **Say hello**, a small-talk moment worded for the passer (child, teen, adult, elder), **Compliment their dog** (only for the dog walker), and, for a dog, **Say hello to the dog** and **Pet the dog** (`LifePassingPolicy.ALL`). Indoors the same menu is shown disabled with the reason. The action is queued like any other: the Lifelet walks to a clear spot on the house side of the sidewalk (a metre from a person, closer for a dog pat), the passer is *held* (`hold`/`release`; a dog on a lead holds its walker and the reverse) and turns to face them and answers with a gesture, Social and Fun rise minute by minute like other activities, and a Lifelet meeting the same face again gains a little more (`FAMILIAR_STEP`, capped). The same passer cannot be greeted again for 20 to 90 game minutes depending on the moment, and any two of a Lifelet's passing moments are at least six minutes apart. The passer is released the moment the action leaves the front of the queue for any reason; a hold that nobody renews also lapses after three game minutes, and an approach that takes over 45 game minutes is cancelled with a notice. A passer who leaves, a Lifelet who can no longer see them, or a blocked route cancel the moment with a notice.

An idle Lifelet who is short of company (`social` below 52) and can see a passer may start a moment by themselves (`LifePassingPolicy.autonomy_choice`): a wave first, then a hello, then small talk with a familiar face, gated by a per-Lifelet, per-passer, per-20-minute draw. Queued moments persist through saves like any queued action; `passing_contacts` (passer id to `{at, count}`) and `last_passing_any` are new optional `LifeSim` state fields, validated on load.

`tests/test_pedestrian_pacing.gd`, `tests/test_passing_chat.gd` and `tests/test_hug.gd` cover pace, schedule, gait and hold behaviour, the passing chat flow, and the embrace.

## Verification

Run `python3 tests/run_neighborhood_checks.py`. It creates a private project snapshot with editor services disabled, sets `JUSTLIFE_DATA_DIR` and `XDG_DATA_HOME` to isolated directories, imports it, and runs validation, producer, fresh-process save consumer, queued-absence producer and fresh continuation, and existing neighborhood regression checks. The producer's `user://resident_expected.json` is consumed by the immediately following fresh process. Logs, input hashes and results remain under `dist/test-work/resident-checks-*/evidence`.
