extends SceneTree
## Building a wall run closes a sliver gap. A room that would seal someone in
## gets a real doorway instead of a solid loop or an open missing panel.
const Building = preload("res://scripts/building_state.gd")
const Land = preload("res://scripts/land.gd")
const Edits = preload("res://scripts/building_edits.gd")

var checks: int = 0
var failures: int = 0

func check(value: bool, detail: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(detail)

func _spans(walls: Array, horizontal: bool, line: float) -> Array:
	var spans: Array = []
	for wall: Dictionary in walls:
		var along: bool = float(wall.w) > float(wall.d)
		if along != horizontal: continue
		var at: float = float(wall.z) if horizontal else float(wall.x)
		if absf(at - line) > .08: continue
		var mid: float = float(wall.x) if horizontal else float(wall.z)
		var half: float = maxf(float(wall.w), float(wall.d)) * .5
		spans.append(Vector2(mid - half, mid + half))
	spans.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x)
	return spans

func _widest_gap(spans: Array) -> float:
	var gap: float = 0.0
	for index: int in range(spans.size() - 1):
		gap = maxf(gap, float(spans[index + 1].x) - float(spans[index].y))
	return gap

func _initialize() -> void:
	Building.set_land(Land.fresh())
	var run: Dictionary = Building.fresh()
	run.walls = [{"id": "run", "level": 0, "x": 0.0, "z": 0.0, "w": 4.0, "d": 0.14, "height": 2.6, "cut": true, "material": "eae7d7"}]
	run.floors = [{"id": "floor", "level": 0, "x": 0.0, "z": 0.0, "w": 16.0, "d": 16.0, "material": "cfa97e"}]
	var extended: Dictionary = Edits.propose(run, {"op": "structure", "tool": "wall", "level": 0, "ax": 2.35, "az": 0.0, "bx": 6.0, "bz": 0.0}, 8000)
	check(bool(extended.ok), "Extending a wall run quotes (%s)." % str(extended.get("error", "")))
	if bool(extended.ok):
		var spans: Array = _spans(extended.after.walls, true, 0.0)
		check(spans.size() == 1, "The extended run is one wall, not two panels with a gap (%d)." % spans.size())
		if spans.size() == 1:
			check(float(spans[0].x) <= -1.9 and float(spans[0].y) >= 5.9, "The joined run covers both the old wall and the extension (%s)." % str(spans[0]))
			check(_widest_gap(spans) < .05, "No gap remains in the extended wall run.")
	var door: Dictionary = Building.fresh()
	door.walls = [
		{"id": "left", "level": 0, "x": -1.4, "z": 2.0, "w": 1.8, "d": 0.14, "height": 2.6, "cut": true, "material": "eae7d7"},
		{"id": "right", "level": 0, "x": 1.4, "z": 2.0, "w": 1.8, "d": 0.14, "height": 2.6, "cut": true, "material": "eae7d7"},
	]
	door.floors = run.floors.duplicate(true)
	var kept: Dictionary = Edits.propose(door, {"op": "structure", "tool": "wall", "level": 0, "ax": -6.0, "az": 4.0, "bx": -3.0, "bz": 4.0}, 8000)
	check(bool(kept.ok), "A wall elsewhere still quotes while a doorway exists.")
	if bool(kept.ok):
		var opening: Array = _spans(kept.after.walls, true, 2.0)
		check(opening.size() == 2 and _widest_gap(opening) > .9 and _widest_gap(opening) < 1.4,
			"A real doorway stays open (%s gap %s)." % [str(opening.size()), str(_widest_gap(opening))])
	var sealed: Dictionary = Building.fresh()
	sealed.floors = [{"id": "pad", "level": 0, "x": 0.0, "z": 0.0, "w": 16.0, "d": 16.0, "material": "cfa97e"}]
	var room: Dictionary = Edits.propose(sealed, {"op": "structure", "tool": "room", "level": 0, "ax": -2.0, "az": -2.0, "bx": 2.0, "bz": 2.0}, 8000)
	check(bool(room.ok), "A room quotes (%s)." % str(room.get("error", "")))
	if bool(room.ok):
		var found_door: bool = false
		for line: float in [-2.0, 2.0]:
			var spans: Array = _spans(room.after.walls, true, line)
			var gap: float = _widest_gap(spans)
			if spans.size() >= 2 and gap >= .9 and gap <= 1.35: found_door = true
		for line: float in [-2.0, 2.0]:
			var spans: Array = _spans(room.after.walls, false, line)
			var gap: float = _widest_gap(spans)
			if spans.size() >= 2 and gap >= .9 and gap <= 1.35: found_door = true
		check(found_door, "A sealed room gets a doorway you can walk through.")
		var solid: bool = true
		for wall: Dictionary in room.after.walls:
			if maxf(float(wall.w), float(wall.d)) > 3.2: solid = false
		check(room.after.walls.size() >= 5, "The doorway is a cut opening, not a missing wall (%d panels)." % room.after.walls.size())
	var grab_room: Dictionary = Building.fresh()
	grab_room.walls = [
		{"id": "n", "level": 0, "x": 0.0, "z": -2.0, "w": 4.0, "d": 0.14, "height": 2.6, "cut": true, "material": "eae7d7"},
		{"id": "s", "level": 0, "x": 0.0, "z": 2.0, "w": 4.0, "d": 0.14, "height": 2.6, "cut": true, "material": "eae7d7"},
		{"id": "w", "level": 0, "x": -2.0, "z": 0.0, "w": 0.14, "d": 4.0, "height": 2.6, "cut": true, "material": "eae7d7"},
		{"id": "e", "level": 0, "x": 2.0, "z": 0.0, "w": 0.14, "d": 4.0, "height": 2.6, "cut": true, "material": "eae7d7"},
	]
	grab_room.floors = [{"id": "f0", "level": 0, "x": 0.0, "z": 0.0, "w": 4.0, "d": 4.0, "material": "cfa97e"}]
	var grab: Dictionary = Edits.propose(grab_room, {"op": "structure", "tool": "grab", "level": 0, "id": "s", "line": 3.0}, 5000)
	check(bool(grab.ok), "Grab wall still quotes after the run is closed (%s)." % str(grab.get("error", "")))
	if bool(grab.ok):
		var south: Dictionary = Building.find(grab.after, "s")
		var west: Dictionary = Building.find(grab.after, "w")
		check(is_equal_approx(float(south.z), 3.0) and is_equal_approx(float(west.d), 5.0), "Grab wall still stretches the connectors and moves the wall.")
		var interior := Vector2(0.0, 2.7)
		var covered: bool = false
		for floor: Dictionary in grab.after.floors:
			if Building.rect(floor).has_point(interior): covered = true
		check(covered, "Grab wall still grows the floor under the push.")
	print("WALL_RUN %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
