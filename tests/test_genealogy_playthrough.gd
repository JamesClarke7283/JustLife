extends "res://tests/test_school_playthrough.gd"
## Independent eight-member creator genealogy, visible reciprocal tree, real
## child-to-adult birthdays, and named fresh-process persistence.
const FAMILY_NAMES: Array[String] = ["Ellis Reed", "Morgan Reed", "Casey Vale", "Robin Reed", "Avery Reed", "Jamie Reed", "Taylor Reed", "Parker Reed"]

func _run() -> void:
	screenshot_dir = "res://art/genealogy_playthrough"
	DirAccess.make_dir_recursive_absolute(screenshot_dir)
	app = load("res://scenes/main.tscn").instantiate()
	root.add_child(app);current_scene = app
	await frames(4);app.set_sound(false)
	app.household.notice.connect(func(message: String):notices.append(message))
	app.household.member_action_finished.connect(func(id: String,action: Dictionary):member_completed.append(id+":"+str(action.id)))
	if resume_only:await _restart_genealogy()
	else:
		await _create_genealogy()
		await _tree_flow("01")
		await _grown_child()
		await _save_genealogy()
	_write_report()
	app.queue_free();await frames(3)
	print("GENEALOGY_RESULT assertions=%d failures=%d resume=%s" % [assertions,failures.size(),str(resume_only)])
	quit(0 if failures.is_empty() else 1)

func _declare(selected_name: String,other_index: int,role_index: int) -> void:
	await press_member(selected_name);await press("Connections")
	await _connection(other_index,role_index)
	await press("Back to creating")

func _create_genealogy() -> void:
	await _enter_new_game()
	var names: Array[String] = [FAMILY_NAMES[0],"Remove This Draft",FAMILY_NAMES[1],FAMILY_NAMES[2],FAMILY_NAMES[3],FAMILY_NAMES[4],FAMILY_NAMES[5],FAMILY_NAMES[6]]
	var ages: Array[String] = _genealogy_ages()
	for i: int in range(8):
		if i>0:await press("+ Add Lifelet")
		_set_name(names[i]);await _choose_age(ages[i])
	await _declare(FAMILY_NAMES[1],0,3)
	await _declare(FAMILY_NAMES[1],3,2)
	for index: int in range(4,8):await _declare(FAMILY_NAMES[1],index,4)
	await _declare(FAMILY_NAMES[2],4,4)
	await press_member(FAMILY_NAMES[3]);await press("Connections")
	check(app.creator_connection(0)=="grandparent" and app.creator_connection(2)=="parent" and app.creator_connection(3)=="parent","Creator derives grandparent and both parent roles from directed declarations.")
	check(app.creator_connection(5)=="siblings","Shared parent creates sibling kinship without a separate sibling declaration.")
	var prior: Array = app.creator_family_links.duplicate(true)
	await _connection(2,2)
	check(equivalent(prior,app.creator_family_links),"Attempted child-parent partnership leaves the entire draft unchanged.")
	await screenshot("00_creator_invalid_kin_partner")
	await press("Back to creating")
	await press_member(FAMILY_NAMES[1]);await press("Connections")
	prior = app.creator_family_links.duplicate(true)
	await _connection(3,3)
	check(equivalent(prior,app.creator_family_links),"Same-stage parent declaration is rejected atomically, preserving existing partners.")
	await press("Back to creating")
	await press_member("Remove This Draft");await press("Remove")
	check(app.household_profiles.size()==7,"Removing an unrelated intermediate draft leaves seven Lifelets.")
	await press_member(FAMILY_NAMES[3]);await press("Connections")
	check(app.creator_connection(0)=="grandparent" and app.creator_connection(1)=="parent" and app.creator_connection(2)=="parent" and app.creator_connection(4)=="siblings","Removal remaps ancestry, coparent and derived sibling identities correctly.")
	await screenshot("00_creator_remapped_family")
	await press("Back to creating")
	await press("+ Add Lifelet");_set_name(FAMILY_NAMES[7]);await _choose_age("Child")
	await _declare(FAMILY_NAMES[7],1,3)
	await press_member(FAMILY_NAMES[3]);await press("Find my home",true)
	await press("Willow Cottage");await press("Start living",true);await press("Ⅱ")
	for member: Dictionary in app.household.members:member.sim.autonomy=false
	await press_member(FAMILY_NAMES[3])
	check(app.household.members.size()==8,"Eight related Lifelets move into the chosen home.")
	_check_lineage("move-in")

