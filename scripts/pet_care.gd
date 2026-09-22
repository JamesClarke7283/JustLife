extends RefCounted
class_name LifePetCare
## What a pet needs, what it can learn, and who it knows.
##
## A pet is not a Lifelet and does not share its simulation, but a household pet
## still has a day: it gets hungry, tired and bored, it learns tricks, and it
## forms its own bond with each person it lives with. This file owns all of that
## as pure static policy — no Nodes, no clock, no wallet — so the household can
## store it, the HUD can draw it and a save can validate it without any of them
## duplicating a rule.
##
## The needs mirror a Lifelet's own list deliberately, so the HUD draws a pet's
## needs with the same rows it already draws for a person.

const VERSION: int = 1

## The needs a pet has, in the order the HUD shows them. These are a Lifelet's
## own need keys, so one panel renders either.
const NEED_NAMES: Array[String] = ["hunger", "energy", "hygiene", "bladder", "fun", "social"]

## How fast each need falls, per game minute. A pet's day is a little slower than
## a Lifelet's, so a pet left alone through a working day is hungry by evening
## rather than starving at noon.
const NEED_DECAY: Dictionary = {
	"hunger": 2.6, "energy": 2.2, "hygiene": 1.5, "bladder": 2.4, "fun": 2.2, "social": 1.8,
}

## What a pet can learn. Tricks are the skill a child or teen can teach; agility
## grows from play; obedience grows from being fed and petted by name.
const SKILL_NAMES: Array[String] = ["tricks", "agility", "obedience"]
const SKILL_LABELS: Dictionary = {"tricks": "Tricks", "agility": "Agility", "obedience": "Obedience"}

## The tricks a pet learns in order, each needing the level on its left. Naming
## them gives the teaching interaction something concrete to show progress
## against, rather than an anonymous bar.
const TRICKS: Array[Dictionary] = [
	{"id": "sit", "label": "Sit", "level": 1},
	{"id": "paw", "label": "Shake a paw", "level": 2},
	{"id": "come", "label": "Come when called", "level": 3},
	{"id": "roll", "label": "Roll over", "level": 4},
	{"id": "fetch", "label": "Fetch", "level": 5},
	{"id": "speak", "label": "Speak", "level": 6},
	{"id": "spin", "label": "Spin around", "level": 7},
	{"id": "bow", "label": "Take a bow", "level": 8},
	{"id": "jump", "label": "Jump through a hoop", "level": 9},
	{"id": "tidy", "label": "Fetch the lead", "level": 10},
]

## A skill's xp cost rises with its level, exactly as a Lifelet's does, so a pet
## and a person level at a comparable pace.
const XP_PER_LEVEL: float = 50.0
const MAX_LEVEL: int = 10

## The five things a player can do with a pet. `min_age` is the youngest life
## stage that may do it; `teaches` names the skill the actor's own level grows,
## which is how a child teaching a trick also becomes more logical.
const INTERACTIONS: Array[Dictionary] = [
	{"id": "pet_feed", "label": "Feed Dog", "needs": {"hunger": 42.0, "social": 6.0}, "pet_skill": "obedience", "pet_xp": 8.0, "duration": 15.0, "min_age": "", "teaches": "", "teach_xp": 0.0},
	{"id": "pet_pet", "label": "Pet", "needs": {"fun": 14.0, "social": 16.0}, "pet_skill": "obedience", "pet_xp": 12.0, "duration": 12.0, "min_age": "", "teaches": "", "teach_xp": 0.0},
	{"id": "pet_tummy_rub", "label": "Tummy rub", "needs": {"fun": 28.0, "social": 20.0}, "pet_skill": "obedience", "pet_xp": 14.0, "duration": 20.0, "min_age": "", "teaches": "", "teach_xp": 0.0, "dog_only": true},
	{"id": "pet_play", "label": "Play with Dog", "needs": {"fun": 40.0, "energy": -6.0, "social": 24.0}, "pet_skill": "agility", "pet_xp": 22.0, "duration": 30.0, "min_age": "", "teaches": "fitness", "teach_xp": 10.0},
	{"id": "pet_tug", "label": "Tug-of-war", "needs": {"fun": 36.0, "energy": -8.0, "social": 18.0}, "pet_skill": "agility", "pet_xp": 20.0, "duration": 22.0, "min_age": "", "teaches": "fitness", "teach_xp": 14.0, "dog_only": true},
	{"id": "pet_teach_trick", "label": "Play Tricks", "needs": {"fun": 20.0, "energy": -4.0, "social": 18.0}, "pet_skill": "tricks", "pet_xp": 30.0, "duration": 35.0, "min_age": "child", "teaches": "logic", "teach_xp": 26.0},
	{"id": "pet_walk", "label": "Take for a Walk", "needs": {"fun": 28.0, "energy": -8.0, "social": 20.0}, "pet_skill": "agility", "pet_xp": 18.0, "duration": 40.0, "min_age": "child", "teaches": "fitness", "teach_xp": 22.0},
	{"id": "pet_train", "label": "Train obedience", "needs": {"fun": 12.0, "social": 14.0}, "pet_skill": "obedience", "pet_xp": 26.0, "duration": 25.0, "min_age": "adult", "teaches": "parenting", "teach_xp": 18.0},
]

