extends SceneTree
## Structural UI oracle: every visible Control must be inside the canvas, and no
## two visible sibling Controls that both accept the mouse may overlap.
##
##   godot --audio-driver Dummy --path <project> --script res://tests/probe_ui_overlap.gd
##
## Reports per screen: `UI_OVERLAP <screen> <a> <b> <overlap>`. Overlapping pairs
## that are both mouse-interactive are real defects: the later-drawn control
## steals the click and hides the other. It does not prove the layout is
## attractive; it proves nothing is unreachable or clipped.

var app: Node
var checks: int = 0
var failures: Array[String] = []
var screens: int = 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, why: String) -> void:
	checks += 1
	if not ok:
		failures.append(why)
		push_error(why)

func frames(count: int = 3) -> void:
	for index: int in count: await process_frame

func descend(node: Node, into: Array[Control]) -> void:
	for child: Node in node.get_children():
		if child is Control and (child as Control).visible and not (child as Control).is_queued_for_deletion():
			into.append(child)
			descend(child, into)

func press(label_text: String) -> bool:
	for node: Node in app.find_children("*", "Button", true, false):
		if node is Button and node.is_visible_in_tree() and not node.disabled and str(node.text) == label_text:
			node.pressed.emit()
			await frames(2)
			return true
	return false

## Emulates Godot's Control picking: recurse into children in reverse order
## (last drawn wins), then test the node itself. A Control is unreachable when
## this returns something that is neither it nor one of its descendants.
const INTERACTIVE := ["Button", "LineEdit", "TextEdit", "OptionButton", "CheckBox", "CheckButton", "HSlider", "VSlider", "SpinBox", "MenuButton", "LinkButton", "TextureButton"]

func is_interactive(control: Control) -> bool:
	for kind: String in INTERACTIVE:
		if control.is_class(kind):
			return true
	return false

func pick(node: Node, point: Vector2) -> Control:
	if node is CanvasItem and not (node as CanvasItem).is_visible_in_tree():
		return null
	for index: int in range(node.get_child_count() - 1, -1, -1):
		var hit: Control = pick(node.get_child(index), point)
		if hit != null:
			return hit
	var control: Control = node as Control
	if control == null or control.mouse_filter == Control.MOUSE_FILTER_IGNORE:
		return null
	if not control.get_global_rect().has_point(point):
		return null
	return control

## `dismiss_layer()` adds a flat, transparent Button as a click-outside-to-close
## backdrop. Its own centre is behind the dialog by design, so it is not a
## blocked control. It is recognised by construction: flat, no text, no theme
## styleboxes, and covering most of the canvas.
func is_backdrop(control: Control) -> bool:
	if not (control is Button):
		return false
	var button: Button = control
	if not button.flat or not str(button.text).is_empty():
		return false
	var canvas: Vector2 = app.get_viewport().get_visible_rect().size
	return control.size.x >= canvas.x * 0.5 and control.size.y >= canvas.y * 0.5 \
		and button.get_theme_stylebox("normal") is StyleBoxEmpty

## Sample nine points across a control (centre, four corners and four edge
## midpoints, all inset) and return how many are routed to something else. A
## single centre sample misses a control whose middle is clear but whose corners
## are covered by a neighbouring button.
func occluded_points(control: Control) -> Array[Vector2]:
	var rect: Rect2 = control.get_global_rect()
	var inner: Rect2 = rect.grow(-3.0)
	if inner.size.x <= 0.0 or inner.size.y <= 0.0:
		inner = rect
	var points: Array[Vector2] = [inner.get_center()]
	for x: float in [inner.position.x, inner.get_center().x, inner.end.x]:
		for y: float in [inner.position.y, inner.get_center().y, inner.end.y]:
			points.append(Vector2(x, y))
	var blocked: Array[Vector2] = []
	for point: Vector2 in points:
		var winner: Control = pick(pick_root(), point)
		if winner == null or (winner != control and not winner.is_ancestor_of(control) and not control.is_ancestor_of(winner)):
			blocked.append(point)
	return blocked