func _check_lineage(context: String) -> void:
	var h: Node = app.household
	for pair: Array in [["housemate_3","player","grandparent"],["player","housemate_3","grandchild"],["housemate_3","housemate_1","parent"],["housemate_1","housemate_3","child"],["housemate_3","housemate_2","parent"],["housemate_3","housemate_4","siblings"],["housemate_7","housemate_3","siblings"]]:
		check(h.family_relationship(pair[0],pair[1])==pair[2],context+": reciprocal/derived role "+str(pair))
	check(h.member_sim("housemate_1").romantic_partner=="housemate_2" and h.member_sim("housemate_2").romantic_partner=="housemate_1",context+": coparents retain reciprocal partnership.")
	for target: String in ["player","housemate_1","housemate_2","housemate_4"]:
		check(not h.member_sim("housemate_3").get_action_availability("flirt",target).available,context+": kin romance unavailable with "+target)

func _focus(id: String) -> void:
	var button: Button = app.find_child("FamilyFocus_"+id,true,false)
	var scroll: ScrollContainer = app.find_child("FamilyTreeScroll",true,false)
	check(is_instance_valid(button) and button.is_visible_in_tree(),"Family tree exposes clickable focus card "+id)
	if not is_instance_valid(button):return
	scroll.ensure_control_visible(button);await frames(4)
	check(scroll.get_global_rect().encloses(button.get_global_rect()),"Scrolled focus button is inside the actual visible tree viewport.")
	button.pressed.emit();await frames(6)
	var focused: Control = app.find_child("FamilyCard_"+id,true,false)
	var refreshed: ScrollContainer = app.find_child("FamilyTreeScroll",true,false)
	check(refreshed.get_global_rect().encloses(focused.get_global_rect()),"Newly focused family card remains fully visible after the tree rebuild.")

func _card_label(id: String,value: String) -> bool:
	var card: Control = app.find_child("FamilyCard_"+id,true,false)
	if not is_instance_valid(card):return false
	for label: Label in card.find_children("*","Label",true,false):
		if label.text==value:return true
	return false

func _tree_flow(prefix: String) -> void:
	await press("My Lifelet");await press("Family tree")
	check(app.sim.speed==0,"Family tree pauses the household.")
	var diagram: Control = app.find_child("FamilyDiagram",true,false)
	var scroll: ScrollContainer = app.find_child("FamilyTreeScroll",true,false)
	var cards: Array[Control] = []
	for node: Node in diagram.get_children():
		if str(node.name).begins_with("FamilyCard_"):cards.append(node)
	check(cards.size()==8,"Tree renders one card for every household Lifelet.")
	for i: int in range(cards.size()):
		check(Rect2(Vector2.ZERO,diagram.size).encloses(cards[i].get_rect()),"Card remains inside scrollable diagram: "+str(cards[i].name))
		for j: int in range(i):check(not cards[i].get_rect().intersects(cards[j].get_rect()),"Distinct family cards do not overlap.")
	check(diagram.size.x>scroll.size.x and scroll.get_h_scroll_bar().max_value>scroll.size.x,"Five children create a real horizontal scroll range instead of overflowing the modal.")
	check(_card_label("player","Grandparent") and _card_label("housemate_1","Parent") and _card_label("housemate_2","Parent") and _card_label("housemate_4","Sibling"),"Child-focused tree labels grandparent, both parents and derived sibling correctly.")
	await screenshot(prefix+"_child_focused_tree")
	await _focus("housemate_7")
	check(_card_label("housemate_7","You are viewing") and _card_label("housemate_3","Sibling"),"Last scrolled child card can become focus without changing kinship.")
	await screenshot(prefix+"_last_child_focus")
	await _focus("player")
	check(_card_label("housemate_1","Child") and _card_label("housemate_3","Grandchild"),"Grandparent-focused cards show reciprocal child and grandchild roles.")
	await screenshot(prefix+"_grandparent_focused_tree")
	await _focus("housemate_1")
	check(_card_label("player","Parent") and _card_label("housemate_3","Child") and _card_label("housemate_2","Partner"),"Parent-focused tree shows its parent, child and partner.")
	await screenshot(prefix+"_parent_focused_tree")
	await press("Back to life")
	check(app.household.selected_id()=="housemate_3","Tree focus changes do not silently switch the controlled Lifelet.")
	await press("People");await press("All relationships",true);await press("Family tree")
	check(_card_label("player","Grandparent"),"All relationships opens the selected child's family tree.")
	await press("Back to life")

