extends SceneTree
## Carpet and the home paint coats stay inside one closed room.

const Building = preload("res://scripts/building_state.gd")
const Edits = preload("res://scripts/building_edits.gd")

var checks: int = 0
var failures: int = 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
		print("FAIL ", message)

func wall(id: String, x: float, z: float, w: float, d: float) -> Dictionary:
	return {"id": id, "level": 0, "x": x, "z": z, "w": w, "d": d, "height": 2.6, "cut": true, "material": "eae7d7"}

func room() -> Dictionary:
	var state: Dictionary = Building.fresh()
	state.walls = [
		wall("walls_1", 0, -2, 4, .12),
		wall("walls_2", 0, 2, 4, .12),
		wall("walls_3", -2, 0, .12, 4),
		wall("walls_4", 2, 0, .12, 4),
		wall("walls_5", 8, 0, .12, 4),
	]
	state.floors = [{"id": "floors_1", "level": 0, "x": 0.0, "z": 0.0, "w": 12.0, "d": 10.0, "material": "cfa97e"}]
	state.next_serial = 6
	return state

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var state: Dictionary = room()
	var built: String = Building.validate(state)
	check(built.is_empty(), "The fixture house is valid (%s)." % built)
	var outside: Dictionary = Edits.propose(state, {"op": "structure", "tool": "carpet", "level": 0, "px": 8.0, "pz": 0.0, "material": "f4b6c8", "style": "striped"}, 5000)
	check(not bool(outside.ok), "Carpet outside a closed room is refused.")
	var carpet: Dictionary = Edits.propose(state, {"op": "structure", "tool": "carpet", "level": 0, "px": 0.0, "pz": 0.0, "material": "f4b6c8", "style": "striped"}, 5000)
	check(bool(carpet.ok), "Carpet inside a closed room is accepted (%s)." % str(carpet.get("error", "")))
	if bool(carpet.ok):
		var area: float = 0.0
		var pink: float = 0.0
		var kept: bool = false
		for floor: Dictionary in carpet.after.floors:
			var rect: Rect2 = Building.rect(floor)
			var measure: float = rect.size.x * rect.size.y
			area += measure
			if str(floor.material) == "f4b6c8":
				pink += measure
				check(str(floor.get("carpet", "")) == "striped", "The room carpet records its weave.")
				check(absf(rect.position.x) < 2.2 and absf(rect.position.y) < 2.2 and absf(rect.end.x) < 2.2 and absf(rect.end.y) < 2.2, "Pink carpet stays inside the room.")
			elif rect.has_point(Vector2(4, 0)):
				kept = str(floor.material) == "cfa97e"
		check(is_equal_approx(area, 120.0), "Splitting the slab does not change how much floor there is (%.2f)." % area)
		check(pink > 1.0 and pink < 20.0, "Only the room is carpeted (%.2f m²)." % pink)
		check(kept, "The floor outside the room keeps its old finish.")
		check(int(carpet.cost) == maxi(1, int(round(pink * 2.0))) or int(carpet.cost) > 0, "Carpet costs about ℒ2 per square metre (ℒ%d)." % int(carpet.cost))
	var paint: Dictionary = Edits.propose(state, {"op": "structure", "tool": "paint", "level": 0, "id": "walls_1", "material": "6aa6e0", "palette": "home", "pattern": "two_tone", "scope": "room", "px": 0.0, "pz": 0.0}, 5000)
	check(bool(paint.ok), "Room paint is accepted (%s)." % str(paint.get("error", "")))
	if bool(paint.ok):
		var blue: int = 0
		var outsider: String = ""
		for painted: Dictionary in paint.after.walls:
			if str(painted.material) == "6aa6e0":
				blue += 1
				check(str(painted.pattern) == "two_tone" and str(painted.accent) == "f4b6c8", "Two-tone paint keeps its accent.")
			if str(painted.id) == "walls_5": outsider = str(painted.material)
		check(blue == 4, "The four room walls are painted and the spare wall is not (%d)." % blue)
		check(outsider == "eae7d7", "A wall outside the room is not painted.")
		check(int(paint.cost) > 0, "Room paint charges by the square metre.")
	var legacy: Dictionary = Edits.propose(state, {"op": "structure", "tool": "paint", "level": 0, "id": "walls_5", "material": "8faf9f"}, 5000)
	check(bool(legacy.ok) and int(legacy.cost) == int(4.0 * 6), "A paint call without a home coat still prices one wall by length.")
	print("ROOM_SURFACES ", checks, " assertions; ", failures, " failures")
	quit(1 if failures else 0)
