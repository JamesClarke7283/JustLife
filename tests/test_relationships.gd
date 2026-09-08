extends SceneTree

const Simulation = preload("res://scripts/life_sim.gd")
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


func advance(sim: LifeSim, duration: float) -> void:
	var remaining: float = duration
	while remaining > .0001:
		var step: float = minf(remaining, 120.0)
		sim.tick(step / LifeSim.GAME_MINUTES_PER_SECOND)
		remaining -= step


func complete(sim: LifeSim, action_id: String, target: String) -> void:
	check(sim.queue_action(action_id, target), "Action %s must be available." % action_id)
	sim.begin_current_action()
	advance(sim, float(sim.get_current_action().duration))


func run() -> void:
	_test_gates_and_milestones()
	_test_partnership_persistence()
	await _test_household_reciprocity()
	print("Relationship progression: %d checks, %d failures." % [checks, failures])
	quit(1 if failures > 0 else 0)


func _test_gates_and_milestones() -> void:
	var sim: LifeSim = Simulation.new()
	sim.new_household({"name":"Robin", "traits":[]})
	sim.autonomy = false
	check(sim.character.life_stage == "adult" and sim.relationships.maya.life_stage == "adult", "Existing adult-only avatars must carry explicit adult metadata.")
	var before: Dictionary = sim.relationships.duplicate(true)
	check(not sim.get_action_availability("ask_partner", "maya").available and not sim.queue_action("ask_partner", "maya"), "An acquaintance must not accept an unearned partnership.")
	check(sim.relationships == before and sim.social_history.is_empty() and sim.action_queue.is_empty(), "Unavailable relationship choices must leave relationships and history unchanged.")
	check(not sim.queue_action("friendly", "missing_person") and sim.relationships == before, "An unknown target must never fall back to changing Maya's relationship.")
	var options: Array = sim.get_actions_for("neighbor", "leo")
	var partner_option: Dictionary = {}
	for option: Dictionary in options:
		if option.id == "ask_partner": partner_option = option
	check(not partner_option.available and partner_option.unavailable_reason.contains("45 friendship"), "Target-aware menus must explain the real friendship and romance requirement.")
	complete(sim, "friendly", "maya")
	complete(sim, "friendly", "maya")
	check(sim.relationships.maya.status == "Friend", "Completed conversations must reach a genuine friendship milestone.")
	var friend_count: int = 0
	for entry: Dictionary in sim.social_history:
		if entry.stage == "friends": friend_count += 1
	check(friend_count == 1 and sim.social_history.size() == 2, "Meeting and friendship must each create one staged social memory.")
	complete(sim, "joke", "maya")
	friend_count = 0
	for entry: Dictionary in sim.social_history:
		if entry.stage == "friends": friend_count += 1
	check(friend_count == 1, "A milestone must not repeat on every later conversation.")
	sim.relationships.leo.friendship = 90.0
	sim.relationships.leo.romance = 90.0
	sim.relationships.leo.life_stage = "minor"
	before = sim.relationships.duplicate(true)
	check(not sim.queue_action("flirt", "leo") and not sim.queue_action("ask_partner", "leo") and sim.relationships == before, "Non-adult targets must block romantic actions without consequences.")
	sim.relationships.leo.life_stage = "adult"
	sim.character.life_stage = "unknown"
	check(not sim.get_action_availability("ask_partner", "leo").available, "The initiating Lifelet must also be explicitly adult.")
	sim.character.life_stage = "adult"
	check(sim.queue_action("ask_partner", "leo"), "An eligible relationship may enter the approach phase.")
	sim.relationships.leo.romance = 10.0
	before = sim.relationships.duplicate(true)
	sim.begin_current_action()
	check(sim.action_queue.is_empty() and sim.relationships == before, "Arrival must recheck eligibility instead of accepting a stale queued invitation.")
	sim.free()


