# Household coordination

`LifeHousehold` owns up to eight independent `LifeSim` nodes. `new_household(profiles)` creates them, with IDs `player`, `housemate_1`, and onward. Public `members` entries contain `{id,sim}`. `selected()`, `selected_id()`, `select(index)`, and `member_sim(id)` expose selection.

Call `tick(delta)` once for the household. Do not separately tick its members. Time and speed are shared; needs, skills, careers, moods, memories and action queues remain individual. Money is synchronized before and after each member step. Only the first Lifelet charges the household's daily bill. UI edits to the selected member's funds/speed are adopted on the next tick or `adopt_selected_changes()`; `set_funds()` and `set_speed()` apply immediately to all members.

`member_action_started(id,action)` and `member_action_finished(id,action)` identify whose movement/animation to update. World integration must keep a path per member and call `begin_action(id)` on arrival so ingredient charges update the shared wallet. `register_targets(array)` supplies autonomy targets to everyone. `notice(message)` forwards household events.

`save_game(world_data)` stores every member, selection, shared resources, and the world snapshot in the existing user save path. `load_game()` returns `{ok,world}` or `{ok:false,error}` and accepts the original single-Lifelet save format. `restore_state()` validates every member before replacing any live state. Positions remain world-owned and should be stored alongside the world data or in each character's `world_state`.

`tests/test_household.gd`: 20 stateful assertions covering concurrent activity, independent skills/needs, one wallet, one daily bill, exact pause, selection, migration, and atomic restore rejection.
