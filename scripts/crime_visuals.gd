extends RefCounted
## Presentation shared by the home response and the station's custody room.
const Actor = preload("res://scripts/actor.gd")

static func material(color: String, emissive: bool = false) -> StandardMaterial3D:
	var out := StandardMaterial3D.new()
	out.albedo_color = Color(color)
	out.roughness = .65
	if emissive:
		out.emission_enabled = true
		out.emission = Color(color)
		out.emission_energy_multiplier = 2.0
	return out

static func box(parent: Node3D, at: Vector3, size: Vector3, color: String, label: String = "") -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	node.mesh = mesh
	node.material_override = material(color)
	parent.add_child(node)
	node.position = at
	if not label.is_empty(): node.name = label
	return node

static func sphere(parent: Node3D, at: Vector3, size: Vector3, color: String, label: String = "") -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = .5
	mesh.height = 1
	mesh.radial_segments = 16
	mesh.rings = 8
	node.mesh = mesh
	node.material_override = material(color)
	parent.add_child(node)
	node.position = at
	node.scale = size
	if not label.is_empty(): node.name = label
	return node

static func label(parent: Node3D, at: Vector3, content: String, size: int = 35) -> Label3D:
	var node := Label3D.new()
	node.text = content
	node.font_size = size
	node.pixel_size = .006
	node.outline_size = 4
	node.modulate = Color("f4efe3")
	node.outline_modulate = Color("1d3046")
	parent.add_child(node)
	node.position = at
	return node

static func person(parent: Node3D, role: String, index: int = 0) -> LifeActor:
	var body := Actor.new()
	body.name = "Burglar" if role == "burglar" else "Officer_%d" % index
	parent.add_child(body)
	body.configure({"name": "Unknown burglar" if role == "burglar" else "Officer %s" % ["Reed", "Patel"][index % 2],
		"age_stage":"adult", "life_stage":"adult", "frame":index % 2, "outfit":3,
		"hair":5, "hair_color":"24242a", "top_color":"e8e8e1" if role == "burglar" else "233b59",
		"bottom_color":"20242b", "shoe_color":"141920", "skin_color":"d09e7a" if index == 0 else "a67655"})
	body.voice_enabled = false
	body.set_selected(false)
	var head: Node3D = body._joints.get("Head", body._model)
	if role == "burglar":
		var shader := Shader.new()
		shader.code = "shader_type spatial; varying vec3 at; void vertex(){at=VERTEX;} void fragment(){float stripe=step(0.5,fract(at.y*11.0));ALBEDO=mix(vec3(0.035,0.04,0.05),vec3(0.92,0.91,0.86),stripe);ROUGHNESS=0.9;}"
		var striped := ShaderMaterial.new()
		striped.shader = shader
		for mesh: MeshInstance3D in body._model.find_children("*", "MeshInstance3D", true, false):
			for i: int in mesh.mesh.get_surface_count():
				var original: Material = mesh.mesh.surface_get_material(i)
				if original != null and original.resource_name in ["Top", "Top_seam"]:
					mesh.set_surface_override_material(i, striped)
		sphere(head, Vector3(0,.14,0), Vector3(.31,.17,.29), "141920", "BlackBeanie")
		box(head, Vector3(0,.013,.128), Vector3(.255,.058,.045), "141920", "EyeMask")
		for side: float in [-1.0, 1.0]:
			sphere(head, Vector3(side*.060,.017,.152), Vector3(.045,.020,.008), "e8e6dc")
		sphere(body._model, Vector3(.22,.95,-.20), Vector3(.43,.57,.30), "4a4036", "LootSack")
	else:
		sphere(head, Vector3(0,.155,0), Vector3(.34,.14,.29), "172c44", "PoliceCap")
		box(head, Vector3(0,.117,.145), Vector3(.32,.025,.15), "14263a", "CapVisor")
		box(head, Vector3(0,.155,.141), Vector3(.075,.060,.012), "e1bc55", "CapBadge")
		box(body._model, Vector3(-.095,1.28,.155), Vector3(.07,.08,.025), "e1bc55", "Badge")
		box(body._model, Vector3(0,.98,0), Vector3(.38,.08,.25), "141e2b", "DutyBelt")
		box(body._model, Vector3(.24,1.08,0), Vector3(.10,.20,.08), "1a2128", "Radio")
	return body

