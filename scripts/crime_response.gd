extends Node3D
class_name LifeCrimeResponse
## One authoritative burglary journal and its visible police response. All
## movement through the home follows the world's actual floor/door graph.
const Visuals = preload("res://scripts/crime_visuals.gd")
const CarEntry = preload("res://scripts/car_entry.gd")
const BASE_CHANCE: float = .01
const CASH_LIMIT: int = LifeSim.ROBBERY_LOSS
const RECOVERY_BONUS: int = 200
const CURB := Vector3(2.4,.16,10.1)
const START := Vector3(23,.16,10.1)
const STATION := Vector3(-32,0,3)
const STATION_PARK := Vector3(-30,.16,7.0)
const PHASES: Array[String] = ["idle","sneaking","breaking_in","stealing","fleeing","escaped","police_arriving","officers_exiting","officers_approaching","scuffle","cuffing","escorting","loading","departing","station_unloading","station_escort","jailed"]
const STEALABLE: Array[String] = ["stereo","tv","computer","bedside_lamp","lamp","plant","painting","framed_picture","easel","guitar","violin","nightstand"]

signal notice(message: String)
signal changed
signal layout_changed
signal alert_requested

var world: LifeWorld
var household: LifeHousehold
var phase: String = "idle"
var burglary_phase: String = "idle"
var phase_time: float = 0
var burglary_time: float = 0
var elapsed: float = 0
var last_roll_day: int = 0
var incident: int = 0
var called: bool = false
var caller_id: String = ""
var alarm_triggered: bool = false
var stolen_cash: int = 0
var cash_taken: bool = false
var stolen_items: Array = []
var recovered: bool = false
var jailed_day: int = 0
var history: Array = []
var targets: Array[String] = []
var target_index: int = 0
var target_id: String = ""
var route_error: String = ""
var sound_enabled: bool = true
var home_visible: bool = true
var burglar: LifeActor
var officers: Array[LifeActor] = []
var police_car: Node3D
var station: Node3D
var cuff_view: Node3D
var car_entry: RefCounted
var audio: Dictionary = {}
var routes: Dictionary = {}
var _load_from: Vector3 = Vector3.ZERO
var _officer_from: Array = []
var _rng := RandomNumberGenerator.new()

func setup(owner_world: LifeWorld, owner_household: LifeHousehold) -> void:
	world = owner_world; household = owner_household
	_rng.randomize()
	name = "CrimeResponse"
	_ensure_visuals()
	_sync_visibility()

func _ensure_visuals() -> void:
	if is_instance_valid(burglar): return
	burglar = Visuals.person(self,"burglar")
	cuff_view = Visuals.cuffs(burglar)
	police_car = Visuals.car(self)
	police_car.position = START; police_car.rotation.y = -PI*.5
	car_entry = CarEntry.new(police_car,[])
	# Officers use the curb-side front door; the prisoner uses the opposite
	# rear door, reached by walking around the car's rear bumper.
	if car_entry.doors.has("front"):
		var front: Node3D = car_entry.doors.front.rig
		front.position.x *= -1
		front.scale.x *= -1
	for index: int in 2: officers.append(Visuals.person(self,"officer",index))
	station = Visuals.station(self,STATION)
	for kind: String in ["creepy","siren","alarm"]:
		var player := AudioStreamPlayer.new()
		player.name = "CrimeAudio_"+kind; player.stream = Visuals.sound(kind)
		player.volume_db = -15 if kind == "creepy" else -11
		add_child(player); audio[kind] = player

func busy() -> bool:
	return phase not in ["idle","escaped","jailed"]

func has_alarm() -> bool:
	if not is_instance_valid(world): return false
	for item: Dictionary in world.items:
		if str(item.kind) in ["security_alarm","burglar_alarm","burglar_prevention"]: return true
	return false

func set_home_visible(value: bool) -> void:
	home_visible = value
	_sync_visibility()

func set_sound(value: bool) -> void:
	sound_enabled = value
	_sync_audio()

func consider_night(day: int, roll: float = -1.0) -> Dictionary:
	if day <= last_roll_day: return {"ok":false,"reason":"Already checked this night."}
	last_roll_day = day
	if busy() or phase == "escaped": return {"ok":false,"reason":"An existing incident is still open."}
	var chance: float = _rng.randf() if roll < 0 else roll
	if chance >= BASE_CHANCE: return {"ok":false,"reason":"No break-in tonight.","chance":BASE_CHANCE}
	return begin_break_in()

