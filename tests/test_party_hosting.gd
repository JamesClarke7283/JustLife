extends "res://tests/test_multi_guest_visits.gd"
## Hosting a party: People -> "Host a party..." opens the planner card, sending it asks
## the chosen friends over a few minutes apart, a friend with a dish makes it first and
## sets it on the table as shared servings, the party record and its music, status card
## and guests' choices follow the party until it ends, a save in the middle brings all of
## it back, and saves that lie are refused. A party for someone with a waiting birthday
## holds the cake for the guests, who then sing with the family.
##
## A visitor suite: it only runs in a plugin-free copy (tests/run_home_visits.py builds one).
var flow: LifePartyFlow


func _first_of(kind: String) -> Dictionary:
	for item: Dictionary in app.world.items:
		if str(item.kind) == kind: return item
	return {}

func _party() -> Dictionary: return app.household.party
func _entry(id: String) -> Dictionary: return LifePartyPlan.guest_entry(app.household.party, id)
func _clock() -> float: return app.residents.home_visit._now()

## A fresh game on the bigger starter home, with a child for the birthday scene.
func _boot(profiles: Array, minutes: float = 600.0, tidy: bool = true) -> void:
	if is_instance_valid(app):
		app.queue_free()
		await process_frame
	app = MainScene.instantiate()
	root.add_child(app)
	for index: int in 4: await process_frame
	app.set_sound(false)
	app.household_profiles = profiles
	app.selected_lot = maxi(0, LifeProperties.starters_for(app.household_profiles).find("willow"))
	app.creator_family_links = []
	app.start_household()
	for index: int in 6: await process_frame
	app.set_process(false)
	app.household.set_speed(0)
	app.household.day = 1
	app.household.minutes = minutes
	for member: Dictionary in app.household.members:
		member.sim.day = 1
		member.sim.minutes = minutes
		member.sim.autonomy = false
		member.sim.set_aging("normal", false)
		member.sim.household_bills_enabled = false
		member.sim.wants.clear()
		for need: String in LifeSim.NEED_NAMES: member.sim.needs[need] = 85.0
		for id: String in FRIENDS_ALL:
			if member.sim.relationships.has(id): member.sim.relationships[id].friendship = 45
	flow = app.party_flow
	# The household starts close to the front door; a party's guests need the hall, so the
	# household waits in the bedrooms, as a host who is out of the way would.
	var waiting: Array[Vector2] = [Vector2(4.6, 3.0), Vector2(4.6, -1.0), Vector2(3.0, -1.2), Vector2(4.6, 1.0)]
	for index: int in app.household.members.size() if tidy else 0:
		var at: Vector3 = app.world.nearest_clear_point(Vector3(waiting[index % waiting.size()].x, .16, waiting[index % waiting.size()].y), 0)
		if at.is_finite(): app.world.actors[str(app.household.members[index].id)].position = at
	app._store_motion()

const FRIENDS_ALL: Array[String] = ["maya", "leo", "priya"]

## Run frames until `done` says so; a real frame now and then lets deferred calls happen.
func _until_done(done: Callable, limit: int = 6000) -> bool:
	for index: int in limit:
		app._process(.05)
		if index % 25 == 0: await process_frame
		if done.call(): return true
	return false

## A 3D speaker takes up a pause only after the physics frame that starts it, so a check of
## the speaker waits a few frames after changing anything.
func _settle() -> void:
	for index: int in 3: await process_frame
	app.party_music.tick(.05)

func _press(name: String) -> bool:
	var found: Node = app.overlay.find_child(name, true, false)
	if not found is Button or (found as Button).disabled: return false
	(found as Button).pressed.emit()
	return true

func _tick(name: String, on: bool) -> bool:
	var found: Node = app.overlay.find_child(name, true, false)
	if not found is BaseButton or (found as BaseButton).disabled: return false
	(found as BaseButton).button_pressed = on
	return true

func _text_of(name: String, root_node: Node = null) -> String:
	var scope: Node = root_node if root_node != null else app
	var found: Node = scope.find_child(name, true, false)
	return str((found as Label).text) if found is Label else ""


func _run() -> void:
	# PARTY_ONLY picks one part while a test is being written: rules, main, end or birthday.
	var only: String = OS.get_environment("PARTY_ONLY")
	if only.is_empty() or only == "rules": _rules()
	if only.is_empty() or only == "main":
		await _boot([{"name": "Ada Vale", "age_stage": "adult", "traits": []}, {"name": "Ben Vale", "age_stage": "adult", "traits": []}])
		await _planner_and_party()
	if only.is_empty() or only == "end": await _early_end()
	if only.is_empty() or only == "birthday": await _birthday_party()
	if only.is_empty() or only == "door": await _held_at_the_door()
	if not is_instance_valid(app):
		app = MainScene.instantiate()
		root.add_child(app)
	await _finish()


## ---- The rules on their own

