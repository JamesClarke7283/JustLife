extends Node
class_name LifeHouseholdFlow
## Household chores, skill books, instruments and shared listening.
##
## This service owns the small stateful extras that need a real world and a real
## household to mean anything:
##   * the rubbish bin's fill, raised by cooking, eating and clearing tables;
##   * the skill books a Lifelet buys and shelves, each teaching one skill;
##   * instrument practice (guitar, violin), which builds Music;
##   * clearing used plates and finished dishes off a table surface;
##   * watching television with a welcomed guest.
##
## It never mutates needs, funds or the clock itself: every action carries its
## own changes and the ordinary controller commits money. Its data round-trips
## through `get_state`/`restore`, so a save always resumes it.

const SERVICE_ACTIONS: Array[String] = ["buy_book", "study_book", "empty_bin", "clear_table", "practice_instrument", "watch_together"]
## One book per skill in `LifeSim.SKILL_NAMES`, so every subject has a shelf
## route. Prices and XP follow the difficulty of the skill: the original four
## keep their tuned values, and the four added later are priced to match.
const BOOK_SKILLS: Dictionary = {
	"cooking":{"label":"A Well-Fed Home","price":90,"xp":52.0},
	"fitness":{"label":"Move With Purpose","price":80,"xp":48.0},
	"gardening":{"label":"Soil and Season","price":85,"xp":50.0},
	"music":{"label":"Notes for Beginners","price":110,"xp":58.0},
	"creativity":{"label":"Sparks of Invention","price":100,"xp":54.0},
	"charisma":{"label":"The Room Listens","price":95,"xp":50.0},
	"logic":{"label":"Reasons in Order","price":105,"xp":56.0},
	"parenting":{"label":"A Steady Hand","price":115,"xp":52.0},
}
## A book can carry a skill to level 9. The tenth level is reserved for the
## computer, so the screen is the only way to become a true master of a subject.
const BOOK_MAX_LEVEL: int = 9
const MAX_BOOKS: int = 6
const BIN_CAPACITY: int = 4
## Furniture put away into the household's storage unit. A stored furnishing is
## a detached layout record (kind, x, z, rotation, level) held outside the live
## world, so it costs nothing to keep and can be withdrawn or sold later.
const MAX_STORAGE: int = 30

var app: Node
var books: Array = []                       # [{"id":"book_1","skill":"cooking","shelf":"item_6"}]
var fill: Dictionary = {}                   # bin item id -> whole units of rubbish
var storage: Array = []                     # [{"id":"placed_1","kind":"bed","x":..,"z":..,"rotation":..,"level":..}]
var serial: int = 0
var _full_notice_day: int = -1


func _init(owner_app: Node = null) -> void:
	app = owner_app


# ---------------------------------------------------------------- ownership

## Whether the household owns a placed bicycle helmet. Riding is refused without
## one, so this is the rule rather than a suggestion.
func owns_helmet() -> bool:
	return not helmet_ids().is_empty()

## The identities of every placed helmet, so one is enough however many are
## bought and a sold helmet no longer permits a ride.
func helmet_ids() -> Array[String]:
	var out: Array[String] = []
	if app == null or not is_instance_valid(app.world): return out
	for item: Dictionary in app.world.items:
		if str(item.get("kind", "")) == "helmet": out.append(str(item.id))
	return out


# ---------------------------------------------------------------- persistence

func get_state() -> Dictionary:
	return {"version":1, "serial":serial, "books":books.duplicate(true), "fill":fill.duplicate(true), "storage":storage.duplicate(true), "truck":_truck_state()}


## The weekly food truck's own small record rides here rather than in a system
## of its own: it is one schedule stamp and one order counter, and the extras
## record is already the household's additive, optional sidecar. A build
## without a truck (an older save) simply carries an empty record.
func _truck_state() -> Dictionary:
	if not is_instance_valid(app) or not is_instance_valid(app.food_truck):
		return {}
	return app.food_truck.get_state()