func begin_break_in() -> Dictionary:
	if not is_instance_valid(world) or not is_instance_valid(household): return {"ok":false,"reason":"No home is available."}
	if busy() or phase == "escaped": return {"ok":false,"reason":"Resolve the current incident first."}
	_ensure_visuals()
	incident += 1; called = false; caller_id = ""; alarm_triggered = false
	stolen_cash = 0; stolen_items.clear(); recovered = false; cash_taken = false
	targets.clear(); target_index = 0; target_id = ""; routes.clear(); route_error = ""
	for kind: String in STEALABLE:
		for item: Dictionary in world.items:
			if str(item.kind) == kind and world.item_level(item) == 0 and targets.size() < 3:
				targets.append(str(item.id))
	burglar.position = _clear(Vector3(5.5,.16,6.6))
	burglar.rotation.y = PI
	police_car.position = START; police_car.rotation.y = -PI*.5
	car_entry.set_door("rear",0); car_entry.set_door("front",0)
	station.get_node("JailDoor").rotation.y = 0
	_set_burglary("sneaking")
	if not _route("burglar",burglar.position,_clear(Vector3(0,.16,4.75))):
		_set_phase("idle"); burglary_phase = "idle"
		return {"ok":false,"reason":"The home entrance cannot be reached."}
	_set_phase("sneaking")
	notice.emit("Someone in stripes is sneaking around your home. Call the police from the alert or any phone!")
	alert_requested.emit()
	return {"ok":true,"incident":incident}

func call_police(member_id: String = "") -> Dictionary:
	if phase in ["idle","jailed"]: return {"ok":false,"reason":"There is no active burglary to report."}
	if called: return {"ok":false,"reason":"Two officers are already on their way."}
	if not member_id.is_empty():
		var member: LifeSim = household.member_sim(member_id)
		if member == null: return {"ok":false,"reason":"Choose someone in the household to call."}
		var stage: String = str(member.character.get("age_stage",member.character.get("life_stage","adult")))
		if stage in ["baby","toddler"]: return {"ok":false,"reason":"A child or older Lifelet must call the police."}
		if member.is_away(): return {"ok":false,"reason":"Choose a Lifelet who is at home."}
	called = true; caller_id = member_id
	if phase == "stealing" and not alarm_triggered:
		# The reported thief pauses among the stolen belongings on hearing
		# approaching sirens; the officers must reach this interior position.
		_set_burglary("waiting")
	if phase == "escaped":
		burglar.position = _clear(Vector3(-7,.16,6.8))
		_set_burglary("waiting")
		notice.emit("A patrol located the reported burglar nearby. The stolen-property report is still open.")
	police_car.position = START; police_car.rotation.y = -PI*.5
	_set_phase("police_arriving")
	notice.emit("Police called. A patrol car with two officers is on its way.")
	return {"ok":true,"caller":caller_id}

