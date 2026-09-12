extends "res://tests/test_stair_controller.gd"
const Controller=preload("res://tests/resident_v2_load_controller.gd")
var trip_facts:Array=[]
func _same(a:Variant,b:Variant)->bool:
 return JSON.parse_string(JSON.stringify(LifeSaveLibrary._json_safe(a),"",true,true))==JSON.parse_string(JSON.stringify(LifeSaveLibrary._json_safe(b),"",true,true))
func _trip(destination:String)->void:
 app.travel_to(destination)
 check(app.mode=="travel","Departure accepted for "+destination)
 var crossings:Dictionary={};var intermediate:Dictionary={};var frames:int=0
 for frame:int in 4000:
  if app.mode!="travel":break
  app._process(.05);frames+=1
  for member:Dictionary in app.household.members:
   var body:LifeActor=app.world.actors[member.id]
   if not body.stair_presentation.is_empty():crossings[member.id]=true
   if body.position.y>.17 and body.position.y<3.15:intermediate[member.id]=true
  if frame%20==0:await process_frame
 check(app.mode=="live" and app.current_venue==destination,"Actual boarding, drive and arrival complete at "+destination)
 check(app.traversal.routes.is_empty() and app.household.journeys.is_empty(),"Arrival removes old-lot traversal and cached journeys at "+destination)
 trip_facts.append({"destination":destination,"frames":frames,"actors":app.world.actors.keys().map(func(id:String):return {"id":id,"position":str(app.world.actors[id].position),"visible":app.world.actors[id].visible}),"phase":str(app.residents.trip.get("phase","")),"routes":str(app.traversal.routes),"gait_members":crossings.keys(),"intermediate_heights":intermediate.keys()})

func _run()->void:
 if OS.get_environment("JUSTLIFE_DATA_DIR").is_empty() or OS.get_environment("XDG_DATA_HOME").is_empty():push_error("Use isolated save and user-data folders.");quit(2);return
 app=Controller.new();root.add_child(app);app.set_process(false);app.set_sound(false)
 if "--consume" in OS.get_cmdline_user_args():await _consume();return
 _setup(2)
 app.sim.relationships.maya.friendship=30
 app.household.members[1].sim.relationships.maya.friendship=30
 app.residents.tick(.4)
 var resident_before:Dictionary=app.residents.locations.duplicate(true)
 var body_before:Transform3D=app.world.actors.maya.transform
 var physical:Dictionary=app._physical_snapshot_context()
 check(physical.members.player.residents==app.residents.snapshot(),"Physical snapshot reads the live neighborhood state without requiring a prior save")
 check(app.residents.locations==resident_before and app.world.actors.maya.transform==body_before,"Physical snapshot does not move residents or modify their cached motion")
 var home:Array=app.world.serialize_items().duplicate(true)
 check(app.save_game("","V2 upstairs household"),"Named save stores an upstairs household with neighborhood data")
 var home_slot:String=app.active_save_id
 var child:Vector3=app.world.actors.housemate_1.position
 var home_residents:Dictionary=app.residents.snapshot()
 app.load_game(home_slot);await process_frame
 check(app.world.actors.housemate_1.position==child and app.world.point_level(child)==1,"Detached named load retains the exact upper-floor body position")
 check(app.residents.app==app and app.residents.snapshot()==home_residents,"Adopted residents belong to the live controller and retain their exact route state")
 app.on_ground_clicked(Vector3(-2,3.16,3.5))
 check(_until_transit("player"),"A real owned crossing is in progress before departure refusal")
 var before:Dictionary=app.traversal.snapshot();var resident_state:Dictionary=app.residents.snapshot();var world_id:int=app.world.get_instance_id()
 var queue:Array=app.sim.action_queue.duplicate(true);var layout:Array=app.home_layout.duplicate(true)
 app.travel_to("park")
 check(app.mode=="live" and app.traversal.snapshot()==before and app.world.get_instance_id()==world_id,"An owned stair crossing refuses travel without changing its physical position or ownership")
 check(app.residents.snapshot()==resident_state and app.sim.action_queue==queue and app.home_layout==layout,"Refusal preserves residents, queued work and saved home layout")
 for frame:int in 1800:
  app._process(.05)
  if not app.walk_only:break
 check(app.world.point_level(app.player.position)==1 and app.traversal.routes.is_empty(),"Existing crossing reaches its supported upper destination before retry")
 await _trip("maya_home")
 if app.mode!="live" or app.current_venue!="maya_home":await _finish_v2();return
 check(trip_facts[0].gait_members.has("player") and trip_facts[0].gait_members.has("housemate_1") and trip_facts[0].intermediate_heights.size()==2,"Both upstairs household members descend using actual stair presentation before boarding")
 check(app.world.last_layout_error.is_empty() and not app.world.construction.building_state.is_empty(),"The cottage has a validated canonical ground structure")
 check(app.world.validate_home_layout(app.world.serialize_items()).is_empty(),"The cottage's complete layout can pass the detached canonical loader: "+app.world.validate_home_layout(app.world.serialize_items()))
 var compare:=FileAccess.open("user://home_compare.json",FileAccess.WRITE);compare.store_string(JSON.stringify({"before":home,"after":app.home_layout},"  "));compare.close()
 check(_same(app.home_layout,home),"Visit preserves exact home floors, finishes, stairs, openings and furnishings")
 app.household.set_speed(0)
 check(app.save_game("","V2 cottage visit"),"Named save is allowed after actual car arrival at the cottage: "+app.notice_label.text)
 if app.active_save_id==home_slot:await _finish_v2();return
 var visit_slot:String=app.active_save_id
 var visit_residents:Dictionary=app.residents.snapshot();var visit_world:Array=app.world.serialize_items().duplicate(true)
 var old_world:Node=app.world;var old_household:Node=app.household;var old_residents:LifeResidents=app.residents
 var old_child_count:int=app.get_child_count();var original:Dictionary=app.household.get_state(app.world.serialize_items())
 Controller.reject_preparation=true
 app.load_game(home_slot);await process_frame
 check(app.notice_label.text.contains("Controlled rejection after candidate residents"),"Failure was injected only after candidate residents and journeys were reconstructed")
 check(app.world==old_world and app.household==old_household and app.residents==old_residents and app.get_child_count()==old_child_count,"Rejected candidate leaves original world, household, residents and node ownership intact")
 check(app.household.get_state(app.world.serialize_items())==original and app.residents.snapshot()==visit_residents,"Rejected load preserves all old physical records, resident motion and household values")
 Controller.reject_preparation=false
 app.load_game(visit_slot);await process_frame
 check(app.current_venue=="maya_home" and app.residents.app==app and app.residents.active_place=="maya_home","Named friend-home load adopts the matching resident service")
 check(app.residents.present("maya") and not app.residents.present("leo"),"Only the loaded cottage's present resident is targetable")
 check(_same(app.residents.snapshot(),visit_residents) and _same(app.world.serialize_items(),visit_world),"Named friend-home load preserves exact resident and house records")
 var expected:Dictionary={"slot":visit_slot,"home":home,"visit":visit_world,"residents":visit_residents}
 var receipt:=FileAccess.open("user://resident_v2_expected.json",FileAccess.WRITE);receipt.store_string(JSON.stringify(expected,"",true,true));receipt.close()
 await _trip("home")
 check(_same(app.world.serialize_items(),home),"Returning restores all canonical two-floor home records exactly")
 for member:Dictionary in app.household.members:check(app.world.point_level(app.world.actors[member.id].position)==0,"Returning Lifelet steps onto the actual ground sidewalk: "+str(member.id))
 await _finish_v2()

