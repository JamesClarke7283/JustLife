extends SceneTree
const Household = preload("res://scripts/household.gd")
const Graph = preload("res://scripts/family_graph.gd")
var checks: int = 0
var failures: int = 0
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1;push_error(message)
func profiles() -> Array:
	return [{"name":"Grandparent","age_stage":"elder"},{"name":"Parent","age_stage":"adult"},{"name":"Parent sibling","age_stage":"adult"},{"name":"Child","age_stage":"teen"},{"name":"Cousin","age_stage":"child"},{"name":"Other parent","age_stage":"young_adult"},{"name":"Unrelated","age_stage":"elder"},{"name":"Second child","age_stage":"child"}]
func family_links() -> Array:
	return [{"a":"player","b":"housemate_1","role":"parent"},{"a":"player","b":"housemate_2","role":"parent"},{"a":"housemate_1","b":"housemate_3","role":"parent"},{"a":"housemate_2","b":"housemate_4","role":"parent"},{"a":"housemate_5","b":"housemate_3","role":"parent"},{"a":"housemate_1","b":"housemate_7","role":"parent"}]
func roundtrip(data: Dictionary) -> Dictionary:
	var json: JSON = JSON.new();json.parse(JSON.stringify(data));return json.data
func run() -> void:
	var home: LifeHousehold = Household.new();root.add_child(home);home.new_household(profiles())
	var node: LifeSim = home.selected()
	check(home.configure_family(family_links()).ok,"A three-generation family and two explicit parents configure together.")
	check(home.selected()==node,"Family setup preserves existing simulation Nodes.")
	var expectations: Array = [["player","housemate_1","child"],["housemate_1","player","parent"],["player","housemate_3","grandchild"],["housemate_3","player","grandparent"],["housemate_1","housemate_2","siblings"],["housemate_3","housemate_7","siblings"],["housemate_3","housemate_2","parent_sibling"],["housemate_2","housemate_3","sibling_child"],["housemate_3","housemate_4","cousin"],["housemate_3","housemate_5","parent"],["housemate_1","housemate_5","none"],["player","housemate_6","none"]]
	for entry: Array in expectations:
		check(home.family_relationship(entry[0],entry[1])==entry[2],"Derived relation: "+str(entry))
		check(home.family_relationship(entry[1],entry[0])==Graph.inverse(entry[2]),"Every role has a correct directional inverse: "+str(entry))
		check(home.member_sim(entry[0]).relationships[entry[1]].family_role==entry[2],"Simulation relationship role matches graph: "+str(entry))
	check(home.family_parent_links().size()==6 and home.get_family_links().size()==6,"Editable declarations contain actual parent edges, not inferred cousins or grandparents.")
	check(home.funds==2500 and home.selected().social_history.is_empty(),"Genealogy setup grants no money or earned social history.")
	var loaded: LifeHousehold = Household.new();root.add_child(loaded)
	var state: Dictionary = home.get_state()
	var original: Dictionary = state.duplicate(true)
	check(loaded.restore_state(roundtrip(state)).ok,"Directed graph and all derived roles survive complete JSON restoration.")
	check(loaded.get_family_links()==home.get_family_links() and loaded.family_graph==home.family_graph,"Restored graph has the same minimal directed edges.")
	check(state==original,"Restoration does not mutate caller-owned data.")
	# Friendly actions mirror numbers, while parent/child labels remain directional.
	var child: LifeSim = home.member_sim("housemate_3")
	var parent: LifeSim = home.member_sim("housemate_1")
	for member: Dictionary in home.members:member.sim.autonomy=false
	check(child.queue_action("friendly","housemate_1"),"A child can have an ordinary friendly conversation with a parent.")
	home.begin_action("housemate_3")
	for i: int in range(12):home.tick(.5)
	check(child.action_queue.is_empty() and child.relationships.housemate_1.friendship==parent.relationships.housemate_3.friendship,"A completed family conversation mirrors friendship.")
	check(child.relationships.housemate_1.family_role=="parent" and parent.relationships.housemate_3.family_role=="child","Reciprocal social mirroring preserves parent/child direction.")
	check(child.relationships.housemate_1.status=="Parent" and parent.relationships.housemate_3.status=="Child","Family labels remain readable after social completion.")
	# Birthdays may reach or overtake the parent's current stage; genealogy is permanent.
	check(child.celebrate_birthday() and child.celebrate_birthday(),"A teen can celebrate into Adult while their parent remains Adult.")
	home.adopt_selected_changes()
	check(child.character.age_stage==parent.character.age_stage and home.family_relationship("housemate_3","housemate_1")=="parent","Existing family ties survive matching age stages.")
	check(loaded.restore_state(roundtrip(home.get_state())).ok,"A family with matching current parent/child age stages remains loadable.")
	for target: String in ["player","housemate_1","housemate_2","housemate_4","housemate_5","housemate_7"]:
		for id: String in ["flirt","ask_partner","commit","break_up"]:
			var before: Dictionary = child.relationships.duplicate(true)
			check(not child.get_action_availability(id,target).available and not child.queue_action(id,target) and child.relationships==before,"Family romance remains blocked without changing relationships: "+id+" / "+target)
	check(child.get_action_availability("flirt","housemate_6").available,"Unrelated adults retain romantic actions.")
	var stable: Dictionary = loaded.get_state()
	for mutation: String in ["cycle","three_parents","unknown","self","duplicate","one_sided","missing_graph","romance","milestone","romantic_queue","wrong_version","neighbor_family"]:
		var broken: Dictionary = stable.duplicate(true)
		match mutation:
			"cycle": broken.family_graph.parents.append({"a":"housemate_3","b":"player"})
			"three_parents": broken.family_graph.parents.append({"a":"housemate_6","b":"housemate_3"})
			"unknown": broken.family_graph.parents.append({"a":"missing","b":"housemate_3"})
			"self": broken.family_graph.parents.append({"a":"player","b":"player"})
			"duplicate": broken.family_graph.parents.append(broken.family_graph.parents[0].duplicate())
			"one_sided": broken.members[3].state.relationships.housemate_1.family_role="child"
			"missing_graph": broken.erase("family_graph")
			"romance": broken.members[3].state.relationships.housemate_1.romance=30.0
			"milestone": broken.members[3].state.relationships.housemate_1.milestones.append("spark")
			"romantic_queue": broken.members[3].state.action_queue=[{"id":"flirt","target_id":"housemate_1","duration":25.0,"elapsed":0.0,"target_position":[0,0,0]}]
			"wrong_version": broken.family_graph.version=true
			"neighbor_family": broken.members[0].state.relationships.maya.family_role="parent"
		var copy: Dictionary = broken.duplicate(true)
		check(not loaded.restore_state(broken).ok and loaded.get_state()==stable,"Invalid genealogy save fails atomically: "+mutation)
		check(broken==copy,"Invalid genealogy save does not mutate input: "+mutation)
	# Creation-time restrictions are distinct from persistence after birthdays.
	var creator: LifeHousehold = Household.new();root.add_child(creator);creator.new_household(profiles())
	var empty: Dictionary = creator.get_state()
	for links: Array in [[{"a":"housemate_1","b":"housemate_2","role":"parent"}],[{"a":"housemate_3","b":"housemate_4","role":"parent"}],[{"a":"housemate_4","b":"housemate_1","role":"parent"}],family_links()+[{"a":"housemate_6","b":"housemate_3","role":"parent"}],family_links()+[{"a":"housemate_3","b":"housemate_4","role":"partners"}],family_links()+[{"a":"housemate_3","b":"housemate_4","role":"housemates"}]]:
		check(not creator.configure_family(links).ok and creator.get_state()==empty,"Invalid age/kinship creator declarations fail atomically.")
	check(creator.configure_family([{"a":"housemate_5","b":"housemate_3","role":"parent"}]).ok,"An explicitly adult Young adult may parent a teen at setup.")
	_legacy_cases()
	_graph_cases()
	home.queue_free();loaded.queue_free();creator.queue_free();await process_frame
	print("GENEALOGY TESTS: %d checks, %d failures" % [checks,failures]);quit(1 if failures>0 else 0)
