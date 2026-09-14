extends RefCounted
class_name LifeAdoptionFlow
## Phone presentation and physical arrival. The household owns all family/payment state.
const P=preload("res://scripts/palette.gd")
var app:Node
var request:Dictionary={}
var confirming:bool=false
var primary:String=""
var choice:int=0
var blocked:Dictionary={}
var calendar:LifeCalendarPanel

func _init(owner:Node) -> void:
	app=owner
	calendar=LifeCalendarPanel.new(owner)

func _panel(title:String,subtitle:String) -> void:
	app._begin_pause_overlay()
	app.menus.shade()
	app.card(Vector2(265,143),Vector2(910,616),P.WHITE,24,app.overlay)
	app.small_caps("Phone · Household services",Vector2(300,165),Vector2(780,26),app.overlay)
	app.text_label(title,Vector2(298,208),Vector2(805,57),38,P.INK,true,app.overlay)
	app.paragraph(subtitle,Vector2(302,276),Vector2(822,64),18,P.MUTED,app.overlay)

func context_error() -> String:
	if app.mode!="live" or app.current_venue!="home" or not app.pending_move.is_empty():return "Return to Live mode at home to arrange an adoption."
	return ""

func show_phone() -> void:
	request.clear();primary=app.household.selected_id()
	_panel("A little room to grow.","Household services for the people who make this place home.")
	var reason:String=context_error()
	if reason.is_empty():reason=app.household.adoption_availability([primary])
	var agenda:Button=app.button("Household calendar",Vector2(302,354),Vector2(820,52),calendar.open,true,app.overlay)
	agenda.name="PhoneCalendar";agenda.disabled=app.mode!="live"
	app.paragraph("See everyone's school, work and upcoming birthdays.",Vector2(307,412),Vector2(806,28),16,P.MUTED,app.overlay)
	var adopt:Button=app.button("Adopt a child",Vector2(302,446),Vector2(820,52),show_candidates,false,app.overlay)
	adopt.name="PhoneAdoptChild";adopt.disabled=not reason.is_empty();adopt.tooltip_text=reason
	app.paragraph("Welcome a school-age Lifelet into your family. Choose one or two adult guardians. Adoption costs §1,000.",Vector2(307,504),Vector2(806,40),16,P.INK,app.overlay)
	var pet_reason:String=app.household.pet_shop_availability()
	var pets:Button=app.button("Juniper Pet Shop",Vector2(302,552),Vector2(820,52),show_pets,false,app.overlay)
	pets.name="PhonePetShop";pets.disabled=not pet_reason.is_empty();pets.tooltip_text=pet_reason
	app.paragraph("Adopt a cat or a dog and shape its sex, coat and markings yourself. Bowls, cat trees and kennels are sold alongside.",Vector2(307,610),Vector2(806,52),16,P.INK,app.overlay)
	app.paragraph(reason if not reason.is_empty() else pet_reason,Vector2(307,668),Vector2(806,32),14,P.TEAL,app.overlay)
	app.button("Back to life",Vector2(302,706),Vector2(820,44),app.close_overlay,false,app.overlay)

func show_pets() -> void:
	app.pet_shop.show_shop()

func show_candidates() -> void:
	request.clear()
	_panel("Someone to welcome home.","Meet these children, then review your household and guardian choices. Nothing is charged until you confirm.")
	for index:int in range(LifeAdoption.CANDIDATE_COUNT):
		var candidate:Dictionary=LifeAdoption.candidate(int(app.household.adoptions.next_serial),index)
		var p:Vector2=Vector2(302+index*280,361)
		app.card(p,Vector2(261,275),P.PALE,15,app.overlay)
		app.model_thumbnail("character",p+Vector2(73,10),Vector2(115,119),true,app.overlay,candidate)
		app.text_label(str(candidate.name),p+Vector2(15,137),Vector2(232,35),23,P.INK,true,app.overlay)
		app.text_label("Child · "+", ".join(PackedStringArray(candidate.traits)),p+Vector2(15,178),Vector2(232,25),16,P.INK,false,app.overlay)
		var review:Button=app.button("Meet "+str(candidate.name).split(" ")[0],p+Vector2(15,219),Vector2(231,40),func():show_review(index),false,app.overlay)
		review.name="AdoptionCandidate_%d" % index
	app.button("Back to phone",Vector2(302,675),Vector2(820,47),show_phone,false,app.overlay)

