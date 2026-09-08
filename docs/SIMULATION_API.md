# LifeSim integration

`scripts/life_sim.gd` is a `Node` with class name `LifeSim`. It does not process itself. Instantiate it, add it to the scene tree, and call `sim.tick(delta)` from the world's `_process`. One real second advances six game minutes at speed 1. Supported speeds are `0`, `1`, `3`, and `8`. Clock starts at day 1, 08:00. Need decay and action durations use game minutes.

## World and character setup

- `new_household(profile: Dictionary)` resets all household state. Profile fields `name`, `traits` (up to three of Creative, Outgoing, Active, Bookworm, Foodie, Neat), and `aspiration` (Maker, Connected, Successful, Balanced) drive simulation. Other appearance fields are preserved unchanged.
- `register_targets(targets: Array)` supplies autonomy with `{id: String, kind: String, position: Vector3}` entries. Re-register when furniture moves. Autonomy considers actions after 15 idle game minutes and only when a need falls below 52.
- Set `autonomy` directly; call `set_speed(value)` for clock control.

## Interactions and movement

1. `get_actions_for(kind, target_id = "")` returns an Array of dictionaries with `id`, `label`, `duration`, `changes` (need deltas), `cost`, `skill`, `xp`, `description`, `available`, and `unavailable_reason`. Supplying the target makes social requirements accurate for that Lifelet. Supported kinds: fridge, stove, bed, shower, toilet, sofa, bench, tv, bookshelf, easel, desk, plant, neighbor. A bench offers relax, read and nap. Aliases kitchen, bath, chair, computer, maya, leo also work.
2. `queue_action(id, target_id = "", target_position = Vector3.ZERO) -> bool` queues one of at most eight actions. IDs: snack, cook, sleep, nap, shower, toilet, relax, watch, read, paint, work, study, job, water, friendly, joke, deep_talk, flirt, argue, ask_partner, commit, break_up.
3. `action_started(action)` emits when an action becomes first in the queue, with `phase = "approach"`. Move the character to `target_position`, then call `begin_current_action()`. Calling it repeatedly is safe. Money is charged at this point, only once.
4. The action becomes `phase = "active"`; `elapsed` advances in game minutes, `progress` ranges from 0 to 1. Need and skill changes accrue during activity. The world can animate based on its `id`.
5. `action_finished(action)` emits on completion and the next queued action starts. Completion bonuses (income, relationship changes, wants) happen once.

`get_current_action()` returns the front dictionary or `{}`. Public `action_queue` exposes the whole queue; later entries have phase `queued`. `cancel_action(index = 0)` removes a queued or active item and advances the queue when needed. Started activities do not refund ingredients; partial need and skill gains remain. Social target IDs may be `maya`, `leo`, or a household member ID. The exact aliases `neighbor_maya` and `neighbor_leo` also resolve.

## Reconsidering blocked autonomy

`reconsider_waiting_autonomy(blocked_target_ids: Array, waited_game_minutes: float) -> bool` replaces only an **autonomous front action in approach**, after at least 30 game minutes of waiting. It excludes unavailable objects, considers recoverable needs below 52 in ascending order, and can choose another object or another depleted need. A blocked bed can therefore lead to a sofa nap; a blocked bed and sofa can lead to food or another available recovery activity. The returned `true` means the replacement was queued and its normal movement signal emitted. Later queued actions remain unchanged.

Explicit player-directed actions, disabled autonomy, coordinated sessions, active actions and brief waits are preserved. The controller checks availability and requests reconsideration; LifeSim does not reserve furniture or move actors. The controller retries an unsuccessful reconsideration after another 15 game minutes. This policy does not yet schedule school, homework or employment autonomously, and social choices still favor earlier registered targets. `tests/test_waiting_autonomy.gd` covers alternative recovery, urgent hunger, preserving directed/paired work, and both fun-selection trait branches (11 checks).

## Relationships and adult partnerships

`get_action_availability(action_id, target_id = "") -> {available, reason}` exposes the same gate used by the menu and action queue. Romantic eligibility is checked when queued, again on arrival, and again when a partnership action finishes. An unknown target is rejected instead of silently changing a different relationship.

| Action | Requirements | Outcome |
| --- | --- | --- |
| `ask_partner` | Both adults; both available; at least 45 friendship and 35 romance | Establishes a partnership |
| `commit` | Current partners; both adults; at least 65 friendship and 65 romance | Records a shared commitment |
| `break_up` | Current adult partners | Ends the partnership; friendship −12 and romance −35 |

Household pairs must meet the friendship and romance thresholds on both sides. `LifeHousehold` supplies actual partner, adulthood and reciprocal-score context, synchronizes accepted changes to the receiving Lifelet, and prevents multiple members from partnering the same neighbor. A couple's partner IDs and relationship stages must be reciprocal in saved data. Relationship milestones do not grant money or satisfaction.