## The youngest life stage that may handle a pet at all. A baby may watch one but
## not handle it, so the option is withheld rather than silently failing. The
## comparison reads the lifecycle's own stage order rather than repeating it, so a
## stage added there cannot silently lock pets away from a whole age.
const HANDLING_FROM: String = "child"

## Starting needs for a pet that has just come home: content, fed and rested.
const FRESH_NEEDS: Dictionary = {"hunger": 82.0, "energy": 76.0, "hygiene": 80.0, "bladder": 74.0, "fun": 64.0, "social": 58.0}

## How much friendship one interaction adds to the bond with its actor, before
## the pet's own mood scales it.
const BOND_PER_INTERACTION: float = 7.0
## Friendship thresholds that rename the bond, lowest first.
const BOND_STATUS: Array[Dictionary] = [
	{"at": 0.0, "label": "Wary"},
	{"at": 20.0, "label": "Getting used to you"},
	{"at": 45.0, "label": "Friendly"},
	{"at": 70.0, "label": "Devoted"},
	{"at": 92.0, "label": "Inseparable"},
]


static func interaction(id: String) -> Dictionary:
	for entry: Dictionary in INTERACTIONS:
		if str(entry.id) == id: return entry
	return {}


static func interaction_ids() -> Array[String]:
	var out: Array[String] = []
	for entry: Dictionary in INTERACTIONS:
		out.append(str(entry.id))
	return out


## Whether a life stage may handle a pet at all.
static func stage_handles(stage: String) -> bool:
	return _stage_at_least(stage, HANDLING_FROM)


## Why this actor may not use this interaction, or "" when it may. One gate, so
## the withheld option and a refused call say exactly the same thing.
static func interaction_error(id: String, stage: String, away: bool = false, species: String = "dog") -> String:
	var entry: Dictionary = interaction(id)
	if entry.is_empty(): return "That is not something you can do with a pet."
	if away: return "Wait until this Lifelet is home."
	if not stage_handles(stage):
		return "A %s is too young to handle a pet. An older Lifelet can." % str(LifeLifecycle.LABELS.get(stage, stage)).to_lower()
	var min_age: String = str(entry.get("min_age", ""))
	if not min_age.is_empty() and not _stage_at_least(stage, min_age):
		return "Only an %s or older Lifelet can %s." % [str(LifeLifecycle.LABELS.get(min_age, min_age)).to_lower(), str(entry.label).to_lower()]
	if bool(entry.get("dog_only", false)) and species != "dog":
		return "That is a dog's own game. Cats keep to themselves."
	return ""


## "At least child" is a rank comparison against the lifecycle's own stage order,
## so the ranks stay one fact rather than two that can drift apart.
static func _stage_at_least(stage: String, minimum: String) -> bool:
	return LifeLifecycle.at_least(stage, minimum)


## A fresh care record for a pet that has just arrived.
static func fresh() -> Dictionary:
	return {
		"version": VERSION,
		"needs": FRESH_NEEDS.duplicate(true),
		"skills": _fresh_skills(),
		"bonds": {},
		"tricks": [],
	}


static func _fresh_skills() -> Dictionary:
	var out: Dictionary = {}
	for name: String in SKILL_NAMES:
		out[name] = {"level": 1, "xp": 0.0}
	return out


static func level(care: Dictionary, skill: String) -> int:
	var record: Variant = (care.get("skills", {}) as Dictionary).get(skill, {})
	return int((record as Dictionary).get("level", 1)) if record is Dictionary else 1


