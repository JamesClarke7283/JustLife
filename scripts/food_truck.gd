extends Node
class_name LifeFoodTruck
## The weekly food truck: a real street object that parks on the front sidewalk
## on a weekly schedule driven by the shared game clock, is clicked to open its
## shop, and delivers a real furnishing the household can then use.
##
## It is deliberately a street object and not a venue. A venue replaces the whole
## lot (`main.setup_live` rebuilds the world and hides every actor), which is the
## shape for somewhere the household *travels to*; the truck is a van parked
## outside the home, so the household stays at home, keeps its Lifelets, its
## actions and its camera, and simply walks out to the curb to order. Its own
## saved state is one small record — the day it last visited and the serial of
## the order it last filled — so it round-trips on the shared clock.

const Menu = preload("res://scripts/food_truck_menu.gd")
## One visit every seven days, and the van is parked for the whole of that day.
const PERIOD_DAYS: int = 7
const OPEN_MINUTES: float = 8.0 * 60.0
const CLOSE_MINUTES: float = 20.0 * 60.0
## Where the van parks: on the front sidewalk, west of the path, clear of the
## front door and the mailbox. The lot runs to z=9, so z=8.5 is street side.
##
## Its own 2.33 m length lies along x when yawed a quarter turn, and the solid
## band drawn around it is grown a further 0.16 m on every side. The eight
## departure slots span x -2.625 … +2.625, which reaches x=-2.91 with that
## growth, so parking at -3.6 put the van's band across the westmost slot and a
## departure there was walked out to the next clear cell. The van now parks far
## enough west that its band (x -5.765 … -3.435) clears every slot.
const PARK: Vector3 = Vector3(-4.6, 0.16, 8.5)
const PARK_ROTATION: float = 90.0
## The vans's own delivered menu. Each line is a real catalogue kind, priced at
## what the shop charges for it; the delivered article is placed through the
## ordinary furnishing path, so support, doorway and reach rules still apply.
const GOODS: Dictionary = {
	"coffee_machine":{"label":"Counter-top espresso machine","note":"Pull a shot of espresso and drink it: a temporary second wind, on tap."},
	"garden_bed":{"label":"Kitchen garden bed","note":"Grow your own herbs and vegetables at home."},
	"rubbish_bin":{"label":"Pedal rubbish bin","note":"A pedal bin for the kitchen corner."},
	"plant":{"label":"A breath of green","note":"A leafy houseplant for the windowsill."},
	"stool":{"label":"Kitchen stool","note":"A spare seat for the counter."},
	"side_table":{"label":"Corner side table","note":"A small table for the corner of a room."},
}

var app: Node
var last_visit_day: int = 0
var serial: int = 0
var _van: Node3D = null
var _pick_info: Dictionary = {}


func _init(owner_app: Node = null) -> void:
	app = owner_app


# ---------------------------------------------------------------- persistence

func get_state() -> Dictionary:
	return {"version":1, "serial":serial, "last_visit_day":last_visit_day}


func restore(data: Variant) -> void:
	serial = 0
	last_visit_day = 0
	if not data is Dictionary:
		return
	serial = maxi(0, int(data.get("serial", 0)))
	last_visit_day = maxi(0, int(data.get("last_visit_day", 0)))
	if last_visit_day > 1000000:
		last_visit_day = 0


## The saved record is optional (an older save simply has no truck) and, when it
## is present, every field must be a whole number in range. A future visit day
## would otherwise let a corrupt save park the van permanently.
static func validate(data: Variant, day: int) -> String:
	if data == null:
		return ""
	if not data is Dictionary:
		return "The saved food truck is invalid."
	if not LifeBuildingState.number(data.get("serial", 0), 0, 1000000000, true):
		return "The saved food truck has an invalid order counter."
	if not LifeBuildingState.number(data.get("last_visit_day", 0), 0, 1000000, true):
		return "The saved food truck has an invalid visit day."
	if int(data.get("last_visit_day", 0)) > int(day):
		return "The saved food truck visited in the future."
	return ""


# ------------------------------------------------------------------ schedule

## Whether the truck is parked today. The schedule is a plain weekly period on
## the shared game day, so fast speed, pause and a save all agree about it.
func visiting() -> bool:
	if not is_instance_valid(app) or not is_instance_valid(app.household):
		return false
	return posmod(int(app.household.day) - 1, PERIOD_DAYS) == 0


## Whether the van is parked *and* keeping its opening hours right now.
func open() -> bool:
	if app.current_venue != "home" or not visiting():
		return false
	var minutes: float = float(app.household.minutes)
	return minutes >= OPEN_MINUTES and minutes < CLOSE_MINUTES


## The next game day the van comes back, for the phone entry and its tooltip.
func next_visit_day() -> int:
	return int(app.household.day) + (PERIOD_DAYS - posmod(int(app.household.day) - 1, PERIOD_DAYS))


