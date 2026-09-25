extends SceneTree
## A child sleeps in a free child bed. An adult keeps the adult bed. An adult
## bed is not a silent stand-in while a child bed can still be bought.

var checks: int = 0
var failures: int = 0

func check(value: bool, detail: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(detail)

func _bed_targets() -> Array:
	return [
		{"id":"adult_bed","kind":"bed","position":Vector3(0,.16,1)},
		{"id":"own_bed","kind":"child_bed","position":Vector3(2,.16,1)},
		{"id":"sofa","kind":"sofa","position":Vector3(4,.16,1)},
	]

func _sim(stage: String) -> LifeSim:
	var sim: LifeSim = LifeSim.new()
	sim.new_household({"name":"Sleeper","age_stage":stage,"traits":[]})
	sim.autonomy = false
	sim.household_bills_enabled = false
	sim.set_aging("normal", false)
	sim.minutes = 1200.0
	sim.needs.energy = 10.0
	return sim

func _initialize() -> void:
	var child: LifeSim = _sim("child")
	child.funds = 2500
	child.register_targets(_bed_targets())
	var energy: Dictionary = child.autonomy_need_choice("energy")
	check(str(energy.get("id")) == "sleep" and str(energy.get("target_id")) == "own_bed",
		"A child with a free child bed is assigned that bed (%s @ %s)." % [str(energy.get("id")), str(energy.get("target_id"))])
	check(str(energy.get("target_id")) != "adult_bed",
		"A child is not assigned the adult bed while a child bed is free.")
	check(not child.queue_action("sleep", "adult_bed", Vector3(0,.16,1)),
		"Queueing sleep in the adult bed fails while a child bed is free.")
	check(child.get_action_availability("sleep", "adult_bed").reason.contains("child"),
		"The adult bed tells a child to use their own bed.")
	check(child.queue_action("sleep", "own_bed", Vector3(2,.16,1)),
		"The child can queue sleep in the free child bed.")
	var adult: LifeSim = _sim("adult")
	adult.funds = 2500
	adult.register_targets(_bed_targets())
	var grown: Dictionary = adult.autonomy_need_choice("energy")
	check(str(grown.get("id")) == "sleep" and str(grown.get("target_id")) == "adult_bed",
		"An adult keeps the adult bed (%s @ %s)." % [str(grown.get("id")), str(grown.get("target_id"))])
	check(not adult.queue_action("sleep", "own_bed", Vector3(2,.16,1)),
		"An adult cannot sleep in a child's bed.")
	var buyer: LifeSim = _sim("child")
	buyer.funds = 2500
	buyer.register_targets([{"id":"adult_bed","kind":"bed","position":Vector3(0,.16,1)}])
	check(not buyer.get_action_availability("sleep", "adult_bed").available,
		"With money for a child bed, a child is not silently sent to the adult bed.")
	var broke: LifeSim = _sim("child")
	broke.funds = 0
	broke.register_targets([{"id":"adult_bed","kind":"bed","position":Vector3(0,.16,1)}])
	var fallback: Dictionary = broke.autonomy_need_choice("energy")
	check(broke.get_action_availability("sleep", "adult_bed").available and str(fallback.get("target_id")) == "adult_bed",
		"Without a child bed to buy, the adult bed remains the fallback (%s)." % str(fallback.get("target_id")))
	child.free()
	adult.free()
	buyer.free()
	broke.free()
	print("CHILD_BED_ROUTING %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
