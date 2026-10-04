extends RefCounted
class_name LifeDrivingPanel
## The "Book a driving lesson" panel: how far the course has come (theory days,
## lessons, the day the course ends), a button for a lesson right now (only while
## lessons run), the three slots a lesson can be booked for, and the booking, if any.
## Every control only asks the Lifelet or the lesson controller; nothing here decides
## whether a lesson may happen.

const P = preload("res://scripts/palette.gd")
const School = preload("res://scripts/driving_school.gd")


static func show_panel(app: Node, member_id: String) -> void:
	app._begin_pause_overlay()
	var sim: LifeSim = app.household.member_sim(member_id)
	if sim == null:
		app.close_overlay()
		return
	var summary: Dictionary = sim.driving_summary()
	var first: String = str(sim.character.name).split(" ")[0]
	var options: Array = summary.options
	var booking: Dictionary = summary.booking
	var rows: int = options.size() + (1 if not booking.is_empty() else 0)
	var panel_height: float = 396.0 + float(rows) * 56.0
	var top: float = maxf(8.0, (900.0 - panel_height) * .5)
	var shade: ColorRect = ColorRect.new()
	shade.color = Color(.08, .17, .15, .28)
	app.rect(shade, Vector2(app.interface_local_x(0.0), 0), app.interface_size(), app.overlay)
	var backing: Panel = app.card(Vector2(428, top), Vector2(584, panel_height), P.WHITE, 24, app.overlay)
	backing.name = "DrivingPanel"
	app.small_caps("Juniper Driving School", Vector2(462, top + 20), Vector2(500, 23), app.overlay)
	app.text_label("Driving lessons", Vector2(460, top + 46), Vector2(510, 52), 36, P.INK, true, app.overlay)
	var progress: String = "Theory %d of %d days · Lessons %d of %d" % [int(summary.theory), int(summary.theory_needed), int(summary.lessons), int(summary.lessons_needed)]
	if int(summary.lessons) > 0: progress += "\nThe course ends on day %d." % int(summary.course_end_day)
	var status: Label = app.paragraph(progress, Vector2(464, top + 102), Vector2(520, 50), 16, P.INK, app.overlay)
	status.name = "DrivingProgress"
	var blocked: String = str(summary.lesson_error)
	var panel_blocked: String = str(summary.panel_error)
	var note: String = panel_blocked if not panel_blocked.is_empty() else (School.window_text() if not blocked.is_empty() and blocked == School.window_text() else (blocked if not blocked.is_empty() else "A blue car with L plates comes to the kerb. %s drives for an hour and a half, free." % first))
	app.paragraph(note, Vector2(464, top + 158), Vector2(520, 66), 14, P.MUTED, app.overlay).name = "DrivingNote"
	var now: Button = app.button("Have a lesson now", Vector2(462, top + 232), Vector2(520, 46), func() -> void: _now(app, member_id), true, app.overlay)
	now.name = "DrivingLessonNow"
	now.disabled = not blocked.is_empty()
	now.tooltip_text = blocked if not blocked.is_empty() else "The instructor's car comes to the kerb now."
	app.small_caps("Or book one", Vector2(464, top + 296), Vector2(300, 21), app.overlay)
	var y: float = top + 326.0
	if not booking.is_empty():
		var held: Label = app.text_label("Booked: %s at %s" % [_day_text(int(booking.day), sim.day), School.clock_text(float(booking.minutes))], Vector2(464, y + 6), Vector2(330, 30), 18, P.TEAL, true, app.overlay)
		held.name = "DrivingBooked"
		var cancel: Button = app.button("Cancel the booking", Vector2(800, y), Vector2(182, 42), func() -> void: _cancel(app, member_id), false, app.overlay)
		cancel.name = "DrivingBookCancel"
		y += 56.0
	for option: Dictionary in options:
		var label: String = "%s at %s · %s" % [str(option.label), School.clock_text(float(option.minutes)), _day_text(int(option.day), sim.day)]
		var pick: Button = app.button(label, Vector2(462, y), Vector2(520, 46), func() -> void: _book(app, member_id, int(option.day), float(option.minutes)), false, app.overlay)
		pick.name = "DrivingBook_" + str(option.id)
		pick.disabled = not panel_blocked.is_empty()
		pick.tooltip_text = "A lesson is held for you. It starts on time, and is given up if %s is not free within half an hour." % first
		y += 56.0
	if options.is_empty() and panel_blocked.is_empty(): app.paragraph("No slot is free in the next week.", Vector2(464, y), Vector2(520, 26), 14, P.MUTED, app.overlay)
	app.button("Back to life", Vector2(462, top + panel_height - 62), Vector2(520, 44), app.close_overlay, false, app.overlay)


static func _day_text(day: int, today: int) -> String:
	if day == today: return "today"
	if day == today + 1: return "tomorrow"
	return ("next " if day - today >= 7 else "") + LifeEducation.weekday_name(day)


static func _now(app: Node, member_id: String) -> void:
	app.close_overlay()
	# A learner who is only pottering about on their own gives that up for the lesson,
	# the way a booked one does; plans the player lined up are still asked about first.
	var sim: LifeSim = app.household.member_sim(member_id)
	var only_own: bool = sim != null and sim.action_queue.all(func(action: Dictionary) -> bool: return bool(action.get("autonomous", false)))
	var problem: String = app.driving_lesson.request(member_id, only_own)
	if not problem.is_empty(): app.show_notice(problem)
	else: app.refresh_hud()


static func _book(app: Node, member_id: String, day: int, minutes: float) -> void:
	var sim: LifeSim = app.household.member_sim(member_id)
	if sim == null: return
	var result: Dictionary = sim.book_driving_lesson(day, minutes)
	if not bool(result.ok): app.show_notice(str(result.error))
	show_panel(app, member_id)


static func _cancel(app: Node, member_id: String) -> void:
	var sim: LifeSim = app.household.member_sim(member_id)
	if sim != null and sim.cancel_driving_booking(): app.show_notice("The booking is cancelled.")
	show_panel(app, member_id)