func _rules() -> void:
	check(LifePartyPlan.MAX_HOURS == 5 and LifePartyPlan.MAX_GUESTS == 4 and LifePartyPlan.MIN_HOURS == 1, "A party runs one to five hours with up to four friends")
	check(LifePartyPlan.clamp_hours(9) == 5 and LifePartyPlan.clamp_hours(0) == 1 and LifePartyPlan.clamp_hours(3) == 3 and LifePartyPlan.clamp_hours("long") == 5, "The hours are kept between one and five")
	var all_known: bool = true
	for id: String in LifeResidentCatalogue.IDS:
		if LifePartyPlan.potluck_recipe(id).is_empty() or not LifeMeals.RECIPES.has(LifePartyPlan.potluck_recipe(id)): all_known = false
	check(all_known and LifePartyPlan.potluck_recipe("maya") == "garden_salad" and LifePartyPlan.potluck_label("maya") == "garden fresh salad" and LifePartyPlan.potluck_recipe("nobody").is_empty(), "Every neighbor has a dish that is an ordinary recipe")
	check(not LifePartyPlan.window_open(419.0) and LifePartyPlan.window_open(420.0) and LifePartyPlan.window_open(1320.0) and not LifePartyPlan.window_open(1321.0), "Parties are thrown between 07:00 and 22:00")
	check(LifePartyPlan.guest_error("maya", {"friendly": true}).is_empty() and not LifePartyPlan.guest_error("maya", {"friendly": false}).is_empty() and not LifePartyPlan.guest_error("maya", {"friendly": true, "visiting": true}).is_empty() and not LifePartyPlan.guest_error("maya", {"friendly": true, "moved_in": true}).is_empty() and not LifePartyPlan.guest_error("zed", {"friendly": true}).is_empty(), "A neighbor needs 20 friendship and must not be visiting or living here")
	var good: Dictionary = {"party_on": false, "at_home": true, "minutes": 600.0, "guests": ["maya", "leo"], "errors": {}}
	check(LifePartyPlan.send_error(good).is_empty(), "A party with two friends in the morning can be sent")
	check(not LifePartyPlan.send_error(good.merged({"party_on": true}, true)).is_empty() and not LifePartyPlan.send_error(good.merged({"at_home": false}, true)).is_empty() and not LifePartyPlan.send_error(good.merged({"minutes": 1400.0}, true)).is_empty() and not LifePartyPlan.send_error(good.merged({"minutes": 120.0}, true)).is_empty() and not LifePartyPlan.send_error(good.merged({"guests": []}, true)).is_empty() and not LifePartyPlan.send_error(good.merged({"guests": ["maya", "leo", "priya", "tom", "maya"]}, true)).is_empty(), "A second party, being away, a late or early hour, no guests and five guests are refused")
	check("late" in LifePartyPlan.send_error(good.merged({"minutes": 1400.0}, true)) and "Maya" in LifePartyPlan.send_error(good.merged({"errors": {"maya": "They are already visiting."}}, true)), "The reasons name the problem")
	var built: Dictionary = LifePartyPlan.build(3, "player", "kit", 1000.0, 9, true, [{"id": "maya", "potluck": true}, {"id": "leo", "potluck": false}, {"id": "tom", "potluck": true}])
	check(int(built.hours) == 5 and is_equal_approx(float(built.ends_at) - float(built.started_at), 300.0) and str(built.phase) == "inviting" and int(built.serial) == 3, "A party asked to run nine hours runs five")
	var maya: Dictionary = LifePartyPlan.guest_entry(built, "maya")
	var leo: Dictionary = LifePartyPlan.guest_entry(built, "leo")
	var tom: Dictionary = LifePartyPlan.guest_entry(built, "tom")
	check(is_equal_approx(float(maya.depart_at), 1000.0 + LifePartyPlan.POTLUCK_PREP) and is_equal_approx(float(leo.depart_at), 1000.0 + LifePartyPlan.ARRIVAL_STAGGER) and is_equal_approx(float(tom.depart_at), 1000.0 + 2.0 * LifePartyPlan.ARRIVAL_STAGGER + LifePartyPlan.POTLUCK_PREP), "Friends set off a few minutes apart, and twenty minutes later when bringing a dish")
	check(str(maya.potluck) == "garden_salad" and str(leo.potluck).is_empty() and bool(leo.brought) and not bool(maya.brought) and str(tom.potluck) == "herb_pasta", "Only the friends who bring a dish have one to set down")
	check(LifePartyPlan.decor_fun(0) == 0 and LifePartyPlan.decor_fun(1) == LifePartyPlan.FUN_FESTIVE and LifePartyPlan.decor_fun(2) == LifePartyPlan.FUN_FESTIVE and LifePartyPlan.decor_fun(3) == LifePartyPlan.FUN_VERY_FESTIVE, "A decorated home lifts the guests: more for a very festive one")
	check(is_equal_approx(LifePartyPlan.friendship_gain(false), 6.0) and is_equal_approx(LifePartyPlan.friendship_gain(true), 9.0), "A party earns six friendship, nine when the dish was eaten")
	check(LifePartyPlan.clock_text(1000.0) == "16:40" and LifePartyPlan.clock_text(1440.0 + 90.0) == "01:30", "Times of day read as a clock")
	var party: Dictionary = built.duplicate(true)
	party.celebrant_id = "kit"
	party.started_at = 1000.0
	check(LifePartyPlan.ritual_waits(party, "kit", 1010.0) and not LifePartyPlan.ritual_waits(party, "ada", 1010.0) and not LifePartyPlan.ritual_waits(party, "kit", 1000.0 + LifePartyPlan.RITUAL_WAIT), "The cake waits for the guests, but only for the birthday person, and not beyond an hour")
	LifePartyPlan.guest_entry(party, "maya").status = "inside"
	LifePartyPlan.guest_entry(party, "leo").status = "inside"
	LifePartyPlan.guest_entry(party, "tom").status = "inside"
	check(not LifePartyPlan.ritual_waits(party, "kit", 1010.0), "...and no longer once the guests are all in")
	# validation on a made-up save
	var stub: Dictionary = {"day": 1, "minutes": 1020.0, "party_serial": 3, "members": [{"id": "player"}, {"id": "kit"}], "resident_members": {}, "meals": {"batches": []}}
	var valid: Dictionary = LifePartyPlan.build(3, "player", "kit", 1000.0, 3, true, [{"id": "maya", "potluck": true}, {"id": "leo", "potluck": false}])
	check(LifePartyPlan.validate(valid, stub).is_empty() and LifePartyPlan.validate({}, stub).is_empty() and LifePartyPlan.validate(null, stub).is_empty(), "A fresh party, and none, are believed")
	var refused: Dictionary = {
		"duration of 400 minutes": func(p: Dictionary) -> void: p.ends_at = float(p.started_at) + 400.0,
		"no duration": func(p: Dictionary) -> void: p.ends_at = p.started_at,
		"unknown guest": func(p: Dictionary) -> void: p.guests[0].id = "stranger",
		"duplicate guest": func(p: Dictionary) -> void: p.guests[1].id = "maya",
		"no guests": func(p: Dictionary) -> void: p.guests = [],
		"five guests": func(p: Dictionary) -> void: p.guests = [p.guests[0], p.guests[1], p.guests[0].duplicate(true), p.guests[0].duplicate(true), p.guests[0].duplicate(true)],
		"unknown dish": func(p: Dictionary) -> void: p.guests[0].potluck = "moon_pie",
		"dish with no friend to bring it": func(p: Dictionary) -> void: p.guests[1].batch = "meal_9",
		"a bad phase": func(p: Dictionary) -> void: p.phase = "dancing",
		"host outside the household": func(p: Dictionary) -> void: p.host_id = "stranger",
		"celebrant outside the household": func(p: Dictionary) -> void: p.celebrant_id = "stranger",
		"hours of six": func(p: Dictionary) -> void: p.hours = 6,
		"a party from the future": func(p: Dictionary) -> void: p.started_at = 99999.0,
		"a number from nowhere": func(p: Dictionary) -> void: p.serial = 9,
		"a guest inside before it began": func(p: Dictionary) -> void:
			p.guests[0].status = "inside"
			p.guests[0].came = true,
		"a guest inside who never came": func(p: Dictionary) -> void:
			p.phase = "active"
			p.guests[0].status = "inside",
		"music that is not on or off": func(p: Dictionary) -> void: p.music = "loud",
	}
	for label: String in refused:
		var copy: Dictionary = valid.duplicate(true)
		refused[label].call(copy)
		check(not LifePartyPlan.validate(copy, stub).is_empty(), "A saved party with " + label + " is refused")
	var moved: Dictionary = stub.duplicate(true)
	moved.resident_members = {"maya": "player"}
	check(not LifePartyPlan.validate(valid, moved).is_empty(), "A guest who lives in the household is refused")
	var stray: Dictionary = stub.duplicate(true)
	stray.party_serial = 1
	check(not LifePartyPlan.validate(valid, stray).is_empty() and not LifePartyPlan.validate(null, {"party_serial": -2}).is_empty(), "A party number past the counter, or a bad counter, is refused")
	var dish_ok: Dictionary = valid.duplicate(true)
	dish_ok.guests[0].batch = "meal_4"
	dish_ok.guests[0].brought = true
	var with_dish: Dictionary = stub.duplicate(true)
	with_dish.meals.batches = [{"id": "meal_4", "brought_by": "maya"}]
	check(LifePartyPlan.validate(dish_ok, with_dish).is_empty() and not LifePartyPlan.validate(dish_ok, stub).is_empty(), "A dish the friend set out must be in the meal ledger as theirs")
	with_dish.meals.batches = [{"id": "meal_4", "brought_by": "leo"}]
	check(not LifePartyPlan.validate(dish_ok, with_dish).is_empty(), "...and not as another friend's")
	var late_birthday: Dictionary = stub.duplicate(true)
	late_birthday.celebrations = {"pending": [{"party_serial": 7}]}
	check(not LifePartyPlan.validate(null, late_birthday).is_empty(), "A birthday that names a party never held is refused")
	check(LifePartyPlan.owns({"id": "bring_dish"}) and LifePartyPlan.owns({"id": "dance"}) and not LifePartyPlan.owns({"id": "relax"}), "The party names its own guest actions")


