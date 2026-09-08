extends Control
## Live speech stays readable independently of camera zoom. The actor owns its
## words, voice and pause-aware lifetime; this layer only arranges presentation.
const P = preload("res://scripts/palette.gd")
var app: Node
var cards: Dictionary = {}
var connectors: Array = []

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = P.theme()

func _process(_delta: float) -> void:
	connectors.clear()
	if not is_instance_valid(app) or not is_instance_valid(app.world): return
	visible = app.mode == "live" and not app.overlay_open
	var active: Array = []
	var heads: Array[Rect2] = []
	var camera: Camera3D = app.world.camera
	var bounds: Rect2 = Rect2(Vector2(18, 96), Vector2(get_viewport_rect().size.x - 36, 594))
	var physical_scale: float = maxf(.5, get_viewport().get_screen_transform().get_scale().x)
	var text_scale: float = maxf(1.0, 1.0 / physical_scale)
	for id: String in app.world.actors:
		var actor: LifeActor = app.world.actors[id]
		if not is_instance_valid(actor): continue
		actor.screen_speech = true
		actor._speech.visible = false
		if not visible or not actor.is_visible_in_tree(): continue
		var head: Vector3 = actor.to_global(actor.get_portrait_center())
		if camera.is_position_behind(head): continue
		var anchor: Vector2 = camera.unproject_position(head)
		if not bounds.has_point(anchor): continue
		heads.append(Rect2(anchor - Vector2(23, 28), Vector2(46, 56)))
		var message: Dictionary = actor.speech_presentation()
		if message.is_empty(): continue
		active.append({"id": id, "actor": actor, "anchor": anchor, "message": message})
	active.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a.id == b.id: return false
		if a.id == app.household.selected_id(): return true
		if b.id == app.household.selected_id(): return false
		return str(a.id) < str(b.id))
	var occupied: Array[Rect2] = []
	for control: Node in app.ui.get_children():
		if control is Control and control.is_visible_in_tree():
			occupied.append(control.get_global_rect().grow(6))
	var retained: Array[String] = []
	for entry: Dictionary in active:
		var id: String = entry.id
		retained.append(id)
		var card: Panel = _card(id)
		var heading: Label = card.get_node("Speaker")
		var words: Label = card.get_node("Words")
		heading.text = str(entry.actor.get_meta("display_name", "Lifelet"))
		heading.add_theme_font_size_override("font_size", roundi(11 * text_scale))
		words.add_theme_font_size_override("font_size", roundi(16 * text_scale))
		words.text = entry.message.text
		var width: float = 216 * text_scale
		heading.position = Vector2(14, 9) * text_scale
		heading.size = Vector2(width - 28 * text_scale, 17 * text_scale)
		words.position = Vector2(14, 28) * text_scale
		words.size = Vector2(width - 28 * text_scale, 0)
		var height: float = maxf(24 * text_scale, words.get_minimum_size().y)
		words.size.y = height
		card.size = Vector2(width, height + 39 * text_scale)
		var placement: Rect2 = _place(entry.anchor, card.size, bounds, occupied, heads)
		card.visible = placement.has_area()
		if not card.visible: continue
		card.position = placement.position.round()
		occupied.append(placement.grow(7))
		var edge: Vector2 = Vector2(clampf(entry.anchor.x, placement.position.x + 12, placement.end.x - 12), clampf(entry.anchor.y, placement.position.y + 12, placement.end.y - 12))
		connectors.append({"from": edge, "to": Vector2(entry.anchor) - Vector2(0, 20)})
	for id: String in cards.keys():
		if id not in retained:
			cards[id].queue_free()
			cards.erase(id)
	queue_redraw()

func _card(id: String) -> Panel:
	if cards.has(id): return cards[id]
	var card := Panel.new()
	card.name = "Speech_" + id
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style: StyleBoxFlat = P.panel(P.WHITE, 14, P.LINE, 1)
	style.shadow_color = Color(0.12, 0.22, 0.18, .16)
	style.shadow_size = 4
	style.shadow_offset = Vector2(0, 3)
	card.add_theme_stylebox_override("panel", style)
	add_child(card)
	for label_name: String in ["Speaker", "Words"]:
		var label := Label.new()
		label.name = label_name
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if label_name == "Speaker":
			label.add_theme_color_override("font_color", P.TEAL)
			label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		else:
			label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		card.add_child(label)
	cards[id] = card
	return card

func _place(anchor: Vector2, extent: Vector2, bounds: Rect2, occupied: Array[Rect2], heads: Array[Rect2]) -> Rect2:
	# Prefer above the speaker, then nearby sides. Never cover another face or
	# overlap a prior bubble; omit excess crowd chatter when no clear spot fits.
	var offsets: Array[Vector2] = [Vector2(-extent.x / 2, -extent.y - 42), Vector2(42, -extent.y / 2 - 20), Vector2(-extent.x - 42, -extent.y / 2 - 20)]
	for lift: float in [70.0, 140.0]:
		offsets.append(Vector2(-extent.x / 2, -extent.y - 42 - lift))
		offsets.append(Vector2(42, -extent.y - lift))
		offsets.append(Vector2(-extent.x - 42, -extent.y - lift))
	for offset: Vector2 in offsets:
		var point: Vector2 = anchor + offset
		point.x = clampf(point.x, bounds.position.x, bounds.end.x - extent.x)
		var candidate := Rect2(point, extent)
		if not bounds.encloses(candidate): continue
		var blocked: bool = false
		for avoid: Rect2 in occupied + heads:
			if candidate.intersects(avoid): blocked = true; break
		if not blocked: return candidate
	return Rect2()

func _draw() -> void:
	for connector: Dictionary in connectors:
		draw_line(connector.from, connector.to, Color(P.TEAL, .55), 1.5, true)
		draw_circle(connector.to, 2.5, P.WHITE)
