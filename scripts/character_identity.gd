extends RefCounted
class_name LifeCharacterIdentity
## Deterministic, complete creator appearances using the authored model controls.
## generate(seed, template, household, styling) returns a deep copy. The template's
## age, explicit gender, traits, aspiration and other gameplay fields survive;
## name and appearance change. Styling optionally supplies hair/outfits/bottoms
## index arrays from LifeActor. It never enables an adult style on a baby.
## Call profile.merge(generate(...), true) when preserving a creator Dictionary's
## shared household reference; append the result directly for a new housemate.

const FACE_KEYS: Array[String] = ["face_round", "jaw_strong", "nose_wide", "eye_spacing", "nose_length", "lip_fullness", "brow_arch", "chin_length", "face_length", "mouth_width", "nose_bridge"]
const SIGNED_FACE_KEYS: Array[String] = ["nose_length", "lip_fullness", "brow_arch", "chin_length", "face_length", "mouth_width", "nose_bridge"]
# Deliberately different proportions, followed by small individual variation.
# Every feature combination is independent of complexion, frame and name.
const FACES: Array = [
	# Cheeks, jaw, nose width, eye set; nose length, lips, brow, chin;
	# lower-face length, mouth width and bridge profile.
	[.12, .18, .24, .16, -.48, -.25,  .12, -.40,  .40, -.30,  .20],
	[.72, .15, .36, .56, -.38,  .52,  .36, -.55, -.65,  .45, -.50],
	[.22, .78, .32, .28,  .52, -.42, -.28,  .46,  .65, -.18,  .65],
	[.34, .38, .78, .64, -.14,  .45, -.36,  .10, -.20,  .65, -.55],
	[.58, .60, .18, .30,  .34,  .12,  .62, -.26,  .12, -.45,  .50],
	[.16, .24, .58, .80,  .64, -.10,  .34,  .38,  .70,  .30,  .15],
	[.78, .34, .68, .18, -.60,  .64, -.22, -.62, -.60,  .50, -.60],
	[.42, .76, .56, .76,  .08,  .20, -.48,  .54,  .32,  .62,  .00],
	[.26, .52, .14, .68,  .46, -.32,  .65, -.12,  .62, -.32,  .58],
	[.60, .16, .76, .38, -.32,  .58,  .22, -.36, -.48,  .44, -.36],
	[.12, .66, .72, .12,  .62, -.38, -.56,  .64,  .46, -.35,  .32],
	[.78, .64, .32, .82, -.18,  .28,  .50,  .02, -.12,  .08,  .42],
]
const BUILDS: Array = [
	[.89, .95], [.94, 1.06], [1.04, .94], [1.13, 1.06],
	[1.10, .98], [.91, 1.02], [1.01, 1.08], [1.04, 1.00],
]
const SKIN_TONES: Array[String] = ["f2d5bf", "edc4a6", "dfb493", "d39b7a", "c28b66", "b77955", "a77351", "925e43", "805239", "704932", "603c2d", "492f26"]
const HAIR_COLORS: Array[String] = ["211e1c", "302521", "473027", "684632", "875437", "a06b43", "b39666", "d7c19a", "744236", "462e33"]
const ELDER_HAIR_COLORS: Array[String] = ["bfb8aa", "d9d6cd", "85817c", "66635f", "a19682"]
const EYE_COLORS: Array[String] = ["49352a", "63462f", "866740", "8e8755", "55715d", "657966", "53748b", "879298"]
# A dominant colour, supporting neutral and shoe colour for each outfit palette.
const PALETTES: Array = [
	["397a75", "e2d5bb", "e9e2d6"], ["b65f4e", "394d57", "eee5d6"],
	["557993", "343e4b", "e6e4dc"], ["a78849", "3e4940", "49382e"],
	["85647f", "d6ccbb", "43353c"], ["ebe1cb", "72534b", "433d39"],
	["40524e", "b29a7c", "e5dcc7"], ["96454d", "303d42", "32292a"],
	["73866e", "e7d9c2", "594a3f"], ["3e5879", "aa8b6d", "41342b"],
	["d3a077", "454a59", "e7e1d7"], ["5c526c", "8c9289", "363537"],
]
const FIRST_NAMES: Array[String] = ["Mara", "Ellis", "Jules", "Noa", "Robin", "Avery", "Morgan", "Jamie", "Remy", "Sage", "Wren", "Alex", "Drew", "Riley", "Marin", "Sasha", "Indigo", "Quinn", "Rowan", "Kit", "Charlie", "River", "Micah", "Skyler", "Emery", "Finley", "Cameron", "Reese", "Blair", "Lane", "Devon", "Arden"]
const LAST_NAMES: Array[String] = ["Vale", "Rowan", "Park", "Rivera", "Ash", "Woods", "Bell", "Reed", "Finch", "Ellis", "Moss", "Linden", "Brooks", "Solis", "Hayes", "North", "Sutton", "Lane", "Flores", "Reyes", "Song", "Kim", "Patel", "Shah", "Okafor", "Mensah", "Clarke", "Bennett", "Castillo", "Hale", "Laurent", "Silva"]