func tick(delta: float, _game_minutes: float = 0.0) -> void:
	if delta <= 0 or not is_finite(delta) or not home_visible:
		_sync_audio()
		return
	var step: float = minf(delta,.25)
	elapsed += step; phase_time += step
	if phase in ["idle","escaped","jailed"]:
		_sync_audio(); return
	if phase in ["sneaking","breaking_in","stealing","fleeing","police_arriving","officers_exiting","officers_approaching"]:
		_tick_burglar(step)
	match phase:
		"police_arriving":
			police_car.position = police_car.position.move_toward(CURB,5.0*step)
			if police_car.position.distance_to(CURB) < .02:
				_officer_from.clear()
				for i: int in 2:
					officers[i].position = police_car.to_global(Vector3((-.36 if i == 0 else .36),.25,.12))
					_officer_from.append(officers[i].position)
				_set_phase("officers_exiting")
		"officers_exiting":
			car_entry.set_door("front",sin(clampf(phase_time/2.5,0,1)*PI))
			for i: int in 2:
				var end: Vector3 = _officer_door(i)
				officers[i].position = Vector3(_officer_from[i]).lerp(end,clampf((phase_time-.25)/1.75,0,1))
				Visuals.pose(officers[i],"walk",step,true,elapsed)
			if phase_time >= 2.5:
				_set_burglary("waiting")
				for i: int in 2: _officer_route(i)
				_set_phase("officers_approaching")
		"officers_approaching":
			var ready: bool = true
			for i: int in 2:
				if not _walk("officer_%d"%i,officers[i],step,1.9,"walk"): ready = false
				_face(officers[i],burglar.position)
			if ready and officers[0].position.distance_to(burglar.position) < 1.7 and officers[1].position.distance_to(burglar.position) < 1.7:
				_set_phase("scuffle")
			elif ready and phase_time > 1.0:
				# A furnishing may have changed the way in. The burglar leaves
				# by the same traversable front route, meeting officers outdoors.
				if _route("burglar",burglar.position,_clear(Vector3(0,.16,5.5))):
					_set_burglary("fleeing"); _set_phase("police_arriving"); police_car.position = CURB
		"scuffle":
			Visuals.pose(burglar,"scuffle",step,false,elapsed)
			for officer: LifeActor in officers: Visuals.pose(officer,"scuffle",step,false,elapsed+.7)
			if phase_time >= 3.2: _set_phase("cuffing")
		"cuffing":
			Visuals.pose(burglar,"cuffed",step,false,elapsed)
			for officer: LifeActor in officers: Visuals.pose(officer,"steal",step,false,elapsed)
			if phase_time >= 2.0:
				_recover()
				if _route_to_car("burglar",burglar.position,_rear_stand()):
					for i: int in 2: _route_to_car("officer_%d"%i,officers[i].position,_rear_stand()+Vector3(-.65 if i==0 else .65,0,.50))
					_set_phase("escorting")
		"escorting":
			var arrived: bool = _walk("burglar",burglar,step,1.05,"cuffed")
			for i: int in 2:
				var distance: float = officers[i].position.distance_to(burglar.position)
				_walk("officer_%d"%i,officers[i],step,1.0 if distance < 1.8 else 1.45,"walk")
			if arrived:
				_load_from = burglar.position
				_officer_from = [officers[0].position,officers[1].position]
				_set_phase("loading")
		"loading":
			car_entry.set_door("rear",minf(phase_time/.8,1) if phase_time < 3.2 else maxf(0,1-(phase_time-3.2)/.8))
			var seat: Vector3 = _rear_seat()
			burglar.position = _load_from.lerp(seat,clampf((phase_time-.8)/1.5,0,1))
			burglar.rotation.y = police_car.rotation.y
			Visuals.pose(burglar,"seated" if phase_time > 1.0 else "cuffed",step,false,elapsed)
			for i: int in 2:
				var front_seat: Vector3 = police_car.to_global(Vector3(-.34 if i == 0 else .34,.22,.20))
				officers[i].position = Vector3(_officer_from[i]).lerp(front_seat,clampf((phase_time-2)/2.0,0,1))
				Visuals.pose(officers[i],"seated" if phase_time > 2.3 else "walk",step,phase_time < 2.3,elapsed)
			if phase_time >= 4.3: _set_phase("departing")
		"departing":
			# The corner at the station is turned into early and the heading follows the
			# way the car is going at a bounded rate, so it never snaps round.
			var waypoint: Vector3 = Vector3(STATION_PARK.x,.16,CURB.z) if police_car.position.x > STATION_PARK.x+3.7 else STATION_PARK
			var direction: Vector3 = waypoint-police_car.position
			if direction.length() > .01: police_car.rotation.y = rotate_toward(police_car.rotation.y,PI if waypoint == STATION_PARK and direction.length() < 2.2 else atan2(direction.x,direction.z),2.6*step)
			police_car.position = police_car.position.move_toward(waypoint,4.5*step)
			_seat_party(step)
			if police_car.position.distance_to(STATION_PARK) < .03:
				_load_from = burglar.position
				_officer_from = [officers[0].position,officers[1].position]
				_set_phase("station_unloading")
		"station_unloading":
			car_entry.set_door("rear",minf(phase_time/.5,1))
			burglar.position = _load_from.lerp(STATION+Vector3(1.65,.16,3.5),clampf(phase_time/2.5,0,1))
			Visuals.pose(burglar,"cuffed",step,phase_time>1,elapsed)
			for i: int in 2:
				officers[i].position = Vector3(_officer_from[i]).lerp(STATION+Vector3(.5+float(i)*2,.16,3.7),clampf(phase_time/2.5,0,1))
				Visuals.pose(officers[i],"walk",step,true,elapsed)
			if phase_time >= 2.8:
				station.get_node("JailDoor").rotation.y = -PI*.52
				_set_phase("station_escort")
		"station_escort":
			car_entry.set_door("rear",0)
			var end: Vector3 = STATION+Vector3(1.65,.16,0)
			_move_outside(burglar,end,step,1.0,"cuffed")
			_move_outside(officers[0],STATION+Vector3(1.1,.16,1.95),step,1.0,"walk")
			_move_outside(officers[1],STATION+Vector3(2.3,.16,1.95),step,1.0,"walk")
			if burglar.position.distance_to(end) < .03:
				station.get_node("JailDoor").rotation.y = 0
				jailed_day = household.day
				_set_phase("jailed")
				notice.emit("The officers booked the burglar into the station jail. Your stolen property and cash have been returned, plus ℒ200.")
	_flash_lights()
	_sync_audio()

