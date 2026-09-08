extends SceneTree

var checks: int = 0
var failures: int = 0

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func assert_pair(home: LifeHousehold, a: String, b: String, role: String) -> void:
	check(home.family_relationship(a, b) == role, "Current family context: %s -> %s = %s" % [a, b, role])
	check(home.family_relationship(b, a) == LifeFamilyGraph.inverse(role), "Current inverse family context: " + role)
	var actor: LifeSim = home.member_sim(a)
	var target: LifeSim = home.member_sim(b)
	if actor.character.life_stage == "adult" and target.character.life_stage == "adult":
		check(bool(actor.get_action_availability("flirt", b).available) == (role == "none"), "Romance eligibility uses the current family context.")

func run() -> void:
	var home: LifeHousehold = LifeHousehold.new()
	root.add_child(home)
	home.new_household([{"age_stage":"elder"}, {"age_stage":"adult"}, {"age_stage":"young_adult"}])
	assert_pair(home, "player", "housemate_1", "none")
	check(home.configure_family([{ "a":"player", "b":"housemate_1", "role":"parent" }, { "a":"housemate_1", "b":"housemate_2", "role":"parent" }]).ok, "A complete family setup replaces the unrelated context.")
	assert_pair(home, "player", "housemate_2", "grandchild")
	var family_save: Dictionary = home.get_state()
	check(not home.configure_family([{ "a":"player", "b":"player", "role":"parent" }]).ok, "Invalid setup is rejected.")
	assert_pair(home, "player", "housemate_2", "grandchild")
	check(home.configure_family([]).ok, "Removing creator links removes their derived context.")
	assert_pair(home, "player", "housemate_2", "none")
	check(home.restore_state(JSON.parse_string(JSON.stringify(family_save))).ok, "Restoring another graph updates family context.")
	assert_pair(home, "player", "housemate_2", "grandchild")
	var malformed: Dictionary = family_save.duplicate(true)
	malformed.family_graph.parents.append({ "a":"housemate_2", "b":"player" })
	check(not home.restore_state(malformed).ok, "Invalid restore preserves the existing graph and context.")
	assert_pair(home, "player", "housemate_2", "grandchild")
	check(home.add_member({"age_stage":"adult"}) == "housemate_3", "Adding a member extends the context with a canonical identity.")
	assert_pair(home, "player", "housemate_3", "none")
	assert_pair(home, "player", "housemate_2", "grandchild")
	check(home.member_sim("housemate_2").celebrate_birthday(), "A birthday changes eligibility while retaining ancestry.")
	assert_pair(home, "player", "housemate_2", "grandchild")
	for member: Dictionary in home.members:
		member.sim.autonomy = false
	home.set_speed(0)
	home.tick(1.0)
	assert_pair(home, "player", "housemate_2", "grandchild")
	check(home.family_relationship("player", "missing") == "none" and home.family_relationship("missing", "player") == "none" and home.family_relationship("player", "player") == "none", "Unknown and self identities have no family relationship.")
	home.new_household([{}, {}])
	assert_pair(home, "player", "housemate_1", "none")
	check(home.family_relationship("player", "housemate_2") == "none", "A new household clears removed identities and old relatives.")
	var legacy: Dictionary = home.get_state()
	legacy.erase("family_graph")
	check(home.restore_state(legacy).ok, "Legacy unrelated households construct a fresh family context.")
	assert_pair(home, "player", "housemate_1", "none")
	home.queue_free()
	await process_frame
	print("FAMILY CONTEXT TESTS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)
