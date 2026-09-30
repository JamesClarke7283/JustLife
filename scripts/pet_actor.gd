extends Node3D
class_name LifePetActor
const LifePetsPolicy=preload("res://scripts/pets.gd")
## An original household pet in the world. It owns its authored model, its mixed
## coat and a small idle animation; the controller owns where it stands and when
## it walks. The body is presentation only — the household owns the real pet
## record, so a save always resumes the same animal.

const COAT_SHADER: String = "res://assets/shaders/pet_coat.gdshader"
## The authored material names the coat shader overrides, exactly as the
## character actor overrides its own authored surfaces by name.
const COAT_SURFACES: Array[String] = ["Fur", "Fur_Mark"]
## The collar and leash are their own authored surfaces, coloured from the pet's
## own saved accessory colours rather than the coat.
const COLLAR_SURFACE: String = "Collar"
const LEASH_SURFACE: String = "Leash"
const LEG_NAMES: Array[String] = ["Leg_FL", "Leg_FR", "Leg_BL", "Leg_BR"]

## Authored standing height per species, so the coat gradient spans the body.
const SPECIES_HEIGHT: Dictionary = {"cat": 0.30, "dog": 0.52}
## Authored shoulder-to-tail-base length, used to scale the walk cycle.
const SPECIES_LENGTH: Dictionary = {"cat": 0.60, "dog": 0.85}

var pet_id: String = ""
var display_name: String = ""
var species: String = "cat"
var sex: String = "female"
var floor_level: int = 0
var traversing_stairs: bool = false
var coat: Dictionary = {}
var selected: bool = false:
	set(value):
		selected = value
		if is_instance_valid(_ring):_ring.visible = value
## A speed factor of zero freezes the pet, matching the household clock.
var speed: float = 1.0
var _model: Node3D
var _head: Node3D
var _tail: Node3D
var _tail_rest_basis: Basis = Basis.IDENTITY
var _legs: Array[Node3D] = []
var _ring: MeshInstance3D
var _bark_player: AudioStreamPlayer3D
var bark_count: int = 0
var _speech: Label3D
## The actor's own surface materials, cached so a redraw can drop them. Both the
## coat shader and the collar/leash tints are kept, so the array is typed to their
## common Material base rather than to ShaderMaterial alone.
var _materials: Array[Material] = []
var _configured: bool = false
var _time: float = 0.0
var _phase: float = 0.0
var _base_height: float = 0.0
var _collar: Node3D
## The care beat a Lifelet is giving this pet (care_motion.gd), on that beat's
## own clock, and where the person is.
var interaction: String = ""
var interaction_time: float = 0.0
var _partner: Vector3 = Vector3.ZERO
## Furniture poses are separate from Lifelet care so the two controllers never
## overwrite one another. They share the same authored joints.
var behavior: String = ""
var behavior_time: float = 0.0
var squeak_count: int = 0
var _squeak_player: AudioStreamPlayer3D

## How far forward of the neck joint each species' mouth sits.
const MOUTH_REACH: Dictionary = {"cat": .14, "dog": .22}


func _ready() -> void:
	_ensure_nodes()
	# A caller that configured the pet before adding it has already built the
	# authored model; rebuilding here would discard it and re-apply the coat.
	if _model == null and not _configured:
		configure(pet_id, species, coat, display_name, sex)


func _ensure_nodes() -> void:
	if _ring != null:
		return
	_ring = MeshInstance3D.new()
	_ring.name = "PetSelectionRing"
	var shape := TorusMesh.new()
	shape.inner_radius = 0.20
	shape.outer_radius = 0.225
	shape.rings = 40
	shape.ring_segments = 8
	_ring.mesh = shape
	_ring.position.y = 0.02
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("77bd9d")
	material.emission_enabled = true
	material.emission = Color("77bd9d")
	material.emission_energy_multiplier = 0.6
	_ring.material_override = material
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ring.visible = false
	add_child(_ring)
	_speech = Label3D.new()
	_speech.name = "PetSpeech"
	_speech.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_speech.font_size = 38
	_speech.pixel_size = 0.003
	_speech.outline_size = 12
	_speech.modulate = Color("29473f")
	_speech.outline_modulate = Color("fffcf0")
	_speech.shaded = false
	_speech.visible = false
	if ResourceLoader.exists("res://assets/fonts/Body.ttf"):
		_speech.font = LifePalette.body_font()
	add_child(_speech)


