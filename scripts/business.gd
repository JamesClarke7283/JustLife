extends RefCounted
class_name LifeBusiness
## Buying and staffing a business: what a Lifelet who has earned a great deal of
## Lifeons does with it next.
##
## A career pays a daily wage and ends there. A business is bought once for a
## price the brief fixes, and then it pays every day — more, the more of it is
## staffed. That is the whole shape of this file: a price to take a business on,
## the trade and level a player must be shown before they commit, a fee to take
## an employee on, and the takings that follow from how many of the staff slots
## are actually filled.
##
## **The owner works it too.** Takings are stated for the whole roster and shared
## evenly between the owner's own shift and each employee's, so an unstaffed
## business still earns — badly — and every hire lifts the day by the same step.
## That keeps the arithmetic one fact (the takings, the roster size) rather than
## a case for every staffing level that could drift apart from it.
##
## Pure static policy — no Nodes, no clock, no wallet. The household owns the
## bought record; this file owns the prices, the requirements and the sums.

## The level in a business's own trade a Lifelet must stand at before it may be
## taken on at all, whatever the trade. The brief names nine. A venture whose own
## trade bar is lower is still held to this flat one, which is why a refusal can
## come from either the trade's own number or this one — and why the trade's
## number is checked first, so a player hears the harder bar when it is the
## specific one.
const MIN_LEVEL: int = 9

## The brief's two price points: a modest business is ℒ100,000 and a substantial
## one ℒ200,000. Both are written into the table as they stand rather than
## derived from a formula, so a price the brief fixed cannot drift.
const START_COST: int = 100000
const UPGRADE_COST: int = 200000

## A bought business is a money record as well as an id, and a save is external
## input, so the totals it carries need a sane ceiling to be checked against.
const MONEY_LIMIT: int = 100000000

## The version of the owned-business record, so a save from a later build can be
## refused instead of misread.
const VERSION: int = 1

## How many days of one pair of hands' takings it costs to take an employee on.
## Stated against the takings rather than as a flat fee, so staffing a bigger
## business costs more; and because the fee is a multiple of the same share the
## employee adds each day, a hire pays for itself in HIRE_FEE_DAYS days whatever
## the business is.
const HIRE_FEE_DAYS: int = 6

## Every business a Lifelet may buy.
##
## `label` is what the player reads, `skill` names the trade it is plied with and
## `level` the rung of that trade it demands, so the requirement can be shown
## before the money is committed. `cost` is the purchase price, `staff` how many
## employees it has room for, and `income` the day's takings once the owner and
## every employee are on shift.
##
## Authored from the modest ventures a household meets first to the substantial
## ones it grows into, which is also the order `ids()` hands to a picker.
const BUSINESSES: Dictionary = {
	# -------------------------------------------------------- modest ventures
	# The tier a household reaches with its first ℒ100,000. Each is a trade the
	# Lifelet can already be at the top of, which is what makes the money the last
	# requirement rather than the first.
	"cafe": {
		"label": "Café", "skill": "charisma", "level": 9, "cost": START_COST, "staff": 3, "income": 1200,
	},
	"salon": {
		"label": "Hair salon", "skill": "charisma", "level": 9, "cost": START_COST, "staff": 3, "income": 1150,
	},
	"bakery": {
		"label": "Bakery", "skill": "cooking", "level": 9, "cost": START_COST, "staff": 2, "income": 1050,
	},
	## A garden centre is a smallholding with a till: it asks less of the trade than
	## the brief's flat bar, so MIN_LEVEL is what actually holds a player back here.
	"garden_centre": {
		"label": "Garden centre", "skill": "gardening", "level": 8, "cost": START_COST, "staff": 3, "income": 1250,
	},
	"nursery": {
		"label": "Nursery", "skill": "parenting", "level": 9, "cost": START_COST, "staff": 4, "income": 1300,
	},

	# ---------------------------------------------------- substantial ventures
	# The tier the brief prices at ℒ200,000. Each is the top of its trade: a
	# Lifelet buys one after a long career in the work it runs, and it takes far
	# more staff, which is where the daily takings come from.
	"restaurant": {
		"label": "Restaurant", "skill": "cooking", "level": 10, "cost": UPGRADE_COST, "staff": 6, "income": 3200,
	},
	"gym": {
		"label": "Gym", "skill": "fitness", "level": 10, "cost": UPGRADE_COST, "staff": 4, "income": 2600,
	},
	"studio": {
		"label": "Recording studio", "skill": "music", "level": 10, "cost": UPGRADE_COST, "staff": 3, "income": 2400,
	},
	"software_house": {
		"label": "Software house", "skill": "logic", "level": 10, "cost": UPGRADE_COST, "staff": 4, "income": 3000,
	},
	"design_studio": {
		"label": "Design studio", "skill": "creativity", "level": 10, "cost": UPGRADE_COST, "staff": 3, "income": 2600,
	},
}


## Every business a player could be shown, in the order a picker should offer
## them: the modest ventures first, then the substantial ones. Dictionary order
## is insertion order in Godot, so a single pass is already stable across runs
## and needs no sort.
static func ids() -> Array[String]:
	var out: Array[String] = []
	for id: String in BUSINESSES: out.append(id)
	return out


static func has(id: String) -> bool:
	return BUSINESSES.has(id)


## One business's row, or an empty dictionary for an id this file does not know.
static func info(id: String) -> Dictionary:
	return BUSINESSES.get(id, {})