func _legacy_cases() -> void:
	var home: LifeHousehold=Household.new();root.add_child(home);home.new_household([{}, {}, {}])
	home.configure_family([{"a":"player","b":"housemate_1","role":"siblings"},{"a":"housemate_1","b":"housemate_2","role":"siblings"}])
	var legacy:Dictionary=home.get_state();legacy.erase("family_graph")
	var original:Dictionary=legacy.duplicate(true)
	check(home.restore_state(legacy).ok and home.family_graph.siblings.size()==2,"Legacy sibling families migrate to minimal spanning declarations.")
	check(legacy==original and home.family_relationship("player","housemate_2")=="siblings","Legacy migration preserves sibling closure without mutating input.")
	legacy.members[0].state.relationships.housemate_2.family_role="none"
	legacy.members[2].state.relationships.player.family_role="none"
	check(home.restore_state(legacy).ok and home.family_relationship("player","housemate_2")=="siblings","Sparse old sibling declarations derive the missing sibling relation.")
	legacy.members[0].state.relationships.housemate_2.romance=20.0
	check(not home.restore_state(legacy).ok,"Sparse legacy migration rejects romance implied to be between relatives.")
	home.queue_free()
func _graph_cases() -> void:
	var ids:Array=["a","b","c","d","e","f"]
	var graph:Dictionary={"version":1,"parents":[{"a":"a","b":"c"},{"a":"a","b":"d"},{"a":"b","b":"d"},{"a":"b","b":"e"}],"siblings":[]}
	check(Graph.validate(graph,ids).is_empty() and Graph.relationship(graph,"c","d")=="siblings" and Graph.relationship(graph,"d","e")=="siblings","A shared parent derives half-siblings.")
	check(Graph.relationship(graph,"c","e")=="none","A chain of half-siblings must not invent a shared parent for unrelated ends.")
	graph={"version":1,"parents":[{"a":"a","b":"b"},{"a":"b","b":"c"},{"a":"c","b":"d"}],"siblings":[]}
	check(Graph.relationship(graph,"d","a")=="ancestor" and Graph.relationship(graph,"a","d")=="descendant","Longer ancestral paths retain reciprocal nongendered roles.")
	graph.siblings=[{"a":"a","b":"d"}]
	check(not Graph.validate(graph,ids).is_empty(),"An ancestor cannot be declared a sibling of their descendant.")
