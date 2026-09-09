extends SceneTree

var count:int=0
var failed:int=0

func check(value:bool,message:String) -> void:
	count+=1
	if not value:failed+=1;push_error(message)

func _initialize() -> void:
	var sim=LifeSim.new()
	sim.autonomy=false
	for key in sim.needs:sim.needs[key]=90
	sim.add_moodlet("A new canvas","Inspired","Something creative.",20,3)
	check(sim.get_mood().label=="Inspired","An activity can leave a persistent emotion")
	sim.set_speed(0);sim.tick(10)
	check(sim.moodlets[0].remaining==20,"Pause preserves emotion duration")
	sim.set_speed(1);sim.tick(24.0/LifeSim.GAME_MINUTES_PER_SECOND)
	check(sim.moodlets.is_empty(),"Timed emotions expire with the simulation clock")
	check(sim.choose_career("culinary"),"A Lifelet can choose a culinary career")
	check(sim.career.title=="Kitchen assistant" and sim.career.salary==160,"Career changes have actual titles and pay")
	sim.career.performance=100;sim._check_promotion()
	check(sim.career.title=="Prep cook" and sim.career.salary==270,"Promotions follow the selected career")
	check(sim.memories.size()==2,"Career milestones become personal memories")
	sim.queue_action("job","desk")
	check(not sim.choose_career("technology"),"Queued shifts cannot be switched to a different career pay scale")
	sim.cancel_action()
	check(sim.choose_career("technology") and sim.career.title=="Support specialist","Changing careers after cancel works")
	sim.add_moodlet("Stress","Tense","A hard day.",100,4)
	sim.needs.hunger=5
	check(sim.get_mood().label=="Hungry","Critical needs still take precedence over moodlets")
	var state=sim.get_state()
	var copy=LifeSim.new()
	check(copy.restore_state(state).ok,"Progression snapshot is valid")
	check(copy.moodlets.size()==sim.moodlets.size() and copy.memories.size()==sim.memories.size(),"Emotions and memories persist")
	var damaged=state.duplicate(true);damaged.moodlets[0].remaining="bad"
	check(not copy.restore_state(damaged).ok,"Malformed timed emotions are rejected")
	sim.free();copy.free()
	print("PROGRESSION_TESTS ",count," assertions; ",failed," failures")
	quit(1 if failed else 0)
