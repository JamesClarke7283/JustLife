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
# Saved looks, one per outfit type. Everyday is the generated daily wear; the
# others start from distinct silhouettes and palettes so a wardrobe change is
# visible. Original clothing, not a copy of another game's items.
## Makeup. The authored Makeup_Lips and Makeup_Lids surfaces are tinted at
## runtime, so a look is a colour rather than a mesh. Girls get the whole set;
## boys get the plainer lip tints and a clear option, which is the limited
## makeup set a male Lifelet may wear.
const MAKEUP_LIP_COLORS: Array[String] = [
	"a8564f", "b5453f", "c2554f", "8f3f3c", "7a2f34",
	"d4706a", "c98a86", "b06a70", "8d4a55", "6f3a44",
]
const MAKEUP_EYE_COLORS: Array[String] = [
	"4a3b46", "6b4a5e", "8a5a6e", "3f4a5e", "5e6b8a",
	"2f3a44", "7a5a4a", "4a5e52", "6b3a4a", "8a7a6b",
]
## Men's lip tints: cooler, lower-saturation tints rather than the fuller set.
const MEN_MAKEUP_LIP_COLORS: Array[String] = [
	"8f5a55", "7a4a48", "9c6660", "6b403f",
]
const MEN_MAKEUP_EYE_COLORS: Array[String] = [
	"4a4a52", "5e5560", "3f444a",
]
## Jewelry. A stud or a hoop on each ear, plus a chain at the throat. The
## authored Jewelry_Stud pair already rides the head, so an earring is a tint
## of that surface; a necklace adds a chain the model has never carried.
const JEWELRY_METALS: Array[String] = [
	"d8b45a", "c9c3b6", "d7d2c4", "b08d3f", "e6cf94",
	"8f8a7d", "a86a6a", "6e8a9c", "3f4448", "e8e2d2",
]
## A plain lip and a bare eye are real choices, so each set leads with "none".
const MAKEUP_NONE: String = "none"
## Which makeup a male Lifelet is offered: the limited set, keyed by the same
## names the full set uses.
const MEN_ALLOWED_MAKEUP: Array[String] = ["none", "lips", "eyes"]
const OUTFIT_CATEGORIES: Array[String] = ["everyday", "formal", "athletic", "sleep", "party"]
const OUTFIT_CATEGORY_LABELS: Dictionary = {
	"everyday": "Everyday", "formal": "Formal", "athletic": "Athletic", "sleep": "Sleep", "party": "Party"
}
const OUTFIT_CATEGORY_BLURBS: Dictionary = {
	"everyday": "Easy clothes for the day at home.",
	"formal": "Tailored pieces for evenings and ceremonies.",
	"athletic": "Light layers ready to move.",
	"sleep": "Soft clothes for rest.",
	"party": "A little more occasion than the everyday set.",
}
const OUTFIT_CATEGORY_PRESETS: Dictionary = {
	"formal": {"outfit": 1, "bottom": 0, "top_color": "394d57", "bottom_color": "2c2a2e", "shoe_color": "1f1c1a"},
	"athletic": {"outfit": 3, "bottom": 1, "top_color": "397a75", "bottom_color": "3e4940", "shoe_color": "e6e4dc"},
	"sleep": {"outfit": 4, "bottom": 1, "top_color": "d6ccbb", "bottom_color": "72534b", "shoe_color": "e9e2d6"},
	"party": {"outfit": 2, "bottom": 0, "top_color": "96454d", "bottom_color": "303d42", "shoe_color": "32292a"},
}
const CATEGORY_OUTFIT_NAMES: Dictionary = {
	"everyday": ["Casual", "Jacket", "Cardigan", "Tee", "Hoodie"],
	"formal": ["Tuxedo", "Dinner Jacket", "Evening Suit", "Classic Tailored", "Black Tie"],
	"athletic": ["Active Tank", "Speed Jersey", "Warm-up Tee", "Sport Crew", "Training Hoodie"],
	"sleep": ["Comfort Robe", "Lounge Wrap", "Soft Kimono", "Sleep Tunic", "Night Gown"],
	"party": ["Wrap Dress", "Peplum Cardigan", "Festive Sash", "Cocktail Wrap", "Celebration Knit"],
}
const CATEGORY_OUTFIT_TIPS: Dictionary = {
	"everyday": [
		"Short-sleeve shirt with a light collar and placket",
		"Cropped bomber with a stand collar and zip",
		"Open knit cardigan over a cream tee",
		"Plain crew-neck tee",
		"Soft hoodie with a kangaroo pocket"
	],
	"formal": [
		"Full tailored tuxedo jacket with silk lapels and dress tie",
		"Dinner jacket with stand collar and French cuffs",
		"Evening suit coat with structured drape",
		"Classic tailored coat for ceremonies",
		"Refined black tie ensemble with crisp accents"
	],
	"athletic": [
		"Breathable active tank with ribbed armhole binding",
		"Speed training jersey with chevron chest detailing",
		"Performance warm-up crew for outdoor conditioning",
		"Lightweight athletic layer built for movement",
		"Flexible training top with relaxed athletic cut"
	],
	"sleep": [
		"Plush lounging robe with belted waist sash and shawl collar",
		"Cozy open lounge wrap for quiet mornings",
		"Soft draped kimono robe with wide folded collar",
		"Relaxed sleep tunic with ribbed cuffs",
		"Warm bedtime lounging gown"
	],
	"party": [
		"Elegant wrap dress with dramatic diagonal sash and flared hem",
		"Celebration peplum cardigan with tailored sleeves",
		"Festive party wrap with accent waist sash",
		"Chic cocktail evening wrap for dancing",
		"Draped party knit with flowing silhouette"
	],
}
const CATEGORY_BOTTOM_NAMES: Dictionary = {
	"everyday": ["Trousers", "Shorts"],
	"formal": ["Dress Trousers", "Formal Shorts"],
	"athletic": ["Track Pants", "Running Shorts"],
	"sleep": ["Pyjama Bottoms", "Sleep Shorts"],
	"party": ["Tailored Slacks", "Party Shorts"],
}
const CATEGORY_PALETTES: Dictionary = {
	"everyday": {
		"top": ["c97c66", "417a71", "efeadb", "7195b3", "bd9b68", "3d4145"],
		"bottom": ["eadfc9", "3e5955", "51697c", "493e37", "b88a72", "292f32"],
		"shoes": ["e9e4d9", "49382e", "32292a", "eee5d6", "433d39", "1f1c1a"],
	},
	"formal": {
		"top": ["2d3748", "1a202c", "742a2a", "2b4c7e", "4a5568", "f7fafc"],
		"bottom": ["1a202c", "2d3748", "2b4c7e", "3f3f46", "23272e", "e2e8f0"],
		"shoes": ["1a202c", "2d241e", "3b2f2f", "4a3728", "1f1c1a", "262626"],
	},
	"athletic": {
		"top": ["397a75", "e53e3e", "3182ce", "38a169", "d69e2e", "2d3748"],
		"bottom": ["2d3748", "3e4940", "1a202c", "2b4c7e", "4a5568", "edf2f7"],
		"shoes": ["e6e4dc", "3182ce", "e53e3e", "1a202c", "dd6b20", "f7fafc"],
	},
	"sleep": {
		"top": ["d6ccbb", "b7c4cf", "d8b4a0", "c3b1e1", "b2c9ab", "e2e8f0"],
		"bottom": ["72534b", "5c6b73", "8c7a6b", "6e7c7a", "4a5568", "cbd5e0"],
		"shoes": ["e9e2d6", "b8a99a", "8d7b68", "cfc6b8", "5a504a", "f0ece1"],
	},
	"party": {
		"top": ["96454d", "6b46c1", "d69e2e", "319795", "b83280", "1a202c"],
		"bottom": ["303d42", "1a202c", "44337a", "234e52", "2d3748", "e2e8f0"],
		"shoes": ["32292a", "d69e2e", "6b46c1", "1a202c", "b83280", "4a5568"],
	},
}
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
	result.erase("outfit_collection")
	result["outfit_category"] = "everyday"
	ensure_wardrobe(result)
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
	var allowed_hair: Array = [0, 1, 2] if baby else [0, 1, 2, 3, 4, 5, 6, 7, 8, 9]
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

