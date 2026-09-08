extends "res://tests/test_meal_autonomy.gd"
func _run()->void:
 app=load("res://scenes/main.tscn").instantiate();root.add_child(app);app.set_process(false);app.set_sound(false)
 var f:Dictionary=_fixture();f.sim.autonomy=false
 var start:Vector3=Vector3(.75,.16,-3.25)
 var point:Vector3=app.meal_flow._floor_slot(start,f.batch)
 var navcell:Vector2i=Vector2i(roundi(point.x*4),roundi(point.z*4))
 check(not app.world.navigation.is_point_solid(navcell),"Chosen platter center is a free actual navigation cell")
 var bounds:Rect2=Rect2(Vector2(point.x,point.z)-LifeMeals.PLATTER_HALF_SIZE,LifeMeals.PLATTER_HALF_SIZE*2)
 var overlaps:Array=[]
 for wall:Dictionary in app.world.construction.records:
  if bounds.intersects(app.world.construction.wall_rect(wall)):overlaps.append(wall)
 check(overlaps.is_empty(),"Chosen floor platter footprint does not intersect an actual wall")
 print("WALL_REPRO ",JSON.stringify({"point":[point.x,point.y,point.z],"walls":overlaps}))
 app.world.construction.add_floor({"x":7.25,"z":6.25,"w":1.5,"d":1.5,"color":"cfa97e"});app.world.rebuild_navigation()
 var edge_start:Vector3=Vector3(7.94,.16,6.25);var edge_point:Vector3=app.meal_flow._floor_slot(edge_start,f.plate)
 var outside:Vector3=edge_point+Vector3(LifeMeals.PLATE_HALF_SIZE.x,0,0)
 var center_height:float=app.meal_flow._floor_height(edge_point);var edge_height:float=app.meal_flow._floor_height(outside)
 check(absf(edge_point.y-center_height)<.000001,"Chosen plate center rests on the actual player-built floor")
 check(absf(center_height-edge_height)<.003,"Whole floor plate remains supported at the raised floor edge")
 print("EDGE_REPRO ",JSON.stringify({"point":[edge_point.x,edge_point.y,edge_point.z],"edge_x":outside.x,"center_height":center_height,"edge_support_height":edge_height}))
 app.queue_free();await process_frame;await process_frame;await process_frame
 var file:=FileAccess.open("user://floor_food_support.json",FileAccess.WRITE);file.store_string(JSON.stringify({"checks":checks,"failures":failures},"  "));file.close()
 print("FLOOR_FOOD_SUPPORT ",checks," checks, ",failures.size()," failures");quit(0 if failures.is_empty() else 1)