`character.life_stage` and each relationship's `life_stage` use `adult`, `minor` or `unknown`. The existing adult-only avatar saves migrate to explicit `adult` values. Only `adult` participants can use romantic interactions; the other values are data guards, not child or aging features. New relationships also have `bond` (`none`, `partners`, `committed`, `separated`) and a `milestones` array. `romantic_partner` holds the current partner ID or an empty string.

`social_history` retains the latest sixty `{day, minutes, target_id, target_name, stage, label, detail}` entries, newest first. Stages are meeting, friendship, close friendship, a romantic spark, partnership, commitment and separation. Friendship milestones record once; a new partnership after a breakup is a new event. Both playable participants receive their own history. These memories also appear in the Lifelet's general diary. The actor uses the existing original wordless voices and conversational gestures for the three new interactions.

## UI state and signals

- `changed()` emits every 0.2 simulation seconds and on user mutations; `notice(text)` emits player-facing events.
- `needs`: hunger, energy, hygiene, bladder, fun, social, each float 0–100.
- `funds`, `day`, `minutes`, `speed`, `satisfaction`, `bills_paid`: numeric values.
- `character`: full profile, including name, appearance fields, traits and aspiration.
- `skills`: cooking, creativity, charisma, logic, gardening; each `{level: int, xp: float}`. Next level requires `level * 50` XP; cap 10.
- `relationships`: maya and leo, each `{name, friendship, romance, status}`. Friendship ranges −100 to 100, romance 0–100.
- `career`: `{track, title, level, performance, salary, worked_day}`. `CAREER_TRACKS` offers studio, culinary, technology and community work. `choose_career(track_id) -> bool` changes jobs unless a shift is queued. A job shift pays once daily; freelance work is unrestricted. Completing enough shifts earns a promotion and bonus. Household bills cost §35 each midnight; no automatic wages. `household_bills_enabled = false` disables duplicate bills for other Lifelets in the same household.
- `wants`: `{id,label,description,progress,target,reward,complete}` dictionaries. Completing each pays its reward in satisfaction and household funds once.
- `get_mood()`: `{label, description, color: Color}`; `get_clock_text()` formats `Day 1 · 08:00`.
- `get_state()` returns a deep snapshot suitable for inspection; it includes live Vector3 queue positions.
- `moodlets` contains up to eight timed `{label, emotion, description, remaining, strength}` effects. `memories` keeps the latest forty `{day, minutes, label, detail}` entries. `add_moodlet(...)` and `remember(...)` add entries; moodlets expire with game time and influence `get_mood()` after critical needs are considered.

## Sustained aspiration progression

The opening chapter has three wants. Children begin with **A little independence**, fulfilled by a completed fridge snack, because their stove cooking is unavailable. Other ages begin with the first cooked meal. Old uncompleted child cooking wants migrate to the attainable snack goal without paying a reward; already fulfilled wants remain intact. After all three complete, the chapter is archived and the next chapter opens the following morning. There are always three current wants. Completed wants remain visible until the next chapter opens, and each reward pays only once.

`get_aspiration_progress() -> Dictionary` returns `{stage: int, title: String, next_stage_day: int, history: Array}`. A zero `next_stage_day` means the current chapter is still in progress. `aspiration_history` keeps the latest sixty completed chapters, newest first, with `{stage, title, completed_day, reward, wants}`. Historical rewards are accounting entries and are not paid again on loading.

Recurring Maker chapters combine paintings, other creative interests and friendly conversations on two days. Connected chapters combine Charisma practice, three conversation types and friendships maintained across two days. Successful chapters combine new earned income, practice in the career skill and varied recovery activities. Balanced chapters combine two days with every need at least 55, varied activities and company. Targets grow moderately through chapter seven and then stay bounded. Practice still counts at skill level ten, so late chapters remain achievable.

Additional fields on recurring wants are `metric`, `actions`, `skill`, `seen` and `seen_days`. The simulator owns these counters. Partial practice accrues with activities, while action counts and variety require completion. Income goals count completed work and painting payouts; story grants and want rewards do not satisfy those income goals. Social-day and self-care-day goals count each calendar day only once, including after a JSON save/load.

## Daily story choices

Call `get_story_events() -> Array` to show pending choices. Each event is `{id, kind, day, title, description, choices}`. Each choice is `{id, label, effects: String, available: bool, unavailable_reason: String}`. `effects` lists the exact costs, payouts, need deltas, XP, friendship and career changes. Availability is recalculated from the current funds and skills whenever the API is read.

`choose_story_event(event_id: String, choice_id: String) -> bool` applies the selected effects immediately, records the decision, emits `changed`, and removes that event. It returns false without changing state for unknown IDs or unmet requirements. The event is removed before effect notifications, preventing reentrant listeners from paying it twice. Choosing a story does not advance time, move the Lifelet or replace the action queue. Need and relationship changes respect their normal bounds. Story choices can be made while the clock is paused.

