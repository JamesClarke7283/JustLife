extends RefCounted
class_name LifePartyPlan
## Hosting a party: the pure rules.
##
## A party is a small gathering of up to four friends (the neighbors) that runs for
## up to five game hours. The household keeps the record and writes it to the save;
## this module names the limits, builds and checks that record, and answers the
## small questions the planner card and the guests' own choices ask. No nodes, no
## signals, no global randomness. `scripts/party_flow.gd` is the part the player
## sees and the part that walks people about.
##
## The saved record (`household.party`, with `household.party_serial` counting
## parties) is `{}` when no party is on, otherwise
##   version, serial, phase ("inviting" until the first guest is inside, then
##   "active", then "ending"), host_id, celebrant_id ("" for no one in particular),
##   created_at, started_at, ends_at (absolute game minutes, the clock of
##   LifeHomeVisit), hours, music, and guests: a list of
##   {id, potluck (a recipe or ""), status ("preparing", "walking", "inside" or
##   "left"), depart_at (when the friend sets off), batch (the meal id of the dish
##   they set out, or ""), brought (the dish is dealt with, set down or given up),
##   came (the friend has been inside at least once)}.

const VERSION: int = 1
const MIN_HOURS: int = 1
const MAX_HOURS: int = 5
const MAX_GUESTS: int = 4
## A party never runs longer than this many game minutes. It matches the longest
## stay a saved party guest may have (LifeHomeVisit.PARTY_MAX_MINUTES).
const MAX_MINUTES: float = 300.0
## Friends set off a few minutes apart, so they do not all reach the door at once.
const ARRIVAL_STAGGER: float = 6.0
## A friend who is bringing a dish spends this long making it before setting off.
const POTLUCK_PREP: float = 20.0
## Nobody throws a party in the small hours or late at night.
const WINDOW_OPEN: float = 420.0
const WINDOW_CLOSE: float = 1320.0
## The cake waits for the guests this long, then the family has it without them.
const RITUAL_WAIT: float = 60.0
## When the host ends the party early, guests say goodbye this far apart.
const GOODBYE_GAP: float = 2.0
## A friend who cannot get in is tried again after this long, up to this many times.
const INVITE_RETRY: float = 5.0
const INVITE_TRIES: int = 6
## What a party earns each friend who came: friendship with the host and the
## person whose birthday it is, and a little more when their dish was eaten.
const FRIENDSHIP_GAIN: float = 6.0
const POTLUCK_GAIN: float = 3.0
## A household with decorations gives its guests a lift when they arrive.
const FUN_FESTIVE: int = 5
const FUN_VERY_FESTIVE: int = 8
const VERY_FESTIVE: int = 3

const PHASES: Array[String] = ["inviting", "active", "ending"]
const STATUSES: Array[String] = ["preparing", "walking", "inside", "left"]

## The guest actions only a party uses. Like the birthday song, they take only a
## place to stand: the table and the stereo stay free for everyone else.
const BRING: String = "bring_dish"
const DANCE: String = "dance"
const IDS: Array[String] = [BRING, DANCE]

## The dish each friend is known for. Every one is an ordinary recipe.
const POTLUCK: Dictionary = {"maya": "garden_salad", "leo": "pancake_stack", "priya": "mushroom_soup", "tom": "herb_pasta"}

## The words the household hears, kept here so every place says the same thing.
const MOODLET_FESTIVE: String = "Festive home"
const MOODLET_GREAT: String = "Great party"


## Whether this guest action belongs to the party.
static func owns(action: Dictionary) -> bool:
	return str(action.get("id", "")) in IDS

## A whole number of hours between the least and the most a party can run.
static func clamp_hours(hours: Variant) -> int:
	if not (hours is int or hours is float) or not is_finite(float(hours)): return MAX_HOURS
	return clampi(int(hours), MIN_HOURS, MAX_HOURS)

## The recipe this friend brings, or "" for a friend with no dish.
static func potluck_recipe(guest_id: String) -> String:
	var recipe: String = str(POTLUCK.get(guest_id, ""))
	return recipe if LifeMeals.RECIPES.has(recipe) else ""

