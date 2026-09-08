extends RefCounted
class_name LifeOvenSequence
## All appliance and handoff motion derives from persisted recipe progress.
const PHASES: Array = [
	["season",0.0,.12], ["reach_load",.12,.16], ["open_load",.16,.19],
	["pull_load",.19,.225], ["load",.225,.28], ["push_load",.28,.315],
	["close_load",.315,.35], ["release_load",.35,.3855], ["bake",.3855,.726],
	["reach_unload",.726,.762], ["open_unload",.762,.792], ["pull_unload",.792,.822],
	["unload",.822,.882], ["push_unload",.882,.936], ["close_unload",.936,.968],
	["release_unload",.968,1.0],
]
static func phase(p:float)->String:
	for entry:Array in PHASES:
		if p<float(entry[2]):return str(entry[0])
	return "release_unload"

static func fraction(p:float,name:String)->float:
	for entry:Array in PHASES:
		if str(entry[0])==name:return clampf((p-float(entry[1]))/(float(entry[2])-float(entry[1])),0,1)
	return 0.0

static func crouch(p:float)->float:
	return maxf(smoothstep(.40,1,fraction(p,"reach_load"))*(1-smoothstep(0,.60,fraction(p,"release_load"))),smoothstep(.40,1,fraction(p,"reach_unload"))*(1-smoothstep(0,.60,fraction(p,"release_unload"))))

static func transfer_height(p:float)->float:
	return maxf(smoothstep(.70,1,fraction(p,"pull_load"))*(1-smoothstep(.50,1,fraction(p,"push_load"))),smoothstep(.70,1,fraction(p,"pull_unload"))*(1-smoothstep(.50,1,fraction(p,"push_unload"))))

static func side_carry(p:float)->float:
	return maxf(smoothstep(0,.40,fraction(p,"reach_load"))*(1-smoothstep(.60,1,fraction(p,"release_load"))),smoothstep(0,.40,fraction(p,"reach_unload"))*(1-smoothstep(.60,1,fraction(p,"release_unload"))))

static func support_offset(p:float)->Vector3:
	return Vector3(-.105*(1.0-side_carry(p)),-.004,0)

static func door_open(p:float)->float:
	return maxf(smoothstep(0,1,fraction(p,"open_load"))*(1-smoothstep(.50,1,fraction(p,"close_load"))),smoothstep(0,1,fraction(p,"open_unload"))*(1-smoothstep(.50,1,fraction(p,"close_unload"))))

static func rack_extension(p:float)->float:
	return .22*maxf(smoothstep(.50,1,fraction(p,"pull_load"))*(1-smoothstep(.50,1,fraction(p,"push_load"))),smoothstep(.50,1,fraction(p,"pull_unload"))*(1-smoothstep(.50,1,fraction(p,"push_unload"))))

static func apply_door(oven:Node3D,p:float)->void:
	var door:Node3D=oven.find_child("OvenDoor",true,false)
	if is_instance_valid(door):door.rotation.x=PI*.5*door_open(p)
	var carrier:Node3D=oven.find_child("OvenRackCarrier",true,false)
	if is_instance_valid(carrier):carrier.position.z=rack_extension(p)

static func inside(p:float)->bool:
	return fraction(p,"load")>=1.0 and fraction(p,"unload")<=.50

static func tray(oven:Node3D,p:float,held:Transform3D)->Transform3D:
	var rack:Node3D=oven.find_child("OvenRack",true,false)
	if not is_instance_valid(rack):return held
	var result:Transform3D=held
	var amount:float=smoothstep(.50,1,fraction(p,"load"))*(1-smoothstep(.50,1,fraction(p,"unload")))
	# Full-size dish stays level, supported by the real sliding rack.
	var start:Vector3=oven.to_local(held.origin)
	var finish:Vector3=oven.to_local(rack.global_position)
	# Lower outside the appliance, align with its opening, then slide forward.
	# A diagonal shortcut cuts the full-width handles through the enamel side.
	result.origin=oven.to_global(Vector3(lerpf(start.x,finish.x,smoothstep(.20,.70,amount)),lerpf(start.y,finish.y,smoothstep(0,.30,amount)),lerpf(start.z,finish.z,smoothstep(.45,1,amount))))
	return result