static func xp(care: Dictionary, skill: String) -> float:
	var record: Variant = (care.get("skills", {}) as Dictionary).get(skill, {})
	return float((record as Dictionary).get("xp", 0.0)) if record is Dictionary else 0.0


## How much experience the next level costs at the level reached.
static func xp_required(for_level: int) -> float:
	return float(for_level) * XP_PER_LEVEL


## Grow one pet skill, levelling as it crosses each threshold. Returns the new
## level, so a caller can tell a level-up from ordinary progress.
static func gain_xp(care: Dictionary, skill: String, amount: float) -> int:
	if not SKILL_NAMES.has(skill) or amount <= 0.0: return level(care, skill)
	var skills: Dictionary = care.get("skills", {})
	var record: Dictionary = skills.get(skill, {"level": 1, "xp": 0.0})
	var current: int = int(record.level)
	if current >= MAX_LEVEL:
		record["xp"] = 0.0
		skills[skill] = record
		return MAX_LEVEL
	record["xp"] = float(record.xp) + amount
	while current < MAX_LEVEL and float(record.xp) >= xp_required(current):
		record["xp"] = float(record.xp) - xp_required(current)
		current += 1
	if current >= MAX_LEVEL: record["xp"] = 0.0
	record["level"] = current
	skills[skill] = record
	# A new trick is learned the moment the skill reaches its own level, so the
	# list of learned tricks follows the skill rather than a separate counter.
	_sync_tricks(care)
	return current


static func _sync_tricks(care: Dictionary) -> void:
	var learned: Array = care.get("tricks", [])
	var trick_level: int = level(care, "tricks")
	for entry: Dictionary in TRICKS:
		if int(entry.level) <= trick_level and not learned.has(str(entry.id)):
			learned.append(str(entry.id))
	care["tricks"] = learned


