extends SceneTree
## Generated identities stay distinct, age-compatible and saveable without
## changing the caller's profile, personality or the simulation random stream.

const Identity = preload("res://scripts/character_identity.gd")
const APPEARANCE_KEYS: Array[String] = ["name", "frame", "hair", "outfit", "bottom", "face_round", "jaw_strong", "nose_wide", "eye_spacing", "nose_length", "lip_fullness", "brow_arch", "chin_length", "face_length", "mouth_width", "nose_bridge", "body_scale", "height_scale", "skin_color", "hair_color", "eye_color", "top_color", "bottom_color", "shoe_color"]
var checks: int = 0
var failures: int = 0

func _initialize() -> void: run.call_deferred()

func check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(description)

func same_value(a: Variant, b: Variant) -> bool:
	# JSON prints decimal numbers; compare appearance weights at engine precision.
	if (a is float or a is int) and (b is float or b is int): return is_equal_approx(float(a), float(b))
	return a == b

func valid_appearance(person: Dictionary) -> bool:
	for key: String in APPEARANCE_KEYS:
		if not person.has(key): return false
	for key: String in Identity.FACE_KEYS:
		if float(person[key]) < (-1.0 if key in Identity.SIGNED_FACE_KEYS else 0.0) or float(person[key]) > 1.0: return false
	if float(person.body_scale) < .85 or float(person.body_scale) > 1.15: return false
	if float(person.height_scale) < .93 or float(person.height_scale) > 1.08: return false
	if int(person.frame) not in [0, 1] or int(person.hair) not in range(8): return false
	if int(person.outfit) not in range(5) or int(person.bottom) not in [0, 1]: return false
	for key: String in ["skin_color", "hair_color", "eye_color", "top_color", "bottom_color", "shoe_color"]:
		if not LifeBabyPlan._color(person[key]): return false
	return str(person.name).length() <= 48 and not str(person.name).strip_edges().is_empty()