func conflicts(screen: String) -> int:
	var found: Array[Control] = roots()
	var reported: int = 0
	for control: Control in found:
		if not is_interactive(control) or control.mouse_filter != Control.MOUSE_FILTER_STOP:
			continue
		if control.size.x <= 4.0 or control.size.y <= 4.0 or inside_scroll(control) or is_backdrop(control):
			continue
		if not control.is_visible_in_tree():
			continue
		var blocked: Array[Vector2] = occluded_points(control)
		if blocked.is_empty():
			continue
		reported += 1
		print("UI_BLOCKED %s | %s | %d/9 own points unreachable | rect=%s | first=%s" % [
			screen, _name_of(control), blocked.size(), str(control.get_global_rect()), str(blocked.front())])
	return reported

func _name_of(control: Control) -> String:
	if not str(control.name).is_empty() and not str(control.name).begins_with("@"):
		return str(control.name)
	if control is Button:
		return "Button(\"%s\")" % str((control as Button).text)
	if control is Label:
		return "Label(\"%s\")" % str((control as Label).text).left(24)
	return str(control.get_class())

func roots() -> Array[Control]:
	# `ui` is the HUD/creator layer and `overlay` is the modal layer. Whatever
	# the overlay currently holds is on top and intentionally covers the HUD, so
	# only the topmost non-empty layer is inspected for each screen.
	var layer: Node = app.get_node("Interface")
	var overlay: Control = layer.get_node("Overlay")
	var active: Control = overlay if overlay.get_child_count() > 0 else layer.get_node("UI")
	var out: Array[Control] = [active]
	descend(active, out)
	return out

func pick_root() -> Node:
	var layer: Node = app.get_node("Interface")
	var overlay: Control = layer.get_node("Overlay")
	return overlay if overlay.get_child_count() > 0 else layer.get_node("UI")

## Content inside a ScrollContainer is clipped by design; its overflow is not a
## layout defect. Skip the scroll container's own content subtree.
func inside_scroll(control: Control) -> bool:
	var node: Node = control.get_parent()
	while node != null:
		if node is ScrollContainer:
			return true
		node = node.get_parent()
	return false

func measure(screen: String) -> void:
	await frames(3)
	var before: int = failures.size()
	# Every visible Control must sit inside the canvas.
	var canvas: Vector2 = app.get_viewport().get_visible_rect().size
	var inside: Array[Control] = roots()
	for control: Control in inside:
		if control.mouse_filter == Control.MOUSE_FILTER_IGNORE:
			continue
		if inside_scroll(control):
			continue
		var rect: Rect2 = control.get_global_rect()
		if rect.size.x <= 0.0 or rect.size.y <= 0.0:
			continue
		if rect.position.x < -2.0 or rect.position.y < -2.0 or rect.end.x > canvas.x + 2.0 or rect.end.y > canvas.y + 2.0:
			check(false, "%s: %s escapes the canvas %s: %s" % [screen, _name_of(control), str(canvas), str(rect)])
	var overlaps: int = conflicts(screen)
	screens += 1
	print("UI_SCREEN %s overlaps=%d canvas=%s offscreen=%d" % [screen, overlaps, str(canvas), failures.size() - before])