## Rebuild the pet from its record. Called on spawn and on every restore, so the
## live body always matches the saved animal.
func configure(id: String, new_species: String, appearance: Dictionary, name: String = "", new_sex: String = "female") -> void:
	_configured = true
	_ensure_nodes()
	pet_id = id
	species = new_species if LifePets.SPECIES.has(new_species) else "cat"
	sex = new_sex
	display_name = name
	coat = LifePets.appearance(appearance)
	if is_instance_valid(_model):
		remove_child(_model)
		_model.queue_free()
	_model = null
	_head = null
	_tail = null
	_legs.clear()
	_materials.clear()
	_ring.visible = selected
	var path: String = "res://assets/models/pet_%s.glb" % species
	# A species whose authored model has not been imported yet falls back to the
	# other one rather than rendering nothing; the caller reports the gap.
	if not ResourceLoader.exists(path):
		path = "res://assets/models/pet_cat.glb" if species == "dog" else "res://assets/models/pet_dog.glb"
	if not ResourceLoader.exists(path):
		push_error("JustLife pet model is missing for species " + species)
		return
	_model = load(path).instantiate()
	add_child(_model)
	_head = _model.find_child("Head", true, false) as Node3D
	_tail = _model.find_child("Tail", true, false) as Node3D
	if is_instance_valid(_tail): _tail_rest_basis = _tail.basis
	_collar = _model.find_child("Collar", true, false) as Node3D
	for leg_name: String in LEG_NAMES:
		var leg := _model.find_child(leg_name, true, false) as Node3D
		if leg != null:
			_legs.append(leg)
	_apply_coat()
	# A long coat sits slightly fuller; a short coat sits sleeker. Scaling the
	# whole body keeps the legs and the pivot correct.
	var fullness: float = {"short": 0.96, "medium": 1.0, "long": 1.06}.get(str(coat.coat_length), 1.0)
	_model.scale = Vector3.ONE * fullness
	_phase = float(abs(pet_id.hash()) % 100) * 0.0628
	_time = 0.0
	_ring.position.y = 0.02


## Replace the authored placeholder surfaces with one mixed-coat shader. The
## marking zones keep a bias toward the second colour, so a bicolour or tuxedo
## pet reads even when the gradient is light.
func _apply_coat() -> void:
	var shader: Shader = load(COAT_SHADER) if ResourceLoader.exists(COAT_SHADER) else null
	var primary := Color.from_string(str(coat.coat_color), Color("89563a"))
	var secondary := Color.from_string(str(coat.mark_color), Color("ead6b8"))
	var authored_height: float = float(SPECIES_HEIGHT.get(species, 0.30))
	var marking_bias: float = _marking_bias()
	for mesh: MeshInstance3D in _model.find_children("*", "MeshInstance3D", true, false):
		if mesh.mesh == null:
			continue
		for surface_index: int in range(mesh.mesh.get_surface_count()):
			var original: Material = mesh.mesh.surface_get_material(surface_index)
			if not original is StandardMaterial3D:
				continue
			var surface_name: String = str(original.resource_name)
			if surface_name == COLLAR_SURFACE or surface_name == LEASH_SURFACE:
				# The collar and leash take the pet's own accessory colours, so two
				# animals with the same coat are still told apart in the home.
				var accessory := StandardMaterial3D.new()
				accessory.albedo_color = Color.from_string(str(coat.get("collar_color", LifePetsPolicy.DEFAULT_COLLAR)) if surface_name == COLLAR_SURFACE else str(coat.get("leash_color", LifePetsPolicy.DEFAULT_LEASH)), Color(LifePetsPolicy.DEFAULT_COLLAR))
				accessory.roughness = 0.55
				mesh.set_surface_override_material(surface_index, accessory)
				_materials.append(accessory)
				continue
			if surface_name not in COAT_SURFACES:
				continue
			var material: StandardMaterial3D = null
			if shader != null:
				var shader_material := ShaderMaterial.new()
				shader_material.shader = shader
				shader_material.set_shader_parameter("primary_color", primary)
				shader_material.set_shader_parameter("secondary_color", secondary)
				shader_material.set_shader_parameter("gradient_blend", float(coat.gradient))
				shader_material.set_shader_parameter("marking_bias", marking_bias if surface_name == "Fur_Mark" else 0.0)
				shader_material.set_shader_parameter("softness", 0.55)
				shader_material.set_shader_parameter("coat_roughness", 0.88)
				shader_material.set_shader_parameter("coat_height", authored_height)
				shader_material.set_shader_parameter("base_y", position.y)
				mesh.set_surface_override_material(surface_index, shader_material)
				_materials.append(shader_material)
				continue
			# Without the shader the coat is still correct, just flat: the base
			# surface takes the first colour and the marking zone the second.
			material = StandardMaterial3D.new()
			material.albedo_color = primary if surface_name == "Fur" else secondary
			material.roughness = 0.88
			mesh.set_surface_override_material(surface_index, material)