## The dish's name for a label: "garden fresh salad".
static func potluck_label(guest_id: String) -> String:
	var recipe: String = potluck_recipe(guest_id)
	return str(LifeMeals.RECIPES[recipe].label).to_lower() if not recipe.is_empty() else ""

## Whether a time of day (minutes after midnight) is a time to throw a party.
static func window_open(minutes: float) -> bool:
	return minutes >= WINDOW_OPEN and minutes <= WINDOW_CLOSE

## Why this neighbor cannot be asked, or "" when they can. `facts` is a plain
## description made by the caller: moved_in, visiting (already a guest or at the
## door), friendly (any household member has 20 friendship with them).
static func guest_error(id: String, facts: Dictionary) -> String:
	if not LifeResidentCatalogue.PEOPLE.has(id): return "That is not one of your neighbors."
	if bool(facts.get("moved_in", false)): return "They live with you now."
	if bool(facts.get("visiting", false)): return "They are already visiting."
	if not bool(facts.get("friendly", false)): return "Reach 20 friendship with this neighbor before inviting them over."
	return ""

## Why a party cannot be sent with these choices, or "" when it can. `facts`:
## minutes (time of day), party_on, hours, guests (the invited ids), errors (a map
## of id to that neighbor's own reason, or ""), at_home (at home in Live mode).
static func send_error(facts: Dictionary) -> String:
	if bool(facts.get("party_on", false)): return "A party is already on."
	if not bool(facts.get("at_home", true)): return "Host a party while you are at home in Live mode."
	if not window_open(float(facts.get("minutes", WINDOW_OPEN))): return "It is too late for a party tonight." if float(facts.get("minutes", WINDOW_OPEN)) > WINDOW_CLOSE else "It is too early for a party."
	var guests: Array = facts.get("guests", [])
	if guests.is_empty(): return "Invite at least one friend."
	if guests.size() > MAX_GUESTS: return "A party has room for four friends."
	var errors: Dictionary = facts.get("errors", {})
	for id: Variant in guests:
		var why: String = str(errors.get(str(id), ""))
		if not why.is_empty(): return "%s: %s" % [str(LifeResidentCatalogue.PEOPLE.get(str(id), {}).get("name", id)).split(" ")[0], why]
	return ""

## A new party record. `invited` lists {id, potluck: bool} in the order the friends
## are asked; `now` is the absolute game minute. Each friend sets off a little after
## the one before, and a friend bringing a dish first spends time making it.
static func build(serial: int, host_id: String, celebrant_id: String, now: float, hours: int, music: bool, invited: Array) -> Dictionary:
	var length: int = clamp_hours(hours)
	var guests: Array = []
	for index: int in invited.size():
		var entry: Dictionary = invited[index]
		var id: String = str(entry.get("id", ""))
		var recipe: String = potluck_recipe(id) if bool(entry.get("potluck", false)) else ""
		guests.append({"id": id, "potluck": recipe, "status": "preparing", "depart_at": now + ARRIVAL_STAGGER * float(index) + (POTLUCK_PREP if not recipe.is_empty() else 0.0), "batch": "", "brought": recipe.is_empty(), "came": false})
	return {"version": VERSION, "serial": serial, "phase": "inviting", "host_id": host_id, "celebrant_id": celebrant_id, "created_at": now, "started_at": now, "ends_at": now + float(length) * 60.0, "hours": length, "music": music, "guests": guests}

## The entry for one guest in a record, or {}.
static func guest_entry(party: Dictionary, id: String) -> Dictionary:
	for entry: Dictionary in party.get("guests", []):
		if str(entry.id) == id: return entry
	return {}

## How many friends are in each state, and how many came at all.
static func counts(party: Dictionary) -> Dictionary:
	var result: Dictionary = {"preparing": 0, "walking": 0, "inside": 0, "left": 0, "total": 0}
	for entry: Dictionary in party.get("guests", []):
		result[str(entry.status)] = int(result[str(entry.status)]) + 1
		result.total = int(result.total) + 1
	return result

