extends SceneTree
## Dollhouse play keeps the child visible, pulls a doll out, and moves while playing.
const Actor = preload("res://scripts/actor.gd")

var checks: int = 0
var failures: int = 0

func check(value: bool, detail: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(detail)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var child: LifeSim = LifeSim.new()
	child.new_household({"name": "Mina", "age_stage": "child", "traits": []})
	child.autonomy = false
	child.register_targets([{"id": "house", "kind": "dollhouse", "position": Vector3(1, .16, 1)}])
	check(child.queue_action("play_dollhouse", "house", Vector3(1, .16, 1)), "The child queues dollhouse play.")
	check(str(child.get_current_action().get("id")) == "play_dollhouse", "Dollhouse play is the action in progress.")
	var actor: LifeActor = Actor.new()
	root.add_child(actor)
	actor.configure({"name": "Mina", "age_stage": "child", "low_detail": true, "frame": 1})
	actor.voice_enabled = false
	actor.set_activity_anchor(Vector3(1, 0, 1), 0.0, "standing", "play_dollhouse")
	actor.animate(0.2, 1.0, false, "play_dollhouse")
	check(actor.visible and actor.scale.length() > 0.5, "The child stays fully visible while playing.")
	check(is_instance_valid(actor._doll) and actor._doll.visible, "A doll is pulled out of the house.")
	var first: Vector3 = actor._doll.position
	var first_head: Vector3 = actor._joints["Head"].rotation if actor._joints.has("Head") else Vector3.ZERO
	actor.animate(0.9, 1.0, false, "play_dollhouse")
	check(actor._doll.visible and actor._doll.position.distance_to(first) > 0.02, "The doll travels as the child acts the scene (%.3f)." % actor._doll.position.distance_to(first))
	var moved: bool = false
	if actor._joints.has("Arm_R"):
		moved = actor._joints["Arm_R"].rotation.length() > 0.2
	check(moved or actor._joints["Head"].rotation.distance_to(first_head) > 0.02, "The child is not standing still.")
	child.free()
	actor.free()
	print("DOLLHOUSE_PLAY %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
