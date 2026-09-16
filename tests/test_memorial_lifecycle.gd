extends SceneTree

const Household = preload("res://scripts/household.gd")
var checks: int = 0
var failures: int = 0

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func run() -> void:
	var home: LifeHousehold = Household.new()
	root.add_child(home)
	home.new_household([
		{"name":"Eleanor Vance", "age_stage":"elder", "life_stage":"adult"},
		{"name":"Thomas Vance", "age_stage":"adult", "life_stage":"adult"},
		{"name":"Clara Vance", "age_stage":"teen", "life_stage":"minor"}
	])
	var links: Array = [
		{"a":"player", "b":"housemate_1", "role":"parent"},
		{"a":"housemate_1", "b":"housemate_2", "role":"parent"}
	]
	check(home.configure_family(links).ok, "Three-generation family tree configures cleanly.")
	
	var elder: LifeSim = home.member_sim("player")
	var adult: LifeSim = home.member_sim("housemate_1")
	var teen: LifeSim = home.member_sim("housemate_2")
	
	# Verify elder stage and due_to_pass
	check(not LifeLifecycle.due_to_pass("elder", elder.lifecycle), "Fresh elder is not due to pass.")
	elder.lifecycle.progress = 1.0
	check(LifeLifecycle.due_to_pass("elder", elder.lifecycle), "Elder with progress 1.0 is due to pass.")
	check(not LifeLifecycle.due_to_pass("adult", adult.lifecycle), "Adult with progress 1.0 is not due to pass (has next stage).")
	
	var starting_funds: int = home.funds
	var passed_name: String = str(elder.character.name)
	
	# Execute passing
	var result: Dictionary = home.pass_away("player")
	check(result.get("ok", false), "Elder passes away cleanly when due.")
	check(home.members.size() == 3, "Household retains the playable spirit alongside survivors.")
	check(home.member_sim("player").is_spirit(), "The departed elder remains selectable as a spirit.")
	check(home.funds == starting_funds + LifeHousehold.ESTATE_GIFT, "One estate gift is paid to household funds.")
	
	# Verify genealogy preservation
	check(not LifeFamilyGraph.departed_ids(home.family_graph).has("player"), "The playable spirit retains its active family identity.")
	check(LifeFamilyGraph.relationship(home.family_graph, "housemate_1", "player") == "parent", "Surviving child still reads departed ancestor as parent.")
	check(LifeFamilyGraph.relationship(home.family_graph, "housemate_2", "player") == "grandparent", "Surviving grandchild still reads departed ancestor as grandparent.")
	
	# Verify grief and mourning on survivors
	check(adult.moodlets.any(func(m): return str(m.get("label", "")) == "In mourning"), "Surviving adult receives Mourning moodlet.")
	check(teen.moodlets.any(func(m): return str(m.get("label", "")) == "In mourning"), "Surviving teen receives Mourning moodlet.")
	check(adult.get_fears().has("fear_of_loss"), "A farewell naturally triggers fear of loss.")
	check(not home.pass_away("player").ok, "A second farewell is refused.")
	check(home.funds == starting_funds + LifeHousehold.ESTATE_GIFT and home.memorials.size() == 1, "A repeat farewell cannot duplicate the gift or memorial.")
	
	# Verify memorial interactions on adult
	home.register_targets([{ "id":result.memorial_id, "kind":"memorial", "position":Vector3.ZERO, "use_position":Vector3.ZERO }, {"id":"housemate_2", "kind":"housemate", "position":Vector3.ZERO, "use_position":Vector3.ZERO}])
	check(adult.get_actions_for("memorial").any(func(action): return str(action.id) == "mourn"), "The placed remembrance stone offers mourning.")
	adult.queue_action("mourn", result.memorial_id)
	check(adult.action_queue.size() > 0 and adult.action_queue[0].id == "mourn", "Survivor queues Mourn at the memorial.")
	adult.cancel_action()
	
	# Verify social comfort
	adult.queue_action("comfort_loss", "housemate_2")
	check(adult.action_queue.size() > 0 and adult.action_queue[0].id == "comfort_loss", "Survivor queues Comfort over loss.")
	adult.cancel_action()
	
	# Verify save/load persistence
	var saved: Dictionary = home.get_state()
	var loaded: LifeHousehold = Household.new()
	root.add_child(loaded)
	var parser := JSON.new()
	parser.parse(JSON.stringify(saved))
	var restore_res: Dictionary = loaded.restore_state(parser.data)
	check(restore_res.get("ok", false), "Household with departed members and mourning survives full JSON round trip.")
	check(loaded.members.size() == 3, "Loaded household retains the spirit and survivors.")
	check(loaded.member_sim("player").is_spirit(), "Loaded household retains the spirit identity.")
	
	# The first member owns the clock and bill ledger even after passing.
	for member: Dictionary in loaded.members:
		member.sim.autonomy = false
	loaded.day = 7
	loaded.minutes = 1439.5
	loaded.set_speed(1)
	loaded.tick(1.0)
	check(loaded.day == 8, "A spirit household owner continues the shared calendar.")
	check(not loaded.bill().is_empty(), "Weekly bills still issue after the owner passes.")
	check(loaded.funds == starting_funds + LifeHousehold.ESTATE_GIFT, "Continued ticking does not repeat the estate gift.")

	home.free()
	loaded.free()
	print("Memorial lifecycle: %d checks, %d failures." % [checks, failures])
	quit(0 if failures == 0 else 1)

func _initialize() -> void:
	call_deferred("run")