One opportunity is offered each midnight starting on day two, cycling through neighbor supper, career project, hobby exhibition, garden exchange, library learning circle and community picnic. There are at most three pending opportunities. Unanswered events remain available without penalties; a full pending list skips new offers until space is available on a later day. The recurring cycle alternates neighbor context and captures relevant career/creative skill context at the time of the offer. Every event has an available option that requires no funds.

The first event is `story_day_2`, **An extra place at the table**:

| Choice ID | Label | Effects |
| --- | --- | --- |
| `bring_dish` | Bring a homemade dish | Pay §24; Hunger +12, Social +24, Fun +10, Energy −8; Cooking +20 XP; Maya friendship +14 |
| `walk_together` | Suggest a walk together | Energy −10, Fun +15, Social +18; Gardening +12 XP; Maya friendship +8 |
| `keep_day_free` | Keep today to myself | No cost or stat changes |

`story_history` keeps the latest sixty decisions, newest first: `{event_id, kind, title, offered_day, day, minutes, choice_id, choice_label, effects}`. Raw `story_events` contains compact internal tickets; use `get_story_events()` for display. Event identity/context, chapter progress and decision history are validated before a save is applied. Old saves without these fields load with chapter one and empty story histories.

When using `LifeHousehold`, apply a choice to the selected member's simulator and call `household.adopt_selected_changes()` to immediately synchronize its funds change to the shared wallet before refreshing household UI.

## Save / load

`save_game(world_data: Array = []) -> bool` writes a validated-format JSON snapshot atomically via a temporary file to `user://justlife_save.json`. Arbitrary world placement dictionaries are passed through; Vector3 values become numeric `[x,y,z]` arrays and Colors become HTML strings. The world owns decoding its own placement fields.

`load_game() -> Dictionary` returns `{ok: true, world: Array}` on success or `{ok: false, error: String}`. Corrupt or unsupported saves do not mutate live state. `restore_state(state)` uses the same validation for in-memory snapshots and is useful in tests. Queue actions resume with preserved elapsed time and ingredient payment, but first enter `approach` so the world can position the actor before `begin_current_action()`. Connect signals before loading, or inspect `get_current_action()` afterward.

Tests include `tests/test_simulation.gd`, `tests/test_progression.gd`, `tests/test_household.gd`, `tests/test_story.gd` and `tests/test_relationships.gd`. The story suite completes the initial Maker goals, plays a second chapter across days two and three, reaches chapter three on day four, makes three different choices, and performs a real JSON save/load. It also verifies pending limits, free declines, skill-gated choices, reentrancy protection, skill-cap progress and legacy/corrupt saves. Relationship tests cover both adult gates, mutual score requirements, unavailable/stale proposals, staged history, commitment, breakup, reciprocal household state, neighbor exclusivity and JSON persistence. Run these in an isolated test project without the editor MCP autoload.

## Schooling and birthday transactions

Each LifeSim stores `education`, validated by `LifeEducation`. Children and teens can queue `school` at registered desks/computers (label: **Attend online classes**, 180 minutes, weekdays 08:00–14:00) and `homework` at desks/computers/bookshelves (45 minutes, weekdays by 23:00). Completion applies learning and need effects once; cancellation grants no attendance or learning. Duplicate daily reservations, missing/wrong furniture, late arrivals, expired resumed classes, and incompatible age stages are rejected or cancelled. Saved school actions include the original furniture kind and start day/minute; strict validation checks duration, progress, dates, and eligibility.

Daily updates finalize attendance. Birthday transitions archive the completed school stage, apply any earned graduation effects once, and clear incompatible schoolwork. Late-day enrollment starts attendance obligations on the following school day. Older saves without education receive a fresh term appropriate to their current age and calendar.

Birthday queue entries bind `birthday_from_stage`, so a natural birthday cannot cause a queued celebration to advance a second stage accidentally. Age, lifecycle history, education records, and queue cleanup commit before age/change/action-start observers run. An optional internal `celebrate_birthday(start_next_action=true)` argument lets the action-completion path start the surviving next action exactly once.

## Fresh familiar-face wish

New Lifelets receive a `familiar_chat` goal for “A familiar face”: complete a friendly chat, joke or heartfelt talk with a target whose friendship reaches at least35. Pre-existing family friendship alone does not complete it. Both participating household Lifelets can satisfy their own goal; rewards enter each participant's ordinary simulation tick so the shared wallet counts each one exactly once. Canceled partial actions do not count.

Older saved `friend` wants keep their absolute-friendship semantics, and completed rewards remain completed. The new goal uses existing action-progress fields and a one-conversation target. `tests/test_familiar_chat.gd` passes24 checks for fresh family start, threshold, cancellation, reciprocal participation, once-only rewards and old/new JSON persistence. The related simulation/story/progression/child-want/family/save and genealogy regression suites also pass.
