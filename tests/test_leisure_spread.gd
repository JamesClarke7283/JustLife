extends "res://tests/test_autonomy_policy.gd"
## Leisure spreads over the whole home: a furnishing nobody has touched for half
## a day draws a bored Lifelet ahead of the shelf everyone used an hour ago, a
## soak in the tub counts as a pastime, and five recent pastimes are remembered.

class FakeHousehold extends Node:
	var members:Array=[]
	func before_member_notification(_sim:Object=null)->void:pass
	func after_member_notification(_sim:Object=null)->void:pass
	func member_id(sim:Object)->String:
		for member:Dictionary in members:
			if member.sim==sim:return str(member.id)
		return ""

func lounge(stage:String="adult",clock:float=1000.0,date:int=6) -> LifeSim:
	var sim:LifeSim=setup(stage,clock,date)
	var all:Array=targets()
	all.append({"id":"easel","kind":"easel","position":Vector3(5,.16,5)})
	all.append({"id":"tv","kind":"tv","position":Vector3(6,.16,5)})
	all.append({"id":"piano","kind":"piano","position":Vector3(7,.16,5)})
	all.append({"id":"tub","kind":"bathtub","position":Vector3(8,.16,5)})
	sim.register_targets(all)
	return sim

func run() -> void:
	var home:FakeHousehold=FakeHousehold.new()
	var first:LifeSim=lounge();var second:LifeSim=lounge()
	first.character.traits=["Outgoing"];second.character.traits=["Outgoing"]
	for sim:LifeSim in [first,second]:sim.cooperation_owner=home
	home.members=[{"id":"a","sim":first},{"id":"b","sim":second}]
	first.needs.fun=30.0
	# Everybody used the easel, shelf and television within the last two hours; the piano never.
	var now:float=first._autonomy_now()
	for sim:LifeSim in [first,second]:
		sim._recent_target_use={"easel":now-30.0,"shelf":now-60.0,"tv":now-90.0}
	first._leisure_history.assign(["paint","read","watch"])
	var choice:Dictionary=first._autonomous_choice()
	check(str(choice.get("id",""))=="play_piano","A piano nobody has touched draws a bored Lifelet ahead of the shelf and television everyone used an hour ago (chose %s)." % str(choice.get("id","")))
	first._recent_target_use.clear();second._recent_target_use.clear();first._leisure_history.clear()
	check(str(first._autonomous_choice().get("id",""))=="paint","With nothing recent the free easel stays the first choice.")
	# A soak counts as leisure once hygiene is under 70 and the tub is free.
	first.needs.hygiene=60.0;first.needs.fun=30.0
	first._leisure_history.assign(["paint","read","watch"])
	for sim:LifeSim in [first,second]:sim._recent_target_use={"easel":now-30.0,"shelf":now-60.0,"tv":now-90.0,"piano":now-45.0,"mirror":now-40.0}
	choice=first._autonomous_choice()
	check(str(choice.get("id",""))=="bath","A free bathtub nobody has used is a pastime at hygiene 60 (chose %s)." % str(choice.get("id","")))
	first.needs.hygiene=90.0
	check(str(first._autonomous_choice().get("id",""))!="bath","At hygiene 90 the tub is not a pastime.")
	# Five pastimes are remembered and survive a save.
	first.needs.hygiene=60.0
	for id:String in ["paint","read","watch","play_piano","bath","dance"]:
		first.queue_action(id,{"paint":"easel","read":"shelf","watch":"tv","play_piano":"piano","bath":"tub","dance":"tv"}[id]);complete_front(first)
	check(first._leisure_history.size()==5 and first._leisure_history[0]=="dance" and not first._leisure_history.has("paint"),"The pastime history keeps the last five: "+str(first._leisure_history))
	var restored:LifeSim=lounge()
	check(bool(restored.restore_state(json_state(first)).ok) and restored._leisure_history==first._leisure_history,"Five saved pastimes restore exactly.")
	for sim:LifeSim in [first,second,restored]:sim.cooperation_owner=null
	home.free()
	for node:Node in owned:node.free()
	print("LEISURE_SPREAD %d checks, %d failures" % [checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