func show_review(index:int,second:String="") -> void:
	choice=index
	var guardians:Array=[primary]
	if not second.is_empty():guardians.append(second)
	var prepared:Dictionary=app.household.prepare_adoption(guardians,index)
	request=prepared.get("request",{}).duplicate(true)
	var candidate:Dictionary=LifeAdoption.candidate(int(app.household.adoptions.next_serial),index)
	_panel("Welcome "+str(candidate.name)+"?","Please review this new chapter. Cancel keeps your family and funds exactly as they are.")
	app.model_thumbnail("character",Vector2(309,358),Vector2(173,188),true,app.overlay,candidate)
	app.text_label(str(candidate.name)+" · Child",Vector2(514,354),Vector2(591,39),25,P.INK,true,app.overlay)
	app.text_label("Guardian: "+str(app.household.member_sim(primary).character.name),Vector2(516,408),Vector2(582,29),18,P.INK,false,app.overlay)
	app.text_label("Second guardian (optional)",Vector2(516,453),Vector2(583,25),17,P.MUTED,false,app.overlay)
	var select:=OptionButton.new();select.name="AdoptionSecondGuardian";select.add_item("One guardian")
	select.set_item_metadata(0,"")
	for member:Dictionary in app.household.members:
		if str(member.id)==primary or str(member.sim.character.life_stage)!="adult" or member.sim.is_away():continue
		select.add_item(str(member.sim.character.name));select.set_item_metadata(select.item_count-1,str(member.id))
		if str(member.id)==second:select.select(select.item_count-1)
	app.rect(select,Vector2(516,486),Vector2(583,42),app.overlay)
	select.item_selected.connect(func(selected:int):show_review(index,str(select.get_item_metadata(selected))))
	app.paragraph("§1,000 once · %d of 8 household places\nClasses begin after a day to settle in. Your child will walk home from the street and can then be controlled like any Lifelet." % (app.household.members.size()+1),Vector2(307,553),Vector2(806,77),18,P.INK,app.overlay)
	var reason:String=str(prepared.get("error",context_error()))
	if not reason.is_empty():app.paragraph(reason,Vector2(307,626),Vector2(804,40),14,P.TEAL,app.overlay)
	app.button("Cancel adoption",Vector2(302,675),Vector2(392,47),show_candidates,false,app.overlay)
	var confirm:Button=app.button("Confirm adoption · §1,000",Vector2(710,675),Vector2(412,47),confirm_adoption,true,app.overlay)
	confirm.name="AdoptionConfirm";confirm.disabled=not reason.is_empty();confirm.tooltip_text=reason

func _clear_body(at:Vector3,person:String="") -> bool:
	if not app.meal_flow.standing_geometry_clear(at):return false
	for id:String in app.world.actors:
		if id==person:continue
		var actor:LifeActor=app.world.actors[id]
		if actor.visible and Vector2(actor.position.x-at.x,actor.position.z-at.z).length()<.85:return false
	for member:Dictionary in app.household.members:
		if str(member.id)==person:continue
		var action:Dictionary=member.sim.get_current_action()
		if not action.is_empty() and (str(action.phase)=="active" or str(action.id)=="arrive_home") and action.target_position.distance_to(at)<.85:return false
	return true

func _destination(index:int,from:Vector3,person:String="") -> Vector3:
	var preferred:Vector3=app.world.lot_return_position(index)
	for z:int in range(6):
		for x:int in range(9):
			var offset:int=(x+1)/2*(1 if x%2==1 else -1)
			var at:Vector3=preferred+Vector3(offset*.5,0,-z*.5)
			if not _clear_body(at,person):continue
			var path:PackedVector3Array=app.world.path_to(from,at)
			if not path.is_empty() and path[-1].distance_to(at)<.001:return at
	return Vector3.INF

func confirm_adoption() -> void:
	if confirming or request.is_empty() or not app.overlay_open or app.overlay.get_node_or_null("AdoptionConfirm")==null:return
	confirming=true
	var reason:String=context_error()
	var spawn:Vector3=app.world.lot_exit_position(app.household.members.size())
	var destination:Vector3=_destination(app.household.members.size(),spawn)
	if reason.is_empty() and (not _clear_body(spawn) or not destination.is_finite()):reason="The arrival path is blocked. Clear the front garden, then review again."
	var result:Dictionary={"ok":false,"error":reason}
	if reason.is_empty():result=app.household.commit_adoption(request,spawn,destination,app.world.serialize_items())
	if bool(result.ok) and not bool(result.get("duplicate",false)):
		var id:String=str(result.child)
		var child:LifeSim=app.household.member_sim(id)
		app.spawn_actor(id,child.character,spawn)
		app.household_profiles.append(child.character.duplicate(true))
		app.motion_states[id]=app._empty_motion()
		app.household.register_targets(app.world.simulation_targets())
		app._member_action_started(id,child.get_current_action())
		request.clear()
		app.close_overlay();app.draw_live()
		app.show_notice("Welcome to the family, %s. Select their household portrait to help them settle in." % str(child.character.name).split(" ")[0])
	elif bool(result.ok):request.clear();app.close_overlay()
	else:app.show_notice(str(result.error))
	confirming=false

func _blocked_arrival() -> void:
	var id:String=app.bound_member_id
	if not bool(blocked.get(id,false)):
		blocked[id]=true
		app.show_notice("The arrival route is blocked. Clear the front garden, or cancel the walk to choose another activity.")

func start_arrival(action:Dictionary) -> void:
	app._clear_motion();app.pending_action=action
	app._set_route(action.target_position)
	if not app.path.is_empty() and app.path[-1].distance_to(action.target_position)>.001:app.path.clear()
	if app.path.is_empty() and app.player.position.distance_to(action.target_position)>=.015:_blocked_arrival()
	else:blocked.erase(app.bound_member_id)
	app.refresh_hud()

func advance_arrival(delta:float,action:Dictionary) -> bool:
	if app.sim.speed<=0:return false
	var at:Vector3=action.target_position
	if not _clear_body(at,app.bound_member_id):
		var replacement:Vector3=_destination(app._member_index(app.bound_member_id),app.player.position,app.bound_member_id)
		if not replacement.is_finite():app.path.clear();_blocked_arrival();return false
		action.target_position=replacement;start_arrival(action);at=replacement
	if app.player.position.distance_to(at)<.015:
		blocked.erase(app.bound_member_id);app._clear_motion();app.sim.complete_adoption_arrival(action);return false
	if app.path.is_empty():
		start_arrival(action)
		if app.path.is_empty():return false
	var moved:bool=app._advance_path(delta)
	if app.player.position.distance_to(at)<.015:
		blocked.erase(app.bound_member_id);app._clear_motion();app.sim.complete_adoption_arrival(action)
	return moved
