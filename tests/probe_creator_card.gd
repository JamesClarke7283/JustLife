extends SceneTree
## Oracle for the creator's right-hand card across the cases that make it
## tallest: an elder (15 hair colours, three rows), a male Lifelet (the shorter
## makeup set), every age stage, and the baby creator. Any overlap between two
## interactive controls, or any control drawn past the card or the canvas, is a
## real defect: the later-drawn control steals the click.
##
##   godot --path . --audio-driver Dummy --script res://tests/probe_creator_card.gd

const CARD_MIN_HEIGHT := 600.0
const CARD_WIDTH := 322.0

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
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://creator_card"))
	var path: String = "user://creator_card/%s.png" % name
	var error: int = root.get_texture().get_image().save_png(path)
	print("CREATOR_CARD_SHOT %s %s %s" % [name, "ok" if error == OK else "FAILED", ProjectSettings.globalize_path(path)])

const INTERACTIVE := ["Button", "LineEdit", "TextEdit", "OptionButton", "CheckBox", "CheckButton", "HSlider", "VSlider", "SpinBox", "MenuButton", "LinkButton", "TextureButton"]

func is_interactive(control: Control) -> bool:
	for kind: String in INTERACTIVE:
		if control.is_class(kind): return true
	return false

func label_of(control: Control) -> String:
	var text: Variant = control.get("text")
	if text != null and not str(control.name).begins_with("@"):
		return "%s(\"%s\")" % [str(control.name), str(text)]
	if text != null:
		return "Button(\"%s\")" % str(text)
	return str(control.name)

func visible_controls(root_control: Control) -> Array[Control]:
	var out: Array[Control] = []
	var stack: Array[Control] = [root_control]
	while not stack.is_empty():
		var node: Control = stack.pop_back()
		for child: Node in node.get_children():
			if child is Control and (child as Control).visible and not (child as Control).is_queued_for_deletion():
				out.append(child)
				stack.append(child)
	return out

func card_panel() -> Panel:
	var best: Panel = null
	for control: Control in visible_controls(app.overlay if app.overlay.get_child_count() > 0 else app.get_node("Interface/UI")):
		if control is Panel and is_equal_approx(control.size.x, CARD_WIDTH) and control.size.y >= CARD_MIN_HEIGHT:
			if best == null or control.size.y > best.size.y: best = control as Panel
	return best

## An overlap, an escape past the card, or an escape past the canvas all mean a
## player can see a control drawn wrongly. Also asserts something overlaps the
## "Find my home" call to action, which is the worst case of a tall card.
func inspect(screen: String) -> void:
	var layer: Control = app.overlay if app.overlay.get_child_count() > 0 else app.get_node("Interface/UI")
	var card: Panel = card_panel()
	var card_rect: Rect2 = card.get_global_rect() if card != null else Rect2(Vector2(1080, 126), Vector2(CARD_WIDTH, 614))
	var canvas: Rect2 = Rect2(Vector2.ZERO, app.get_viewport().get_visible_rect().size)
	var inside: Array[Control] = []
	for control: Control in visible_controls(layer):
		if not is_interactive(control): continue
		if control.mouse_filter != Control.MOUSE_FILTER_STOP: continue
		if control.size.x <= 4.0 or control.size.y <= 4.0: continue
		if not control.is_visible_in_tree(): continue
		inside.append(control)
	var overlaps: int = 0
	for a: int in range(inside.size()):
		for b: int in range(a + 1, inside.size()):
			var first: Control = inside[a]
			var second: Control = inside[b]
			var hit: Rect2 = first.get_global_rect().intersection(second.get_global_rect())
			if hit.size.x <= 1.0 or hit.size.y <= 1.0: continue
			if first.is_ancestor_of(second) or second.is_ancestor_of(first): continue
			overlaps += 1
			print("CREATOR_CARD_OVERLAP %s | %s %s | %s %s | %s" % [
				screen, label_of(first), str(first.get_global_rect()), label_of(second), str(second.get_global_rect()), str(hit)])
	var escapes: int = 0
	for control: Control in inside:
		var rect: Rect2 = control.get_global_rect()
		if rect.position.x < -2.0 or rect.position.y < -2.0 or rect.end.x > canvas.end.x + 2.0 or rect.end.y > canvas.end.y + 2.0:
			escapes += 1
			print("CREATOR_CARD_ESCAPE_CANVAS %s | %s | %s | canvas %s" % [screen, label_of(control), str(rect), str(canvas)])
		elif rect.position.x >= card_rect.position.x - 2.0 and rect.end.x > card_rect.end.x + 2.0 \
				and rect.position.y >= card_rect.position.y - 2.0 and rect.end.y <= card_rect.end.y + 2.0:
			escapes += 1
			print("CREATOR_CARD_ESCAPE %s | %s | %s | card %s" % [screen, label_of(control), str(rect), str(card_rect)])
	check(overlaps == 0, "%s: no two interactive controls overlap (%d)" % [screen, overlaps])
	check(escapes == 0, "%s: every control sits inside the card and the canvas (%d escaped)" % [screen, escapes])
	print("CREATOR_CARD %s overlaps=%d escapes=%d card=%s" % [screen, overlaps, escapes, str(card_rect)])

func sweep(prefix: String) -> void:
	for tab: String in ["Look", "Face", "Wardrobe", "Style"]:
		app.set_creator_tab(tab)
		await frames(6)
		await inspect("%s_%s" % [prefix, tab.to_lower()])
		await shot("%s_%s" % [prefix, tab.to_lower()])

func _run() -> void:
	app = load("res://scenes/main.tscn").instantiate()
	root.add_child(app); current_scene = app
	await frames(8)
	app.set_sound(false)
	app.new_game()
	await frames(10)
	check(app.mode == "creator", "Creator is open")
	await sweep("young")

	# A male Lifelet: the shorter makeup set, and the same jewelry set.
	app.set_creator_gender(1)
	await frames(6)
	await sweep("male")

	# An elder: 15 hair colours, which wraps to three swatch rows.
	app.set_creator_gender(0)
	app.set_creator_age("elder")
	await frames(8)
	await sweep("elder")

	# Every age stage the creator offers, on the Look tab where the styles and
	# palettes change length.
	for age: String in app.creator_age_stages():
		app.set_creator_age(age)
		await frames(6)
		app.set_creator_tab("Look")
		await frames(5)
		await inspect("age_" + age)
		await shot("age_" + age)

	print("CREATOR_CARD_RESULT ", JSON.stringify({"checks": checks, "failures": failures}))
	app.queue_free(); await frames(3)
	quit(0 if failures.is_empty() else 1)
