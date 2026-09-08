extends SceneTree
const Actor = preload("res://scripts/actor.gd")
var checks:int=0
var failures:int=0
func _initialize()->void:call_deferred("run")
func check(ok:bool,message:String)->void:
	checks+=1
	if not ok:failures+=1;push_error(message)
func run()->void:
	for frame:int in range(2):
		for lod:bool in [false,true]:
			var actor:LifeActor=Actor.new();root.add_child(actor)
			actor.configure({"name":"Grip QA","frame":frame,"low_detail":lod})
			actor.voice_enabled=false
			for side:String in ["L","R"]:
				check(not actor._grip_shapes[side].is_empty(),"Both authored hand grip morphs must exist on the production body.")
				for shape:Dictionary in actor._grip_shapes[side]:
					check(is_zero_approx(shape.mesh.get_blend_shape_value(shape.index)),"Each grip morph must initialize in the relaxed neutral state.")
				check(actor._grip_anchors[side].distance_to(actor._palm_offset(side)) > .02,"Full-grip contact metadata must describe a real offset from the relaxed palm.")
			for i:int in range(180):actor.animate(1.0/60.0,1,false,"cook")
			check(absf(actor._grip_amounts.R-.95) < .001 and absf(actor._grip_amounts.L-.25) < .001,"Cooking must use a full spoon grip and lighter bowl support.")
			for side:String in ["L","R"]:
				for shape:Dictionary in actor._grip_shapes[side]:
					check(absf(shape.mesh.get_blend_shape_value(shape.index)-actor._grip_amounts[side]) < .001,"Every hand mesh must receive its independently blended grip.")
			check(actor._cooking_spoon.position.is_equal_approx(actor._grip_offset("R")) and actor._cooking_bowl.position.is_equal_approx(actor._grip_offset("L")),"Held objects must follow the matching interpolated grip centers.")
			var tip:Vector3=actor._bowl_center.to_local(actor._spoon_tip.global_position)
			check(Vector2(tip.x,tip.z).length()<.12 and tip.y>-.015 and tip.y<.08,"The spoon must remain in the bowl after its hand grip changes.")
			var grip_before:Dictionary=actor._grip_amounts.duplicate(true)
			var spoon_before:Transform3D=actor._cooking_spoon.global_transform
			actor.animate(.6,0,true,"")
			check(actor._grip_amounts==grip_before and actor._cooking_spoon.global_transform.is_equal_approx(spoon_before),"Pause must freeze finger grip values and held contact positions.")
			for i:int in range(115):actor.animate(1.0/60.0,1,false,"snack")
			var mouth:Vector3=actor._model.to_local(actor._joints.Head.to_global(actor._mouth_anchor))
			var food:Vector3=actor._model.to_local(actor._snack.to_global(Vector3(0,.029,-.011)))
			check(mouth.distance_to(food)<.035,"A partial snack grip must preserve lip contact through the moving grip offset.")
			check(absf(actor._grip_amounts.R-.45)<.001 and actor._grip_amounts.L<.001,"Eating must leave the unused hand relaxed.")
			for i:int in range(120):actor.animate(1.0/60.0,1,true,"")
			check(actor._grip_amounts.L<.001 and actor._grip_amounts.R<.001,"Walking must release both hand grips smoothly.")
			actor.queue_free()
	await process_frame;await create_timer(.2).timeout
	print("GRIP ACTOR TESTS: %d checks, %d failures"%[checks,failures])
	quit(1 if failures>0 else 0)
