extends SceneTree
## A hug is a physical embrace. The hugger walks up to the partner, both turn to
## face each other and step in until their chests meet, both wrap their arms
## round each other's backs (hands land on the back, not in thin air), hold, and
## let go. The partner is held in place, a moving partner is caught without the
## action ping-ponging, a neighbour returns the hug, and every way it can end
## (finished, cancelled, unreachable, timed out) leaves both bodies idle.
## Headless, through the real main scene (about two minutes).

var app: Node
var checks: int = 0
var failures: Array[String] = []

func check(value: bool, message: String) -> void:
	checks += 1
	print("CHECK ", "PASS " if value else "FAIL ", message)
	if not value:
		failures.append(message)
		push_error(message)

func _initialize() -> void:
	_run.call_deferred()

func step(count: int, delta: float = .05) -> void:
	for _i: int in range(count):
		app._process(delta)
		await process_frame

func until(condition: Callable, limit: int, delta: float = .05) -> bool:
	for _i: int in range(limit):
		if condition.call():
			return true
		app._process(delta)
		await process_frame
	return condition.call()

func phase() -> String:
	return str(app.sim.get_current_action().get("phase", ""))

func item_for(id: String) -> Dictionary:
	var actor: LifeActor = app.world.actors[id]
	return {"id": id, "kind": "neighbor", "label": str(actor.get_meta("display_name")), "node": actor, "size": Vector2(.6, .6)}

## Flat distance between the two bodies' model origins (where they really are
## drawn, after each has stepped in).
func drawn_gap(first: LifeActor, second: LifeActor) -> float:
	var a: Vector3 = first.visual.global_position
	var b: Vector3 = second.visual.global_position
	return Vector2(a.x - b.x, a.z - b.z).length()

## How the hugger's hands sit on the partner: in the partner's own model space, a
## hand on the back is behind the centre plane (z < 0), at shoulder-blade height.
func back_report(hugger: LifeActor, partner: LifeActor) -> Dictionary:
	var report: Dictionary = {"back": true, "reach": true, "detail": []}
	for side: String in ["L", "R"]:
		var palm: Vector3 = hugger.palm_world(side)
		var theirs: Vector3 = partner.visual.to_local(palm)
		var mine: Vector3 = hugger.visual.to_local(palm)
		var behind: bool = theirs.z < .03 and theirs.z > -.24
		var high: bool = theirs.y > partner._hip_height + .04 and theirs.y < partner.embrace_shoulder_height() + .16
		var wide: bool = absf(theirs.x) < .30
		if not (behind and high and wide):
			report.back = false
		if mine.z < .18:
			report.reach = false
		report.detail.append("%s partner-local (%.2f, %.2f, %.2f) own z %.2f" % [side, theirs.x, theirs.y, theirs.z, mine.z])
	return report

func facing_dot(from: LifeActor, to: LifeActor) -> float:
	var forward: Vector3 = Vector3(sin(from.rotation.y), 0, cos(from.rotation.y))
	var toward: Vector3 = to.position - from.position
	toward.y = 0.0
	return forward.dot(toward.normalized())

func idle_body(actor: LifeActor) -> bool:
	return not actor.is_embracing() and actor.visual.position.length() < .03 and absf(actor.visual.rotation.x) < .03

func reset_pair(a_at: Vector3, b_at: Vector3) -> void:
	app.traversal.cancel("player")
	app.traversal.cancel("housemate_1")
	for id: String in ["player", "housemate_1"]:
		app.world.actors[id].position = a_at if id == "player" else b_at
		app.world.actors[id].rotation.y = 0.0
	app.residents.publish_targets(true)
	app._refresh_sim_targets(false)

