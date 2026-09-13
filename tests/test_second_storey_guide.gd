extends SceneTree
## The second-storey recipe through public paths only: pressing Upper with no
## slab starts the Floor tool itself, a supported rectangle over the starter
## rooms quotes and commits through the public transactions, an unsupported
## rectangle names the wall requirement, and the committed slab invites the
## Stairs step. Headless: no pointer or rendering proof; the rendered
## two-floor suite owns actual clicks.

const Building=preload("res://scripts/building_state.gd")
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
	var construction=app.world.construction

	app.set_build_mode(true)
	app.set_build_level(0);await process_frame
	check(not construction.has_upper_floor(),"The starter home begins with no upper floor.")
	check(construction.tool.is_empty(),"No construction tool is active on the ground level.")

	app.set_build_level(1);await process_frame
	check(app.world.view_level==1,"The Upper press switches the build view upstairs.")
	check(construction.tool=="floor","With no upper floor yet, Upper starts the Floor tool itself.")
	# An oversized, off-centre drag is fitted to the walls rather than refused:
	# the whole point of the one-go purchase. A drag that misses the walls
	# entirely still names the two-opposite-bearing-walls rule.
	construction.anchored=true;construction.anchor=Vector3(-8,0,-7)
	var overhang:Dictionary=construction.make_proposal(Vector3(8,3.16,7))
	check(bool(overhang.get("valid",false)) and int(overhang.get("cost",0))==1440,
		"A drag past the ground walls is fitted to the walled span instead of refused: §%s."%str(overhang.get("cost",-1)))
	construction.anchored=true;construction.anchor=Vector3(-14.5,0,-9.5)
	var outside:Dictionary=construction.make_proposal(Vector3(-12,3.16,-7))
	check(not bool(outside.get("valid",false)) and str(outside.get("error","")).contains("opposite bearing walls"),
		"A rectangle that misses the walled span names the wall requirement: "+str(outside.get("error","")))

	# A supported rectangle over the enclosed starter rooms quotes and commits.
	var wallet:int=app.household.funds
	construction.anchored=true;construction.anchor=Vector3(-6,0,-5)
	var slab:Dictionary=construction.make_proposal(Vector3(6,3.16,5))
	check(bool(slab.get("valid",false)) and int(slab.get("cost",0))==1440,
		"The full upper slab over the enclosed rooms quotes for §1440: §%s."%str(slab.get("cost",-1)))
	app.on_construction(slab);await process_frame
	check(construction.has_upper_floor() and app.household.funds==wallet-1440,
		"The committed slab lands upstairs and the household pays exactly §1440 through the public callback.")
	check(not construction.tool.is_empty() and construction.tool=="floor",
		"The floor tool stays active after the slab, ready for the Stairs step through the Structure row.")

	# The stair completes the connection exactly as the rendered suite buys it.
	app.begin_construction("stairs")
	var stair:Dictionary=construction.make_proposal(Vector3(-1.5,.16,-2.5))
	check(bool(stair.get("valid",false)),"The stair at the slab edge quotes through the public flow: "+str(stair.get("error","")))
	app.on_construction(stair);await process_frame
	var state:Dictionary=construction.snapshot()
	check(state.stairs.size()==1 and state.openings.size()==1 and Building.validate(state).is_empty(),
		"Stair, upper opening and guard land together and the architecture validates.")

	app.queue_free();await process_frame
	print("SECOND_STOREY_GUIDE %d checks, %d failures" % [checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