## ---- A whole party

func _planner_and_party() -> void:
	var host_id: String = app.household.selected_id()
	var residents: LifeResidents = app.residents
	app.household.minutes = 600.0
	check(flow.host_reason().is_empty() and not flow.active() and not app.party_on(), "With friends and a morning free, a party can be hosted")
	# the People panel
	app.show_relationships()
	var host_button: Button = app.overlay.find_child("HostParty", true, false)
	check(is_instance_valid(host_button) and not host_button.disabled and host_button.text == "Host a party…", "People offers a Host a party button")
	var tree_button: Button = app.overlay.find_child("FamilyTree", true, false)
	var back_buttons: Array = app.overlay.find_children("*", "Button", true, false).filter(func(b: Node) -> bool: return (b as Button).text == "Back to life")
	check(is_instance_valid(tree_button) and back_buttons.size() == 1 and host_button.position.x > tree_button.position.x and (back_buttons[0] as Button).position.x > host_button.position.x and (back_buttons[0] as Button).position.x + (back_buttons[0] as Button).size.x <= 984.0, "The three bottom buttons sit side by side inside the card")
	if not is_instance_valid(host_button):
		return
	# a decorated table: the planner says so, and so do the guests
	var table: Dictionary = _first_of("dining")
	check(not table.is_empty() and PartyDecor_apply(table), "A tablecloth makes the home festive")
	host_button.pressed.emit()
	var planner_card: Node = app.overlay.find_child("PartyPlanner", true, false)
	check(is_instance_valid(planner_card), "Host a party opens the planner card")
	check(is_instance_valid(app.overlay.find_child("PartyCelebrant", true, false)) and is_instance_valid(app.overlay.find_child("PartyHoursLess", true, false)) and is_instance_valid(app.overlay.find_child("PartyMusic", true, false)) and is_instance_valid(app.overlay.find_child("PartySend", true, false)), "The card has the celebrant list, hours stepper, music switch and Send")
	for id: String in LifeResidentCatalogue.IDS:
		check(is_instance_valid(app.overlay.find_child("PartyInvite_" + id, true, false)) and is_instance_valid(app.overlay.find_child("PartyPotluck_" + id, true, false)), "The card has an invitation and a dish box for " + id)
	check(app.overlay.find_child("PartyInvite_tom", true, false).disabled and "20 friendship" in app.overlay.find_child("PartyInvite_tom", true, false).tooltip_text, "A neighbor who is not yet a friend cannot be asked, and the card says why")
	check(app.overlay.find_child("PartyPotluck_maya", true, false).disabled, "A dish cannot be ticked before the friend is invited")
	check(app.overlay.find_child("PartySend", true, false).disabled and "friends" in _text_of("PartySummary", app.overlay), "Sending waits until someone is chosen")
	check("1 festive touch" in _text_of("PartyDecor", app.overlay), "The card counts the home's festive touches (%s)" % _text_of("PartyDecor", app.overlay))
	check(_text_of("PartyHours", app.overlay) == "5 hours", "Five hours is the default")
	_press("PartyHoursLess")
	_press("PartyHoursLess")
	check(_text_of("PartyHours", app.overlay) == "3 hours", "The stepper counts down")
	for index: int in 6: _press("PartyHoursMore")
	check(_text_of("PartyHours", app.overlay) == "5 hours" and app.overlay.find_child("PartyHoursMore", true, false).disabled, "...and stops at five")
	_press("PartyHoursLess")
	_press("PartyHoursLess")
	check(_tick("PartyInvite_maya", true) and _tick("PartyPotluck_maya", true) and _tick("PartyInvite_leo", true), "Two friends are ticked, one bringing a dish")
	check(not app.overlay.find_child("PartyPotluck_maya", true, false).disabled and "Maya" in _text_of("PartySummary", app.overlay) and "1 friend is bringing a dish" in _text_of("PartySummary", app.overlay), "The card sums it up (%s)" % _text_of("PartySummary", app.overlay))
	check("garden fresh salad" in app.overlay.find_child("PartyPotluck_maya", true, false).text, "A dish box names the dish")
	var funds: int = app.household.funds
	var now_at_send: float = _clock()
	check(_press("PartySend"), "Send invitations")
	check(flow.active() and app.party_on() and app.household.party_serial == 1 and not app.overlay_open, "The party record is written and the card closes")
	var party: Dictionary = _party()
	check(int(party.serial) == 1 and str(party.host_id) == host_id and is_equal_approx(float(party.ends_at) - float(party.started_at), 180.0) and int(party.hours) == 3 and bool(party.music) and party.guests.size() == 2, "The party runs three hours with two guests")
	check(str(_entry("maya").potluck) == "garden_salad" and str(_entry("leo").potluck).is_empty() and str(_entry("maya").status) == "preparing", "Maya is making her salad")
	check(app.household.funds == funds, "Hosting costs nothing")
	check(flow.notices.any(func(n: String) -> bool: return "Maya is making garden fresh salad" in n), "The player is told Maya is making a dish")
	var frozen: Dictionary = _facts()
	check(not residents.begin_trip("park") and app.mode == "live", "Travel waits for the party, even before anyone has arrived")
	app.set_build_mode(true)
	check(app.mode == "live", "...and so does building")
	check(not residents.home_visit.requirement("tom").is_empty() and not residents.home_visit.invite("tom"), "An ordinary invitation waits while the party is on")
	# friends set off in turn
	app.household.set_speed(8)
	check(await _until_done(func() -> bool: return residents.party_visits.size() >= 1, 400), "Leo sets off first, six minutes in")
	check(_visit("leo").owns("leo") and str(_entry("leo").status) == "walking" and residents.party_visits.size() == 1 and _clock() - now_at_send >= LifePartyPlan.ARRIVAL_STAGGER - 1.0, "Only Leo is on his way; Maya is still cooking")
	# a save while Maya is still cooking and Leo is on his way
	app.household.set_speed(0)
	check(app.save_game("", "Party with one friend cooking"), "A save while one friend is still cooking is accepted")
	var cooking_slot: String = app.active_save_id
	var cooking_party: Dictionary = _party().duplicate(true)
	_load(cooking_slot)
	await process_frame
	flow = app.party_flow
	residents = app.residents
	app.set_process(false)
	check(_same_snapshot(_party(), cooking_party) and residents.party_visits.size() == 1 and str(_entry("maya").status) == "preparing" and is_equal_approx(float(_entry("maya").depart_at), float(cooking_party.guests[0].depart_at)), "It loads as it was: Leo walking, Maya still cooking, her time unchanged")
	_reject_party(cooking_slot, "A friend still cooking who is already visiting", func(raw: Dictionary) -> void: raw.party.guests[1].status = "preparing")
	app.household.set_speed(8)
	check(await _until_done(func() -> bool: return residents.party_visits.size() >= 2, 600), "Maya sets off after her twenty minutes")
	check(_clock() - now_at_send >= LifePartyPlan.POTLUCK_PREP - 1.0 and str(_entry("maya").status) == "walking", "...once the dish is made")
	check(float(_visit("maya").state.party_until) == float(party.ends_at) and float(_visit("leo").state.party_until) == float(party.ends_at) and int(_visit("maya").state.party) == 1, "Every guest's stay ends when the party does")
	# Maya arrives holding her dish
	check(await _until_done(func() -> bool: return flow.dishes.has("maya"), 400), "Maya is seen holding a dish as she walks over")
	check(bool(app.world.actors.maya.meal_presentation.get("carrying", false)) and is_instance_valid(flow.dishes.maya) and "garden_salad" in str(flow.dishes.maya.scene_file_path), "She carries the garden salad in both hands")
	# a save while she is carrying it
	app.household.set_speed(0)
	check(app.save_game("", "Party with a dish on its way"), "A save while Maya carries her dish is accepted")
	var carrying_slot: String = app.active_save_id
	var carrying_party: Dictionary = _party().duplicate(true)
	_load(carrying_slot)
	await process_frame
	flow = app.party_flow
	residents = app.residents
	app.set_process(false)
	check(_same_snapshot(_party(), carrying_party) and str(_entry("maya").status) == "walking" and not bool(_entry("maya").brought), "It loads as it was")
	_step(6)
	await process_frame
	check(flow.dishes.has("maya") and bool(app.world.actors.maya.meal_presentation.get("carrying", false)), "Maya is holding her dish again after the load")
	app.household.set_speed(8)
	check(_spread("inside", ["maya", "leo"]) >= LifeHomeVisit.GUEST_GAP - .001, "The two have places inside of their own (%.2f m apart)" % _spread("inside", ["maya", "leo"]))
	check(await _until_done(func() -> bool: return _guest_phase("leo") == "inside", 3000), "Leo walks straight in with nobody welcoming him")
	check(str(_party().phase) == "active" and str(_entry("leo").status) == "inside" and bool(_entry("leo").came), "The first guest inside begins the party")
	check(_visit("leo").state.greeting.is_empty() and _visit("leo").state.entrance.is_empty(), "No host greeting")
	var festive_lift: bool = false
	for member: Dictionary in app.household.members: festive_lift = festive_lift or LifePartyPlan.MOODLET_FESTIVE in member.sim.moodlets.map(func(m: Dictionary) -> String: return str(m.label))
	check(festive_lift, "A decorated home leaves the household feeling festive")
	check(app.party_music.wants_loop, "The party loop is asked for")
	# Maya sets her dish down
	check(await _until_done(func() -> bool: return bool(_entry("maya").brought), 5000), "Maya sets her dish down")
	var batch: Dictionary = app.household.meals.batch(str(_entry("maya").batch))
	check(not batch.is_empty() and str(batch.brought_by) == "maya" and str(batch.recipe) == "garden_salad" and str(batch.storage) == "surface" and not str(batch.host).is_empty() and int(batch.remaining) == int(batch.initial), "A garden salad sits on the party table as shared servings, brought by Maya")
	check(str(app._find_item(str(batch.host)).get("kind", "")) in LifeBirthdayFlow.TABLE_KINDS, "The dish is on a table")
	_step(3)
	check(not flow.dishes.has("maya") and not bool(app.world.actors.maya.meal_presentation.get("carrying", false)), "Her hands are empty again")
	check(str(batch.chef) == host_id, "The host is the dish's named cook, because every saved dish needs a household cook")
	app.household.set_speed(0)
	# the status card
	flow.refresh_status()
	check(is_instance_valid(app.ui.find_child("PartyStatus", true, false)) and not is_instance_valid(app.ui.find_child("GuestStatus", true, false)), "A party card shows where the guest card would be")
	var text: String = _text_of("PartyStatusText", app.ui)
	check("guests here" in text and LifePartyPlan.clock_text(float(_party().ends_at)) in text, "The card says who is here and when it ends (%s)" % text)
	check(app.ui.find_child("PartyEnd", true, false) is Button and app.ui.find_child("PartyMusicToggle", true, false) is Button, "It has End the party and Music buttons")
	# guest choices
	var maya_visit: LifeHomeVisit = _visit("maya")
	maya_visit.activity.cancel("")
	maya_visit.activity.data.needs.hunger = 30.0
	maya_visit.activity.data.pick = 1
	check(flow.guest_choose(maya_visit.activity), "A hungry guest at a party goes for the food")
	check(maya_visit.meal.active() or str(maya_visit.activity.current_action().get("id", "")) == "eat_party_food", "...a dish or the platter")
	maya_visit.activity.cancel("")
	if maya_visit.meal.active(): maya_visit.meal.cancel("")
	maya_visit.activity.data.pick = 3
	check(not flow.guest_choose(maya_visit.activity), "Every third choice is left to the guest's ordinary choices")
	# a save in the middle of the party
	check(app.save_game("", "Party under way"), "A party in progress can be saved")
	var mid_slot: String = app.active_save_id
	var expected_party: Dictionary = _party().duplicate(true)
	var expected_visits: Dictionary = app.residents.snapshot()
	_load(mid_slot)
	await process_frame
	flow = app.party_flow
	residents = app.residents
	check(_same_snapshot(_party(), expected_party) and app.household.party_serial == 1, "The party record comes back as it was")
	check(_same_snapshot(residents.snapshot(), expected_visits) and residents.party_visits.size() == 2, "...with both guests")
	app.set_process(false)
	_step(6)
	check(is_instance_valid(app.ui.find_child("PartyStatus", true, false)), "...and the party card")
	check(app.party_music.wants_loop, "...and the party music")
	check(flow.active() and app.party_on() and not residents.begin_trip("park"), "Travel is still refused after the load")
	check(LifePartyPlan.validate(_party_data(mid_slot).get("party"), _party_data(mid_slot)).is_empty() and LifeHomeVisit.validate_saved(_party_data(mid_slot)).is_empty(), "The saved party validates")
	# tampered saves
	_reject_party(mid_slot, "A party that runs 400 minutes", func(raw: Dictionary) -> void: raw.party.ends_at = float(raw.party.started_at) + 400.0)
	_reject_party(mid_slot, "A party guest nobody invited", func(raw: Dictionary) -> void: raw.party.guests[0].id = "tom")
	_reject_party(mid_slot, "The same friend asked twice", func(raw: Dictionary) -> void: raw.party.guests[1].id = raw.party.guests[0].id)
	_reject_party(mid_slot, "A dish that no friend brought", func(raw: Dictionary) -> void:
		raw.party.guests[1].batch = "meal_1"
		raw.party.guests[1].brought = true)
	_reject_party(mid_slot, "A guest visit that is not on the guest list", func(raw: Dictionary) -> void: raw.party.guests = [raw.party.guests[0]])
	_reject_party(mid_slot, "A party number that was never given out", func(raw: Dictionary) -> void: raw.party_serial = 0)
	_reject_party(mid_slot, "A friend marked as still cooking who is visiting", func(raw: Dictionary) -> void:
		raw.party.guests[0].status = "preparing"
		raw.party.guests[0].came = false)
	# the end of the party
	app.household.set_speed(8)
	check(await _until_done(func() -> bool: return str(_party().get("phase", "")) == "ending" or not flow.active(), 4000), "The party winds down when its time is up")
	check(float(_clock()) >= float(expected_party.ends_at) - 1.0, "...not before")
	var friendships_before: Dictionary = {}
	for id: String in ["maya", "leo"]: friendships_before[id] = float(app.household.member_sim(host_id).relationships[id].friendship)
	check(await _until_done(func() -> bool: return not flow.active(), 6000), "Every guest says goodbye and the party is over")
	check(not app.party_on() and _party().is_empty() and residents.party_visits.is_empty() and not residents.any_visit_active(), "Nobody is left and the party is forgotten")
	app.household.set_speed(0)
	var host_sim: LifeSim = app.household.member_sim(host_id)
	check(float(host_sim.relationships.maya.friendship) >= float(friendships_before.maya) + LifePartyPlan.FRIENDSHIP_GAIN - .01 and float(host_sim.relationships.leo.friendship) >= float(friendships_before.leo) + LifePartyPlan.FRIENDSHIP_GAIN - .01, "The host grew closer to both friends")
	check(host_sim.moodlets.any(func(m: Dictionary) -> bool: return str(m.label) == LifePartyPlan.MOODLET_GREAT) and host_sim.memories.any(func(m: Dictionary) -> bool: return str(m.label) == "Hosted a party"), "A good party leaves a mood and a memory")
	await process_frame
	check(not app.party_music.wants_loop, "The party music stops")
	check(not is_instance_valid(app.ui.find_child("PartyStatus", true, false)), "The party card goes")
	check(not app.household.meals.batch(str(batch.id)).is_empty(), "Maya's salad stays for the household")
	app.set_build_mode(true)
	check(app.mode == "build", "Building works again")
	app.set_build_mode(false)