func _marking_bias() -> float:
	# How strongly the marking zones lean toward the second colour. A plain coat
	# keeps only the gradient; the patterned ones push the zones further.
	return float({"none": 0.0, "bicolour": 0.45, "tuxedo": 0.55, "tabby": 0.30, "points": 0.65, "mask": 0.70}.get(str(coat.marking), 0.0))


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		# The coat's shader materials are owned by this actor; drop the cache so
		# no later call can touch a material the renderer has already released.
		_materials.clear()


## A small idle: the head turns, the tail sways and the legs stay planted. A
## walking pet instead takes a four-beat gait whose stride follows its length.
## Both go through the same joint setters, so there is no second system.
func animate(delta: float, moving: bool, speed_factor: float = 1.0) -> void:
	if speed_factor <= 0.0:
		stop_squeak()
		return
	_time += delta * clampf(speed_factor, 0.0, 3.0) * 0.9
	var caring: bool = not interaction.is_empty() and not moving
	if not caring and not moving and not behavior.is_empty():
		_behavior_pose(delta)
		return
	_settle_body(delta, caring)
	if caring:
		_care_pose(delta)
		if is_instance_valid(_ring): _ring.rotation.y = _time * 0.6
		return
	var stride: float = float(SPECIES_LENGTH.get(species, 0.60))
	if is_instance_valid(_head):
		var look: float = sin(_time * 0.7 + _phase) * 0.16
		var nod: float = maxf(0.0, sin(_time * 0.45 + _phase)) * 0.07
		if moving:
			look = sin(_time * 2.2 + _phase) * 0.06
			nod = 0.035 + sin(_time * 4.4 + _phase) * 0.03
		_head.rotation = Vector3(nod, look, 0.0)
	if is_instance_valid(_tail):
		var sway: float = sin(_time * 1.6 + _phase) * (0.30 if moving else 0.22)
		var lift: float = -0.22 + sin(_time * 1.1 + _phase) * 0.08
		if moving:
			lift = -0.10 + sin(_time * 3.2 + _phase) * 0.12
		_tail.basis = Basis.from_euler(Vector3(lift, sway, 0.0)) * _tail_rest_basis
	for index: int in range(_legs.size()):
		var leg: Node3D = _legs[index]
		if not is_instance_valid(leg):
			continue
		# Diagonal pairs swing together, which reads as a real four-beat trot.
		var reach: float = 0.0
		if moving:
			var offset: float = 0.0 if index in [0, 3] else PI
			reach = sin(_time * stride * 6.0 + offset) * 0.42
		else:
			# Standing, each leg only settles with the body's breathing.
			reach = sin(_time * 0.5 + _phase + float(index) * 1.2) * 0.012
		leg.rotation = Vector3(reach, 0.0, 0.0)
	if is_instance_valid(_ring):
		_ring.rotation.y = _time * 0.6


func set_interaction(id: String, time: float, partner: Vector3) -> void:
	interaction = id
	interaction_time = time
	_partner = partner