func restore(data: Variant) -> void:
	books = []
	fill = {}
	storage = []
	serial = 0
	if not data is Dictionary:
		return
	serial = int(data.get("serial", 0))
	var raw_fill: Variant = data.get("fill", {})
	if raw_fill is Dictionary:
		for key: Variant in raw_fill:
			fill[str(key)] = clampi(int(raw_fill[key]), 0, BIN_CAPACITY)
	for entry: Variant in data.get("books", []):
		if not entry is Dictionary or not BOOK_SKILLS.has(str(entry.get("skill", ""))):
			continue
		books.append({"id":str(entry.get("id", "")), "skill":str(entry.skill), "shelf":str(entry.get("shelf", ""))})
	for entry: Variant in data.get("storage", []):
		if not entry is Dictionary or not _stored_record_valid(entry):
			continue
		storage.append(_stored_record(entry))
	if is_instance_valid(app) and is_instance_valid(app.food_truck):
		app.food_truck.restore(data.get("truck", null))


static func validate(data: Variant, layout: Array, day: int = 0) -> String:
	# Additive optional record: absent means the pre-book default, and every
	# stored reference must still name a real furnishing of the right kind.
	if data == null:
		return ""
	if not data is Dictionary:
		return "The saved household extras are invalid."
	if not LifeBuildingState.number(data.get("serial", 0), 0, 1000000000, true):
		return "The saved household extras have an invalid counter."
	var kinds: Dictionary = {}
	for entry: Variant in layout:
		if entry is Dictionary and str(entry.get("kind", "")) != "__construction":
			kinds[str(entry.get("id", ""))] = str(entry.get("kind", ""))
	var saved_fill: Variant = data.get("fill", {})
	if not saved_fill is Dictionary or saved_fill.size() > 64:
		return "The saved rubbish bins are invalid."
	for key: Variant in saved_fill:
		if not LifeBuildingState.number(saved_fill[key], 0, BIN_CAPACITY, true):
			return "A saved rubbish bin holds an impossible amount."
		if str(kinds.get(str(key), "")) != "rubbish_bin":
			return "Saved rubbish refers to a missing bin."
	var saved_books: Variant = data.get("books", [])
	if not saved_books is Array or saved_books.size() > MAX_BOOKS:
		return "The saved skill books are invalid."
	var seen: Dictionary = {}
	for entry: Variant in saved_books:
		if not entry is Dictionary or not BOOK_SKILLS.has(str(entry.get("skill", ""))):
			return "A saved skill book has an unknown subject."
		var id: String = str(entry.get("id", ""))
		if id.is_empty() or seen.has(id):
			return "A saved skill book has a duplicate identity."
		seen[id] = true
		if str(kinds.get(str(entry.get("shelf", "")), "")) != "bookshelf":
			return "A saved skill book refers to a missing shelf."
	var saved_storage: Variant = data.get("storage", [])
	if not saved_storage is Array or saved_storage.size() > MAX_STORAGE:
		return "The saved storage unit is invalid."
	var stored_ids: Dictionary = {}
	for entry: Variant in saved_storage:
		if not _stored_record_valid(entry):
			return "A saved stored furnishing is invalid."
		var stored_id: String = str(entry.get("id", ""))
		if stored_ids.has(stored_id):
			return "Two saved stored furnishings share an identity."
		stored_ids[stored_id] = true
	return LifeFoodTruck.validate(data.get("truck", null), day)

## A stored record is a detached layout entry: the same identity, kind and
## transform a placed furnishing carries, with no live node. It must name a real
## catalogue item at a supported level and stay inside the lot.
static func _stored_record_valid(entry: Variant) -> bool:
	if not entry is Dictionary:
		return false
	if not entry.get("id") is String or str(entry.get("id", "")).is_empty():
		return false
	if not LifeCatalog.ITEMS.has(str(entry.get("kind", ""))):
		return false
	if not LifeBuildingState.number(entry.get("level", 0), 0, 1, true):
		return false
	for axis: String in ["x", "z", "rotation"]:
		if not LifeBuildingState.number(entry.get(axis, 0), -100000, 100000):
			return false
	if entry.has("lit") and not entry.get("lit") is bool:
		return false
	if entry.has("paint") and not LifeCatalog._shade(str(entry.get("paint",""))):
		return false
	return true

