extends SceneTree
## Screenshot the reworked town map at several zooms, so the bigger scrollable
## map with every place pinned is checked as the player sees it.
##
##   godot --path . --audio-driver Dummy --script res://tests/probe_neighborhood_map.gd

var app: Node
var failures: Array[String] = []
var checks: int = 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, why: String) -> void:
	checks += 1
	print("CHECK ", "PASS " if ok else "FAIL ", why)
	if not ok: failures.append(why)

func frames(n: int = 3) -> void:
	for i: int in n: await process_frame

func shot(name: String) -> void:
	RenderingServer.force_draw(false, 0.0)
	await process_frame
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://neighborhood_map"))
	var path: String = "user://neighborhood_map/%s.png" % name
	var error: int = root.get_texture().get_image().save_png(path)
	print("MAP_SHOT %s %s %s" % [name, "ok" if error == OK else "FAILED", ProjectSettings.globalize_path(path)])

## Every visitable place must have exactly one pin inside the map canvas.
func pins() -> Array[Button]:
	var out: Array[Button] = []
	var canvas: Node = app.find_child("NeighborhoodCanvas", true, false)
	if canvas == null: return out
	for node: Node in canvas.find_children("*", "Button", true, false):
		var b: Button = node as Button
		if b != null and b.is_visible_in_tree(): out.append(b)
	return out

func _run() -> void:
	app = load("res://scenes/main.tscn").instantiate()
	root.add_child(app); current_scene = app
	await frames(8)
	app.set_sound(false)
	app.selected_lot = 0
	app.start_household()
	await frames(12)
	app.household.set_speed(0)
	app.show_neighborhood()
	await frames(10)

	var places: Array = LifeNeighborhood.PLACES.keys()
	var found: Array[Button] = pins()
	print("MAP places=%d pins=%d zoom=%.3f" % [places.size(), found.size(), app.map_zoom])
	check(found.size() == places.size(), "Every visitable place has a pin (%d places, %d pins)" % [places.size(), found.size()])
	var named: Array[String] = []
	for b: Button in found: named.append(str(b.text))
	for id: String in places:
		var label: String = str(LifeNeighborhood.PLACES[id].name)
		check(named.has(label), "The map shows a pin for %s" % label)
	# The pins must not overlap each other, or the later one steals the click.
	var overlaps: int = 0
	for a: int in range(found.size()):
		for b: int in range(a + 1, found.size()):
			var hit: Rect2 = found[a].get_global_rect().intersection(found[b].get_global_rect())
			if hit.size.x > 1.0 and hit.size.y > 1.0:
				overlaps += 1
				print("MAP_OVERLAP %s %s" % [found[a].text, found[b].text])
	check(overlaps == 0, "No two pins overlap at the default zoom (%d)" % overlaps)
	var scroll: ScrollContainer = app.find_child("NeighborhoodMap", true, false) as ScrollContainer
	check(scroll != null, "The map is a scroll container")
	await shot("fit")

	# Zoom in: the town's coordinates spread out and the view can be scrolled.
	var zoom_before: float = app.map_zoom
	app.zoom_neighborhood_map(app.MAP_ZOOM_STEP)
	await frames(6)
	check(app.map_zoom > zoom_before, "Zooming in raises the map zoom (%.3f -> %.3f)" % [zoom_before, app.map_zoom])
	var canvas: Control = app.find_child("NeighborhoodCanvas", true, false) as Control
	check(canvas != null and canvas.size.x > scroll.size.x, "Zoomed in, the town is wider than the viewport (%.0f > %.0f)" % [canvas.size.x if canvas != null else 0.0, scroll.size.x])
	await shot("zoom_in")
	app.zoom_neighborhood_map(app.MAP_ZOOM_STEP)
	await frames(6)
	await shot("zoom_deeper")
	# Zooming out past the fit point clamps at the whole town.
	for i: int in range(12): app.zoom_neighborhood_map(-app.MAP_ZOOM_STEP)
	await frames(8)
	check(app.map_zoom >= app.MAP_MIN_ZOOM - 0.0001, "Zooming out clamps at the minimum (%.3f)" % app.map_zoom)
	await shot("zoom_out")
	app.zoom_neighborhood_map(-99.0)
	await frames(6)
	check(is_equal_approx(app.map_zoom, app._neighborhood_fit_zoom()), "Fit the whole town returns to the fitting zoom")
	await shot("fit_again")

	# Selecting a place from the map still offers its travel button.
	app.show_neighborhood("library")
	await frames(8)
	var go: Button = null
	for node: Node in app.overlay.find_children("*", "Button", true, false):
		var b: Button = node as Button
		if b != null and str(b.text).begins_with("Travel here"): go = b
	check(go != null and not go.disabled, "A public place keeps its available travel button")
	await shot("library_selected")

	print("MAP_RESULT ", JSON.stringify({"checks": checks, "failures": failures}))
	app.queue_free(); await frames(3)
	quit(0 if failures.is_empty() else 1)
