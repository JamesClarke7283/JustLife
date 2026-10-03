extends RefCounted
## The facts of household cleaning that need no world: the chore action ids, how long
## each takes and what it costs a Lifelet, who may do it and how high they can reach,
## how fast each kind of dirt returns, and what a saved chain of chores may say.
## `LifeChoreFlow` (chore_flow.gd) is the service that puts them to work.

const IDS: Array[String] = ["chore_vacuum", "chore_vacuum_curtains", "chore_dust", "chore_mop", "chore_wipe_sink", "chore_scrub_toilet", "chore_fluff", "chore_sweep_entry", "chore_wipe_door", "chore_wash_window"]
## Chores that were already real actions; a chain queues them like any other task.
const EXISTING: Array[String] = ["mop_puddle", "clean_plate", "clear_table", "empty_bin", "clean_litter_tray", "put_pet_toy"]
const PLAN_IDS: Array[String] = ["chore_vacuum", "chore_vacuum_curtains", "chore_dust", "chore_mop", "chore_wipe_sink", "chore_scrub_toilet", "chore_fluff", "chore_sweep_entry", "chore_wipe_door", "chore_wash_window", "mop_puddle", "clean_plate", "clear_table", "empty_bin", "clean_litter_tray", "put_pet_toy"]
const MODES: Array[String] = ["task", "quick", "full", "inside", "outside", "custom", "auto"]
const STATION_PREFIX: String = "chore:"
const MAX_PLAN: int = 96
const MAX_KEYS: int = 1024
const NEED_NAMES: Array[String] = ["hunger", "energy", "hygiene", "bladder", "fun", "social"]

## label, base minutes, extra minutes per unit (cushion, metre of surface), the
## household category it belongs to, the dirt kind it clears, and the youngest stage.
const CHORES: Dictionary = {
	"chore_vacuum": {"label": "Vacuum the floor", "short": "Vacuum", "minutes": 3.5, "per": 0.0, "category": "floors", "dirt": "fvac", "min_stage": "child", "wet": 1.0,
		"description": "Push the vacuum cleaner over this patch of floor in long, overlapping strokes."},
	"chore_vacuum_curtains": {"label": "Vacuum the curtains", "short": "Vacuum curtains", "minutes": 8.0, "per": 0.0, "category": "curtains", "dirt": "curt", "min_stage": "teen", "wet": 1.0,
		"description": "Run the hose nozzle across the curtains in passes, working down from the top."},
	"chore_dust": {"label": "Dust the surfaces", "short": "Dust", "minutes": 2.5, "per": 0.4, "category": "dust", "dirt": "dust", "min_stage": "child", "wet": 1.0,
		"description": "Sweep a feather duster over the top and front of this piece."},
	"chore_mop": {"label": "Mop the floor", "short": "Mop", "minutes": 4.0, "per": 0.0, "category": "floors", "dirt": "fmop", "min_stage": "child", "wet": 2.0,
		"description": "Mop this patch of hard floor with the damp mop."},
	"chore_wipe_sink": {"label": "Wipe down the sink", "short": "Wipe the sink", "minutes": 5.0, "per": 0.0, "category": "kitchen", "dirt": "sink", "min_stage": "teen", "wet": 2.0,
		"description": "Scrub the basin, tap and worktop edge with a sponge, then rinse."},
	"chore_scrub_toilet": {"label": "Scrub the toilet", "short": "Scrub the toilet", "minutes": 8.0, "per": 0.0, "category": "bathroom", "dirt": "toilet", "min_stage": "teen", "wet": 2.0,
		"description": "Work the toilet brush round the bowl, then flush."},
	"chore_fluff": {"label": "Fluff the cushions", "short": "Fluff cushions", "minutes": 3.0, "per": .75, "category": "cushions", "dirt": "cush", "min_stage": "child", "wet": 1.0,
		"description": "Plump each cushion and set it square again."},
	"chore_sweep_entry": {"label": "Sweep the front entry", "short": "Sweep the entry", "minutes": 6.0, "per": 0.0, "category": "entry", "dirt": "entry", "min_stage": "child", "wet": 1.0,
		"description": "Sweep the doorstep and steps clear of leaves and grit with a broom."},
	"chore_wipe_door": {"label": "Wipe down the door", "short": "Wipe the door", "minutes": 5.0, "per": 0.0, "category": "entry", "dirt": "door", "min_stage": "child", "wet": 1.0,
		"description": "Spray and wipe the door and its handle."},
	"chore_wash_window": {"label": "Wash the window", "short": "Wash the window", "minutes": 7.0, "per": 0.0, "category": "windows", "dirt": "win", "min_stage": "teen", "wet": 1.0,
		"description": "Spray the glass and draw a squeegee down it in strokes, then wipe the edges."},
}

