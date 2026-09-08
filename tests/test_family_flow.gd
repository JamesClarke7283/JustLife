extends SceneTree
var app:Node
var checks:int=0
var failures:int=0
func _initialize() -> void:run.call_deferred()
func check(value:bool,message:String) -> void:
	checks+=1
	if not value:failures+=1;push_error(message)
func press(value:String) -> void:
	for b:Node in app.find_children("*","Button",true,false):
		if b.text==value and b.is_visible_in_tree() and not b.disabled:b.pressed.emit();return
	check(false,"Missing "+value)
func choose(other:int,role:int) -> void:
	for control:Node in app.find_children("*","OptionButton",true,false):
		if int(control.get_meta("connection_member",-1))==other and control.is_visible_in_tree():control.item_selected.emit(role);return
	check(false,"Missing connection selector")
func run() -> void:
	app=load("res://scenes/main.tscn").instantiate();root.add_child(app);app.set_process(false);app.set_sound(false)
	press("New game");press("+ Add Lifelet");press("+ Add Lifelet");press("+ Add Lifelet");await process_frame
	app.select_creator_member(0);press("Connections");await process_frame
	choose(1,1);await process_frame
	check(app.creator_connection(1)=="siblings","First sibling pair is explicit in creator.")
	app.close_overlay();app.select_creator_member(1);press("Connections");choose(2,1);await process_frame
	app.close_overlay();app.select_creator_member(0)
	check(app.creator_connection(2)=="siblings","The third sibling is visibly part of the same family.")
	press("Connections");choose(2,2);await process_frame
	check(app.creator_connection(2)=="siblings","Incompatible partner choice preserves declared siblings.")
	app.close_overlay();app.select_creator_member(2);press("Connections");choose(3,2);await process_frame
	check(app.creator_connection(3)=="partners","An unrelated adult can be an explicit starting partner.")
	app.close_overlay();app.select_creator_member(0);press("Connections");choose(3,2);await process_frame
	check(app.creator_connection(3)=="housemates","A second simultaneous partner is refused.")
	app.close_overlay();app.select_creator_member(1);press("Remove");await process_frame
	check(app.household_profiles.size()==3,"Removing a draft Lifelet keeps the other three.")
	app.select_creator_member(0)
	check(app.creator_connection(1)=="siblings","Removing a connecting sibling preserves remaining sibling kinship.")
	app.select_creator_member(1)
	check(app.creator_connection(2)=="partners","Partner links remap to the remaining canonical identities.")
	press("Find my home  →");press("Start living  →");await process_frame
	check(app.mode=="live" and app.household.members.size()==3,"The configured family moves into their home.")
	check(app.household.members[0].sim.relationships.housemate_1.family_role=="siblings","Sibling identity reaches live simulation.")
	check(app.household.members[1].sim.romantic_partner=="housemate_2" and app.household.members[2].sim.romantic_partner=="housemate_1","Starting partners are reciprocal.")
	check(not app.household.members[0].sim.get_action_availability("flirt","housemate_1").available,"Romantic sibling interactions are unavailable.")
	app.save_game();var id:String=app.active_save_id;app.load_game(id);await process_frame
	check(app.household.members[0].sim.relationships.housemate_1.family_role=="siblings","Sibling family survives named-save reload.")
	check(app.household.members[1].sim.romantic_partner=="housemate_2","Partner identity survives named-save reload.")
	LifeSaveLibrary.delete_slot(id)
	app.queue_free();await process_frame;await process_frame
	print("Family UI: %d assertions, %d failures." % [checks,failures]);quit(0 if failures==0 else 1)
