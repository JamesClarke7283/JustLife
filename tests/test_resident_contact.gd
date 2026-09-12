extends "res://tests/test_autonomy_policy.gd"
## Visiting residents start one contact per game day with a nearby household
## member: a cheerful chat off hours, or looking for company while their
## workday mood is drained. The decision is pure; the effects land on a real
## LifeSim.

var residents: LifeResidents

func _decider() -> LifeResidents:
	var controller: Node = Node.new()
	owned.append(controller)
	return LifeResidents.new(controller)

func run()->void:
	residents=_decider()
	var maya_position: Vector3 = Vector3(-2.5, .16, 2.75)
	# A resident who is not visiting never initiates.
	check(residents.resident_initiation("maya","walking",maya_position,{"player":Vector3(-2.0,.16,2.75)},true,600.0,1).is_empty(),
		"A walking resident does not start a contact.")
	check(residents.resident_initiation("maya","home",maya_position,{"player":Vector3(-2.0,.16,2.75)},true,600.0,1).is_empty(),
		"A resident at home does not start a contact.")
	# Distance gating: nobody within reach, no contact.
	check(residents.resident_initiation("maya","visiting",maya_position,{},true,600.0,1).is_empty(),
		"A visiting resident without nearby company does not start a contact.")
	check(residents.resident_initiation("maya","visiting",maya_position,{"player":Vector3(4.0,.16,2.75)},true,600.0,1).is_empty(),
		"A member further than the initiate radius is not approached.")
	# Workday drain: Maya's catalogue mood at work is 35, so she seeks company.
	var vent: Dictionary = residents.resident_initiation("maya","visiting",maya_position,{"player":Vector3(-2.0,.16,2.75)},true,600.0,1)
	check(not vent.is_empty() and str(vent.kind)=="vent","A drained visiting Maya starts a vent contact ('"+str(vent.get("kind",""))+"').")
	check(str(vent.get("member",""))=="player","The contact targets the nearest member.")
	check(float(vent.get("social",0.0))>0.0 and float(vent.get("friendship",0.0))>0.0,"The vent contact carries social and friendship gains.")
	# One contact per day: the second call is refused even with company close.
	check(residents.resident_initiation("maya","visiting",maya_position,{"player":Vector3(-2.0,.16,2.75)},true,600.0,1).is_empty(),
		"Maya does not start a second contact the same day.")
	# Off hours Maya is rested: a plain chat.
	residents._initiated.clear()
	var chat: Dictionary = residents.resident_initiation("maya","visiting",maya_position,{"player":Vector3(-2.0,.16,2.75)},true,1200.0,1)
	check(not chat.is_empty() and str(chat.kind)=="chat","A rested Maya starts a plain chat ('"+str(chat.get("kind",""))+"').")
	# Leo is Cheerful off hours: his chat carries the larger boost.
	var cheerful: Dictionary = residents.resident_initiation("leo","visiting",Vector3(2.5,.16,2.75),{"player":Vector3(2.0,.16,2.75)},false,720.0,2)
	check(not cheerful.is_empty() and str(cheerful.kind)=="cheerful_chat","Cheerful Leo starts a cheerful chat ('"+str(cheerful.get("kind",""))+"').")
	check(float(cheerful.get("social",0.0))>float(chat.get("social",0.0)),"The cheerful chat boosts social more than a plain chat.")
	# The next day the same resident can initiate again.
	check(not residents.resident_initiation("maya","visiting",maya_position,{"player":Vector3(-2.0,.16,2.75)},true,600.0,2).is_empty(),
		"A new game day reopens the resident's initiation.")
	# Applying a contact lands on a real household member.
	var home: LifeHousehold = home_setup(["adult"])
	var member: Dictionary = home.members[0]
	member.sim.relationships["maya"]={"name":"Maya","friendship":30.0,"romance":0.0,"status":"Friend"}
	var before_social: float = float(member.sim.needs.social)
	var before_friendship: float = float(member.sim.relationships["maya"].friendship)
	residents._initiated.clear()
	var applied: Dictionary = residents.resident_initiation("maya","visiting",maya_position,{str(member.id):Vector3(-2.0,.16,2.75)},true,600.0,1)
	check(not applied.is_empty() and str(applied.get("member",""))==str(member.id),"The visit targets the real member id.")
	member.sim.needs.social=40.0
	residents.apply_contact(applied,member.sim)
	var social_after: float = float(member.sim.needs.social)
	var friendship_after: float = float(member.sim.relationships["maya"].friendship)
	check(social_after>40.0 and social_after<=100.0,"Applying the contact raises social within the clamp (+%.1f)." % (social_after-40.0))
	check(friendship_after>before_friendship and friendship_after<=100.0,"Applying the contact raises friendship within the clamp (+%.1f)." % (friendship_after-before_friendship))
	# An unknown neighbour relationship is left untouched rather than created.
	var stranger: Dictionary = residents.resident_initiation("leo","visiting",Vector3(2.5,.16,2.75),{str(member.id):Vector3(2.0,.16,2.75)},false,720.0,3)
	check(not stranger.is_empty(),"Leo initiates on a later day.")
	member.sim.needs.social=40.0
	residents.apply_contact({"resident":"zed","social":10.0,"friendship":8.0},member.sim)
	check(not member.sim.relationships.has("zed"),"A contact with an unknown neighbour creates nothing.")
	routine_probe()
	print("RESIDENT_CONTACT %d checks, %d failures"%[checks,failures.size()])
	quit(0 if failures.is_empty() else 1)

func routine_probe()->void:
	# Pure window check: weekday hours inside the window are out; nights and
	# the weekend are home.
	var maya: Dictionary = LifeResidentCatalogue.PEOPLE["maya"]
	check(not LifeResidentCatalogue.routine_active(maya,true,600.0),"Maya keeps no off-lot routine.")
	var priya: Dictionary = LifeResidentCatalogue.PEOPLE["priya"]
	check(LifeResidentCatalogue.routine_active(priya,true,600.0),"Priya's library window is open on a weekday morning.")
	check(not LifeResidentCatalogue.routine_active(priya,true,480.0),"Priya's window is closed before ten.")
	check(not LifeResidentCatalogue.routine_active(priya,false,600.0),"Priya's routine does not run on the weekend.")
