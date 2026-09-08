extends SceneTree
## Controller/resource checks; arrival is explicit, without renderer or path claims.
var checks:int=0
var failures:int=0
func _initialize() -> void:run.call_deferred()
func check(value:bool,detail:String) -> void:
	checks+=1
	if not value:failures+=1;push_error(detail)
func add_item(world:LifeWorld,id:String,kind:String,at:Vector3) -> Dictionary:
	var node:Node3D=Node3D.new();world.add_child(node);node.position=at
	var item:Dictionary={"id":id,"kind":kind,"node":node,"size":Vector2.ONE}
	world.items.append(item);return item
func run() -> void:
	var app:Node=load("res://scripts/main.gd").new()
	app.world=LifeWorld.new();root.add_child(app.world)
	app.household=LifeHousehold.new();root.add_child(app.household)
	app.household.new_household([{"age_stage":"child"},{"age_stage":"adult"}])
	var desk:Dictionary=add_item(app.world,"desk","desk",Vector3.ZERO)
	var chair:Dictionary=add_item(app.world,"chair","chair",Vector3(0,0,.88))
	var second:Dictionary=add_item(app.world,"second_desk","desk",Vector3(.5,0,0))
	var separate:Dictionary=add_item(app.world,"separate_desk","desk",Vector3(4,0,0))
	add_item(app.world,"separate_chair","chair",Vector3(4,0,.88))
	var targets:Array=[]
	for item:Dictionary in app.world.items:targets.append({"id":item.id,"kind":item.kind,"position":item.node.position})
	for member:Dictionary in app.household.members:member.sim.register_targets(targets);member.sim.autonomy=false
	var child:LifeSim=app.household.members[0].sim
	var adult:LifeSim=app.household.members[1].sim
	check(child.queue_action("school","desk"),"A child can reserve a real school desk.")
	app.bound_member_id="player"
	check(app._activity_available(child.get_current_action()),"An unoccupied desk and chair are available.")
	child.begin_current_action()
	check(adult.queue_action("relax","chair"),"The adult can queue a chair activity while school is active.")
	app.bound_member_id="housemate_1"
	check(not app._activity_available(adult.get_current_action()),"An active class reserves its separate support chair.")
	check(not app._activity_available({"target_id":"second_desk"}),"Different desks sharing one chair cannot seat two Lifelets at once.")
	check(app._activity_available({"target_id":"separate_desk"}),"An unrelated desk/chair remains usable.")
	child.cancel_action()
	check(app._activity_available(adult.get_current_action()),"Canceling school releases the support chair immediately.")
	adult.begin_current_action()
	check(child.queue_action("school","desk"),"A class can wait in the queue for a seated Lifelet.")
	app.bound_member_id="player"
	check(not app._activity_available(child.get_current_action()),"An occupied support chair blocks a new desk activity in the reverse order too.")
	adult.cancel_action()
	check(app._activity_available(child.get_current_action()),"Canceling the seat activity releases the waiting class.")
	check(app.world.activity_resource_ids(desk).has("chair") and not app.world.activity_resource_ids(separate).has("chair"),"Reservations reflect the actual nearest supporting chair.")
	app.world.items.erase(chair)
	check(app.world.activity_resource_ids(desk)==["desk"],"A removed support chair cannot leave a stale reservation.")
	app.household.queue_free();app.world.queue_free();app.free();await process_frame
	print("DESK_OCCUPANCY %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)
