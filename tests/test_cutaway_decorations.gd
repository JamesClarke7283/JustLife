extends SceneTree
var checks:int=0
var failures:Array=[]
var world:LifeWorld
func _initialize()->void:run.call_deferred()
func check(value:bool,label:String)->void:
 checks+=1
 if not value:failures.append(label);push_error(label)
func install(walls:Array)->void:
 world.construction.restore({"kind":"__construction","walls":walls,"floors":[]})
 check(world.construction.last_error.is_empty(),"Directed wall fixture validates")
func wall(id:String,x:float,z:float,w:float,d:float,cut:bool=true)->Dictionary:
 return {"id":id,"x":x,"z":z,"w":w,"d":d,"height":2.6,"cut":cut,"color":"eae7d7"}
func run()->void:
 world=LifeWorld.new();root.add_child(world);world.create_home(LifeCatalog.starter_layout());await process_frame
 var windows:Array[Node3D]=[];var trim:Array[Node3D]=[]
 for n:Node3D in world.house.get_children():
  if not n.has_meta("wall_decoration"):continue
  if n is MeshInstance3D:trim.append(n)
  else:windows.append(n)
 check(windows.size()==5 and trim.size()==2,"Actual starter windows and low skirting are present")
 check(windows.all(func(n:Node3D)->bool:return n.visible),"Uncut starter back and side walls retain all supported windows")
 check(trim.all(func(n:Node3D)->bool:return n.visible),"Original full-span low skirting remains supported")
 var transforms:Array=windows.map(func(n:Node3D)->Transform3D:return n.transform)
 var meshes:Array=[]
 for n:Node3D in windows:
  for m:MeshInstance3D in n.find_children("*","MeshInstance3D",true,false):meshes.append(m.mesh)
 var original:Dictionary=world.construction.snapshot();var cut:Dictionary=original.duplicate(true)
 for w:Dictionary in cut.walls:w.cut=true
 world.construction.restore(cut)
 check(windows.all(func(n:Node3D)->bool:return not n.visible),"Restoring lowered supporting walls hides complete full-height panes immediately")
 check(trim.all(func(n:Node3D)->bool:return n.visible),"Lowered walls still retain legitimate low skirting")
 var snapshot:Dictionary=world.construction.snapshot();world.set_cutaway(false)
 check(windows.all(func(n:Node3D)->bool:return n.visible),"Full-wall toggle restores original window artwork")
 check(world.construction.snapshot()==snapshot,"View toggling leaves exact structural records unchanged")
 check(windows.map(func(n:Node3D)->Transform3D:return n.transform)==transforms,"Cutaway leaves pane transforms unchanged")
 var after:Array=[]
 for n:Node3D in windows:
  for m:MeshInstance3D in n.find_children("*","MeshInstance3D",true,false):after.append(m.mesh)
 check(meshes==after,"Cutaway leaves every original window mesh resource unchanged")
 world.set_cutaway(true)
 check(windows.all(func(n:Node3D)->bool:return not n.visible),"Repeated cutaway toggle hides panes again without stale state")
 world.set_cutaway(false)
 var back_id:String=""
 for w:Dictionary in world.construction.records:
  if float(w.w)>10 and float(w.z)<-5:back_id=str(w.id)
 world.construction.remove_wall(back_id)
 check(not windows[0].visible and not windows[1].visible and not windows[2].visible,"Direct wall demolition hides all dependent back windows")
 check(windows[3].visible and windows[4].visible and trim[1].visible,"Demolishing back wall keeps independent side windows and side skirting")
 check(not trim[0].visible,"Demolished back wall cannot retain a floating full-span trim")
 install([wall("short",-1.25,-5.04,2,.16)])
 check(not windows[1].visible,"A centered wall narrower than the whole frame cannot support the window")
 install([wall("fits",-1.25,-5.04,2.3,.16)])
 check(windows[1].visible,"A short but sufficient wall span supports the complete central window")
 check(not windows[0].visible and not windows[2].visible and not trim[0].visible,"Unbacked outer windows and oversized trim stay hidden")
 install([wall("left",-1.85,-5.04,1.2,.16),wall("right",-.65,-5.04,1.2,.16)])
 check(windows[1].visible,"Adjacent collinear segments jointly support a whole window")
 install([wall("left",-1.86,-5.04,1.18,.16),wall("right",-.64,-5.04,1.18,.16)])
 check(not windows[1].visible,"A real gap between supporting wall spans hides the crossing window")
 install([wall("wrong_axis",-1.25,-4.945,.16,3)])
 check(not windows[1].visible,"A perpendicular crossing wall cannot masquerade as window backing")
 # The deep reveal now deliberately enters the wall. Check the authored
 # attachment face, not the reveal's outside edge behind the back wall.
 var back_face:float=windows[1].position.z-.015
 install([wall("attachment_gap4mm",-1.25,back_face-.08-.004,3,.16)])
 check(windows[1].visible,"A real4mm attachment gap stays inside the authored5mm allowance")
 install([wall("attachment_gap6mm",-1.25,back_face-.08-.006,3,.16)])
 check(not windows[1].visible,"A real6mm attachment gap is rejected beyond the allowance")
 install([wall("near_detached",-1.25,-5.14,3,.16)])
 check(not windows[1].visible,"A parallel wall10cm behind the real attachment face cannot support a floating frame")
 install([wall("front_detached",-1.25,-4.70,3,.16)])
 check(not windows[1].visible,"A wall beyond the curtain/front cannot support the window back face")
 install([wall("stepped_left",-1.85,-5.04,1.2,.16),wall("stepped_right",-.65,-5.00,1.2,.16)])
 check(not windows[1].visible,"Separate stepped wall planes are not unioned into a fictitious flat backing")
 install([wall("offset",-1.25,-4.0,3,.16)])
 check(not windows[1].visible,"A distant parallel wall cannot support the frame")
 install([])
 var upper:Dictionary=wall("upper_only",-1.25,-5.04,3,.16);upper.level=1
 world.construction.add_wall(upper);world.construction.refresh_decorations()
 check(not windows[1].visible,"Coincident upper wall cannot support a ground window")
 world.window_panel(Vector3(-1.25,4.78,-4.945),false);var upper_window:Node3D=world.house.get_child(world.house.get_child_count()-1)
 world.construction.refresh_decorations()
 check(upper_window.visible,"Actual upper window can use its full-height upper support")
 # Direct renderer fixture for future shorter walls; versioned Building currently
 # requires2.6m walls, so this does not claim serialized short-wall acceptance.
 world.construction.remove_wall("upper_only")
 var low:Dictionary=wall("low",0,-5.04,12.2,.16);low.height=.35
 world.construction.cutaway=true
 world.construction.add_wall(low);world.construction.refresh_decorations()
 check(not windows[1].visible and trim[0].visible,"Physically low wall hides tall decoration but retains backed low skirting")
 var low_mesh:MeshInstance3D=world.construction.wall_nodes["low"].get_child(0)
 check(is_equal_approx(low_mesh.mesh.get_aabb().size.y,.35),"Actual cutaway wall mesh never raises a physically shorter wall")
 world.set_cutaway(false);world.create_home(LifeCatalog.starter_layout());await process_frame
 check(not world.construction.cutaway,"Rebuilt construction inherits the active full-wall setting")
 var rebuilt_visible:int=0
 for n:Node3D in world.house.get_children():
  if n.has_meta("wall_decoration") and not n is MeshInstance3D and n.visible:rebuilt_visible+=1
 check(rebuilt_visible==5,"Rebuilding a full-wall home preserves all supported windows")
 world.position=Vector3(2,1,-3);world.rotation.y=.35;world.construction.refresh_decorations()
 var translated_visible:int=0
 for n:Node3D in world.house.get_children():
  if n.has_meta("wall_decoration") and not n is MeshInstance3D and n.visible:translated_visible+=1
 check(translated_visible==5,"Actual mesh bounds remain valid when the whole world transforms")
 FileAccess.open("user://cutaway_decoration_controls.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"pid":OS.get_process_id(),"scope":"Actual starter decoration geometry/visibility across cutaway, full walls, rebuilding, demolition, span gaps, rotated side panels, lower/upper support and low trim. No redesigned windows or camera workaround."},"  "))
 print("CUTAWAY_DECORATION_CONTROLS ",checks," failures ",failures.size()," PID ",OS.get_process_id());world.queue_free();await process_frame;quit(0 if failures.is_empty() else 1)