## Days for each kind of dirt to go from clean to filthy.
const PERIOD: Dictionary = {"fvac": 3.0, "fmop": 4.0, "wmop": 2.4, "dust": 4.0, "cush": 5.0, "curt": 14.0, "win_in": 10.0, "win_out": 8.0, "door": 7.0, "entry": 2.5, "sink": 2.0, "toilet": 2.0}
## Household weights of the "home is N% clean" figure; absent categories drop out.
const WEIGHTS: Dictionary = {"floors": .30, "windows": .15, "dust": .15, "bathroom": .15, "kitchen": .10, "entry": .10, "cushions": .02, "curtains": .02, "toys": .01}
const CATEGORY_LABELS: Dictionary = {"floors": "Floors", "dust": "Dust", "windows": "Windows", "curtains": "Curtains", "cushions": "Cushions", "toys": "Toys", "kitchen": "Kitchen", "bathroom": "Bathroom", "entry": "Entry and doors"}
const CATEGORY_ORDER: Array[String] = ["floors", "dust", "windows", "curtains", "cushions", "toys", "kitchen", "bathroom", "entry"]
## What a Lifelet notices and what needs cleaning from, in percent dirt.
const GRUBBY: float = 35.0
const NEEDS_CLEANING: float = 50.0
const FILTHY: float = 85.0
## How high each stage can work (metres above the floor), measured on the actor rigs.
const REACH_TOP: Dictionary = {"child": 1.21, "teen": 1.67, "young_adult": 1.92, "adult": 1.92, "elder": 1.88}
## Heights the work needs, so a station can be refused to somebody too short.
const STOOL_HEIGHT: float = .30
const COMFORT: float = .17
const DAWN_HOUR: float = 7.0
const DUSK_HOUR: float = 17.5
const AUTO_START: float = 8.0 * 60.0
const AUTO_END: float = 21.0 * 60.0

## Furnishing kinds each chore is offered at: dusted from the top or the front face,
## and cushioned seats. Toys are real items on the floor, tidied by `LifeToyFlow`.
const DUST_MODE: Dictionary = {"bookshelf": "face", "shelf": "face", "desk": "top", "study_desk": "top", "office_desk": "top", "dining": "top", "table": "top", "coffee_table": "top", "side_table": "top", "nightstand": "top", "dressing_table": "top", "tv": "face", "fireplace": "face", "piano": "top"}
const CUSHION_KINDS: Array[String] = ["sofa", "loveseat", "armchair"]

## The chores a click on this kind of furnishing offers.
static func menu_for(kind: String) -> Array[String]:
	var out: Array[String] = []
	if DUST_MODE.has(kind): out.append("chore_dust")
	if kind in CUSHION_KINDS: out.append("chore_fluff")
	match kind:
		"sink": out.append("chore_wipe_sink")
		"toilet": out.append("chore_scrub_toilet")
		"curtains": out.append("chore_vacuum_curtains")
		"house_window": out.append("chore_wash_window")
	return out

static func is_chore(id: String) -> bool:
	return CHORES.has(id)

static func is_plan_id(id: String) -> bool:
	return id in PLAN_IDS

static func definition(id: String) -> Dictionary:
	return CHORES.get(id, {})

static func label(id: String) -> String:
	return str(CHORES.get(id, {}).get("label", id))

static func stage_error(stage: String, id: String) -> String:
	if stage == "baby": return "A baby cannot do that yet."
	var need: String = str(CHORES.get(id, {}).get("min_stage", "child"))
	if not LifeLifecycle.at_least(stage, need): return "Only teens and older can do this chore yet."
	return ""

## Game minutes a chore takes for this Lifelet: the base plus its per-unit share,
## slower for the very young and old, quicker for somebody Neat.
static func duration(id: String, units: float, stage: String, neat: bool) -> float:
	var entry: Dictionary = CHORES.get(id, {})
	if entry.is_empty(): return 8.0
	var minutes: float = float(entry.minutes) + float(entry.per) * units
	minutes = minf(minutes, 14.0 if id == "chore_fluff" else 20.0)
	if stage == "elder": minutes *= 1.25
	elif stage == "child": minutes *= 1.15
	if neat: minutes *= .85
	return snappedf(clampf(minutes, 1.0, 60.0), .1)

## Needs the whole chore spends: tired legs and wet hands, a little boredom; Neat
## Lifelets actually enjoy it.
static func changes(id: String, minutes: float, neat: bool) -> Dictionary:
	var wet: float = float(CHORES.get(id, {}).get("wet", 1.0))
	var result: Dictionary = {"energy": snappedf(-.15 * minutes, .01), "hygiene": snappedf(-.06 * wet * minutes, .01), "fun": snappedf((.07 if neat else -.05) * minutes, .01)}
	return result

## Whether `at` lies in the hours the sun is up, which exterior chores keep to.
static func daylight(minutes_of_day: float) -> bool:
	return minutes_of_day >= DAWN_HOUR * 60.0 and minutes_of_day <= DUSK_HOUR * 60.0

## Highest point a Lifelet of this stage can work from the floor, in metres.
static func reach_top(stage: String) -> float:
	return float(REACH_TOP.get(stage, 1.5))

