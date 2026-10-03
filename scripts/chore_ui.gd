extends RefCounted
## The player's side of household cleaning: the "Clean Home" entry on a housemate's
## wheel and on a Lifelet's own card, the compact HUD button with the home's percentage,
## and the panel with its four presets and a choice of what to clean. Every control only
## asks `LifeChoreFlow` to start a round; nothing here decides what gets cleaned.

const Defs = preload("res://scripts/chore_defs.gd")
const P = preload("res://scripts/palette.gd")
const URGENT_LABEL: String = "Spills, dishes and bins"
const PRESETS: Array = [
	["quick", "Quick tidy", "The worst of it, about an hour and a half at most"],
	["full", "Full clean", "Everything that has gathered any dirt, inside and out"],
	["inside", "Inside only", "Everything indoors"],
	["outside", "Outside only", "Entry, doors and window glass outside, while there is daylight"],
]


static func _title(label: String) -> String:
	var plain: String = label.substr(4) if label.begins_with("the ") else label
	return plain.substr(0, 1).to_upper() + plain.substr(1)


static func minutes_text(minutes: float) -> String:
	var whole: int = int(round(minutes))
	if whole < 60: return "%d min" % maxi(1, whole)
	var hours: int = whole / 60
	var rest: int = whole % 60
	return "%d h" % hours if rest == 0 else "%d h %02d" % [hours, rest]


# -------------------------------------------------------------- entry points

## The wheel entry for a housemate, or {} for anyone who is not part of the household.
static func wheel_entry(app: Node, member_id: String) -> Dictionary:
	var sim: LifeSim = app.household.member_sim(member_id)
	if sim == null or not is_instance_valid(app.chore_flow): return {}
	var flow: Node = app.chore_flow
	var reason: String = flow.start_error(sim)
	var quick: Dictionary = {}
	if reason.is_empty():
		quick = flow.preview(sim, "quick")
		if int(quick.count) == 0:
			# Nothing is dirty enough for a quick tidy: the time is that of the full clean, if it has anything.
			var full: Dictionary = flow.preview(sim, "full")
			if int(full.count) > 0: quick = full
			elif int(flow.preview(sim, "custom").count) == 0: reason = "Nothing needs cleaning right now."
	var first: String = flow.first_name(sim)
	return {"id": "clean_home", "label": "Clean Home", "cost": 0, "duration": int(float(quick.get("minutes", 60.0))) if int(quick.get("count", 0)) > 0 else 60, "available": reason.is_empty(), "unavailable_reason": reason,
		"description": "Ask %s to clean the home: floors, dust, windows, sinks, the bathroom and the front entry." % first}


## The "Clean Home…" button on a Lifelet's own card at `at`, wide as the card's buttons.
static func person_button(app: Node, at: Vector2, member_id: String) -> void:
	var entry: Dictionary = wheel_entry(app, member_id)
	if entry.is_empty(): return
	var b: Button = app.button("Clean Home…", at, Vector2(388, 34), func() -> void: show_panel(app, member_id), false, app.overlay)
	b.name = "CleanHome"
	b.disabled = not bool(entry.available)
	b.tooltip_text = str(entry.unavailable_reason) if not bool(entry.available) else str(entry.description)


static func hud_button(app: Node) -> Button:
	var b: Button = app.button("Clean Home", Vector2(476, 842), Vector2(126, 26), func() -> void: show_panel(app, app.bound_member_id), false)
	b.name = "CleanHomeHud"
	app.compact_button(b)
	return b


## Keep the HUD button's percentage and tooltip current; hidden where there is no home to clean.
static func refresh_hud(app: Node) -> void:
	# The HUD is rebuilt (build mode, venues) and takes the button with it: read the
	# reference as a plain Variant, which a freed button cannot make an error.
	var held: Variant = app.get("chore_hud_button")
	if not is_instance_valid(held): return
	var b: Button = held as Button
	var flow: Node = app.chore_flow
	var here: bool = app.mode == "live" and str(app.current_venue) == "home" and is_instance_valid(flow) and not flow.list.is_empty()
	b.visible = here
	if not here: return
	var score: int = int(round(flow.home_score()))
	b.text = "Clean Home · %d%%" % score
	var lines: Array = ["The home is %d%% clean. Click to choose what to clean." % score]
	var worst: Array = flow.worst(3)
	if worst.is_empty(): lines.append("Nothing is more than a little dusty.")
	else:
		lines.append("Needs attention:")
		for row: Dictionary in worst: lines.append("  %s: %d%% dirty" % [_title(str(row.label)), int(round(float(row.dirt)))])
	b.tooltip_text = "\n".join(lines)


