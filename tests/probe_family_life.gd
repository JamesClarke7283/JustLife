extends SceneTree
## Focused check for pregnancy HUD text, hot-tub pregnancy refusal, pet care
## interactions, and the new catalogue kinds.

var checks: int = 0
var failures: Array[String] = []


func check(value: bool, message: String) -> void:
	checks += 1
	print("CHECK ", "PASS " if value else "FAIL ", message)
	if not value:
		failures.append(message)
		push_error(message)


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var progress: float = 0.5
	check(LifeBabyPlan.pregnancy_stage(progress) == "mid", "Mid pregnancy stage maps from half progress.")
	var state: Dictionary = LifeBabyPlan.fresh()
	state.active = true
	state.due_at = LifeBabyPlan.now_of(5, 0.0) + LifeBabyPlan.PREGNANCY_MINUTES * 0.5
	var status: String = LifeBabyPlan.pregnancy_status_text(state, 5, 0.0)
	check(status.contains("pregnancy") and status.contains("day"), "Pregnancy status names stage and days left: %s" % status)

	check(LifeOutdoorActs.act_error("hot_tub", "adult", false, true, true).contains("Pregnant"), "Pregnant adults are refused the hot tub.")
	check(LifeOutdoorActs.act_error("hot_tub", "child", false, true, false).is_empty(), "Children may soak when not pregnant.")
	check(not LifeOutdoorActs.act_error("pool", "adult", false, true, false).is_empty(), "Adults are outside the pool age window.")
	check(LifeOutdoorActs.act_error("pool", "young_adult", false, true, false).is_empty(), "Young adults may swim.")
	check(LifeOutdoorActs.acts("adult_slide").has("from"), "Adult slide is an outdoor act.")
	check(LifeOutdoorActs.acts("baby_pram").has("from"), "Pram push is an outdoor act.")

	check(LifePetCare.interaction("pet_tug").has("id"), "Tug-of-war is a pet care interaction.")
	check(LifePetCare.interaction("pet_tummy_rub").has("dog_only"), "Tummy rub is dog-only.")
	check(LifePetCare.interaction_error("pet_tug", "child", false, "dog").is_empty(), "Children may tug with a dog.")
	check(not LifePetCare.interaction_error("pet_tug", "child", false, "cat").is_empty(), "Cats refuse tug-of-war.")

	for kind: String in ["baby_pram", "pushchair", "baby_car_seat", "child_car_seat", "curtains", "adult_slide", "toy_chest", "nursery_room_pack", "child_bedroom_pack"]:
		check(LifeCatalog.ITEMS.has(kind), "Catalogue sells %s." % kind)
		if kind.ends_with("_pack"):
			continue
		var path: String = "res://assets/models/%s.glb" % kind
		check(ResourceLoader.exists(path), "Mesh exists for %s." % kind)

	check(LifeCatalog.nursery_preset_price() == 2000, "Nursery pack is ℒ2000.")
	check(LifeCatalog.child_bedroom_preset_price() == 2000, "Child bedroom pack is ℒ2000.")
	check(LifeCatalog.ITEMS.curtains.styles.size() == 10, "Curtains offer ten styles.")
	check(LifeCatalog.ITEMS.curtains.colors.size() == 10, "Curtains offer ten colours.")
	check(LifeCatalog.ITEMS.nursery_paint.styles.size() == 10, "Nursery paint offers ten styles.")

	var app: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	await process_frame
	await process_frame
	app.selected_lot = 0
	app.start_household()
	await process_frame
	app.set_process(false)

	# Force an active pregnancy on the selected member and redraw Needs.
	var mother_id: String = str(app.household.members[app.household.selected_index].id)
	app.household.pregnancy = {
		"version": LifeBabyPlan.SAVE_VERSION, "active": true, "pending": false,
		"mother_id": mother_id, "father_id": mother_id,
		"conceived_at": LifeBabyPlan.now_of(app.household.day, app.household.minutes),
		"due_at": LifeBabyPlan.now_of(app.household.day, app.household.minutes) + LifeBabyPlan.PREGNANCY_MINUTES,
		"serial": 1, "baby": {},
	}
	app.panel_tab = "Needs"
	app.draw_live()
	await process_frame
	check(is_instance_valid(app.pregnancy_meter), "Pregnancy progress bar appears on the Needs panel.")
	check(is_instance_valid(app.pregnancy_label) and str(app.pregnancy_label.text).contains("pregnancy"), "Pregnancy label shows stage text.")
	var soak: Dictionary = app.sim.get_action_availability(LifeOutdoorActs.ACTION_ID, "")
	# Need a hot tub target — place availability via act_error directly already covered.
	check(app.household.member_is_pregnant(mother_id), "Household names the pregnant mother.")

	# Pet care round-trip on a dog if one exists, else skip soft.
	if app.household.pets.get("pets", []).size() > 0:
		var pet: Dictionary = app.household.pets.pets[0]
		var actions: Array = app.household.pet_actions(str(pet.id), mother_id)
		var ids: Array = actions.map(func(a: Dictionary) -> String: return str(a.id))
		check(ids.has("pet_tummy_rub") or str(pet.species) != "dog", "Dog actions include tummy rub.")
		check(ids.has("pet_tug") or str(pet.species) != "dog", "Dog actions include tug-of-war.")
		check(ids.has("pet_walk"), "Walk the dog is offered.")

	app.queue_free()
	await process_frame
	print("FAMILY_LIFE %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