## Makeup and jewelry read off a look with the right default for its gender.
## The authored palettes are the suggested starting shades a swatch row offers;
## a Lifelet may wear any shade the player picks, so `makeup_value` accepts every
## valid colour and only the empty/none marker means bare skin.
static func makeup_lip_colors(look: Dictionary) -> Array:
	return MEN_MAKEUP_LIP_COLORS if is_male(look) else MAKEUP_LIP_COLORS

static func makeup_eye_colors(look: Dictionary) -> Array:
	return MEN_MAKEUP_EYE_COLORS if is_male(look) else MAKEUP_EYE_COLORS

static func is_male(look: Dictionary) -> bool:
	return int(look.get("frame", 0)) == 1 or str(look.get("gender", "female")).to_lower() == "male"

## Whether a stored makeup value is a colour a face can actually wear. Any
## six-digit hex shade is valid: the picker hands back whatever the player chose,
## so a custom lipstick or eyeliner is a colour rather than a membership test.
static func makeup_shade(value: Variant) -> String:
	var shade: String = str(value).trim_prefix("#").to_lower()
	if shade == MAKEUP_NONE or shade.is_empty():
		return MAKEUP_NONE
	if shade.length() != 6:
		return MAKEUP_NONE
	for index: int in range(6):
		if not "0123456789abcdef".contains(shade[index]):
			return MAKEUP_NONE
	return shade

