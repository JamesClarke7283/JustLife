extends SceneTree
## Detached fixture: exercise the production reservation guard without loading
## a rendered household or mutating its wallet, navigation, or furnishings.
const Transactions = preload("res://scripts/build_transactions.gd")
class DriverFixture extends RefCounted:
	var action: Dictionary = {}
	func get_current_action() -> Dictionary: return action
class HouseholdFixture extends RefCounted:
	var members: Array = []
class WorldFixture extends Node3D:
	var layout: Array = []
	func serialize_items() -> Array: return layout.duplicate(true)
class AppFixture extends Node:
	var world: WorldFixture
	var household: HouseholdFixture

var checks: int = 0
var failures: Array[String] = []
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message); push_error(message)
func _initialize() -> void: run.call_deferred()
func changed(layout: Array, id: String, key: String, value: Variant) -> Array:
	var result: Array = layout.duplicate(true)
	for item: Dictionary in result:
		if str(item.id) == id: item[key] = value
	return result
func without(layout: Array, id: String) -> Array:
	return layout.filter(func(item: Dictionary) -> bool: return str(item.id) != id)
func run() -> void:
	var app := AppFixture.new(); root.add_child(app)
	app.world = WorldFixture.new(); app.add_child(app.world)
	app.household = HouseholdFixture.new()
	var driver := DriverFixture.new()
	app.household.members = [{"id":"player", "sim":driver}]
	app.world.layout = [
		{"id":"car", "kind":"car", "x":-3.2, "z":0.35, "rotation":0, "level":0},
		{"id":"garage", "kind":"car_garage", "x":0.0, "z":0.0, "rotation":0, "level":0},
		{"id":"other_garage", "kind":"car_garage", "x":15.0, "z":0.0, "rotation":0, "level":0},
		{"id":"chair", "kind":"chair", "x":6.0, "z":6.0, "rotation":0, "level":0}]
	var original: Array = app.world.serialize_items()
	var tx := Transactions.new(app)
	check(tx.commute_vehicles().is_empty() and tx.commute_layout_error(without(original,"car")).is_empty(), "Idle drivers do not reserve a car.")
	driver.action = {"id":"drive_to_work", "target_id":"car", "phase":"approach"}
	check(tx.commute_vehicles() == ["car"], "Walk-to-car reserves its source before choreography is initialized.")
	check(tx.commute_layout_error(original).is_empty(), "An unchanged active car and garage remain valid.")
	check(tx.commute_layout_error(changed(original,"car","size","")).is_empty(), "Explicit default size matches an omitted size without a Variant type error.")
	check(tx.commute_layout_error(changed(original,"car","rotation",0.0)).is_empty(), "Equivalent integer and floating-point rotations remain valid.")
	for phase: String in ["walk", "board", "depart", "away", "return", "exit", "back"]:
		driver.action = {"id":"drive_to_work" if phase in ["walk","board","depart"] else "career_day", "target_id":"car" if phase in ["walk","board","depart"] else "lot_exit", "commute":{"vehicle":"car", "phase":phase}}
		check(not tx.commute_layout_error(without(original,"car")).is_empty(), "Removing or storing the source car is blocked during "+phase+".")
	for key: String in ["x", "z", "rotation", "level", "size", "kind"]:
		var value: Variant = {"x":-2.0, "z":1.0, "rotation":90, "level":1, "size":"large", "kind":"car_electric"}[key]
		check(not tx.commute_layout_error(changed(original,"car",key,value)).is_empty(), "An active car cannot change "+key+".")
	check(tx.commute_layout_error(changed(original,"chair","x",7.0)).is_empty(), "Unrelated furnishing movement remains allowed.")
	check(tx.commute_layout_error(without(original,"chair")).is_empty(), "Unrelated furnishing removal remains allowed.")
	check(not tx.commute_layout_error(without(original,"garage")).is_empty(), "Removing the occupied garage is blocked.")
	check(not tx.commute_layout_error(changed(original,"garage","x",1.0)).is_empty(), "Moving the occupied garage is blocked.")
	check(not tx.commute_layout_error(changed(original,"garage","rotation",90)).is_empty(), "Rotating the occupied garage is blocked.")
	check(tx.commute_layout_error(without(original,"other_garage")).is_empty(), "Removing an unoccupied garage remains allowed.")
	check(tx.commute_layout_error(changed(original,"other_garage","x",17.0)).is_empty(), "Moving a different unoccupied garage remains allowed.")
	# Garage occupation follows authored bay transforms, including rotation.
	var rotated: Array = changed(original,"garage","rotation",90)
	var bay: Vector3 = Basis(Vector3.UP,PI/2.0)*LifeCatalog.vehicle_snap_locals("car_garage")[0]
	rotated = changed(changed(rotated,"car","x",bay.x),"car","z",bay.z)
	app.world.layout = rotated
	check(not tx.commute_layout_error(without(rotated,"garage")).is_empty(), "Rotated occupied garage bays retain their reservation.")
	var second := DriverFixture.new(); second.action=driver.action.duplicate(true)
	app.household.members.append({"id":"housemate_1", "sim":second})
	check(tx.commute_vehicles() == ["car"], "Two driver references reserve one source vehicle once.")
	driver.action = {"id":"read", "target_id":"shelf"}; second.action={}
	check(tx.commute_vehicles().is_empty() and tx.commute_layout_error(without(rotated,"car")).is_empty(), "A finished or canceled commute releases car and garage reservations.")
	check(app.world.serialize_items() == rotated, "Reservation checks never mutate current furnishings.")
	var no_household := Node.new(); root.add_child(no_household)
	check(Transactions.new(no_household).commute_vehicles().is_empty(), "Transaction fixtures without a household retain existing behavior.")
	check(Transactions.new().commute_vehicles().is_empty(), "An unbound transaction service holds no reservations.")
	no_household.queue_free(); app.queue_free(); await process_frame
	print("COMMUTE_BUILD_PROTECTION %d checks, %d failures" % [checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
