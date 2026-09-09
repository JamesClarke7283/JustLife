extends SceneTree
## Isolated selector component. Predicates and query answers below are explicit
## stubs; the real consider(), candidate ordering, budget, cost and install run.
## This is not geometry, physical passage, persistence or natural-day evidence.
var checks:int=0
var failures:Array[String]=[]
var cases:Array=[]

class QueryProbe extends "res://scripts/courtesy.gd":
	var successful_call:int=-1
	var calls:Array=[]
	func now(_t)->float:return 100.0
	func _positions(_t)->Array:return [1,"selector-component"]
	func _blocked_candidate(_t,_id:String)->bool:return true
	func _eligible(_t,id:String)->bool:return id=="donor"
	func _current_floor_donor(_t,_id:String)->bool:return false
	func _local_pair(_t,donor:String,peer:String)->bool:return donor=="donor" and peer.begins_with("peer_")
	func _anchor_clear(_t,_id:String,_anchor:Vector3)->bool:return true
	func _sweep(_t,_id:String,_from:Vector3,_to:Vector3)->bool:return true
	func _next(_t,_id:String)->Vector3:return Vector3.ZERO
	func _hypothetical(_t,_beneficiary:String,_donor:String,_anchor:Vector3,_restoring:bool=false)->Array[Vector3]:return []
	func _hypothetical_step(_t,_id:String,_next_point:Vector3,_occupied:Array[Vector3])->bool:return false
	func _beneficiary_kind(_t,_id:String)->String:return "action"
	func _action(t,id:String)->Dictionary:return t.actions[id]
	func _benefit(t,peer:String,donor:String,anchor:Vector3,_restoring:bool=false)->PackedVector3Array:
		var index:int=calls.size()
		calls.append({"index":index,"peer":peer,"donor":donor,"anchor":anchor})
		if index!=successful_call:return PackedVector3Array()
		return PackedVector3Array([t.app.world.actors[peer].position,t.routes[peer].destination])

func check(ok:bool,label:String)->void:
	checks+=1
	print("CHECK ","PASS " if ok else "FAIL ",label)
	if not ok:failures.append(label)

func fixture(peer_count:int)->Dictionary:
	var ids:Array[String]=["donor"]
	for index:int in peer_count:ids.append("peer_"+str(index))
	var actors:Dictionary={};var routes:Dictionary={};var actions:Dictionary={}
	for index:int in ids.size():
		var id:String=ids[index];var at:Vector3=Vector3(0,.16,float(index)*10.0)
		var goal:Vector3=at+Vector3(0,0,2)
		actors[id]={"position":at}
		routes[id]={"identity":index+1,"destination":goal,"legs":[],"points":PackedVector3Array([at,goal]),"point":0,"cursor":0,"prepared":true}
		actions[id]={"id":"component_instruction","phase":"approach","target_position":goal,"paid":false,"elapsed":0.0}
	return {"app":{"household":{"speed":1},"world":{"actors":actors,"lot_navigation":{"generation":1}}},"routes":routes,"actions":actions}

func exercise(label:String,peer_count:int,successful_call:int,expected_rank:int)->void:
	var t:Dictionary=fixture(peer_count);var helper:=QueryProbe.new()
	helper.successful_call=successful_call
	for id:String in t.routes:
		helper.blocked[id]={"age":.3,"at":t.app.world.actors[id].position,"identity":t.routes[id].identity}
	var initial:Dictionary=t.duplicate(true)
	helper.consider(t)
	check(helper.trace.size()==1,label+": one actual selector invocation records one trace")
	if helper.trace.size()!=1:return
	var trace:Dictionary=helper.trace[0];var selected:Dictionary=trace.selected
	check(helper.queries==24 and int(trace.queries)==24 and helper.calls.size()==24 and trace.evaluated.size()==24,label+": real query work reaches but never exceeds24")
	check(t.app==initial.app and t.actions==initial.actions,label+": selector changes neither stub bodies nor original instructions")
	var groups:Dictionary={}
	for call:Dictionary in helper.calls:
		var anchor:Vector3=call.anchor
		if not groups.has(anchor):groups[anchor]=[]
		groups[anchor].append(str(call.peer))
	check(groups.values().all(func(peers:Array)->bool:return peers.size()<=2),label+": each actual generated anchor receives at most two peer queries")
	if peer_count==1:
		check(groups.size()==24 and groups.values().all(func(peers:Array)->bool:return peers==["peer_0"]),label+": a two-person block spends its budget across24 distinct anchors")
	else:
		check(groups.size()==12 and groups.values().all(func(peers:Array)->bool:return peers==["peer_0","peer_1"]),label+": three available peers retain deterministic first-two truncation")
	if expected_rank>=0:
		check(not selected.is_empty(),label+": complete query beyond the old anchor window is selectable")
		if not selected.is_empty():
			var peer:String="peer_0" if peer_count==1 else "peer_1"
			var route:Dictionary=t.routes.donor;var fact:Dictionary=route.courtesy
			check(int(selected.candidate_rank)==expected_rank and selected.beneficiaries==[peer],label+": chosen candidate rank and successful peer stay associated")
			check(fact.version==2 and fact.beneficiary_kind=="action" and fact.beneficiary_id==peer and int(fact.beneficiary_identity)==int(initial.routes[peer].identity),label+": installation keeps the existing typed action ownership fields")
			check(is_same(route.courtesy_action,t.actions.donor) and is_same(route.courtesy_peer_action,t.actions[peer]),label+": installation retains the original action references")
			check(route.identity==initial.routes.donor.identity and route.destination==initial.routes.donor.destination and t.routes[peer].identity==initial.routes[peer].identity and t.routes[peer].destination==initial.routes[peer].destination,label+": participant identities and final destinations remain exact")
			check(route.courtesy_priority==PackedVector3Array([initial.app.world.actors[peer].position,initial.routes[peer].destination]) and t.routes[peer].points==route.courtesy_priority,label+": selected complete answer belongs to the installed beneficiary")
	else:
		check(selected.is_empty() and helper.owner(t).is_empty() and t==initial,label+": unsuccessful or out-of-budget answers install no ownership or route change")
	cases.append({"label":label,"peer_count":peer_count,"successful_call":successful_call,"trace":trace.duplicate(true),"calls":helper.calls.duplicate(true)})

func _initialize()->void:
	var base:String=ProjectSettings.globalize_path("res://").trim_suffix("/")
	if base.get_file()!="justlife-playthrough-query-budget" or OS.get_environment("XDG_DATA_HOME")!=base.path_join("userdata") or OS.get_environment("JUSTLIFE_DATA_DIR")!=base.path_join("userdata/save_data") or ProjectSettings.has_setting("autoload/MCPRuntimeServer"):
		printerr("Private selector component project and data paths required");quit(2);return
	exercise("two_people_late_success",1,17,17)
	exercise("two_people_all_fail",1,-1,-1)
	exercise("two_people_success_outside_budget",1,24,-1)
	exercise("four_people_peer_cap",3,-1,-1)
	exercise("four_people_selected_second_peer",3,1,0)
	DirAccess.make_dir_recursive_absolute("res://evidence")
	var report:Dictionary={"scope":"Stubbed eligibility, geometry and benefit responses around real production selector; no natural-world or persistence claim.","checks":checks,"failures":failures,"cases":cases}
	var file:=FileAccess.open("res://evidence/query_budget.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(LifeSaveLibrary._json_safe(report),"  ",true,true));file.close()
	print("COURTESY_QUERY_BUDGET checks=%d failures=%d"%[checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
