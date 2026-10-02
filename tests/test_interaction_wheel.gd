extends SceneTree
## Clicking a person opens a wheel of social, fun and romantic rings, and the
## proposals are asked in words that fit whoever is being asked.
var app: Node
var checks: int = 0
var failures: Array[String] = []

func _initialize() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
	checks += 1
	print("CHECK ", "PASS " if ok else "FAIL ", message)
	if not ok: failures.append(message)
func frames(count: int = 3) -> void:
	for i: int in count: await process_frame

func wheel(id: String, label: String) -> void:
	app.show_interactions({"id": id, "kind": "neighbor", "label": label}, Vector2(700, 420))
	await frames()

func ring(name: String) -> void:
	var button: Button = app.overlay.find_child("WheelCategory_" + name, true, false)
	check(is_instance_valid(button), "The %s ring is on the wheel" % name)
	if is_instance_valid(button):
		button.pressed.emit()
		await frames()

func action(id: String) -> Button:
	return app.overlay.find_child("WheelAction_" + id, true, false)

func run() -> void:
	app = load("res://scenes/main.tscn").instantiate(); root.add_child(app)
	await frames(4)
	app.set_sound(false)
	app.household_profiles = [{"name": "Robin Vale", "age_stage": "adult", "traits": []}]
	app.selected_lot = 0; app.start_household()
	await frames(4)
	app.set_process(false); app.household.set_speed(0)

	# ---- the name a spouse takes belongs to the home they move into, not to anyone's gender
	check(LifeMarriage.married_name("Maya Chen", "Robin Vale") == "Maya Vale", "A wife takes the surname of the home she joins")
	check(LifeMarriage.married_name("Leo Morgan", "Robin Vale") == "Leo Vale", "A husband takes it too")
	check(LifeMarriage.married_name("Leo Morgan", "Sam Birch") == "Leo Birch", "Two men: the incoming spouse takes the resident's surname")
	check(LifeMarriage.married_name("Priya Sharma", "Maya Chen") == "Priya Chen", "Two women: the same")
	check(LifeMarriage.married_name("Maya", "Robin Vale") == "Maya Vale", "A spouse with one name gains the surname")
	check(LifeMarriage.married_name("Maya Chen", "Robin") == "Maya Chen", "A host with no surname gives none, and no first name is lent")

	# ---- the wheel itself
	await wheel("maya", "Maya Chen")
	check(app.overlay.find_child("InteractionWheel", true, false) != null, "Clicking a person opens a wheel")
	check(app.overlay.find_child("WheelHub", true, false) != null, "Their name sits in the hub")
	for name: String in ["social", "fun", "romantic"]:
		check(app.overlay.find_child("WheelCategory_" + name, true, false) != null, "The %s ring is offered" % name)
	check(app.overlay.find_children("*", "Button", true, false).filter(func(b: Node) -> bool: return str(b.name).begins_with("WheelAction_")).is_empty(), "Only the rings show until one is chosen")
	await ring("social")
	for id: String in ["friendly", "deep_talk", "share_interests"]:
		check(action(id) != null, "A social choice: %s" % id)
	check(app.overlay.find_child("WheelBack", true, false) != null, "A ring has a way back")
	app.overlay.find_child("WheelBack", true, false).pressed.emit(); await frames()
	await ring("fun")
	check(action("joke") != null and action("playful_prank") != null, "The fun ring has jokes and pranks")
	app.overlay.find_child("WheelBack", true, false).pressed.emit(); await frames()
	await ring("romantic")
	for id: String in ["flirt", "ask_partner", "go_on_date", "commit"]:
		check(action(id) != null, "A romantic choice: %s" % id)
	# The way from friend to spouse can be seen, with each step's reason.
	check(action("ask_partner").disabled and action("commit").disabled, "Proposing is shut until it has been earned")
	check("three successful flirts" in str(action("ask_partner").tooltip_text), "The partner proposal says what unlocks it (%s)" % action("ask_partner").tooltip_text)
	check("two dates" in str(action("commit").tooltip_text).to_lower() or "date" in str(action("commit").tooltip_text).to_lower(), "The marriage proposal says what unlocks it (%s)" % action("commit").tooltip_text)

	# ---- the words of a proposal
	check(app.proposal_question("ask_partner", "maya") == "Would you like to be my girlfriend?", "Asking a woman: girlfriend")
	check(app.proposal_question("ask_partner", "leo") == "Would you like to be my boyfriend?", "Asking a man: boyfriend")
	check(app.proposal_question("ask_partner", "nobody") == "Would you like to be my partner?", "Asking someone unknown: partner")
	check(app.proposal_question("commit", "maya") == "Would you like to move in with me and become my wife?", "Asking a woman to marry: wife")
	check(app.proposal_question("commit", "leo") == "Would you like to move in with me and become my husband?", "Asking a man to marry: husband")
	check(app.proposal_question("commit", "nobody") == "Would you like to move in with me and become my spouse?", "Asking someone unknown to marry: spouse")
	var accepted: Dictionary = {"id": "ask_partner", "target_id": "leo", "social_accepted": true}
	check(app.finish_line(accepted) == "Would you like to be my boyfriend?", "A proposal is spoken aloud as the conversation ends")
	check(app.finish_line({"id": "commit", "target_id": "maya", "social_accepted": true}) == "Would you like to move in with me and become my wife?", "So is the marriage proposal")
	check(app.finish_line({"id": "friendly", "target_id": "maya"}) == "Good to talk with you!", "Other lines are unchanged")

	# ---- the entries carry those words, and open after the right history
	var relation: Dictionary = app.sim.relationships.maya
	relation.friendship = 60.0; relation.successful_flirts = 3
	if app.sim._social_reciprocal.has("maya"): app.sim._social_reciprocal.maya.friendship = 60.0
	app.sim._update_relationship_status(relation)
	await wheel("maya", "Maya Chen"); await ring("romantic")
	check(action("ask_partner").text.begins_with("Would you like to be my girlfriend?"), "The menu asks a woman to be a girlfriend (%s)" % action("ask_partner").text)
	check(not action("ask_partner").disabled, "The proposal opens after three successful flirts")
	await wheel("leo", "Leo Morgan"); await ring("romantic")
	check(action("ask_partner").text.begins_with("Would you like to be my boyfriend?"), "The menu asks a man to be a boyfriend (%s)" % action("ask_partner").text)
	relation.bond = "partners"; relation.completed_dates = 2
	app.sim.romantic_partner = "maya"
	app.sim._update_relationship_status(relation)
	await wheel("maya", "Maya Chen"); await ring("romantic")
	check(action("commit").text.begins_with("Would you like to move in with me and become my wife?"), "The menu asks a woman to move in and be a wife (%s)" % action("commit").text)
	check(not action("commit").disabled, "The marriage proposal opens after two dates")

	# ---- the visitor's own choices are on the wheel from the moment they arrive
	var visit: Variant = app.residents.home_visit
	check(not visit.active(), "No visit yet")
	app.close_overlay()
	print("INTERACTION_WHEEL %d checks, %d failures" % [checks, failures.size()])
	app.queue_free(); await process_frame
	quit(0 if failures.is_empty() else 1)
