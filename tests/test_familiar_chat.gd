extends SceneTree
var checks:int=0
var failures:int=0
func _initialize()->void:call_deferred("run")
func check(value:bool,message:String)->void:
	checks+=1
	if not value:failures+=1;push_error(message)
func friend_want(sim:LifeSim)->Dictionary:
	for want:Dictionary in sim.wants:
		if str(want.id)=="friend":return want
	return {}
func finish(home:LifeHousehold,id:String,target:String,action:String="friendly")->void:
	check(home.member_sim(id).queue_action(action,target),"A familiar conversation queues.")
	home.begin_action(id)
	for i:int in range(20):home.tick(.5)
	check(home.member_sim(id).action_queue.is_empty(),"The conversation completes.")
func run()->void:
	var home:=LifeHousehold.new();root.add_child(home)
	home.new_household([{"name":"Parent","age_stage":"adult","aspiration":"Maker"},{"name":"Child","age_stage":"child","aspiration":"Maker"}])
	check(home.configure_family([{"a":"player","b":"housemate_1","role":"parent"}]).ok,"A starting family is configured.")
	for member:Dictionary in home.members:member.sim.autonomy=false
	for i:int in range(10):home.tick(.5)
	check(home.funds==2500 and home.selected().satisfaction==0,"Existing family friendship does not pay an opening reward without conversation.")
	check(friend_want(home.selected()).progress==0 and not friend_want(home.selected()).complete,"Fresh familiar-face want waits for participation.")
	var json:JSON=JSON.new();json.parse(JSON.stringify(home.get_state()))
	var restored:=LifeHousehold.new();root.add_child(restored)
	check(restored.restore_state(json.data).ok and friend_want(restored.selected()).metric=="familiar_chat","An unfinished new goal restores through JSON.")
	for i:int in range(4):restored.tick(.5)
	check(restored.funds==2500,"Restoring before a conversation grants no reward.")
	check(home.selected().queue_action("friendly","housemate_1"),"A partial family conversation queues.")
	home.begin_action("player");home.tick(.25);home.selected().cancel_action()
	check(home.funds==2500 and not friend_want(home.selected()).complete,"Canceled partial conversation grants no familiar-face reward.")
	finish(home,"player","housemate_1")
	check(friend_want(home.selected()).complete and friend_want(home.member_sim("housemate_1")).complete,"Both participating Lifelets complete their fresh familiar-face goal.")
	check(home.funds==2660 and home.selected().satisfaction==80 and home.member_sim("housemate_1").satisfaction==80,"Both rewards enter the shared wallet exactly once.")
	finish(home,"player","housemate_1","joke")
	check(home.funds==2660,"A second conversation cannot repeat either reward.")
	home.new_household([{"name":"First","aspiration":"Maker"},{"name":"Second","aspiration":"Maker"}])
	for member:Dictionary in home.members:member.sim.autonomy=false
	finish(home,"player","housemate_1")
	check(home.funds==2500 and not friend_want(home.selected()).complete,"A completed conversation below35 friendship does not satisfy the threshold.")
	finish(home,"player","housemate_1")
	check(home.funds==2660,"The next completed conversation reaching35 friendship fulfills both goals.")
	# Earlier saves retain their original absolute-friendship goal semantics.
	home.new_household([{"aspiration":"Maker"},{"aspiration":"Maker"}]);home.configure_family([{"a":"player","b":"housemate_1","role":"siblings"}])
	var legacy:Dictionary=home.get_state()
	for member:Dictionary in legacy.members:
		for want:Dictionary in member.state.wants:
			if str(want.id)=="friend":
				for key:String in ["metric","actions","seen","seen_days","skill"]:want.erase(key)
				want.description="Build a friendship to35.";want.target=35.0
	check(restored.restore_state(legacy).ok,"An older unfinished friendship goal remains loadable.")
	for member:Dictionary in restored.members:member.sim.autonomy=false
	restored.tick(.5)
	check(restored.funds==2660 and friend_want(restored.selected()).complete,"Legacy absolute-threshold goal keeps its prior behavior.")
	var earned:Dictionary=restored.get_state()
	check(home.restore_state(earned).ok,"Already earned legacy friendship rewards remain loadable.")
	home.tick(.5)
	check(home.funds==2660,"Loading an already earned legacy reward does not award it again.")
	home.queue_free();restored.queue_free();await process_frame
	print("FAMILIAR CHAT TESTS: %d checks, %d failures"%[checks,failures]);quit(0 if failures==0 else 1)
