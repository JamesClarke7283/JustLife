extends "res://tests/test_grip_playthrough.gd"
## Final repaired surface + grip overlay, public creator and normal kitchen.
func _enter_new_game()->void:
	await super._enter_new_game()
	var extras:Dictionary=app.preview._find_model_extras(app.preview._model)
	check(int(extras.get("rig_version",0))==18 and int(extras.get("surface_revision",0))==2,"Rendered creator loads actual v18 surface revision2 metadata.")
	await press("Face")
	await screenshot("00_creator_surface_face",false,false)
	var original:Transform3D=app.world.camera.transform
	var center:Vector3=app.preview.get_portrait_center()
	for side:int in [-1,1]:
		app.world.camera.position=center+app.preview.global_basis.x*float(side)*1.37
		app.world.camera.look_at(center,Vector3.UP)
		await screenshot("00_creator_surface_profile_"+str(side),false,false)
	app.world.camera.transform=original

func _prop_state()->Dictionary:
	var result:Dictionary=super._prop_state()
	result["surface_metadata"]=app.player._find_model_extras(app.player._model)
	return result

func _kitchen_action(action_id:String,furnishing:String,prefix:String,cost:int)->void:
	var first:int=pose_evidence.size()
	await super._kitchen_action(action_id,furnishing,prefix,cost)
	for sample:Dictionary in pose_evidence.slice(first):
		check(int(sample.surface_metadata.get("rig_version",0))==18 and int(sample.surface_metadata.get("surface_revision",0))==2,action_id+": actual imported live model carries repaired v18 surface metadata.")
