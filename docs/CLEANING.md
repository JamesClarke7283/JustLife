# Household cleaning

Every home gathers dirt, and every Lifelet from child to elder can clean it: by clicking one thing, by asking a housemate to **Clean Home**, or, if they are comfortable and tidy-minded, on their own. Babies and toddlers are left out.

## What can be cleaned

A chore is an ordinary queued action. Each has its own tool, its own motion and its own zone of dirt.

| Action id | Chore | Minutes | Who | Tool and motion |
| --- | --- | --- | --- | --- |
| `chore_vacuum` | Vacuum a patch of floor | 3.5 | child and up | Canister vacuum: floor head and wand in both hands, long push-and-pull strokes drifting across the patch, the canister following on its sagging hose. |
| `chore_mop` | Mop a patch of hard floor (not carpet, not under a rug), including the bathroom floor | 4 | child and up | The existing juniper mop and its measured mopping pose, with the head wandering over the patch. |
| `chore_vacuum_curtains` | Vacuum a panel of curtain | 8 | teen and up | Hand nozzle on the hose, five passes across and down from the top; the other hand holds the nozzle. The fabric sways. A step stool for the top. |
| `chore_dust` | Dust a table top or shelf face | 2.5 + .4 per metre | child (low pieces) and up | Feather duster: side-to-side sweeps along a top, or vertical lanes down a face. |
| `chore_fluff` | Fluff the cushions of a seat | 3 + .75 each | child and up | Both hands lift each cushion in turn, pull it toward them, shake and set it down; the cushion really moves and squashes. |
| `chore_wipe_sink` | Wipe a sink (kitchen or bathroom) | 5 | teen and up | Sponge circling in the basin, the other hand on the worktop, a rinse at the tap. |
| `chore_scrub_toilet` | Scrub the toilet | 8 | teen and up | Squatting over the bowl with the brush, circling. |
| `chore_sweep_entry` | Sweep the front or back entry (porch and its two steps) | 6 | child and up | Broom in both hands, sideways sweeps with a forward flick; leaves go off the edge. |
| `chore_wipe_door` | Wipe an exterior door | 5 | child (as high as they reach) and up | A spray, then a cloth: circles round the handle, then vertical lanes. |
| `chore_wash_window` | Wash the inside or the outside of a window | 7 | teen and up | A spray, then a squeegee down the glass in lanes (a step stool when it brings the top within reach of an adult or teen, otherwise an extension pole; elders and the expectant never climb, so they use the pole), then a cloth round the frame. A sparkle at the end. |

The chain also uses actions that already exist: `mop_puddle`, `clear_table`, `empty_bin`, `clean_litter_tray` (elders may now clean trays too) and `put_pet_toy` for every toy lying on the floor, a pet's or a child's.

Wide things are worked in parts one stand can reach: a window or the front door is two stations, curtains two panels, a long table two halves and a sofa one station per seat. The two back windows of the starter home sit behind the kitchen counters; their inside faces say "Move the furniture to reach this window".

Reach decides what a Lifelet may do. The measured top reach of each body (child 1.21 m, teen 1.67, young adult and adult 1.92, elder 1.88) gives a comfortable height; above it an adult or teen takes the step stool (not while expectant), an elder or expectant Lifelet takes the pole where the chore allows one, and a child is refused with a reason ("Too small to reach that yet."). Outdoor chores wait for daylight (07:00 to 17:30).

## How dirty is the home

`LifeChores` (`scripts/chores.gd`) holds one number per zone: the game minute it was last cleaned. Nothing ticks. A zone's dirt is how far along its own period that is (a sink two days, a floor three or four, a window eight to ten, a curtain fortnightly; busier households and pets shorten them). A zone seen for the first time, whether in a new game, an old save or a newly bought piece, is stamped now, so a home never turns filthy overnight because of an update. Some activities soil things: the toilet soils the toilet and bathroom sinks, cooking the kitchen sink and the floor near the stove, a shower the bathroom floor, coming and going the entry and the floor by the door, a child's play leaves real toys on the floor (see below).

`LifeChoreFlow.home_score()` weights the categories (floors 30%, windows 15, dust 15, bathroom 15, kitchen 10, entry 10, the rest small) into the "N% clean" the HUD shows. A score under 40 gives everyone at home a once-a-day "A grubby home" mood.

## Stations

`LifeChoreSites` (`scripts/chore_sites.gd`) turns the home into stations: a dirt key, where to stand, which way to face, where the work lands and how high it reaches. They are rebuilt when furniture, doors or walls change and published as simulation targets (`world.chore_targets`, appended in `LifeWorld.simulation_targets`), which is what keeps a queued chore alive through the controller's target refresh. Ids look like `chore:fvac:0:2:-1` or `chore:win_out:win_0_-425_-504:1`.

## Rounds