func _run() -> void:
	app = load("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	await process_frame
	await process_frame
	app.selected_lot = 0
	var second: Dictionary = app.household_profiles[0].duplicate(true)
	second["name"] = "Casey Vale"
	second["hair"] = 3
	app.household_profiles.append(second)
	app.start_household()
	await process_frame
	app.set_process(false)
	app.set_sound(false)
	for member: Dictionary in app.household.members:
		member.sim.autonomy = false
	check(app.household.members.size() == 2, "Two housemates start.")
	var sim: LifeSim = app.sim
	var partner_sim: LifeSim = app.household.member_sim("housemate_1")
	var hugger: LifeActor = app.world.actors["player"]
	var partner: LifeActor = app.world.actors["housemate_1"]
	# Keep the street and the neighbours out of the way of the front-lawn fixture.
	for id: String in ["maya", "leo", "priya", "tom"]:
		app.world.set_actor_away(id, true, true)
		app.residents.locations[app.current_venue][id].phase = "home"
		app.residents.locations[app.current_venue][id].wait = 999999.0
	app.household.speed = 1

	# ------------------------------------------------- a housemate on the lawn
	reset_pair(Vector3(-3.0, .16, 6.4), Vector3(.5, .16, 6.4))
	await step(2)
	var friendship_before: float = float(sim.relationships.housemate_1.friendship)
	var social_before: float = float(sim.needs.social)
	sim.needs.social = 30.0
	social_before = 30.0
	check(bool(sim.get_action_availability("hug", "housemate_1").available), "A hug is available between housemates.")
	app.queue_interaction(item_for("housemate_1"), "hug")
	await step(1)
	check(str(sim.get_current_action().get("id", "")) == "hug" and phase() == "approach", "The hug is queued and the hugger sets off.")
	var began: bool = await until(func() -> bool: return phase() == "active", 900)
	check(began, "The hugger walks up and the hug begins.")
	var standing: float = Vector2(hugger.position.x - partner.position.x, hugger.position.z - partner.position.z).length()
	check(standing >= LifeTraversal.ROUTE_CLEARANCE - .001 and standing <= 1.6, "The hugger arrives at conversation range (%.2f m) rather than hugging from across the room." % standing)
	await step(10)
	check(app.embrace.holds("housemate_1") and app.embrace.posed("housemate_1"), "The partner is held for the embrace and returns it.")
	# Mid-hug: chests together, arms round the back.
	var mid: bool = await until(func() -> bool: return float(sim.get_current_action().get("elapsed", 0.0)) >= float(sim.get_current_action().get("duration", 15.0)) * .5, 900)
	check(mid, "The hug reaches its middle.")
	await step(4)
	var gap: float = drawn_gap(hugger, partner)
	check(gap >= .20 and gap <= .42, "Mid-hug the two bodies are %.2f m apart, chest to chest (from %.2f m at the start)." % [gap, standing])
	check(facing_dot(hugger, partner) > .95 and facing_dot(partner, hugger) > .95, "Both face each other (%.2f, %.2f)." % [facing_dot(hugger, partner), facing_dot(partner, hugger)])
	check(hugger.is_embracing() and partner.is_embracing(), "Both bodies are in the embrace pose.")
	for pair: Array in [[hugger, partner, "The hugger's"], [partner, hugger, "The partner's"]]:
		var report: Dictionary = back_report(pair[0], pair[1])
		check(bool(report.back), "%s hands are on the other's back, not in thin air (%s)." % [pair[2], "; ".join(report.detail)])
		check(bool(report.reach), "%s arms are reaching round, not hanging (%s)." % [pair[2], "; ".join(report.detail)])
	var held_position: Vector3 = partner.position
	await step(20)
	check(partner.position.distance_to(held_position) < .001 and hugger.position.distance_to(Vector3(-3.0, .16, 6.4)) > .5, "Neither body wanders during the hold.")
	var done: bool = await until(func() -> bool: return sim.action_queue.is_empty(), 1500)
	check(done, "The hug completes.")
	check(float(sim.relationships.housemate_1.friendship) > friendship_before and float(sim.needs.social) > social_before, "The hug pays its Social and friendship as before.")
	await step(40)
	check(idle_body(hugger) and idle_body(partner), "Both bodies are idle again: no pose, no leftover lean or offset.")
	check(not app.embrace.holds("housemate_1") and not app.embrace.posed("housemate_1"), "The partner is released.")
	check(hugger.position.distance_to(partner.position) >= LifeTraversal.ROUTE_CLEARANCE - .01, "The bodies are back at their standing distance (%.2f m)." % hugger.position.distance_to(partner.position))
	await step(10)
	partner_sim.autonomy = false

	# ----------------------------------- a partner who is walking away is caught
	reset_pair(Vector3(-3.0, .16, 6.4), Vector3(0.0, .16, 6.4))
	await step(2)
	sim.last_hugs.clear()
	app.select_household_member(1)
	app.on_ground_clicked(Vector3(5.5, .16, 6.4))
	await step(2)
	app.select_household_member(0)
	check(app.traversal.busy("housemate_1") or not app.motion_states["housemate_1"].path.is_empty() or app.traversal.active("housemate_1"), "The housemate is on their way somewhere.")
	app.queue_interaction(item_for("housemate_1"), "hug")
	var flips: int = 0
	var last_phase: String = ""
	var active_seen: bool = false
	for _i: int in range(2400):
		app._process(.05)
		await process_frame
		var current: String = phase()
		if current != last_phase:
			if last_phase == "active" and current == "approach":
				flips += 1
			last_phase = current
		if current == "active":
			active_seen = true
		if active_seen and sim.action_queue.is_empty():
			break
	check(active_seen, "A housemate who was walking away is caught and hugged.")
	check(flips == 0, "The hug never flips back to approaching once it has begun (%d flips)." % flips)
	check(sim.action_queue.is_empty(), "That hug also completes.")
	await step(20)
	partner_sim.autonomy = false
	check(not app.embrace.holds("housemate_1"), "The walker is released after the hug.")
	check(idle_body(hugger) and idle_body(partner), "Both bodies are idle after the caught hug.")
	# Arms and posture are back to the ordinary standing pose.
	check(not partner.is_embracing() and not hugger.is_embracing(), "Nobody is left embracing.")

	# --------------------------------------------- a neighbour returns the hug
	app.world.set_actor_away("maya", false, false)
	app.residents.locations[app.current_venue]["maya"].phase = "walking"
	app.residents.locations[app.current_venue]["maya"].wait = 999999.0
	var maya: LifeActor = app.world.actors["maya"]
	reset_pair(Vector3(-3.0, .16, 6.4), Vector3(5.0, .16, 4.5))
	maya.position = Vector3(-1.0, .16, 6.4)
	app.residents.locations[app.current_venue]["maya"].position = [-1.0, .16, 6.4]
	app.residents.publish_targets(true)
	app._refresh_sim_targets(false)
	await step(2)
	sim.last_hugs.clear()
	sim.needs.social = 30.0
	app.queue_interaction(item_for("maya"), "hug")
	var maya_began: bool = await until(func() -> bool: return phase() == "active", 1200)
	check(maya_began, "The hugger reaches Maya.")
	await until(func() -> bool: return float(sim.get_current_action().get("elapsed", 0.0)) >= float(sim.get_current_action().get("duration", 15.0)) * .45, 900)
	await step(4)
	var maya_gap: float = drawn_gap(hugger, maya)
	check(maya.is_embracing() and hugger.is_embracing(), "Maya returns the hug with her own body.")
	check(maya_gap >= .20 and maya_gap <= .42, "The hugger and Maya stand %.2f m apart, chest to chest (roots %.2f m apart, offsets %s / %s)." % [maya_gap, hugger.position.distance_to(maya.position), str(hugger.visual.position), str(maya.visual.position)])
	for pair: Array in [[hugger, maya, "The hugger's"], [maya, hugger, "Maya's"]]:
		var report: Dictionary = back_report(pair[0], pair[1])
		check(bool(report.back), "%s hands are on the other's back (%s)." % [pair[2], "; ".join(report.detail)])
	var maya_done: bool = await until(func() -> bool: return sim.action_queue.is_empty(), 1500)
	check(maya_done, "The hug with Maya completes.")
	await step(40)
	check(idle_body(hugger) and idle_body(maya), "Both are idle afterwards.")
	app.world.set_actor_away("maya", true, true)
	app.residents.locations[app.current_venue]["maya"].phase = "home"

	# ---------------------------------------------------- a child and an adult
	# A child's arms only reach an adult's waist and an adult stoops: the pose
	# adapts to the different heights rather than reaching into empty air.
	var child_profile: Dictionary = {"name": "Kit", "age_stage": "child", "low_detail": true}
	var kid := LifeActor.new()
	root.add_child(kid)
	kid.configure(child_profile)
	kid.voice_enabled = false
	var grownup := LifeActor.new()
	root.add_child(grownup)
	grownup.configure({"name": "Ari", "age_stage": "adult", "low_detail": true})
	grownup.voice_enabled = false
	kid.position = Vector3(20, 0, 20)
	grownup.position = Vector3(20, 0, 21.0)
	grownup.rotation.y = PI
	for _i: int in range(150):
		kid.set_embrace(grownup.position, true, .5, grownup.get_display_height(), grownup.embrace_depth(), grownup)
		grownup.set_embrace(kid.position, true, .5, kid.get_display_height(), kid.embrace_depth(), kid)
		kid.animate(1.0 / 60.0, 1.0, false, "hug")
		grownup.animate(1.0 / 60.0, 1.0, false, "hug")
	var kid_report: Dictionary = back_report(kid, grownup)
	var adult_report: Dictionary = back_report(grownup, kid)
	check(bool(kid_report.reach) and bool(adult_report.reach), "A child and an adult both reach round each other (%s | %s)." % ["; ".join(kid_report.detail), "; ".join(adult_report.detail)])
	var child_gap: float = drawn_gap(kid, grownup)
	check(child_gap >= .20 and child_gap <= .56, "A child and an adult meet %.2f m apart (the adult crouches to the child's level)." % child_gap)
	kid.queue_free()
	grownup.queue_free()

	# ------------------------------------------------------- never a freeze
	# A partner who cannot be reached refuses with a notice and the queue clears.
	reset_pair(Vector3(-3.0, .16, 6.4), Vector3(0.0, .16, 6.4))
	await step(2)
	sim.last_hugs.clear()
	partner.position = Vector3(0, 6.16, 0)
	app.residents.publish_targets(true)
	app.queue_interaction(item_for("housemate_1"), "hug")
	await step(30)
	check(sim.action_queue.is_empty() and not app.embrace.holds("housemate_1"), "A hug that cannot be reached is cancelled rather than left hanging.")
	reset_pair(Vector3(-3.0, .16, 6.4), Vector3(.5, .16, 6.4))
	await step(2)
	# An approach that has gone on too long is given up by the controller.
	sim.last_hugs.clear()
	app.queue_interaction(item_for("housemate_1"), "hug")
	await step(2)
	check(phase() == "approach", "The hugger is on the way.")
	app.embrace._approach["player"] = LifeEmbrace.APPROACH_LIMIT + 1.0
	await step(6)
	check(sim.action_queue.is_empty(), "An approach that has taken too long is cancelled with a notice.")
	# Cancelling mid-embrace lets go at once and leaves nobody posed or held.
	reset_pair(Vector3(-3.0, .16, 6.4), Vector3(.5, .16, 6.4))
	await step(2)
	sim.last_hugs.clear()
	app.queue_interaction(item_for("housemate_1"), "hug")
	var second_began: bool = await until(func() -> bool: return phase() == "active", 900)
	await step(120)
	check(second_began and hugger.is_embracing() and partner.is_embracing(), "The second hug is in full embrace.")
	app.cancel_current_action()
	await step(40)
	check(sim.action_queue.is_empty() and not hugger.is_embracing() and not partner.is_embracing() and not app.embrace.holds("housemate_1"), "Cancelling lets go of the hug at once.")
	check(idle_body(hugger) and idle_body(partner), "Both bodies settle back to standing after a cancelled hug.")
	# A partner who is asleep or washing is not hugged; a free one is.
	check(app.embrace.refusal("housemate_1").is_empty(), "A free housemate raises no objection to a hug.")
	partner_sim.action_queue.append({"id": "sleep", "phase": "active"})
	check(app.embrace.refusal("housemate_1").contains("busy"), "A sleeping housemate is not hugged (%s)." % app.embrace.refusal("housemate_1"))
	partner_sim.action_queue.pop_back()

	print("HUG %d checks, %d failures" % [checks, failures.size()])
	app.queue_free()
	await process_frame
	quit(1 if not failures.is_empty() else 0)