static func _stored_record(entry: Dictionary) -> Dictionary:
	var record: Dictionary = {"id":str(entry.get("id", "")), "kind":str(entry.get("kind", "")), "x":float(entry.get("x", 0.0)), "z":float(entry.get("z", 0.0)), "rotation":float(entry.get("rotation", 0.0)), "level":int(entry.get("level", 0))}
	if entry.has("lit"):
		record["lit"] = bool(entry.lit)
	if entry.has("paint"):
		record["paint"] = str(entry.get("paint",""))
	return record


# ------------------------------------------------------------------- books

func books_on(shelf_id: String) -> Array:
	var result: Array = []
	for book: Dictionary in books:
		if str(book.shelf) == shelf_id:
			result.append(book)
	return result


func has_book() -> bool:
	return not books.is_empty()


func buy_book(shelf_id: String, skill: String) -> Dictionary:
	if not BOOK_SKILLS.has(skill):
		return {"ok":false, "error":"Choose a subject to study."}
	var item: Dictionary = _item(shelf_id)
	if item.is_empty() or str(item.kind) != "bookshelf":
		return {"ok":false, "error":"That bookshelf is no longer here."}
	if books_on(shelf_id).size() >= MAX_BOOKS:
		return {"ok":false, "error":"This shelf is full. Study a book before buying another."}
	serial += 1
	books.append({"id":"book_"+str(serial), "skill":skill, "shelf":shelf_id})
	refresh_props()
	return {"ok":true, "price":int(BOOK_SKILLS[skill].price), "label":str(BOOK_SKILLS[skill].label)}


func study_definition(base: Dictionary, skill: String) -> Dictionary:
	if not BOOK_SKILLS.has(skill):
		return {}
	var result: Dictionary = base.duplicate(true)
	result.merge({"label":"Study "+str(skill).capitalize(), "duration":60.0, "cost":0, "skill":skill,
		"xp":float(BOOK_SKILLS[skill].xp), "book_skill":skill,
		"description":"Read %s and practise its ideas. %s skill grows with every session." % [str(BOOK_SKILLS[skill].label), str(skill).capitalize()]}, true)
	return result


## The subject a shelf session would teach: the first book whose skill has not yet
## reached the book ceiling. Empty when every book on the shelf is finished, which
## is exactly the case the menu refuses.
func study_skill_for(sim: LifeSim, shelf_id: String) -> String:
	for book: Dictionary in books_on(shelf_id):
		var skill: String = str(book.skill)
		if not BOOK_SKILLS.has(skill):
			continue
		if int(sim.skills.get(skill,{"level":1}).level) < BOOK_MAX_LEVEL:
			return skill
	return ""


# ----------------------------------------------------------------- rubbish

func bin_is_full(bin_id: String) -> bool:
	if str(_item(bin_id).get("kind", "")) != "rubbish_bin":
		return false
	return int(fill.get(bin_id, 0)) >= BIN_CAPACITY


func add_rubbish(units: int = 1) -> void:
	# Cooking, eating and clearing tables all leave something behind. The bin
	# nearest the kitchen takes it, so the household's own bin fills first.
	var bin: Dictionary = app.world.closest_item("rubbish_bin", Vector3(0, 0, -4.4))
	if bin.is_empty():
		bin = app.world.closest_item("rubbish_bin", Vector3.ZERO)
	if bin.is_empty():
		return
	var id: String = str(bin.id)
	fill[id] = mini(BIN_CAPACITY, int(fill.get(id, 0)) + maxi(0, units))
	refresh_props()
	if not bin_is_full(id) or _full_notice_day == app.household.day:
		return
	_full_notice_day = app.household.day
	app.show_notice("The rubbish bin is full. Empty it out on the street.")


func empty_bin(bin_id: String) -> bool:
	if not bin_is_full(bin_id):
		return false
	fill[bin_id] = 0
	refresh_props()
	return true


# ---------------------------------------------------------------- storage

## File a placed furnishing away into the household's storage unit. The record
## leaves the live world (no node, no navigation cost) and waits in `storage`.
func store_furnishing(entry: Dictionary) -> Dictionary:
	if not _stored_record_valid(entry):
		return {"ok":false, "error":"That furnishing cannot be stored."}
	if storage.size() >= MAX_STORAGE:
		return {"ok":false, "error":"The storage unit is full (%d items). Take something out first." % MAX_STORAGE}
	storage.append(_stored_record(entry))
	return {"ok":true}