func _tick_burglar(delta: float) -> void:
	burglary_time += delta
	match burglary_phase:
		"sneaking":
			if _walk("burglar",burglar,delta,.72,"sneak"):
				_set_burglary("breaking_in")
				if not called: _set_phase("breaking_in")
		"breaking_in":
			Visuals.pose(burglar,"steal",delta,false,elapsed)
			if has_alarm() and not alarm_triggered:
				alarm_triggered = true
				_mark_shaken()
				notice.emit("The keypad alarm is sounding! The burglar is frightened and the police have been called automatically.")
				call_police()
				_route("burglar",burglar.position,_clear(Vector3(3.7,.16,6.6)))
				_set_burglary("fleeing")
			elif burglary_time >= 3.0: _next_target()
		"to_item":
			if _walk("burglar",burglar,delta,.82,"sneak"):
				_set_burglary("taking")
		"taking":
			Visuals.pose(burglar,"steal",delta,false,elapsed)
			if burglary_time >= 1.8:
				_take_item()
				_next_target()
		"fleeing":
			if _walk("burglar",burglar,delta,1.2 if called else 1.55,"sneak"):
				if called: _set_burglary("waiting")
				else:
					_set_phase("escaped")
					_set_burglary("escaped")
					notice.emit("The burglar got away. Call the police to report the theft and recover the stolen property.")
		"waiting": Visuals.pose(burglar,"sneak",delta,false,elapsed)

func _next_target() -> void:
	while target_index < targets.size():
		target_id = targets[target_index]; target_index += 1
		var item: Dictionary = _item(target_id)
		if item.is_empty(): continue
		var at: Vector3 = world.approach(item)
		if not at.is_finite() or not _route("burglar",burglar.position,at): continue
		_set_burglary("to_item")
		if not called: _set_phase("stealing")
		return
	# An empty home still has a purse, but the burglar must enter it first.
	if not cash_taken:
		if target_id != "__cash":
			target_id = "__cash"
			if _route("burglar",burglar.position,_clear(Vector3(0,.16,2.5))):
				_set_burglary("to_item")
				if not called: _set_phase("stealing")
				return
		else: _take_cash()
	if called and not alarm_triggered:
		# Hearing the patrol at the curb makes the thief freeze at the last
		# stolen item. Officers still have to enter through the home's door.
		_set_burglary("waiting")
		return
	_route("burglar",burglar.position,_clear(Vector3(-7.5,.16,6.7)))
	_set_burglary("fleeing")
	if not called: _set_phase("fleeing")

func _take_item() -> void:
	if target_id == "__cash": _take_cash(); return
	for entry: Dictionary in world.serialize_items():
		if str(entry.get("id","")) != target_id: continue
		var live_item: Dictionary = _item(target_id)
		if not live_item.is_empty():
			# Layout serialization records the floor and horizontal position.
			# Keep the actual wall lift as well, so recovered art returns to the
			# height the player chose even after saving the open theft report.
			var lift: float = live_item.node.position.y-LifeWorld.Building.level_y(world.item_level(live_item))
			if not is_zero_approx(lift): entry["hang"] = lift
		# The journal exists before the furnishing leaves the scene. It survives
		# escape and save/load, including colour, rotation and variant settings.
		stolen_items.append(entry.duplicate(true))
		world.remove_item(target_id)
		layout_changed.emit()
		_take_cash()
		notice.emit("The burglar put your %s into the sack. Call the police!" % str(LifeCatalog.get_item(str(entry.kind)).get("label",entry.kind)))
		return

func _take_cash() -> void:
	if cash_taken: return
	cash_taken = true
	stolen_cash = mini(CASH_LIMIT,household.funds)
	household.set_funds(household.funds-stolen_cash)
	household.last_purse_note = "The burglar took ℒ%d. Call the police to recover it." % stolen_cash
	_mark_shaken()
	changed.emit()

func _mark_shaken() -> void:
	for member: Dictionary in household.members:
		if member.sim.has_method("mark_robbery_shaken"): member.sim.mark_robbery_shaken()
		else: member.sim.add_moodlet("Upset / Shaken","Tense","A burglar disturbed the safety of home.",2880,3)