## How this Lifelet works at `need_top` metres above the floor: {"aid": "" (from the
## floor), "stool", "pole" or "refused", "top": the highest contact it will make}. An
## elder or an expectant Lifelet never climbs a stool; a child cannot use one. Work that
## cannot be done in full is done as high as can be reached, so long as that is `min_top`.
## `aids` is the most help the chore allows: "", "stool" or "pole" (stool and pole).
static func reach(stage: String, pregnant: bool, need_top: float, min_top: float, aids: String) -> Dictionary:
	var comfortable: float = reach_top(stage) - COMFORT
	if need_top <= comfortable: return {"aid": "", "top": need_top}
	var stool_ok: bool = aids in ["stool", "pole"] and stage in ["teen", "young_adult", "adult"] and not pregnant
	if stool_ok and need_top <= comfortable + STOOL_HEIGHT + .0001: return {"aid": "stool", "top": need_top}
	if aids == "pole" and stage != "child": return {"aid": "pole", "top": need_top}
	var best: float = comfortable + (STOOL_HEIGHT if stool_ok else 0.0)
	if best >= min_top: return {"aid": "stool" if stool_ok else "", "top": minf(best, need_top)}
	return {"aid": "refused", "top": best}

## Station key grammar: lower-case words joined by colons, digits, dots, dashes.
static func key_valid(key: Variant) -> bool:
	if not key is String: return false
	var text: String = key
	if text.length() < 3 or text.length() > 64: return false
	for index: int in text.length():
		var code: int = text.unicode_at(index)
		var ok: bool = (code >= 97 and code <= 122) or (code >= 48 and code <= 57) or code in [58, 46, 45, 95]
		if not ok: return false
	return true

static func entry_valid(entry: Variant) -> bool:
	if not entry is String: return false
	var text: String = entry
	var at: int = text.find("@")
	if at < 1 or at > 40 or text.length() > 120: return false
	if text.substr(0, at) not in PLAN_IDS: return false
	for index: int in range(at + 1, text.length()):
		var code: int = text.unicode_at(index)
		var ok: bool = (code >= 97 and code <= 122) or (code >= 65 and code <= 90) or (code >= 48 and code <= 57) or code in [58, 46, 45, 95]
		if not ok: return false
	return text.length() > at + 1

## Validation of the `chore` record a queued chore carries through a save.
static func save_error(action: Dictionary) -> String:
	var id: String = str(action.get("id", ""))
	if not action.has("chore"): return ""
	if id not in PLAN_IDS: return "Save contains cleaning data on an unrelated action."
	var record: Variant = action.chore
	if not record is Dictionary: return "Save contains an invalid cleaning record."
	if not (record.get("v") is int or record.get("v") is float) or int(record.v) != 1: return "Save contains an unknown cleaning record version."
	if str(record.get("mode", "")) not in MODES: return "Save contains an invalid cleaning mode."
	var plan: Variant = record.get("plan", [])
	if not plan is Array or plan.size() > MAX_PLAN: return "Save contains an invalid cleaning plan."
	for entry: Variant in plan:
		if not entry_valid(entry): return "Save contains an invalid cleaning task."
	for key: String in ["index", "total"]:
		var value: Variant = record.get(key, 0)
		if not (value is int or value is float) or not is_finite(float(value)) or float(value) != floorf(float(value)) or float(value) < 0.0 or float(value) > 400.0: return "Save contains an invalid cleaning count."
	if int(record.get("index", 0)) > int(record.get("total", 0)): return "Save contains an inconsistent cleaning count."
	if not record.get("label", "") is String or str(record.get("label", "")).length() > 90: return "Save contains an invalid cleaning label."
	for key: String in ["key", "item", "face"]:
		if not record.get(key, "") is String or str(record.get(key, "")).length() > 80: return "Save contains an invalid cleaning target."
	if not record.get("aid", "") is String or str(record.get("aid", "")) not in ["", "stool", "pole"]: return "Save contains an invalid reach aid."
	var changes_value: Variant = record.get("changes", {})
	if not changes_value is Dictionary: return "Save contains invalid cleaning effects."
	for need: Variant in changes_value:
		var amount: Variant = changes_value[need]
		if str(need) not in NEED_NAMES or not (amount is float or amount is int) or not is_finite(float(amount)) or absf(float(amount)) > 100.0: return "Save contains invalid cleaning effects."
	var duration: Variant = action.get("duration", 8.0)
	if not (duration is float or duration is int) or not is_finite(float(duration)) or float(duration) < 1.0 or float(duration) > 60.0: return "Save contains an invalid cleaning duration."
	return ""

## Rebuild a queued chore's own label, effects and chain from its saved copy.
static func restore_action(action: Dictionary, stored: Dictionary) -> void:
	if not stored.has("chore") or not stored.chore is Dictionary: return
	var record: Dictionary = (stored.chore as Dictionary).duplicate(true)
	record["index"] = int(record.get("index", 0)); record["total"] = int(record.get("total", 0))
	action["chore"] = record
	if not str(record.get("label", "")).is_empty(): action["label"] = str(record.label)
	var effects: Dictionary = record.get("changes", {})
	var restored: Dictionary = {}
	for need: Variant in effects: restored[str(need)] = float(effects[need])
	if not restored.is_empty() or str(action.id) in IDS: action["changes"] = restored
