extends SceneTree
## A drawn room meets at the corners and keeps one doorway.

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

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var state: Dictionary = Building.fresh()
	var built: Dictionary = Edits.propose(state, {
		"op": "structure", "tool": "room", "level": 0,
		"ax": -2.0, "az": -2.0, "bx": 2.0, "bz": 2.0,
	}, 50000)
	check(bool(built.ok), "A room can be drawn (%s)." % str(built.get("error", "")))
	if not bool(built.ok):
		print("ROOM_CORNERS ", checks, " assertions; ", failures, " failures")
		quit(1)
		return
	var after: Dictionary = built.after
	for corner: Vector2 in [Vector2(-2, -2), Vector2(2, -2), Vector2(-2, 2), Vector2(2, 2)]:
		var covered: int = 0
		for wall: Dictionary in after.walls:
			if Building.rect(wall).grow(.02).has_point(corner): covered += 1
		check(covered >= 2, "Corner %s is covered by both walls that meet there (%d)." % [str(corner), covered])
	var gap: bool = false
	for wall: Dictionary in after.walls:
		if float(wall.w) > float(wall.d) and absf(float(wall.z) + 2.0) < .2:
			gap = gap or float(wall.w) < 3.2
	check(gap or after.walls.size() > 4, "The room keeps a doorway instead of a solid loop (%d walls)." % after.walls.size())
	var inside: Dictionary = Edits._enclosed_cells(after, 0, Vector2(0, 0))
	check(not bool(inside.escaped) and not (inside.cells as Dictionary).is_empty(), "The corner joints and the doorway still read as one closed room.")
	print("ROOM_CORNERS ", checks, " assertions; ", failures, " failures")
	quit(1 if failures else 0)