func _recover() -> void:
	if recovered: return
	for entry: Dictionary in stolen_items:
		if _item(str(entry.id)).is_empty(): world.add_item(entry.duplicate(true),false)
	world.rebuild_navigation()
	household.set_funds(household.funds+stolen_cash+RECOVERY_BONUS)
	household.last_purse_note = "Police returned ℒ%d and all stolen items, plus a ℒ200 insurance apology payment." % stolen_cash
	recovered = true
	layout_changed.emit(); changed.emit()
	notice.emit("Burglar handcuffed. All stolen items and ℒ%d have been returned, plus a ℒ200 apology payment." % stolen_cash)

func _item(id: String) -> Dictionary:
	for item: Dictionary in world.items:
		if str(item.id) == id: return item
	return {}

func _clear(at: Vector3) -> Vector3:
	var result: Vector3 = world.nearest_clear_point(at,0)
	return at if not result.is_finite() else result

func _route(id: String, from: Vector3, to: Vector3) -> bool:
	var path: PackedVector3Array = world.path_to(from,to)
	if path.is_empty() or path[0].distance_to(from) > .65 or path[-1].distance_to(to) > .65:
		routes[id] = []
		route_error = "No clear route for %s from %s to %s." % [id,from,to]
		return false
	routes[id] = Array(path)
	route_error = ""
	return true

func _walk(id: String, body: LifeActor, delta: float, speed: float, mode: String) -> bool:
	var path: Array = routes.get(id,[])
	var remaining: float = delta*speed
	var moved: bool = false
	while not path.is_empty() and remaining > 0:
		var next: Vector3 = path[0]
		var distance: float = body.position.distance_to(next)
		if distance < .015: path.pop_front(); continue
		_face(body,next)
		var step: float = minf(distance,remaining)
		body.position = body.position.move_toward(next,step)
		remaining -= step; moved = true
		if distance <= step+.001: path.pop_front()
	routes[id] = path
	Visuals.pose(body,mode,delta,moved,elapsed)
	return path.is_empty()

func _face(body: Node3D, target: Vector3) -> void:
	var difference: Vector3 = target-body.position
	if Vector2(difference.x,difference.z).length() > .02: body.rotation.y = atan2(difference.x,difference.z)

func _officer_door(index: int) -> Vector3:
	return _clear(Vector3(CURB.x+(.8 if index == 0 else -.8),.16,8.5))

func _rear_stand() -> Vector3:
	var at: Vector3 = car_entry.stand_point("rear")
	at.y = .16
	return at

func _route_to_car(id: String, from: Vector3, stand: Vector3) -> bool:
	# The floor graph ends at the sidewalk. Beyond it the street is open;
	# explicit rear-bumper waypoints keep the escort out of the car body.
	var corner: Vector3 = _clear(Vector3(CURB.x+2.7,.16,8.5))
	if not _route(id,from,corner): return false
	routes[id].append(Vector3(CURB.x+2.7,.16,CURB.z+1.6))
	routes[id].append(stand)
	return true

func _rear_seat() -> Vector3:
	return police_car.to_global(Vector3(.36,.22,-.65))

func _officer_route(index: int) -> void:
	var offsets: Array[Vector3] = [Vector3(-.7 if index==0 else .7,0,.45),Vector3(0,0,.7),Vector3(-.65 if index==0 else .65,0,-.4),Vector3(0,0,-.7)]
	for offset: Vector3 in offsets:
		var goal: Vector3 = _clear(burglar.position+offset)
		var close_path: PackedVector3Array = world.path_to(burglar.position,goal)
		if close_path.is_empty(): continue
		var length: float = 0
		for point: int in range(1,close_path.size()): length += close_path[point-1].distance_to(close_path[point])
		# Euclidean distance alone permits an officer to scuffle through a
		# wall. A short traversable route proves both stand on the same side.
		if length > 1.5: continue
		if _route("officer_%d"%index,officers[index].position,goal): return
	_route("officer_%d"%index,officers[index].position,burglar.position)

func _move_outside(body: LifeActor, target: Vector3, delta: float, speed: float, mode: String) -> void:
	_face(body,target)
	var moving: bool = body.position.distance_to(target) > .02
	body.position = body.position.move_toward(target,delta*speed)
	Visuals.pose(body,mode,delta,moving,elapsed)

func _seat_party(delta: float) -> void:
	burglar.position = _rear_seat(); burglar.rotation.y = police_car.rotation.y
	Visuals.pose(burglar,"seated",delta,false,elapsed)
	for index: int in 2:
		officers[index].position = police_car.to_global(Vector3(-.34 if index == 0 else .34,.22,.20))
		officers[index].rotation.y = police_car.rotation.y
		Visuals.pose(officers[index],"seated",delta,false,elapsed)