func _consume()->void:
 var file:=FileAccess.open("user://resident_v2_expected.json",FileAccess.READ)
 if file==null:check(false,"Fresh consumer has producer receipt");await _finish_v2();return
 var expected:Dictionary=JSON.parse_string(file.get_as_text());file.close()
 app.load_game(str(expected.slot));await process_frame
 check(app.current_venue=="maya_home" and app.has_active_game,"Fresh process opens the named cottage visit")
 check(_same(app.home_layout,expected.home),"Fresh process retains canonical upper home records")
 check(_same(app.world.serialize_items(),expected.visit),"Fresh process reconstructs the exact canonical friend home")
 check(_same(app.residents.snapshot(),expected.residents),"Fresh process restores the exact visiting resident state")
 check(app.residents.present("maya") and not app.residents.present("leo"),"Fresh process publishes only the physically present cottage resident")
 await _trip("library")
 check(app.save_game("","V2 public stop"),"Fresh consumer saves a public stop while retaining an upstairs home")
 var public_slot:String=app.active_save_id
 app.load_game(public_slot);await process_frame
 check(app.current_venue=="library" and _same(app.home_layout,expected.home),"Legacy public-venue load retains every canonical home furnishing level and structure record")
 await _trip("home")
 check(_same(app.world.serialize_items(),expected.home),"Fresh process return preserves complete two-floor home data")
 await _finish_v2()

func _finish_v2()->void:
 var suffix:String="fresh" if "--consume" in OS.get_cmdline_user_args() else "producer"
 var file:=FileAccess.open("user://resident_v2_"+suffix+".json",FileAccess.WRITE)
 file.store_string(JSON.stringify({"checks":checks,"failures":failures,"trips":trip_facts},"  "));file.close()
 print("RESIDENT_V2 ",suffix," checks=",checks," failures=",failures.size())
 app.queue_free();await process_frame;await process_frame;await create_timer(.2).timeout
 quit(0 if failures.is_empty() else 1)