func clear_interaction() -> void:
	interaction = ""


func set_behavior(id: String, elapsed: float) -> void:
	behavior = id
	behavior_time = elapsed


func clear_behavior() -> void:
	behavior = ""


func _behavior_pose(delta: float) -> void:
	if not is_instance_valid(_model): return
	var blend: float = 1.0 - exp(-delta * 8.0)
	var h: float = float(SPECIES_HEIGHT.get(species, .30))
	var body_rotation := Vector3.ZERO
	var body_position := Vector3.ZERO
	var head := Vector3.ZERO
	var legs: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO]
	var t: float = behavior_time
	match behavior:
		"trick_sit", "trick_paw", "trick_high_five", "trick_speak":
			body_rotation.x = -.38; body_position.y = h * .08
			legs[2].x = -1.1; legs[3].x = -1.1
			if behavior in ["trick_paw", "trick_high_five"]: legs[1].x = -1.25 if behavior == "trick_high_five" else -.65
			head.x = -.25 + (.2 * sin(t * 8.0) if behavior == "trick_speak" else 0.0)
		"trick_lie", "trick_play_dead":
			body_position.y = -h * .28
			for leg: int in range(4): legs[leg].x = -1.2 if leg < 2 else 1.2
			if behavior == "trick_play_dead": body_rotation.z = PI * .5; body_position.y = h * .12
		"trick_roll":
			body_rotation.z = TAU * clampf(t / 3.0, 0.0, 1.0); body_position.y = h * .4 * sin(clampf(t / 3.0, 0.0, 1.0) * PI)
		"trick_backflip":
			var part: float = clampf(t / 2.0, 0.0, 1.0)
			body_rotation.x = -TAU * part; body_position.y = sin(part * PI) * .8
		"trick_dance":
			body_rotation = Vector3(-1.0, sin(t * 2.0) * .5, sin(t * 5.0) * .12)
			body_position.y = h * .35
			legs[0].x = -.9; legs[1].x = -.9
			legs[2].x = sin(t * 6.0) * .3; legs[3].x = -legs[2].x
		"rest":
			body_position.y = -h * .30 + sin(t * .7) * .003
			legs = [Vector3(-1.25, 0, .1), Vector3(-1.25, 0, -.1), Vector3(1.2, 0, .1), Vector3(1.2, 0, -.1)]
			head = Vector3(.32, .08, 0)
		"scratch":
			body_rotation.x = -.8
			body_position.y = h * .13
			legs[0] = Vector3(-1.15 + sin(t * 10.0) * .40, 0, 0)
			legs[1] = Vector3(-1.15 - sin(t * 10.0) * .40, 0, 0)
			head.x = .35
		"climb":
			body_rotation.x = -.5
			for i: int in range(4): legs[i].x = sin(t * 10.0 + float(i) * PI) * .8
		"tree_play", "toy_play":
			body_rotation.x = .14
			body_position.y = sin(t * 4.0) * .012
			legs[0].x = maxf(0.0, sin(t * 5.0)) * -1.0
			legs[1].x = maxf(0.0, sin(t * 5.0 + PI)) * -1.0
			head = Vector3(.45, sin(t * 4.0) * .25, 0)
		"eat", "retrieve", "sniff":
			head = Vector3(.60 + sin(t * 7.0) * .08, sin(t * 2.0) * .08, 0)
	_model.rotation = _model.rotation.lerp(body_rotation, blend)
	_model.position = _model.position.lerp(body_position, blend)
	for i: int in range(_legs.size()):
		if is_instance_valid(_legs[i]): _legs[i].rotation = _legs[i].rotation.lerp(legs[i], blend)
	if is_instance_valid(_head): _head.rotation = _head.rotation.lerp(head, blend)
	if is_instance_valid(_tail): _tail.basis = Basis.from_euler(Vector3(-.65 if behavior == "rest" else -.05, sin(t * 3.0) * (.04 if behavior == "rest" else (0.0 if behavior == "trick_play_dead" else .25)), 0)) * _tail_rest_basis