# --------------------------------------------------------------------- panel

static func show_panel(app: Node, member_id: String) -> void:
	app._begin_pause_overlay()
	var sim: LifeSim = app.household.member_sim(member_id)
	var flow: Node = app.chore_flow
	if sim == null or not is_instance_valid(flow):
		app.close_overlay()
		return
	var first: String = flow.first_name(sim)
	var start_reason: String = flow.start_error(sim)
	var summary: Dictionary = flow.category_summary()
	var rows: Array = []
	var urgent: Dictionary = flow.preview(sim, "custom", [flow.URGENT])
	if int(urgent.count) > 0: rows.append({"id": flow.URGENT, "label": URGENT_LABEL, "dirt": 100.0, "count": int(urgent.count), "minutes": float(urgent.minutes)})
	for category: String in Defs.CATEGORY_ORDER:
		if not summary.has(category): continue
		var preview: Dictionary = flow.preview(sim, "custom", [category])
		rows.append({"id": category, "label": str(Defs.CATEGORY_LABELS[category]), "dirt": float(summary[category].dirt), "count": int(preview.count), "minutes": float(preview.minutes), "refused": preview.refused})
	var list_height: float = clampf(float(rows.size()) * 46.0, 92.0, 322.0)
	var panel_height: float = 372.0 + list_height
	var top: float = maxf(8.0, (900.0 - panel_height) * .5)
	var shade: ColorRect = ColorRect.new()
	shade.color = Color(.08, .17, .15, .28)
	app.rect(shade, Vector2(app.interface_local_x(0.0), 0), app.interface_size(), app.overlay)
	var backing: Panel = app.card(Vector2(338, top), Vector2(764, panel_height), P.WHITE, 24, app.overlay)
	backing.name = "CleanHomePanel"
	app.small_caps("A tidy home", Vector2(373, top + 20), Vector2(670, 23), app.overlay)
	app.text_label("Clean Home", Vector2(370, top + 48), Vector2(686, 52), 36, P.INK, true, app.overlay)
	var score: int = int(round(flow.home_score()))
	var headline: String = "The home is %d%% clean." % score
	var worst: Array = flow.worst(3)
	if not worst.is_empty():
		var names: Array = []
		for row: Dictionary in worst: names.append(str(row.label))
		headline += " %s would start with %s." % [first, ", ".join(names)]
	if not start_reason.is_empty(): headline = start_reason
	var status: Label = app.paragraph(headline, Vector2(374, top + 104), Vector2(686, 46), 15, P.MUTED, app.overlay)
	status.name = "CleanHomeStatus"
	# The four presets, each saying what it holds and how long it takes.
	for index: int in PRESETS.size():
		var preset: Array = PRESETS[index]
		var preview: Dictionary = flow.preview(sim, str(preset[0])) if start_reason.is_empty() else {"count": 0, "minutes": 0.0, "refused": {}, "night": 0}
		var count: int = int(preview.count)
		var label: String = "%s\n%s" % [str(preset[1]), ("%d tasks · %s" % [count, minutes_text(float(preview.minutes))]) if count > 0 else "nothing to do"]
		var b: Button = app.button(label, Vector2(371 + index * 174, top + 158), Vector2(166, 66), func() -> void: _start(app, member_id, str(preset[0]), []), index == 0, app.overlay)
		b.name = "CleanPreset_" + str(preset[0])
		b.disabled = count == 0 or not start_reason.is_empty()
		b.add_theme_font_size_override("font_size", 14)
		var why: String = str(preset[2])
		if not start_reason.is_empty(): why = start_reason
		elif count == 0:
			why = "Nothing here needs cleaning right now."
			if int(preview.get("night", 0)) > 0: why = "The outdoor jobs wait for daylight."
			for text: Variant in preview.refused: why = str(text); break
		else:
			var notes: Array = [why]
			for text: Variant in preview.refused: notes.append("%d skipped: %s" % [int(preview.refused[text]), str(text)])
			if int(preview.get("night", 0)) > 0: notes.append("%d outdoor jobs wait for daylight" % int(preview.night))
			why = "\n".join(notes)
		b.tooltip_text = why
	app.small_caps("Or choose what to clean", Vector2(373, top + 240), Vector2(500, 21), app.overlay)
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.name = "CleanHomeRows"
	app.rect(scroll, Vector2(371, top + 268), Vector2(692, list_height), app.overlay)
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	scroll.add_child(column)
	var boxes: Dictionary = {}
	var summary_label: Array = []
	for row: Dictionary in rows:
		var line: Control = Control.new()
		line.custom_minimum_size = Vector2(670, 40)
		column.add_child(line)
		app.card(Vector2.ZERO, Vector2(670, 40), Color("f3f4ed"), 10, line)
		var check: CheckBox = CheckBox.new()
		check.name = "CleanCat_" + str(row.id)
		check.button_pressed = float(row.dirt) >= Defs.GRUBBY and int(row.count) > 0
		check.disabled = int(row.count) == 0 or not start_reason.is_empty()
		for style_name: String in ["normal", "hover", "pressed", "focus", "disabled", "hover_pressed"]:
			check.add_theme_stylebox_override(style_name, StyleBoxEmpty.new())
		app.rect(check, Vector2(10, 7), Vector2(26, 26), line)
		boxes[str(row.id)] = {"box": check, "count": int(row.count), "minutes": float(row.minutes)}
		app.text_label(str(row.label), Vector2(46, 6), Vector2(300, 28), 17, P.INK, false, line)
		var detail: String = "%d%% dirty" % int(round(float(row.dirt))) if str(row.id) != str(flow.URGENT) else "needs attention"
		detail += " · %d task%s · %s" % [int(row.count), "" if int(row.count) == 1 else "s", minutes_text(float(row.minutes))] if int(row.count) > 0 else " · nothing to do"
		var detail_label: Label = app.text_label(detail, Vector2(300, 8), Vector2(360, 24), 13, P.MUTED, false, line)
		detail_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		for text: Variant in row.get("refused", {}):
			detail_label.tooltip_text = str(text); detail_label.mouse_filter = Control.MOUSE_FILTER_PASS; break
	var go: Button = app.button("Clean the selected", Vector2(371, top + panel_height - 62), Vector2(330, 44), func() -> void: _start(app, member_id, "custom", _chosen(boxes)), true, app.overlay)
	go.name = "CleanSelected"
	go.disabled = not start_reason.is_empty() or rows.is_empty()
	var tally: Label = app.text_label("", Vector2(712, top + panel_height - 56), Vector2(200, 34), 13, P.MUTED, false, app.overlay)
	tally.name = "CleanTally"
	var refresh: Callable = func() -> void:
		var count: int = 0
		var minutes: float = 0.0
		for key: String in boxes:
			if boxes[key].box.button_pressed: count += int(boxes[key].count); minutes += float(boxes[key].minutes)
		tally.text = "%d tasks · %s" % [count, minutes_text(minutes)] if count > 0 else "nothing chosen"
		go.disabled = count == 0 or not start_reason.is_empty()
	for key: String in boxes: boxes[key].box.toggled.connect(func(_on: bool) -> void: refresh.call())
	refresh.call()
	app.button("Back to life", Vector2(904, top + panel_height - 62), Vector2(158, 44), app.close_overlay, false, app.overlay)


static func _chosen(boxes: Dictionary) -> Array:
	var chosen: Array = []
	for key: String in boxes:
		if boxes[key].box.button_pressed: chosen.append(key)
	return chosen


static func _start(app: Node, member_id: String, mode: String, categories: Array) -> void:
	var flow: Node = app.chore_flow
	var result: Dictionary = flow.start(member_id, mode, categories)
	var sim: LifeSim = app.household.member_sim(member_id)
	app.close_overlay()
	if not bool(result.get("ok", false)):
		app.show_notice(str(result.get("error", "That cannot be cleaned right now.")))
		return
	app.show_notice("%s is cleaning the home: %d tasks, about %s." % [flow.first_name(sim), int(result.count), minutes_text(float(result.minutes))])
	app.refresh_hud()
