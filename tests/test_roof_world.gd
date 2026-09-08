extends SceneTree
const Building=preload("res://scripts/building_state.gd")
const Rules=preload("res://scripts/roof_rules.gd")
const World=preload("res://scripts/world.gd")
var checks:int=0
var failures:Array[String]=[]
func _initialize()->void:_run.call_deferred()
func check(value:bool,message:String)->void:
	checks+=1;print("CHECK ","PASS " if value else "FAIL ",message)
	if not value:failures.append(message);push_error(message)
func base()->Dictionary:
	var state:Dictionary=Building.fresh();state.floors=[{"id":"floor","level":0,"x":0.0,"z":0.0,"w":8.0,"d":10.0,"material":"cfa97e"}]
	for sign:int in [-1,1]:
		state.walls.append({"id":"west" if sign<0 else "east","level":0,"x":sign*4.0,"z":0.0,"w":.14,"d":10.0,"height":2.6,"cut":true,"material":"eae7d7"})
		state.walls.append({"id":"north" if sign<0 else "south","level":0,"x":0.0,"z":sign*5.0,"w":8.0,"d":.14,"height":2.6,"cut":true,"material":"eae7d7"})
	return state
func roof_record()->Dictionary:return {"level":0,"x":0.0,"z":0.0,"w":8.0,"d":10.0,"pitch":.5,"rotation":0,"material":"57736a","supports":["west","east"]}
func _run()->void:
	var world:=World.new();root.add_child(world);await process_frame
	var state:Dictionary=base();check(Building.validate(state).is_empty(),"Actual whole-perimeter ground home is valid before its roof.")
	var quote:Dictionary=Building.propose(state,{"op":"add","collection":"roofs","record":roof_record()},3000)
	check(bool(quote.ok) and int(quote.cost)==1440,"Detached complete roof quote retains its original§18 per square metre price.")
	check(bool(world.load_home([quote.after,{"id":"fridge","kind":"fridge","x":0.0,"z":0.0,"rotation":0}]).ok),"Actual world loads validated roof data and existing furniture.")
	world.construction.set_roof_visibility(true)
	check(world.construction.roof_nodes.size()==1 and world.construction.roof_nodes.values()[0].visible,"World renderer builds the parameterized roof from its persisted record.")
	var scene_id:int=world.house.get_instance_id();var original:Array=world.serialize_items().duplicate(true)
	var edge:Dictionary=base()
	for group:String in ["walls","floors"]:
		for entry:Dictionary in edge[group]:entry.x+=4.75
	var record:Dictionary=roof_record();record.x+=4.75
	check(Building.validate(edge).is_empty(),"Edge fixture support footprint and bearing walls are valid inside the lot.")
	var rejected:Dictionary=Building.propose(edge,{"op":"add","collection":"roofs","record":record},3000)
	check(not bool(rejected.ok) and str(rejected.error).contains("eaves"),"A roof whose support fits but full eaves cross the lot edge is rejected.")
	var bad:Dictionary=quote.after.duplicate(true)
	for group:String in ["walls","floors","roofs"]:
		for entry:Dictionary in bad[group]:entry.x+=4.75
	check(not bool(world.load_home([bad]).ok) and world.house.get_instance_id()==scene_id and world.serialize_items()==original,"Malformed roof ingress cannot replace the current home or its refrigerator.")
	var slab:Dictionary=Building.propose(quote.after,{"op":"add","collection":"floors","record":{"level":1,"x":0.0,"z":0.0,"w":8.0,"d":10.0,"material":"cfa97e","supports":["west","east"]}},3000)
	check(not bool(slab.ok) and str(slab.error).contains("height envelope"),"An upper slab cannot intersect an existing lower roof's full vertical extent.")
	var other:Dictionary=roof_record();other.id="other";other.x=.25
	var overlapping:Dictionary={"roofs":[quote.after.roofs[0],other],"floors":[],"walls":[]}
	check(not Rules.validate(overlapping).is_empty(),"Separate overlapping roof/eave envelopes reject in the pure geometric rule.")
	var obstacle:Dictionary=base();obstacle.walls.append({"id":"eave_blocker","level":0,"x":4.2,"z":0.0,"w":.14,"d":2.0,"height":2.6,"cut":true,"material":"eae7d7"})
	var blocked:Dictionary=Building.propose(obstacle,{"op":"add","collection":"roofs","record":roof_record()},3000)
	check(not bool(blocked.ok) and str(blocked.error).contains("eave"),"A neighboring wall in the overhang is rejected despite valid support geometry.")
	var steep:Dictionary=quote.after.duplicate(true);steep.roofs[0].pitch=1.0
	check(Building.validate(steep).is_empty(),"Valid steep roof remains supported and within its full lot envelope.")
	check(bool(world.load_home([steep,{"id":"shower","kind":"shower","x":0.0,"z":0.0,"rotation":0}]).ok),"Actual imported shower under a steep ridge fits without using the low remote eave as its ceiling.")
	check(Rules.obstruction(steep,AABB(Vector3(-.3,3.5,-.3),Vector3(.6,3.5,.6)))!="","An object crossing the actual high roof section is rejected.")
	var serialized:Array=JSON.parse_string(JSON.stringify(world.serialize_items()));var restored:=World.new();root.add_child(restored)
	var restore_result:Dictionary=restored.load_home(serialized)
	print("ROOF_RESTORE_DIAGNOSTIC ",JSON.stringify({"result":restore_result,"node_count":restored.construction.roof_nodes.size(),"before":world.construction.building_state.roofs,"after":restored.construction.building_state.get("roofs",[])}))
	var same:bool=bool(restore_result.ok) and restored.construction.roof_nodes.size()==1 and restored.construction.building_state.roofs.size()==1
	if same:
		var before:Dictionary=world.construction.building_state.roofs[0];var after:Dictionary=restored.construction.building_state.roofs[0]
		for key:String in ["id","material","supports"]:same= same and before[key]==after[key]
		# Godot JSON restores valid whole numbers as floats. Compare the schema's
		# numeric values while still demanding exact identity/material/supports.
		for key:String in ["level","rotation","x","z","w","d","pitch"]:same=same and is_equal_approx(float(before[key]),float(after[key]))
	check(same,"Fresh world-node JSON restore reconstructs one roof with unchanged pitch/yaw/material/identity.")
	for invalid:Variant in ["0",.25]:
		var malformed:Array=serialized.duplicate(true)
		for entry:Dictionary in malformed:
			if str(entry.get("kind",""))=="__construction":entry.roofs[0].rotation=invalid
		check(not bool(restored.load_home(malformed).ok),"Malformed roof rotation rejects despite legitimate JSON integer-to-float conversion.")
	world.construction.set_roof_visibility(false)
	check(not world.construction.roof_nodes.values()[0].visible and world.construction.building_state.roofs.size()==1,"Roof cutaway hides only presentation and retains persisted geometry.")
	var upper:Dictionary=Building.propose(base(),{"op":"add","collection":"floors","record":{"level":1,"x":0.0,"z":0.0,"w":8.0,"d":10.0,"material":"cfa97e","supports":["west","east"]}},3000)
	check(bool(upper.ok),"Actual upper roof fixture starts with a completely supported storey slab.")
	if bool(upper.ok):
		var upper_state:Dictionary=upper.after
		for wall:Dictionary in base().walls:
			var raised:Dictionary=wall.duplicate(true);raised.id="upper_"+str(wall.id);raised.level=1;upper_state.walls.append(raised)
		var upper_record:Dictionary=roof_record();upper_record.level=1;upper_record.supports=["upper_west","upper_east"]
		var upper_roof:Dictionary=Building.propose(upper_state,{"op":"add","collection":"roofs","record":upper_record},3000)
		check(bool(upper_roof.ok) and bool(restored.load_home([upper_roof.after]).ok),"Actual world loads a roof on supported upper perimeter walls.")
		if bool(upper_roof.ok) and not restored.construction.roof_nodes.is_empty():
			var upper_node:Node3D=restored.construction.roof_nodes.values()[0]
			check(is_equal_approx(upper_node.position.y,5.76),"Upper roof has its real wall-top elevation, not a cosmetically raised ground slab.")
			restored.construction.set_roof_visibility(true);restored.set_view_level(0)
			check(not upper_node.visible,"Ground cutaway hides the upper roof without changing its record.")
			restored.set_view_level(1)
			check(upper_node.visible and restored.construction.building_state.roofs.size()==1,"Upper view restores the same parameterized roof model and record.")
	var file:=FileAccess.open("user://roof_world.json",FileAccess.WRITE);file.store_string(JSON.stringify({"checks":checks,"failures":failures},"  "));file.close()
	world.queue_free();restored.queue_free();await process_frame;print("ROOF_WORLD checks=%d failures=%d"%[checks,failures.size()]);quit(0 if failures.is_empty() else 1)
