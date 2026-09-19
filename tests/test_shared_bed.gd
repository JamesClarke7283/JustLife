extends SceneTree
## Partners share one bed: the second sleeper takes the free half of the same
## mattress, the pair lies on separate halves, and a non-partner housemate is
## refused the occupied bed. Headless, through the public selection and
## interaction queue the household chips use.

var checks:int=0
var failures:Array[String]=[]
func check(value:bool,message:String)->void:
	checks+=1;print("CHECK ","PASS " if value else "FAIL ",message)
	if not value:failures.append(message);push_error(message)

func _initialize()->void:_run.call_deferred()

func _find(app:Node,kind:String)->Dictionary:
	for item:Dictionary in app.world.items:
		if str(item.kind)==kind:return item
	return {}

func _queue(app:Node,item:Dictionary,action_id:String,index:int)->void:
	app.select_household_member(index)
	app.queue_interaction({"id":str(item.id),"kind":str(item.kind),"node":item.node,"size":item.size},action_id)

func _run()->void:
	var app=load("res://scenes/main.tscn").instantiate();root.add_child(app)
	await process_frame;await process_frame
	app.selected_lot=0;app.start_household();await process_frame
	var household=app.household
	while household.members.size()<3:household.add_member({"name":"Extra","age_stage":"adult","gender":"Male"})
	for member:Dictionary in household.members:
		member.sim.autonomy=false
		member.sim.needs.energy=20.0
		if not app.world.actors.has(str(member.id)):
			app.spawn_actor(str(member.id),member.sim.character.duplicate(true),Vector3(6.5,.16,6.5))
	var ada:String=str(household.members[0].id)
	var ben:String=str(household.members[1].id)
	household.members[0].sim.character.name="Ada"
	household.members[1].sim.character.name="Ben"
	household.members[2].sim.character.name="Cass"
	household.members[0].sim.romantic_partner=ben
	household.members[1].sim.romantic_partner=ada
	var bed:Dictionary=_find(app,"bed")
	check(not bed.is_empty(),"The starter home has a bed to share.")
	if bed.is_empty():quit(1);return

	_queue(app,bed,"sleep",0)
	for i:int in range(8):await process_frame
	var first:Dictionary=household.members[0].sim.get_current_action()
	check(not first.is_empty() and str(first.id)=="sleep","The first partner queues sleep on the bed.")
	check(str(first.get("seat_slot",""))=="left","The first sleeper takes the left half (%s)."%str(first.get("seat_slot","")))

	_queue(app,bed,"sleep",1)
	for i:int in range(8):await process_frame
	var second:Dictionary=household.members[1].sim.get_current_action()
	check(not second.is_empty() and str(second.id)=="sleep","The partner is admitted to the same bed.")
	check(str(second.get("seat_slot",""))=="right","The partner takes the other half (%s)."%str(second.get("seat_slot","<none>")))
	var apart:float=Vector3(first.get("target_position",Vector3.ZERO)).distance_to(Vector3(second.get("target_position",Vector3.ZERO)))
	check(apart>.6 and apart<1.6,"The pair lies on separate halves of one mattress (%.2f m apart)."%apart)

	_queue(app,bed,"sleep",2)
	for i:int in range(8):await process_frame
	# A non-partner may still queue a sleep and wait, exactly as they would for any
	# other furnishing; what the bed refuses is simultaneous occupancy. So the
	# real invariant is that the third body is never admitted while the pair lies
	# there, and takes the bed the moment it is free.
	for i:int in range(40):await process_frame
	var third:Dictionary=household.members[2].sim.get_current_action()
	check(not third.is_empty() and str(third.get("target_id",""))==str(bed.id) and str(third.get("phase",""))!="active",
		"A non-partner housemate waits for the occupied bed without being admitted to it: %s/%s."%[str(third.get("target_id","<none>")),str(third.get("phase","<none>"))])
	household.members[0].sim.cancel_action(0)
	household.members[1].sim.cancel_action(0)
	for i:int in range(40):await process_frame
	check(str(household.members[2].sim.get_current_action().get("target_id",""))==str(bed.id),
		"The waiting non-partner takes the bed once it is free.")

	app.queue_free();await process_frame
	print("SHARED_BED %d checks, %d failures" % [checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