## Whether friends are still to come or here, so the party is not over yet.
static func guests_remaining(party: Dictionary) -> bool:
	var found: Dictionary = counts(party)
	return int(found.preparing) + int(found.walking) + int(found.inside) > 0

## Whether the family's cake is held back for the guests: the party is for this
## person, some friends are still on their way, and the wait has not run out.
static func ritual_waits(party: Dictionary, member_id: String, now: float) -> bool:
	if party.is_empty() or str(party.get("celebrant_id", "")) != member_id: return false
	if str(party.get("phase", "")) == "ending": return false
	if now >= float(party.get("started_at", now)) + RITUAL_WAIT: return false
	var found: Dictionary = counts(party)
	return int(found.preparing) + int(found.walking) > 0 or int(found.inside) == 0

## How much fun a guest gains on arriving at a home with this many festive touches.
static func decor_fun(score: int) -> int:
	if score <= 0: return 0
	return FUN_VERY_FESTIVE if score >= VERY_FESTIVE else FUN_FESTIVE

## The friendship a guest earns by the end of the party.
static func friendship_gain(dish_eaten: bool) -> float:
	return FRIENDSHIP_GAIN + (POTLUCK_GAIN if dish_eaten else 0.0)

## The clock time of an absolute game minute, "19:00".
static func clock_text(absolute: float) -> String:
	var minute: int = int(fposmod(absolute, 1440.0))
	return "%02d:%02d" % [minute / 60, minute % 60]

## Whether a number from a save is a finite number in a range (and a whole one when asked).
static func _number(value: Variant, minimum: float, maximum: float, whole: bool = false) -> bool:
	if not (value is int or value is float) or not is_finite(float(value)): return false
	if float(value) < minimum or float(value) > maximum: return false
	return not whole or float(value) == floorf(float(value))