## Take a stored furnishing back out as a fresh layout record ready to place.
## The layout is not committed here — the caller validates the destination first.
func withdraw_furnishing(id: String) -> Dictionary:
	for index: int in range(storage.size()):
		if str(storage[index].id) != id:
			continue
		var record: Dictionary = storage[index].duplicate(true)
		storage.remove_at(index)
		return {"ok":true, "record":record}
	return {"ok":false, "error":"That furnishing is no longer in storage."}

## Sell a stored furnishing outright, paying its usual sale value back.
func sell_stored(id: String) -> Dictionary:
	for index: int in range(storage.size()):
		if str(storage[index].id) != id:
			continue
		var record: Dictionary = storage[index]
		var credit: int = int(LifeCatalog.ITEMS[str(record.kind)].price * .7)
		storage.remove_at(index)
		return {"ok":true, "credit":credit, "kind":str(record.kind)}
	return {"ok":false, "error":"That furnishing is no longer in storage."}


func storage_count() -> int:
	return storage.size()


func refresh_props() -> void:
	for item: Dictionary in app.world.items:
		var node: Node3D = item.node
		if str(item.kind) == "rubbish_bin":
			var bag: Node = node.find_child("BinBag", true, false)
			if bag != null:
				bag.visible = bin_is_full(str(item.id))
		elif str(item.kind) == "bookshelf":
			var on_shelf: Array = books_on(str(item.id))
			for index: int in range(MAX_BOOKS):
				var prop: Node = node.find_child("ShelfBook_%d" % index, true, false)
				if prop == null:
					continue
				prop.visible = index < on_shelf.size()
				if prop is Node3D and index < on_shelf.size():
					_theme_book(prop, str(on_shelf[index].skill))


func _theme_book(prop: Node, skill: String) -> void:
	var tint: Dictionary = {"cooking":"c97c66", "fitness":"417a71", "gardening":"48794b", "music":"6e5470"}
	var colour: String = str(tint.get(skill, "b6b29c"))
	for mesh: Node in prop.find_children("*", "MeshInstance3D", true, false):
		var geometry: MeshInstance3D = mesh as MeshInstance3D
		if geometry != null and geometry.has_meta("book_cover"):
			geometry.material_override = app.world.material(colour)


# -------------------------------------------------------------------- table

func dirty_on(host_id: String) -> Array:
	# Used plates and finished serving dishes left on one surface. A plate with
	# a live owner is still in use; a serving dish with servings left is food.
	var result: Array = []
	var meals: LifeMeals = app.household.meals
	for plate: Dictionary in meals.portions:
		if str(plate.venue) != app.current_venue or str(plate.host) != host_id:
			continue
		if str(plate.storage) not in ["table", "surface", "dirty"] or not str(plate.owner).is_empty():
			continue
		result.append(plate)
	for batch: Dictionary in meals.batches:
		if str(batch.venue) != app.current_venue or str(batch.host) != host_id or str(batch.storage) != "surface":
			continue
		if str(batch.owner).is_empty() and (int(batch.remaining) <= 0 or _now() >= float(batch.expires)):
			result.append(batch)
	return result


func table_has_dirty(host_id: String) -> bool:
	return not dirty_on(host_id).is_empty()


# ----------------------------------------------------------- availability

func action_availability(sim: LifeSim, id: String, target_id: String) -> String:
	var kind: String = str(_item(target_id).get("kind", ""))
	match id:
		"buy_book":
			if kind != "bookshelf":
				return "Choose a bookshelf to hold your books."
			if books_on(target_id).size() >= MAX_BOOKS:
				return "This shelf is full. Study a book before buying another."
		"study_book":
			if kind != "bookshelf":
				return "Choose a bookshelf with a skill book on it."
			if books_on(target_id).is_empty():
				return "Buy a skill book for this shelf first."
			# A book teaches up to level 9. Mastery at 10 belongs to the computer,
			# so the shelf tells the player where to go next instead of silently
			# capping their progress.
			if not study_skill_for(sim, target_id).is_empty():
				return ""
			return "Every skill book on this shelf is already at level %d. Mastery at level 10 needs the computer." % BOOK_MAX_LEVEL
		"empty_bin":
			if kind != "rubbish_bin":
				return "Choose the rubbish bin."
			if not bin_is_full(target_id):
				return "The bin is not full yet."
		"clear_table":
			if not table_has_dirty(target_id):
				return "There are no used plates or finished dishes here to clear."
			if app.world.closest_item("sink", Vector3.ZERO).is_empty():
				return "Place a sink to wash the plates at."
		"practice_instrument":
			if kind not in LifeCatalog.INSTRUMENTS:
				return "Choose a guitar or a violin."
	return ""


