extends SceneTree
const LifeWantsManager = preload("res://scripts/wants_manager.gd")
## Iteration 61 depth package, through the public paths only: the spendable
## rewards store (permanent perks and one-use potions), the emotion-gated
## interactions, and the trait-gated interactions. Every gate is read from the
## same availability the menu and the queue use, and the new save fields survive
## a real JSON round trip. Headless.

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


func _find(app_node: Node, kind: String) -> Dictionary:
	for item: Dictionary in app_node.world.items:
		if str(item.kind) == kind:
			return item
	return {}


func _trait_sim(trait_name: String) -> LifeSim:
	var sim: LifeSim = LifeSim.new()
	var chosen: Array = [trait_name] if not trait_name.is_empty() else []
	sim.new_household({"name": "Probe " + (trait_name if not trait_name.is_empty() else "Plain"), "age_stage": "young_adult", "traits": chosen})
	sim.autonomy = false
	sim.wants.clear()
	for need: String in sim.needs:
		sim.needs[need] = 90.0
	return sim


func _run() -> void:
	app = load("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	await process_frame
	await process_frame
	app.selected_lot = 0
	var guest_profile: Dictionary = app.profile.duplicate(true)
	guest_profile.name = "Roommate Rowan"
	app.household_profiles = [app.profile, guest_profile]
	app.start_household()
	await process_frame
	app.set_process(false)
	var sim: LifeSim = app.sim
	sim.autonomy = false
	sim.moodlets.clear()
	sim.wants.clear()
	sim.satisfaction = 0
	sim.purchased_perks.clear()

	# ---------------------------------------------------------------- 1. store
	check(LifeSim.REWARDS.size() >= 6, "The store lists at least six rewards.")
	var plain: LifeSim = _trait_sim("")
	var quick: LifeSim = _trait_sim("")
	var bladder_before_plain: float = plain.needs.bladder
	var bladder_before_quick: float = quick.needs.bladder
	quick.satisfaction = 400
	check(quick.buy_reward("steel_bladder"), "An affordable permanent perk can be bought.")
	check(quick.satisfaction == 150, "Buying a ℒ250 perk removes exactly 250 satisfaction (got %d)." % quick.satisfaction)
	check(quick.purchased_perks == ["steel_bladder"], "The permanent perk is recorded in purchased_perks.")
	var owned_entry: Dictionary = {}
	for reward: Dictionary in quick.available_rewards():
		if str(reward.id) == "steel_bladder": owned_entry = reward
	check(not owned_entry.is_empty() and bool(owned_entry.owned), "The store reports the perk as owned.")
	quick.tick(60.0)
	plain.tick(60.0)
	var lost_plain: float = bladder_before_plain - float(plain.needs.bladder)
	var lost_quick: float = bladder_before_quick - float(quick.needs.bladder)
	check(lost_plain > 3.9 and lost_plain < 4.1, "An unperked Lifelet loses the ordinary 4 bladder over an hour (got %.2f)." % lost_plain)
	check(absf(lost_quick - lost_plain * 0.7) < 0.05, "Steel Bladder cuts that hourly decay by 30%% (%.2f vs %.2f)." % [lost_quick, lost_plain])
	plain.free()
	quick.free()

	# A second permanent perk really moves the multiplier it names.
	var connected: LifeSim = _trait_sim("")
	connected.satisfaction = 600
	check(connected.buy_reward("connections"), "A ℒ450 career perk can be bought.")
	check(absf(connected._career_performance_gain(20.0) - 25.0) < 0.0001, "Connections lifts every performance gain by 25%% (got %.2f)." % connected._career_performance_gain(20.0))
	connected.free()

	# A one-use potion acts at once, is not remembered as a perk, and is spent.
	sim.satisfaction = 300
	sim.needs.hunger = 10.0
	var perks_before: int = sim.purchased_perks.size()
	check(sim.buy_reward("instant_meal"), "An affordable one-use potion can be bought.")
	check(absf(float(sim.needs.hunger) - 100.0) < 0.001, "Instant Meal restores hunger completely (now %.0f)." % sim.needs.hunger)
	check(sim.satisfaction == 180, "The potion removed exactly its ℒ120 price (got %d)." % sim.satisfaction)
	check(sim.purchased_perks.size() == perks_before, "A one-use potion is not recorded as a permanent perk.")

	# The mood potion grants the very mood the emotion gates read.
	sim.satisfaction = 300
	sim.moodlets.clear()
	check(sim.buy_reward("inspiring_presence"), "The mood potion can be bought.")
	check(str(sim.get_mood().label) == "Inspired", "Inspiring Presence really puts the Lifelet in the Inspired mood (got %s)." % sim.get_mood().label)
	var gift: Dictionary = {}
	for entry: Dictionary in sim.moodlets:
		if str(entry.label) == "Inspired by a gift": gift = entry
	check(not gift.is_empty() and absf(float(gift.remaining) - 480.0) < 0.001 and str(gift.emotion) == "Inspired", "The granted moodlet lasts the advertised 480 minutes.")

	# An unaffordable reward and an owned one are both refused with a reason and leave state alone.
	sim.moodlets.clear()
	sim.satisfaction = 0
	sim.purchased_perks.clear()
	var poor: Dictionary = sim.can_buy_reward("hardy_constitution")
	check(not bool(poor.available) and str(poor.reason).contains("350"), "An unaffordable reward is refused with its price as the reason.")
	check(not sim.buy_reward("hardy_constitution") and sim.satisfaction == 0 and sim.purchased_perks.is_empty(), "A refused purchase changes nothing.")
	sim.satisfaction = 1000
	check(sim.buy_reward("carefree"), "A perk can be bought while rich.")
	var owned_reason: Dictionary = sim.can_buy_reward("carefree")
	check(not bool(owned_reason.available) and str(owned_reason.reason).contains("already own"), "An already-owned perk is refused with an ownership reason.")
	var satisfied_at: int = sim.satisfaction
	check(not sim.buy_reward("carefree") and sim.satisfaction == satisfied_at and sim.purchased_perks == ["carefree"], "Buying an owned reward twice is refused and pays nothing back.")
	check(not sim.can_buy_reward("not_a_reward").available, "An unknown reward id is refused.")
	sim.purchased_perks.clear()
	sim.satisfaction = 0

	# ---------------------------------------------------- 2. emotion-gated work
	var easel: Dictionary = _find(app, "easel")
	var treadmill: Dictionary = _find(app, "treadmill")
	var desk: Dictionary = _find(app, "desk")
	check(not easel.is_empty(), "The starter home has an easel.")
	sim.moodlets.clear()
	for need: String in sim.needs: sim.needs[need] = 90.0
	sim.skills.creativity = {"level": 1, "xp": 0.0}
	check(str(sim.get_mood().label) != "Inspired", "With no moodlet and full needs the Lifelet is not Inspired.")
	var closed: Dictionary = sim.get_action_availability("paint_masterpiece", str(easel.id))
	check(not bool(closed.available) and str(closed.reason).contains("Inspired"), "Outside Inspiration the masterpiece is unavailable with a clear reason.")
	var easel_menu: Array = sim.get_actions_for("easel", str(easel.id))
	var offered_closed: Dictionary = {}
	for action: Dictionary in easel_menu:
		if str(action.id) == "paint_masterpiece": offered_closed = action
	check(not offered_closed.is_empty() and not bool(offered_closed.available), "The menu still shows the masterpiece, disabled while the mood is wrong.")
	check(not sim.queue_action("paint_masterpiece", str(easel.id), app.world.approach(easel)), "The queue refuses the masterpiece outside Inspiration.")
	check(sim.action_queue.is_empty(), "A refused masterpiece leaves the queue empty.")

	sim.add_moodlet("A wellspring", "Inspired", "Something is waiting to be made.", 180, 3)
	check(str(sim.get_mood().label) == "Inspired", "The Inspired moodlet drives the live mood label.")
	check(bool(sim.get_action_availability("paint_masterpiece", str(easel.id)).available), "While Inspired, the masterpiece is offered.")
	app.queue_interaction(easel, "paint_masterpiece")
	var masterpiece: Dictionary = sim.get_current_action()
	check(str(masterpiece.get("id", "")) == "paint_masterpiece", "The masterpiece queues through the public interaction path.")
	var funds_before: int = sim.funds
	masterpiece.phase = "active"
	masterpiece.elapsed = float(masterpiece.duration)
	sim._finish_front()
	var masterpiece_sale: int = sim.funds - funds_before
	check(masterpiece_sale == 285, "The Inspired masterpiece sells for its promised ℒ285 (got ℒ%d)." % masterpiece_sale)
	check(masterpiece_sale > int((55 + 35) * 1.25), "The masterpiece pays substantially more than an ordinary Inspired canvas (ℒ%d)." % int((55 + 35) * 1.25))
	var master_memory: bool = false
	for entry: Dictionary in sim.moodlets:
		if str(entry.label) == "A real masterpiece": master_memory = true
	check(master_memory, "Finishing a masterpiece leaves its own moodlet.")
	check(int(sim.get_action_definition("paint_masterpiece").xp) > int(sim.get_action_definition("paint").xp), "The masterpiece grants more creativity xp than an ordinary canvas.")

	# The other four emotional opportunities appear only in their own mood.
	for pair: Array in [["study_hard", "Focused", "desk"], ["push_through", "Energized", "treadmill"], ["playful_prank", "Playful", "maya"], ["bold_introduction", "Confident", "maya"]]:
		var id: String = str(pair[0])
		var emotion: String = str(pair[1])
		var target: String = str(pair[2])
		if target == "treadmill" and not treadmill.is_empty(): target = str(treadmill.id)
		elif target == "desk" and not desk.is_empty(): target = str(desk.id)
		sim.moodlets.clear()
		var shut: Dictionary = sim.get_action_availability(id, target)
		check(not bool(shut.available) and str(shut.reason).contains(emotion), "%s is refused outside %s (%s)." % [id, emotion, str(shut.reason)])
		var mood_entry: Dictionary = {"label": "A passing mood", "emotion": emotion, "description": "A mood.", "remaining": 120.0, "strength": 3}
		sim.moodlets.append(mood_entry)
		check(str(sim.get_mood().label) == emotion, "The %s moodlet drives the mood label." % emotion)
		check(bool(sim.get_action_availability(id, target).available), "%s opens up while %s." % [id, emotion])
		sim.moodlets.clear()

	# The gated actions carry real effects, not just labels.
	check(int(sim.get_action_definition("study_hard").xp) > int(sim.get_action_definition("study").xp), "Study hard grants more logic xp than ordinary study.")
	check(int(sim.get_action_definition("push_through").xp) > int(sim.get_action_definition("jog").xp), "Push through grants more fitness xp than the ordinary jog.")
	check(float(sim.get_action_definition("push_through").changes.energy) < float(sim.get_action_definition("jog").changes.energy), "Push through costs more energy than the ordinary jog.")
	check(int(sim.get_action_definition("bold_introduction").xp) == int(sim.get_action_definition("friendly").xp), "The bold introduction is a friendship swing, not a skill shortcut.")

	# The prank really can backfire into Tense when the friendship is thin.
	var prank: LifeSim = _trait_sim("")
	prank.relationships.maya.friendship = 10.0
	prank.moodlets.append({"label": "Feeling silly", "emotion": "Playful", "description": "Mischief is in the air.", "remaining": 200.0, "strength": 3})
	check(bool(prank.get_action_availability("playful_prank", "maya").available), "A Playful Lifelet is offered the prank.")
	check(prank.queue_action("playful_prank", "maya"), "The prank queues while Playful.")
	var prank_action: Dictionary = prank.get_current_action()
	prank_action.phase = "active"
	prank_action.elapsed = float(prank_action.duration)
	prank.moodlets.clear()
	prank._finish_front()
	var tense: bool = false
	for entry: Dictionary in prank.moodlets:
		if str(entry.emotion) == "Tense": tense = true
	check(tense, "A prank on a thin friendship leaves the prankster Tense.")
	prank.relationships.maya.friendship = 60.0
	var friend_at: float = float(prank.relationships.maya.friendship)
	prank.moodlets.append({"label": "Feeling silly", "emotion": "Playful", "description": "Mischief is in the air.", "remaining": 200.0, "strength": 3})
	check(prank.queue_action("playful_prank", "maya"), "The prank queues again between friends.")
	var good_prank: Dictionary = prank.get_current_action()
	good_prank.phase = "active"
	good_prank.elapsed = float(good_prank.duration)
	prank.moodlets.clear()
	prank._finish_front()
	check(float(prank.relationships.maya.friendship) > friend_at, "A prank between friends still deepens the friendship.")
	prank.free()

	# ----------------------------------------------------- 3. trait-gated work
	for pair: Array in [["sketch_for_fun", "Creative", "easel"], ["host_a_chat", "Outgoing", "sofa"], ["morning_run", "Active", "lot_exit"], ["deep_read", "Bookworm", "bookshelf"], ["experiment_recipe", "Foodie", "stove"], ["deep_clean", "Neat", "sink"]]:
		var id: String = str(pair[0])
		var trait_name: String = str(pair[1])
		var kind: String = str(pair[2])
		var target_id: String = ""
		if kind == "lot_exit":
			target_id = "lot_exit"
		else:
			var item: Dictionary = _find(app, kind)
			if not item.is_empty(): target_id = str(item.id)
		var with_trait: LifeSim = _trait_sim(trait_name)
		var without: LifeSim = _trait_sim("")
		check(bool(with_trait.get_action_availability(id, target_id).available), "A %s Lifelet is offered %s." % [trait_name, id])
		var refused: Dictionary = without.get_action_availability(id, target_id)
		check(not bool(refused.available) and str(refused.reason).contains(trait_name), "Every other Lifelet is refused %s (%s)." % [id, str(refused.reason)])
		var menu: Array = without.get_actions_for(kind, target_id)
		var entry: Dictionary = {}
		for action: Dictionary in menu:
			if str(action.id) == id: entry = action
		check(not entry.is_empty() and not bool(entry.available), "The menu offers %s to strangers only as a disabled entry." % id)
		with_trait.free()
		without.free()

	# The trait habits have real, distinct effects.
	var sketch: Dictionary = sim.get_action_definition("sketch_for_fun")
	var canvas: Dictionary = sim.get_action_definition("paint")
	check(float(sketch.duration) < float(canvas.duration) and int(sketch.cost) < int(canvas.cost) and float(sketch.changes.fun) > 0.0, "Sketching is shorter and cheaper than a canvas, and still good fun.")
	check(int(sim.get_action_definition("morning_run").xp) > int(sim.get_action_definition("jog").xp) and float(sim.get_action_definition("morning_run").changes.energy) < 0.0, "The morning run beats the treadmill for fitness and costs energy.")
	check(int(sim.get_action_definition("deep_read").xp) > int(sim.get_action_definition("read").xp) and float(sim.get_action_definition("deep_read").duration) > float(sim.get_action_definition("read").duration), "The deep read is a longer, richer logic session than ordinary reading.")
	check(float(sim.get_action_definition("experiment_recipe").changes.fun) > 0.0 and str(sim.get_action_definition("experiment_recipe").skill) == "creativity", "Experimenting with a recipe gives fun and creativity.")
	check(float(sim.get_action_definition("deep_clean").changes.hygiene) > 0.0 and float(sim.get_action_definition("deep_clean").changes.fun) > 0.0, "Deep cleaning is a hygiene chore that pays a little fun.")

	# The host's chat lifts the whole nearby household, not just the actor.
	var sofa: Dictionary = _find(app, "sofa")
	var housemate: LifeSim = app.household.member_sim("housemate_1")
	check(housemate != null, "The household has a second member for the hosted chat.")
	housemate.needs.social = 20.0
	sim.needs.social = 20.0
	sim.character.traits = ["Outgoing"]
	app.queue_interaction(sofa, "host_a_chat")
	var chat: Dictionary = sim.get_current_action()
	check(str(chat.get("id", "")) == "host_a_chat", "The hosted chat queues through the public interaction path.")
	chat.phase = "active"
	# The tick applies the need changes continuously; reproduce that before the
	# completion so the host's own social gain is actually exercised.
	sim._apply_continuous_effects(chat, 1.0)
	chat.elapsed = float(chat.duration)
	sim._finish_front()
	check(float(sim.needs.social) > 20.0, "Hosting a chat raises the host's own social need.")
	check(float(housemate.needs.social) > 20.0, "Hosting a chat also lifts the nearby housemate (now %.0f)." % housemate.needs.social)
	check(float(sim.get_action_definition("host_a_chat").changes.social) > float(sim.get_action_definition("friendly").changes.social), "A hosted chat is a bigger social gain than one conversation.")
	sim.character.traits = ["Creative", "Outgoing", "Foodie"]

	# --------------------------------------------------------- 4. save / load
	sim.moodlets.clear()
	sim.action_queue.clear()
	sim.satisfaction = 640
	sim.purchased_perks = ["steel_bladder", "connections"]
	sim.needs.energy = 43.0
	var snapshot: Dictionary = sim.get_state()
	var json: JSON = JSON.new()
	json.parse(JSON.stringify(sim._json_safe(snapshot)))
	var restored: LifeSim = LifeSim.new()
	var result: Dictionary = restored.restore_state(json.data)
	check(bool(result.ok), "A state saved with the new fields reloads through the normal restore path (%s)." % str(result.get("error", "")))
	check(restored.satisfaction == 640, "Satisfaction survives the JSON round trip (got %d)." % restored.satisfaction)
	check(restored.purchased_perks == ["steel_bladder", "connections"], "Every purchased perk survives the JSON round trip.")
	check(absf(float(restored.needs.energy) - 43.0) < 0.001, "The rest of the state still loads alongside the new field.")
	var owned_count: int = 0
	for reward: Dictionary in restored.available_rewards():
		if bool(reward.owned): owned_count += 1
	check(owned_count == 2, "The reloaded store still reports both perks as owned.")
	check(absf(restored._perk_decay_multiplier("bladder") - 0.7) < 0.0001, "The reloaded perk keeps slowing decay.")
	check(absf(restored._career_performance_gain(20.0) - 25.0) < 0.0001, "The reloaded career perk keeps its multiplier.")

	# A corrupted or impossible new field is rejected, and rejection mutates nothing.
	for bad: Variant in [["steel_bladder", "steel_bladder"], ["instant_meal"], ["not_a_reward"], "steel_bladder", [1, 2]]:
		var damaged: Dictionary = sim.get_state()
		damaged.purchased_perks = bad
		var rejected: Dictionary = restored.restore_state(damaged)
		check(not bool(rejected.ok) and str(rejected.error).contains("reward"), "The validator rejects a corrupted purchased_perks (%s)." % str(bad))
	check(restored.purchased_perks == ["steel_bladder", "connections"] and restored.satisfaction == 640, "A rejected save leaves the live household untouched.")

	# A save written before the store existed still loads with no perks.
	var legacy: Dictionary = sim.get_state()
	legacy.erase("purchased_perks")
	check(bool(restored.restore_state(legacy).ok) and restored.purchased_perks.is_empty(), "An old save without the store loads with an empty perk list.")

	# The Wishes panel keeps the simulation running, so a whim slot can refresh
	# between the moment a card is drawn and the moment its Pin is pressed. The
	# button is wired to the whim's own identity, so a press never suppresses the
	# desire that quietly replaced the one on screen.
	app.household.set_speed(0)
	sim.needs.fun = 5.0
	sim.needs.hunger = 90.0
	sim.needs.energy = 90.0
	sim.needs.hygiene = 90.0
	sim.needs.social = 90.0
	sim.whims = LifeWantsManager.fresh_state(sim.character, str(sim.get_mood().label), sim.needs, true)
	app.show_wishes()
	await process_frame;await process_frame;await process_frame
	var card_id: String = str(sim.get_whims()[0].get("id", ""))
	var pin: Button = null
	for node: Node in app.overlay.find_children("*", "Button", true, false):
		if (node as Button).text == "Pin" and (node as Button).is_visible_in_tree():
			pin = node
			break
	check(pin != null, "The Wishes panel offers a Pin on its needs card.")
	var slots: Array = sim.get_whims()[0].get("action_tags", [])
	sim.whims["whims"][0]["completed"] = true
	sim.needs.fun = 95.0
	sim.needs.hunger = 5.0
	LifeWantsManager.refresh_whims(sim.whims, sim.character, sim.needs, str(sim.get_mood().label))
	var replacement_id: String = str(sim.get_whims()[0].get("id", ""))
	check(replacement_id != card_id, "The needs slot refreshed behind the open panel (%s -> %s)." % [card_id, replacement_id])
	pin.pressed.emit()
	await process_frame;await process_frame;await process_frame
	check(not bool(sim.get_whims()[0].get("pinned", false)), "A press on the old card does not pin the whim that replaced it.")
	app.close_overlay()
	await process_frame;await process_frame

	restored.free()
	app.queue_free()
	await process_frame
	print("DEPTH_V61 %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
