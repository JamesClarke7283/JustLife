extends SceneTree
## Every authored resident-home furnishing must be reachable from the travel
## curb. A sofa-and-plant pocket that sealed Priya's west nook used to report
## "The way is blocked" for her bookshelves, lamp and rug.
const Building = preload("res://scripts/building_state.gd")

var checks: int = 0
var failures: Array[String] = []

func check(ok: bool, why: String) -> void:
	checks += 1
	print("CHECK ", "PASS " if ok else "FAIL ", why)
	if not ok:
		failures.append(why)
		push_error(why)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var world := LifeWorld.new()
	root.add_child(world)
	world.set_process(false)
	await process_frame
	var curb := Vector3(-1.5, Building.GROUND_Y, 7.5)
	for place: String in LifeNeighborhood.RESIDENT_HOMES:
		world.create_resident_home(place, LifeNeighborhood.layout(place))
		await process_frame
		check(world.last_layout_error.is_empty(), "%s builds without a layout error." % place)
		check(world.lot_navigation.point_clear(0, curb), "%s leaves the travel curb walkable." % place)
		var blocked: Array[String] = []
		for item: Dictionary in world.items:
			var at: Vector3 = world.approach(item)
			var route: Dictionary = world.route_to(curb, at) if at.is_finite() else {}
			if not bool(route.get("ok", false)):
				blocked.append("%s (%s: %s)" % [item.id, item.kind, route.get("error", "no approach")])
		check(blocked.is_empty(), "%s furnishings are reachable from the curb%s." % [place, "" if blocked.is_empty() else ": " + ", ".join(blocked)])
		var stand: Vector3 = LifeResidents.clear_home_stand(world)
		check(world.lot_navigation.point_clear(0, stand), "%s host stands on a clear tile (%.2f, %.2f)." % [place, stand.x, stand.z])
		var talk: Vector3 = world.nearest_clear_point(stand + Vector3(0, 0, 1.0), 0)
		var social: Dictionary = world.route_to(curb, talk) if talk.is_finite() else {}
		check(bool(social.get("ok", false)), "%s host has a reachable conversation place." % place)
	print("RESIDENT_HOME_APPROACHES %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
