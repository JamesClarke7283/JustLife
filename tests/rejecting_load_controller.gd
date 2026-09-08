extends "res://scripts/main.gd"
# Exercise the public commit boundary with a deterministic reconstruction fault.
# The candidate must already have an actual imported world and actors.
func _restore_journeys()->Dictionary:
	if not is_instance_valid(world.house) or world.actors.size()<3:return {"ok":false,"error":"Test did not reach constructed candidate world."}
	return {"ok":false,"error":"Controlled reconstruction rejection after staging."}
