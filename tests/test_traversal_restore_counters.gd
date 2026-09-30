extends SceneTree
## Real traversal requests/restores against a tiny floor-only world. Actors never
## enter the tree, so this exercises persistence without loading a rendered home.
class FloorWorld extends RefCounted:
	var actors:Dictionary={}
	var lot_navigation:Dictionary={"generation":1}
	func route_to(from:Vector3,to:Vector3)->Dictionary:
		return {"ok":true,"generation":1,"already_reached":from==to,"points":PackedVector3Array([from,to]),"segments":[{"kind":"floor","stair_id":"","from":from,"to":to}]}

class EmptyHousehold extends RefCounted:
	func member_sim(_id:String)->LifeSim:return null

class Controller extends Node:
	var world:=FloorWorld.new()
	var household:=EmptyHousehold.new()

var checks:int=0
var failures:Array[String]=[]

func _initialize()->void:run.call_deferred()
func check(value:bool,label:String)->void:
	checks+=1
	if not value:failures.append(label);push_error(label)

func run()->void:
	var app:=Controller.new()
	for id:String in ["host","guest","next"]:
		var actor:=LifeActor.new()
		actor.position=Vector3(0,.16,0)
		app.world.actors[id]=actor
	var traversal:=LifeTraversal.new(app)
	check(bool(traversal.request("host",Vector3(2,.16,0)).ok),"Existing household floor journey is created")
	check(bool(traversal.request("guest",Vector3(0,.16,3)).ok),"Visitor floor journey is created")
	traversal.next_ticket=7
	var host:Dictionary=traversal.routes.host.duplicate(true)
	var action:Dictionary={"id":"relax","target_id":"sofa"}
	var original:Dictionary=traversal.snapshot_person("guest",action)
	var saved:Dictionary=JSON.parse_string(JSON.stringify({"version":LifeJourneyState.VERSION,"next_identity":traversal.next_identity,"next_ticket":traversal.next_ticket,"members":{"guest":original}}))
	var identity:int=int(saved.members.guest.motion.identity)
	for reload:int in 3:
		traversal.routes.erase("guest")
		check(bool(traversal.restore(saved,true).ok),"Visitor floor journey restores on reload %d"%reload)
		check(traversal.next_identity==int(saved.next_identity) and traversal.next_ticket==int(saved.next_ticket),"Paused reload %d consumes no identity or FIFO ticket"%reload)
		check(traversal.snapshot_person("guest",action)==original and int(traversal.routes.guest.identity)==identity,"Reload %d preserves the saved visitor identity and physical record"%reload)
		check(traversal.routes.host==host,"Reload %d preserves the existing household journey"%reload)
	check(bool(traversal.request("next",Vector3(-2,.16,0)).ok) and int(traversal.routes.next.identity)==int(saved.next_identity) and traversal.next_identity==int(saved.next_identity)+1,"The next real request consumes exactly the next available identity")
	check(traversal.next_ticket==7,"A real floor request does not consume a stair ticket")
	traversal.next_identity=20;traversal.next_ticket=30
	check(bool(traversal.restore(saved,true).ok) and traversal.next_identity==20 and traversal.next_ticket==30,"Older guest counters do not rewind newer household counters")
	check(bool(traversal.request("next",Vector3(-3,.16,0)).ok) and int(traversal.routes.next.identity)==20 and traversal.next_identity==21,"A real request follows the preserved household counter")
	var newer:Dictionary=saved.duplicate(true)
	newer.next_identity=40;newer.next_ticket=50
	check(bool(traversal.restore(newer,true).ok) and traversal.next_identity==40 and traversal.next_ticket==50,"Newer saved guest counters are adopted without a reconstruction increment")
	check(bool(traversal.request("next",Vector3(-4,.16,0)).ok) and int(traversal.routes.next.identity)==40 and traversal.next_identity==41,"A real request follows the adopted guest counter")
	check(bool(traversal.restore(saved).ok) and traversal.routes.size()==1 and traversal.next_identity==int(saved.next_identity) and traversal.next_ticket==int(saved.next_ticket),"Ordinary replacement restore retains its authoritative counters")
	for actor:LifeActor in app.world.actors.values():actor.free()
	app.free()
	print("TRAVERSAL_RESTORE_COUNTERS checks=%d failures=%d"%[checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