## A short rubber-toy chirp, synthesised as PCM to keep the asset portable.
## A distinct pitch sweep separates it from speech, UI clicks and alarms.
static func squeak_stream() -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.mix_rate = 22050
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	var duration: float = .19
	var count: int = int(duration * stream.mix_rate)
	var samples := PackedByteArray()
	samples.resize(count * 2)
	var phase: float = 0.0
	for i: int in range(count):
		var t: float = float(i) / float(stream.mix_rate)
		var unit: float = t / duration
		phase += TAU * (950.0 + sin(unit * PI) * 1050.0) / float(stream.mix_rate)
		var envelope: float = sin(unit * PI) * minf(1.0, t * 100.0)
		var value: int = int((sin(phase) + .25 * sin(phase * 2.0)) * envelope * 10000.0)
		samples.encode_s16(i * 2, value)
	stream.data = samples
	return stream


func squeak() -> void:
	if not is_instance_valid(_squeak_player):
		_squeak_player = AudioStreamPlayer3D.new()
		_squeak_player.name = "SqueakyToyAudio"
		_squeak_player.stream = squeak_stream()
		_squeak_player.volume_db = -9.0
		_squeak_player.unit_size = 10.0
		_squeak_player.max_distance = 35.0
		add_child(_squeak_player)
	_squeak_player.pitch_scale = 1.13 if species == "cat" else .93
	_squeak_player.play()
	squeak_count += 1


## Two short low-frequency bursts make Speak an audible command.
func bark() -> void:
	if not is_instance_valid(_bark_player):
		_bark_player = AudioStreamPlayer3D.new();_bark_player.name = "DogBarkAudio"
		var stream := AudioStreamWAV.new();stream.format = AudioStreamWAV.FORMAT_16_BITS;stream.mix_rate = 22050
		var samples := PackedByteArray();samples.resize(8820 * 2)
		for n: int in 8820:
			var t: float = float(n) / 22050.0
			var beat: float = fmod(t, .2)
			var envelope: float = sin(PI * minf(beat / .12, 1.0)) * exp(-beat * 15.0) if beat < .12 else 0.0
			var wave: float = sin(t * TAU * 180.0) + .45 * sin(t * TAU * 370.0) + .2 * sin(t * TAU * 913.0)
			samples.encode_s16(n * 2, int(wave * envelope * 11000.0))
		stream.data = samples;_bark_player.stream = stream;_bark_player.volume_db = -10.0;_bark_player.max_distance = 30.0
		add_child(_bark_player)
	_bark_player.play();bark_count += 1

func stop_squeak() -> void:
	if is_instance_valid(_squeak_player): _squeak_player.stop()
	if is_instance_valid(_bark_player): _bark_player.stop()


## The whole body leans, sits, bows or rolls from the model root; with no care
## beat it eases back to standing.
func _body_goal(caring: bool) -> Array:
	var h: float = float(SPECIES_HEIGHT.get(species, 0.30))
	var scale: float = h / 0.52
	if not caring: return [Vector3.ZERO, Vector3.ZERO]
	match interaction:
		"pet_pet", "pet_play", "pet_teach_trick", "pet_train", "pet_train_social", "pet_train_logic", "bathe_pet":
			return [Vector3(-.38, 0, 0), Vector3(0, .05 * scale, 0)]
		"pet_tummy_rub":
			var roll: float = smoothstep(0.0, .9, interaction_time)
			return [Vector3(0, 0, roll * PI * .92), Vector3(0, roll * h, 0)]
		"pet_tug":
			var pull: float = .5 + .5 * sin(interaction_time * 3.2)
			return [Vector3(.22, 0, 0), Vector3(0, 0, (-.05 + .09 * pull) * scale)]
		"pet_feed":
			return [Vector3(.10 if interaction_time > 1.4 else 0.0, 0, 0), Vector3.ZERO]
	return [Vector3.ZERO, Vector3.ZERO]


func _settle_body(delta: float, caring: bool) -> void:
	if not is_instance_valid(_model): return
	var goal: Array = _body_goal(caring)
	var blend: float = 1.0 - exp(-delta * 7.0)
	_model.rotation = _model.rotation.lerp(goal[0], blend)
	_model.position = _model.position.lerp(goal[1], blend)