func _set_phase(value: String) -> void:
	phase = value; phase_time = 0
	if history.is_empty() or str(history[-1]) != value: history.append(value)
	if history.size() > 128: history = history.slice(history.size()-128)
	_sync_visibility(); _sync_audio(); changed.emit()

func _set_burglary(value: String) -> void:
	burglary_phase = value; burglary_time = 0

func _sync_visibility() -> void:
	visible = home_visible
	if not is_instance_valid(burglar): return
	burglar.visible = phase not in ["idle","escaped"]
	police_car.visible = called and phase not in ["idle","escaped"]
	for officer: LifeActor in officers: officer.visible = called and phase not in ["idle","escaped","police_arriving"]
	cuff_view.visible = phase in ["cuffing","escorting","loading","departing","station_unloading","station_escort","jailed"]
	var sack: Node3D = burglar._model.get_node_or_null("LootSack")
	if is_instance_valid(sack): sack.visible = not recovered
	station.visible = phase in ["departing","station_unloading","station_escort","jailed"]
	_sync_audio()

func _sync_audio() -> void:
	for kind: String in audio:
		var playing: bool = sound_enabled and home_visible and busy() and (not is_instance_valid(household) or household.speed > 0)
		if kind == "creepy": playing = playing and not called and burglary_phase in ["sneaking","breaking_in","to_item","taking","fleeing"]
		elif kind == "siren": playing = playing and phase in ["police_arriving","departing"]
		elif kind == "alarm": playing = playing and alarm_triggered and phase in ["police_arriving","officers_exiting","officers_approaching"]
		var player: AudioStreamPlayer = audio[kind]
		if playing and not player.playing: player.play()
		elif not playing and player.playing: player.stop()

func _flash_lights() -> void:
	if not is_instance_valid(police_car): return
	for color: String in ["RedLight","BlueLight"]:
		var lamp: MeshInstance3D = police_car.get_node(color)
		var lit: bool = (fmod(elapsed,.6)<.3) == (color=="RedLight")
		(lamp.material_override as StandardMaterial3D).emission_energy_multiplier = 2.0 if lit else .05
		lamp.get_node("BeaconGlow").visible = lit

func decorate_station(parent: Node3D, at: Vector3 = Vector3.ZERO, occupied: bool = false) -> Node3D:
	return Visuals.station(parent,at,occupied or phase == "jailed")

static func _vector(value: Vector3) -> Array:
	return [value.x,value.y,value.z]

static func _read_vector(value: Variant, fallback: Vector3 = Vector3.ZERO) -> Vector3:
	if not value is Array or value.size() != 3: return fallback
	for axis: Variant in value:
		if not (axis is float or axis is int) or not is_finite(float(axis)): return fallback
	return Vector3(float(value[0]),float(value[1]),float(value[2]))

func snapshot() -> Dictionary:
	var saved_routes: Dictionary = {}
	for id: String in routes:
		var points: Array = []
		for point: Vector3 in routes[id]: points.append(_vector(point))
		saved_routes[id] = points
	var positions: Array = []
	for officer: LifeActor in officers: positions.append({"at":_vector(officer.position),"angle":officer.rotation.y})
	var officer_from: Array = []
	for point: Vector3 in _officer_from: officer_from.append(_vector(point))
	return {"version":1,"phase":phase,"burglary_phase":burglary_phase,"phase_time":phase_time,"burglary_time":burglary_time,
		"elapsed":elapsed,"last_roll_day":last_roll_day,"incident":incident,"called":called,"caller_id":caller_id,
		"alarm_triggered":alarm_triggered,"stolen_cash":stolen_cash,"cash_taken":cash_taken,"stolen_items":stolen_items.duplicate(true),
		"recovered":recovered,"jailed_day":jailed_day,"history":history.duplicate(),"targets":targets.duplicate(),"target_index":target_index,"target_id":target_id,
		"burglar_at":_vector(burglar.position) if is_instance_valid(burglar) else [0,.16,0],"burglar_angle":burglar.rotation.y if is_instance_valid(burglar) else 0,
		"car_at":_vector(police_car.position) if is_instance_valid(police_car) else _vector(START),"car_angle":police_car.rotation.y if is_instance_valid(police_car) else -PI*.5,
		"officers":positions,"routes":saved_routes,"load_from":_vector(_load_from),"officer_from":officer_from}