static func generate(seed_value: int, template: Dictionary = {}, household_profiles: Array = [], styling: Dictionary = {}) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var result: Dictionary = template.duplicate(true)
	result.erase("world_state")
	var stage: String = LifeLifecycle.stage_for(template)
	result["age_stage"] = stage
	result["life_stage"] = LifeLifecycle.eligibility(stage)
	if not result.has("traits"): result["traits"] = ["Creative", "Outgoing"]
	if not result.has("aspiration"): result["aspiration"] = "Balanced"
	var best: Dictionary = {}
	var best_distance: float = -1.0
	# Prefer a face/build that is recognizably different from existing housemates.
	# Bounded search always completes even for an unusually large caller list.
	for attempt: int in range(24):
		var look: Dictionary = _appearance(rng, result, stage, styling)
		var nearest: float = 10.0
		for other: Dictionary in household_profiles:
			nearest = minf(nearest, _distance(look, other))
		if nearest > best_distance:
			best = look
			best_distance = nearest
		if nearest >= .48: break
	result.merge(best, true)
	result["name"] = _unique_name(rng, household_profiles)
	return result

static func _appearance(rng: RandomNumberGenerator, template: Dictionary, stage: String, styling: Dictionary) -> Dictionary:
	var look: Dictionary = {}
	var declared_gender: String = str(template.get("gender", "")).to_lower()
	look["frame"] = (1 if declared_gender == "male" else 0) if declared_gender in ["male", "female"] else rng.randi_range(0, 1)
	var face: Array = FACES[rng.randi_range(0, FACES.size() - 1)]
	for index: int in FACE_KEYS.size():
		var signed_feature: bool = FACE_KEYS[index] in SIGNED_FACE_KEYS
		var variation: float = rng.randf_range(-.06, .06) if signed_feature else rng.randf_range(-.085, .085)
		look[FACE_KEYS[index]] = snappedf(clampf(float(face[index]) + variation, -.8 if signed_feature else .02, .8 if signed_feature else .92), .01)
	var build: Array = BUILDS[rng.randi_range(0, BUILDS.size() - 1)]
	look["body_scale"] = snappedf(clampf(float(build[0]) + rng.randf_range(-.015, .015), .85, 1.15), .01)
	look["height_scale"] = snappedf(clampf(float(build[1]) + rng.randf_range(-.009, .009), .93, 1.08), .01)
	var baby: bool = stage == "baby"
	var allowed_hair: Array = [0, 1, 2] if baby else [0, 1, 2, 3, 4, 5, 6, 7]
	look["hair"] = _choose_style(rng, styling.get("hair", allowed_hair), allowed_hair)
	look["outfit"] = _choose_style(rng, styling.get("outfits", [0, 1, 2, 3, 4]), [0] if baby else [0, 1, 2, 3, 4])
	look["bottom"] = _choose_style(rng, styling.get("bottoms", [0, 1]), [0] if baby else [0, 1])
	look["skin_color"] = SKIN_TONES[rng.randi_range(0, SKIN_TONES.size() - 1)]
	var hair_colors: Array[String] = ELDER_HAIR_COLORS if stage == "elder" and rng.randf() < .8 else HAIR_COLORS
	look["hair_color"] = hair_colors[rng.randi_range(0, hair_colors.size() - 1)]
	look["eye_color"] = EYE_COLORS[rng.randi_range(0, EYE_COLORS.size() - 1)]
	var palette: Array = PALETTES[rng.randi_range(0, PALETTES.size() - 1)]
	look["top_color"] = palette[0]
	look["bottom_color"] = palette[1]
	look["shoe_color"] = palette[2]
	return look

static func _choose_style(rng: RandomNumberGenerator, requested: Variant, allowed: Array) -> int:
	var choices: Array[int] = []
	if requested is Array:
		for value: Variant in requested:
			if value is int and value in allowed and not choices.has(value): choices.append(value)
	if choices.is_empty(): choices.append(int(allowed[0]))
	return choices[rng.randi_range(0, choices.size() - 1)]

static func _distance(a: Dictionary, b: Dictionary) -> float:
	var face_distance: float = 0.0
	for key: String in FACE_KEYS:
		var domain: float = 2.0 if key in SIGNED_FACE_KEYS else 1.0
		face_distance += pow((float(a.get(key, 0.0)) - float(b.get(key, 0.0))) / domain, 2)
	# Normalize both the signed control domains and feature count so adding more
	# controls cannot make effectively similar housemates pass the old threshold.
	return sqrt(face_distance * 4.0 / FACE_KEYS.size()) + absf(float(a.get("body_scale", 1.0)) - float(b.get("body_scale", 1.0))) * .4 + (.10 if a.get("frame", 0) != b.get("frame", 0) else 0.0)

static func _unique_name(rng: RandomNumberGenerator, household_profiles: Array) -> String:
	var occupied: Dictionary = {}
	for person: Dictionary in household_profiles:
		occupied[str(person.get("name", "")).strip_edges().to_lower()] = true
	var combination_count: int = FIRST_NAMES.size() * LAST_NAMES.size()
	var start: int = rng.randi_range(0, combination_count - 1)
	for offset: int in combination_count:
		var index: int = (start + offset) % combination_count
		var candidate: String = FIRST_NAMES[index % FIRST_NAMES.size()] + " " + LAST_NAMES[index / FIRST_NAMES.size()]
		if not occupied.has(candidate.to_lower()): return candidate
	# The creator permits eight members; this also behaves for external callers
	# that have exhausted all 1,024 combinations.
	var serial: int = 2
	while occupied.has("alex rivera %d" % serial): serial += 1
	return "Alex Rivera %d" % serial
