extends Node
class_name LifeRelationshipFlow
## World-facing dates and marriage. The queue owns date time; the household
## transaction owns identities, so pause/load/cancel cannot grant extra dates.
var app:Node
var _topics:Dictionary={}

## Locks are inferred from current active actions, so cancellation, completion
## and loading release them without an independent saved ownership record.
func conversation(id:String)->Dictionary:
	for member:Dictionary in app.household.members:
		var host:String=str(member.id)
		var action:Dictionary=member.sim.get_current_action()
		if str(action.get("phase",""))!="active" or str(action.get("id","")) not in LifeSim.SOCIAL_ACTIONS or str(action.id)=="hug":continue
		var target:String=str(action.get("target_id",""))
		if id not in [host,target] or not _pair_present(host,target):continue
		return {"host":host,"target":target,"action":action}
	for visit:LifeHomeVisit in app.residents.visits():
		if not visit.active():continue
		var action:Dictionary=visit.activity.current_action()
		if str(action.get("phase",""))!="active" or str(action.get("id","")) not in ["friendly","joke"]:continue
		var host:String=visit.activity.person();var target:String=str(action.get("target_id",""))
		if id in [host,target] and _pair_present(host,target):return {"host":host,"target":target,"action":action}
	return {}

func _pair_present(first:String,second:String)->bool:
	var actor:LifeActor=app.world.actors.get(first);var other:LifeActor=app.world.actors.get(second)
	if not is_instance_valid(actor) or not is_instance_valid(other) or not actor.visible or not other.visible:return false
	if bool(actor.get_meta("away",false)) or bool(other.get_meta("away",false)):return false
	return actor.position.distance_to(other.position)<=1.8 and app.world.sight_line_clear(actor.position,other.position)

func holds(id:String)->bool:return not conversation(id).is_empty()
func listener_held(id:String)->bool:
	var pair:Dictionary=conversation(id)
	return not pair.is_empty() and str(pair.host)!=id

func blocks(action:Dictionary,id:String)->bool:
	if listener_held(id):return true
	if str(action.get("id","")) not in LifeSim.SOCIAL_ACTIONS:return false
	var target:String=str(action.get("target_id",""))
	var pair:Dictionary=conversation(target)
	return not pair.is_empty() and str(pair.host)!=id

func present_conversation(id:String)->bool:
	var pair:Dictionary=conversation(id)
	if pair.is_empty():return false
	var other_id:String=str(pair.target) if str(pair.host)==id else str(pair.host)
	var actor:LifeActor=app.world.actors[id];var other:LifeActor=app.world.actors[other_id]
	var toward:Vector3=other.position-actor.position
	var action_id:String=str(pair.action.id) if str(pair.host)==id else "friendly"
	actor.rotation.y=atan2(toward.x,toward.z)
	actor.set_activity_anchor(actor.position,actor.rotation.y,"standing",action_id,{"attention_target":other.to_global(other.get_portrait_center())})
	return true

func invite_date(target:String)->bool:
	var host:LifeSim=app.household.selected()
	var reason:String=host.get_action_availability(LifeRelationshipProgress.DATE,target).reason
	if not reason.is_empty():app.show_notice(reason);return false
	if not app.residents.home_visit.invite(target):return false
	app.household.date_invitation={"host":app.household.selected_id(),"target":target,"visit_serial":int(app.residents.home_visit.state.serial)}
	app.close_overlay();app.show_notice("Your partner is coming over for a date. Welcome them inside to begin.")
	return true

func guest_entered(target:String)->void:
	var invitation:Dictionary=app.household.date_invitation
	if invitation.is_empty() or str(invitation.target)!=target:return
	app.household.date_invitation={}
	start_date(str(invitation.host),target)

func start_date(host_id:String,target:String)->bool:
	var host:LifeSim=app.household.member_sim(host_id)
	if host==null:return false
	var reason:String=host.get_action_availability(LifeRelationshipProgress.DATE,target).reason
	var body:LifeActor=app.world.actors.get(target)
	if reason.is_empty() and (not is_instance_valid(body) or not body.visible):reason="Meet your partner here before starting the date."
	var partner:LifeSim=app.household.member_sim(target)
	if reason.is_empty() and partner!=null and not partner.action_queue.is_empty():reason="Let your partner finish their current activity before the date."
	if not reason.is_empty():app.show_notice(reason);return false
	var visit:LifeHomeVisit=app.residents.visit_for(target)
	if visit.owns(target):
		if str(visit.state.phase)!="inside":app.show_notice("Welcome your partner inside before starting the date.");return false
		if not visit.activity.interrupt_for_social():app.show_notice("Your partner will be ready to talk after reaching a safe place.");return false
	if not host.queue_action(LifeRelationshipProgress.DATE,target,body.position):return false
	app.close_overlay();app.show_notice("Your date begins when you are together. Stay for the whole date to complete it.")
	return true

