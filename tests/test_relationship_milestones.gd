extends SceneTree
var checks:int=0
var failures:int=0
class DeferredMarriageApp extends Node:
	var load_epoch:int=0
	var household:LifeHousehold
	var world:Dictionary={"actors":{}}
	var notices:Array[String]=[]
	func show_notice(message:String)->void:notices.append(message)
func _initialize()->void:call_deferred("run")
func check(ok:bool,message:String)->void:
	checks+=1
	print("CHECK ","PASS " if ok else "FAIL ",message)
	if not ok:failures+=1;push_error(message)
func home(name:String="Alex Rowan",gender:String="female",count:int=2)->LifeHousehold:
	var household:=LifeHousehold.new();root.add_child(household)
	var profiles:Array=[{"name":name,"gender":gender,"age_stage":"adult","traits":[]}]
	while profiles.size()<count:profiles.append({"name":"Casey Reed" if profiles.size()==1 else "Other Reed","gender":"female","age_stage":"adult","traits":[]})
	household.new_household(profiles)
	for member:Dictionary in household.members:
		member.sim.autonomy=false;member.sim.set_aging("normal",false)
	return household
func advance(household:LifeHousehold,minutes:float)->void:
	while minutes>0:
		var step:float=minf(30.0,minutes)
		household.tick(step/LifeSim.GAME_MINUTES_PER_SECOND)
		minutes-=step
func complete(household:LifeHousehold,source:String,id:String,target:String)->void:
	var sim:LifeSim=household.member_sim(source)
	check(sim.queue_action(id,target),id+" is queued")
	if sim.action_queue.is_empty():return
	household.begin_action(source)
	var remaining:float=float(sim.get_current_action().get("duration",0))-float(sim.get_current_action().get("elapsed",0))
	for member:Dictionary in household.members:
		for need:String in member.sim.needs:member.sim.needs[need]=85.0
	advance(household,remaining+.01)