static func makeup_value(look: Dictionary, key: String) -> String:
	return makeup_shade(look.get(key, MAKEUP_NONE))

static func jewelry_metal(look: Dictionary) -> String:
	var value: String = str(look.get("jewelry_metal", JEWELRY_METALS[0])).trim_prefix("#").to_lower()
	return value if JEWELRY_METALS.has(value) else JEWELRY_METALS[0]

static func wardrobe_fields(look: Dictionary) -> Dictionary:
	return {
		"outfit": int(look.get("outfit", 0)),
		"bottom": int(look.get("bottom", 0)),
		"top_color": str(look.get("top_color", "c97c66")),
		"bottom_color": str(look.get("bottom_color", "eadfc9")),
		"shoe_color": str(look.get("shoe_color", "e9e4d9")),
		"outfit_category": normalize_category(look.get("outfit_category", "everyday")),
		"hair": int(look.get("hair", 0)),
		"hair_color": str(look.get("hair_color", "54382a")),
		"eye_color": str(look.get("eye_color", "547365")),
		"makeup_lips": makeup_value(look, "makeup_lips"),
		"makeup_eyes": makeup_value(look, "makeup_eyes"),
		"jewelry_ears": str(look.get("jewelry_ears", MAKEUP_NONE)),
		"jewelry_metal": str(look.get("jewelry_metal", JEWELRY_METALS[0])),
		"jewelry_neck": bool(look.get("jewelry_neck", false)),
	}

static func normalize_category(value: Variant) -> String:
	var category: String = str(value)
	return category if category in OUTFIT_CATEGORIES else "everyday"

static func next_category(value: Variant) -> String:
	var index: int = OUTFIT_CATEGORIES.find(normalize_category(value))
	return OUTFIT_CATEGORIES[(index + 1) % OUTFIT_CATEGORIES.size()]

static func category_label(value: Variant) -> String:
	return str(OUTFIT_CATEGORY_LABELS.get(normalize_category(value), "Everyday"))

static func get_category_tops(category: String) -> Array:
	return CATEGORY_OUTFIT_NAMES.get(normalize_category(category), CATEGORY_OUTFIT_NAMES["everyday"])

static func get_category_top_tips(category: String) -> Array:
	return CATEGORY_OUTFIT_TIPS.get(normalize_category(category), CATEGORY_OUTFIT_TIPS["everyday"])