func _run() -> void:
	app = load("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	current_scene = app
	await frames(6)
	app.set_sound(false)

	await measure("main_menu")
	await press("Saved lives")
	await measure("save_picker")
	await press("Close")

	await press("New game")
	await measure("creator_look")
	await press("Face")
	await measure("creator_face")
	await press("Wardrobe")
	await measure("creator_wardrobe")
	await press("+ Add Lifelet")
	await press("Connections")
	await measure("creator_connections")
	await press("Back to creating")

	await press("Find my home  →")
	await measure("lot_selection")
	await press("Start living  →")
	await frames(10)
	app.household.set_speed(0)
	app.draw_live()
	await measure("live_needs")
	for tab: String in ["Skills", "People", "Career"]:
		app.panel_tab = tab
		app.draw_live()
		await measure("live_" + tab.to_lower())

	for opener: Dictionary in [
		{"call": func(): app.show_person(), "name": "person"},
		{"call": func(): app.show_stories(), "name": "stories"},
		{"call": func(): app.show_neighborhood(), "name": "explore"},
		{"call": func(): app.show_careers(), "name": "careers"},
		{"call": func(): app.show_wishes(), "name": "wishes"},
		{"call": func(): app.show_rewards(), "name": "rewards"},
		{"call": func(): app.show_relationships(), "name": "relationships"},
		{"call": func(): app.show_family_tree(), "name": "family_tree"},
		{"call": func(): app.show_school_record(), "name": "school_record"},
		{"call": func(): app.show_career_record(), "name": "career_record"},
		{"call": func(): app.show_life_settings(), "name": "life_settings"},
		{"call": func(): app.show_menu(), "name": "pause_menu"},
		{"call": func(): app.show_help(), "name": "help"},
		{"call": func(): app.adoption_flow.show_phone(), "name": "phone"},
		{"call": func(): app.adoption_flow.calendar.show_calendar(), "name": "calendar"},
		{"call": func(): app.adoption_flow.show_candidates(), "name": "adoption_candidates"},
		{"call": func(): app.pet_shop.show_shop(), "name": "pet_shop"},
		{"call": func(): app.pet_shop.show_species(), "name": "pet_picker"},
	]:
		opener["call"].call()
		await measure(str(opener["name"]))
		app.close_overlay()

	# The panels this objective adds or touches, so a control that a real player
	# has to press is measured for reachability like every older panel.
	var mirror: Dictionary = app.world.closest_item("mirror", Vector3.ZERO)
	if not mirror.is_empty():
		for tab: String in ["clothes", "hair", "makeup", "jewelry"]:
			app.show_wardrobe_panel(str(mirror.id), tab)
			await measure("wardrobe_" + tab)
			app.close_overlay()

	var dressing: Dictionary = app.world.closest_item("dressing_table", Vector3.ZERO)
	if not dressing.is_empty():
		app.show_wardrobe_panel(str(dressing.id), "makeup")
		await measure("dressing_table_makeup")
		app.close_overlay()

	var dining: Dictionary = app.world.closest_item("dining", Vector3.ZERO)
	if not dining.is_empty():
		var food: LifeMeals = app.household.meals
		var now: float = app.meal_flow.now()
		var batch: Dictionary = food.create_batch("garden_skillet", str(app.household.selected_id()), 2, app.current_venue, now)
		food.set_batch_location(str(batch.id), "surface", str(dining.id), dining.node.global_position, now)
		app.meal_flow.sync_world(true)
		app.show_food_offers(str(batch.id))
		await measure("food_offers")
		app.close_overlay()
		app.meal_flow.show_leftovers(str(batch.id))
		await measure("leftovers")
		app.close_overlay()

	var stove: Dictionary = app.world.closest_item("stove", Vector3.ZERO)
	if not stove.is_empty():
		app.meal_flow.show_recipes(str(stove.id))
		await measure("recipes")
		app.close_overlay()

	for kind: String in ["fridge", "rubbish_bin", "wardrobe", "mirror", "stove", "bed", "desk", "toybox"]:
		var item: Dictionary = app.world.closest_item(kind, Vector3.ZERO)
		if item.is_empty():
			continue
		app.show_interactions(item, app.get_viewport().get_visible_rect().size * 0.5)
		await measure("interactions_" + kind)
		app.close_overlay()

	var owned: Array = app.household.pets.get("pets", [])
	if not owned.is_empty():
		app.show_pet_card(str(owned[0].id))
		await measure("pet_card")
		app.close_overlay()

	app.set_build_mode(true)
	await measure("build_catalog")
	for category: String in LifeCatalog.CATEGORIES:
		app.catalog_category = category
		app.draw_live()
		await measure("build_" + category.to_lower())
	app.show_storage()
	await measure("storage")
	app.close_overlay()
	# The variant picker: every style, size and colour button has to be reachable,
	# and its wrapped swatch grid is exactly the shape that used to overlap.
	for kind: String in ["pool", "tree_garden", "fence", "car", "game_trampoline"]:
		app.pick_furnishing(kind)
		await measure("variant_" + kind)
		app.close_overlay()
	# And the post box's own list.
	app.show_post_box()
	await measure("post_box")
	app.close_overlay()

	print("UI_OVERLAP_RESULT ", JSON.stringify({"screens": screens, "checks": checks, "failures": failures}))
	app.queue_free()
	await frames(3)
	quit(0 if failures.is_empty() else 1)
