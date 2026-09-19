extends SceneTree
## Run in a copied project with MCP autoload disabled. Exercises the actual UI controller.

const MainScript = preload("res://scripts/main.gd")
var main: Node
var failures: int = 0
var assertions: int = 0


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	main=MainScript.new()
	root.add_child(main)
	main.set_process(false)
	main.set_body_scale(1.15)
	_check(main.preview.scale.is_equal_approx(Vector3.ONE),"Creator body slider keeps the navigation root at unit scale.")
	main.refresh_preview()
	_check(is_equal_approx(main.preview.visual.scale.x,1.15),"Appearance refresh must not square the selected body scale.")
	main.start_household()
	main.sim.autonomy=false
	await process_frame
	_test_pause_ownership()
	_test_cancellation()
	_test_build_transactions()
	_test_target_rebinding()
	_test_construction_undo()
	_test_career_ui()
	await _test_save_load()
	main.queue_free()
	await process_frame
	await process_frame
	# Give the audio mixer one buffer interval to retire the stopped ambience voice.
	await create_timer(.15).timeout
	print("Integration: %d assertions, %d failures." % [assertions,failures])
	quit(0 if failures==0 else 1)


func _check(condition:bool,message:String) -> void:
	assertions+=1
	if not condition:
		failures+=1
		push_error(message)


func _key(code:Key) -> void:
	var event:InputEventKey=InputEventKey.new()
	event.keycode=code
	event.pressed=true
	main._unhandled_input(event)


func _cancel_all() -> void:
	while not main.sim.action_queue.is_empty():main.cancel_current_action()


func _item(kind:String) -> Dictionary:
	for item:Dictionary in main.world.items:
		if str(item.kind)==kind:return item
	return {}


func _free_position(kind:String,away_from:Vector3=Vector3(100,0,100)) -> Vector3:
	for x:int in range(-10,11):
		for z:int in range(-8,9):
			var point:Vector3=Vector3(float(x)*.5,.16,float(z)*.5)
			if point.distance_to(away_from)>1.0 and main.world.can_place(kind,point,0.0):return point
	return Vector3(100,0,100)


func _test_pause_ownership() -> void:
	main.set_game_speed(3)
	main.show_menu()
	_check(main.sim.speed==0 and main.pause_before_menu==3,"Menu remembers the exact running speed.")
	main.set_sound(false)
	main.show_menu()
	_check(main.pause_before_menu==3,"Redrawing the sound menu must not overwrite the remembered speed with zero.")
	_key(KEY_3)
	_check(main.sim.speed==0,"Speed hotkeys cannot restart simulation behind a pause menu.")
	main.close_overlay()
	_check(main.sim.speed==3,"Closing a pause menu restores its original speed.")
	main.set_game_speed(0)
	main.show_person()
	_key(KEY_ESCAPE)
	_check(main.sim.speed==0,"Closing a non-pausing panel must preserve manual pause.")
	main.set_build_mode(true)
	main.show_menu()
	main.show_help()
	main.close_overlay()
	_check(main.mode=="build" and main.sim.speed==0,"Help/menu nested over Build must leave Build paused.")
	main.set_build_mode(false)
	_check(main.sim.speed==0,"Leaving Build restores a manually paused Live game.")
	main.set_game_speed(8)
	main.set_build_mode(false)
	_check(main.sim.speed==8,"Clicking Live while already Live must be idempotent.")
	main.set_build_mode(true)
	main.set_game_speed(1)
	_check(main.sim.speed==0,"Build mode ignores speed changes.")
	main.set_build_mode(false)
	_check(main.sim.speed==8,"Build has its own remembered speed, independent of menus.")
	main.set_sound(true)
	_check(main.player.voice_enabled,"Sound re-enables voices during running Live mode.")
	main.set_build_mode(true)
	_check(not main.player.voice_enabled,"Entering paused Build explicitly disables voice playback.")
	main.set_build_mode(false)
	main.set_game_speed(1)