static func get_category_bottoms(category: String) -> Array:
	return CATEGORY_BOTTOM_NAMES.get(normalize_category(category), CATEGORY_BOTTOM_NAMES["everyday"])

static func get_category_palettes(category: String) -> Dictionary:
	return CATEGORY_PALETTES.get(normalize_category(category), CATEGORY_PALETTES["everyday"])

static func ensure_wardrobe(look: Dictionary) -> Dictionary:
	var stage: String = LifeLifecycle.stage_for(look)
	var current: Dictionary = _slot_from(look, stage)
	if not look.get("outfit_collection") is Dictionary:
		look["outfit_collection"] = {}
	var collection: Dictionary = look["outfit_collection"]
	for category: String in OUTFIT_CATEGORIES:
		if _valid_slot(collection.get(category, {}), stage):
			continue
		collection[category] = current.duplicate(true) if category == "everyday" else _preset_slot(category, current, stage)
	look["outfit_collection"] = collection
	look["outfit_category"] = normalize_category(look.get("outfit_category", "everyday"))
	if not look.has("outfit"):
		_apply_slot(look, collection[look["outfit_category"]], stage)
	return look

static func apply_category(look: Dictionary, category: Variant) -> Dictionary:
	ensure_wardrobe(look)
	var chosen: String = normalize_category(category)
	look["outfit_category"] = chosen
	_apply_slot(look, look["outfit_collection"][chosen], LifeLifecycle.stage_for(look))
	return look

static func _apply_slot(look: Dictionary, source: Variant, stage: String) -> void:
	var slot: Dictionary = _slot_from(source, stage)
	look["outfit"] = slot.outfit
	look["bottom"] = slot.bottom
	look["top_color"] = slot.top_color
	look["bottom_color"] = slot.bottom_color
	look["shoe_color"] = slot.shoe_color

static func store_current(look: Dictionary) -> Dictionary:
	ensure_wardrobe(look)
	var stage: String = LifeLifecycle.stage_for(look)
	var category: String = normalize_category(look.get("outfit_category", "everyday"))
	look["outfit_collection"][category] = _slot_from(look, stage)
	return look

static func _slot_from(source: Variant, stage: String) -> Dictionary:
	var look: Dictionary = source if source is Dictionary else {}
	var baby: bool = stage == "baby"
	return {
		"outfit": 0 if baby else clampi(int(look.get("outfit", 0)), 0, 4),
		"bottom": 0 if baby else clampi(int(look.get("bottom", 0)), 0, 1),
		"top_color": str(look.get("top_color", "c97c66")),
		"bottom_color": str(look.get("bottom_color", "eadfc9")),
		"shoe_color": str(look.get("shoe_color", "e9e4d9")),
	}

static func _preset_slot(category: String, everyday: Dictionary, stage: String) -> Dictionary:
	var slot: Dictionary = everyday.duplicate(true)
	var preset: Dictionary = OUTFIT_CATEGORY_PRESETS.get(category, {})
	if preset is Dictionary:
		slot.merge(preset, true)
	return _slot_from(slot, stage)

static func _valid_slot(value: Variant, stage: String) -> bool:
	if not value is Dictionary:
		return false
	var slot: Dictionary = value
	for key: String in ["outfit", "bottom", "top_color", "bottom_color", "shoe_color"]:
		if not slot.has(key):
			return false
	for key: String in ["makeup_lips", "makeup_eyes", "jewelry_ears", "jewelry_metal"]:
		if slot.has(key) and not str(slot[key]) is String:
			return false
	if slot.has("jewelry_neck") and not slot.jewelry_neck is bool:
		return false
	var baby: bool = stage == "baby"
	if baby and (int(slot.outfit) != 0 or int(slot.bottom) != 0):
		return false
	if not baby and (int(slot.outfit) < 0 or int(slot.outfit) > 4 or int(slot.bottom) < 0 or int(slot.bottom) > 1):
		return false
	return true

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