func PartyDecor_apply(table: Dictionary) -> bool:
	return preload("res://scripts/party_decor.gd").apply(app, "lay_tablecloth", str(table.id))

func _reject_party(slot: String, label: String, mutate: Callable) -> void:
	var raw: Dictionary = _party_data(slot)
	mutate.call(raw)
	_reject(raw, label)


## Put a stereo somewhere clear on the ground floor, and a party platter on the dining table.
func _furnish_for_party() -> void:
	var world: LifeWorld = app.world
	var placed: bool = false
	for spot: Vector2 in [Vector2(-1.2, 1.0), Vector2(-.6, 1.6), Vector2(.4, 2.2), Vector2(-1.4, -.4), Vector2(1.0, -1.0)]:
		if world.can_place("stereo", Vector3(spot.x, .16, spot.y), 0.0):
			world.add_item({"id": "party_stereo", "kind": "stereo", "x": spot.x, "z": spot.y, "rotation": 0.0})
			placed = true
			break
	check(placed, "A stereo is set up for the party")
	var table: Dictionary = _first_of("dining")
	var at: Vector3 = table.node.to_global(Vector3.ZERO)
	at.y = LifeWorld.Building.level_y(world.item_level(table))
	var entry: Dictionary = {"id": "party_platter", "kind": "party_food", "x": at.x, "z": at.z, "rotation": table.node.rotation_degrees.y, "style": "snacks"}
	entry.merge(world.surface_placement("party_food", at, table.node.rotation_degrees.y), true)
	world.add_item(entry)
	app._refresh_sim_targets()
	check(not _first_of("party_food").is_empty() and int(_first_of("party_food").get("servings", 0)) == 8, "A full party platter stands on the table")