func run() -> void:
	var template: Dictionary = {"name":"Existing Person", "traits":["Bookworm", "Neat"], "aspiration":"Successful", "gender":"female", "age_stage":"adult", "life_stage":"adult", "world_state":{"player":[1, 2, 3]}}
	var before: Dictionary = template.duplicate(true)
	var first: Dictionary = Identity.generate(61347, template)
	check(first == Identity.generate(61347, template), "A seed reproduces the full identity")
	check(template == before, "Generation leaves the source Dictionary and nested state intact")
	check(not first.has("world_state"), "New creator identities cannot inherit an old world position")
	check(first.traits == template.traits and first.aspiration == template.aspiration, "Appearance generation preserves chosen personality")
	check(first.gender == "female" and first.frame == 0 and first.age_stage == "adult", "Declared gender and age remain consistent with the generated appearance")
	first.traits.append("Creative")
	check(template.traits.size() == 2, "The generated profile does not share mutable personality arrays")
	seed(918273)
	var expected_random: int = randi()
	seed(918273)
	Identity.generate(333)
	check(randi() == expected_random, "Identity generation does not consume simulation randomness")
	var original_name: String = str(Identity.generate(9012).name)
	var colliding: Array = [{"name":"  " + original_name.to_upper() + "  "}]
	check(str(Identity.generate(9012, {}, colliding).name).to_lower() != original_name.to_lower(), "Names avoid existing household names regardless of case or outer spaces")
	var limited: Dictionary = Identity.generate(123, {}, [], {"hair":[6], "outfits":[2], "bottoms":[0]})
	check(limited.hair == 6 and limited.outfit == 2 and limited.bottom == 0, "Supplied authored wardrobe choices constrain the result")
	for stage: String in LifeLifecycle.STAGES:
		var stage_template: Dictionary = {"age_stage":stage, "life_stage":LifeLifecycle.eligibility(stage)}
		for serial: int in 24:
			var person: Dictionary = Identity.generate(1000 + serial, stage_template)
			check(valid_appearance(person), "%s identity %d has complete valid appearance fields" % [stage, serial])
			check(person.age_stage == stage and person.life_stage == LifeLifecycle.eligibility(stage), "Generation preserves lifecycle eligibility")
			if stage == "baby":
				check(LifeBabyPlan.profile_error(person).is_empty(), "Generated baby fits the strict pending-birth validator: " + LifeBabyPlan.profile_error(person))
		var state_sim := LifeSim.new()
		var restored_sim := LifeSim.new()
		root.add_child(state_sim)
		root.add_child(restored_sim)
		state_sim.new_household(Identity.generate(24, stage_template))
		var json_state: Dictionary = JSON.parse_string(JSON.stringify(LifeSaveLibrary._json_safe(state_sim.get_state())))
		var loaded: Dictionary = restored_sim.restore_state(json_state)
		check(bool(loaded.ok), "A generated %s identity passes actual JSON save restoration: %s" % [stage, str(loaded.get("error", ""))])
		for key: String in APPEARANCE_KEYS:
			check(same_value(restored_sim.character.get(key), state_sim.character.get(key)), "JSON preserves %s for %s" % [key, stage])
		state_sim.queue_free()
		restored_sim.queue_free()
	var baby: Dictionary = Identity.generate(55, {"age_stage":"baby", "life_stage":"minor"}, [], {"hair":[7], "outfits":[4], "bottoms":[1]})
	check(baby.hair == 0 and baby.outfit == 0 and baby.bottom == 0 and LifeBabyPlan.profile_error(baby).is_empty(), "An adult caller wardrobe cannot put unavailable hair or clothing on a baby")
	for feature: String in Identity.SIGNED_FACE_KEYS:
		for extreme: float in [-1.0, 1.0]:
			var valid: Dictionary = baby.duplicate(true)
			valid[feature] = extreme
			check(LifeBabyPlan.profile_error(valid).is_empty(), "Both authored endpoints of " + feature + " pass pending-birth validation")
		for invalid: Variant in [-1.01, 1.01, NAN, INF, "0.5", false, {}]:
			var malformed: Dictionary = baby.duplicate(true)
			malformed[feature] = invalid
			check(not LifeBabyPlan.profile_error(malformed).is_empty(), "Malformed signed facial control is rejected: " + feature)
	var legacy_baby: Dictionary = baby.duplicate(true)
	for feature: String in Identity.SIGNED_FACE_KEYS: legacy_baby.erase(feature)
	check(LifeBabyPlan.profile_error(legacy_baby).is_empty(), "A baby saved before the signed controls still validates")
	for feature: String in ["face_round", "jaw_strong", "nose_wide", "eye_spacing"]:
		var malformed: Dictionary = baby.duplicate(true)
		malformed[feature] = -.01
		check(not LifeBabyPlan.profile_error(malformed).is_empty(), "Existing facial control still rejects negative values: " + feature)
	var mother: Dictionary = Identity.generate(3099)
	var father: Dictionary = Identity.generate(8140)
	var inherited: Dictionary = {"skin_color":false, "hair_color":false, "eye_color":false}
	var fallbacks: Dictionary = {"skin_color":LifeBabyPlan.SKIN_TONES, "hair_color":LifeBabyPlan.HAIR_COLORS, "eye_color":LifeBabyPlan.EYE_COLORS}
	for serial: int in range(1, 33):
		var child: Dictionary = LifeBabyPlan.roll(mother, father, serial)
		check(LifeBabyPlan.profile_error(child).is_empty(), "A baby with the expanded parental palette still passes save validation")
		for key: String in inherited:
			var resembles_parent: bool = child[key] == mother[key] or child[key] == father[key]
			inherited[key] = bool(inherited[key]) or resembles_parent
			check(resembles_parent or child[key] in fallbacks[key], "Baby " + key + " comes from a parent or the valid fallback palette")
	for key: String in inherited:
		check(bool(inherited[key]), "Generated parental " + key + " survives real conception rolls")
		var rng := RandomNumberGenerator.new()
		rng.seed = 6530
		var custom: Dictionary = {key:"#ABCDEF80"}
		var custom_seen: bool = false
		for serial: int in 24:
			var inherited_color: String = LifeBabyPlan._inherit([custom], rng, fallbacks[key], key)
			custom_seen = custom_seen or inherited_color == custom[key]
		check(custom_seen, "Valid parent hex outside the predefined palette is preserved exactly for " + key)
		for invalid: Variant in [null, "invalid", "12345", 123456, false, {}, []]:
			for serial: int in 8:
				check(LifeBabyPlan._inherit([{key:invalid}], rng, fallbacks[key], key) in fallbacks[key], "Invalid parental " + key + " safely uses a palette fallback")
	var people: Array = []
	var names: Dictionary = {}
	var faces: Dictionary = {}
	var bodies: Dictionary = {}
	var styles: Dictionary = {}
	for serial: int in 8:
		var person: Dictionary = Identity.generate(61100 + serial, template, people)
		check(not names.has(person.name), "Every generated household member gets a distinct name")
		for other: Dictionary in people:
			check(Identity._distance(person, other) >= .40, "Housemates have separated facial proportions even with a shared gender template")
		people.append(person)
		names[person.name] = true
		faces[str(Identity.FACE_KEYS.map(func(key: String): return person[key]))] = true
		bodies[str([person.body_scale, person.height_scale])] = true
		styles[str([person.hair, person.outfit, person.bottom, person.top_color])] = true
	check(faces.size() == 8 and bodies.size() >= 6 and styles.size() == 8, "A full household has eight faces and outfits and at least six different builds")
	for feature: String in Identity.SIGNED_FACE_KEYS:
		check(people.any(func(person: Dictionary): return float(person[feature]) < -.1) and people.any(func(person: Dictionary): return float(person[feature]) > .1), "The household explores both halves of the authored " + feature + " range")
	var home := LifeHousehold.new()
	var loaded_home := LifeHousehold.new()
	root.add_child(home)
	root.add_child(loaded_home)
	home.new_household(people)
	var restored: Dictionary = loaded_home.restore_state(JSON.parse_string(JSON.stringify(home.json_safe(home.get_state([])))))
	check(bool(restored.ok), "The entire generated household restores through the household validator: " + str(restored.get("error", "")))
	for index: int in 8:
		for key: String in APPEARANCE_KEYS:
			check(same_value(loaded_home.members[index].sim.character[key], people[index][key]), "Household save retains each member's individual " + key)
	home.queue_free()
	loaded_home.queue_free()
	var authored: Array = []
	for id: String in LifeResidentCatalogue.IDS:
		var person: Dictionary = LifeResidentCatalogue.PEOPLE[id]
		check(valid_appearance(person), id + " has an authored full appearance with no default face or palette")
		for other: Dictionary in authored:
			check(Identity._distance(person, other) > .5, "Authored neighbors have distinct facial structures and builds")
		authored.append(person)
	for serial: int in range(1, 8):
		var candidates: Array = []
		for choice: int in LifeAdoption.CANDIDATE_COUNT:
			var candidate: Dictionary = LifeAdoption.candidate(serial, choice)
			var index: int = (serial - 1) * LifeAdoption.CANDIDATE_COUNT + choice
			check(valid_appearance(candidate) and candidate.age_stage == "child", "Every adoption candidate has a complete child appearance")
			check(candidate.name == LifeAdoption.NAMES[index % LifeAdoption.NAMES.size()] and candidate.frame == index % 2, "Adoption names and frames retain their stable serial/choice meaning")
			check(candidate.traits == [["Creative", "Bookworm"], ["Outgoing", "Active"], ["Neat", "Foodie"]][choice] and candidate.aspiration == ["Maker", "Connected", "Balanced"][choice], "Adoption preserves the existing personalities and aspirations")
			check(candidate == LifeAdoption.candidate(serial, choice), "Reopening an adoption card retains the reviewed identity")
			for other: Dictionary in candidates:
				check(Identity._distance(candidate, other) >= .40, "Each adoption review contains three different facial identities")
			candidates.append(candidate)
	await process_frame
	print("CHARACTER_IDENTITY_RESULT ", checks, " checks; ", failures, " failures")
	quit(0 if failures == 0 else 1)