static func pose(body: LifeActor, mode: String, delta: float, moving: bool, clock: float) -> void:
	body.animate(delta, .75 if mode == "sneak" else 1.0, moving, "argue" if mode == "scuffle" else "")
	if mode == "sneak":
		body.visual.rotation.x = -.16
		body.visual.position.y = -.08
		joint(body, "Arm_L", Vector3(-.55,0,-.1))
		joint(body, "Arm_R", Vector3(-.50,0,.1))
		joint(body, "Forearm_L", Vector3(-.8,0,0))
		joint(body, "Forearm_R", Vector3(-.8,0,0))
	elif mode == "cuffed":
		body.visual.rotation.x = -.055
		var restrained: Dictionary = {}
		body._reach_hand(restrained,"L",Vector3(-.062,.96,-.21),Vector3(-.6,-.7,-.45))
		body._reach_hand(restrained,"R",Vector3(.062,.96,-.21),Vector3(.6,-.7,-.45))
		for key: String in restrained: joint(body,key,restrained[key])
	elif mode == "scuffle":
		body.visual.rotation.z = sin(clock*9.0)*.07
		joint(body, "Arm_L", Vector3(-1.1+sin(clock*7.0)*.2,0,-.15))
		joint(body, "Arm_R", Vector3(-1.0-sin(clock*7.0)*.2,0,.15))
		joint(body, "Forearm_L", Vector3(-.6,0,0))
		joint(body, "Forearm_R", Vector3(-.7,0,0))
	elif mode == "seated":
		body.visual.position.y = -.55
		for side: String in ["L","R"]:
			joint(body, "Leg_"+side, Vector3(-PI*.47,0,0))
			joint(body, "Shin_"+side, Vector3(PI*.48,0,0))
	elif mode == "steal":
		body.visual.rotation.x = -.18
		for side: String in ["L","R"]:
			joint(body, "Arm_"+side, Vector3(-1.25,0,0))
			joint(body, "Forearm_"+side, Vector3(-.6,0,0))

static func joint(body: LifeActor, key: String, rotation: Vector3) -> void:
	if body._joints.has(key): body._joints[key].rotation = Vector3(body._rest_rotations[key]) + rotation
	for entry: Dictionary in body._rig_bones:
		if str(entry.name) != key: continue
		var rest: Quaternion = entry.rest
		entry.skeleton.set_bone_pose_rotation(int(entry.index),rest.inverse()*Quaternion.from_euler(rotation)*rest)

static func cuffs(body: LifeActor) -> Node3D:
	var rig := Node3D.new()
	rig.name = "Handcuffs"
	body._model.add_child(rig)
	rig.position = Vector3(0,.96,-.21)
	for side: float in [-1.0, 1.0]:
		var ring := MeshInstance3D.new()
		var torus := TorusMesh.new()
		torus.inner_radius = .032; torus.outer_radius = .050
		torus.rings = 16; torus.ring_segments = 8
		ring.mesh = torus; ring.material_override = material("c4d0da")
		rig.add_child(ring); ring.position.x = side*.062; ring.rotation.x = PI*.5
	box(rig, Vector3.ZERO, Vector3(.10,.018,.018), "c4d0da", "CuffChain")
	return rig

static func car(parent: Node3D) -> Node3D:
	var rig := Node3D.new(); rig.name = "PoliceCar"; parent.add_child(rig)
	var shell: Node3D = load("res://assets/models/juniper_car.glb").instantiate()
	rig.add_child(shell)
	for mesh: MeshInstance3D in shell.find_children("*", "MeshInstance3D", true, false):
		var mesh_name: String = str(mesh.name).to_lower()
		if mesh_name.contains("body") or LifeCatalogVariants.is_tint(mesh.name): mesh.material_override = material("f0eee6")
		elif mesh_name.contains("hood") or mesh_name.contains("hatch"): mesh.material_override = material("203449")
		elif mesh_name.contains("glass"):
			var glazing := material("8399a5")
			glazing.albedo_color.a = .24
			glazing.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			glazing.cull_mode = BaseMaterial3D.CULL_DISABLED
			mesh.material_override = glazing
	box(rig,Vector3(0,.57,-.65),Vector3(1.28,.24,.56),"24313b","BackSeat")
	box(rig,Vector3(0,.81,-.93),Vector3(1.28,.49,.10),"24313b","BackSeatRest")
	box(rig, Vector3(0,1.70,0), Vector3(1.30,.075,.27), "13273e", "LightBar")
	for side: float in [-1.0,1.0]:
		var lamp := box(rig, Vector3(side*.40,1.79,0), Vector3(.46,.13,.25), "e13537" if side < 0 else "3676f3", "RedLight" if side < 0 else "BlueLight")
		lamp.material_override = material("e13537" if side < 0 else "3676f3", true)
		var beacon := OmniLight3D.new()
		beacon.name = "BeaconGlow"
		beacon.light_color = Color("e13537" if side < 0 else "3676f3")
		beacon.omni_range = 3.5; beacon.light_energy = .8
		lamp.add_child(beacon)
		box(rig, Vector3(side*.883,.85,-.10), Vector3(.024,.26,1.25), "203c61", "PoliceStripe")
		var text := label(rig, Vector3(side*.901,.87,-.08), "POLICE", 28)
		text.rotation.y = side*PI*.5
	return rig