func _test_partnership_persistence() -> void:
	var sim: LifeSim = Simulation.new()
	sim.autonomy = false
	sim.wants.clear()
	sim.relationships.maya.friendship = 70.0
	sim.relationships.maya.romance = 70.0
	var money: int = sim.funds
	var satisfaction: int = sim.satisfaction
	complete(sim, "ask_partner", "maya")
	check(sim.romantic_partner == "maya" and sim.relationships.maya.bond == "partners" and sim.relationships.maya.status == "Partner", "An accepted invitation must establish an explicit partnership.")
	check(sim.funds == money and sim.satisfaction == satisfaction, "Relationship milestones must not grant unearned currency or satisfaction.")
	check(not sim.queue_action("ask_partner", "leo"), "A Lifelet must end an existing partnership before beginning another.")
	complete(sim, "commit", "maya")
	check(sim.relationships.maya.bond == "committed" and sim.social_history[0].stage == "committed", "A high-trust partnership must support an explicit commitment and memory.")
	check(not sim.queue_action("commit", "maya"), "An existing commitment must not repeat as a fresh milestone.")
	var parser: JSON = JSON.new()
	parser.parse(JSON.stringify(sim.get_state()))
	var loaded: LifeSim = Simulation.new()
	check(loaded.restore_state(parser.data).ok and loaded.romantic_partner == "maya" and loaded.relationships.maya.status == "Committed partner", "Partnership and commitment must survive a JSON round-trip.")
	check(loaded.social_history == sim.social_history, "Staged social history must survive the same round-trip.")
	var old_friendship: float = float(loaded.relationships.maya.friendship)
	var old_romance: float = float(loaded.relationships.maya.romance)
	complete(loaded, "break_up", "maya")
	check(loaded.romantic_partner.is_empty() and loaded.relationships.maya.bond == "separated" and loaded.relationships.maya.status == "Former partner", "A breakup must end the partnership explicitly.")
	check(is_equal_approx(float(loaded.relationships.maya.friendship), old_friendship - 12.0) and is_equal_approx(float(loaded.relationships.maya.romance), old_romance - 35.0), "A breakup must apply its advertised relationship tradeoffs exactly once.")
	check(loaded.social_history[0].stage == "separated" and not loaded.queue_action("break_up", "maya"), "A breakup must be remembered and cannot repeat without a new partnership.")
	var invalid: Dictionary = sim.get_state()
	invalid.relationships.maya.life_stage = "minor"
	check(not loaded.restore_state(invalid).ok, "A saved partnership with a non-adult participant must be rejected.")
	sim.free()
	loaded.free()


func _test_household_reciprocity() -> void:
	var home: LifeHousehold = Household.new()
	root.add_child(home)
	home.new_household([{"name":"Robin"}, {"name":"Avery"}, {"name":"Jules"}])
	for member: Dictionary in home.members:
		member.sim.autonomy = false
		member.sim.wants.clear()
	var first: LifeSim = home.member_sim("player")
	var second: LifeSim = home.member_sim("housemate_1")
	first.relationships.housemate_1.friendship = 75.0
	first.relationships.housemate_1.romance = 75.0
	home.adopt_selected_changes()
	check(not first.get_action_availability("ask_partner", "housemate_1").available, "The receiving housemate must also meet friendship and romance gates.")
	second.relationships.player.friendship = 75.0
	second.relationships.player.romance = 75.0
	home.adopt_selected_changes()
	check(first.queue_action("ask_partner", "housemate_1"), "Housemates with a developed relationship may choose partnership.")
	home.begin_action("player")
	home.tick(35.0 / LifeSim.GAME_MINUTES_PER_SECOND)
	check(first.romantic_partner == "housemate_1" and second.romantic_partner == "player", "Accepted housemate partnerships must be reciprocal.")
	check(first.relationships.housemate_1.bond == second.relationships.player.bond and second.social_history[0].target_id == "player", "Both Lifelets must share the relationship stage and receive their own history entry.")
	check(first.queue_action("commit", "housemate_1"), "An eligible household couple may commit.")
	home.begin_action("player")
	home.tick(45.0 / LifeSim.GAME_MINUTES_PER_SECOND)
	check(second.relationships.player.status == "Committed partner", "Commitment must update the receiving household member.")
	var state: Dictionary = home.get_state()
	var loaded: LifeHousehold = Household.new()
	root.add_child(loaded)
	check(loaded.restore_state(home.json_safe(state)).ok and loaded.member_sim("housemate_1").romantic_partner == "player", "A reciprocal household couple must survive full household restore.")
	var invalid: Dictionary = state.duplicate(true)
	invalid.members[1].state.romantic_partner = ""
	invalid.members[1].state.relationships.player.bond = "none"
	check(not loaded.restore_state(invalid).ok, "A one-sided saved partnership must be rejected.")
	check(first.queue_action("break_up", "housemate_1"), "Either household partner can initiate a breakup.")
	home.begin_action("player")
	home.tick(25.0 / LifeSim.GAME_MINUTES_PER_SECOND)
	check(first.romantic_partner.is_empty() and second.romantic_partner.is_empty() and second.relationships.player.bond == "separated", "A household breakup must free both partners and retain their shared history.")
	first.relationships.maya.friendship = 80.0
	first.relationships.maya.romance = 80.0
	check(first.queue_action("ask_partner", "maya"), "A now-single adult may form a new eligible partnership.")
	home.begin_action("player")
	home.tick(35.0 / LifeSim.GAME_MINUTES_PER_SECOND)
	second.relationships.maya.friendship = 80.0
	second.relationships.maya.romance = 80.0
	check(not second.get_action_availability("ask_partner", "maya").available and not second.queue_action("ask_partner", "maya"), "A neighbor already partnered with one member must be unavailable to another.")
	home.queue_free()
	loaded.queue_free()
	await process_frame
