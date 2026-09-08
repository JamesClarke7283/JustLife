extends RefCounted
class_name LifeStairGait
## Deterministic contact schedule over authored treads. The controller owns distance.
## No queue, admission, arrival or save mutations happen in this pose sampler.
const SPEED:float=.65

static func plan(stair_transform:Transform3D,direction:int,rear_shoe_extent:float)->Dictionary:
	assert(direction in [-1,1])
	var start:=Vector3(0,0,-.5) if direction==1 else Vector3(0,3,4.25)
	# Leave the entire toe/heel behind the 12mm overhanging next tread nose.
	var center:float=minf(.125,.25-.016-rear_shoe_extent)
	var placements:Array[Vector3]=[]
	if direction==1:
		placements.append(Vector3(0,0,-.20))
		for i:int in range(15):placements.append(Vector3(0,.2*(i+1),center+.25*i))
		placements.append_array([Vector3(0,3,4),Vector3(0,3,4.25),Vector3(0,3,4.25)])
	else:
		placements.append(Vector3(0,3,4))
		for i:int in range(14,-1,-1):placements.append(Vector3(0,.2*(i+1),center+.25*i))
		placements.append_array([Vector3(0,0,-.20),Vector3(0,0,-.5),Vector3(0,0,-.5)])
	var contacts:Dictionary={"L":start,"R":start}
	var stages:Array=[]
	var distance:float=0
	for i:int in placements.size():
		var side:String="L" if i%2==0 else "R"
		var before:Dictionary=contacts.duplicate()
		var root_from:Vector3=(Vector3(contacts.L)+Vector3(contacts.R))*.5
		contacts[side]=placements[i]
		var root_to:Vector3=(Vector3(contacts.L)+Vector3(contacts.R))*.5
		var length:float=root_from.distance_to(root_to)
		stages.append({"side":side,"before":before,"after":contacts.duplicate(),"root_from":root_from,"root_to":root_to,"start":distance,"length":length})
		distance+=length
	return {"transform":stair_transform,"direction":direction,"stages":stages,"length":distance}

static func sample(schedule:Dictionary,distance:float)->Dictionary:
	var traveled:float=clampf(distance,0,float(schedule.length))
	var stage:Dictionary=schedule.stages[-1]
	var index:int=schedule.stages.size()-1
	for i:int in schedule.stages.size():
		if traveled<float(schedule.stages[i].start)+float(schedule.stages[i].length):stage=schedule.stages[i];index=i;break
	var part:float=clampf((traveled-float(stage.start))/maxf(.000001,float(stage.length)),0,1)
	var swing:float=clampf((part-.10)/.80,0,1)
	var blend:float=smoothstep(.20,.80,swing)
	var feet:Dictionary=stage.before.duplicate()
	var moving_foot:Vector3=Vector3(stage.before[stage.side]).lerp(stage.after[stage.side],blend)
	# Clear the highest riser before advancing over its nose. Ascent lifts early;
	# descent holds the raised foot until its heel has cleared the old tread.
	var lower:float=minf(stage.before[stage.side].y,stage.after[stage.side].y)
	var upper:float=maxf(stage.before[stage.side].y,stage.after[stage.side].y)
	if swing>0 and swing<1:
		var lift:float=smoothstep(0,.20,swing)*(1-smoothstep(.80,1,swing))
		moving_foot.y=lerpf(stage.before[stage.side].y,upper+.12,smoothstep(0,.20,swing))
		moving_foot.y=lerpf(moving_foot.y,stage.after[stage.side].y,smoothstep(.80,1,swing))
		moving_foot.y=maxf(moving_foot.y,lower+.12*lift)
	feet[stage.side]=moving_foot
	var transform:Transform3D=schedule.transform
	return {"root":transform*Vector3(stage.root_from).lerp(stage.root_to,part),"feet":{"L":transform*feet.L,"R":transform*feet.R},"planted":{"L":stage.side!="L" or swing<=0 or swing>=1,"R":stage.side!="R" or swing<=0 or swing>=1},"yaw":transform.basis.get_euler().y+(PI if int(schedule.direction)==-1 else 0),"phase":index+part,"distance":traveled,"length":schedule.length,"finished":traveled>=float(schedule.length)}