func restore(state: Dictionary) -> Dictionary:
	if state.is_empty():
		phase = "idle"; burglary_phase = "idle"; called = false
		stolen_items.clear(); stolen_cash = 0; recovered = false
		phase_time = 0; burglary_time = 0; elapsed = 0; last_roll_day = 0; incident = 0
		caller_id = ""; alarm_triggered = false; cash_taken = false; jailed_day = 0
		history.clear(); targets.clear(); target_index = 0; target_id = ""; routes.clear()
		_sync_visibility(); return {"ok":true}
	var error: String = validate_snapshot(state)
	if not error.is_empty(): return {"ok":false,"error":error}
	_ensure_visuals()
	phase = str(state.phase); burglary_phase = str(state.get("burglary_phase","waiting"))
	phase_time = maxf(0,float(state.get("phase_time",0))); burglary_time = maxf(0,float(state.get("burglary_time",0)))
	elapsed = maxf(0,float(state.get("elapsed",0))); last_roll_day = int(state.get("last_roll_day",0)); incident = int(state.get("incident",0))
	called = bool(state.get("called",false)); caller_id = str(state.get("caller_id","")); alarm_triggered = bool(state.get("alarm_triggered",false))
	stolen_cash = int(state.get("stolen_cash",0)); cash_taken = bool(state.get("cash_taken",false)); stolen_items = state.get("stolen_items",[]).duplicate(true)
	recovered = bool(state.get("recovered",false)); jailed_day = int(state.get("jailed_day",0)); history = state.get("history",[]).duplicate()
	targets.assign(state.get("targets",[])); target_index = int(state.get("target_index",0)); target_id = str(state.get("target_id",""))
	burglar.position = _read_vector(state.get("burglar_at")); burglar.rotation.y = float(state.get("burglar_angle",0))
	police_car.position = _read_vector(state.get("car_at"),START); police_car.rotation.y = float(state.get("car_angle",-PI*.5))
	var positions: Array = state.get("officers",[])
	for i: int in mini(2,positions.size()):
		officers[i].position = _read_vector(positions[i].get("at")); officers[i].rotation.y = float(positions[i].get("angle",0))
	routes.clear()
	for id: String in state.get("routes",{}):
		var points: Array = []
		for point: Variant in state.routes[id]: points.append(_read_vector(point))
		routes[id] = points
	_load_from = _read_vector(state.get("load_from")); _officer_from.clear()
	for point: Variant in state.get("officer_from",[]): _officer_from.append(_read_vector(point))
	while _officer_from.size() < 2: _officer_from.append(officers[_officer_from.size()].position)
	# Only remove items belonging to an unrecovered journal. Re-loading a
	# completed arrest must never remove returned belongings or pay twice.
	if not recovered:
		for entry: Dictionary in stolen_items:
			if not _item(str(entry.id)).is_empty(): world.remove_item(str(entry.id))
	station.get_node("JailDoor").rotation.y = -PI*.52 if phase == "station_escort" else 0
	Visuals.pose(burglar,"cuffed" if recovered else "sneak",.01,false,elapsed)
	if phase == "loading":
		car_entry.set_door("rear",minf(phase_time/.8,1) if phase_time < 3.2 else maxf(0,1-(phase_time-3.2)/.8))
		Visuals.pose(burglar,"seated" if phase_time > 1.0 else "cuffed",.01,false,elapsed)
	elif phase == "departing": _seat_party(.01)
	elif phase == "station_unloading": car_entry.set_door("rear",minf(phase_time/.5,1))
	else: car_entry.set_door("rear",0)
	car_entry.set_door("front",sin(clampf(phase_time/2.5,0,1)*PI) if phase == "officers_exiting" else 0)
	_sync_visibility()
	return {"ok":true}

static func _number(value: Variant, low: float, high: float, integer: bool = false) -> bool:
	if not (value is float or value is int): return false
	var number: float = float(value)
	return is_finite(number) and number >= low and number <= high and (not integer or number == floor(number))

static func _valid_vector(value: Variant) -> bool:
	return value is Array and value.size() == 3 and _number(value[0],-500,500) and _number(value[1],-10,100) and _number(value[2],-500,500)