## Open the planner, tick these friends and send.
func _send(friends: Array, hours: int, music: bool = true, celebrant: String = "", dishes: Array = []) -> bool:
	app.show_relationships()
	_press("HostParty")
	if not is_instance_valid(app.overlay.find_child("PartyPlanner", true, false)): return false
	if not celebrant.is_empty():
		var chooser: OptionButton = app.overlay.find_child("PartyCelebrant", true, false)
		for index: int in chooser.item_count:
			if str(chooser.get_item_metadata(index)) == celebrant:
				chooser.select(index)
				chooser.item_selected.emit(index)
	for id: String in friends: _tick("PartyInvite_" + id, true)
	for id: String in dishes: _tick("PartyPotluck_" + id, true)
	while int(flow.planner.hours) > hours: _press("PartyHoursLess")
	(app.overlay.find_child("PartyMusic", true, false) as CheckButton).button_pressed = music
	return _press("PartySend")


## ---- A party the host calls off, with dancing, the platter and the music

func _early_end() -> void:
	await _boot([{"name": "Ada Vale", "age_stage": "adult", "traits": []}, {"name": "Ben Vale", "age_stage": "adult", "traits": []}])
	_furnish_for_party()
	var residents: LifeResidents = app.residents
	app.set_sound(true)
	check(_send(["maya", "leo", "priya"], 5), "A five-hour party for three friends is sent")
	check(is_equal_approx(float(_party().ends_at) - float(_party().started_at), 300.0) and _party().guests.size() == 3, "It runs five hours")
	var started: float = float(_party().started_at)
	app.household.set_speed(8)
	check(await _until_done(func() -> bool: return _all("inside", FRIENDS_ALL), 9000), "All three friends are inside")
	app.household.set_speed(1)
	_step(8)
	await _settle()
	check(str(_party().phase) == "active" and LifePartyPlan.counts(_party()).inside == 3, "The party is on with three guests")
	# the music: from the stereo, theme turned down not stopped
	var music: LifePartyMusic = app.party_music
	_step(4)
	await _settle()
	check(music.wants_loop and music.loop_at.is_finite() and music.stereo_player.global_position.distance_to(music.loop_at) < .01, "The party loop is asked for at the stereo")
	var stereo: Dictionary = _first_of("stereo")
	check((stereo.node as Node3D).global_position.distance_to(music.loop_at) < 1.5, "...the stereo that is in the house (%.2f m away)" % (stereo.node as Node3D).global_position.distance_to(music.loop_at))
	check(music.current_voice() == "party" and music.stereo_player.playing and not music.stereo_player.stream_paused and not music.loop_player.playing, "The groove plays from the speaker, and the flat player is silent")
	check(is_equal_approx(music.stereo_player.unit_size, 12.0) and not app.music_player.stream_paused, "It fades with distance, and the theme is not paused")
	for index: int in 60: music.tick(.1)
	check(app.music_player.volume_db <= LifePartyMusic.DUCK_DB + .01 and app.music_player.volume_db < music.theme_db, "The theme is turned down for it (%.1f dB)" % app.music_player.volume_db)
	# the music button on the card
	flow.refresh_status()
	var toggle: Button = app.ui.find_child("PartyMusicToggle", true, false)
	check(toggle is Button and toggle.text == "Music on", "The card's music button says Music on")
	toggle.pressed.emit()
	_step(2)
	check(not bool(_party().music) and not music.wants_loop and toggle.text == "Music off", "Music off silences the party loop")
	check(music.current_voice() == "theme", "The theme has the speakers again")
	toggle.pressed.emit()
	_step(2)
	check(bool(_party().music) and music.wants_loop and toggle.text == "Music on", "Music on brings it back")
	app.set_music(false)
	await _settle()
	check(music.current_voice() == "theme" and music.stereo_player.stream_paused, "The menu's Music switch silences it too")
	app.set_music(true)
	app.set_sound(false)
	await _settle()
	check(music.current_voice() == "theme" and music.stereo_player.stream_paused, "...and so does the Sound switch")
	app.set_sound(true)
	app.household.set_speed(0)
	_step(2)
	await _settle()
	check(music.stereo_player.stream_paused, "A paused household holds the party loop where it is")
	app.household.set_speed(1)
	_step(2)
	await _settle()
	check(not music.stereo_player.stream_paused, "...and it carries on with the household")
	# guests dance round the stereo, each on a place of their own
	for id: String in FRIENDS_ALL:
		var act: LifeGuestActivity = _visit(id).activity
		act.cancel("")
		act.data.needs.hunger = 95.0
		act.data.pick = 1
		check(flow.guest_choose(act), "%s is moved to dance" % id)
	var dancers: Array[Vector3] = []
	for id: String in FRIENDS_ALL:
		var current: Dictionary = _visit(id).activity.current_action()
		check(str(current.get("id", "")) == "dance" and str(current.get("target_id", "")) == str(stereo.id), "%s's plan is a dance at the stereo" % id)
		if current.has("target_position"): dancers.append(Vector3(current.target_position))
	var apart: float = 100.0
	for first: int in dancers.size():
		for second: int in range(first + 1, dancers.size()): apart = minf(apart, dancers[first].distance_to(dancers[second]))
	check(apart >= LifeDancePlan.MIN_SPACING, "Three dancers each have their own place (%.2f m apart)" % apart)
	app.household.set_speed(4)
	check(await _until_done(func() -> bool: return FRIENDS_ALL.all(func(id: String) -> bool: return str(_visit(id).activity.current_action().get("phase", "")) == "active"), 3000), "All three reach the stereo and dance")
	app.household.set_speed(0)
	var facing_ok: bool = true
	for id: String in FRIENDS_ALL:
		var body: LifeActor = app.world.actors[id]
		var toward: Vector3 = (stereo.node as Node3D).global_position - body.position
		var want: float = atan2(toward.x, toward.z)
		if absf(angle_difference(body._activity_anchor.get("yaw", 99.0), want)) > .05: facing_ok = false
	check(facing_ok, "They face the stereo")
	var fun_before: float = float(_visit("maya").activity.data.needs.fun)
	app.household.set_speed(4)
	check(await _until_done(func() -> bool: return FRIENDS_ALL.all(func(id: String) -> bool: return not _visit(id).activity.active()), 4000), "They dance to the end")
	app.household.set_speed(0)
	check(float(_visit("maya").activity.data.needs.fun) > fun_before + 10.0 or float(_visit("maya").activity.data.needs.fun) >= 99.0, "Dancing is fun")
	# the platter
	var platter: Dictionary = _first_of("party_food")
	var eater: LifeGuestActivity = _visit("leo").activity
	eater.cancel("")
	eater.data.needs.hunger = 30.0
	eater.data.pick = 2
	check(flow.guest_choose(eater) and str(eater.current_action().get("id", "")) == "eat_party_food" and str(eater.current_action().get("target_id", "")) == str(platter.id), "A hungry guest goes to the party food platter")
	app.household.set_speed(4)
	check(await _until_done(func() -> bool: return int(_first_of("party_food").get("servings", 8)) < 8, 3000), "Leo takes a serving from the platter")
	app.household.set_speed(0)
	check(int(_first_of("party_food").get("servings", 8)) == 7 and float(eater.data.needs.hunger) > 30.0, "The platter has seven left and Leo is less hungry")
	# the host calls it off
	flow.refresh_status()
	var end_button: Button = app.ui.find_child("PartyEnd", true, false)
	check(end_button is Button and not end_button.disabled, "The card has an End the party button")
	var called_at: float = _clock()
	end_button.pressed.emit()
	check(str(_party().phase) == "ending" and float(_party().ends_at) <= called_at + 2.0 * LifePartyPlan.GOODBYE_GAP + .01 and float(_party().ends_at) < started + 300.0, "End the party winds it down at once")
	var untils: Array = []
	for id: String in FRIENDS_ALL: untils.append(float(_visit(id).state.party_until))
	untils.sort()
	check(is_equal_approx(float(untils[1]) - float(untils[0]), LifePartyPlan.GOODBYE_GAP) and is_equal_approx(float(untils[2]) - float(untils[1]), LifePartyPlan.GOODBYE_GAP), "Guests say goodbye two minutes apart")
	var order: Array = []
	app.household.set_speed(8)
	for index: int in 6000:
		app._process(.05)
		if index % 25 == 0: await process_frame
		for id: String in FRIENDS_ALL:
			if _guest_phase(id) in ["leaving", "absent"] and not order.has(id): order.append(id)
		if not flow.active(): break
	app.household.set_speed(0)
	check(order.size() == 3 and not flow.active() and residents.party_visits.is_empty(), "Everyone leaves and the party is over")
	check(_clock() < called_at + 40.0 and called_at < started + 280.0, "...within forty minutes of the host calling it off, not at the five-hour mark")
	check(not music.wants_loop and not music.stereo_player.playing and is_equal_approx(app.music_player.volume_db, music.theme_db) or app.music_player.volume_db > LifePartyMusic.DUCK_DB, "The music stops and the theme comes back up")