static func station(parent: Node3D, at: Vector3 = Vector3.ZERO, occupied: bool = false) -> Node3D:
	var station := Node3D.new(); station.name = "PoliceStationCustody"; parent.add_child(station); station.position = at
	box(station, Vector3(0,.02,0), Vector3(6,.25,5), "c5c8c7", "StationFloor")
	box(station, Vector3(1.5,-.025,5.0), Vector3(4.0,.12,5.0), "b9b9ae", "StationDriveway")
	box(station, Vector3(0,1.45,-2.5), Vector3(6,2.7,.18), "d8dfdf", "StationBackWall")
	box(station, Vector3(-3,1.45,0), Vector3(.18,2.7,5), "b5c4ce", "StationSideWall")
	box(station, Vector3(0,2.75,-2.39), Vector3(4.3,.47,.12), "203c61", "StationSign")
	label(station, Vector3(0,2.76,-2.30), "JUNIPER BAY POLICE", 31)
	box(station, Vector3(-1.6,.68,1.1), Vector3(2,1.05,.68), "344c68", "ReceptionDesk")
	label(station, Vector3(-1.6,1.12,1.46), "RECEPTION", 18)
	# The open-front cutaway keeps the two-bed custody room inspectable.
	box(station, Vector3(.35,1.35,-.6), Vector3(.12,2.4,3.6), "b0babe", "CellPartition")
	# A low side wall and full-height bars enclose the right of the cell while
	# retaining the same cutaway visibility as the town's other buildings.
	box(station, Vector3(3,.43,-.6), Vector3(.12,.55,3.8), "b0babe", "CellRightWall")
	for z: float in [-2.4,-2.1,-1.8,-1.5,-1.2,-.9,-.6,-.3,0,.3,.6,.9,1.2]:
		box(station,Vector3(3,1.4,z),Vector3(.035,2.5,.035),"596573","CellSideBar")
	box(station,Vector3(3,2.55,-.6),Vector3(.05,.05,3.8),"596573","CellSideRail")
	for x: float in [.4,.7,1.0,2.3,2.6,2.9]:
		box(station, Vector3(x,1.4,1.25), Vector3(.035,2.5,.035), "596573", "JailBar")
	for y: float in [.25,2.55]: box(station, Vector3(1.65,y,1.25), Vector3(2.65,.05,.05), "596573")
	var door := Node3D.new(); door.name = "JailDoor"; station.add_child(door); door.position = Vector3(1.08,0,1.25)
	for x: float in [0,.28,.56,.84,1.08]: box(door, Vector3(x,1.4,0), Vector3(.035,2.5,.04), "596573")
	for y: float in [.25,2.55]: box(door, Vector3(.54,y,0), Vector3(1.1,.05,.05), "596573")
	box(door, Vector3(.99,1.3,0), Vector3(.09,.14,.08), "b5ab84", "CellLock")
	box(station, Vector3(2.18,.43,-1.20), Vector3(1.25,.25,1.95), "6e8392", "CustodyBed")
	box(station, Vector3(2.18,.59,-1.25), Vector3(1.20,.08,1.82), "aec0c9", "CustodyMattress")
	box(station, Vector3(2.18,.67,-1.84), Vector3(.92,.13,.39), "e7e5db", "CustodyPillow")
	if occupied:
		var prisoner := person(station,"burglar")
		prisoner.position = Vector3(1.65,.16,0)
		prisoner._model.get_node("LootSack").hide()
		cuffs(prisoner)
		pose(prisoner,"cuffed",.01,false,0)
	return station

static func sound(kind: String) -> AudioStreamWAV:
	var rate: int = 16000
	var duration: float = 4.0 if kind == "creepy" else 2.0
	var count: int = int(rate*duration)
	var data := PackedByteArray(); data.resize(count*2)
	var phase: float = 0
	for i: int in count:
		var t: float = float(i)/rate
		var value: float
		if kind == "creepy":
			value = (sin(TAU*113*t)+.5*sin(TAU*119*t)+.28*sin(TAU*227*t))*.15*(.65+.35*sin(t*TAU*.5))
		else:
			var frequency: float = (690.0+300.0*sin(TAU*t*.75)) if kind == "siren" else (960.0 if fmod(t,.30)<.15 else 620.0)
			phase += TAU*frequency/rate
			value = (sin(phase)+.2*sin(phase*3))*.22
		data.encode_s16(i*2,int(clampf(value,-1,1)*32767))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS; stream.mix_rate = rate
	stream.data = data; stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_end = count
	return stream
