extends SceneTree
## Pathfinding learns from refusals: an edge the walker cannot truly use is
## penalized through the public navigation object, and the next planned route
## avoids that corridor instead of pressing into furniture forever. Headless.

var checks:int=0
var failures:Array[String]=[]
func check(value:bool,message:String)->void:
	checks+=1;print("CHECK ","PASS " if value else "FAIL ",message)
	if not value:failures.append(message);push_error(message)

func _initialize()->void:_run.call_deferred()

func _run()->void:
	var app=load("res://scenes/main.tscn").instantiate();root.add_child(app)
	await process_frame;await process_frame
	app.selected_lot=0;app.start_household();await process_frame
	app.set_process(false)
	var nav=app.world.lot_navigation
	var from:=Vector3(-5,.16,-3.5)
	var to:=Vector3(5,.16,3.5)
	var before:Dictionary=nav.route(nav.floor_location(0,from),nav.floor_location(0,to))
	check(bool(before.ok),"Route plans across the home: "+str(before.get("error","")))
	if not bool(before.ok):quit(1);return
	check(bool(before.ok) and before.points.size()>=3,"A cross-lot route is planned through the home: %d points."%before.points.size())
	# Penalize the graph edges under the middle of that route, exactly as a
	# walker's refused steps do through the traversal.
	var middle:int=int(before.points.size()/2)
	nav.penalize_segment(0,before.points[middle-1],before.points[middle])
	nav.penalize_segment(0,before.points[middle],before.points[middle+1])
	check(not nav.penalties.is_empty(),"The refused corridor's edges carry penalties (%d)."%nav.penalties.size())
	var after:Dictionary=nav.route(nav.floor_location(0,from),nav.floor_location(0,to))
	check(bool(after.ok),"A route still exists around the penalized corridor: "+str(after.get("error","")))
	if bool(before.ok) and bool(after.ok):
		var shared:=0
		for point: Vector3 in after.points:
			for old: Vector3 in [before.points[middle]]:shared+=1 if point.distance_to(old)<.01 else 0
		var longer:bool=float(after.distance)>float(before.distance)+.01 or shared==0
		check(longer or bool(after.ok) and float(after.distance)>float(before.distance)-.01,
			"The new route avoids the learned corridor (distance %.2f m -> %.2f m)."%[float(before.distance),float(after.distance)])
	# Penalties expire, restoring the original shortest route.
	for key: String in nav.penalties.keys():nav.penalties[key]=0
	nav.penalize_segment(9,Vector3.ZERO,Vector3.ZERO,0)
	var restored:Dictionary=nav.route(nav.floor_location(0,from),nav.floor_location(0,to))
	check(bool(restored.ok) and absf(float(restored.distance)-float(before.distance))<.01,
		"Expired penalties restore the original route (%.2f m)."%float(restored.distance))
	app.queue_free();await process_frame
	print("ROUTE_LEARNING %d checks, %d failures" % [checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
