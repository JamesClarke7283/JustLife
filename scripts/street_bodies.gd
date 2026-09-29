extends RefCounted
class_name LifeStreetBodies
## The living bodies of `LifeStreetLife`'s passers: low-detail Lifelet models for
## every age and dogs, walking at the natural pace of their age with a gait clock
## that follows the ground they cover. Each body carries a pick capsule so a
## click reaches the passer, and a held passer turns to the Lifelet who is
## talking to them and stands in the pose of the conversation.
const CareProps = preload("res://scripts/care_props.gd")

var app: Node
var bodies: Dictionary = {}
var _leashes: Dictionary = {}
## passer id -> action id the passer answers with while a Lifelet talks to them.
var poses: Dictionary = {}


func _init(controller: Node) -> void:
	app = controller


func body_of(id: String) -> Node3D:
	# The world is rebuilt on a load, freeing every body: test the raw value
	# before it is assigned to a typed variable.
	var body: Variant = bodies.get(id)
	return body as Node3D if is_instance_valid(body) else null


## Where the pick capsule reaches: the world's own extras, so the ordinary click
## path (`object_clicked`) opens the passer's menu.
func label_of(passer: Dictionary) -> String:
	var role: String = {"child": "child", "teen": "teenager", "adult": "neighbour", "elder": "neighbour", "pet": "dog"}.get(str(passer.kind), "neighbour")
	return "%s (passing %s)" % [str(passer.name), role]


func sync(delta: float) -> void:
	var street: LifeStreetLife = app.street_life
	var world: LifeWorld = app.world
	if street == null or not is_instance_valid(world) or not is_instance_valid(world.house):
		return
	var game_speed: float = float(app.household.speed)
	for passer: Dictionary in street.passers:
		var id: String = str(passer.id)
		var body: Node3D = body_of(id)
		if body == null:
			body = _spawn(passer)
			if body == null:
				continue
			bodies[id] = body
		var live: bool = bool(passer.active)
		body.visible = live
		_set_pickable(body, id, live)
		if not live:
			world.pick_extras.erase(id)
			continue
		world.pick_extras[id] = {"id": id, "kind": "passer", "label": label_of(passer), "node": body, "size": Vector2(.6, .6), "passer_kind": str(passer.kind), "name": str(passer.name)}
		body.position = street.position_of(passer)
		var held: bool = float(passer.hold_left) > 0.0
		var walking: bool = game_speed > 0.0 and not held and not bool(passer.get("waiting", false))
		var heading: float = street.heading_of(passer)
		var facing_delta: float = minf(delta * (8.0 if not held else 6.0), 1.0)
		if held:
			var holder_at: Vector3 = _holder_position(str(passer.holder))
			var toward: Vector3 = holder_at - body.position
			toward.y = 0.0
			if holder_at.is_finite() and toward.length() > 0.05:
				heading = atan2(toward.x, toward.z)
		body.rotation.y = lerp_angle(body.rotation.y, heading, facing_delta)
		var pace: String = str(passer.pace)
		if body is LifeActor:
			(body as LifeActor).animate(delta, LifePedestrianPace.gait_factor(pace, game_speed) if walking else game_speed, walking, str(poses.get(id, "")) if held else "")
		elif body is LifePetActor:
			var dog: LifePetActor = body as LifePetActor
			if not held and dog.interaction != "":
				dog.clear_interaction()
			var dog_factor: float = LifePedestrianPace.gait_factor("dog", game_speed)
			# A dog on a lead is moved at its walker's pace, so its legs keep that pace.
			if not str(passer.get("follows", "")).is_empty():
				for other: Dictionary in street.passers:
					if str(other.id) == str(passer.follows):
						dog_factor = LifePedestrianPace.gait_factor_at("dog", float(other.speed), game_speed)
						break
			dog.animate(delta, walking, dog_factor if walking else game_speed)
	_sync_leashes(street)


## Bodies a walker waits behind rather than through: every visible ground-floor
## Lifelet or neighbour who is standing on the sidewalk band.
func obstacles() -> Array:
	var result: Array = []
	if not is_instance_valid(app.world):
		return result
	for id: String in app.world.actors:
		var actor: Node3D = app.world.actors[id]
		if not is_instance_valid(actor) or not actor.visible or bool(actor.get_meta("away", false)):
			continue
		if actor.position.z > 7.4 and absf(actor.position.y - LifeStreetLife.HEIGHT) < .1:
			result.append(actor.position)
	return result


func _holder_position(holder_id: String) -> Vector3:
	var actor: Node3D = app.world.actors.get(holder_id)
	return actor.position if is_instance_valid(actor) else Vector3.INF


func _spawn(passer: Dictionary) -> Node3D:
	var world: LifeWorld = app.world
	var id: String = str(passer.id)
	var body: Node3D
	if str(passer.kind) == "pet":
		var pet := LifePetActor.new()
		pet.name = id
		world.house.add_child(pet)
		pet.configure(id, "dog", passer.look, str(passer.name), "female")
		body = pet
	else:
		var person := LifeActor.new()
		person.name = id
		world.house.add_child(person)
		var profile: Dictionary = (passer.look as Dictionary).duplicate(true)
		profile["name"] = str(passer.name)
		profile["age_stage"] = str(passer.stage)
		profile["low_detail"] = true
		person.configure(profile)
		person.voice_enabled = false
		person.set_meta("display_name", str(passer.name))
		body = person
	_pick_body(body, passer)
	return body


## A capsule sized to the body, on the same pick layers as a pet, carrying the
## passer's id: `LifeWorld.pick` resolves it through `pick_extras`.
func _pick_body(body: Node3D, passer: Dictionary) -> void:
	var pick := StaticBody3D.new()
	pick.name = "PasserPick"
	pick.collision_layer = LifeWorld.PICK_GROUND | LifeWorld.PICK_UPPER
	pick.input_ray_pickable = true
	pick.set_meta("item_id", str(passer.id))
	body.add_child(pick)
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	if body is LifeActor:
		capsule.height = maxf(.8, (body as LifeActor).get_display_height())
		capsule.radius = .30
	else:
		capsule.height = float(LifePetActor.SPECIES_HEIGHT.get("dog", .52)) + .10
		capsule.radius = .26
	shape.shape = capsule
	shape.position.y = capsule.height * .5
	pick.add_child(shape)


func _set_pickable(body: Node3D, _id: String, live: bool) -> void:
	var pick: StaticBody3D = body.get_node_or_null("PasserPick") as StaticBody3D
	if pick == null:
		return
	pick.collision_layer = (LifeWorld.PICK_GROUND | LifeWorld.PICK_UPPER) if live else 0


## A lead between the walker's hand and the dog's collar.
func _sync_leashes(street: LifeStreetLife) -> void:
	for passer: Dictionary in street.passers:
		var leader_id: String = str(passer.get("follows", ""))
		if leader_id.is_empty():
			continue
		var id: String = str(passer.id)
		var dog: LifePetActor = body_of(id) as LifePetActor
		var walker: LifeActor = body_of(leader_id) as LifeActor
		var held_props: Variant = _leashes.get(id)
		var props: Node3D = held_props as Node3D if is_instance_valid(held_props) else null
		if props == null:
			props = CareProps.new()
			app.world.house.add_child(props)
			_leashes[id] = props
		if dog == null or walker == null or not bool(passer.active):
			props.call("hide_all")
			continue
		var hand: Vector3 = walker.to_global(Vector3(.18, .82 * walker.get_display_height() / 1.76, .16))
		props.call("present", {"leash": [hand, dog.collar_point()]})
