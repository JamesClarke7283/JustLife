extends SceneTree
## Build mode offers three archway styles and ten colours. An archway cuts a
## wall opening the way a door does, and the walkway between the jambs stays clear.
const Variants = preload("res://scripts/catalog_variants.gd")
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

func _initialize() -> void:
	var data: Dictionary = LifeCatalog.get_item("archway")
	var styles: Array = Variants.styles(data)
	var colors: Array = Variants.colors(data)
	check(styles.size() == 3 and styles == ["round", "roman", "tudor"], "Three archway styles (%s)." % str(styles))
	check(colors.size() == 10, "Ten archway colours (%d)." % colors.size())
	check(bool(data.get("cuts_doorway", false)) and bool(data.get("wall_mounted", false)), "An archway hangs in a wall and cuts an opening like a door.")
	for style: String in styles:
		var path: String = Variants.model_path("archway", style)
		check(FileAccess.file_exists(path), "The %s archway mesh is authored (%s)." % [style, path])
		var kept: Dictionary = Variants.record(data, style, str(colors[3]), "")
		check(str(kept.get("style", "")) == style and str(kept.get("color", "")) == str(colors[3]),
			"Style %s and colour %s stay on the placed archway." % [style, str(colors[3])])
	var panels: Array = LifeCatalog.local_panels("archway")
	check(panels.size() == 2, "Only the two jambs block, not a solid leaf (%d)." % panels.size())
	var blocks_centre: bool = false
	for panel: Dictionary in panels:
		if absf(float(panel.x)) < float(panel.w) * .5: blocks_centre = true
	check(not blocks_centre, "The centre of the archway is a walkway.")
	Building.set_land(Land.fresh())
	var wall: Dictionary = Building.fresh()
	wall.walls = [{"id": "run", "level": 0, "x": 0.0, "z": 0.0, "w": 6.0, "d": 0.14, "height": 2.6, "cut": true, "material": "eae7d7"}]
	wall.floors = [{"id": "pad", "level": 0, "x": 0.0, "z": 0.0, "w": 12.0, "d": 12.0, "material": "cfa97e"}]
	var door: Dictionary = Edits.propose(wall, {"op": "structure", "tool": "door", "level": 0, "id": "run", "center": 0.0}, 5000)
	check(bool(door.ok), "The wall opening an archway uses can be cut (%s)." % str(door.get("error", "")))
	if bool(door.ok):
		var gap: float = 0.0
		var spans: Array = []
		for piece: Dictionary in door.after.walls:
			var mid: float = float(piece.x)
			var half: float = float(piece.w) * .5
			spans.append(Vector2(mid - half, mid + half))
		spans.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x)
		if spans.size() >= 2:
			gap = float(spans[1].x) - float(spans[0].y)
		check(spans.size() >= 2 and gap > .9 and gap < 1.4, "The archway opening is a doorway, not a missing wall (gap %.2f)." % gap)
	print("ARCHWAY %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