func tick()->void:
	if app.mode!="live":return
	for member:Dictionary in app.household.members:member.sim.conversation_service=self
	var invitation:Dictionary=app.household.date_invitation
	if not invitation.is_empty():
		var visit=app.residents.home_visit
		if not visit.owns(str(invitation.target)) or int(visit.state.get("serial",-1))!=int(invitation.visit_serial):app.household.date_invitation={}
		elif str(visit.state.phase)=="inside":guest_entered(str(invitation.target))
	for member:Dictionary in app.household.members:
		var action:Dictionary=member.sim.get_current_action()
		if str(action.get("id",""))!=LifeRelationshipProgress.DATE:continue
		var target:String=str(action.target_id)
		var partner:LifeSim=app.household.member_sim(target)
		var reason:String=member.sim.get_action_availability(LifeRelationshipProgress.DATE,target).reason
		if partner!=null and (not partner.action_queue.is_empty() or bool(app.motion_states.get(target,{}).get("walk",false))):reason="Your partner started another activity. Plan another date when you are both free."
		if not reason.is_empty():member.sim.cancel_action();app.show_notice(reason);continue
		if str(action.get("phase",""))!="active" or app.household.speed<=0:continue
		var topic:int=int(float(action.elapsed)/18.0)
		if int(_topics.get(str(member.id),-1))==topic:continue
		_topics[str(member.id)]=topic
		var lines:Array[String]=["I'm glad we set aside time together.","What shall we do on our next adventure?","You always make me smile.","Tell me about your favourite memory.","I'd love another evening like this."]
		var body:LifeActor=app.world.actors.get(str(member.id))
		var other:LifeActor=app.world.actors.get(target)
		if is_instance_valid(body):body.speech(lines[topic%lines.size()])
		if is_instance_valid(other):other.speech("I love spending time with you.")

func companion(hosted_id:String)->bool:
	return not app.household.date_host_for(hosted_id).is_empty() and app.household.member_sim(hosted_id).action_queue.is_empty()

func present_companion(id:String)->bool:
	var host_id:String=app.household.date_host_for(id)
	if host_id.is_empty() or not companion(id):return false
	var host:LifeActor=app.world.actors.get(host_id);var actor:LifeActor=app.world.actors.get(id)
	if not is_instance_valid(host) or not is_instance_valid(actor):return false
	var toward:Vector3=host.position-actor.position
	actor.set_activity_anchor(actor.position,atan2(toward.x,toward.z),"standing","friendly",{})
	return true

func finished(id:String,action:Dictionary)->void:
	if not bool(action.get("social_accepted",false)):return
	if str(action.id)=="commit":_complete_marriage.call_deferred(id,str(action.target_id),app.load_epoch,app.household.get_instance_id())
	elif str(action.id)==LifeRelationshipProgress.DATE:
		_topics.erase(id)
		var count:int=int(app.household.member_sim(id).relationships[str(action.target_id)].get("completed_dates",0))
		app.show_notice("Date complete · %d of 2 dates before marriage." % count if count<2 else "Two dates complete. You can now ask your partner to marry and move in.")

func _complete_marriage(host_id:String,target_id:String,epoch:int,household_instance:int)->void:
	if not is_instance_valid(app) or app.load_epoch!=epoch:return
	if not is_instance_valid(app.household) or app.household.get_instance_id()!=household_instance:return
	var actor:LifeActor=app.world.actors.get(target_id)
	if not is_instance_valid(actor) or not actor.visible:app.show_notice("Your partner needs to be here to complete the proposal.");return
	var needs:Dictionary={}
	if app.residents.visit_for(target_id).owns(target_id):needs=app.residents.visit_for(target_id).activity.data.get("needs",{}).duplicate(true)
	var result:Dictionary=LifeMarriage.complete(app.household,host_id,target_id,actor.position,actor.rotation.y,app.world.serialize_items(),needs)
	if not bool(result.ok):app.show_notice(str(result.error));return
	var spouse_id:String=str(result.spouse_id)
	if bool(result.joined):
		app.residents.visit_for(target_id).detach_moved_in(target_id)
		for place:Dictionary in app.residents.locations.values():place.erase(target_id)
		app.residents.sidewalk_routes.erase(target_id)
		app.world.actors.erase(target_id);app.world.actors[spouse_id]=actor
		actor.name=spouse_id.capitalize();actor.set_meta("display_name",str(result.name))
		for body:StaticBody3D in actor.find_children("*","StaticBody3D",true,false):body.set_meta("item_id",spouse_id)
		app.motion_states[spouse_id]=app._empty_motion()
		var profile:Dictionary=app.household.member_sim(spouse_id).character.duplicate(true)
		profile.low_detail=true;actor.configure(profile)
	else:actor.set_meta("display_name",str(result.name))
	app.household.date_invitation={}
	app.household_profiles.clear()
	for member:Dictionary in app.household.members:app.household_profiles.append(member.sim.character.duplicate(true))
	app._refresh_sim_targets();app.refresh_hud();app.draw_live()
	var celebration=preload("res://scripts/wedding_celebration.gd").new()
	celebration.sound=app.sound_enabled;app.add_child(celebration)
	app.show_notice("Just married! %s is now part of your household." % str(result.name))