## ---- Somebody in the hall holds a guest at the door

func _held_at_the_door() -> void:
	await _boot([{"name": "Ada Vale", "age_stage": "adult", "traits": []}, {"name": "Ben Vale", "age_stage": "adult", "traits": []}, {"name": "Kit Vale", "age_stage": "child", "traits": []}], 600.0, false)
	check(_send(["maya"], 3), "A party for one friend is sent while the household stands in the hall")
	var heard: Array = []
	var held: bool = false
	app.household.set_speed(8)
	for index: int in 3000:
		app._process(.05)
		if index % 25 == 0: await process_frame
		if heard.is_empty() or heard[-1] != app.notice_text: heard.append(app.notice_text)
		if _visit("maya").owns("maya") and _visit("maya").state.route.point >= _visit("maya").state.route.points.size() and _visit("maya").state.route.points.size() > 0 and str(_visit("maya").state.phase) == "arriving" and heard.any(func(n: String) -> bool: return "path is blocked" in n):
			held = true
			break
		if _guest_phase("maya") in ["entering", "inside"]: break
	app.household.set_speed(0)
	if not held: print("DEBUG door ", heard, " ", _visit("maya").state.get("phase", "gone"), " members ", app.household.members.map(func(m: Dictionary) -> Vector3: return app.world.actors[str(m.id)].position))
	check(held and str(_visit("maya").state.phase) == "arriving", "The guest waits on the doorstep, and the player is told the way is blocked")
	check(str(_entry("maya").status) == "walking" and _party().get("phase", "") == "inviting", "The party is still waiting for her, not over")
	# the household steps aside
	var steps: Array[Vector2] = [Vector2(4.6, 3.0), Vector2(4.6, -1.0), Vector2(3.0, -1.2)]
	for index: int in app.household.members.size():
		var at: Vector3 = app.world.nearest_clear_point(Vector3(steps[index].x, .16, steps[index].y), 0)
		if at.is_finite(): app.world.actors[str(app.household.members[index].id)].position = at
	app._store_motion()
	app.household.set_speed(8)
	check(await _until_done(func() -> bool: return _guest_phase("maya") == "inside", 3000), "Once the hall is clear she comes in by herself")
	app.household.set_speed(0)
	_step(8)
	check(str(_entry("maya").status) == "inside" and str(_party().phase) == "active", "...and the party begins")