`LifeChoreFlow.start(member_id, mode, categories)` plans a round for one Lifelet (`quick`: dirt of 50% or more, capped near ninety minutes; `full`; `inside`; `outside`; `custom` with chosen categories) and queues its first task. Each queued task carries what remains of the round in its `chore` record (`plan` as `action@target` strings, `index`, `total`, its label and effects). Finishing one pushes the next to the front of the queue before the Lifelet could walk off, so there is no gap, a save keeps the round for free, and cancelling the front action (the HUD's **Cancel action**) cancels all of it. The order is spills and dishes, toys, cushions, dust, curtains, windows inside, floors (vacuum, then mop, each by the shortest walk), sinks, toilet and bathroom floor, then outside.

A round ends early with a notice if somebody else's order waits behind it or a need (hunger, energy, bladder) falls under 20. A task whose target vanished, or that cannot be reached, is dropped and the round carries on. Two Lifelets can run rounds together: each takes the first task nobody has reached and nobody has already done. Players are never stopped by school or work; those are theirs to weigh, as with any queued activity.

## Controls

* Click a **housemate**: a **Household** ring with **Clean Home** (it never appears on a visitor's or neighbour's wheel). Control does not switch.
* Click the **selected Lifelet**: their card has **Clean Home…**.
* Both open the **Clean Home** panel: *Quick tidy*, *Full clean*, *Inside only*, *Outside only* (each with its task count and time), and a row for each part of the home (Floors, Dust, Windows, Curtains, Cushions, Toys, Kitchen, Bathroom, Entry and doors, and Spills, dishes and bins) with its dirt, to tick.
* A compact **Clean Home · N%** button beside Cancel action opens the same panel for the selected Lifelet; its tooltip names the dirtiest places.
* The action line reads **CLEANING HOME — 4 OF 38**; a notice and a "tidy home" mood close the round.
* Single chores are also offered where they are done: sofas and armchairs, sinks, the toilet, tables and shelves, curtains, bought windows; a toy on the floor offers **Put toy away**.

## Unprompted cleaning

`LifeChoreFlow.autonomous_choice` is called from the housekeeping slot of `LifeSim._autonomous_choice`, after needs, school and work. It returns one task, never a round, and only when the Lifelet is idle, it is between 08:00 and 21:00 (07:00 to 17:30 outdoors), every need is at least 55 and energy and hunger at least 50 and 45, nobody else is cleaning unprompted, ninety minutes have passed since their last, and the home is under 55% clean (75% for a Neat Lifelet). A child takes no station chore on their own, but puts toys away through the toy flow (`LifeToyFlow.autonomous_tidy_choice`, tried before this in the same slot). The task is flagged autonomous, so a falling need or a due duty interrupts it like any other. A Neat Lifelet finishes chores 15% faster and enjoys them; elders are 25% slower and children 15% slower.

## Saves

Additive only. The household extras gain `chores`: `cleaned` (zone key to game minute), `toys` (a legacy count of toys left out per box, no longer used: toys are items now) and `auto_next` (cooldowns). An older save has none and loads spotless. A queued chore adds an optional `chore` record validated in `LifeSim._validate_state` (`LifeChoreDefs.save_error`); a chore saved part-done reloads painted at that moment, tool in hand. A corrupt cleaning record or round refuses the load like any other.

## Acting

Props are built in code (`scripts/chore_props.gd`) and posed by `scripts/chore_motion.gd`, plugged into `ActorMotion.handles/apply`: tools are placed from the contact point, hands solved to their grips, the body leaned from the hips and stepped just far enough to reach, ankles kept planted, and anything still out of reach is pulled in so a hand never leaves its tool. The motion reads only the station facts the controller puts in the activity anchor (`chore_*` keys), so a paused or reloaded task shows exactly where it was. `tests/test_chore_motion.gd` measures 11 chores at six points through each task for fourteen body configurations (both frames; adult, young adult, teen, child and elder; small and large builds): hands stay within 30 mm of what they hold and ankles within 12 mm.

Windows and doors are hidden when the walls are lowered, so one being cleaned is shown for the duration. Window glass shows a grey haze (cleared lane by lane), doors a smudge, and doorsteps leaves (`scripts/chore_visuals.gd`).

## Hooks in shared files

`LifeSim` (`chore_service`, the `_define` loop, `queue_action`, `enqueue_prepared`, `push_chain_action`, `begin_current_action`, `cancel_action`, `_finish_front`, availability, validation, restore and the autonomy slot), `main.gd` (service wiring, target refresh, per-frame sync, activity anchor, resources, vanished and blocked targets, the HUD button, card button, wheel ring and panel), `actor.gd` and `actor_motion.gd` (the pose hooks and the `chore_mop` alias to the mopping pose), `world.gd` (`chore_targets`, two doorstep steps), `household_flow.gd` (the `chores` extras), `wants_manager.gd` (the Neat whim).

Tests: `test_chores.gd`, `test_chore_motion.gd`, `test_chore_live.gd`, `test_chore_visuals.gd`, `test_chore_save.gd`, `test_chore_wheel.gd`, `test_chore_autonomy.gd`, `test_chore_upstairs.gd`.

## Toys

Toys are not a dirt zone. A toy lying on the floor (a pet's toy, or a child's or baby's toy that play left out) is a real item, and putting it away is `put_pet_toy` of `LifeToyFlow`: the Lifelet walks to it, bends right down, picks it up, carries it to a box that takes it and sets it in (see [the pets guide](PETS.md)). The **Toys** row of the panel counts the toys out, a round plans one real tidy for each (nearest first, right after spills and dishes), and a child does the same unprompted when idle. An earlier abstract "toys left out of a box" count and its pose were retired in favour of the real thing; its saved count is still read and ignored.

## Edges worth knowing

* The time shown for a round (the panel, the wheel, the notice) is the work **and the walk** to each task, at about a metre a game minute; a quick tidy is capped on that total.
* Stamps are kept while a piece is picked up to be moved or put back, so lifting a filthy sofa and pressing Esc does not clean it; they are dropped only once the move is over and the piece is gone. A different house (a move) starts with none of the old one's dirt.
* A window whose wall has been taken down is not offered for washing, and a station for a piece whose own standing place lies beyond another piece is refused ("Move the furniture to reach it") rather than worked through the furniture.
* An idle Lifelet who would clean unprompted tries the next few best places when the best-scored one cannot be reached, so one walled-off corner cannot stop the cleaning everywhere.