## Why the shop cannot be used right now, in the player's own words.
func availability() -> String:
	if app.mode != "live" or app.current_venue != "home" or not app.pending_move.is_empty():
		return "Be at home in Live mode to visit the food truck."
	if not visiting():
		return "The van comes back on day %d." % next_visit_day()
	if not open():
		return "The van is parked but shut. It opens %s–%s." % [_clock(OPEN_MINUTES), _clock(CLOSE_MINUTES)]
	return ""


## Why one line of the menu cannot be ordered, or "" when it can.
func order_error(kind: String) -> String:
	if not GOODS.has(kind) or not LifeCatalog.ITEMS.has(kind):
		return "That is not on today's menu."
	var reason: String = availability()
	if not reason.is_empty():
		return reason
	var price: int = int(LifeCatalog.ITEMS[kind].price)
	if int(app.household.funds) < price:
		return "%s costs ℒ%d. Your household needs ℒ%d more." % [str(LifeCatalog.ITEMS[kind].label), price, price - int(app.household.funds)]
	return ""


static func _clock(minutes: float) -> String:
	return "%02d:%02d" % [int(minutes) / 60, int(minutes) % 60]


func price_of(kind: String) -> int:
	return int(LifeCatalog.get_item(kind).get("price", 0)) if GOODS.has(kind) else 0


# ------------------------------------------------------------------ delivery

## Charge for one order and hand back the furnishing it delivers. The wallet is
## charged exactly once: the household's own `set_funds` is the single mutation,
## and the order only places the entry it returns. A refused order changes
## nothing at all.
func place_order(kind: String) -> Dictionary:
	var reason: String = order_error(kind)
	if not reason.is_empty():
		return {"ok":false, "error":reason}
	var price: int = price_of(kind)
	var entry: Dictionary = {"id":"truck_%d" % (serial + 1), "kind":kind, "x":0.0, "z":0.0, "rotation":0.0}
	serial += 1
	app.household.set_funds(int(app.household.funds) - price)
	return {"ok":true, "kind":kind, "entry":entry, "price":price}


## The label a delivered order reports back to the player.
func order_label(kind: String) -> String:
	return str(LifeCatalog.get_item(kind).get("label", kind))


# --------------------------------------------------------------- presentation

## A saved truck rebuilds its own van if today is a visiting day; one that is
## gone is removed. Called after the world is (re)built, exactly as `sync_pets`.
func sync_world() -> void:
	if not is_instance_valid(app.world) or not is_instance_valid(app.world.house):
		return
	if not visiting() or app.current_venue != "home":
		remove_van()
		return
	if is_instance_valid(_van):
		return
	_van = Node3D.new()
	_van.name = "FoodTruckVan"
	app.world.house.add_child(_van)
	var model: Node3D = load("res://assets/models/delivery_van.glb").instantiate()
	_van.add_child(model)
	_van.position = PARK
	_van.rotation_degrees.y = PARK_ROTATION
	app.world.assign_structure_layer(_van, 0)
	# The van is picked like a pet's body: its own identity resolves through the
	# world's `pick_extras`, so clicking it opens the shop rather than walking.
	var body: StaticBody3D = StaticBody3D.new()
	body.collision_layer = LifeWorld.PICK_GROUND
	body.set_meta("item_id", _van.name)
	_van.add_child(body)
	var shape: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3(2.4, 1.9, 1.4)  # the van's own length, height and width, yawed
	shape.shape = box
	shape.position = Vector3(0, 0.95, 0)
	body.add_child(shape)
	_pick_info = {"id":str(_van.name), "kind":"food_truck", "label":"Weekly food truck", "node":_van, "size":Vector2(2.4,1.4)}
	app.world.pick_extras[str(_van.name)] = _pick_info
	_van.set_meta("visit_day", int(app.household.day))
	if _van.has_signal("ready"):
		_van.ready.connect(_on_ready, CONNECT_ONE_SHOT)


## The van's own notice when today's visit begins. The controller ticks the
## clock, so this fires from the world sync that follows a day change.
func _on_ready() -> void:
	pass


func remove_van() -> void:
	if is_instance_valid(_van) and is_instance_valid(app.world):
		app.world.pick_extras.erase(str(_van.name))
		_van.queue_free()
	_van = null
	_pick_info = {}


## The truck's own pick payload, for the controller's click dispatch.
func pick_info() -> Dictionary:
	return _pick_info.duplicate()


func present() -> bool:
	return is_instance_valid(_van)


## The van's own node, so a caller can point a camera or a notice at it.
func van() -> Node3D:
	return _van


# -------------------------------------------------------------- click -> shop

## Open the shop. This is the one entry point a click uses, so the phone and the
## van cannot disagree about what the shop is.
func show_shop() -> void:
	Menu.show_shop(app)
