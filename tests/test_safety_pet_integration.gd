extends SceneTree
var app:Node
var checks:int=0
var failed:Array[String]=[]
func check(ok:bool,message:String) -> void:
	checks+=1
	print("CHECK ","PASS " if ok else "FAIL ",message)
	if not ok:failed.append(message)
func _initialize() -> void:
	run.call_deferred()
func frames(count:int=2) -> void:
	for _i:int in count:await process_frame
func capture(label:String) -> void:
	if not OS.get_cmdline_user_args().has("--capture"):return
	await frames(4)
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://evidence/security-pets")
	root.get_texture().get_image().save_png("res://evidence/security-pets/"+label+".png")

func labels() -> String:
	var words:PackedStringArray=[]
	for control:Node in app.overlay.find_children("*","",true,false):
		if control is Button or control is Label:words.append(control.text)
	return "\n".join(words)
func run() -> void:
	app=load("res://scenes/main.tscn").instantiate();root.add_child(app)
	await frames()
	app.start_household();await frames();app.household.set_speed(0)
	for index:int in 2:
		var review:Dictionary=LifePets.candidate(index+1,index)
		app.household.pets.pets.append(LifePets.record_from(review,"pet_%d" % (index+1),app.household.day))
	app.household.pets.next_serial=3;app.sync_pets();app.draw_live();await frames()
	app.show_pet_card("pet_1");await frames()
	await capture("cat-needs")
	check(app.selected_pet_id=="pet_1","Cat card sets the actual selected pet")
	check(labels().contains("Feed the Cat") and labels().contains("Go to Cat Bed") and labels().contains("Command to Play on Cat Tree"),"Cat card offers species-correct commands")
	check(not labels().contains("Feed the Dog") and not labels().contains("Dog House"),"Cat card has no dog commands")
	check(app.find_child("PetNeed_fun",true,false)!=null and labels().contains("Logic / Tricks"),"Personal needs include Play and Logic stats")
	app.close_overlay();app.pet_chips.pet_2.pressed.emit();await frames()
	await capture("dog-needs")
	check(app.selected_pet_id=="pet_2","Dog portrait switches selection")
	check(labels().contains("Feed the Dog") and labels().contains("Go to Dog House") and not labels().contains("Cat Tree"),"Dog card switches all species commands")
	app.close_overlay();app.pet_chips.pet_1.pressed.emit();await frames()
	check(app.selected_pet_id=="pet_1","Switching back to cat is not stuck on dog")
	var cat:LifePetActor=app.pet_actors.pet_1
	var start:Vector3=cat.position
	var destination:Vector3=start
	for offset:Vector3 in [Vector3(1,0,0),Vector3(-1,0,0),Vector3(0,0,1),Vector3(0,0,-1)]:
		if not app._pet_route("pet_1",start,start+offset).is_empty():destination=start+offset;break
	app.on_ground_clicked(destination)
	check(str(app.pet_behavior().state("pet_1").action)=="pet_move","Selected pet receives floor click")
	for step:int in 120:app._tick_pet_autonomy(.05,1.0)
	check(cat.position.distance_to(destination)<.18,"Pet physically reaches clicked floor location")
	check(app.pet_actors.pet_2.position.distance_to(destination)>.18,"Other pet is not moved by cat command")
	app.select_household_member(0);check(app.selected_pet_id.is_empty(),"Lifelet selection clears pet control")
	app.adoption_flow.show_phone();await frames()
	check(app.find_child("PhoneCallPolice",true,false)!=null,"Cell phone has emergency police call")
	app.close_overlay()
	app.adoption_flow.show_insurance();await frames()
	var buy_button:Button=app.find_child("PhoneBuyInsurance",true,false)
	check(buy_button!=null and not buy_button.disabled,"Uninsured phone screen renders the purchase action")
	check(labels().contains("1% per night"),"Phone correctly formats the 1% burglary chance")
	await capture("insurance-purchase")
	var before:int=app.household.funds
	if buy_button!=null:buy_button.pressed.emit()
	var bought:Dictionary={"ok":not app.household.insurance().is_empty()}
	check(bool(bought.ok) and before-app.household.funds==200,"Insurance purchase charges 200")
	check(not app.world.closest_item("burglar_alarm",Vector3.ZERO).is_empty(),"Insurance includes a physical wall keypad")
	check(app.safety.next_payment_day()==app.household.day+7,"Policy displays scheduled weekly payment")
	check(LifeCatalog.ITEMS.burglar_alarm.price==300 and LifeCatalog.wall_mounted("burglar_alarm"),"Buy/Build alarm costs 300 and mounts on walls")
	app.world.begin_placement("burglar_alarm");check(is_instance_valid(app.world.ghost),"Alarm has a visible placement preview");app.world.clear_placement()
	app.adoption_flow.show_insurance();await frames();await capture("insurance");check(labels().contains("Next scheduled payment"),"Insurance screen names the payment date")
	app.close_overlay()
	# Direct policy API after a loaded household shares the same schedule and alarm.
	var old_day:int=app.household.day
	app.household.day=old_day+2
	app.cancel_home_insurance()
	app.household.buy_insurance("home")
	check(app.safety.next_payment_day()==app.household.day+7,"Rebuying insurance resets the schedule to the purchase date")
	app.household.day=old_day
	app.sim.choose_career("police");app.show_career_record();await frames()
	var night:Button=app.find_child("PoliceShift_night",true,false)
	check(night!=null,"Police career exposes night shift picker")
	if night!=null:night.pressed.emit();await frames()
	await capture("police-career")
	check(str(app.sim.career.shift)=="night" and app.sim.career_pay()==150,"Night picker selects officer salary150")
	check(labels().contains("17:00") and labels().contains("09:00"),"Career record shows overnight hours")
	app.close_overlay()
	check(LifeNeighborhood.has("police_station") and not LifeVenues.layout("police_station").is_empty(),"Station is a real travel destination with furnishings")
	var journal:Dictionary=app.household_flow.get_state()
	check(journal.has("safety") and journal.safety.has("crime"),"Crime journal is saved with household extras")
	# A real household snapshot retains the case independently of selected member.
	app.household.set_speed(0)
	var began:Dictionary=app.safety.crime.begin_break_in()
	check(bool(began.ok),"Physical event can be started through integrated safety service")
	app.safety.tick(0)
	check(app.find_child("CallPoliceAlert",true,false)!=null,"An active burglary displays a callable on-screen alert")
	await capture("burglar-alert")
	var original:Dictionary=app.household.get_state(app.world.serialize_items())
	check(original.extras.safety.crime.phase=="sneaking","Real household snapshot contains current crime phase")
	check(LifeHouseholdFlow.validate(original.extras,original.world,app.household.day).is_empty(),"Household validator accepts valid live crime journal")
	var corrupt:Dictionary=original.extras.duplicate(true);corrupt.safety.crime.stolen_cash=-1
	check(not LifeHouseholdFlow.validate(corrupt,original.world,app.household.day).is_empty(),"Household validator refuses corrupt crime journal before loading")
	var old_funds:int=app.household.funds
	app.household_flow.restore(original.extras);app._sync_safety()
	check(app.safety.crime.phase=="sneaking" and app.household.funds==old_funds,"Restoring safety resumes the event without changing funds")
	app.set_build_mode(true);check(app.mode=="live","Active burglary blocks rebuilding over live responders")
	var travel_mode:String=app.mode
	app.travel_to("police_station");check(app.mode==travel_mode,"Active burglary blocks departure until case resolves")
	app.call_police();check(app.safety.crime.called,"Alert/phone callback dispatches actual police controller")
	var called:bool=app.safety.crime.called;app.current_venue="police_station";app.call_police()
	check(app.safety.crime.called==called,"Calling away cannot start a stranded offscreen response")
	app.current_venue="home"
	print("SAFETY_PET_INTEGRATION %d checks %d failures" % [checks,failed.size()])
	app.queue_free();await frames();quit(0 if failed.is_empty() else 1)
