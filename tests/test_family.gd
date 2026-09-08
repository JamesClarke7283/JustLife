extends SceneTree

const Household = preload("res://scripts/household.gd")
var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	call_deferred("run")


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)


func run() -> void:
	var home: LifeHousehold = Household.new()
	root.add_child(home)
	home.new_household([{"name":"Robin Vale"}, {"name":"Avery Vale"}, {"name":"Drew Stone"}, {"name":"Kai Park"}])
	var original_node: LifeSim = home.selected()
	check(home.get_family_links().all(func(link: Dictionary) -> bool: return link.role == "housemates"), "Matching surnames must never infer a family relationship.")
	var before: Dictionary = home.get_state()
	for links: Array in [
		[{"a":"player", "b":"player", "role":"siblings"}],
		[{"a":"player", "b":"missing", "role":"siblings"}],
		[{"a":"player", "b":"housemate_1", "role":"unknown"}],
		[{"a":"player", "b":"housemate_1", "role":"siblings"}, {"a":"housemate_1", "b":"player", "role":"partners"}],
		[{"a":"player", "b":"housemate_1", "role":"partners"}, {"a":"player", "b":"housemate_2", "role":"partners"}],
		[{"a":"player", "b":"housemate_1", "role":"siblings"}, {"a":"housemate_1", "b":"housemate_2", "role":"siblings"}, {"a":"player", "b":"housemate_2", "role":"housemates"}],
		[{"a":"player", "b":"housemate_1", "role":"siblings"}, {"a":"housemate_1", "b":"housemate_2", "role":"siblings"}, {"a":"player", "b":"housemate_2", "role":"partners"}]]:
		check(not home.configure_family(links).ok and home.get_state() == before, "Invalid family declarations must be rejected atomically.")
	var links: Array = [{"a":"player", "b":"housemate_1", "role":"siblings"}, {"a":"housemate_2", "b":"housemate_3", "role":"partners"}]
	check(home.configure_family(links).ok, "Explicit adult siblings and a separate adult couple must initialize together.")
	check(home.selected() == original_node, "Family setup must preserve existing LifeSim Node references.")
	var first: LifeSim = home.member_sim("player")
	var sibling: LifeSim = home.member_sim("housemate_1")
	var third: LifeSim = home.member_sim("housemate_2")
	var fourth: LifeSim = home.member_sim("housemate_3")
	check(first.relationships.housemate_1.family_role == "siblings" and sibling.relationships.player.family_role == "siblings", "Sibling roles must be reciprocal.")
	check(first.relationships.housemate_1.status == "Sibling" and first.relationships.housemate_1.romance == 0.0, "Sibling status must be clear and nonromantic.")
	check(third.romantic_partner == "housemate_3" and fourth.romantic_partner == "housemate_2", "An explicit starting couple must initialize reciprocal partners.")
	check(home.funds == 2500 and first.social_history.is_empty() and third.social_history.is_empty(), "Creator setup must not grant currency or invent newly earned milestone history.")
	for action_id: String in ["flirt", "ask_partner", "commit", "break_up"]:
		check(not first.get_action_availability(action_id, "housemate_1").available and not first.queue_action(action_id, "housemate_1"), "Sibling pairs must block romantic action %s." % action_id)
	check(first.queue_action("friendly", "housemate_1"), "Siblings must retain ordinary friendly conversations.")
	first.cancel_action()
	var snapshot: Dictionary = home.get_state()
	var loaded: LifeHousehold = Household.new()
	root.add_child(loaded)
	var parser: JSON = JSON.new()
	parser.parse(JSON.stringify(snapshot))
	check(loaded.restore_state(parser.data).ok and loaded.get_family_links() == home.get_family_links(), "Family roles and a separate couple must survive a complete JSON household round-trip.")
	var loaded_before: Dictionary = loaded.get_state()
	var malformed: Dictionary = snapshot.duplicate(true)
	malformed.members[1].state.relationships.player.family_role = "none"
	check(not loaded.restore_state(malformed).ok and loaded.get_state() == loaded_before, "One-sided sibling roles must fail without changing the loaded household.")
	malformed = snapshot.duplicate(true)
	malformed.members[0].state.relationships.housemate_1.romance = 60.0
	check(not loaded.restore_state(malformed).ok, "Saved sibling romance must be rejected.")
	malformed = snapshot.duplicate(true)
	malformed.members[0].state.action_queue = [{"id":"flirt", "target_id":"housemate_1", "duration":25.0, "elapsed":0.0, "target_position":[0,0,0]}]
	check(not loaded.restore_state(malformed).ok and loaded.get_state() == loaded_before, "A legacy or malformed romantic sibling queue must be rejected before restoration.")
	var legacy:Dictionary=malformed.members[0].state.duplicate(true)
	check(not loaded.restore_state(legacy).ok, "Legacy single-Lifelet migration must not revive a removed sibling's romantic queue.")
	check(home.configure_family([{"a":"player", "b":"housemate_1", "role":"siblings"}, {"a":"housemate_1", "b":"housemate_2", "role":"siblings"}]).ok, "A fresh creator draft can be revised as a complete declared setup.")
	check(home.member_sim("player").relationships.housemate_2.family_role == "siblings", "Explicit linked siblings must form one consistent sibling family.")
	check(home.member_sim("housemate_3").romantic_partner.is_empty(), "Unlisted pairs in a revised creator setup must return to housemates.")
	home.member_sim("housemate_3").character.life_stage = "minor"
	before = home.get_state()
	check(not home.configure_family([{"a":"player", "b":"housemate_3", "role":"partners"}]).ok and home.get_state() == before, "An initial partnership must require both Lifelets to be adults.")
	home.member_sim("housemate_3").character.life_stage = "adult"
	for member: Dictionary in home.members: member.sim.autonomy = false
	home.tick(.5)
	before = home.get_state()
	check(not home.configure_family([]).ok and home.get_state() == before, "Creator family setup must not rewrite an established live household.")
	home.queue_free()
	loaded.queue_free()
	await process_frame
	print("Family setup: %d checks, %d failures." % [checks, failures])
	quit(1 if failures > 0 else 0)