## Why this Lifelet may not buy this business, as the reason a player reads.
## Empty means the door is open. The picker, the price tag and the buying all
## read this one answer, so a greyed-out button and a refused purchase never
## disagree.
##
## `skills` is the Lifelet's own skill table and `funds` the household purse. The
## checks run in the order a player would meet them: the trade's own bar first
## (the specific number), then the brief's flat bar, then the money — so the
## reason names the requirement actually standing in the way, with its numbers.
static func purchase_error(id: String, stage: String, skills: Dictionary, funds: int) -> String:
	if not has(id): return "That business is not offered here."
	if stage != "adult": return "Business ownership becomes available in young adulthood."
	var data: Dictionary = info(id)
	var skill_name: String = str(data.get("skill", ""))
	var required: int = int(data.get("level", 0))
	var have: int = 1
	if not skill_name.is_empty():
		var row: Variant = skills.get(skill_name, {})
		have = int((row as Dictionary).get("level", 1)) if row is Dictionary else 1
		if required > 0 and have < required:
			return "Requires %s level %d. This Lifelet is at %s level %d." % [
				skill_name.capitalize(), required, skill_name.capitalize(), have]
		if have < MIN_LEVEL:
			return "Running a business demands %s level %d. This Lifelet is at %s level %d." % [
				skill_name.capitalize(), MIN_LEVEL, skill_name.capitalize(), have]
	var cost: int = int(data.get("cost", 0))
	if funds < cost: return "That business costs ℒ%d and the household needs ℒ%d more." % [cost, cost - funds]
	return ""


## The bar a Lifelet must clear to take this business on: the trade's own level,
## or the brief's flat bar when that is higher. Stated once so the number the
## player reads is the number `purchase_error` enforces.
static func _required_level(id: String) -> int:
	return maxi(MIN_LEVEL, int(info(id).get("level", 0)))


## What this business asks for, as player-readable text for the picker: the
## trade and its level, and the price. The label and the takings sit beside it in
## the row, so this line carries only what stands between the player and buying.
static func requirement_text(id: String) -> String:
	var data: Dictionary = info(id)
	if data.is_empty(): return "That business is not offered here."
	var parts: Array[String] = []
	var skill_name: String = str(data.get("skill", ""))
	if not skill_name.is_empty():
		parts.append("%s level %d" % [skill_name.capitalize(), _required_level(id)])
	parts.append("ℒ%d" % int(data.get("cost", 0)))
	return "Requires " + ", ".join(PackedStringArray(parts))


## What one pair of hands — the owner's or an employee's — adds to the takings in
## a day. The stated takings are shared evenly across the whole roster, so this
## is the one number both the pay and the hiring fee are built from.
static func _per_head(id: String) -> int:
	var data: Dictionary = info(id)
	if data.is_empty(): return 0
	var slots: int = maxi(0, int(data.get("staff", 0)))
	return roundi(float(int(data.get("income", 0))) / float(slots + 1))


## What it costs to take one employee on: the days of takings their shift adds.
static func hire_cost(id: String) -> int:
	return roundi(float(_per_head(id)) * float(HIRE_FEE_DAYS))


## Why this employee may not be taken on, or "" when they may. `staff_names` is
## the roster the business already has, so the refusal that matters is the full
## one: every slot has somebody in it and there is no more room.
static func hire_error(id: String, staff_names: Array, funds: int) -> String:
	if not has(id): return "That business is not offered here."
	var data: Dictionary = info(id)
	var slots: int = maxi(0, int(data.get("staff", 0)))
	if staff_names.size() >= slots:
		return "%s already has all %d employees it has room for." % [
			str(data.get("label", id.capitalize())), slots]
	var fee: int = hire_cost(id)
	if funds < fee: return "Hiring an employee costs ℒ%d and the household needs ℒ%d more." % [fee, fee - funds]
	return ""


## What one owned business pays a day. Takings are the whole roster's, so this is
## one share for the owner (who always works) plus one for every employee
## actually on the books, and the roster is capped at the slots the business has.
##
## An owned business is stored as {"version", "id", "staff": [names],
## "invested", "earned"} — the roster and the two money totals, which is
## everything a picker, a wage notice and a save need to read back.
static func daily_income(owned: Dictionary) -> int:
	var id: String = str(owned.get("id", ""))
	if not has(id): return 0
	var roster: Variant = owned.get("staff", [])
	var working: int = mini(roster.size(), int(info(id).get("staff", 0))) if roster is Array else 0
	return _per_head(id) * (1 + working)


## Validate one owned-business record as a save restores it. A household that owns
## nothing holds no record at all, so null and an empty dictionary are both valid
## — the way an empty criminal record means "never caught" — and anything else
## must agree with the table it names and with its own totals.
static func validate_owned(value: Variant) -> String:
	if value == null: return ""
	if not value is Dictionary: return "Save contains an invalid business holding."
	var owned: Dictionary = value
	if owned.is_empty(): return ""
	if int(owned.get("version", 0)) != VERSION: return "The saved business holding uses an unsupported version."
	var id: String = str(owned.get("id", ""))
	if not has(id): return "Save contains an unknown business."
	var slots: int = int(info(id).get("staff", 0))
	var roster: Variant = owned.get("staff", [])
	if not roster is Array: return "Save contains an invalid employee roster."
	if roster.size() > slots: return "Save contains more employees than the business has room for."
	var hired: Array[String] = []
	for name: Variant in roster:
		if not name is String or str(name).strip_edges().is_empty():
			return "Save contains an invalid employee name."
		if hired.has(str(name)): return "Save contains an employee hired twice."
		hired.append(str(name))
	if not _integer(owned.get("invested", 0), int(info(id).get("cost", 0)), MONEY_LIMIT):
		return "Save contains a business bought for less than its price."
	if not _integer(owned.get("earned", 0), 0, MONEY_LIMIT):
		return "Save contains an invalid business earnings total."
	return ""


static func _integer(value: Variant, low: int, high: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floorf(float(value)) and float(value) >= low and float(value) <= high
