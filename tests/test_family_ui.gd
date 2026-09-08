extends "res://tests/test_playthrough.gd"
## Public-control inspection of the new eight-person genealogy view.
const FAMILY_NAMES:Array[String]=["Alex Rowan","Blair Rowan","Cameron Vale","Drew Rowan","Ellis Rowan","Frankie Rowan","Gray Sage","Harper Rowan"]
const FAMILY_AGES:Array[String]=["Elder","Adult","Adult","Child","Child","Young adult","Young adult","Elder"]

func _run() -> void:
	screenshot_dir="res://art/family_ui"
	DirAccess.make_dir_recursive_absolute(screenshot_dir)
	app=load("res://scenes/main.tscn").instantiate();root.add_child(app);current_scene=app
	await frames(4);app.set_sound(false)
	await _enter_new_game()
	for i:int in range(FAMILY_NAMES.size()):
		if i>0:await press("+ Add Lifelet")
		var edit:LineEdit=app.find_children("*","LineEdit",true,false)[0]
		edit.text=FAMILY_NAMES[i];edit.text_changed.emit(edit.text)
		await _age(FAMILY_AGES[i])
	await _link(0,1,4)
	await _link(0,5,4)
	await _link(0,7,2)
	await _link(1,2,2)
	await _link(1,3,4)
	await _link(1,4,4)
	await _link(2,3,4)
	await _link(2,4,4)
	await press_member(FAMILY_NAMES[3]);await press("Connections")
	check(app.creator_connection(0)=="grandparent","Child sees the creator grandparent through the parent.")
	check(app.creator_connection(4)=="siblings","Shared parents establish sibling kinship.")
	check(app.creator_connection(5)=="parent_sibling","Parent's sibling appears as a derived connection.")
	await screenshot("01_creator_generations")
	await press("Back to creating")
	await press_member(FAMILY_NAMES[0]);await press("Find my home",true);await press("Start living",true)
	app.household.set_speed(0)
	for member:Dictionary in app.household.members:member.sim.autonomy=false
	await press("My Lifelet");await press("Family tree")
	check(app.household.members.size()==8,"Eight Lifelets enter the new family view.")
	check(app.sim.speed==0,"Opening family view preserves pause.")
	var diagram:Control=app.find_child("FamilyDiagram",true,false)
	check(is_instance_valid(diagram),"Family diagram is available through My Lifelet.")
	if is_instance_valid(diagram):
		for id:String in ["player","housemate_1","housemate_2","housemate_3","housemate_4","housemate_5","housemate_6","housemate_7"]:
			var card:Control=diagram.get_node_or_null("FamilyCard_"+id)
			check(is_instance_valid(card) and Rect2(Vector2.ZERO,diagram.size).encloses(Rect2(card.position,card.size)),"Family card is inside its scrollable diagram: "+id)
	await screenshot("02_eight_person_family")
	var focus_button:Button=app.find_child("FamilyFocus_housemate_3",true,false)
	check(is_instance_valid(focus_button),"Child focus control exists.")
	if is_instance_valid(focus_button):focus_button.pressed.emit()
	await frames(6)
	check(app.household.selected_id()=="player","Inspecting a relative leaves the controlled Lifelet unchanged.")
	var relation_texts:Array[String]=[]
	for label:Node in app.find_children("*","Label",true,false):
		if label.is_visible_in_tree():relation_texts.append(label.text)
	for expected:String in ["Grandparent","Parent","Sibling","Parent’s sibling","You are viewing"]:
		check(expected in relation_texts,"Child focus displays "+expected+".")
	await screenshot("03_child_family_focus")
	await press("Back to life")
	check(not app.overlay_open and app.sim.speed==0,"Closing family view restores the existing paused game.")
	await _public_save("The Rowan family — three generations")
	await screenshot("04_named_family_save")
	_write_report();app.queue_free();await frames(3)
	print("FAMILY_UI_RESULT assertions=%d failures=%d" % [assertions,failures.size()])
	quit(0 if failures.is_empty() else 1)

func _age(label:String) -> void:
	var selector:OptionButton=app.find_child("CreatorAge",true,false)
	for i:int in range(selector.item_count):
		if selector.get_item_text(i)==label:
			selector.select(i);selector.item_selected.emit(i);await frames(3);return
	check(false,"Age choice "+label+" exists.")

func _link(first:int,second:int,choice_index:int) -> void:
	await press_member(FAMILY_NAMES[first]);await press("Connections")
	var selector:OptionButton
	for candidate:Node in app.find_children("*","OptionButton",true,false):
		if candidate.is_visible_in_tree() and int(candidate.get_meta("connection_member",-1))==second:selector=candidate
	check(is_instance_valid(selector),"Connection selector exists for member "+str(second))
	if is_instance_valid(selector):selector.select(choice_index);selector.item_selected.emit(choice_index)
	await frames(3);await press("Back to creating")
