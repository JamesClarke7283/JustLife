extends SceneTree
## Focused check for hospital homecoming, Welcome Baby Home SAVE-01, and infant
## stage transitions on the existing baby systems.
##
##   godot --headless --path . --audio-driver Dummy --script res://tests/probe_birth_homecoming.gd

var checks: int = 0
var failures: Array[String] = []

func check(ok: bool, why: String) -> void:
	checks += 1
	print("CHECK ", "PASS " if ok else "FAIL ", why)
	if not ok: failures.append(why)

func frames(n: int = 3) -> void:
	for i: int in n: await process_frame

func _initialize() -> void:
	if not OS.get_environment("JUSTLIFE_DATA_DIR").is_absolute_path():
		push_error("Requires JUSTLIFE_DATA_DIR.")
		quit(2); return
	_run.call_deferred()

func _run() -> void:
	# Pure rules first — no scene needed.
	var state: Dictionary = LifeBirthHomecoming.begin("m", "f", "b")
	check(str(state.phase) == LifeBirthHomecoming.PHASE_PARTNER, "Homecoming starts at partner choice.")
	state = LifeBirthHomecoming.choose_dad(state, LifeBirthHomecoming.DAD_NOTIFY)
	check(LifeBirthHomecoming.can_welcome(state), "Notify Dad unlocks Welcome Baby Home.")
	state = LifeBirthHomecoming.start_arrival(state)
	check(bool(state.arrival_started), "Arrival marks the baby as serialized for SAVE-01.")
	check(LifeBirthHomecoming.party_ids(state).has("m") and LifeBirthHomecoming.party_ids(state).has("b"),
		"Mother and baby are on the arrival party.")

	var baby: Dictionary = {"age_stage": "baby", "name": "Kit Stone"}
	LifeBabyPlan.seed_infant(baby, 1)
	check(str(baby.infant_phase) == LifeBabyPlan.INFANT_NEWBORN, "Newborn phase at birth day.")
	check(LifeBabyPlan.infant_phase_for(baby, 15) == LifeBabyPlan.INFANT_SITTING, "Day 15 is sitting.")
	check(LifeBabyPlan.infant_phase_for(baby, 27) == LifeBabyPlan.INFANT_TODDLER, "Day 27 is toddler.")
	check(float(LifeLifecycle.NORMAL_DAYS.baby) >= 26.0, "Baby stage lasts through toddler sub-stages.")

	for kind: String in ["baby_mobile", "baby_rattle", "rocking_chair", "baby_mat", "children_picture",
			"dollhouse", "train_set", "child_rug", "child_desk", "child_chair", "nursery_paint"]:
		check(LifeCatalog.ITEMS.has(kind), "Catalogue lists %s." % kind)

	check(ResourceLoader.exists("res://assets/models/baby_mobile_stars.glb"),
		"Baby mobile stars mesh is on disk.")
	check(ResourceLoader.exists("res://assets/models/baby_rattle.glb"),
		"Baby rattle mesh is on disk.")
	check(ResourceLoader.exists("res://assets/models/rocking_chair.glb"),
		"Rocking chair mesh is on disk.")
	check(ResourceLoader.exists("res://assets/models/dollhouse_classic.glb"),
		"Dollhouse mesh is on disk.")
	check(LifeCatalog.nursery_room_preset().size() >= 6, "Nursery room preset has furnishings.")

	print("HOMECOMING_RESULT ", JSON.stringify({"checks": checks, "failures": failures}))
	quit(0 if failures.is_empty() else 1)