func _item(id: String) -> Dictionary:
	return app._find_item(id)


# ------------------------------------------------------------------- pets

## What a pet can be taught. The canonical list lives in LifePets, beside the
## save validator that reads it, so a stored trick is always one of these.
func next_trick(pet_id: String) -> String:
	var known: Array = tricks_for(pet_id)
	for trick: String in LifePets.TRICKS:
		if not known.has(trick):
			return trick
	return ""


## Every trick this pet has learned, newest last.
func tricks_for(pet_id: String) -> Array:
	var record: Dictionary = _pet_record(pet_id)
	var known: Variant = record.get("tricks", [])
	return known.duplicate() if known is Array else []


## One teaching session. Progress is counted per trick in `trick_progress`, and
## the trick joins `tricks` only when it is really learned, so a partial session
## is honest about what the animal can do. Both records ride the household save.
func teach_pet_trick(pet_id: String, teacher: String) -> Dictionary:
	var record: Dictionary = _pet_record(pet_id)
	if record.is_empty():
		return {"ok":false, "error":"That pet is not part of this household."}
	var trick: String = next_trick(pet_id)
	if trick.is_empty():
		return {"ok":false, "error":"%s already knows everything you know how to teach." % str(record.get("name","Your pet"))}
	var progress: Dictionary = record.get("trick_progress", {})
	progress[trick] = int(progress.get(trick, 0)) + 1
	record["trick_progress"] = progress
	if int(progress[trick]) >= LifePets.TRICK_SESSIONS:
		var known: Array = tricks_for(pet_id)
		known.append(trick)
		record["tricks"] = known
		progress.erase(trick)
		record["trick_progress"] = progress
		record["taught_by"] = teacher
		return {"ok":true, "trick":"%s" % trick, "learned":true}
	return {"ok":true, "trick":trick, "learned":false, "progress":int(progress[trick])}


## A tummy rub or a scratch: pure affection. It warms the pet's bond with the
## person who gave it and is remembered on the pet's own record.
func affectionate_pet(pet_id: String, person: String) -> Dictionary:
	var record: Dictionary = _pet_record(pet_id)
	if record.is_empty():
		return {"ok":false, "error":"That pet is not part of this household."}
	record["affection"] = int(record.get("affection", 0)) + 1
	record["last_affection_by"] = person
	return {"ok":true}


## A bath. It restores the animal's own cleanliness, which the household's clock
## then drains again like any other need. A cat never reaches this: its coat is
## its own business, and the availability gate refuses it first.
func bathe_pet(pet_id: String, bather: String) -> Dictionary:
	var record: Dictionary = _pet_record(pet_id)
	if record.is_empty():
		return {"ok":false, "error":"That pet is not part of this household."}
	# A bath restores the animal's own coat in the condition record the HUD draws
	# and the household clock drains, exactly as a meal restores hunger.
	var care: Dictionary = record.get("care", {})
	if not care is Dictionary or care.is_empty():
		care = LifePetCare.fresh()
	var needs: Dictionary = care.get("needs", {})
	if not needs is Dictionary or needs.is_empty():
		needs = LifePetCare.FRESH_NEEDS.duplicate(true)
	needs["hygiene"] = 100.0
	care["needs"] = needs
	record["care"] = care
	record["last_bathed_by"] = bather
	return {"ok":true}


## The household's live pet record, or empty when the id names no pet here.
func pet_record(pet_id: String) -> Dictionary:
	return _pet_record(pet_id)


func _pet_record(pet_id: String) -> Dictionary:
	if not is_instance_valid(app) or not is_instance_valid(app.household):
		return {}
	for pet: Dictionary in app.household.pets.get("pets", []):
		if str(pet.get("id","")) == pet_id:
			return pet
	return {}


func _now() -> float:
	return (app.household.day - 1) * 1440.0 + app.household.minutes
