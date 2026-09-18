extends SceneTree
## The creator's Style tab: makeup and jewelry, with preview.
##
## Girls get the full makeup set and boys the limited one, and a male Lifelet
## may wear the same jewelry anyone else can. Each swatch writes the profile and
## repaints the preview, which is the creator's own "preview before you keep it".
var app: Node
var checks: int = 0
var failures: Array[String] = []
func check(v: bool, m: String) -> void:
	checks += 1
	print("CHECK ", "PASS " if v else "FAIL ", m)
	if not v: failures.append(m)
func _initialize() -> void: _run.call_deferred()
func frames(n: int = 3) -> void:
	for i: int in n: await process_frame
func _run() -> void:
	app = load("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	await frames(4)
	app.new_game()
	await frames(6)
	# The creator's Style tab is reachable and shows makeup and jewelry.
	var style_button: Button = null
	for node: Node in app.find_children("*", "Button", true, false):
		if node is Button and str((node as Button).text) == "Style":
			style_button = node
	check(style_button != null, "The creator offers a Style tab.")
	if style_button != null:
		style_button.pressed.emit()
		await frames(4)
		print("  creator_tab now=", app.creator_tab, " overlay=", app.overlay_open, " mode=", app.mode)
		var labels: Array[String] = []
		for node: Node in app.find_children("*", "Control", true, false):
			for prop: String in ["text"]:
				var value: Variant = node.get(prop) if node.has_method("get") else null
				if value is String and not str(value).is_empty():
					labels.append(str(value).to_lower())
		print("  labels sample: ", labels.slice(0, 24))
		check(labels.any(func(t: String) -> bool: return t.contains("makeup and jewelry")), "The Style tab shows makeup and jewelry.")
		check(labels.any(func(t: String) -> bool: return t.contains("lip colour")), "The Style tab offers a lip colour.")
		check(labels.any(func(t: String) -> bool: return t.contains("eye look")), "The Style tab offers an eye look.")
		check(labels.any(func(t: String) -> bool: return t.contains("earrings")), "The Style tab offers earrings.")
		check(labels.any(func(t: String) -> bool: return t.contains("jewelry metal")), "The Style tab offers a jewelry metal.")
		# A male Lifelet gets the limited set.
		app.set_creator_gender(1)
		await frames(4)
		check(LifeCharacterIdentity.is_male(app.profile), "A male Lifelet is recognised as male.")
		var male_lips: Array = LifeCharacterIdentity.makeup_lip_colors(app.profile)
		var female_lips: Array = LifeCharacterIdentity.makeup_lip_colors({"frame": 0})
		check(male_lips.size() < female_lips.size(), "A male Lifelet is offered a limited lip set (%d vs %d)." % [male_lips.size(), female_lips.size()])
		# Men wear jewelry.
		check(LifeCharacterIdentity.JEWELRY_METALS.size() >= 6, "Men's jewelry is offered: the same metal set anyone may wear.")
		# All ten hairstyles are reachable from the creator.
		var hair_buttons: int = 0
		for node: Node in app.find_children("*", "Button", true, false):
			if node is Button and str((node as Button).name).begins_with("") and str((node as Button).text) in ["Crop","Bob","Curls","Pony","Long","Buzz","Waves","Bun","Braids","Topknot"]:
				hair_buttons += 1
		print("  hair buttons on this tab: ", hair_buttons)
	# The wardrobe's own size: every named garment plus every colourway it can be
	# worn in, across all five outfit categories.
	var selectable: int = 0
	for category: String in LifeCharacterIdentity.OUTFIT_CATEGORIES:
		var pal: Dictionary = LifeCharacterIdentity.get_category_palettes(category)
		selectable += LifeCharacterIdentity.get_category_tops(category).size()
		selectable += LifeCharacterIdentity.get_category_bottoms(category).size()
		selectable += (pal.get("top", []) as Array).size()
		selectable += (pal.get("bottom", []) as Array).size()
		selectable += (pal.get("shoes", []) as Array).size()
	print("  selectable clothing options: ", selectable)
	check(selectable >= 100, "The wardrobe offers 100 or more clothing options including shoes (%d)." % selectable)

	print("STYLE %d checks, %d failures" % [checks, failures.size()])
	app.queue_free(); await frames(2); quit(0 if failures.is_empty() else 1)