func _test_cancellation() -> void:
	_cancel_all()
	main.queue_interaction(_item("fridge"),"cook")
	main.queue_interaction(_item("shower"),"shower")
	_check(main.path.size()>0,"First queued activity has a navigation path.")
	main.cancel_current_action()
	_check(str(main.sim.get_current_action().id)=="shower" and main.path.size()>0,"Cancel preserves the next action's synchronously created path.")
	main.cancel_current_action()
	_check(main.path.is_empty() and main.sim.action_queue.is_empty(),"Canceling the sole approaching activity stops walking.")
	var destination:Vector3=main.world.approach(_item("fridge"))
	main.on_ground_clicked(destination)
	main.sim.autonomy=true
	main.sim.needs.hunger=5.0
	main._process(3.0)
	_check(main.sim.action_queue.is_empty(),"Autonomy cannot replace a manual walking order mid-route.")
	main.sim.autonomy=false
	main._clear_motion()


func _test_build_transactions() -> void:
	main.set_build_mode(true)
	var sofa:Dictionary=_item("sofa")
	var id:String=str(sofa.id)
	var old_position:Vector3=sofa.node.position
	var initial_funds:int=main.sim.funds
	main.move_item(sofa)
	_check(main.sim.funds==initial_funds and not main.pending_move.is_empty(),"A pending move has no monetary effect.")
	main.sim.funds+=123
	main.cancel_placement()
	_check(main.sim.funds==initial_funds+123,"Canceling a move must not roll back unrelated funds.")
	_check(main._find_item(id).node.position.is_equal_approx(old_position),"Canceling a move restores its original furnishing and ID.")
	main.move_item(main._find_item(id))
	var moved:Vector3=_free_position("sofa",old_position)
	main.on_placement("sofa",moved,0.0)
	_check(main.pending_move.is_empty() and not main._find_item(id).is_empty(),"Committed moves preserve object identity.")
	_check(main.sim.funds==initial_funds+123,"Moving a furnishing is free.")
	main.undo_build()
	_check(main._find_item(id).node.position.is_equal_approx(old_position),"One undo restores a committed move in one step.")
	main.begin_purchase("plant")
	var purchase_position:Vector3=_free_position("plant")
	var funds_before:int=main.sim.funds
	main.on_placement("plant",purchase_position,0.0)
	_check(main.sim.funds==funds_before-int(LifeCatalog.ITEMS.plant.price),"A successful placement charges its advertised price once.")
	main.sim.funds+=77
	main.undo_build()
	_check(main.sim.funds==funds_before+77,"Undo applies the inverse purchase amount instead of stale total funds.")
	main.set_build_mode(false)
	main.set_build_mode(true)
	_check(main.build_undo.is_empty(),"Undo history ends when a Build session ends.")
	var neighbor:Dictionary={"id":"maya","kind":"neighbor","label":"Maya","node":main.world.actors.maya}
	main.on_object_clicked(neighbor,Vector2.ZERO)
	_check(not main.overlay_open,"Lifelets cannot be sold or moved through the furniture menu.")
	main.set_build_mode(false)


func _test_target_rebinding() -> void:
	_cancel_all()
	main.queue_interaction(_item("fridge"),"cook")
	# A refrigerator meal routes to the stove when one is available.
	var fridge_id:String=str(main.sim.get_current_action().target_id)
	main.queue_interaction(_item("shower"),"shower")
	main.set_build_mode(true)
	main.sell_item(main._find_item(fridge_id))
	_check(main.sim.action_queue.all(func(action:Dictionary)->bool:return str(action.target_id)!=fridge_id),"Selling a target removes all actions attached to it.")
	_check(str(main.sim.get_current_action().id)=="shower" and not main.path.is_empty(),"Selling the current target replans the next valid action.")
	main.undo_build()
	main.set_build_mode(false)
	_cancel_all()
	var easel:Dictionary=_item("easel")
	var easel_id:String=str(easel.id)
	main.queue_interaction(easel,"paint")
	main.sim.begin_current_action()
	main.sim.tick(2.0)
	var progress_before:float=float(main.sim.get_current_action().elapsed)
	main.set_build_mode(true)
	var old_position:Vector3=easel.node.position
	main.move_item(easel)
	var new_position:Vector3=_free_position("easel",old_position)
	main.on_placement("easel",new_position,0.0)
	var action:Dictionary=main.sim.get_current_action()
	_check(str(action.target_id)==easel_id and str(action.phase)=="approach","Moving an active target preserves identity and requires a fresh approach.")
	_check(is_equal_approx(float(action.elapsed),progress_before) and bool(action.paid),"Rebinding preserves action progress and ingredient payment.")
	_check(action.target_position.is_equal_approx(main.world.approach(main._find_item(easel_id))),"Moved activities point at the new interaction slot.")
	main.undo_build()
	main.set_build_mode(false)
	_cancel_all()


