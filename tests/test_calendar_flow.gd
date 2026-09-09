extends SceneTree
const MainScene=preload("res://scenes/main.tscn")
var app:Node
var checks:int=0
var failures:Array[String]=[]
var captures:bool=false
func _initialize() -> void:run.call_deferred()
func check(value:bool,message:String) -> void:
	checks+=1
	if not value:failures.append(message);push_error(message)
func press(text:String) -> void:
	for node:Node in app.find_children("*","Button",true,false):
		if node.text==text and node.is_visible_in_tree() and not node.disabled:node.pressed.emit();return
	check(false,"Missing enabled public button: "+text)
func named(id:String) -> void:
	var node:Button=app.find_child(id,true,false)
	check(is_instance_valid(node) and node.is_visible_in_tree() and not node.disabled,"Enabled control: "+id)
	if is_instance_valid(node) and not node.disabled:node.pressed.emit()
func frames(count:int=4) -> void:
	for index:int in range(count):await process_frame
	if captures:await RenderingServer.frame_post_draw
func capture(name:String) -> void:
	if captures:check(root.get_texture().get_image().save_png("user://calendar/"+name+".png")==OK,"Captured "+name)
func facts() -> Dictionary:
	var result:Dictionary=app.household.get_state().duplicate(true)
	result.erase("speed")
	for member:Dictionary in result.members:member.state.erase("speed")
	return result
func run() -> void:
	var data:String=OS.get_environment("XDG_DATA_HOME")
	if not data.is_absolute_path() or not data.get_file().begins_with("calendar-check-") or OS.get_environment("JUSTLIFE_DATA_DIR")!=data.path_join("save_data"):
		printerr("Calendar flow needs isolated calendar-check-* data and save_data child.");quit(2);return
	captures=DisplayServer.get_name()!="headless";DirAccess.make_dir_recursive_absolute("user://calendar")
	app=MainScene.instantiate();root.add_child(app);current_scene=app
	app.set_process(false);app.set_sound(false);await frames()
	press("New game")
	for index:int in range(8):
		if index>0:press("+ Add Lifelet")
		app.set_creator_age("child" if index==0 else ("teen" if index==1 else "adult"))
	press("Find my home  →");press("Start living  →")
	for member:Dictionary in app.household.members:member.sim.autonomy=false
	var last:LifeSim=app.household.members[-1].sim
	last.character.name="W".repeat(48) # Permitted maximum-width name exercises ellipsis.
	last.lifecycle.progress=1.0-120.0/(42.0*1440.0) # A birthday in today's agenda.
	app.set_game_speed(3);app._process(0.0);await frames()
	check(app.mode=="live" and app.household.members.size()==8,"Public creator reaches Live mode with eight household members.")
	app.queue_nearest("bookshelf","read");app._process(0.0)
	check(not app.sim.action_queue.is_empty() and app.sim.action_queue[0].id=="read","A real reading instruction is queued before the calendar opens.")
	var before:Dictionary=facts()
	press("Phone");await frames();capture("01_phone")
	press("Household calendar");app._process(0.0);await frames()
	check(app.sim.speed==0 and app.household.speed==0,"Opening the calendar pauses the shared household.")
	check(app.find_children("CalendarEntry_*","Control",true,false).size()==9,"The agenda includes all eight current routines and today's expected birthday.")
	for title:Label in app.find_children("AgendaTitle","Label",true,false):
		check(title.size.x<=782 and title.tooltip_text==title.text,"Long agenda titles stay bounded and retain their complete tooltip.")
	var scroll:ScrollContainer=app.find_child("CalendarAgenda",true,false)
	check(scroll.get_v_scroll_bar().max_value>scroll.size.y,"An eight-person agenda can scroll instead of clipping away members.")
	capture("02_agenda")
	named("CalendarFilter_work");await frames()
	check(app.find_children("CalendarEntry_*","Control",true,false).size()==3,"Hiding work keeps both pupils and the birthday visible.")
	named("CalendarFilter_school");await frames()
	check(app.find_children("CalendarEntry_*","Control",true,false).size()==1,"Birthday filtering remains independent of work and school.")
	named("CalendarFilter_birthday");await frames()
	check(is_instance_valid(app.find_child("CalendarEmpty",true,false)),"No selected matching plans has an explicit empty state.")
	named("CalendarNextWeek");await frames()
	check(is_instance_valid(app.find_child("CalendarDay_8",true,false)),"Next week advances seven dates.")
	named("CalendarThisWeek");named("CalendarFilter_school");named("CalendarFilter_work");named("CalendarFilter_birthday");await frames()
	if captures:
		root.size=Vector2i(960,600);await frames(8)
		check(root.size==Vector2i(960,600) and DisplayServer.window_get_size()==Vector2i(960,600) and root.get_texture().get_image().get_size()==Vector2i(960,600),"The small capture uses an actual 960×600 native window and pixels.")
		capture("03_agenda_960")
		scroll=app.find_child("CalendarAgenda",true,false);scroll.scroll_vertical=10000;await frames();capture("04_agenda_scrolled_960")
	named("CalendarBack");await frames();capture("05_phone_960" if captures else "05_phone")
	check(app.find_child("PhoneAdoptChild",true,false).disabled,"Returning to the phone preserves the existing full-household adoption guard.")
	check(facts()==before,"Calendar week, filter and scroll navigation preserve every saved household field except its deliberate pause.")
	press("Back to life");app._process(0.0)
	check(app.sim.speed==3 and app.household.speed==3 and not app.overlay_open,"Closing the nested phone restores the original fast speed.")
	app.set_game_speed(0);app._process(0.0);press("Phone");press("Household calendar");named("CalendarClose");app._process(0.0)
	check(app.sim.speed==0 and not app.overlay_open,"A calendar opened while paused stays paused when closed.")
	app.queue_free();await create_timer(.2).timeout
	print("Calendar flow: %d checks, %d failures." % [checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