func _grown_child() -> void:
	var start_funds: int = app.sim.funds
	var original_graph: Dictionary = app.household.family_graph.duplicate(true)
	for stage: String in ["teen","young_adult","adult"]:
		await press("My Lifelet");await press("Celebrate a birthday");await press("Celebrate · §30")
		await press("▶")
		await wait_until(func()->bool:return active_is("birthday",.15),"routed birthday toward "+stage,40)
		await wait_until(func()->bool:return app.sim.action_queue.is_empty(),"actual birthday completion into "+stage,25)
		await press("Ⅱ");await frames(8)
		check(app.sim.character.age_stage==stage and app.player.profile.age_stage==stage,"Completed birthday updates selected child to "+stage+" in simulation and rendering.")
		check(equivalent(app.household.family_graph,original_graph),"Birthday preserves the exact family graph at "+stage)
	_check_lineage("grown child")
	check(app.sim.funds==start_funds-90 and app.sim.lifecycle.history.size()==3,"Three real birthdays cost exactly90 and retain all adjacent-stage history.")
	check(app.household.member_sim("housemate_1").character.age_stage=="adult" and app.sim.character.age_stage=="adult","Existing parent and grown child can reach the same age stage without losing lineage.")
	await _open_social("housemate_1")
	_disabled_social("flirt","family")
	await screenshot("02_adult_child_parent_social_gate")
	app.close_overlay()
	await press("My Lifelet");await press("Family tree")
	check(_card_label("housemate_1","Parent") and _card_label("housemate_3","You are viewing"),"Adult child remains a child of the original parent in the visible tree.")
	await screenshot("02_grown_child_tree")
	await press("Back to life")

func _save_genealogy() -> void:
	var expected: Dictionary = {"state":app.sim.get_state(),"player":vec(app.player.position),"world":app.world.serialize_items(),"lot":app.selected_lot,"floor":app.floor_color,"selected_index":app.household.selected_index,"family_graph":app.household.family_graph.duplicate(true),"members":[]}
	for member: Dictionary in app.household.members:expected.members.append({"id":member.id,"state":member.sim.get_state(),"position":vec(app.world.actors[member.id].position)})
	await _public_save("Reed family — three generations and a grown child")
	var file := FileAccess.open("user://genealogy_expected.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(expected));file.close()
	await screenshot("03_named_family_save")

func _restart_genealogy() -> void:
	var expected: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("user://genealogy_expected.json"))
	await _public_load();await _compare_saved(expected,"genealogy restart")
	check(equivalent(app.household.family_graph,expected.family_graph),"Named fresh-process restart restores the exact canonical family graph.")
	_check_lineage("fresh process")
	check(app.sim.character.age_stage=="adult" and app.sim.lifecycle.history.size()==3,"Fresh load accepts and preserves the grown child's three birthdays.")
	for i: int in range(app.household.members.size()):
		check(equivalent(app.household.members[i].sim.lifecycle,expected.members[i].state.lifecycle),"Restart preserves each member's exact lifecycle history and progress.")
		check(equivalent(app.household.members[i].sim.education,expected.members[i].state.education),"Restart preserves the schooling records across age transitions.")
	await _tree_flow("04_restart")

func _genealogy_ages() -> Array[String]:
	return ["Elder","Adult","Adult","Adult","Child","Child","Child","Child"]
