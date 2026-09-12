extends SceneTree
## Rendered evidence for iteration 60's family slice: a partnered pair asleep
## on the two halves of one bed, the Try-for-Baby cover beat, and the born
## baby crawling on the home floor. Writes PNGs into the evidence directory.

var checks:int=0
var failures:Array[String]=[]
func check(value:bool,message:String)->void:
	checks+=1;print("CHECK ","PASS " if value else "FAIL ",message)
	if not value:failures.append(message);push_error(message)

func _initialize()->void:_run.call_deferred()

func _shot(label:String)->void:
	await RenderingServer.frame_post_draw
	var image:Image=root.get_texture().get_image()
	var path:="res://evidence/family60/%s.png"%label
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://evidence/family60"))
	image.save_png(path)
	print("EVIDENCE_SHOT ",label)

func _frames(n:int)->void:
	for i:int in range(n):await process_frame

func _find(app:Node,kind:String)->Dictionary:
	for item:Dictionary in app.world.items:
		if str(item.kind)==kind:return item
	return {}

func _run()->void:
	var app=load("res://scenes/main.tscn").instantiate();root.add_child(app)
	await process_frame;await process_frame
	app.selected_lot=0;app.start_household();await process_frame
	var household=app.household
	while household.members.size()<2:household.add_member({"name":"Partner","age_stage":"adult","gender":"male"})
	for member:Dictionary in household.members:
		if not app.world.actors.has(str(member.id)):
			app.spawn_actor(str(member.id),member.sim.character.duplicate(true),Vector3(6.5,.16,6.5))
	# Rename through both directions of every relationship, exactly as the
	# creator does, so the household stays a valid save for commit_baby.
	for index:int in range(household.members.size()):
		var value:String=["Ada","Ben"][index]
		household.members[index].sim.character.name=value
		for other:int in range(household.members.size()):
			if other==index:continue
			household.members[other].sim.relationships[str(household.members[index].id)].name=value
	household.members[0].sim.character.gender="female"
	household.members[1].sim.character.gender="male"
	var ids:Array[String]=[str(household.members[0].id),str(household.members[1].id)]
	household.members[0].sim.romantic_partner=ids[1]
	household.members[1].sim.romantic_partner=ids[0]
	# Declare the partner bond in both relationship records, exactly as the
	# ask_partner action writes it, so the household stays a valid save.
	for pair:Array in [[0,1],[1,0]]:
		var relationship:Dictionary=household.members[pair[0]].sim.relationships[ids[pair[1]]]
		relationship["bond"]="partners"
		relationship["family_role"]="none"
		relationship["status"]=LifeFamilyGraph.label("none")
	for member:Dictionary in household.members:
		member.sim.autonomy=false
		member.sim.needs.energy=20.0
	var bed:Dictionary=_find(app,"bed")
	# Both partners asleep on their own halves.
	app.select_household_member(0)
	app.queue_interaction({"id":str(bed.id),"kind":str(bed.kind),"node":bed.node,"size":bed.size},"sleep")
	await _frames(4)
	app.select_household_member(1)
	app.queue_interaction({"id":str(bed.id),"kind":str(bed.kind),"node":bed.node,"size":bed.size},"sleep")
	await _frames(4)
	# Let both sleepers actually reach the mattress before the beat.
	household.set_speed(8)
	var settle:int=0
	while settle<600:
		var sleeping:int=0
		for member:Dictionary in household.members:
			var action:Dictionary=member.sim.get_current_action()
			if not action.is_empty() and str(action.get("phase",""))=="active" and str(action.get("id",""))=="sleep":sleeping+=1
		if sleeping>=2:break
		await process_frame
		settle+=1
	household.set_speed(1)
	app.world.camera_target=bed.node.position;app.world.camera_distance=5.2;app.world.update_camera()
	await _frames(8)
	await _shot("01_partners_share_bed")
	var slots:Array=[]
	for member:Dictionary in household.members:
		var action:Dictionary=member.sim.get_current_action()
		slots.append("%s=%s"%[str(member.id),str(action.get("seat_slot",""))])
	check(slots.has("player=left") and slots.has("housemate_1=right"),"Rendered pair holds the two halves: "+str(slots))
	# Try for Baby: the beat and its cover, captured mid-moment.
	household.set_speed(1)
	# The public menu path starts the beat AND builds its ruffling covers with it.
	app.try_for_baby(bed)
	var begun:Dictionary={"ok":not household.cooperations.is_empty()}
	check(bool(begun.ok),"The public beat starts for the asleep pair.")
	await _frames(4)
	await _frames(20)
	check(app.cover_beat != null,"The ruffling cover presentation is active during the beat.")
	await _shot("02_try_for_baby_covers")
	household.tick((LifeBabyPlan.DURATION*.4)/LifeSim.GAME_MINUTES_PER_SECOND)
	await _frames(10)
	check(app.cover_beat != null,"The covers still ruffle mid-moment.")
	await _shot("03_try_for_baby_covers_mid")
	# Finish the beat and let the pregnancy run its three days.
	household.tick((LifeBabyPlan.DURATION+1.0)/LifeSim.GAME_MINUTES_PER_SECOND)
	await _frames(6)
	check(bool(household.pregnancy.get("active",false)),"The beat leaves a running pregnancy.")
	var expecting=household.members[0].sim
	var has_moodlet:bool=false
	for mood:Dictionary in expecting.moodlets:has_moodlet = has_moodlet or str(mood.get("label",""))=="Expecting"
	check(has_moodlet,"The expecting mother shows the countdown moodlet in the HUD.")
	await _shot("04_pregnancy_moodlet")
	household.set_speed(1)
	var guard:int=0
	while bool(household.pregnancy.get("active",false)) and guard<400:
		household.tick(60.0/LifeSim.GAME_MINUTES_PER_SECOND)
		guard+=1
	await _frames(20)
	var pending:Dictionary=household.pending_baby_profile()
	check(not pending.is_empty(),"The birth left a pending baby profile for the creator.")
	if not (app.mode=="creator" and app.creator_purpose=="baby"):
		app.show_baby_creator()
		await _frames(6)
	check(app.mode=="creator" and app.creator_purpose=="baby","The birth opens the baby creator.")
	await _shot("05_baby_creator")
	app.profile.name="Wren Solis"
	app.profile.gender="female"
	app.profile.skin_color="925c40"
	app.profile.hair=4
	app.profile.hair_color="dfccb0"
	app.profile.eye_color="55738f"
	app.refresh_preview()
	await _frames(12)
	await _shot("06_baby_creator_edited")
	var members_pre:int=household.members.size()
	app.confirm_baby_creator()
	await _frames(40)
	var baby_id:String=""
	for member:Dictionary in household.members:
		if str(member.sim.character.get("age_stage",""))=="baby":baby_id=str(member.id)
	check(not baby_id.is_empty(),"The confirmed baby joins the household.")
	if not baby_id.is_empty():
		# The newborn walks in from the street; let the arrival settle so the
		# body is present before the capture.
		# Let the newborn walk in at speed: the arrival completes on the real
		# household tick, which is what leaves a body on the lot.
		household.set_speed(8)
		var arrival_wait:int=0
		while arrival_wait<900 and not app.world.actors.has(baby_id):
			await process_frame
			arrival_wait+=1
		household.set_speed(1)
		var actor=app.world.actors.get(baby_id)
		check(actor!=null,"The baby has a body on the home lot.")
		if actor!=null:
			app.world.camera_target=actor.position
			app.world.camera_distance=3.4
			app.world.update_camera()
			await _frames(8)
			await _shot("07_baby_at_home")
			# Walk the baby so the crawl pose is captured in motion.
			var target:Vector3=actor.position+Vector3(2.6,0,0)
			app.household.select(app.household.members.find(func(m:Dictionary)->bool:return str(m.id)==baby_id))
			app.sim.queue_action("walk_only")
			app.world.actors[baby_id].position=target
			actor.animate(0.05,1.0,true,"")
			await _frames(6)
			await _shot("08_baby_crawling")
			check(true,"The crawling baby is captured in the live view.")
	app.queue_free();await process_frame
	print("FAMILY_EVIDENCE %d checks, %d failures" % [checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