static func validate_snapshot(state: Dictionary) -> String:
	if state.is_empty(): return ""
	if not _number(state.get("version"),1,1,true) or not state.get("phase") is String or str(state.phase) not in PHASES:
		return "Unsupported burglary save."
	if str(state.get("burglary_phase","")) not in ["idle","sneaking","breaking_in","to_item","taking","fleeing","escaped","waiting"]:
		return "Invalid saved burglary activity."
	for key: String in ["phase_time","burglary_time","elapsed"]:
		if not _number(state.get(key),0,1000000000): return "Invalid burglary timer: "+key
	for key: String in ["last_roll_day","incident","jailed_day"]:
		if not _number(state.get(key),0,1000000,true): return "Invalid burglary day or incident."
	for key: String in ["called","alarm_triggered","cash_taken","recovered"]:
		if not state.get(key) is bool: return "Invalid burglary status: "+key
	if not state.get("caller_id") is String: return "Invalid police caller."
	if not _number(state.get("stolen_cash"),0,CASH_LIMIT,true): return "Invalid stolen cash."
	if int(state.stolen_cash)>0 and not bool(state.cash_taken): return "Stolen cash lacks a theft record."
	if not state.get("stolen_items") is Array or state.stolen_items.size()>3: return "Invalid stolen-property journal."
	var seen: Dictionary = {}
	for entry: Variant in state.stolen_items:
		if not entry is Dictionary or not entry.get("id") is String or str(entry.id).is_empty() or seen.has(str(entry.id)):
			return "Invalid or duplicate stolen-property identity."
		if not entry.get("kind") is String or str(entry.kind) not in STEALABLE or not LifeCatalog.ITEMS.has(str(entry.kind)):
			return "Unknown stolen-property kind."
		for key: String in ["x","z"]:
			if not _number(entry.get(key),-500,500): return "Invalid stolen-property location."
		if not _number(entry.get("rotation",0),-36000,36000) or not _number(entry.get("level",0),0,LifeWorld.Building.MAX_LEVEL,true): return "Invalid stolen-property orientation or floor."
		if not _number(entry.get("hang",0),0,LifeWorld.Building.RISE): return "Invalid stolen-property hanging height."
		for key: String in ["style","size","color","paint"]:
			if entry.has(key) and not entry[key] is String: return "Invalid stolen-property appearance."
		seen[str(entry.id)] = true
	if not state.stolen_items.is_empty() and not bool(state.cash_taken): return "Stolen property lacks a completed theft record."
	var response: bool = str(state.phase) in ["police_arriving","officers_exiting","officers_approaching","scuffle","cuffing","escorting","loading","departing","station_unloading","station_escort","jailed"]
	if response != bool(state.called): return "Saved police dispatch disagrees with the response phase."
	var after_arrest: bool = str(state.phase) in ["escorting","loading","departing","station_unloading","station_escort","jailed"]
	if (after_arrest and not bool(state.recovered)) or (bool(state.recovered) and not after_arrest and str(state.phase)!="cuffing"):
		return "Saved restitution disagrees with the arrest phase."
	if bool(state.alarm_triggered) and not bool(state.called): return "The alarm has no dispatched police response."
	if str(state.phase)=="idle" and (bool(state.cash_taken) or not state.stolen_items.is_empty()): return "An idle incident cannot hold stolen property."
	if not state.get("targets") is Array or state.targets.size()>3: return "Invalid burglary targets."
	for id: Variant in state.targets:
		if not id is String: return "Invalid burglary target identity."
	if not _number(state.get("target_index"),0,state.targets.size(),true) or not state.get("target_id") is String: return "Invalid burglary target cursor."
	for key: String in ["burglar_at","car_at","load_from"]:
		if not _valid_vector(state.get(key)): return "Invalid saved crime actor position."
	for key: String in ["burglar_angle","car_angle"]:
		if not _number(state.get(key),-36000,36000): return "Invalid saved crime actor angle."
	if not state.get("officers") is Array or state.officers.size()!=2: return "A patrol must have exactly two officers."
	for officer: Variant in state.officers:
		if not officer is Dictionary or not _valid_vector(officer.get("at")) or not _number(officer.get("angle"),-36000,36000): return "Invalid saved police officer."
	if not state.get("officer_from") is Array or state.officer_from.size() not in [0,2]: return "Invalid police boarding positions."
	for point: Variant in state.officer_from:
		if not _valid_vector(point): return "Invalid police boarding position."
	if str(state.phase) in ["officers_exiting","loading","station_unloading"] and state.officer_from.size()!=2: return "The saved boarding sequence lacks its start positions."
	if not state.get("routes") is Dictionary: return "Invalid crime movement routes."
	for id: Variant in state.routes:
		if str(id) not in ["burglar","officer_0","officer_1"] or not state.routes[id] is Array or state.routes[id].size()>8192: return "Invalid crime movement route."
		for point: Variant in state.routes[id]:
			if not _valid_vector(point): return "Invalid crime route position."
	if not state.get("history") is Array or state.history.size()>128: return "Invalid crime phase history."
	for value: Variant in state.history:
		if not value is String or str(value) not in PHASES: return "Invalid crime phase history entry."
	return ""