func run()->void:
	var household:LifeHousehold=home()
	var a:LifeSim=household.member_sim("player");var b:LifeSim=household.member_sim("housemate_1")
	a.relationships.housemate_1.friendship=20.0;b.relationships.player.friendship=20.0
	complete(household,"player","flirt","housemate_1")
	check(int(a.relationships.housemate_1.get("successful_flirts",0))==0,"Unsuccessful completed flirt earns no progress")
	a.relationships.housemate_1.friendship=35.0;b.relationships.player.friendship=35.0
	check(a.queue_action("flirt","housemate_1"),"Flirt can be queued before cancellation")
	a.cancel_action()
	check(int(a.relationships.housemate_1.get("successful_flirts",0))==0,"Cancelled flirt earns no progress")
	for index:int in 3:
		complete(household,"player","flirt","housemate_1")
		check(int(a.relationships.housemate_1.successful_flirts)==index+1 and int(b.relationships.player.successful_flirts)==index+1,"Successful flirt is credited once to both partners")
		check(bool(a.get_action_availability("ask_partner","housemate_1").available)==(index==2),"Partnership unlocks on exactly the third successful flirt")
	complete(household,"player","ask_partner","housemate_1")
	check(a.romantic_partner=="housemate_1" and b.romantic_partner=="player","Partnership is reciprocal")
	check(not a.get_action_availability("commit","housemate_1").available,"Marriage is locked without two dates")
	check(a.queue_action("go_on_date","housemate_1"),"Date can be queued and cancelled")
	household.begin_action("player");household.tick(20.0/LifeSim.GAME_MINUTES_PER_SECOND);a.cancel_action()
	check(int(a.relationships.housemate_1.completed_dates)==0,"Partial cancelled date is not counted")
	complete(household,"player","go_on_date","housemate_1")
	check(int(a.relationships.housemate_1.completed_dates)==1 and int(b.relationships.player.completed_dates)==1,"One completed date counts once for the pair")
	check(not a.get_action_availability("commit","housemate_1").available,"One date does not unlock marriage")
	check(a.queue_action("go_on_date","housemate_1"),"Second date begins")
	household.begin_action("player");household.tick(25.0/LifeSim.GAME_MINUTES_PER_SECOND)
	var saved:Dictionary=household.json_safe(household.get_state())
	var loaded:=LifeHousehold.new();root.add_child(loaded)
	var restored:Dictionary=loaded.restore_state(saved)
	check(bool(restored.ok),"Partially completed date survives JSON household restore: "+str(restored.get("error","")))
	if bool(restored.ok):
		loaded.begin_action("player");advance(loaded,65.1)
		a=loaded.member_sim("player");b=loaded.member_sim("housemate_1")
		check(int(a.relationships.housemate_1.completed_dates)==2 and int(b.relationships.player.completed_dates)==2,"Restored second date completes once")
		check(bool(a.get_action_availability("commit","housemate_1").available),"Two dates unlock marriage")
		var married:Dictionary=LifeMarriage.complete(loaded,"player","housemate_1",Vector3(0,.16,0),0,[])
		check(bool(married.ok),"Same-household marriage validates atomically: "+str(married.get("error","")))
		check(str(b.character.name)=="Casey Rowan" and bool(a.relationships.housemate_1.married),"Incoming same-gender spouse takes the host surname")
		check(not a.get_action_availability("commit","housemate_1").available,"An accepted marriage cannot be repeated")
	loaded.queue_free();household.queue_free()
	for pair:Array in [["Jordan Vale","female","maya"],["Sam Birch","male","leo"]]:
		await resident_marriage(str(pair[0]),str(pair[1]),str(pair[2]))
	await two_resident_marriages()
	await legacy_departed_marriage()
	var full:LifeHousehold=home("Alex Rowan","male",8)
	seed_partner(full,"maya")
	var before:Dictionary=full.get_state()
	var refused:Dictionary=LifeMarriage.complete(full,"player","maya",Vector3(0,.16,0),0,[])
	check(not bool(refused.ok) and full.get_state()==before,"Full household refuses marriage without partial mutation")
	full.queue_free()
	await deferred_proposal()
	print("RELATIONSHIP_MILESTONES %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
func deferred_proposal()->void:
	var app:=DeferredMarriageApp.new();root.add_child(app)
	app.household=home()
	var flow:=LifeRelationshipFlow.new();app.add_child(flow);flow.app=app
	var proposal:Dictionary={"id":"commit","target_id":"maya","social_accepted":true}
	flow.finished("player",proposal)
	app.load_epoch+=1
	await process_frame
	check(app.notices.is_empty(),"Loading invalidates a proposal queued by the previous world")
	flow.finished("player",proposal)
	var previous:LifeHousehold=app.household
	app.household=home()
	previous.free()
	await process_frame
	check(app.notices.is_empty(),"Replacing the household invalidates its pending proposal")
	flow.finished("player",proposal)
	await process_frame
	check(app.notices.size()==1,"A proposal for the current household still reaches world validation")
	app.household.queue_free();app.queue_free()
func legacy_departed_marriage()->void:
	var source:LifeHousehold=home("Alex Rowan","female",3)
	var saved:Dictionary=source.get_state()
	saved.members.remove_at(1)
	saved.family_graph=LifeFamilyGraph.bury(saved.family_graph,"housemate_1")
	var loaded:=LifeHousehold.new();root.add_child(loaded)
	var restored:Dictionary=loaded.restore_state(saved)
	check(bool(restored.ok),"Legacy household with a departed member still loads")
	if bool(restored.ok):
		seed_partner(loaded,"maya")
		var married:Dictionary=LifeMarriage.complete(loaded,"player","maya",Vector3(0,.16,0),0,[])
		check(bool(married.ok),"Marriage works when living member identities contain a gap: "+str(married.get("error","")))
		if bool(married.ok):check(str(married.spouse_id)=="housemate_3" and loaded.member_sim("housemate_2")!=null and LifeFamilyGraph.departed_ids(loaded.family_graph).has("housemate_1"),"Incoming spouse preserves living and departed identities")
	source.queue_free();loaded.queue_free();await process_frame
func seed_partner(household:LifeHousehold,target:String)->void:
	var a:LifeSim=household.member_sim("player")
	a.relationships[target].merge({"friendship":70.0,"romance":70.0,"successful_flirts":3,"completed_dates":2,"bond":"partners","life_stage":"adult"},true)
	a.romantic_partner=target;household.adopt_selected_changes()
func resident_marriage(host_name:String,gender:String,target:String)->void:
	var household:LifeHousehold=home(host_name,gender,1)
	household.day=2;household.member_sim("player").day=2
	household.member_sim("player").career.schedule=LifeCareerSchedule.fresh(2)
	household.member_sim("player")._offer_daily_story()
	household.member_sim("player").story_events[0].context.neighbor=target
	seed_partner(household,target)
	household.member_sim("player")._record_autonomy_contact(target,"flirt")
	var result:Dictionary=LifeMarriage.complete(household,"player",target,Vector3(0,.16,0),0,[],{"hunger":43.0})
	check(bool(result.ok),"Resident marriage validates: "+str(result.get("error","")))
	if bool(result.ok):
		var spouse:LifeSim=household.member_sim(str(result.spouse_id))
		check(household.members.size()==2 and spouse!=null,"Spouse is a selectable real household LifeSim")
		check(str(spouse.character.name).ends_with(host_name.get_slice(" ",1)),"Resident spouse takes host surname regardless of gender")
		check(spouse.romantic_partner=="player" and household.member_sim("player").romantic_partner==str(result.spouse_id),"Resident identity becomes reciprocal household partnership")
		check(not spouse.relationships.has(target) and not household.member_sim("player").relationships.has(target),"Old resident relationship identity is removed")
		check(is_equal_approx(float(spouse.needs.hunger),43.0),"Visitor needs carry into playable spouse")
		var host:LifeSim=household.member_sim("player")
		var story:Dictionary=host.get_story_events()[0]
		var friendship:float=float(host.relationships[str(result.spouse_id)].friendship)
		check(host.choose_story_event(str(story.id),"walk_together") and float(host.relationships[str(result.spouse_id)].friendship)>friendship,"An existing neighbor story credits the moved-in spouse's new identity")
		spouse.day=3;spouse._offer_daily_story()
		var candidate:String=str(spouse.story_events[0].context.neighbor)
		check(spouse.relationships.has(str(spouse.resident_aliases.get(candidate,candidate))),"New spouse stories always select another real Lifelet")
		spouse.day=household.day
		spouse.story_events.clear();spouse._story_generated_day=household.day
		var saved:Dictionary=household.json_safe(household.get_state())
		var loaded:=LifeHousehold.new();root.add_child(loaded)
		var restored:Dictionary=loaded.restore_state(saved)
		check(bool(restored.ok),"Moved-in spouse survives JSON round trip: "+str(restored.get("error","")))
		if bool(restored.ok):check(loaded.resident_members.get(target)==result.spouse_id and not loaded.member_sim("player").relationships.has(target),"Reload keeps catalog identity retired")
		var invalid:Dictionary=saved.duplicate(true);invalid.members[0].state.resident_aliases={}
		check(not loaded.restore_state(invalid).ok,"Mismatched identity migration is rejected")
		invalid=saved.duplicate(true);invalid.members[0].state.relationships[str(result.spouse_id)].completed_dates=1
		check(not loaded.restore_state(invalid).ok,"Marriage with incomplete dating history is rejected")
		invalid=saved.duplicate(true);invalid.family_graph="invalid"
		check(not loaded.restore_state(invalid).ok,"Invalid family data is rejected before alias restoration")
		invalid=saved.duplicate(true);invalid.date_invitation={"host":"player","target":"priya","visit_serial":1}
		invalid.members[0].state.character.world_state={"residents":{"home_visit":[]}}
		check(not loaded.restore_state(invalid).ok,"Malformed home-date visit data is rejected without mutation")
		loaded.queue_free()
	household.queue_free();await process_frame

func two_resident_marriages()->void:
	var household:LifeHousehold=home()
	seed_partner(household,"maya")
	var first:Dictionary=LifeMarriage.complete(household,"player","maya",Vector3(0,.16,0),0,[])
	check(bool(first.ok),"First resident can join a household with another adult")
	var other:LifeSim=household.member_sim("housemate_1")
	other.relationships.leo.merge({"friendship":70.0,"romance":70.0,"successful_flirts":3,"completed_dates":2,"bond":"partners","life_stage":"adult"},true)
	other.romantic_partner="leo";household._sync_social_context()
	var second:Dictionary=LifeMarriage.complete(household,"housemate_1","leo",Vector3(1,.16,0),0,[])
	check(bool(second.ok),"A second resident can join after an earlier marriage: "+str(second.get("error","")))
	if bool(second.ok):
		check(household.members.size()==4 and household.resident_members.size()==2,"Each spouse keeps one unique playable identity")
		var family:Dictionary=household._commit_family(household._family_links_keeping_partners())
		check(bool(family.ok) and bool(household.member_sim("player").relationships[str(first.spouse_id)].married),"Family updates preserve an existing marriage and its progress")
		for member:Dictionary in household.members:
			check(not member.sim.relationships.has("maya") and not member.sim.relationships.has("leo"),"Every member retires both old neighbor identities")
		var restored:=LifeHousehold.new();root.add_child(restored)
		var outcome:Dictionary=restored.restore_state(household.json_safe(household.get_state()))
		check(bool(outcome.ok),"Two moved-in couples survive a save round trip: "+str(outcome.get("error","")))
		restored.queue_free()
	household.queue_free();await process_frame