## Whether a saved party can be believed. `data` is the household's save: its
## members, its day and minutes, the party counter, the meal ledger and the saved
## guests. Nothing is adopted until this says "".
static func validate(value: Variant, data: Dictionary) -> String:
	var counter: int = 0
	if data.has("party_serial"):
		if not _number(data.get("party_serial"), 0, 1000000000, true): return "Save contains an invalid party counter."
		counter = int(data.party_serial)
	# A birthday that names a party must name one that was held.
	var celebrations: Variant = data.get("celebrations", null)
	if celebrations is Dictionary and celebrations.get("pending") is Array:
		for entry: Variant in celebrations.pending:
			if entry is Dictionary and int(entry.get("party_serial", 0)) > counter: return "Save contains a birthday for a party that was never held."
	if value == null: return ""
	if not value is Dictionary: return "Save contains an invalid party record."
	var party: Dictionary = value
	if party.is_empty(): return ""
	var now: float = (float(data.get("day", 1)) - 1.0) * 1440.0 + float(data.get("minutes", 0.0))
	if not _number(party.get("version"), VERSION, VERSION, true): return "Save contains an unknown party version."
	if not _number(party.get("serial"), 1, float(maxi(1, counter)), true) or counter < 1: return "Save contains an invalid party number."
	if str(party.get("phase", "")) not in PHASES: return "Save contains an invalid party phase."
	var member_ids: Array = []
	for member: Variant in data.get("members", []):
		if member is Dictionary and member.get("id") is String: member_ids.append(str(member.id))
	if not party.get("host_id") is String or not member_ids.has(str(party.host_id)): return "Save contains a party with no host in the household."
	if not party.get("celebrant_id") is String or (not str(party.celebrant_id).is_empty() and not member_ids.has(str(party.celebrant_id))): return "Save contains a party for someone outside the household."
	if not _number(party.get("created_at"), 0.0, now) or not _number(party.get("started_at"), float(party.created_at), now) or not _number(party.get("ends_at"), 0.0, 1e12): return "Save contains an invalid party time."
	var length: float = float(party.ends_at) - float(party.started_at)
	if length <= 0.0 or length > MAX_MINUTES: return "Save contains a party that runs too long."
	if not _number(party.get("hours"), MIN_HOURS, MAX_HOURS, true) or not party.get("music") is bool: return "Save contains invalid party settings."
	if not party.get("guests") is Array or party.guests.is_empty() or party.guests.size() > MAX_GUESTS: return "Save contains an invalid party guest list."
	var moved_in: Variant = data.get("resident_members", {})
	var seen: Array = []
	var visits: Dictionary = {}
	for found: Dictionary in LifeHomeVisit.saved_party_visits(data):
		if found.value is Dictionary and found.value.get("visit") is Dictionary and not found.value.visit.is_empty(): visits[str(found.value.visit.get("guest", ""))] = true
	var batches: Dictionary = {}
	var meals: Variant = data.get("meals", {})
	if meals is Dictionary and meals.get("batches") is Array:
		for batch: Variant in meals.batches:
			if batch is Dictionary: batches[str(batch.get("id", ""))] = batch
	var inside: bool = false
	for entry: Variant in party.guests:
		if not entry is Dictionary: return "Save contains an invalid party guest."
		var id: String = str(entry.get("id", "")) if entry.get("id") is String else ""
		if not LifeResidentCatalogue.PEOPLE.has(id): return "Save contains a party guest who is not a neighbor."
		if seen.has(id): return "Save contains the same party guest twice."
		seen.append(id)
		if moved_in is Dictionary and moved_in.has(id): return "Save contains a party guest who lives in the household."
		if not entry.get("potluck") is String or (not str(entry.potluck).is_empty() and not LifeMeals.RECIPES.has(str(entry.potluck))): return "Save contains an unknown party dish."
		if str(entry.get("status", "")) not in STATUSES: return "Save contains an invalid party guest state."
		if not _number(entry.get("depart_at"), float(party.created_at), float(party.ends_at) + 1440.0): return "Save contains an invalid party arrival time."
		if not entry.get("batch") is String or not entry.get("brought") is bool or not entry.get("came") is bool: return "Save contains an invalid party dish record."
		var status: String = str(entry.status)
		if status == "inside": inside = true
		if (status == "inside" and not bool(entry.came)) or (status in ["preparing", "walking"] and bool(entry.came)): return "Save has a party guest whose arrival does not add up."
		if status in ["preparing", "left"] and visits.has(id): return "Save has a party guest who is not meant to be visiting."
		if not str(entry.batch).is_empty():
			var batch: Variant = batches.get(str(entry.batch))
			if not batch is Dictionary or str(batch.get("brought_by", "")) != id or not bool(entry.brought): return "Save names a party dish that nobody brought."
		if str(entry.potluck).is_empty() and not str(entry.batch).is_empty(): return "Save names a party dish for a guest with none."
	if str(party.phase) == "inviting" and inside: return "Save has a party guest inside before the party began."
	# Every party guest in the save belongs to this party.
	for id: Variant in visits:
		if not seen.has(str(id)): return "Save has a party guest who was not invited."
	return ""

## The saved record with its numbers made whole again (a save read back from JSON
## holds every number as a float). Only call after `validate` has passed.
static func adopt(value: Variant) -> Dictionary:
	if not value is Dictionary or value.is_empty(): return {}
	var party: Dictionary = {"version": VERSION, "serial": int(value.serial), "phase": str(value.phase), "host_id": str(value.host_id), "celebrant_id": str(value.celebrant_id), "created_at": float(value.created_at), "started_at": float(value.started_at), "ends_at": float(value.ends_at), "hours": int(value.hours), "music": bool(value.music), "guests": []}
	for entry: Dictionary in value.guests:
		party.guests.append({"id": str(entry.id), "potluck": str(entry.potluck), "status": str(entry.status), "depart_at": float(entry.depart_at), "batch": str(entry.batch), "brought": bool(entry.brought), "came": bool(entry.came)})
	return party