func _test_construction_undo() -> void:
	main.set_build_mode(true)
	var construction:LifeConstruction=main.world.construction
	var count_before:int=construction.records.size()
	var funds_before:int=main.sim.funds
	var proposal:Dictionary={"op":"wall","walls":[{"x":-7.0,"z":0.0,"w":.14,"d":1.0,"cut":true}],"floors":[],"cost":55,"valid":true}
	main.on_construction(proposal)
	_check(construction.records.size()==count_before+1 and main.sim.funds==funds_before-55,"Construction commits structure and its cost together.")
	main.undo_build()
	_check(construction.records.size()==count_before and main.sim.funds==funds_before,"Construction marker snapshots restore walls and money on undo.")
	main.begin_construction("room")
	_key(KEY_ESCAPE)
	_check(construction.tool.is_empty(),"Escape cancels construction tools.")
	main.set_build_mode(false)


func _test_save_load() -> void:
	_cancel_all()
	main.queue_interaction(_item("fridge"),"cook")
	main.sim.begin_current_action()
	main.sim.tick(2.0)
	var saved_elapsed:float=float(main.sim.get_current_action().elapsed)
	main.player.position=main.world.approach(_item("shower"))
	main.player.rotation.y=1.12
	var saved_position:Vector3=main.player.position
	main.world.camera_target=Vector3(-1,.8,2)
	main.world.camera_angle=1.1
	main.world.camera_elevation=.9
	main.world.camera.size=13
	main.selected_lot=1
	main._apply_floor_color("896953")
	main.set_sound(false)
	main.set_game_speed(3)
	main.show_menu()
	main.save_game()
	var saved_funds:int=main.sim.funds
	_check(main.sim.speed==0,"Saving from a menu preserves the current temporary pause.")
	main.player.position=Vector3(0,.16,0)
	main.floor_color="cfa97e"
	main.load_game()
	await process_frame
	_check(main.mode=="live" and main.sim.speed==3,"Loading a menu save restores the intended Live speed.")
	_check(main.player.position.is_equal_approx(saved_position) and is_equal_approx(main.player.rotation.y,1.12),"Save/load restores Lifelet position and facing.")
	_check(main.world.camera_target.is_equal_approx(Vector3(-1,.8,2)) and is_equal_approx(main.world.camera.size,13),"Save/load restores camera framing.")
	_check(main.floor_color=="896953" and main.selected_lot==1 and not main.sound_enabled,"Save/load restores floor finish, selected lot and sound preference.")
	_check(main.sim.action_queue.size()==1 and is_equal_approx(float(main.sim.get_current_action().elapsed),saved_elapsed),"Loading does not cancel the front activity through an old-world callback.")
	main.sim.begin_current_action()
	_check(main.sim.funds==saved_funds,"Resuming after a load must not pay activity costs twice.")
	main._restore_world_state({"player":["bad",0,0],"camera":{},"zoom":"bad","floor":"invalid","angle":[]})
	_check(is_instance_valid(main.player),"Malformed optional world-state values must be handled safely.")


func _test_career_ui() -> void:
	_cancel_all()
	main.set_game_speed(3)
	# The office asks for Logic 3, so the skill is earned before the picker is
	# asked to take the job; the picker's own pausing is what is being checked.
	main.sim.skills.logic.level = 3
	main.show_careers()
	_check(main.sim.speed==0 and main.overlay_pauses_sim,"Career choices pause the household while being reviewed.")
	main._select_career("technology")
	_check(str(main.sim.career.track)=="technology" and main.sim.speed==3,"Choosing a career updates the simulation and restores the previous speed.")
	main.show_person()
	_check(main.sim.moodlets.size()>0 and main.overlay_open,"The Lifelet profile can display an active career-change moodlet.")
	main.close_overlay()
