extends SceneTree
const Edits=preload("res://scripts/building_edits.gd")
const Building=preload("res://scripts/building_state.gd")
func _initialize()->void:_run.call_deferred()
func _run()->void:
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
	var op:Dictionary={"op":"structure","tool":"paint","level":0,"id":"partition_s","material":"8faf9f","scope":"room","px":1.0,"pz":-2.0}
	var result:Dictionary=Edits.propose(state,op,10000)
	print("OK=",result.get("ok")," ERR=",result.get("error",""))
	quit(0)
