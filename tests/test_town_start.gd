extends SceneTree
## Starting money, family starter homes, the commute, the children's park,
## and the child bed / desk menus.

var checks: int = 0
var failures: int = 0

func check(value: bool, detail: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(detail)

func _labels(sim: LifeSim, kind: String) -> Array:
	var labels: Array = []
	for action: Dictionary in sim.get_actions_for(kind, kind):
		labels.append(str(action.label))
	return labels

func _initialize() -> void:
	check(LifeHousehold.starting_funds(1) == 2500, "One Lifelet still starts on ℒ2500.")
	check(LifeHousehold.starting_funds(3) == 5000, "A household of three starts on ℒ5000.")
	var three := LifeHousehold.new()
	three.new_household([
		{"name": "Ned", "age_stage": "adult"},
		{"name": "Ann", "age_stage": "adult"},
		{"name": "Kit", "age_stage": "child"},
	])
	check(three.funds == 5000 and three.members[2].sim.funds == 5000, "The shared purse is ℒ5000 for a man, a woman and a child.")
	var offers: Array = LifeProperties.starters_for([
		{"age_stage": "adult"}, {"age_stage": "adult"}, {"age_stage": "child"},
	])
	check(offers.has("lumen") and offers.has("haven"), "A family with a child is offered Lumen House and Haven (%s)." % str(offers))
	var baby_offers: Array = LifeProperties.starters_for([{"age_stage": "adult"}, {"age_stage": "baby"}])
	check(baby_offers.has("haven"), "A baby’s household is offered the furnished nursery house.")
	check(not LifeProperties.starters_for([{"age_stage": "adult"}]).has("haven"), "Haven is not offered when nobody is a baby or a child.")
	var lumen: Array = LifeCatalog.starter_layout(10)
	var haven: Array = LifeCatalog.starter_layout(11)
	var lumen_kinds: Array = []
	for item: Dictionary in lumen: lumen_kinds.append(str(item.kind))
	var haven_kinds: Array = []
	for item: Dictionary in haven: haven_kinds.append(str(item.kind))
	check(lumen_kinds.has("pool") and lumen_kinds.has("child_bed") and lumen_kinds.count("toilet") >= 2 and lumen_kinds.has("shower") and lumen_kinds.has("bathtub"),
		"Lumen House is two bedrooms, two bathrooms, a pool and a child room.")
	check(haven_kinds.has("cot") and haven_kinds.has("child_bed") and haven_kinds.has("changing_table"),
		"Haven is already furnished with a nursery and a child room.")
	var info: Dictionary = LifeVenues.info("kids_park")
	var placed: Array = LifeVenues.layout("kids_park")
	var park_kinds: Array = []
	for item: Dictionary in placed: park_kinds.append(str(item.kind))
	check(not info.is_empty() and park_kinds.has("toilet") and park_kinds.has("counter") and park_kinds.has("bench") and park_kinds.has("kids_slide"),
		"The children's park has a restroom, a café counter, seating and play.")
	check(info.get("child_npcs", []).size() >= 3 and info.get("passers", []).has("child") and info.get("passers", []).has("pet"),
		"Child NPCs play at the park, and children and pets walk past homes.")
	var adult: LifeSim = three.members[0].sim
	adult.autonomy = false
	adult.register_targets([
		{"id": "car", "kind": "car", "position": Vector3(2, .16, 2)},
		{"id": "exit", "kind": "lot_exit", "position": Vector3(0, .16, 8)},
		{"id": "cot", "kind": "cot", "position": Vector3(3, .16, 1)},
	])
	var drive: Dictionary = adult._commute_choice("career_day", [])
	check(str(drive.get("id")) == "drive_to_work" and str(drive.get("target_id")) == "car",
		"An adult who owns a car drives it to work (%s)." % str(drive.get("id")))
	check(adult.queue_action("drive_to_work", "car", Vector3(2, .16, 2)) and str(adult.get_current_action().phase) == "approach",
		"Driving to work queues a walk out to the car.")
	var child: LifeSim = three.members[2].sim
	child.autonomy = false
	child.minutes = 1000.0
	child.register_targets([
		{"id": "child_bed", "kind": "child_bed", "position": Vector3(1, .16, 1)},
		{"id": "cot", "kind": "cot", "position": Vector3(3, .16, 1)},
		{"id": "desk", "kind": "desk", "position": Vector3(4, .16, 1)},
		{"id": "school_bus", "kind": "school_bus", "position": Vector3(0, .16, 6)},
		{"id": "exit", "kind": "lot_exit", "position": Vector3(0, .16, 8)},
	])
	var bus: Dictionary = child._commute_choice("school_day", [])
	check(str(bus.get("id")) == "board_school_bus" and str(bus.get("target_id")) == "school_bus",
		"A child boards the school bus (%s)." % str(bus.get("id")))
	var bed_labels: Array = _labels(child, "child_bed")
	check(bed_labels.has("Go to Bed") and bed_labels.has("Relax") and bed_labels.has("Take a Nap"),
		"The child bed offers Go to Bed, Relax and Take a Nap (%s)." % str(bed_labels))
	check(not child.get_action_availability("sleep", "cot").available, "A child cannot sleep in the cot.")
	check(not adult.get_action_availability("sleep", "cot").available, "An adult cannot sleep in the cot.")
	var desk_labels: Array = _labels(child, "desk")
	check(desk_labels.has("Do Homework") and desk_labels.has("Read a Book") and desk_labels.has("Skill Up"),
		"After school the desk offers homework, reading and skill building (%s)." % str(desk_labels))
	var home := LifeHousehold.new()
	home.new_household([{"name": "Parent", "age_stage": "adult"}, {"name": "Pip", "age_stage": "baby"}])
	var parent: LifeSim = home.members[0].sim
	parent.register_targets([{"id": "cot", "kind": "cot", "position": Vector3(1, .16, 1)}])
	var baby: LifeSim = home.members[1].sim
	baby.register_targets([{"id": "cot", "kind": "cot", "position": Vector3(1, .16, 1)}])
	var parent_labels: Array = _labels(parent, "cot")
	check(parent_labels.has("Nap") and parent_labels.has("Nighttime Sleep"),
		"A parent can put the baby down for a nap or the night (%s)." % str(parent_labels))
	check(baby.get_action_availability("sleep", "cot").available, "Only the baby sleeps in the cot.")
	three.free()
	home.free()
	print("TOWN_START %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