## Joint poses for each care beat: sitting up to be stroked, legs in the air
## for a tummy rub with a happy back-leg kick, a play bow and head shake on the
## rope, head down in the bowl, a raised paw for a trick.
func _care_pose(delta: float) -> void:
	var blend: float = 1.0 - exp(-delta * 9.0)
	var ct: float = interaction_time
	var legs: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO]
	var head := Vector3(-.1, 0, 0)
	var wag: float = sin(_time * 14.0) * .5
	match interaction:
		"pet_pet", "pet_play", "pet_teach_trick", "pet_train", "pet_train_social", "pet_train_logic", "bathe_pet":
			legs = [Vector3(.38, 0, 0), Vector3(.38, 0, 0), Vector3(-1.1, 0, .08), Vector3(-1.1, 0, -.08)]
			head = Vector3(-.30, 0, .10 * sin(ct * 1.3))
			if interaction in ["pet_play", "pet_teach_trick"]:
				var beg: float = smoothstep(1.8, 2.1, fmod(ct, 3.2)) * (1.0 - smoothstep(2.9, 3.2, fmod(ct, 3.2)))
				legs[1] = Vector3(.38 - 1.3 * beg, 0, 0)
				head.x -= .15 * beg
		"pet_tummy_rub":
			var roll: float = smoothstep(0.0, .9, ct)
			var burst: float = smoothstep(.55, .75, sin(ct * 1.4))
			legs = [Vector3(sin(ct * 5.0) * .35 * roll, 0, 0), Vector3(sin(ct * 5.0 + 1.5) * .35 * roll, 0, 0),
				Vector3((.25 + sin(ct * 18.0) * .7 * burst) * roll, 0, 0), Vector3(.3 * sin(ct * 4.0) * roll, 0, 0)]
			head = Vector3(-.35 * roll, .15 * sin(ct * .8), 0)
		"pet_tug":
			legs = [Vector3(-.35, 0, 0), Vector3(-.35, 0, 0), Vector3(.30, 0, 0), Vector3(.30, 0, 0)]
			head = Vector3(.12, sin(ct * 11.0) * .35, 0)
		"pet_feed":
			if ct > 1.4: head = Vector3(.75 + sin(_time * 7.0) * .08, 0, 0)
			else: head = Vector3(-.2, 0, 0)
		_:
			wag *= .6
	for index: int in range(_legs.size()):
		if is_instance_valid(_legs[index]): _legs[index].rotation = _legs[index].rotation.lerp(legs[index], blend)
	if is_instance_valid(_head): _head.rotation = _head.rotation.lerp(head, blend)
	if is_instance_valid(_tail): _tail.basis = Basis.from_euler(Vector3(-.05, wag, 0)) * _tail_rest_basis


## Where a stroking hand runs along the coat.
func back_point() -> Vector3:
	return to_global(Vector3(0, float(SPECIES_HEIGHT.get(species, 0.30)) * .97 + .01, -.02))


## The upturned tummy while rolled over (and the flank before the roll lands).
func belly_point() -> Vector3:
	return to_global(Vector3(0, float(SPECIES_HEIGHT.get(species, 0.30)) * .64, -.02))


## The front of the muzzle, where a rope toy is gripped.
func mouth_point() -> Vector3:
	if is_instance_valid(_head): return _head.to_global(Vector3(0, -.02, float(MOUTH_REACH.get(species, .14))))
	return to_global(Vector3(0, float(SPECIES_HEIGHT.get(species, 0.30)) * .85, .45))


## The collar ring a lead clips to.
func collar_point() -> Vector3:
	if is_instance_valid(_collar): return _collar.global_position + Vector3(0, -.03, 0)
	return to_global(Vector3(0, float(SPECIES_HEIGHT.get(species, 0.30)) * .78, .27))


func set_selected(value: bool) -> void:
	selected = value
	if is_instance_valid(_ring):
		_ring.visible = value


## The label anchor, so a controller can float text over the pet.
func speech_anchor() -> Vector3:
	return Vector3(0.0, float(SPECIES_HEIGHT.get(species, 0.30)) + 0.22, 0.0)
