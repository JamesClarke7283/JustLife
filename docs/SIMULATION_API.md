# LifeSim integration

`scripts/life_sim.gd` is a `Node` with class name `LifeSim`. It does not process itself. Instantiate it, add it to the scene tree, and call `sim.tick(delta)` from the world's `_process`. One real second advances six game minutes at speed 1. Supported speeds are `0`, `1`, `3`, and `8`. Clock starts at day 1, 08:00. Need decay and action durations use game minutes.

## World and character setup

- `new_household(profile: Dictionary)` resets all household state. Profile fields `name`, `traits` (up to three of Creative, Outgoing, Active, Bookworm, Foodie, Neat), and `aspiration` (Maker, Connected, Successful, Balanced) drive simulation. Other appearance fields are preserved unchanged.
- `register_targets(targets: Array)` supplies autonomy with `{id: String, kind: String, position: Vector3}` entries. Re-register when furniture moves. Autonomy considers actions after 15 idle game minutes and only when a need falls below 52.
- Set `autonomy` directly; call `set_speed(value)` for clock control.

## Interactions and movement

1. `get_actions_for(kind)` returns an Array of dictionaries with `id`, `label`, `duration`, `changes` (need deltas), `cost`, `skill`, `xp`, `description`, and `available`. Supported kinds: fridge, stove, bed, shower, toilet, sofa, tv, bookshelf, easel, desk, plant, neighbor. Aliases kitchen, bath, chair, computer, maya, leo also work.
2. `queue_action(id, target_id = "", target_position = Vector3.ZERO) -> bool` queues one of at most eight actions. IDs: snack, cook, sleep, nap, shower, toilet, relax, watch, read, paint, work, study, job, water, friendly, joke, deep_talk, flirt, argue.
3. `action_started(action)` emits when an action becomes first in the queue, with `phase = "approach"`. Move the character to `target_position`, then call `begin_current_action()`. Calling it repeatedly is safe. Money is charged at this point, only once.
4. The action becomes `phase = "active"`; `elapsed` advances in game minutes, `progress` ranges from 0 to 1. Need and skill changes accrue during activity. The world can animate based on its `id`.
5. `action_finished(action)` emits on completion and the next queued action starts. Completion bonuses (income, relationship changes, wants) happen once.

`get_current_action()` returns the front dictionary or `{}`. Public `action_queue` exposes the whole queue; later entries have phase `queued`. `cancel_action(index = 0)` removes a queued or active item and advances the queue when needed. Started activities do not refund ingredients; partial need and skill gains remain. Social target IDs should be `maya` and `leo`; prefixed forms containing those names also resolve.

## UI state and signals

- `changed()` emits every 0.2 simulation seconds and on user mutations; `notice(text)` emits player-facing events.
- `needs`: hunger, energy, hygiene, bladder, fun, social, each float 0–100.
- `funds`, `day`, `minutes`, `speed`, `satisfaction`, `bills_paid`: numeric values.
- `character`: full profile, including name, appearance fields, traits and aspiration.
- `skills`: cooking, creativity, charisma, logic, gardening; each `{level: int, xp: float}`. Next level requires `level * 50` XP; cap 10.
- `relationships`: maya and leo, each `{name, friendship, romance, status}`. Friendship ranges −100 to 100, romance 0–100.
- `career`: `{title, level, performance, salary, worked_day}`. A job shift pays once daily; freelance work is unrestricted. Completing enough shifts earns a promotion and bonus. Household bills cost §35 each midnight; no automatic wages.
- `wants`: `{id,label,description,progress,target,reward,complete}` dictionaries. Completing each pays its reward in satisfaction and household funds once.
- `get_mood()`: `{label, description, color: Color}`; `get_clock_text()` formats `Day 1 · 08:00`.
- `get_state()` returns a deep snapshot suitable for inspection; it includes live Vector3 queue positions.

## Save / load

`save_game(world_data: Array = []) -> bool` writes a validated-format JSON snapshot atomically via a temporary file to `user://justlife_save.json`. Arbitrary world placement dictionaries are passed through; Vector3 values become numeric `[x,y,z]` arrays and Colors become HTML strings. The world owns decoding its own placement fields.

`load_game() -> Dictionary` returns `{ok: true, world: Array}` on success or `{ok: false, error: String}`. Corrupt or unsupported saves do not mutate live state. `restore_state(state)` uses the same validation for in-memory snapshots and is useful in tests. Queue actions resume with preserved elapsed time and ingredient payment, but first enter `approach` so the world can position the actor before `begin_current_action()`. Connect signals before loading, or inspect `get_current_action()` afterward.

Tests: `godot --headless --path . --script tests/test_simulation.gd`.
