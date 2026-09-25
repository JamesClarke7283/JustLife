extends SceneTree
## A child and a baby who are home (not at the hospital) survive a save and load.

var checks: int = 0
var failures: int = 0

func check(value: bool, detail: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(detail)

func _roundtrip(home: LifeHousehold) -> LifeHousehold:
	var packed: Dictionary = JSON.parse_string(JSON.stringify(LifeSaveLibrary._json_safe(home.get_state([]))))
	var again := LifeHousehold.new()
	var result: Dictionary = again.restore_state(packed)
	check(bool(result.ok), "The household saves and loads (%s)." % str(result.get("error", "")))
	return again

func _initialize() -> void:
	var home := LifeHousehold.new()
	home.new_household([
		{"name": "Parent Vale", "age_stage": "adult", "traits": []},
		{"name": "Kit Vale", "age_stage": "child", "traits": []},
		{"name": "Pip Vale", "age_stage": "baby", "traits": []},
	])
	for member: Dictionary in home.members:
		member.sim.autonomy = false
		member.sim.wants.clear()
	var parent_id: String = str(home.members[0].id)
	var child_id: String = str(home.members[1].id)
	var baby_id: String = str(home.members[2].id)
	LifeBabyPlan.seed_infant(home.members[2].sim.character, home.day)
	home.family_graph.parents.append({"a": parent_id, "b": child_id})
	home.family_graph.parents.append({"a": parent_id, "b": baby_id})
	var ids: Array = [parent_id, child_id, baby_id]
	home.family_graph = LifeFamilyGraph.canonical(home.family_graph, ids)
	for entry: Dictionary in home.members:
		for other: Dictionary in home.members:
			if str(entry.id) == str(other.id): continue
			var role: String = LifeFamilyGraph.relationship(home.family_graph, str(entry.id), str(other.id))
			entry.sim.relationships[str(other.id)] = {
				"name": other.sim.character.name, "friendship": 40.0, "romance": 0.0,
				"status": LifeFamilyGraph.label(role), "life_stage": other.sim.character.life_stage,
				"bond": "none", "milestones": [], "family_role": role,
			}
	check(not home.members[2].sim.is_away(), "The baby is home, not at the hospital.")
	var loaded: LifeHousehold = _roundtrip(home)
	var stages: Dictionary = {}
	for member: Dictionary in loaded.members:
		stages[str(member.sim.character.age_stage)] = str(member.id)
		check(not member.sim.is_away(), "%s is still home after load." % str(member.sim.character.age_stage))
	check(stages.has("adult") and stages.has("child") and stages.has("baby"), "Adult, child and baby all survived (%s)." % str(stages))
	var baby: LifeSim = loaded.member_sim(baby_id)
	check(baby != null and str(baby.character.get("infant_phase", "")) == "newborn", "The home baby keeps the newborn phase.")
	var child: LifeSim = loaded.member_sim(child_id)
	check(child != null and str(child.character.age_stage) == "child", "The child is still a child.")
	home.free()
	loaded.free()
	print("CHILD_HOME_SAVE %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