## ---- A birthday party

func _birthday_party() -> void:
	await _boot([{"name": "Ada Vale", "age_stage": "adult", "traits": []}, {"name": "Ben Vale", "age_stage": "adult", "traits": []}, {"name": "Kit Vale", "age_stage": "child", "traits": []}], 600.0)
	app.household.day = 6
	for member: Dictionary in app.household.members: member.sim.day = 6
	var kit: LifeSim = null
	var kit_id: String = ""
	for member: Dictionary in app.household.members:
		if str(member.sim.character.name).begins_with("Kit"):
			kit = member.sim
			kit_id = str(member.id)
	check(kit.celebrate_birthday(false, "auto") and not app.household.birthday_entry(kit_id).is_empty(), "Kit's birthday comes round and a cake is owed")
	app.set_sound(true)
	check(flow.default_celebrant() == kit_id, "The planner puts the person with a waiting birthday first")
	check(_send(["maya", "leo"], 5, true, kit_id, ["maya"]), "A party for Kit is sent, with Maya bringing a dish")
	check(str(_party().celebrant_id) == kit_id and int(app.household.birthday_entry(kit_id).party_serial) == 1, "Kit's waiting birthday is now the party's")
	check(flow.ritual_waits(kit_id), "The cake waits for the guests")
	app.household.set_speed(8)
	var early: bool = false
	var gathered_at: float = -1.0
	var inside_at: float = -1.0
	var heard: Array = []
	for index: int in 12000:
		app._process(.05)
		if index % 25 == 0: await process_frame
		if heard.is_empty() or heard[-1] != app.notice_text: heard.append(app.notice_text)
		if inside_at < 0.0 and _all("inside", ["maya", "leo"]): inside_at = _clock()
		if not app.household.birthday_session_for(kit_id).is_empty():
			gathered_at = _clock()
			break
	app.household.set_speed(0)
	if inside_at < 0.0: print("DEBUG notices ", heard, " party ", _party(), " visits ", app.residents.guest_ids())
	check(inside_at >= 0.0 and gathered_at >= 0.0, "The family gathers round the cake")
	check(inside_at >= 0.0 and gathered_at >= inside_at - .5, "...only once the guests are in (guests in at %.0f, cake at %.0f)" % [inside_at, gathered_at])
	var session: Dictionary = app.household.birthday_session_for(kit_id)
	if session.is_empty():
		return
	app.household.set_speed(1)
	var singing: bool = false
	for index: int in 1500:
		app._process(.05)
		if index % 25 == 0: await process_frame
		var all_singing: bool = true
		for id: String in ["maya", "leo"]:
			if str(_visit(id).activity.current_action().get("id", "")) != "sing_birthday" or str(_visit(id).activity.current_action().get("phase", "")) != "active": all_singing = false
		if all_singing:
			singing = true
			break
	check(singing, "Both guests stand round the table and sing")
	check(singing and bool(_entry("maya").brought) and not str(_entry("maya").batch).is_empty() and not flow.dishes.has("maya"), "Maya sets her dish down first and then joins the song, not both at once")
	if not singing:
		return
	var spots: Array[Vector3] = []
	for value: Variant in session.positions.values(): spots.append(Vector3(value[0], value[1], value[2]))
	for id: String in ["maya", "leo"]: spots.append(app.world.actors[id].position)
	var closest_pair: float = 100.0
	for first: int in spots.size():
		for second: int in range(first + 1, spots.size()): closest_pair = minf(closest_pair, spots[first].distance_to(spots[second]))
	check(closest_pair >= LifeBirthdayRitual.MIN_SPACING, "Guests and family each have a place round the cake (%.2f m apart)" % closest_pair)
	var maya_body: LifeActor = app.world.actors.maya
	check(str(maya_body.celebration_presentation.get("role", "")) == "singer" and str(maya_body.celebration_presentation.get("session_id", "")) == str(session.id), "A guest takes the singer's pose from the family's clock")
	check(app.party_music.wants_tune and app.party_music.current_voice() == "birthday", "The birthday tune plays, over the party loop")
	app.household.set_speed(8)
	var finished: bool = await _until_done(func() -> bool: return app.household.birthday_session_for(kit_id).is_empty(), 4000)
	app.household.set_speed(0)
	check(finished and app.household.birthday_entry(kit_id).is_empty(), "The candles go out and the birthday is celebrated")
	_step(3)
	check(not (maya_body.celebration_presentation.get("role", "") == "singer") and not flow._singers.has("maya"), "The guests stand down after the song")
	var cake_found: bool = false
	for batch: Dictionary in app.household.meals.batches:
		if str(batch.recipe) == "layer_cake": cake_found = true
	check(cake_found, "A layer cake is set out for everyone")
	app.party_flow.end_party()
	app.household.set_speed(8)
	check(await _until_done(func() -> bool: return not flow.active(), 6000), "The birthday party ends")
	app.household.set_speed(0)
