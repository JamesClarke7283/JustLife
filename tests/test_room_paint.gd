extends SceneTree
## Room-aware whole-room paint: a click repaints only the enclosed room on the
## clicked side; door gaps stay room boundaries; a wall shared with the next
## room changes for both rooms; an unbounded side falls back to joined walls.
const Edits=preload("res://scripts/building_edits.gd")
const Building=preload("res://scripts/building_state.gd")

var checks:int=0
var failures:Array[String]=[]

func _initialize()->void:_run.call_deferred()

func check(value:bool,message:String)->void:
	checks+=1
	if not value:
		failures.append(message);push_error(message)

func cottage() -> Dictionary:
	# Eight-metre by ten-metre shell, partition at x=0 with a 1.06 m doorway
	# gap at z -0.53..0.53, every room wall a separate segment.
	var state:Dictionary=Building.fresh()
	state.floors=[{"id":"ground","level":0,"x":0.0,"z":0.0,"w":8.0,"d":10.0,"material":"cfa97e"}]
	state.walls=[
		{"id":"north_w","level":0,"x":-2.0,"z":-5.0,"w":4.0,"d":.14,"height":2.6,"cut":true,"material":"eae7d7"},
		{"id":"north_e","level":0,"x":2.0,"z":-5.0,"w":4.0,"d":.14,"height":2.6,"cut":true,"material":"eae7d7"},
		{"id":"south_w","level":0,"x":-2.0,"z":5.0,"w":4.0,"d":.14,"height":2.6,"cut":true,"material":"eae7d7"},
		{"id":"south_e","level":0,"x":2.0,"z":5.0,"w":4.0,"d":.14,"height":2.6,"cut":true,"material":"eae7d7"},
		{"id":"west","level":0,"x":-4.0,"z":0.0,"w":.14,"d":10.0,"height":2.6,"cut":true,"material":"eae7d7"},
		{"id":"east","level":0,"x":4.0,"z":0.0,"w":.14,"d":10.0,"height":2.6,"cut":true,"material":"eae7d7"},
		{"id":"partition_s","level":0,"x":0.0,"z":-2.765,"w":.14,"d":4.47,"height":2.6,"cut":true,"material":"eae7d7"},
		{"id":"partition_n","level":0,"x":0.0,"z":2.765,"w":.14,"d":4.47,"height":2.6,"cut":true,"material":"eae7d7"},
	]
	return state

func paint(state:Dictionary,wall_id:String,px:float,pz:float,colour:String="8faf9f",scope:String="room") -> Dictionary:
	var operation:Dictionary={"op":"structure","tool":"paint","level":0,"id":wall_id,"material":colour,"scope":scope,"px":px,"pz":pz}
	return Edits.propose(state,operation,10000)

func changed_ids(before:Dictionary,after:Dictionary) -> Array:
	var out:Array=[]
	for wall:Dictionary in after.walls:
		for old:Dictionary in before.walls:
			if str(old.id)==str(wall.id) and str(old.material)!=str(wall.material):out.append(str(wall.id))
	return out

func has_only(ids:Array,expected:Array) -> bool:
	if ids.size()!=expected.size():return false
	for id:String in ids:
		if not expected.has(id):return false
	return true

func _run()->void:
	var bedroom: Array=["partition_s","partition_n","north_e","south_e","east"]
	var living: Array=["partition_s","partition_n","north_w","south_w","west"]
	# The partition clicked from the bedroom repaints the bedroom's five walls
	# and nothing in the living room.
	var state:Dictionary=cottage()
	var result:Dictionary=paint(state,"partition_s",1.0,-2.0)
	check(bool(result.ok),"Bedroom-side partition paint succeeds: '"+str(result.get("error",""))+"'.")
	var changed:Array=changed_ids(state,result.after)
	check(has_only(changed,bedroom),
		"The bedroom click paints exactly the bedroom walls ('"+str(changed)+"').")
	# The same partition clicked from the living room repaints the living room.
	result=paint(state,"partition_s",-1.0,-2.0)
	changed=changed_ids(state,result.after)
	check(has_only(changed,living),
		"The living-side click paints exactly the living walls ('"+str(changed)+"').")
	# A living-room outer wall repaints the living shell, not the bedroom.
	result=paint(state,"west",-1.0,0.0)
	changed=changed_ids(state,result.after)
	check(has_only(changed,living),
		"The west wall paints the whole living shell ('"+str(changed)+"').")
	# A freestanding garden wall leaks outdoors on both sides: the honest
	# fallback is the joined-wall scope, which for a lone wall is itself.
	state.walls.append({"id":"garden","level":0,"x":8.0,"z":0.0,"w":.14,"d":3.0,"height":2.6,"cut":true,"material":"eae7d7"})
	result=paint(state,"garden",8.0,0.0)
	changed=changed_ids(state,result.after)
	check(has_only(changed,["garden"]),"A freestanding garden wall paints alone ('"+str(changed)+"').")
	# Repainting the bedroom in its own colour is the documented no-op error.
	var state2:Dictionary=cottage()
	var first:Dictionary=paint(state2,"partition_s",1.0,-2.0)
	var again:Dictionary=paint(first.after,"partition_s",1.0,-2.0)
	check(not bool(again.ok) and str(again.get("error","")).contains("already have this colour"),
		"Repainting the bedroom in its own colour is the documented no-op ('"+str(again.get("error",""))+"').")
	# The single-wall scope still exists for precise touches.
	var single:Dictionary=paint(state2,"east",3.5,1.0,"8faf9f","wall")
	check(changed_ids(state2,single.after)==["east"],
		"Single-wall scope repaints exactly one segment ('"+str(changed_ids(state2,single.after))+"').")
	print("ROOM_PAINT %d checks, %d failures"%[checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
