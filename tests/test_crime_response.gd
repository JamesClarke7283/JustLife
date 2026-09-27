extends SceneTree
const Crime = preload("res://scripts/crime_response.gd")
var failures: Array[String] = []
var checks: int = 0

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, detail: String) -> void:
	checks += 1
	if not value: failures.append(detail); push_error(detail)

func advance(crime: Node, wanted: String, seconds: float = 160) -> bool:
	for frame: int in int(seconds*10):
		crime.tick(.1,.3)
		if crime.phase == wanted: return true
	return false

func _run() -> void:
	var world := LifeWorld.new(); root.add_child(world)
	var home := LifeHousehold.new(); root.add_child(home)
	home.new_household([{"name":"Parent","age_stage":"adult"},{"name":"Child","age_stage":"child"}])
	await process_frame
	world.create_home(LifeCatalog.starter_layout(0))
	await process_frame
	var crime := Crime.new(); world.add_child(crime); crime.setup(world,home); crime.set_sound(false)
	check(is_equal_approx(Crime.BASE_CHANCE,.01),"Base break-in chance is exactly 1%.")
	check(not crime.consider_night(2,.01).ok,"The 1% upper boundary does not cause a break-in.")
	check(not crime.consider_night(2,0).ok,"A night cannot be rolled twice.")
	var started: Dictionary = crime.consider_night(3,.0099)
	check(bool(started.ok),"A roll below 1% begins the physical break-in: "+str(started))
	check(crime.audio.creepy.stream is AudioStreamWAV and crime.audio.siren.stream is AudioStreamWAV,"Distinct real audio streams exist for warning and police siren.")
	var burglar_start: Vector3 = crime.burglar.position
	crime.tick(.2,.6)
	check(crime.burglar.position.distance_to(burglar_start)>0 and crime.burglar.position.distance_to(burglar_start)<.2,"Burglar visibly sneaks at walking speed rather than teleporting.")
	check(crime.burglar.find_child("BlackBeanie",true,false)!=null,"Burglar has its distinctive physical outfit and mask.")
	var funds_before: int = home.funds
	var item_count: int = world.items.size()
	check(advance(crime,"escaped"),"Unreported burglar physically visits items and leaves: "+crime.phase+" "+crime.route_error)
	check(crime.stolen_items.size()>=2 and crime.stolen_items.size()<=3,"Burglar steals a few actual household items.")
	check(world.items.size()==item_count-crime.stolen_items.size(),"Stolen items leave the furnishing registry.")
	check(home.funds==funds_before-Crime.CASH_LIMIT,"The theft subtracts real cash exactly once.")
	check(not home.member_sim("housemate_1").moodlets.filter(func(m:Dictionary)->bool:return str(m.label)=="Upset / Shaken").is_empty(),"A child as well as the adult is shaken after the burglary.")
	# Restore a genuinely JSON-encoded incident into a fresh controller/world.
	var saved: Dictionary = JSON.parse_string(JSON.stringify(crime.snapshot()))
	var saved_layout: Array = world.serialize_items()
	crime.free()
	world.create_home(saved_layout)
	await process_frame
	crime = Crime.new(); world.add_child(crime); crime.setup(world,home); crime.set_sound(false)
	check(crime.restore(saved).ok and crime.phase=="escaped","A stolen-property journal survives a fresh load after the burglar escaped.")
	check(crime.call_police("housemate_1").ok,"A child at home can report the burglar using a phone.")
	check(not crime.call_police("player").ok,"Duplicate calls do not dispatch extra police or extra payouts.")
	check(advance(crime,"officers_exiting"),"A physical police car drives from the road to the lot.")
	check(crime.police_car.position.distance_to(Crime.CURB)<.02,"The police car actually reaches the curb.")
	check(crime.officers.size()==2 and crime.officers[0].visible and crime.officers[1].visible,"Exactly two visible officers step out.")
	check(advance(crime,"scuffle"),"Both officers physically approach the burglar before the scuffle: "+crime.phase+" "+crime.route_error)
	check(crime.officers[0].position.distance_to(crime.burglar.position)<1.7,"The scuffle occurs within arm's reach.")
	check(advance(crime,"escorting"),"The officers cuff the burglar before escorting.")
	check(crime.cuff_view.visible,"Physical handcuffs are visible on the prisoner.")
	check(home.funds==funds_before+200 and crime.recovered,"Police return the full stolen cash and a single 200 bonus.")
	check(world.items.size()==item_count,"Every stolen furnishing returns to its original home.")
	for entry: Dictionary in crime.stolen_items:
		var restored: Dictionary = crime._item(str(entry.id))
		check(not restored.is_empty() and is_equal_approx(restored.node.position.x,float(entry.x)) and is_equal_approx(restored.node.position.z,float(entry.z)),"Restitution preserves original position for "+str(entry.id))
	check(advance(crime,"loading"),"Handcuffed prisoner walks all the way to the rear car door.")
	var loading_from: Vector3 = crime.burglar.position
	for i: int in 20: crime.tick(.1,.3)
	check(crime.burglar.position.distance_to(loading_from)>.2 and crime.car_entry.door_amount("rear")>.9,"The rear door opens while the prisoner physically moves into the backseat.")
	var during_loading: Dictionary = JSON.parse_string(JSON.stringify(crime.snapshot()))
	check(crime.restore(during_loading).ok,"An in-progress rear-seat loading sequence restores.")
	check(advance(crime,"departing"),"The loaded patrol departs for the police station.")
	crime.tick(.1,.3)
	check(crime.burglar.position.distance_to(crime._rear_seat())<.001,"The visible prisoner rides in the actual backseat as the car drives.")
	check(advance(crime,"jailed"),"The patrol unloads and escorts the prisoner into the actual jail.")
	check(crime.burglar.position.distance_to(Crime.STATION+Vector3(1.65,.16,0))<.05,"The prisoner ends physically inside the station custody room.")
	check(is_zero_approx(crime.station.get_node("JailDoor").rotation.y),"The barred cell door shuts after booking.")
	var expected: Array = ["police_arriving","officers_exiting","officers_approaching","scuffle","cuffing","escorting","loading","departing","station_unloading","station_escort","jailed"]
	for part: String in expected: check(part in crime.history,"Visible arrest includes phase "+part)
	var terminal: Dictionary = crime.snapshot()
	check(crime.restore(terminal).ok and home.funds==funds_before+200,"Reloading the completed arrest never repeats the payment.")
	var corrupted: Dictionary = terminal.duplicate(true); corrupted.stolen_items.append(corrupted.stolen_items[0])
	check(not crime.restore(corrupted).ok,"Duplicate stolen-property identities are rejected before mutation.")
	for field: String in ["phase_time","elapsed","stolen_cash"]:
		corrupted = terminal.duplicate(true); corrupted[field] = NAN
		check(not Crime.validate_snapshot(corrupted).is_empty(),"The save validator rejects a non-finite "+field)
	corrupted = terminal.duplicate(true); corrupted.recovered = false
	check(not Crime.validate_snapshot(corrupted).is_empty(),"A jailed save cannot claim its restitution is unpaid.")
	corrupted = terminal.duplicate(true); corrupted.stolen_items[0].x = "broken"
	check(not crime.restore(corrupted).ok and crime.phase=="jailed" and home.funds==funds_before+200,"Invalid property locations are rejected without changing the live scene or purse.")
	# Call while the burglar is actually indoors, so the officers must follow
	# the home's door graph rather than merely arresting a passer on the street.
	check(crime.begin_break_in().ok,"An indoor response can start after the first case closes.")
	for frame: int in 1400:
		crime.tick(.1,.3)
		if crime.stolen_items.size()==1: break
	check(crime.stolen_items.size()==1 and crime.burglar.position.z<4.5,"A burglary has reached the interior before the second police call.")
	check(crime.call_police("player").ok,"An adult can call police during a live indoor theft.")
	check(advance(crime,"scuffle"),"Both officers route into the actual home to engage the burglar: "+crime.phase+" "+crime.route_error)
	check(absf(crime.burglar.position.x)<5.95 and absf(crime.burglar.position.z)<4.95,"The live response scuffle is physically inside the house at "+str(crime.burglar.position))
	var scuffle_save: Dictionary = JSON.parse_string(JSON.stringify(crime.snapshot()))
	var saved_position: Vector3 = crime.burglar.position
	check(crime.restore(scuffle_save).ok and crime.burglar.position.distance_to(saved_position)<.001,"Saving during the indoor scuffle preserves exact actor locations.")
	check(advance(crime,"jailed"),"The indoor arrest completes its walk through the door, ride, and jail booking: "+crime.phase+" "+crime.route_error)
	# An alarm scares the burglar before theft and automatically summons police.
	world.add_item({"id":"crime_test_alarm","kind":"burglar_alarm","x":0.0,"z":4.4,"rotation":0.0,"hang":1.45})
	check(crime.has_alarm(),"The placed keypad alarm is detected.")
	check(crime.begin_break_in().ok,"A later incident can begin after the prior booking.")
	check(advance(crime,"police_arriving"),"The security alarm calls police automatically.")
	check(crime.alarm_triggered and crime.stolen_items.is_empty() and crime.stolen_cash==0,"The alarm scares the burglar before property or cash is taken.")
	check(advance(crime,"jailed"),"An alarm response also completes the physical arrest and jail booking.")
	# Raised wall decorations must return to the player's full 3D placement,
	# including when the theft report is saved and reloaded before the arrest.
	world.create_home([
		{"id":"raised_picture","kind":"framed_picture","x":-2.1,"z":-4.88,"rotation":0.0,"level":0,"hang":1.93,"style":"scenic","color":"5c3a24"},
		{"id":"raised_painting","kind":"painting","x":-5.85,"z":1.2,"rotation":90.0,"level":0,"hang":.64}])
	await process_frame
	var original_positions: Dictionary = {}
	for item: Dictionary in world.items: original_positions[str(item.id)] = item.node.position
	check(crime.begin_break_in().ok and advance(crime,"escaped"),"A burglar physically steals the custom-height wall decorations and escapes.")
	check(crime.stolen_items.size()==2,"Both wall decorations enter the real stolen-property journal.")
	var raised_save: Dictionary = JSON.parse_string(JSON.stringify(crime.snapshot()))
	check(Crime.validate_snapshot(raised_save).is_empty(),"Custom hanging heights survive JSON encoding as a valid theft report.")
	for entry: Dictionary in raised_save.stolen_items:
		check(is_equal_approx(float(entry.get("hang",0)),Vector3(original_positions[str(entry.id)]).y-LifeWorld.Building.GROUND_Y),"The theft report retains the exact chosen hanging height of "+str(entry.id))
	for bad_height: Variant in [NAN,INF,-.1,LifeWorld.Building.RISE+.1,"raised"]:
		var malformed: Dictionary = raised_save.duplicate(true)
		malformed.stolen_items[0]["hang"] = bad_height
		check(not Crime.validate_snapshot(malformed).is_empty(),"The theft-report validator rejects invalid hanging height "+str(bad_height))
	var absent_layout: Array = world.serialize_items()
	crime.free(); world.create_home(absent_layout)
	await process_frame
	crime = Crime.new(); world.add_child(crime); crime.setup(world,home); crime.set_sound(false)
	check(crime.restore(raised_save).ok,"A fresh crime controller restores the custom-height theft report.")
	check(crime.call_police("player").ok and advance(crime,"escorting"),"Police catch the escaped wall-art thief and complete restitution after a fresh load.")
	for id: String in original_positions:
		var returned: Dictionary = crime._item(id)
		check(not returned.is_empty() and returned.node.position.distance_to(Vector3(original_positions[id]))<.00001,"Recovered "+id+" returns to its exact original x, y and z.")
	# Once the case has returned the art, ordinary world/household saves must
	# preserve its vertical placement independently of the theft journal.
	var ordinary_layout: Array = JSON.parse_string(JSON.stringify(world.serialize_items()))
	var receiving_home := LifeHousehold.new(); root.add_child(receiving_home)
	var ordinary_save: Dictionary = home.json_safe(home.get_state(ordinary_layout))
	var ordinary_restore: Dictionary = receiving_home.restore_state(ordinary_save)
	check(bool(ordinary_restore.ok),"A normal household JSON save validates and restores the recovered wall-art layout.")
	world.create_home(ordinary_restore.get("world",ordinary_layout))
	await process_frame
	for id: String in original_positions:
		var loaded: Dictionary = crime._item(id)
		check(not loaded.is_empty() and loaded.node.position.distance_to(Vector3(original_positions[id]))<.00001,"Ordinary post-restitution save/load preserves the complete original position of "+id)
	receiving_home.queue_free()
	print("CRIME_RESPONSE_RESULT ",JSON.stringify({"checks":checks,"failures":failures,"history":crime.history}))
	world.queue_free(); home.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