## Every trick this pet has learned, in the order they are taught.
static func known_tricks(care: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for entry: Dictionary in TRICKS:
		if int(entry.level) <= level(care, "tricks"): out.append(str(entry.id))
	return out


## The trick a pet is working towards, or {} when it knows them all.
static func next_trick(care: Dictionary) -> Dictionary:
	var trick_level: int = level(care, "tricks")
	for entry: Dictionary in TRICKS:
		if int(entry.level) > trick_level: return entry
	return {}


## The trick a skill level unlocks, or "" when that level teaches none. This is
## how a level-up names the trick it just earned without re-reading the list.
static func _trick_learned_at(level_reached: int) -> String:
	for entry: Dictionary in TRICKS:
		if int(entry.level) == level_reached: return str(entry.label)
	return ""


static func trick_label(id: String) -> String:
	for entry: Dictionary in TRICKS:
		if str(entry.id) == id: return str(entry.label)
	return id.capitalize()


## Apply one interaction to a pet's care record: its needs move, its skill grows
## and its bond with the actor deepens. Returns what changed, so the caller can
## report a level-up and the trick it earned without re-deriving either.
static func apply_interaction(care: Dictionary, id: String, actor_id: String) -> Dictionary:
	var entry: Dictionary = interaction(id)
	if entry.is_empty(): return {}
	var needs: Dictionary = care.get("needs", {})
	for key: String in (entry.get("needs", {}) as Dictionary):
		needs[key] = clampf(float(needs.get(key, 50.0)) + float((entry.needs as Dictionary)[key]), 0.0, 100.0)
	care["needs"] = needs
	var skill: String = str(entry.pet_skill)
	var before: int = level(care, skill)
	var after: int = gain_xp(care, skill, float(entry.pet_xp))
	return {
		"skill": skill,
		"level": after,
		"levelled": after > before,
		"learned": _trick_learned_at(after) if after > before else "",
		"bond": add_bond(care, actor_id, BOND_PER_INTERACTION),
		"teaches": str(entry.get("teaches", "")),
		"teach_xp": float(entry.get("teach_xp", 0.0)),
	}


## The bond a pet has with one person, 0..100.
static func bond(care: Dictionary, member_id: String) -> float:
	return float((care.get("bonds", {}) as Dictionary).get(member_id, 0.0))


## Deepen the bond with one person, clamped to the scale.
static func add_bond(care: Dictionary, member_id: String, amount: float) -> float:
	if member_id.is_empty(): return 0.0
	var bonds: Dictionary = care.get("bonds", {})
	var value: float = clampf(float(bonds.get(member_id, 0.0)) + amount, 0.0, 100.0)
	bonds[member_id] = value
	care["bonds"] = bonds
	return value


## How the bond with one person reads.
static func bond_label(value: float) -> String:
	var out: String = str(BOND_STATUS[0].label)
	for entry: Dictionary in BOND_STATUS:
		if value >= float(entry.at): out = str(entry.label)
	return out


## The person this pet is closest to, or "" when it has bonded with nobody yet.
static func closest_bond(care: Dictionary) -> String:
	var best: String = ""
	var best_value: float = 0.0
	var bonds: Dictionary = care.get("bonds", {})
	for id: String in bonds:
		if float(bonds[id]) > best_value:
			best_value = float(bonds[id])
			best = id
	return best


## Advance every need by one tick of game minutes. A caller that passes no time
## — a paused household — leaves a pet's needs exactly where they were.
static func tick(care: Dictionary, minutes: float) -> void:
	if minutes <= 0.0: return
	var needs: Dictionary = care.get("needs", {})
	for key: String in NEED_NAMES:
		var decay: float = float(NEED_DECAY.get(key, 0.0)) * minutes
		needs[key] = clampf(float(needs.get(key, 0.0)) - decay, 0.0, 100.0)
	care["needs"] = needs


## The pet's own mood word, from its weakest need. Deliberately a small ladder:
## a pet reads as content unless something is genuinely wrong.
static func mood_label(care: Dictionary) -> String:
	var needs: Dictionary = care.get("needs", {})
	var lowest: float = 101.0
	var key: String = ""
	for name: String in NEED_NAMES:
		var value: float = float(needs.get(name, 50.0))
		if value < lowest:
			lowest = value
			key = name
	if lowest >= 70.0: return "Content"
	if lowest >= 45.0: return "Settled"
	if key == "hunger": return "Hungry"
	if key == "energy": return "Sleepy"
	if key == "fun": return "Bored"
	if key == "bladder": return "Needs the garden"
	if key == "hygiene": return "Mucky"
	if key == "social": return "Lonely"
	return "Out of sorts"


## Validate one pet's care record. Absent is legal and means a pet that predates
## this record, which loads with fresh needs rather than being refused.
static func validate(value: Variant, member_ids: Array) -> String:
	if value == null: return ""
	if not value is Dictionary: return "Save contains an invalid pet condition."
	var care: Dictionary = value
	if not (care.get("version", 0) is int or care.get("version", 0) is float):
		return "Save contains an invalid pet condition version."
	if int(care.get("version", 0)) != VERSION:
		return "The saved pet condition uses an unsupported version."
	var needs: Variant = care.get("needs", null)
	if not needs is Dictionary: return "Save contains invalid pet needs."
	for name: String in NEED_NAMES:
		var amount: Variant = (needs as Dictionary).get(name, null)
		if not (amount is float or amount is int) or not is_finite(float(amount)):
			return "Save contains an invalid pet need."
		if float(amount) < 0.0 or float(amount) > 100.0:
			return "Save contains an impossible pet need."
	var skills: Variant = care.get("skills", null)
	if not skills is Dictionary: return "Save contains invalid pet skills."
	for name: String in SKILL_NAMES:
		var record: Variant = (skills as Dictionary).get(name, null)
		if not record is Dictionary: return "Save is missing a pet skill."
		if not integer((record as Dictionary).get("level", 0), 1, MAX_LEVEL):
			return "Save contains an impossible pet skill level."
		var amount: Variant = (record as Dictionary).get("xp", null)
		if not (amount is float or amount is int) or not is_finite(float(amount)) or float(amount) < 0.0:
			return "Save contains impossible pet skill progress."
	var bonds: Variant = care.get("bonds", null)
	if not bonds is Dictionary: return "Save contains invalid pet bonds."
	for id: String in bonds:
		var amount: Variant = (bonds as Dictionary)[id]
		if not (amount is float or amount is int) or not is_finite(float(amount)):
			return "Save contains an invalid pet bond."
		if float(amount) < 0.0 or float(amount) > 100.0:
			return "Save contains an impossible pet bond."
	var tricks: Variant = care.get("tricks", null)
	if not tricks is Array: return "Save contains an invalid pet trick list."
	for id: Variant in tricks:
		var known: bool = false
		for entry: Dictionary in TRICKS:
			if str(entry.id) == str(id): known = true
		if not known: return "Save contains an unknown pet trick."
	return ""


static func integer(value: Variant, low: int, high: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floorf(float(value)) and float(value) >= low and float(value) <= high
