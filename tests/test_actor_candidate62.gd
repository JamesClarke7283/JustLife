extends "res://tests/test_actor.gd"
## Explicit candidate-only adult integration check. The production release gate
## remains test_actor.gd on both released frames and their live-camera LODs.


func tested_frames() -> Array[int]:
	return [0]


func model_options() -> Dictionary:
	return {"rig_preview":true, "low_detail":false}


func result_label() -> String:
	return "Adult candidate62 actor integration (not production family acceptance)"
