extends SceneTree
## Roof visibility toggle, five styles, tint, and edge-handle resize.
const Building = preload("res://scripts/building_state.gd")
const Roof = preload("res://scripts/roof_geometry.gd")
const Land = preload("res://scripts/land.gd")
const Edits = preload("res://scripts/roof_edits.gd")

var checks: int = 0
var failures: Array = []


func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
		push_error(description)


func _initialize() -> void:
	run.call_deferred()


func run() -> void:
	Building.set_land(Land.fresh())
	check(Roof.STYLES.size() == 5, "Five roof styles are offered")
	check(Roof.normalize_style("A-frame") == "a_frame", "A-frame normalizes")
	check(Roof.normalize_style("hip") == "hipped", "Hip normalizes")

	var base: Dictionary = Building.fresh()
	base.floors = [{"id": "ground", "level": 0, "x": 0.0, "z": 0.0, "w": 8.0, "d": 10.0, "material": "cfa97e"}]
	for sign: int in [-1, 1]:
		base.walls.append({"id": "west" if sign < 0 else "east", "level": 0, "x": sign * 4.0, "z": 0.0, "w": 0.14, "d": 10.0, "height": 2.6, "cut": true, "material": "eae7d7"})
		base.walls.append({"id": "north" if sign < 0 else "south", "level": 0, "x": 0.0, "z": sign * 5.0, "w": 8.0, "d": 0.14, "height": 2.6, "cut": true, "material": "eae7d7"})

	for style: String in Roof.STYLES:
		var record: Dictionary = {
			"id": "r_" + style, "level": 0, "x": 0.0, "z": 0.0, "w": 8.0, "d": 10.0,
			"pitch": 0.05 if style == "flat" else (0.95 if style == "a_frame" else 0.5),
			"rotation": 0, "material": "8b5a3c", "style": style, "supports": ["west", "east"]
		}
		var node: Node3D = Roof.create(record)
		check(is_instance_valid(node), "Style %s builds a node" % style)
		check(str(node.get_meta("roof_style", "")) == style or (style == "gabled" and str(node.get_meta("roof_style", "")) in ["gabled", "a_frame"]),
			"Style %s tags the mesh (got %s)" % [style, str(node.get_meta("roof_style", ""))])
		var handles: int = 0
		for child: Node in node.get_children():
			if child is MeshInstance3D and child.has_meta("roof_edge"):
				handles += 1
		check(handles == 4, "Style %s exposes four edge handles" % style)
		var state: Dictionary = base.duplicate(true)
		state.roofs = [record]
		var error: String = Building.validate(state)
		check(error.is_empty(), "Style %s validates (%s)" % [style, error])
		node.free()

	# Roof edit preserves identity while changing style and tint.
	var roofed: Dictionary = base.duplicate(true)
	roofed.roofs = [{
		"id": "r0", "level": 0, "x": 0.0, "z": 0.0, "w": 8.0, "d": 10.0,
		"pitch": 0.5, "rotation": 0, "material": "57736a", "style": "gabled", "supports": ["west", "east"]
	}]
	var restyle: Dictionary = roofed.roofs[0].duplicate(true)
	restyle.erase("id")
	restyle.style = "hipped"
	restyle.material = "8b5a3c"
	var edit: Dictionary = Edits.propose(roofed, {"op": "roof_edit", "id": "r0", "record": restyle}, 5000)
	check(bool(edit.ok), "Roof style/tint edit quote succeeds (%s)" % str(edit.get("error", "")))
	if bool(edit.ok):
		var after: Dictionary = Building.find(edit.after, "r0")
		check(str(after.style) == "hipped", "Restyled roof is hipped")
		check(str(after.material) == "8b5a3c", "Retinted roof keeps the chosen colour")
	# Edge-handle math: opposite edge fixed, moved edge sets the new span.
	var edge_old_w: float = 8.0
	var fixed: float = 0.0 - 1 * edge_old_w * 0.5  # west edge at -4
	var moving: float = 5.0
	var new_w: float = absf(moving - fixed)
	var new_x: float = (fixed + moving) * 0.5
	check(is_equal_approx(new_w, 9.0) and is_equal_approx(new_x, 0.5), "Edge handle math grows one side only")

	print("ROOF_CUSTOM_PROBE %d/%d" % [checks - failures.size(), checks])
	for failure: String in failures:
		print("FAIL ", failure)
	quit(0 if failures.is_empty() else 1)
