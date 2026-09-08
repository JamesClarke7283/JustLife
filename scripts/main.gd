extends Node

const P = preload("res://scripts/palette.gd")
var household: LifeHousehold
var household_profiles: Array = []
var creator_index: int = 0
var motion_states: Dictionary = {}
var bound_member_id: String = "player"
var sim: LifeSim
var world: LifeWorld
var ui: Control
var overlay: Control
var stage: Node3D
var preview: LifeActor
var player: LifeActor
var mode: String = "creator"
var creator_tab: String = "Look"
var panel_tab: String = "Needs"
var catalog_category: String = "All"
var profile: Dictionary = {"name":"Mara Vale","frame":0,"hair":1,"skin_color":"d9a17d","hair_color":"54382a","top_color":"c97c66","bottom_color":"eadfc9","body_scale":1.0,"height_scale":1.0,"outfit":0,"eye_color":"547365","traits":["Creative","Outgoing","Foodie"],"aspiration":"Maker"}
var selected_lot: int = 0
var path: PackedVector3Array = []
var path_index: int = 0
var walk_only: bool = false
var pending_action: Dictionary = {}
var time_label: Label
var funds_label: Label
var age_label: Label
var mood_label: Label
var action_label: Label
var action_bar: ProgressBar
var need_bars: Dictionary = {}
var need_values: Dictionary = {}
var queue_box: HBoxContainer
var last_queue: String = ""
var notice_label: Label
var notice_card: Panel
var notice_time: float = 0
var hud_refresh: float = 0
var elapsed: float = 0
var creator_spin: float = -.16
var camera_drag: bool = false
var creator_drag: bool = false
var last_mouse: Vector2
var pause_before_menu: int = 1
var speed_before_build: int = 1
var overlay_pauses_sim: bool = false
var overlay_open: bool = false
var selected_item: Dictionary = {}
var build_undo: Array = []
var audio_player: AudioStreamPlayer
var ambience_player: AudioStreamPlayer
var sound_enabled: bool = true
var pending_move: Dictionary = {}
var loading_game: bool = false
var floor_color: String = "cfa97e"
var reconciling_targets: bool = false
var route_generation: int = 0
var walk_destination: Vector3 = Vector3.ZERO
var waiting_for_target: bool = false
var wait_started: float = -1.0
var wait_review: float = -1.0
var skill_labels: Dictionary = {}
var relationship_labels: Dictionary = {}
var career_labels: Dictionary = {}
var goal_labels: Dictionary = {}
var current_venue: String = "home"
var home_layout: Array = []
var venue_layouts: Dictionary = {}
var stories_button: Button
var speed_buttons: Dictionary = {}
var menus:LifeMenus
var has_active_game:bool=false
var active_save_id:String=""
var active_save_name:String=""
var menu_resume_speed:int=1
var menu_game_mode:String="live"
var save_preview:Image
var build_quote:Label
var build_quote_card:Panel
var release_probe:RefCounted
var creator_family_links:Array=[]

func _ready() -> void:
	DisplayServer.window_set_title("JustLife — make room for your story")
	world=LifeWorld.new()
	world.name="World"
	add_child(world)
	household_profiles=[profile]
	household=LifeHousehold.new()
	household.name="Household"
	add_child(household)
	household.new_household(household_profiles)
	sim=household.selected()
	household.notice.connect(show_notice)
	household.member_action_started.connect(_member_action_started)
	household.member_action_finished.connect(_member_action_finished)
	household.member_age_changed.connect(func(id: String, _previous: String, _current: String): _refresh_aged_member.call_deferred(id))
	world.object_clicked.connect(on_object_clicked)
	world.ground_clicked.connect(on_ground_clicked)
	world.placement_requested.connect(on_placement)
	world.construction_requested.connect(on_construction)
	var canvas=CanvasLayer.new()
	canvas.name="Interface"
	add_child(canvas)
	ui=Control.new()
	ui.name="UI"
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.mouse_filter=Control.MOUSE_FILTER_IGNORE
	ui.theme=P.theme()
	canvas.add_child(ui)
	overlay=Control.new()
	overlay.name="Overlay"
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter=Control.MOUSE_FILTER_IGNORE
	overlay.theme=ui.theme
	canvas.add_child(overlay)
	setup_audio()
	menus=LifeMenus.new(self)
	show_main_menu()
	if "--smoke-live" in OS.get_cmdline_user_args():start_household()
	if "--release-check" in OS.get_cmdline_user_args():
		release_probe=preload("res://scripts/release_probe.gd").new()
		release_probe.run.call_deferred(self)
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--capture="):capture_milestone.call_deferred(argument.get_slice("=",1))

func capture_milestone(which:String) -> void:
	if which=="creator":show_creator()
	if which in ["live","build"]:start_household();sim.set_speed(0)
	if which=="build":set_build_mode(true)
	if which=="lots":show_lot_selection()
	await get_tree().create_timer(2.0).timeout
	await RenderingServer.frame_post_draw
	var folder:String="user://captures" if not OS.has_feature("editor") else "res://art/screenshots"
	DirAccess.make_dir_recursive_absolute(folder)
	get_viewport().get_texture().get_image().save_png(folder.path_join(which+".png"))
	if is_instance_valid(player):print("JUSTLIFE_PACKED_AUDIO voice=",player._voice_streams.size()," ambience=",is_instance_valid(ambience_player.stream)," click=",is_instance_valid(audio_player.stream))
	print("JUSTLIFE_CAPTURE ",which)
	get_tree().quit()

func rect(n:Control,p:Vector2,s:Vector2,parent:Node=ui) -> Control:
	parent.add_child(n)
	n.position=p
	n.size=s
	return n

func text_label(value:String,p:Vector2,s:Vector2,font_size:int=16,color:Color=P.INK,serif:bool=false,parent:Node=ui) -> Label:
	var l=Label.new()
	l.text=value
	l.add_theme_font_size_override("font_size",font_size)
	l.add_theme_color_override("font_color",color)
	if serif:l.add_theme_font_override("font",load("res://assets/fonts/Display.otf"))
	l.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter=Control.MOUSE_FILTER_IGNORE
	rect(l,p,s,parent)
	return l

func paragraph(value:String,p:Vector2,s:Vector2,font_size:int=15,color:Color=P.MUTED,parent:Node=ui) -> Label:
	var l=text_label("",p,s,font_size,color,false,parent)
	l.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	l.vertical_alignment=VERTICAL_ALIGNMENT_TOP
	l.text=value
	# Wrapping lowers the Label minimum width; reapply the intended bounds afterward.
	l.size=s
	return l

func card(p:Vector2,s:Vector2,color:Color=P.WHITE,radius:int=18,parent:Node=ui) -> Panel:
	var n=Panel.new()
	n.add_theme_stylebox_override("panel",P.panel(color,radius))
	rect(n,p,s,parent)
	return n

func button(value:String,p:Vector2,s:Vector2,callback:Callable,primary:bool=false,parent:Node=ui) -> Button:
	var b=Button.new()
	b.text=value
	b.mouse_default_cursor_shape=Control.CURSOR_POINTING_HAND
	if primary:
		b.add_theme_stylebox_override("normal",P.panel(P.TEAL,10))
		b.add_theme_stylebox_override("hover",P.panel(Color("4c9381"),10))
		b.add_theme_color_override("font_color",P.WHITE)
		b.add_theme_color_override("font_hover_color",P.WHITE)
	b.pressed.connect(func():play_click();callback.call())
	rect(b,p,s,parent)
	if s.x<160 or s.y<40:
		compact_button(b)
		b.size=s
	return b

func line(p:Vector2,s:Vector2,parent:Node=ui) -> void:
	var n=ColorRect.new()
	n.color=P.LINE
	n.mouse_filter=Control.MOUSE_FILTER_IGNORE
	rect(n,p,s,parent)

func small_caps(value:String,p:Vector2,s:Vector2=Vector2(260,24),parent:Node=ui) -> Label:
	return text_label(value.to_upper(),p,s,11,P.MUTED,false,parent)

func clear_ui() -> void:
	for child in ui.get_children():
		ui.remove_child(child)
		child.queue_free()
	need_bars.clear();need_values.clear();speed_buttons.clear()
	skill_labels.clear();relationship_labels.clear();career_labels.clear();goal_labels.clear()
	queue_box=null;time_label=null;funds_label=null;mood_label=null;action_label=null;action_bar=null
	build_quote=null;build_quote_card=null
	last_queue=""
	close_overlay()

func logo(p:Vector2=Vector2(34,25)) -> void:
	var mark=TextureRect.new()
	mark.texture=load("res://assets/ui/justlife-icon.png")
	mark.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	mark.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	mark.mouse_filter=Control.MOUSE_FILTER_IGNORE
	rect(mark,p+Vector2(-2,-2),Vector2(43,43))
	text_label("JustLife",p+Vector2(51,-3),Vector2(181,44),33,P.INK,true)

func progress_steps(current:int) -> void:
	var names=["01  Create a Lifelet","02  Find a home","03  Live your story"]
	for i in range(3):
		var c=P.TEAL if i==current else P.MUTED
		text_label(names[i],Vector2(465+i*190,34),Vector2(185,28),14,c)
		if i==current:line(Vector2(466+i*190,73),Vector2(145,2))

func show_creator() -> void:
	close_overlay(false)
	cancel_placement()
	mode="creator"
	world.live_enabled=false
	world.set_build(false)
	_sync_actor_sound()
	if world.house:world.house.visible=false
	clear_ui()
	if stage:stage.queue_free()
	stage=Node3D.new()
	stage.name="CharacterStudio"
	world.add_child(stage)
	world.environment.background_color=Color("e8ede2")
	world.environment.ambient_light_energy=.35
	world.sun.light_energy=.65
	world.sun.rotation_degrees=Vector3(-38,-28,0)
	var studio_floor=world.box(stage,Vector3(0,-.085,0),Vector3(180,.10,180),"e8ede2")
	var studio_mat=StandardMaterial3D.new()
	studio_mat.albedo_color=Color("e8ede2")
	studio_mat.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	studio_floor.material_override=studio_mat
	world.cylinder(stage,Vector3(0,-.026,0),.8,.06,"dce4d6")
	world.cylinder(stage,Vector3(0,-.062,0),.9,.025,"cfdccd")
	world.camera.projection=Camera3D.PROJECTION_PERSPECTIVE
	world.camera.fov=32
	world.camera.position=Vector3(0,1.18,4.35)
	world.camera.look_at(Vector3(0,.96,0),Vector3.UP)
	preview=LifeActor.new()
	stage.add_child(preview)
	preview.configure(profile)
	preview.rotation.y=creator_spin
	frame_creator_camera()
	var fill=OmniLight3D.new()
	fill.position=Vector3(-2,2,2)
	fill.light_energy=.12
	fill.omni_range=8
	stage.add_child(fill)
	draw_creator()

func draw_creator() -> void:
	clear_ui()
	logo()
	progress_steps(0)
	button("Main menu",Vector2(1215,28),Vector2(193,40),show_main_menu)
	small_caps("A new beginning",Vector2(42,122))
	text_label("Who will you be?",Vector2(40,145),Vector2(350,60),39,P.INK,true)
	paragraph("A little personality. A style all your own.\nA whole life waiting to happen.",Vector2(42,211),Vector2(312,58),16)
	card(Vector2(38,293),Vector2(316,434),Color("f9faf3"))
	small_caps("Your name",Vector2(60,309))
	var edit=LineEdit.new()
	edit.text=profile.name
	edit.max_length=36
	edit.placeholder_text="First and last name"
	rect(edit,Vector2(58,342),Vector2(276,44))
	edit.text_changed.connect(func(value:String):profile.name=value)
	small_caps("Age",Vector2(60,394),Vector2(86,25))
	var ages: Array = creator_age_stages()
	var age_choice := OptionButton.new()
	age_choice.name="CreatorAge"
	for age: String in ages: age_choice.add_item(str(LifeLifecycle.LABELS[age]))
	age_choice.select(maxi(0,ages.find(LifeLifecycle.stage_for(profile))))
	rect(age_choice,Vector2(167,391),Vector2(167,35))
	age_choice.item_selected.connect(func(index: int):set_creator_age(str(ages[index])))
	small_caps("Personality  ·  choose three",Vector2(60,437))
	var trait_names=["Creative","Outgoing","Active","Bookworm","Foodie","Neat"]
	var descriptions={"Creative":"Build creative skill faster. Making art lifts your mood.","Outgoing":"Social connections come naturally; loneliness matters more.","Active":"Energy lasts longer and naps take less time.","Bookworm":"Reading and studying are especially rewarding.","Foodie":"Cooking is more enjoyable and builds skill faster.","Neat":"Hygiene lasts longer and showers lift your mood."}
	for i in range(trait_names.size()):
		var tr:String=trait_names[i]
		var b=button(tr,Vector2(58+(i%2)*142,468+(i/2)*37),Vector2(134,35),func():toggle_trait(tr),profile.traits.has(tr))
		b.tooltip_text=descriptions[tr]
	small_caps("Life aspiration",Vector2(60,593))
	var op=OptionButton.new()
	for a in ["Maker","Connected","Successful","Balanced"]:op.add_item(a)
	op.select(["Maker","Connected","Successful","Balanced"].find(profile.aspiration))
	rect(op,Vector2(58,624),Vector2(276,42))
	op.item_selected.connect(func(i:int):profile.aspiration=["Maker","Connected","Successful","Balanced"][i];draw_creator())
	var asp_desc={"Maker":"Fill your life with things you create.","Connected":"Turn new faces into lasting friendships.","Successful":"Build your skills. Make a living you love.","Balanced":"Find joy in the everyday."}
	paragraph(asp_desc[profile.aspiration],Vector2(60,676),Vector2(275,36),13)
	# The character is the focal point, with all styling choices on one side.
	card(Vector2(1080,126),Vector2(322,614),Color("f9faf3"))
	for i in range(3):
		var tab_name:String=["Look","Face","Wardrobe"][i]
		var tab_button=button(tab_name,Vector2(1100+i*97,144),Vector2(89,40),func():set_creator_tab(tab_name),creator_tab==tab_name)
		compact_button(tab_button);tab_button.size=Vector2(89,40)
	if creator_tab=="Look":
		small_caps("Body frame",Vector2(1102,202))
		button("Soft",Vector2(1100,232),Vector2(137,39),func():profile.frame=0;refresh_preview(),profile.frame==0)
		button("Broad",Vector2(1246,232),Vector2(137,39),func():profile.frame=1;refresh_preview(),profile.frame==1)
		small_caps("Skin tone",Vector2(1102,292))
		swatches(["f2d1b1","e7b98f","d9a17d","b77e58","925c40","613e30"],"skin_color",Vector2(1100,326),40,7)
		small_caps("Hairstyle",Vector2(1102,385))
		for i in range(3):
			var b=button(["Crop","Bob","Curls"][i],Vector2(1100+i*97,417),Vector2(89,52),func():profile.hair=i;refresh_preview(),profile.hair==i)
			b.tooltip_text=["A relaxed swept crop","A softly sculpted bob","Natural rounded curls"][i]
		small_caps("Hair color",Vector2(1102,490))
		swatches(["2a2420","54382a","89563a","c2a16b","dfccb0","784e49"],"hair_color",Vector2(1100,523),40,7)
		small_caps("Eyes",Vector2(1102,574))
		swatches(["547365","55738f","704b36","b18d54","77797c"],"eye_color",Vector2(1100,605),28,12)
		small_caps("Build",Vector2(1102,642))
		var slider=HSlider.new()
		slider.min_value=.85;slider.max_value=1.15;slider.step=.01;slider.value=profile.body_scale
		rect(slider,Vector2(1105,674),Vector2(270,30))
		slider.value_changed.connect(set_body_scale)
		text_label("Slender",Vector2(1102,704),Vector2(120,25),12,P.MUTED)
		var l=text_label("Fuller",Vector2(1290,704),Vector2(85,25),12,P.MUTED);l.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT
	elif creator_tab=="Face":
		text_label("A face of your own",Vector2(1100,207),Vector2(287,37),25,P.INK,true)
		paragraph("Small changes give each Lifelet a familiar face. Turn your Lifelet to see their profile.",Vector2(1102,264),Vector2(274,72),15)
		var features=["face_round","jaw_strong","nose_wide","eye_spacing"]
		var labels=["Cheek fullness","Jaw definition","Nose width","Eye spacing"]
		for i in range(4):
			var key:String=features[i]
			small_caps(labels[i],Vector2(1102,359+i*75))
			var slider=HSlider.new();slider.min_value=0;slider.max_value=1;slider.step=.01;slider.value=float(profile.get(key,0))
			slider.tooltip_text=labels[i]
			rect(slider,Vector2(1105,391+i*75),Vector2(271,24))
			slider.value_changed.connect(func(value:float):profile[key]=value;preview.set_face_feature(key,value))
		button("Reset face",Vector2(1102,681),Vector2(275,40),func():
			for key:String in features:profile[key]=0.0
			refresh_preview())
	else:
		small_caps("Everyday collection",Vector2(1102,204))
		text_label("Easy, everyday style",Vector2(1100,236),Vector2(290,36),24,P.INK,true)
		paragraph("Soft tailoring, natural textures, and colors that feel like you.",Vector2(1102,282),Vector2(269,55),15)
		small_caps("Outfit",Vector2(1102,345))
		for i in range(3):
			button(["Casual","Jacket","Cardigan"][i],Vector2(1100+i*97,376),Vector2(89,40),func():profile.outfit=i;refresh_preview(),int(profile.get("outfit",0))==i)
		small_caps("Top",Vector2(1102,438))
		swatches(["c97c66","417a71","efeadb","7195b3","bd9b68","3d4145"],"top_color",Vector2(1100,469),40,7)
		small_caps("Trousers",Vector2(1102,532))
		swatches(["eadfc9","3e5955","51697c","493e37","b88a72","292f32"],"bottom_color",Vector2(1100,564),40,7)
		paragraph("Choose a complete palette",Vector2(1102,626),Vector2(275,25),13)
		button("Coastal",Vector2(1100,665),Vector2(88,41),func():profile.top_color="efeadb";profile.bottom_color="51697c";refresh_preview())
		button("Earthy",Vector2(1197,665),Vector2(88,41),func():profile.top_color="c97c66";profile.bottom_color="eadfc9";refresh_preview())
		button("Sage",Vector2(1294,665),Vector2(88,41),func():profile.top_color="417a71";profile.bottom_color="493e37";refresh_preview())
	button("↶",Vector2(626,726),Vector2(48,42),func():creator_spin-=.5;preview.rotation.y=creator_spin)
	button("↷",Vector2(769,726),Vector2(48,42),func():creator_spin+=.5;preview.rotation.y=creator_spin)
	text_label("DRAG TO ROTATE",Vector2(657,782),Vector2(160,24),11,P.MUTED)
	small_caps("Household · %d / 8" % household_profiles.size(),Vector2(42,743),Vector2(162,24))
	var connections=button("Connections",Vector2(214,738),Vector2(133,31),show_creator_connections)
	connections.disabled=household_profiles.size()<2
	for i in range(household_profiles.size()):
		var label_text:String=member_initials(str(household_profiles[i].name),i,household_profiles)
		var chip=button(label_text,Vector2(42+i*39,776),Vector2(34,33),func():select_creator_member(i),i==creator_index)
		compact_button(chip)
		chip.size=Vector2(34,33)
		chip.tooltip_text=str(household_profiles[i].name)
	var add=button("+ Add Lifelet",Vector2(42,823),Vector2(147,41),add_creator_member)
	add.disabled=household_profiles.size()>=LifeHousehold.MAX_MEMBERS
	var remove=button("Remove",Vector2(201,823),Vector2(147,41),remove_creator_member)
	remove.disabled=household_profiles.size()<=1
	button("Surprise me",Vector2(867,815),Vector2(160,50),randomize_person)
	button("Find my home  →",Vector2(1080,802),Vector2(322,62),show_lot_selection,true)

func set_creator_tab(value:String) -> void:
	creator_tab=value
	frame_creator_camera()
	draw_creator()

func toggle_trait(tr:String) -> void:
	if profile.traits.has(tr):profile.traits.erase(tr)
	elif profile.traits.size()<3:profile.traits.append(tr)
	else:show_notice("Choose up to three traits. Deselect one to try another.")
	draw_creator()

func swatches(colors:Array,key:String,p:Vector2,diameter:float,gap:float) -> void:
	for i in range(colors.size()):
		var c:String=colors[i]
		var b=button("",p+Vector2(i*(diameter+gap),0),Vector2(diameter,diameter),func():profile[key]=c;refresh_preview())
		b.tooltip_text=c
		var s=P.panel(Color(c),int(diameter/2),P.TEAL if profile.get(key,"")==c else Color("ffffff"),3)
		b.add_theme_stylebox_override("normal",s)
		b.add_theme_stylebox_override("hover",P.panel(Color(c).lightened(.1),int(diameter/2),P.TEAL,3))
		if profile.get(key,"")==c:b.text="•";b.add_theme_color_override("font_color",Color.WHITE)

func refresh_preview() -> void:
	preview.scale=Vector3.ONE
	preview.configure(profile)
	frame_creator_camera()
	draw_creator()

func set_body_scale(value:float) -> void:
	profile.body_scale=clampf(value,.85,1.15)
	if is_instance_valid(preview):
		preview.scale=Vector3.ONE
		preview.visual.scale=Vector3(profile.body_scale,clampf(float(profile.height_scale),.93,1.08),profile.body_scale)

func randomize_person() -> void:
	profile.name=["Mara Vale","Alex Rowan","Ellis Park","Jules Rivera","Noa Ellis","Robin Ash"][randi()%6]
	profile.frame=randi()%2;profile.hair=randi()%3;profile.outfit=randi()%3
	for feature:String in ["face_round","jaw_strong","nose_wide","eye_spacing"]:profile[feature]=randf_range(0,.75)
	profile.skin_color=["f2d1b1","e7b98f","d9a17d","b77e58","925c40","613e30"][randi()%6]
	profile.hair_color=["2a2420","54382a","89563a","c2a16b","dfccb0"][randi()%5]
	profile.top_color=["c97c66","417a71","efeadb","7195b3"][randi()%4]
	profile.bottom_color=["eadfc9","3e5955","51697c","493e37"][randi()%4]
	refresh_preview()

func show_lot_selection() -> void:
	var guardian: bool = false
	for person: Dictionary in household_profiles:
		if LifeLifecycle.stage_for(person) in ["teen","young_adult","adult","elder"]: guardian = true
	if not guardian:
		show_notice("A child needs a teen or adult in the household."); return
	if str(profile.name).strip_edges().is_empty():profile.name="Mara Vale"
	mode="lots"
	clear_ui()
	if stage:stage.visible=false
	world.create_home(LifeCatalog.starter_layout(selected_lot))
	world.camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	world.camera.size=19.5
	world.camera_angle=.65
	world.camera_target=Vector3(0,0,0)
	world.update_camera()
	world.environment.background_color=Color("cddfd6")
	logo();progress_steps(1)
	card(Vector2(34,120),Vector2(330,580))
	small_caps("Welcome to",Vector2(57,140))
	text_label("Juniper Bay",Vector2(54,171),Vector2(300,58),39,P.INK,true)
	paragraph("Tree-lined streets. Friendly faces.\nA little space to make your own.",Vector2(58,242),Vector2(274,57),16)
	var names=["Willow Cottage","Sage House","A Fresh Canvas"]
	var desc=["A furnished start, with room to grow.","A creative home for your next chapter.","The essentials. You bring the ideas."]
	for i in range(3):
		var b=button(names[i],Vector2(54,331+i*95),Vector2(292,50),func():selected_lot=i;show_lot_selection(),selected_lot==i)
		b.alignment=HORIZONTAL_ALIGNMENT_LEFT
		text_label(desc[i],Vector2(61,382+i*95),Vector2(282,30),12,P.MUTED)
	text_label("1 BED  /  1 BATH  /  GARDEN",Vector2(57,640),Vector2(280,27),11,P.MUTED)
	card(Vector2(476,750),Vector2(920,118),Color("f9faf2"))
	small_caps("Move-in ready",Vector2(500,764))
	text_label(names[selected_lot],Vector2(498,795),Vector2(360,43),30,P.INK,true)
	text_label("Household funds after move-in\n§ %s" % ("4,500" if selected_lot==2 else "2,500"),Vector2(814,782),Vector2(310,58),14,P.MUTED)
	button("Start living  →",Vector2(1136,779),Vector2(234,62),start_household,true)
	button("←  Back to my Lifelet",Vector2(40,805),Vector2(280,50),show_creator)

func select_creator_member(index:int) -> void:
	if index<0 or index>=household_profiles.size():return
	creator_index=index
	profile=household_profiles[index]
	refresh_preview()

func add_creator_member() -> void:
	if household_profiles.size()>=LifeHousehold.MAX_MEMBERS:return
	var person:Dictionary=profile.duplicate(true)
	person.erase("world_state")
	person.name=["Ellis Rowan","Jules Park","Noa Rivera","Robin Ash","Avery Woods","Morgan Bell","Jamie Reed"][household_profiles.size()-1]
	person.frame=household_profiles.size()%2
	person.hair=household_profiles.size()%3
	person.top_color=["417a71","7195b3","bd9b68","efeadb"][household_profiles.size()%4]
	household_profiles.append(person)
	select_creator_member(household_profiles.size()-1)

func remove_creator_member() -> void:
	if household_profiles.size()<=1:return
	var retained:Array=[]
	# Preserve declared sibling connectivity when an intermediate sibling leaves
	# the draft, but never invent a parent or partner for a removed Lifelet.
	var effective:Array=creator_family_links.filter(func(link:Dictionary):return str(link.role)!="siblings")
	for i:int in range(household_profiles.size()):
		var group:Array=[creator_member_id(i)]
		for iteration:int in range(household_profiles.size()):
			for link:Dictionary in creator_family_links:
				if str(link.role)!="siblings":continue
				if str(link.a) in group and str(link.b) not in group:group.append(str(link.b))
				if str(link.b) in group and str(link.a) not in group:group.append(str(link.a))
		for j:int in range(i+1,household_profiles.size()):
			if creator_member_id(j) in group:effective.append({"a":creator_member_id(i),"b":creator_member_id(j),"role":"siblings"})
	for link:Dictionary in effective:
		var a:int=creator_member_index(str(link.a))
		var b:int=creator_member_index(str(link.b))
		if a==creator_index or b==creator_index:continue
		retained.append({"a":creator_member_id(a-1 if a>creator_index else a),"b":creator_member_id(b-1 if b>creator_index else b),"role":link.role})
	creator_family_links=_minimal_sibling_links(retained)
	household_profiles.remove_at(creator_index)
	select_creator_member(mini(creator_index,household_profiles.size()-1))

func start_household() -> void:
	has_active_game=true
	active_save_id="";active_save_name=""
	for person:Dictionary in household_profiles:person.erase("world_state")
	floor_color="cfa97e"
	current_venue="home"
	home_layout=LifeCatalog.starter_layout(selected_lot)
	venue_layouts.clear()
	loading_game=true
	household.new_household(household_profiles)
	var family_result:Dictionary=household.configure_family(creator_family_links)
	if not family_result.ok:
		loading_game=false;has_active_game=false;show_creator();show_notice(str(family_result.error));return
	sim=household.selected()
	bound_member_id=household.selected_id()
	if selected_lot==2:household.set_funds(4500)
	setup_live(LifeCatalog.starter_layout(selected_lot))
	loading_game=false
	show_notice("Welcome home, %s. Click a furnishing to choose what happens next." % str(sim.character.name).split(" ")[0])

func setup_live(layout:Array) -> void:
	close_overlay(false)
	pending_move.clear()
	route_generation+=1
	mode="live"
	if stage:stage.visible=false
	if current_venue=="home":world.create_home(layout)
	else:world.create_public_venue(current_venue,layout)
	world.live_enabled=true
	world.set_build(false)
	world.camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	world.camera.size=16.0
	world.camera_angle=.62
	world.camera_elevation=.82
	world.camera_target=Vector3(0,0,.25)
	world.update_camera()
	world.sun.rotation_degrees=Vector3(-52,-35,0)
	world.environment.background_color=Color("cddfd6")
	motion_states.clear()
	for i in range(household.members.size()):
		var member:Dictionary=household.members[i]
		spawn_actor(member.id,member.sim.character,Vector3(-.7+(i%2)*.65,.16,2.8+(i/2)*.48))
		motion_states[member.id]=_empty_motion()
	bound_member_id=household.selected_id()
	_bind_member(bound_member_id)
	player.set_selected(true)
	spawn_actor("maya",{"name":"Maya Chen","frame":0,"hair":2,"skin_color":"b77e58","hair_color":"2a2420","top_color":"417a71","bottom_color":"eadfc9"},Vector3(7.0,.16,3.2))
	spawn_actor("leo",{"name":"Leo Morgan","frame":1,"hair":0,"skin_color":"e7b98f","hair_color":"89563a","top_color":"7195b3","bottom_color":"493e37"},Vector3(-7,.16,4.5))
	path.clear();path_index=0;walk_only=false
	pending_action={}
	_restore_world_state(sim.character.get("world_state",{}))
	household.register_targets(world.simulation_targets())
	for member:Dictionary in household.members:
		var member_actor:LifeActor=world.actors[member.id]
		var saved:Variant=member.sim.character.get("world_state",{})
		if member.id!=household.selected_id() and saved is Dictionary:
			var at:Vector3=_saved_vector(saved.get("player"),member_actor.position)
			var cell:Vector2i=Vector2i(roundi(at.x*4),roundi(at.z*4))
			if not world.navigation.region.has_point(cell) or world.navigation.is_point_solid(cell):
				cell=world.nearest_free(at)
				at=Vector3(cell.x*.25,.16,cell.y*.25)
			member_actor.position=Vector3(at.x,.16,at.z)
			member_actor.rotation.y=_saved_number(saved.get("player_rotation"),0,-1000,1000)
	build_undo.clear()
	_sync_actor_sound()
	draw_live()
	for member:Dictionary in household.members:
		var current:Dictionary=member.sim.get_current_action()
		if not current.is_empty():_member_action_started(member.id,current)

func spawn_actor(id:String,person:Dictionary,p:Vector3) -> LifeActor:
	var actor=LifeActor.new()
	actor.name=id.capitalize()
	world.house.add_child(actor)
	var actor_profile=person.duplicate(true)
	actor_profile["low_detail"]=true
	actor.configure(actor_profile)
	actor.voice_enabled=sound_enabled and mode=="live" and sim.speed>0
	actor.position=p
	actor.set_meta("display_name",person.name)
	world.actors[id]=actor
	if true:
		var body=StaticBody3D.new()
		body.collision_layer=2
		body.set_meta("item_id",id)
		actor.add_child(body)
		var shape=CollisionShape3D.new()
		var capsule=CapsuleShape3D.new()
		capsule.height=1.8;capsule.radius=.35
		shape.shape=capsule;shape.position.y=.9
		body.add_child(shape)
	return actor

func draw_live() -> void:
	clear_ui()
	card(Vector2(22,18),Vector2(257,62),P.WHITE,14)
	logo(Vector2(36,29))
	button("Explore",Vector2(296,27),Vector2(95,43),show_neighborhood)
	stories_button=button("Stories",Vector2(400,27),Vector2(95,43),show_stories)
	stories_button.add_theme_font_size_override("font_size",13)
	if current_venue!="home":
		text_label(str(LifeNeighborhood.PLACES[current_venue].name),Vector2(306,86),Vector2(610,40),23,P.INK,true)
	card(Vector2(504,18),Vector2(432,57),P.WHITE,14)
	button("Live",Vector2(514,27),Vector2(116,39),func():set_build_mode(false),mode=="live")
	button("Build & buy",Vector2(638,27),Vector2(150,39),func():set_build_mode(true),mode=="build")
	button("My Lifelet",Vector2(796,27),Vector2(130,39),show_person)
	card(Vector2(1125,18),Vector2(293,62),P.WHITE,14)
	funds_label=text_label("§ 2,500",Vector2(1145,29),Vector2(170,38),25,P.TEAL)
	button("☰",Vector2(1357,27),Vector2(48,42),show_menu)
	# Camera affordances remain visible above the household controls.
	button("−",Vector2(1359,530),Vector2(46,42),func():world.camera.size=minf(world.camera.size+1.5,30))
	button("+",Vector2(1359,481),Vector2(46,42),func():world.camera.size=maxf(world.camera.size-1.5,7))
	button("↶",Vector2(1306,530),Vector2(46,42),func():world.camera_angle-=PI/4;world.update_camera())
	button("↷",Vector2(1306,481),Vector2(46,42),func():world.camera_angle+=PI/4;world.update_camera())
	button("Walls",Vector2(1306,585),Vector2(99,38),func():world.set_cutaway(not world.cutaway))
	if mode=="build":draw_build_catalog()
	else:
		draw_goal_card()
		draw_household_bar()
		draw_queue()
	refresh_hud()

func draw_goal_card() -> void:
	card(Vector2(24,104),Vector2(262,157),Color("f8faf2"),14)
	small_caps("A life in the making",Vector2(42,117),Vector2(225,22))
	goal_labels["title"]=text_label("",Vector2(40,149),Vector2(228,33),22,P.INK,true)
	goal_labels["description"]=paragraph("",Vector2(42,191),Vector2(220,42),13)
	goal_labels["reward"]=text_label("",Vector2(42,229),Vector2(219,22),11,P.TEAL)

func _refresh_progress_labels() -> void:
	if is_instance_valid(stories_button) and sim.has_method("get_story_events"):
		var count:int=sim.call("get_story_events").size()
		stories_button.text="Stories"+(" · %d" % count if count>0 else "")
	for skill_name:String in skill_labels:
		skill_labels[skill_name].text="Level %d" % int(sim.skills[skill_name].level)
	for id:String in relationship_labels:
		var relationship:Dictionary=sim.relationships[id]
		relationship_labels[id].text="%s · %d" % [relationship.status,int(relationship.friendship)]
	if is_instance_valid(age_label):
		age_label.text=str(LifeLifecycle.LABELS[str(sim.character.age_stage)])
		age_label.tooltip_text=LifeLifecycle.description(str(sim.character.age_stage),sim.lifecycle)
	if not career_labels.is_empty():
		if str(sim.character.age_stage) in ["child","teen"]:
			var school: Dictionary=LifeEducation.summary(sim.education)
			career_labels.title.text=str(school.school)
			career_labels.details.text="Grade %s · Homework %s" % [school.grade,"ready" if school.homework_ready else "needed"]
			career_labels.work.disabled=not sim.get_action_availability("school").available
			career_labels.work.tooltip_text=str(sim.get_action_availability("school").reason)
			career_labels.homework.disabled=not sim.get_action_availability("homework").available
		else:
			career_labels.title.text=sim.career.title
			career_labels.details.text="Level %d · §%d / shift" % [sim.career.level,sim.career.salary]
			career_labels.work.disabled=int(sim.career.worked_day)==sim.day
	if not goal_labels.is_empty():
		var current:Dictionary={}
		for want:Dictionary in sim.wants:
			if not bool(want.complete):current=want;break
		goal_labels.title.text="A lovely beginning" if current.is_empty() else str(current.label)
		goal_labels.description.text="You have made your first wishes happen. Keep making this life yours." if current.is_empty() else str(current.description)
		goal_labels.reward.text="" if current.is_empty() else "+%d satisfaction" % int(current.reward)

func draw_household_bar() -> void:
	if household.members.size()>1:
		small_caps("Household",Vector2(28,624),Vector2(280,20))
		for i in range(household.members.size()):
			var member:Dictionary=household.members[i]
			var chip=button(member_initials(str(member.sim.character.name),i,household_profiles),Vector2(28+i*35,657),Vector2(31,44),func():select_household_member(i),i==household.selected_index)
			compact_button(chip)
			chip.size=Vector2(31,44)
			chip.tooltip_text=str(member.sim.character.name)+" · Click to control"
	card(Vector2(20,718),Vector2(1400,162),P.WHITE,18)
	line(Vector2(304,738),Vector2(1,121))
	line(Vector2(964,738),Vector2(1,121))
	card(Vector2(36,739),Vector2(73,90),P.PALE,12)
	# A 3D portrait uses the same customized model as the live actor.
	model_thumbnail("character",Vector2(36,732),Vector2(73,105),true)
	var household_name=text_label(str(sim.character.name),Vector2(123,739),Vector2(174,31),22,P.INK,true)
	household_name.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
	household_name.size=Vector2(174,31)
	household_name.tooltip_text=str(sim.character.name)
	household_name.mouse_filter=Control.MOUSE_FILTER_PASS
	mood_label=text_label("Feeling inspired",Vector2(124,778),Vector2(165,26),14,P.TEAL)
	age_label=text_label(str(LifeLifecycle.LABELS[str(sim.character.age_stage)]),Vector2(124,810),Vector2(160,25),12,P.MUTED)
	age_label.mouse_filter=Control.MOUSE_FILTER_PASS
	button("Center",Vector2(42,841),Vector2(111,27),func():world.camera_target=player.position;world.update_camera())
	button("Wishes",Vector2(165,841),Vector2(111,27),show_wishes)
	text_label("TODAY IS YOURS",Vector2(327,738),Vector2(220,23),11,P.MUTED)
	action_label=text_label("Enjoying a moment",Vector2(326,770),Vector2(286,36),21,P.INK,true)
	action_label.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
	action_bar=ProgressBar.new()
	action_bar.show_percentage=false
	rect(action_bar,Vector2(328,818),Vector2(274,7))
	button("Cancel action",Vector2(326,842),Vector2(144,26),cancel_current_action)
	time_label=text_label(sim.get_clock_text(),Vector2(652,736),Vector2(280,33),18,P.INK)
	time_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	var speeds=[0,1,3,8]
	var names=["Ⅱ","▶","▶▶","▶▶▶"]
	for i in range(4):
		var b=button(names[i],Vector2(659+i*67,781),Vector2(59,43),func():set_game_speed(speeds[i]))
		b.toggle_mode=true
		b.tooltip_text=["Pause (Space)","Normal speed (1)","Fast speed (2)","Very fast speed (3)"][i]
		b.add_theme_stylebox_override("pressed",P.panel(P.TEAL,10))
		b.add_theme_color_override("font_pressed_color",P.WHITE)
		compact_button(b);b.size=Vector2(59,43)
		speed_buttons[speeds[i]]=b
	text_label("SPACE  PAUSE   ·   1 / 2 / 3  SPEED",Vector2(663,841),Vector2(269,25),11,P.MUTED)
	for i in range(4):
		var tab_name:String=["Needs","Skills","People","Career"][i]
		button("School" if tab_name=="Career" and str(sim.character.age_stage) in ["child","teen"] else tab_name,Vector2(984+i*103,732),Vector2(96,33),func():panel_tab=tab_name;draw_live(),panel_tab==tab_name)
	if panel_tab=="Needs":
		var nms=["hunger","energy","hygiene","bladder","fun","social"]
		for i in range(6):
			var key:String=nms[i]
			var p=Vector2(989+(i%2)*208,779+(i/2)*29)
			text_label(key.capitalize(),p,Vector2(69,22),12)
			var b=ProgressBar.new();b.show_percentage=false
			rect(b,p+Vector2(69,8),Vector2(105,7))
			need_bars[key]=b
			need_values[key]=text_label("80",p+Vector2(181,0),Vector2(24,22),10,P.MUTED)
	elif panel_tab=="Skills":
		for i in range(mini(6,sim.skills.size())):
			var key:String=sim.skills.keys()[i]
			var p=Vector2(989+(i%2)*208,781+(i/2)*28)
			text_label(key.capitalize(),p,Vector2(130,22),12)
			skill_labels[key]=text_label("Level %d" % sim.skills[key].level,p+Vector2(137,0),Vector2(62,22),12,P.TEAL)
	elif panel_tab=="People":
		var ids:Array=sim.relationship_order()
		for i in range(mini(2,ids.size())):
			var id:String=str(ids[i])
			var rel:Dictionary=sim.relationships[id]
			button(rel.name,Vector2(988+i*208,781),Vector2(192,35),func():focus_neighbor(id))
			relationship_labels[id]=text_label("%s · %d" % [rel.status,rel.friendship],Vector2(991+i*208,819),Vector2(194,22),12,P.MUTED)
		button("All relationships →",Vector2(988,848),Vector2(400,24),show_relationships)
	elif str(sim.character.age_stage) in ["child","teen"]:
		var school: Dictionary=LifeEducation.summary(sim.education)
		career_labels["title"]=text_label(str(school.school),Vector2(989,778),Vector2(235,28),19,P.INK,true)
		career_labels["details"]=text_label("",Vector2(990,814),Vector2(234,27),12,P.MUTED)
		career_labels["work"]=button("Online classes",Vector2(1241,779),Vector2(149,37),func():queue_nearest("desk","school"),true)
		career_labels["homework"]=button("Homework",Vector2(1241,824),Vector2(149,32),func():queue_nearest("desk","homework"))
		button("School record →",Vector2(989,848),Vector2(230,24),show_school_record)
	else:
		career_labels["title"]=text_label(sim.career.title,Vector2(989,778),Vector2(235,28),19,P.INK,true)
		career_labels["details"]=text_label("Level %d  ·  §%d / shift" % [sim.career.level,sim.career.salary],Vector2(990,814),Vector2(234,27),12,P.MUTED)
		career_labels["work"]=button("Work a shift",Vector2(1241,779),Vector2(149,37),func():queue_nearest("desk","job"),true)
		button("Find a job",Vector2(1241,824),Vector2(149,32),show_careers)

func draw_queue() -> void:
	var scroll=ScrollContainer.new()
	scroll.vertical_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_AUTO
	rect(scroll,Vector2(326,650),Vector2(830,61))
	queue_box=HBoxContainer.new()
	queue_box.add_theme_constant_override("separation",8)
	scroll.add_child(queue_box)
	queue_box.custom_minimum_size=Vector2(0,43)
	queue_box.mouse_filter=Control.MOUSE_FILTER_IGNORE

func refresh_hud() -> void:
	if household and bound_member_id!=household.selected_id():return
	if mode not in ["live","build"]:return
	for value in speed_buttons:speed_buttons[value].set_pressed_no_signal(int(value)==sim.speed)
	_refresh_progress_labels()
	if funds_label:funds_label.text="§ %s" % commas(sim.funds)
	if time_label:time_label.text=sim.get_clock_text()+ ("  ·  Paused" if sim.speed==0 else "")
	if mood_label:
		var mood=sim.get_mood()
		mood_label.text=mood.label
		mood_label.add_theme_color_override("font_color",mood.color)
		mood_label.tooltip_text=mood.description
	for key in need_bars:
		var value:float=sim.needs[key]
		need_bars[key].value=value
		var c=P.TEAL if value>45 else (P.GOLD if value>22 else P.CORAL)
		var bar_style=P.panel(c,5)
		bar_style.content_margin_top=0;bar_style.content_margin_bottom=0
		need_bars[key].add_theme_stylebox_override("fill",bar_style)
		need_values[key].text=str(int(value))
	var action=sim.get_current_action()
	if action_label:
		action_label.text="Enjoying a moment" if action.is_empty() else ((("Waiting for " if waiting_for_target else "Walking to ") if action.phase=="approach" else "")+str(action.label))
		if not str(action.get("cooperation_id","")).is_empty():
			var together:Dictionary=household.cooperative_presentation(bound_member_id)
			var partner:LifeSim=household.member_sim(str(together.get("partner_id","")))
			if partner and bool(together.get("ready",false)) and str(together.get("phase",""))!="active":
				action_label.text="Waiting for "+str(partner.character.name)
		action_label.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
	if action_bar:action_bar.value=0 if action.is_empty() else float(action.progress)*100
	if queue_box:
		var key:String=str(sim.action_queue.map(func(a:Dictionary):return a.id+":"+str(a.phase)))
		if key!=last_queue:
			last_queue=key
			for c in queue_box.get_children():
				queue_box.remove_child(c)
				c.queue_free()
			for i in range(sim.action_queue.size()):
				var a:Dictionary=sim.action_queue[i]
				var b=Button.new();b.custom_minimum_size=Vector2(155,43)
				queue_box.add_child(b)
				compact_button(b)
				var title=text_label(str(a.label),Vector2(10,6),Vector2(112,31),12,P.INK,false,b)
				title.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
				title.size=Vector2(112,31)
				text_label("×",Vector2(132,6),Vector2(17,31),17,P.MUTED,false,b)
				b.tooltip_text=str(a.label)+" · Click to cancel this activity"
				b.pressed.connect(func():cancel_current_action(i))

func commas(value:int) -> String:
	var s=str(value)
	var out=""
	for i in range(s.length()):
		if i>0 and (s.length()-i)%3==0:out+="," 
		out+=s[i]
	return out

func model_thumbnail(kind:String,p:Vector2,s:Vector2,portrait:bool=false,parent:Node=ui,appearance:Dictionary={}) -> void:
	var sv=SubViewport.new()
	sv.size=Vector2i(int(s.x*2),int(s.y*2))
	sv.own_world_3d=true
	sv.transparent_bg=true
	sv.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	sv.msaa_3d=Viewport.MSAA_2X
	parent.add_child(sv)
	var view=TextureRect.new()
	view.texture=sv.get_texture()
	view.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	view.mouse_filter=Control.MOUSE_FILTER_IGNORE
	rect(view,p,s,parent)
	var root=Node3D.new();sv.add_child(root)
	var model:Node3D
	if portrait:
		model=LifeActor.new();root.add_child(model);model.configure(sim.character if appearance.is_empty() else appearance)
	else:
		model=load("res://assets/models/%s.glb" % kind).instantiate();root.add_child(model)
	var cam=Camera3D.new();root.add_child(cam)
	cam.projection=Camera3D.PROJECTION_ORTHOGONAL
	if portrait:
		var center:Vector3=model.call("get_portrait_center") if model.has_method("get_portrait_center") else Vector3(0,1.52,0)
		var height:float=float(model.call("get_display_height")) if model.has_method("get_display_height") else 1.76
		var ratio:float=clampf(height/1.76,.8,1.1)
		cam.size=.71*ratio;cam.position=Vector3(.06,center.y+.02*ratio,3);cam.look_at(center-Vector3(0,.07*ratio,0))
	else:
		var data:Dictionary=LifeCatalog.get_item(kind)
		cam.size=maxf(maxf(data.size.x,data.size.y),data.height)*1.45
		cam.position=Vector3(3,2.3,4);cam.look_at(Vector3(0,data.height*.44,0))
	var light=DirectionalLight3D.new();root.add_child(light);light.rotation_degrees=Vector3(-38,-32,0);light.light_energy=.65
	var env=WorldEnvironment.new();var e=Environment.new();e.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;e.ambient_light_color=Color.WHITE;e.ambient_light_energy=.32;env.environment=e;root.add_child(env)
	freeze_viewport.call_deferred(sv.get_instance_id())

func freeze_viewport(viewport_id:int) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var viewport=instance_from_id(viewport_id)
	if is_instance_valid(viewport):viewport.render_target_update_mode=SubViewport.UPDATE_ONCE

func set_build_mode(value:bool) -> void:
	if value and current_venue!="home":show_notice("Travel home to change your own house.");return
	if mode not in ["live","build"] or value==(mode=="build"):return
	close_overlay()
	if value:
		speed_before_build=sim.speed
		mode="build"
		sim.set_speed(0)
	else:
		cancel_placement()
		build_undo.clear()
		mode="live"
		sim.set_speed(speed_before_build)
	world.set_build(value)
	_sync_actor_sound()
	_refresh_sim_targets()
	draw_live()
	if value:show_notice("Pick a furnishing, then click an open floor tile. R rotates; Esc cancels.")

func set_game_speed(value:int) -> void:
	if mode!="live" or overlay_pauses_sim:return
	sim.set_speed(value)
	_sync_actor_sound()
	refresh_hud()

func draw_build_catalog() -> void:
	build_quote_card=card(Vector2(503,570),Vector2(436,54),P.WHITE,12)
	build_quote_card.mouse_filter=Control.MOUSE_FILTER_IGNORE
	build_quote_card.visible=false
	build_quote=text_label("",Vector2(14,6),Vector2(408,41),16,P.INK,false,build_quote_card)
	build_quote.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	card(Vector2(20,643),Vector2(1400,239),P.WHITE,18)
	small_caps("Make yourself at home",Vector2(40,657))
	text_label("Build & buy",Vector2(38,687),Vector2(210,42),29,P.INK,true)
	for i in range(7):
		var category:String=["All","Comfort","Kitchen","Bathroom","Activities","Decor","Structure"][i]
		button(category,Vector2(296+i*132,663),Vector2(123,35),func():catalog_category=category;draw_live(),catalog_category==category)
	button("Undo",Vector2(1250,663),Vector2(144,35),undo_build)
	paragraph("Click to place\nR  rotate   ·   Esc  cancel",Vector2(41,754),Vector2(230,61),14)
	if catalog_category=="Structure":
		button("Wall",Vector2(305,725),Vector2(146,46),func():begin_construction("wall"))
		button("Room",Vector2(461,725),Vector2(146,46),func():begin_construction("room"))
		button("Door",Vector2(617,725),Vector2(146,46),func():begin_construction("door"))
		button("Remove wall",Vector2(773,725),Vector2(173,46),func():begin_construction("erase"))
		text_label("Wall / room: click two corners",Vector2(962,726),Vector2(409,43),13,P.MUTED)
		button("Warm oak",Vector2(305,784),Vector2(200,47),func():change_floor("cfa97e"))
		button("Pale stone",Vector2(520,784),Vector2(200,47),func():change_floor("dcd6c6"))
		button("Walnut",Vector2(735,784),Vector2(200,47),func():change_floor("896953"))
		button("Toggle wall view",Vector2(950,784),Vector2(200,47),func():world.set_cutaway(not world.cutaway))
		return
	var scroll=ScrollContainer.new()
	scroll.vertical_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	rect(scroll,Vector2(292,717),Vector2(1108,153))
	var row=HBoxContainer.new();row.add_theme_constant_override("separation",10);scroll.add_child(row)
	for kind in LifeCatalog.ITEMS:
		var data:Dictionary=LifeCatalog.ITEMS[kind]
		if catalog_category!="All" and data.category!=catalog_category:continue
		var cell=Control.new();cell.custom_minimum_size=Vector2(152,140);row.add_child(cell)
		var b=button("",Vector2.ZERO,Vector2(152,137),func():begin_purchase(kind),false,cell)
		b.tooltip_text=data.label+" · §"+str(data.price)
		model_thumbnail(kind,Vector2(8,2),Vector2(136,88),false,cell)
		var l=text_label(data.label,Vector2(9,91),Vector2(135,20),11,P.INK,false,cell);l.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
		text_label("§ %d" % data.price,Vector2(10,112),Vector2(130,20),13,P.TEAL,false,cell)

func change_floor(color:String) -> void:
	if color==floor_color:return
	if mode=="build":build_undo.append(_build_snapshot())
	_apply_floor_color(color)
	show_notice("A fresh finish for your home.")

func _apply_floor_color(color:String) -> void:
	floor_color=color
	if current_venue!="home" or not is_instance_valid(world.house):return
	for node in world.house.get_children():
		if node is MeshInstance3D and node.mesh is BoxMesh and node.mesh.size.x==12 and node.mesh.size.z==10:
			node.material_override=world.material(color)

func _build_snapshot(funds_delta:int=0) -> Dictionary:
	return {"layout":world.serialize_items(),"funds_delta":funds_delta,"floor":floor_color}

func begin_construction(tool:String) -> void:
	if mode!="build":return
	cancel_placement()
	world.begin_construction(tool)
	show_notice("Click two corners to create a %s. Esc cancels." % tool if tool in ["wall","room"] else "Click a wall to %s. Esc cancels." % ("add a doorway" if tool=="door" else "remove it"))

func on_construction(data:Dictionary) -> void:
	if mode!="build":return
	if data.has("error"):show_notice(str(data.error));return
	if not bool(data.get("valid",false)):return
	var cost:int=int(data.get("cost",0))
	if sim.funds<cost:show_notice("You need §%d for this construction." % cost);return
	build_undo.append(_build_snapshot(cost))
	_cancel_all_cooperative_actions()
	world.construction.commit(data)
	sim.funds-=cost
	_refresh_sim_targets()
	refresh_hud()
	show_notice("Your home is taking shape. %s§%d." % ["−" if cost>=0 else "+",absi(cost)])

func on_placement(kind:String,p:Vector3,angle:float) -> void:
	if mode!="build" or not LifeCatalog.ITEMS.has(kind):return
	if not world.can_place(kind,p,angle):
		show_notice("That space needs a little more room.");return
	var moving:bool=not pending_move.is_empty() and str(pending_move.entry.kind)==kind
	if not pending_move.is_empty() and not moving:cancel_placement()
	var price:int=0 if moving else int(LifeCatalog.ITEMS[kind].price)
	if sim.funds<price:show_notice("You need §%d for this furnishing." % price);return
	var snapshot:Dictionary=pending_move.snapshot if moving else _build_snapshot(price)
	var entry:Dictionary={"id":str(pending_move.entry.id) if moving else "placed_%d" % Time.get_ticks_usec(),"kind":kind,"x":p.x,"z":p.z,"rotation":angle}
	_cancel_all_cooperative_actions()
	world.add_item(entry)
	if _find_item(str(entry.id)).is_empty():return
	build_undo.append(snapshot)
	sim.funds-=price
	if moving:
		pending_move.clear()
		world.clear_placement()
	_refresh_sim_targets()
	refresh_hud()
	play_click()
	show_notice("%s moved into place." % LifeCatalog.ITEMS[kind].label if moving else "%s added to your home. −§%d" % [LifeCatalog.ITEMS[kind].label,price])

func undo_build() -> void:
	if mode!="build":return
	cancel_placement()
	if build_undo.is_empty():show_notice("There are no furnishing changes to undo yet.");return
	var data:Dictionary=build_undo.back()
	var funds_delta:int=int(data.get("funds_delta",0))
	if sim.funds+funds_delta<0:
		show_notice("You need §%d to restore that furnishing." % -funds_delta);return
	build_undo.pop_back()
	_cancel_all_cooperative_actions()
	world.clear_placement()
	for item in world.items:item.node.queue_free()
	world.items.clear()
	for entry:Dictionary in data.layout:
		if str(entry.get("kind",""))=="__construction":world.construction.restore(entry)
		else:world.add_item(entry,false)
	world.construction.refresh_decorations()
	world.rebuild_navigation()
	sim.funds+=funds_delta
	_apply_floor_color(str(data.get("floor",floor_color)))
	_refresh_sim_targets()
	refresh_hud()
	show_notice("Your last furnishing change was undone.")

func on_object_clicked(item:Dictionary,screen:Vector2) -> void:
	selected_item=item
	if mode=="build":
		if not LifeCatalog.ITEMS.has(str(item.kind)):
			show_notice("Lifelets can be visited in Live mode.");return
		show_build_object(item,screen);return
	if mode=="live":
		if household.member_sim(str(item.id)) and str(item.id)!=household.selected_id():
			show_housemate_interactions(item,screen)
		elif str(item.id)==household.selected_id():show_person()
		else:show_interactions(item,screen)

func close_overlay(restore_speed:bool=true) -> void:
	if is_instance_valid(overlay):
		for child in overlay.get_children():
			overlay.remove_child(child)
			child.queue_free()
	overlay_open=false
	if overlay_pauses_sim:
		overlay_pauses_sim=false
		if restore_speed and is_instance_valid(sim) and mode in ["live","build"]:
			sim.set_speed(0 if mode=="build" else pause_before_menu)
		_sync_actor_sound()

func _begin_pause_overlay() -> void:
	if not overlay_open and mode in ["live","build"]:capture_save_preview()
	var resume_speed:int=pause_before_menu if overlay_pauses_sim else sim.speed
	close_overlay(false)
	pause_before_menu=resume_speed
	overlay_open=true
	overlay_pauses_sim=true
	sim.set_speed(0)
	_sync_actor_sound()

func dismiss_layer() -> void:
	var bg=Button.new()
	bg.flat=true
	bg.add_theme_stylebox_override("normal",StyleBoxEmpty.new())
	bg.add_theme_stylebox_override("hover",StyleBoxEmpty.new())
	bg.add_theme_stylebox_override("pressed",StyleBoxEmpty.new())
	rect(bg,Vector2.ZERO,Vector2(1440,900),overlay)
	bg.pressed.connect(close_overlay)

func show_interactions(item:Dictionary,screen:Vector2) -> void:
	close_overlay();overlay_open=true;dismiss_layer()
	var actions:Array=sim.get_actions_for(str(item.kind),str(item.id))
	if str(item.kind) in ["desk","computer"] and str(sim.character.age_stage) in ["child","teen"]:
		var availability:Dictionary=sim.get_action_availability("homework",str(item.id))
		var reason:String=str(availability.reason)
		if not sim.action_queue.is_empty():reason="Finish or cancel this Lifelet’s current activity first."
		actions.insert(mini(2,actions.size()),{"id":"supported_homework","label":"Do homework together…","cost":0,"duration":45,"available":reason.is_empty(),"unavailable_reason":reason,"description":"Choose a trusted household adult to help. Learn together and strengthen your friendship."})
	var control_index:int=-1
	for i in range(household.members.size()):
		if household.members[i].id==str(item.id) and i!=household.selected_index:control_index=i
	var start_y:float=134 if control_index>=0 else 85
	var h:float=clampf(start_y+actions.size()*54+13,150,604)
	var pos=Vector2(clampf(screen.x-156,300,1064),clampf(screen.y-70,99,maxf(99,700-h)))
	card(pos,Vector2(340,h),P.WHITE,17,overlay)
	var title=text_label(str(item.label),pos+Vector2(19,14),Vector2(300,37),24,P.INK,true,overlay)
	title.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS;title.size=Vector2(300,37)
	if control_index>=0:
		button("Control this Lifelet",pos+Vector2(18,61),Vector2(304,39),func():select_household_member(control_index),true,overlay)
	small_caps("What would you like to do?",pos+Vector2(20,start_y-29),Vector2(299,21),overlay)
	var scroll=ScrollContainer.new();rect(scroll,pos+Vector2(14,start_y),Vector2(314,h-start_y-9),overlay)
	var column=VBoxContainer.new();column.add_theme_constant_override("separation",10);scroll.add_child(column)
	for a:Dictionary in actions:
		var label_text:String=a.label
		if int(a.cost)>0:label_text+="   §%d" % a.cost
		var b=Button.new();b.text=label_text;b.custom_minimum_size=Vector2(300,44)
		b.add_theme_font_size_override("font_size",13)
		b.tooltip_text=str(a.get("unavailable_reason","")) if not bool(a.available) else str(a.description)+"  ·  %d min" % a.duration
		b.disabled=not bool(a.available)
		b.pressed.connect(func():
			play_click()
			if str(a.id)=="supported_homework":show_homework_helpers(item)
			else:queue_interaction(item,a.id);close_overlay())
		column.add_child(b)
	if actions.is_empty():paragraph("A little detail that makes this place home.",pos+Vector2(18,80),Vector2(304,55),13,P.MUTED,overlay)

func show_homework_helpers(item:Dictionary) -> void:
	_begin_pause_overlay()
	var helpers:Array=household.homework_helpers(bound_member_id,str(item.id))
	var list_height:float=clampf(helpers.size()*87.0-10.0,77.0,320.0)
	var panel_height:float=340.0+list_height
	var top:float=(900.0-panel_height)*.5
	var shade=ColorRect.new();shade.color=Color(.08,.17,.15,.28);rect(shade,Vector2.ZERO,Vector2(1440,900),overlay)
	card(Vector2(338,top),Vector2(764,panel_height),P.WHITE,24,overlay)
	small_caps("A little help goes a long way",Vector2(373,top+22),Vector2(670,23),overlay)
	text_label("Learn something together.",Vector2(370,top+60),Vector2(686,57),36,P.INK,true,overlay)
	paragraph("Choose an adult to help "+str(sim.character.name)+" with this assignment. Both Lifelets meet at the desk, then spend 45 minutes learning together.",Vector2(374,top+132),Vector2(686,77),16,P.MUTED,overlay)
	var scroll=ScrollContainer.new();scroll.name="HomeworkHelpers";rect(scroll,Vector2(371,top+231),Vector2(692,list_height),overlay)
	var column=VBoxContainer.new();column.add_theme_constant_override("separation",10);scroll.add_child(column)
	for helper:Dictionary in helpers:
		var row=Control.new();row.custom_minimum_size=Vector2(670,77);column.add_child(row)
		card(Vector2.ZERO,Vector2(670,77),Color("f3f4ed"),12,row)
		var plan:Dictionary=_supported_homework_plan(item,str(helper.id))
		var reason:String=str(helper.reason) if not bool(helper.available) else str(plan.get("error",""))
		text_label(str(helper.name),Vector2(17,8),Vector2(425,27),20,P.INK,true,row)
		paragraph(reason if not reason.is_empty() else "Parenting level %d · More learning, a closer friendship" % int(helper.parenting_level),Vector2(17,39),Vector2(425,34),12,P.MUTED,row)
		var choose:Button=button("Learn together",Vector2(464,17),Vector2(189,43),_queue_supported_homework.bind(str(item.id),str(helper.id)),true,row)
		choose.name="HomeworkHelper_"+str(helper.id);choose.disabled=not reason.is_empty();choose.tooltip_text=reason
	if helpers.is_empty():paragraph("Add an adult Lifelet to your household to share homework time. Young adults and elders can help too.",Vector2(378,top+246),Vector2(669,75),17,P.MUTED,overlay)
	paragraph("The adult builds Parenting skill. The learner gains extra Logic, and both grow closer. Canceling ends the activity for both.",Vector2(374,top+list_height+243),Vector2(680,47),13,P.MUTED,overlay)
	button("Back to life",Vector2(820,top+list_height+292),Vector2(246,34),close_overlay,false,overlay)

func _supported_homework_plan(item:Dictionary,helper_id:String) -> Dictionary:
	if not world.actors.has(bound_member_id) or not world.actors.has(helper_id):return {"ok":false,"error":"Both Lifelets must be here to learn together."}
	if not _activity_available({"target_id":str(item.id)}):return {"ok":false,"error":"The desk or its chair is being used. Try again when it is free."}
	return world.supported_homework_plan(item,world.actors[bound_member_id].position,world.actors[helper_id].position)

func _queue_supported_homework(furniture_id:String,helper_id:String) -> void:
	var item:Dictionary=_find_item(furniture_id)
	if item.is_empty():show_notice("This desk is no longer here.");return
	var plan:Dictionary=_supported_homework_plan(item,helper_id)
	if not bool(plan.ok):show_notice(str(plan.error));return
	var result:Dictionary=household.queue_supported_homework(bound_member_id,helper_id,furniture_id,plan.learner_position,plan.helper_position)
	if not bool(result.ok):show_notice(str(result.error));return
	close_overlay();refresh_hud()
	show_notice("Meet at the desk. Your homework begins when you are both ready.")

func show_build_object(item:Dictionary,screen:Vector2) -> void:
	close_overlay();overlay_open=true;dismiss_layer()
	var p=Vector2(clampf(screen.x-140,300,1100),clampf(screen.y-70,99,440))
	card(p,Vector2(290,176),P.WHITE,17,overlay)
	text_label(item.label,p+Vector2(18,14),Vector2(261,38),22,P.INK,true,overlay)
	button("Sell  +§%d" % int(LifeCatalog.ITEMS[item.kind].price*.7),p+Vector2(16,71),Vector2(258,40),func():sell_item(item);close_overlay(),false,overlay)
	button("Move furnishing",p+Vector2(16,122),Vector2(258,40),func():move_item(item);close_overlay(),false,overlay)

func sell_item(item:Dictionary) -> void:
	if mode!="build":return
	cancel_placement()
	var existing:Dictionary=_find_item(str(item.get("id","")))
	if existing.is_empty():return
	var credit:int=int(LifeCatalog.ITEMS[existing.kind].price*.7)
	build_undo.append(_build_snapshot(-credit))
	_cancel_all_cooperative_actions()
	world.remove_item(existing.id)
	sim.funds+=credit
	_refresh_sim_targets()
	refresh_hud()

func move_item(item:Dictionary) -> void:
	if mode!="build":return
	cancel_placement()
	var snapshot:Dictionary=_build_snapshot()
	var original:Dictionary={}
	for entry:Dictionary in snapshot.layout:
		if str(entry.get("id",""))==str(item.get("id","")) and entry.has("id"):original=entry.duplicate(true)
	if original.is_empty():return
	_cancel_all_cooperative_actions()
	pending_move={"entry":original,"snapshot":snapshot}
	world.remove_item(str(original.id))
	world.begin_placement(str(original.kind))
	world.placement_angle=float(original.get("rotation",0))
	# Keep actions attached to this ID until the move is committed or canceled.
	_refresh_sim_targets(false)
	refresh_hud()
	show_notice("Place the furnishing in its new spot. Esc puts it back.")

func begin_purchase(kind:String) -> void:
	cancel_placement()
	world.begin_placement(kind)

func cancel_placement() -> void:
	if not is_instance_valid(world):return
	world.clear_placement()
	if not pending_move.is_empty():
		world.add_item(pending_move.entry)
		pending_move.clear()
		_refresh_sim_targets()

func _find_item(id:String) -> Dictionary:
	for item:Dictionary in world.items:
		if str(item.id)==id:return item
	return {}

func _refresh_sim_targets(replan:bool=true) -> void:
	if not is_instance_valid(household) or household.members.is_empty():return
	_store_motion()
	var prior:String=bound_member_id
	household.register_targets(world.simulation_targets())
	for member:Dictionary in household.members:
		_bind_member(member.id)
		_refresh_member_targets(replan)
		_store_motion()
	_bind_member(prior)

func _refresh_member_targets(replan:bool=true) -> void:
	if not is_instance_valid(sim) or not is_instance_valid(world.house):return
	var targets:Array=world.simulation_targets()
	var by_id:Dictionary={}
	for target:Dictionary in targets:by_id[str(target.id)]=target
	sim.register_targets(targets.filter(func(target:Dictionary):return str(target.id)!=bound_member_id))
	reconciling_targets=true
	for index:int in range(sim.action_queue.size()-1,-1,-1):
		var action:Dictionary=sim.action_queue[index]
		var target_id:String=str(action.target_id)
		if not pending_move.is_empty() and target_id==str(pending_move.entry.id):continue
		if not by_id.has(target_id):
			sim.cancel_action(index)
			continue
		var destination:Vector3=by_id[target_id].position
		if str(action.get("cooperation_role",""))=="helper":
			destination=action.target_position
			var desk:Dictionary=_find_item(target_id)
			if desk.is_empty() or not world._clear_coaching_space(destination) or destination.distance_to(desk.node.position)>2.2:
				household.cancel_cooperative_action(bound_member_id)
				continue
		if str(action.phase)=="active" and destination.distance_to(action.target_position)>.05:
			action.phase="approach"
		action.target_position=destination
	reconciling_targets=false
	if not replan or loading_game:return
	var current:Dictionary=sim.get_current_action()
	if current.is_empty():
		if walk_only:
			path=world.path_to(player.position,walk_destination)
			path_index=0
			if path.is_empty():walk_only=false
		else:_clear_motion()
	elif str(current.phase)=="approach":on_action_started(current)

func _clear_motion() -> void:
	waiting_for_target=false
	wait_started=-1.0
	wait_review=-1.0
	route_generation+=1
	path.clear()
	path_index=0
	walk_only=false
	pending_action={}

func cancel_current_action(index:int=0) -> void:
	# The next action's start signal is synchronous; clear the OLD route first.
	if index==0:_clear_motion()
	if index==0 and household.cancel_cooperative_action(bound_member_id):
		for member:Dictionary in household.members:
			if member.sim.get_current_action().is_empty():motion_states[member.id]=_empty_motion()
	else:sim.cancel_action(index)
	refresh_hud()

func _cancel_all_cooperative_actions() -> void:
	for member:Dictionary in household.members:household.cancel_cooperative_action(str(member.id))

func queue_interaction(item:Dictionary,id:String) -> void:
	if str(item.id)==bound_member_id:return
	var destination:Vector3=world.approach(item)
	if item.kind=="neighbor":destination=item.node.position+Vector3(0,0,.9)
	sim.queue_action(id,item.id,destination)
	refresh_hud()

func queue_nearest(kind:String,id:String) -> void:
	for item in world.items:
		if item.kind==kind:queue_interaction(item,id);return
	show_notice("Add a %s in Build & buy first." % kind)

func focus_neighbor(id:String) -> void:
	var actor:LifeActor=world.actors[id]
	world.camera_target=actor.position;world.update_camera()
	show_interactions({"id":id,"kind":"neighbor","label":actor.get_meta("display_name"),"node":actor,"size":Vector2(.6,.6)},Vector2(850,380))

func _empty_motion() -> Dictionary:
	return {"path":PackedVector3Array(),"index":0,"walk":false,"pending":{},"generation":0,"destination":Vector3.ZERO,"waiting":false,"wait_started":-1.0,"wait_review":-1.0}

func _store_motion() -> void:
	if bound_member_id.is_empty():return
	motion_states[bound_member_id]={"path":path,"index":path_index,"walk":walk_only,"pending":pending_action,"generation":route_generation,"destination":walk_destination,"waiting":waiting_for_target,"wait_started":wait_started,"wait_review":wait_review}

func _bind_member(id:String) -> void:
	var member:LifeSim=household.member_sim(id)
	if not member:return
	bound_member_id=id
	sim=member
	player=world.actors.get(id)
	var motion:Dictionary=motion_states.get(id,_empty_motion())
	path=motion.path;path_index=motion.index;walk_only=motion.walk;pending_action=motion.pending
	route_generation=motion.generation;walk_destination=motion.destination;waiting_for_target=motion.get("waiting",false)
	wait_started=float(motion.get("wait_started",-1.0))
	wait_review=float(motion.get("wait_review",-1.0))

func select_household_member(index:int) -> void:
	if index<0 or index>=household.members.size():return
	_store_motion()
	if is_instance_valid(player):player.set_selected(false)
	household.select(index)
	_bind_member(household.selected_id())
	player.set_selected(true)
	close_overlay()
	draw_live()

func _member_action_started(id:String,action:Dictionary) -> void:
	if loading_game or reconciling_targets:return
	var prior:String=bound_member_id
	_store_motion()
	_bind_member(id)
	on_action_started(action)
	_store_motion()
	_bind_member(prior)

func _member_action_finished(id:String,action:Dictionary) -> void:
	if loading_game:return
	var prior:String=bound_member_id
	_store_motion()
	_bind_member(id)
	on_action_finished(action)
	_store_motion()
	_bind_member(prior)

func show_housemate_interactions(item:Dictionary,screen:Vector2) -> void:
	show_interactions(item,screen)

func on_ground_clicked(p:Vector3) -> void:
	if mode!="live":return
	close_overlay()
	if not sim.action_queue.is_empty():
		show_notice("Cancel the current activity before walking somewhere else.");return
	walk_destination=p
	path=world.path_to(player.position,p)
	path_index=0
	walk_only=not path.is_empty()
	if path.is_empty():show_notice("That spot is out of reach.")

func on_action_started(action:Dictionary) -> void:
	if loading_game or reconciling_targets or not is_instance_valid(player):return
	_clear_motion()
	player.clear_speech()
	if str(action.id) in LifeSim.SOCIAL_ACTIONS and world.actors.get(str(action.target_id)) is LifeActor:
		world.actors[str(action.target_id)].clear_speech()
	_resolve_activity_target(action)
	pending_action=action
	if not pending_move.is_empty() and str(action.target_id)==str(pending_move.entry.id):return
	path=world.path_to(player.position,action.target_position)
	if path.is_empty():
		show_notice("The way is blocked. Try moving a furnishing.")
		_cancel_blocked_action.call_deferred(route_generation,action,bound_member_id)
	refresh_hud()

func _cancel_blocked_action(generation:int,action:Dictionary,member_id:String="") -> void:
	if loading_game:return
	if member_id.is_empty():member_id=bound_member_id
	var prior:String=bound_member_id
	_store_motion()
	_bind_member(member_id)
	if generation==route_generation and sim.get_current_action()==action:cancel_current_action()
	_store_motion()
	_bind_member(prior)

func on_action_finished(action:Dictionary) -> void:
	if is_instance_valid(player):
		player.speech({"cook":"Delicious!","read":"One more chapter…","paint":"Made something lovely.","friendly":"Good to talk with you!","joke":"Ha!","deep_talk":"I understand.","water":"Looking greener.","work":"All done!"}.get(action.id,"That feels better."))
	refresh_hud()

func show_notice(message:String) -> void:
	if not is_instance_valid(ui):return
	if is_instance_valid(notice_card):notice_card.queue_free()
	var position:Vector2=Vector2(1038,98) if mode in ["live","build"] else Vector2(460,98)
	var dimensions:Vector2=Vector2(374,94) if mode in ["live","build"] else Vector2(560,66)
	notice_card=card(position,dimensions,P.INK,13)
	notice_card.mouse_filter=Control.MOUSE_FILTER_IGNORE
	notice_label=paragraph(message,Vector2(16,13),dimensions-Vector2(32,22),13 if mode in ["live","build"] else 14,P.WHITE,notice_card)
	notice_time=5.5

func show_menu() -> void:
	_begin_pause_overlay()
	var bg=ColorRect.new();bg.color=Color(.08,.17,.15,.28);rect(bg,Vector2.ZERO,Vector2(1440,900),overlay)
	card(Vector2(490,166),Vector2(460,576),P.WHITE,24,overlay)
	small_caps("Take a little pause",Vector2(526,212),Vector2(385,25),overlay)
	text_label("Life at your pace.",Vector2(523,246),Vector2(390,57),37,P.INK,true,overlay)
	var actions=[
		["Resume",close_overlay],
		["Save this life",func():menus.show_picker("save")],
		["Load a saved life",func():menus.show_picker("load")],
		["Life settings",show_life_settings],
		["How to play",func():show_help()],
		["Sound: "+("on" if sound_enabled else "off"),func():set_sound(not sound_enabled);show_menu()],
		["Main menu",show_main_menu]
	]
	for i in range(actions.size()):button(actions[i][0],Vector2(522,323+i*53),Vector2(396,43),actions[i][1],i==0,overlay)

func show_help() -> void:
	_begin_pause_overlay()
	var background:ColorRect=ColorRect.new()
	background.color=Color(.08,.17,.15,.28)
	rect(background,Vector2.ZERO,Vector2(1440,900),overlay)
	card(Vector2(420,148),Vector2(600,587),P.WHITE,24,overlay)
	text_label("Make yourself at home.",Vector2(454,175),Vector2(526,63),36,P.INK,true,overlay)
	paragraph("Click a furnishing or a neighbor to choose an activity. Your Lifelet walks there, then gets started. Queue activities and cancel them by clicking their ×. Needs change throughout the day; different activities restore them.",Vector2(458,257),Vector2(514,108),17,P.INK,overlay)
	paragraph("Build friendships, practice skills, sell paintings, or do a paid shift at your desk. Your traits and aspirations shape what feels rewarding.",Vector2(458,377),Vector2(514,76),17,P.INK,overlay)
	paragraph("CAMERA   Mouse wheel to zoom · right-drag to orbit\n                  WASD / arrows to pan · Q / E to rotate\nTIME          Space to pause · 1 / 2 / 3 for speed\nHOME       B for Build & buy · R to rotate furniture\nSAVE         F5 to save · F9 to continue your save\nMENU       Esc to close a panel or pause",Vector2(458,473),Vector2(514,164),15,P.MUTED,overlay)
	button("Let's live",Vector2(458,659),Vector2(522,48),close_overlay,true,overlay)

func show_person() -> void:
	close_overlay();overlay_open=true;dismiss_layer()
	card(Vector2(492,167),Vector2(456,560),P.WHITE,24,overlay)
	small_caps("Your Lifelet",Vector2(525,191),Vector2(390,24),overlay)
	var personal_name=text_label(sim.character.name,Vector2(521,234),Vector2(390,61),37,P.INK,true,overlay)
	personal_name.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS;personal_name.size=Vector2(390,61)
	personal_name.tooltip_text=str(sim.character.name);personal_name.mouse_filter=Control.MOUSE_FILTER_PASS
	text_label(LifeLifecycle.description(str(sim.character.age_stage),sim.lifecycle),Vector2(525,297),Vector2(385,22),12,P.MUTED,false,overlay)
	text_label("Aspiration  ·  "+sim.character.aspiration,Vector2(525,320),Vector2(385,32),19,P.TEAL,false,overlay)
	var traits_text=""
	for tr in sim.character.traits:traits_text+="•  "+tr+"\n"
	paragraph(traits_text,Vector2(525,379),Vector2(384,135),21,P.INK,overlay)
	if sim.moodlets.is_empty():
		paragraph(sim.get_mood().description,Vector2(525,536),Vector2(380,65),16,P.MUTED,overlay)
	else:
		for index:int in range(mini(2,sim.moodlets.size())):
			var feeling:Dictionary=sim.moodlets[sim.moodlets.size()-1-index]
			var label:Label=text_label("%s · %s" % [feeling.emotion,feeling.label],Vector2(525,534+index*35),Vector2(380,31),13,P.TEAL,false,overlay)
			label.tooltip_text=str(feeling.description)+" · %d minutes" % int(feeling.remaining)
	var has_school_history:bool=not sim.education.records.is_empty()
	if not LifeLifecycle.next_stage(str(sim.character.age_stage)).is_empty():
		button("Celebrate a birthday",Vector2(525,609),Vector2(184 if has_school_history else 386,29),show_birthday,false,overlay)
	if has_school_history:
		button("School history",Vector2(726,609),Vector2(186,29),show_school_history,false,overlay)
	button("Family tree",Vector2(524,649),Vector2(179,48),show_family_tree,false,overlay)
	button("Back to life",Vector2(717,649),Vector2(196,48),close_overlay,true,overlay)

func show_careers() -> void:
	_begin_pause_overlay()
	var background:ColorRect=ColorRect.new()
	background.color=Color(.08,.17,.15,.28)
	rect(background,Vector2.ZERO,Vector2(1440,900),overlay)
	card(Vector2(446,132),Vector2(548,644),P.WHITE,24,overlay)
	small_caps("Find your direction",Vector2(478,155),Vector2(480,25),overlay)
	text_label("A new chapter at work.",Vector2(476,194),Vector2(484,57),33,P.INK,true,overlay)
	paragraph("Choose a path that fits your Lifelet. A career change starts at its first rank; your learned skills stay with you.",Vector2(479,261),Vector2(479,54),14,P.MUTED,overlay)
	var index:int=0
	for track_id:String in LifeSim.CAREER_TRACKS:
		var track:Dictionary=LifeSim.CAREER_TRACKS[track_id]
		var y:float=325+index*91
		var current:bool=str(sim.career.get("track","studio"))==track_id
		button(str(track.label)+( " · Current" if current else ""),Vector2(478,y),Vector2(484,43),func():_select_career(track_id),current,overlay)
		text_label("%s · §%d / shift · %s skill" % [track.titles[0],track.base_salary,str(track.skill).capitalize()],Vector2(484,y+47),Vector2(474,28),12,P.MUTED,false,overlay)
		index+=1
	button("Back to life",Vector2(478,713),Vector2(484,43),close_overlay,false,overlay)

func _select_career(track_id:String) -> void:
	if sim.choose_career(track_id):
		close_overlay()
		draw_live()

func show_wishes() -> void:
	close_overlay();overlay_open=true;dismiss_layer()
	card(Vector2(467,115),Vector2(506,651),P.WHITE,24,overlay)
	small_caps("Little steps. A fuller life.",Vector2(500,139),Vector2(441,24),overlay)
	text_label("Your wishes",Vector2(497,177),Vector2(440,60),40,P.INK,true,overlay)
	text_label("%d satisfaction earned" % sim.satisfaction,Vector2(500,247),Vector2(440,34),17,P.TEAL,false,overlay)
	for i in range(sim.wants.size()):
		var w:Dictionary=sim.wants[i]
		var y=304+i*105
		text_label(("✓  " if w.complete else "○  ")+w.label,Vector2(500,y),Vector2(440,33),22,P.INK,true,overlay)
		paragraph(w.description,Vector2(527,y+36),Vector2(407,40),14,P.MUTED,overlay)
		line(Vector2(500,y+91),Vector2(440,1),overlay)
	button("Back to life",Vector2(500,695),Vector2(440,45),close_overlay,true,overlay)

func save_game(slot_id:String="",title:String="") -> bool:
	if mode not in ["live","build"]:show_notice("Move into a home to save your life.");return false
	if title.is_empty():
		slot_id=active_save_id
		title=active_save_name if not active_save_name.is_empty() else str(sim.character.name)+"'s story"
	if not overlay_open:capture_save_preview()
	cancel_placement()
	_store_motion()
	sim.character["world_state"]={"player":[player.position.x,player.position.y,player.position.z],"player_rotation":player.rotation.y,"camera":[world.camera_target.x,world.camera_target.y,world.camera_target.z],"angle":world.camera_angle,"elevation":world.camera_elevation,"zoom":world.camera.size,"floor":floor_color,"lot":selected_lot,"cutaway":world.cutaway,"sound":sound_enabled,"venue":current_venue,"home_layout":home_layout,"venue_layouts":venue_layouts}
	# Store the user's live speed, not a temporary menu/build pause.
	var current_speed:int=sim.speed
	sim.speed=speed_before_build if mode=="build" else (pause_before_menu if overlay_pauses_sim else current_speed)
	for member:Dictionary in household.members:
		if member.id==bound_member_id:continue
		var actor:LifeActor=world.actors[member.id]
		member.sim.character["world_state"]={"player":[actor.position.x,actor.position.y,actor.position.z],"player_rotation":actor.rotation.y}
	for member:Dictionary in household.members:
		var motion:Dictionary=motion_states.get(str(member.id),_empty_motion())
		var action:Dictionary=member.sim.get_current_action()
		member.sim.character.world_state["resource_wait_started"]=float(motion.wait_started) if bool(motion.waiting) else -1.0
		member.sim.character.world_state["waiting_action_id"]=str(action.get("id",""))
		member.sim.character.world_state["waiting_target_id"]=str(action.get("target_id",""))
	household.adopt_selected_changes()
	var result:Dictionary=LifeSaveLibrary.save_slot(slot_id,title,household.get_state(world.serialize_items()),save_preview)
	var saved:bool=bool(result.ok)
	if saved:active_save_id=str(result.id);active_save_name=title
	household.set_speed(current_speed)
	if saved:show_notice("Your life is saved. See you right here.")
	else:show_notice(str(result.get("error","The save could not be written.")))
	return saved

func _restore_world_state(value:Variant) -> void:
	if not value is Dictionary:return
	var state:Dictionary=value
	var position:Vector3=_saved_vector(state.get("player"),player.position)
	var cell:Vector2i=Vector2i(roundi(position.x*4),roundi(position.z*4))
	if not world.navigation.region.has_point(cell) or world.navigation.is_point_solid(cell):
		cell=world.nearest_free(position)
		position=Vector3(cell.x*.25,.16,cell.y*.25)
	player.position=Vector3(position.x,.16,position.z)
	player.rotation.y=_saved_number(state.get("player_rotation"),0.0,-1000.0,1000.0)
	var target:Vector3=_saved_vector(state.get("camera"),world.camera_target)
	world.camera_target=Vector3(clampf(target.x,-16,16),clampf(target.y,-2,5),clampf(target.z,-12,12))
	world.camera_angle=_saved_number(state.get("angle"),world.camera_angle,-1000.0,1000.0)
	world.camera_elevation=_saved_number(state.get("elevation"),world.camera_elevation,.35,1.30)
	world.camera.size=_saved_number(state.get("zoom"),world.camera.size,6.0,31.0)
	selected_lot=int(_saved_number(state.get("lot"),float(selected_lot),0.0,2.0))
	var saved_floor:Variant=state.get("floor",floor_color)
	if saved_floor is String and _valid_hex_color(saved_floor):_apply_floor_color(saved_floor)
	else:_apply_floor_color(floor_color)
	if state.get("cutaway") is bool:world.set_cutaway(state.cutaway)
	if state.get("sound") is bool:set_sound(state.sound)
	world.update_camera()

func _saved_number(value:Variant,fallback:float,minimum:float,maximum:float) -> float:
	if not (value is float or value is int) or not is_finite(float(value)):return fallback
	return clampf(float(value),minimum,maximum)

func _saved_vector(value:Variant,fallback:Vector3) -> Vector3:
	if not value is Array or value.size()!=3:return fallback
	for component:Variant in value:
		if not (component is float or component is int) or not is_finite(float(component)):return fallback
	return Vector3(clampf(float(value[0]),-1000,1000),clampf(float(value[1]),-1000,1000),clampf(float(value[2]),-1000,1000))

func _valid_hex_color(value:String) -> bool:
	var hex:String=value.trim_prefix("#").to_lower()
	if hex.length() not in [6,8]:return false
	for character:String in hex:
		if character not in "0123456789abcdef":return false
	return true

func load_game(slot_id:String="") -> void:
	if slot_id.is_empty():slot_id=active_save_id if not active_save_id.is_empty() else LifeSaveLibrary.latest_id()
	var read_result:Dictionary=LifeSaveLibrary.read_slot(slot_id)
	if not read_result.ok:show_notice(str(read_result.get("error","No saved life yet.")));return
	loading_game=true
	route_generation+=1
	var result:Dictionary=household.restore_state(read_result.data)
	if not result.ok:
		loading_game=false
		show_notice(str(result.error));return
	has_active_game=true
	active_save_id=slot_id
	active_save_name=""
	for slot:Dictionary in LifeSaveLibrary.list_saves():
		if str(slot.id)==slot_id:active_save_name=str(slot.name);break
	sim=household.selected()
	var saved_world:Variant=sim.character.get("world_state",{})
	current_venue="home";home_layout=[];venue_layouts={}
	if saved_world is Dictionary:
		var place:String=str(saved_world.get("venue","home"))
		if LifeNeighborhood.PLACES.has(place):current_venue=place
		home_layout=_safe_layout(saved_world.get("home_layout",[]))
		var saved_venues:Variant=saved_world.get("venue_layouts",{})
		if saved_venues is Dictionary:
			for key:String in saved_venues:
				if key in LifeNeighborhood.PLACES and key!="home":venue_layouts[key]=_safe_layout(saved_venues[key])
	bound_member_id=household.selected_id()
	household_profiles=[]
	for member:Dictionary in household.members:household_profiles.append(member.sim.character.duplicate(true))
	creator_index=household.selected_index
	profile=household_profiles[creator_index]
	floor_color="cfa97e"
	setup_live(result.world)
	loading_game=false
	_refresh_sim_targets()
	_restore_resource_waits()
	_sync_actor_sound()
	show_notice("Welcome back, %s." % sim.character.name)

func _restore_resource_waits() -> void:
	var now:float=(household.day-1)*1440.0+household.minutes
	for member:Dictionary in household.members:
		var action:Dictionary=member.sim.get_current_action()
		var saved:Variant=member.sim.character.get("world_state",{})
		if not saved is Dictionary or action.is_empty() or str(action.phase)!="approach":continue
		if str(saved.get("waiting_action_id",""))!=str(action.id) or str(saved.get("waiting_target_id",""))!=str(action.target_id):continue
		var started:float=_saved_number(saved.get("resource_wait_started",-1.0),-1.0,-1.0,now)
		if started>=0:motion_states[str(member.id)]["wait_started"]=started
	_bind_member(household.selected_id())

func setup_audio() -> void:
	audio_player=AudioStreamPlayer.new();add_child(audio_player)
	if ResourceLoader.exists("res://assets/audio/soft_click.wav"):
		audio_player.stream=load("res://assets/audio/soft_click.wav")
	audio_player.volume_db=0
	ambience_player=AudioStreamPlayer.new();add_child(ambience_player)
	if ResourceLoader.exists("res://assets/audio/ambience_garden.wav"):
		var stream:AudioStreamWAV=load("res://assets/audio/ambience_garden.wav").duplicate()
		stream.loop_mode=AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin=0
		stream.loop_end=int(stream.get_length()*stream.mix_rate)
		ambience_player.stream=stream
		ambience_player.volume_db=0
		ambience_player.play()

func set_sound(enabled:bool) -> void:
	sound_enabled=enabled
	if is_instance_valid(ambience_player):ambience_player.stream_paused=not enabled
	if not enabled and is_instance_valid(audio_player):audio_player.stop()
	_sync_actor_sound()

func _sync_actor_sound() -> void:
	if not is_instance_valid(world):return
	var enabled:bool=sound_enabled and mode=="live" and is_instance_valid(sim) and sim.speed>0
	for actor:LifeActor in world.actors.values():
		if is_instance_valid(actor):actor.voice_enabled=enabled
	if is_instance_valid(preview):preview.voice_enabled=false

func play_click() -> void:
	if sound_enabled and audio_player and audio_player.stream:audio_player.play()

func _exit_tree() -> void:
	for audio:AudioStreamPlayer in [audio_player,ambience_player]:
		if is_instance_valid(audio):
			audio.stream_paused=false
			audio.stop()
			audio.stream=null

func _process(delta:float) -> void:
	elapsed+=delta
	if is_instance_valid(notice_card):
		notice_time-=delta
		if notice_time<.5:notice_card.modulate.a=clampf(notice_time*2,0,1)
		if notice_time<=0:notice_card.queue_free()
	if mode=="creator":
		if is_instance_valid(preview):preview.animate(delta,1,false,"")
		return
	if mode not in ["live","build"]:return
	if mode=="live":
		_store_motion()
		var selected_id:String=household.selected_id()
		var autonomy_values:Dictionary={}
		for member:Dictionary in household.members:
			autonomy_values[member.id]=member.sim.autonomy
			if bool(motion_states.get(member.id,_empty_motion()).walk):member.sim.autonomy=false
		household.tick(delta)
		for member:Dictionary in household.members:member.sim.autonomy=autonomy_values[member.id]
		world.daylight(household.minutes)
		world.begin_activity_frame(household.speed<=0)
		for member:Dictionary in household.members:
			_bind_member(member.id)
			var moving:bool=_advance_movement(delta)
			var action:Dictionary=sim.get_current_action()
			var action_id:String="" if action.is_empty() or action.phase!="active" else action.id
			if not str(action.get("cooperation_id","")).is_empty() and action_id.is_empty():
				var shared:Dictionary=household.cooperative_presentation(bound_member_id)
				if bool(shared.get("ready",false)) and str(shared.get("role",""))=="learner":action_id="homework_wait"
			_update_activity_facing(delta,action,action_id)
			player.animate(delta,float(sim.speed),moving,action_id)
			_store_motion()
		_bind_member(selected_id)
		for id:String in ["maya","leo"]:
			var actor:LifeActor=world.actors[id]
			var talk_id:String=""
			for member:Dictionary in household.members:
				var action:Dictionary=member.sim.get_current_action()
				if not action.is_empty() and str(action.target_id)==id and action.phase=="active":
					talk_id=action.id
					var direction:Vector3=world.actors[member.id].position-actor.position
					actor.rotation.y=lerp_angle(actor.rotation.y,atan2(direction.x,direction.z),minf(delta*4,1))
			actor.animate(delta,float(sim.speed),false,talk_id)
		hud_refresh+=delta
		if hud_refresh>.25:hud_refresh=0;refresh_hud()
	if mode=="build":refresh_build_quote()
	if not overlay_open and not get_viewport().gui_get_focus_owner() is LineEdit:
		var pan=Vector2.ZERO
		if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP):pan.y-=1
		if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN):pan.y+=1
		if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):pan.x-=1
		if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):pan.x+=1
		if pan.length()>0:
			var side=Vector3(cos(world.camera_angle),0,-sin(world.camera_angle))
			var forward=Vector3(sin(world.camera_angle),0,cos(world.camera_angle))
			world.camera_target+=(side*pan.x+forward*pan.y)*delta*7
			world.camera_target.x=clampf(world.camera_target.x,-16,16);world.camera_target.z=clampf(world.camera_target.z,-12,12)
			world.update_camera()

func _advance_movement(delta:float) -> bool:
	if not is_instance_valid(player) or sim.speed<=0:return false
	if waiting_for_target:
		if _activity_available(sim.get_current_action()):
			waiting_for_target=false
			wait_started=-1.0
			household.begin_action(bound_member_id)
		else:_reconsider_waiting_activity()
		return false
	if not walk_only and sim.action_queue.is_empty():
		_clear_motion();return false
	var was_moving:bool=path_index<path.size()
	var distance_left:float=maxf(0.0,delta)*1.6*float(sim.speed)
	while path_index<path.size() and distance_left>0.00001:
		var goal:Vector3=path[path_index]
		var direction:Vector3=goal-player.position
		var distance:float=direction.length()
		if distance<.001:
			path_index+=1;continue
		player.rotation.y=lerp_angle(player.rotation.y,atan2(direction.x,direction.z),minf(delta*12,1))
		if distance<=distance_left:
			player.position=goal;distance_left-=distance;path_index+=1
		else:
			player.position+=direction/distance*distance_left;distance_left=0.0
	if was_moving and path_index>=path.size():
		path.clear();path_index=0
		var should_begin:bool=not walk_only
		walk_only=false
		if should_begin:
			if wait_started<0:wait_started=(household.day-1)*1440.0+household.minutes
			if _activity_available(sim.get_current_action()):
				wait_started=-1.0
				household.begin_action(bound_member_id)
			else:waiting_for_target=true
	return was_moving

func _reconsider_waiting_activity() -> void:
	var action:Dictionary=sim.get_current_action()
	if action.is_empty() or not bool(action.get("autonomous",false)) or not str(action.get("cooperation_id","")).is_empty():return
	var now:float=(household.day-1)*1440.0+household.minutes
	var waited:float=now-wait_started
	if wait_started<0 or waited<30 or now<wait_review:return
	var blocked:Array[String]=[]
	for target:Dictionary in world.simulation_targets():
		if str(target.id)==bound_member_id:continue
		if not _activity_available({"target_id":str(target.id),"target_position":target.position}):blocked.append(str(target.id))
	_store_motion()
	var prior:Dictionary=motion_states[bound_member_id].duplicate()
	_clear_motion()
	if not sim.reconsider_waiting_autonomy(blocked,waited):
		motion_states[bound_member_id]=prior
		_bind_member(bound_member_id)
		wait_review=now+15.0

func _unhandled_input(event:InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode==KEY_ESCAPE:
			if overlay_open:close_overlay()
			elif mode=="build" and _has_placement_tool():cancel_placement()
			elif mode in ["live","build"]:show_menu()
			get_viewport().set_input_as_handled()
			return
		if get_viewport().gui_get_focus_owner() is LineEdit:return
		if overlay_open:return
		if mode in ["live","build"]:
			match event.keycode:
				KEY_B:set_build_mode(mode!="build")
				KEY_SPACE:set_game_speed(1 if sim.speed==0 else 0)
				KEY_1:set_game_speed(1)
				KEY_2:set_game_speed(3)
				KEY_3:set_game_speed(8)
				KEY_Q:world.camera_angle-=PI/8;world.update_camera()
				KEY_E:world.camera_angle+=PI/8;world.update_camera()
				KEY_R:
					if mode=="build":world.placement_angle+=90
				KEY_F5:save_game()
				KEY_F9:menus.show_picker("load")
	if overlay_open:return
	if event is InputEventMouseButton:
		if event.button_index==MOUSE_BUTTON_RIGHT:camera_drag=event.pressed;last_mouse=event.position
		if mode=="creator" and event.button_index==MOUSE_BUTTON_LEFT:
			creator_drag=event.pressed;last_mouse=event.position
		if mode in ["live","build"]:
			if event.button_index==MOUSE_BUTTON_WHEEL_UP:world.camera.size=maxf(world.camera.size-1,6)
			if event.button_index==MOUSE_BUTTON_WHEEL_DOWN:world.camera.size=minf(world.camera.size+1,31)
			if event.button_index==MOUSE_BUTTON_LEFT and event.pressed:world.pick(event.position)
	if event is InputEventMouseMotion:
		if mode=="creator" and creator_drag:
			creator_spin+=event.relative.x*.012;preview.rotation.y=creator_spin
		elif camera_drag and mode in ["live","build"]:
			world.camera_angle-=event.relative.x*.008
			world.camera_elevation=clampf(world.camera_elevation+event.relative.y*.004,.35,1.30)
			world.update_camera()

func _has_placement_tool() -> bool:
	return not world.placement_kind.is_empty() or (is_instance_valid(world.construction) and not world.construction.tool.is_empty())

func _update_activity_facing(delta:float,action:Dictionary,action_id:String) -> void:
	if player.has_method("clear_activity_anchor"):player.clear_activity_anchor()
	if action_id.is_empty():return
	var item:Dictionary=_find_item(str(action.target_id))
	if not item.is_empty():
		if action_id=="help_homework":
			var at:Vector3=action.target_position
			var toward:Vector3=item.node.to_global(Vector3(0,.9,.3))-at
			var anchor:Dictionary={"position":at,"yaw":atan2(toward.x,toward.z),"kind":"standing"}
			player.set_activity_anchor(at,anchor.yaw,"standing",action_id,anchor)
			return
		var landmarks:Dictionary=player.get_body_landmarks() if player.has_method("get_body_landmarks") else {}
		var anchor:Dictionary=world.activity_anchor(item,action_id,landmarks)
		if player.has_method("set_activity_anchor"):
			player.set_activity_anchor(anchor.position,anchor.yaw,anchor.kind,action_id,anchor)
		else:
			player.rotation.y=lerp_angle(player.rotation.y,anchor.yaw,minf(delta*6,1))
		return
	if world.actors.has(str(action.target_id)):
		var direction:Vector3=world.actors[str(action.target_id)].position-player.position
		player.rotation.y=lerp_angle(player.rotation.y,atan2(direction.x,direction.z),minf(delta*6,1))

func _resolve_activity_target(action:Dictionary) -> void:
	if world.actors.has(str(action.target_id)):
		action.target_position=world.actors[str(action.target_id)].position+Vector3(0,0,.9)
		return
	var item:Dictionary=_find_item(str(action.target_id))
	var wanted:String=""
	if action.id=="cook" and not item.is_empty() and item.kind=="fridge":wanted="stove"
	if action.id=="watch" and not item.is_empty() and item.kind=="tv":wanted="sofa"
	if wanted.is_empty():return
	var best:Dictionary=world.closest_item(wanted,item.node.position)
	if not best.is_empty():
		action.target_id=best.id
		action.target_position=world.approach(best)

func _activity_available(action:Dictionary) -> bool:
	if action.is_empty():return false
	var wanted:Array[String]=_activity_resources(action)
	var session_id:String=str(action.get("cooperation_id",""))
	for member:Dictionary in household.members:
		if member.id==bound_member_id:continue
		var other:Dictionary=member.sim.get_current_action()
		if other.is_empty():continue
		var other_session:String=str(other.get("cooperation_id",""))
		if not session_id.is_empty() and session_id==other_session:continue
		var other_wait:Dictionary=motion_states.get(str(member.id),_empty_motion())
		if other.phase!="active" and other_session.is_empty():
			if not bool(other_wait.waiting):continue
			var earlier:float=float(other_wait.get("wait_started",-1.0))
			if earlier<0:continue
			# An arrived Lifelet keeps their place when an earlier actor in the
			# household array finishes and immediately requests the same object.
			if wait_started>=0 and earlier>wait_started:continue
			if wait_started>=0 and is_equal_approx(earlier,wait_started) and str(member.id)>bound_member_id:continue
		for resource_id:String in _activity_resources(other):
			if wanted.has(resource_id):return false
	return true

func _activity_resources(action:Dictionary) -> Array[String]:
	var target_id:String=str(action.get("target_id",""))
	var item:Dictionary=_find_item(target_id)
	var resources:Array[String]=[]
	if item.is_empty():resources.append(target_id)
	else:resources=world.activity_resource_ids(item)
	if action.has("target_position"):
		var at:Vector3=action.target_position
		var cell:Vector2i=Vector2i(roundi(at.x*2),roundi(at.z*2))
		resources.append("standing:%d:%d" % [cell.x,cell.y])
		if str(action.get("cooperation_role",""))=="helper":
			for offset:Vector2i in [Vector2i(1,0),Vector2i(-1,0),Vector2i(0,1),Vector2i(0,-1)]:
				resources.append("standing:%d:%d" % [cell.x+offset.x,cell.y+offset.y])
	return resources

func show_relationships() -> void:
	close_overlay();overlay_open=true;dismiss_layer()
	card(Vector2(456,116),Vector2(528,654),P.WHITE,24,overlay)
	small_caps("People in your life",Vector2(487,138),Vector2(460,25),overlay)
	text_label("Every connection counts.",Vector2(485,177),Vector2(465,52),31,P.INK,true,overlay)
	var scroll=ScrollContainer.new()
	rect(scroll,Vector2(486,254),Vector2(470,415),overlay)
	var column=VBoxContainer.new();column.add_theme_constant_override("separation",10);scroll.add_child(column)
	for id:String in sim.relationship_order():
		var rel:Dictionary=sim.relationships[id]
		var row=Control.new();row.custom_minimum_size=Vector2(450,83);column.add_child(row)
		button(rel.name,Vector2.ZERO,Vector2(444,38),func():focus_neighbor(id),false,row)
		text_label("%s · Friendship %d · Romance %d" % [rel.status,rel.friendship,rel.romance],Vector2(8,44),Vector2(438,30),13,P.MUTED,false,row)
	button("Family tree",Vector2(486,699),Vector2(222,43),show_family_tree,false,overlay)
	button("Back to life",Vector2(724,699),Vector2(230,43),close_overlay,true,overlay)

func compact_button(b:Button) -> void:
	b.add_theme_font_size_override("font_size",12)
	for style_name:String in ["normal","hover","pressed","focus","disabled"]:
		var style:StyleBox=b.get_theme_stylebox(style_name).duplicate()
		style.content_margin_left=4;style.content_margin_right=4;style.content_margin_top=4;style.content_margin_bottom=4
		b.add_theme_stylebox_override(style_name,style)

func _safe_layout(value:Variant) -> Array:
	var result:Array=[]
	if not value is Array:return result
	for entry:Variant in value:
		if not entry is Dictionary:continue
		if str(entry.get("kind",""))=="__construction":
			if entry.get("walls") is Array and entry.get("floors") is Array:result.append(entry.duplicate(true))
			continue
		if not LifeCatalog.ITEMS.has(str(entry.get("kind",""))) or not entry.get("id") is String:continue
		if not (entry.get("x") is float or entry.get("x") is int) or not (entry.get("z") is float or entry.get("z") is int):continue
		result.append({"id":str(entry.id),"kind":str(entry.kind),"x":_saved_number(entry.x,0,-15,15),"z":_saved_number(entry.z,0,-15,15),"rotation":_saved_number(entry.get("rotation"),0,-10000,10000)})
	return result

func show_neighborhood(chosen:String="") -> void:
	if chosen.is_empty():chosen=current_venue
	_begin_pause_overlay()
	var shade=ColorRect.new();shade.color=Color(.08,.17,.15,.28);rect(shade,Vector2.ZERO,Vector2(1440,900),overlay)
	card(Vector2(211,122),Vector2(1018,650),P.WHITE,24,overlay)
	small_caps("A place to belong",Vector2(247,143),Vector2(600,24),overlay)
	text_label("Around Juniper Bay",Vector2(245,181),Vector2(750,59),40,P.INK,true,overlay)
	var map=Control.new();rect(map,Vector2(241,264),Vector2(580,436),overlay)
	map.draw.connect(func():
		map.draw_style_box(P.panel(Color("e5ebd8"),18),Rect2(Vector2.ZERO,Vector2(580,436)))
		map.draw_polyline(PackedVector2Array([Vector2(24,378),Vector2(112,338),Vector2(214,359),Vector2(343,374),Vector2(430,339),Vector2(564,346)]),Color("91b9b2"),42,true)
		map.draw_polyline(PackedVector2Array([Vector2(82,278),Vector2(255,208),Vector2(486,261)]),Color("f7f3df"),25,true)
		map.draw_polyline(PackedVector2Array([Vector2(255,208),Vector2(261,49)]),Color("f7f3df"),21,true)
		for p:Vector2 in [Vector2(36,52),Vector2(47,90),Vector2(531,75),Vector2(499,44),Vector2(330,303),Vector2(364,316),Vector2(41,217),Vector2(536,301)]:
			map.draw_circle(p,19,Color("a2bb84"));map.draw_circle(p-Vector2(5,5),12,Color("b5cb99"))
		for p:Vector2 in [Vector2(70,122),Vector2(332,76),Vector2(356,92),Vector2(172,226),Vector2(417,144)]:
			map.draw_style_box(P.panel(Color("c3bfa5"),4),Rect2(p,Vector2(32,28))))
	var points:Dictionary={"home":Vector2(74,230),"park":Vector2(97,74),"library":Vector2(356,242),"studio":Vector2(335,80)}
	for id:String in points:
		var data:Dictionary=LifeNeighborhood.PLACES[id]
		var p:Vector2=points[id]
		var pin=button(str(data.name),p,Vector2(170,53),func():show_neighborhood(id),id==chosen,map)
		pin.add_theme_font_size_override("font_size",13)
		if id==current_venue:text_label("YOU ARE HERE",p+Vector2(12,55),Vector2(166,22),10,P.TEAL,false,map)
	var data:Dictionary=LifeNeighborhood.PLACES[chosen]
	small_caps(str(data.tag),Vector2(848,282),Vector2(341,45),overlay)
	text_label(str(data.name),Vector2(846,334),Vector2(342,46),28,P.INK,true,overlay)
	paragraph(str(data.description),Vector2(848,395),Vector2(340,115),16,P.MUTED,overlay)
	paragraph("Travel takes the household together and clears current activities. The walk across town takes 15 minutes.",Vector2(848,545),Vector2(331,84),13,P.MUTED,overlay)
	var go=button("Travel here  →",Vector2(848,650),Vector2(344,50),func():travel_to(chosen),true,overlay)
	go.disabled=chosen==current_venue
	button("Back to life",Vector2(848,716),Vector2(344,35),close_overlay,false,overlay)

func travel_to(destination:String) -> void:
	if not LifeNeighborhood.PLACES.has(destination) or destination==current_venue:return
	cancel_placement()
	if current_venue=="home":home_layout=world.serialize_items()
	else:venue_layouts[current_venue]=world.serialize_items()
	var resume:int=pause_before_menu if overlay_pauses_sim else (speed_before_build if mode=="build" else sim.speed)
	close_overlay(false)
	loading_game=true
	_cancel_all_cooperative_actions()
	var automatic:Array=[]
	for member:Dictionary in household.members:
		automatic.append(member.sim.autonomy);member.sim.autonomy=false
		while not member.sim.action_queue.is_empty():member.sim.cancel_action()
		member.sim.character.erase("world_state")
	household.set_speed(1);household.tick(2.5)
	for i in range(household.members.size()):household.members[i].sim.autonomy=automatic[i]
	household.set_speed(resume)
	current_venue=destination
	var layout:Array=home_layout if destination=="home" else venue_layouts.get(destination,LifeNeighborhood.layout(destination))
	if destination=="home" and layout.is_empty():layout=LifeCatalog.starter_layout(selected_lot)
	setup_live(layout)
	loading_game=false
	for member:Dictionary in household.members:member.sim.remember("A change of scenery","Visited "+str(LifeNeighborhood.PLACES[destination].name)+".")
	show_notice("Welcome to "+str(LifeNeighborhood.PLACES[destination].name)+".")

func show_stories() -> void:
	_begin_pause_overlay()
	var shade=ColorRect.new();shade.color=Color(.08,.17,.15,.28);rect(shade,Vector2.ZERO,Vector2(1440,900),overlay)
	card(Vector2(358,103),Vector2(724,701),P.WHITE,24,overlay)
	small_caps("Day %d · %s" % [sim.day,sim.character.name],Vector2(392,125),Vector2(650,24),overlay)
	text_label("The stories you make.",Vector2(390,166),Vector2(650,55),37,P.INK,true,overlay)
	paragraph("A new connection. A small decision. The ordinary moments that make a life.",Vector2(394,236),Vector2(646,49),16,P.MUTED,overlay)
	var scroll=ScrollContainer.new();rect(scroll,Vector2(390,303),Vector2(656,398),overlay)
	var column=VBoxContainer.new();column.add_theme_constant_override("separation",22);scroll.add_child(column)
	var events:Array=sim.call("get_story_events") if sim.has_method("get_story_events") else []
	for event:Dictionary in events:
		var row=Control.new();row.custom_minimum_size=Vector2(635,133+event.choices.size()*83);column.add_child(row)
		text_label(str(event.title),Vector2(2,0),Vector2(623,39),25,P.INK,true,row)
		paragraph(str(event.description),Vector2(4,48),Vector2(623,72),14,P.MUTED,row)
		for i in range(event.choices.size()):
			var choice:Dictionary=event.choices[i]
			var b=button(str(choice.label),Vector2(2,127+i*83),Vector2(622,39),func():choose_story(str(event.id),str(choice.id)),false,row)
			b.disabled=not bool(choice.available)
			paragraph(str(choice.effects),Vector2(9,172+i*83),Vector2(610,34),12,P.MUTED,row)
	if events.is_empty():
		var row=Control.new();row.custom_minimum_size=Vector2(635,106);column.add_child(row)
		text_label("A little space for everyday life.",Vector2(2,0),Vector2(623,40),26,P.INK,true,row)
		paragraph("New invitations and opportunities arrive as the days pass. Your next decision will appear here.",Vector2(4,49),Vector2(623,51),15,P.MUTED,row)
	if sim.has_method("get_aspiration_progress"):
		var progress:Dictionary=sim.call("get_aspiration_progress")
		var row=Control.new();row.custom_minimum_size=Vector2(635,79);column.add_child(row)
		small_caps("Aspiration · chapter %d" % int(progress.stage),Vector2(4,0),Vector2(610,25),row)
		text_label(str(progress.title),Vector2(2,33),Vector2(623,38),24,P.TEAL,true,row)
	for i in range(mini(12,sim.memories.size())):
		var memory:Dictionary=sim.memories[i]
		var row=Control.new();row.custom_minimum_size=Vector2(635,88);column.add_child(row)
		small_caps("Day %d" % int(memory.day),Vector2(4,0),Vector2(610,21),row)
		text_label(str(memory.label),Vector2(2,23),Vector2(623,29),19,P.INK,true,row)
		paragraph(str(memory.detail),Vector2(4,57),Vector2(623,31),13,P.MUTED,row)
	button("Back to life",Vector2(390,735),Vector2(656,45),close_overlay,true,overlay)

func choose_story(event_id:String,choice_id:String) -> void:
	if sim.has_method("choose_story_event") and bool(sim.call("choose_story_event",event_id,choice_id)):
		household.adopt_selected_changes()
		show_stories()

func show_main_menu() -> void:
	if mode in ["live","build"] and has_active_game:
		menu_resume_speed=pause_before_menu if overlay_pauses_sim else sim.speed
		menu_game_mode=mode
		if not overlay_open:capture_save_preview()
	close_overlay(false)
	mode="menu"
	world.live_enabled=false
	world.set_build(false)
	_sync_actor_sound()
	if not has_active_game:
		if is_instance_valid(stage):stage.visible=false
		world.create_home(LifeCatalog.starter_layout(0))
		world.camera.projection=Camera3D.PROJECTION_ORTHOGONAL
		world.camera.size=16.5
		world.camera_angle=.62;world.camera_elevation=.80
		world.camera_target=Vector3(-3.0,0,-1.7)
		world.update_camera();world.daylight(1010)
	menus.main_menu()

func continue_life() -> void:
	if has_active_game:
		close_overlay(false)
		mode=menu_game_mode
		world.live_enabled=true
		world.set_build(mode=="build")
		household.set_speed(0 if mode=="build" else menu_resume_speed)
		draw_live();_sync_actor_sound()
	else:load_game()

func new_game() -> void:
	if has_active_game:
		show_replace_life("new","")
		return
	_begin_new_game()

func _begin_new_game() -> void:
	has_active_game=false;active_save_id="";active_save_name=""
	profile={"name":"Mara Vale","frame":0,"hair":1,"skin_color":"d9a17d","hair_color":"54382a","top_color":"c97c66","bottom_color":"eadfc9","body_scale":1.0,"height_scale":1.0,"outfit":0,"eye_color":"547365","traits":["Creative","Outgoing","Foodie"],"aspiration":"Maker"}
	household_profiles=[profile];creator_index=0;creator_family_links=[]
	show_creator()

func request_load_save(id:String) -> void:
	if has_active_game:show_replace_life("load",id)
	else:load_game(id)

func show_replace_life(action:String,id:String) -> void:
	_begin_pause_overlay();menus.shade()
	card(Vector2(461,265),Vector2(519,379),P.WHITE,24,overlay)
	text_label("Keep this chapter?",Vector2(491,294),Vector2(455,57),35,P.INK,true,overlay)
	paragraph("You have a household open. Save its latest moments before starting another life.",Vector2(495,382),Vector2(445,74),18,P.INK,overlay)
	var proceed=func():
		if action=="new":_begin_new_game()
		else:load_game(id)
	button("Save and continue",Vector2(494,490),Vector2(451,48),func():
		if mode=="menu":continue_life()
		if save_game():proceed.call(),true,overlay)
	button("Continue without saving",Vector2(494,552),Vector2(279,44),proceed,false,overlay)
	button("Cancel",Vector2(787,552),Vector2(158,44),close_overlay,false,overlay)

func capture_save_preview() -> void:
	if DisplayServer.get_name()=="headless":return
	var rendered:Image=get_viewport().get_texture().get_image()
	if rendered==null or rendered.is_empty():return
	var dimensions:Vector2i=rendered.get_size()
	var section=Rect2i(int(dimensions.x*.21),int(dimensions.y*.22),int(dimensions.x*.61),int(dimensions.y*.49))
	save_preview=rendered.get_region(section)
	save_preview.resize(640,380,Image.INTERPOLATE_LANCZOS)

func refresh_build_quote() -> void:
	if not is_instance_valid(build_quote_card) or not is_instance_valid(world.construction):return
	var structure:LifeConstruction=world.construction
	build_quote_card.visible=not structure.tool.is_empty()
	if not build_quote_card.visible:return
	if not structure.anchored and structure.tool in ["wall","room"]:
		build_quote.text="Click the first corner · Esc to cancel"
		build_quote.add_theme_color_override("font_color",P.INK)
		return
	var proposal:Dictionary=structure.proposal
	if proposal.is_empty():build_quote.text="Point at a wall · Esc to cancel";return
	var cost:int=int(proposal.get("cost",0))
	if not bool(proposal.get("valid",false)):
		build_quote.text="That space overlaps or is outside your lot"
		build_quote.add_theme_color_override("font_color",Color("a84f43"))
	elif cost>sim.funds:
		build_quote.text="§%d · You need §%d more" % [cost,cost-sim.funds]
		build_quote.add_theme_color_override("font_color",Color("a84f43"))
	else:
		build_quote.text=("Refund §%d" % -cost if cost<0 else "§%d" % cost)+" · Click to confirm"
		build_quote.add_theme_color_override("font_color",P.TEAL)

func member_initials(person_name:String,index:int,people:Array) -> String:
	var words:PackedStringArray=person_name.strip_edges().split(" ",false)
	var initials:String=words[0].left(1) if not words.is_empty() else "L"
	if words.size()>1:initials+=words[-1].left(1)
	else:initials=person_name.left(2)
	for i in range(people.size()):
		if i==index:continue
		var other_words:PackedStringArray=str(people[i].name).strip_edges().split(" ",false)
		var other:String=other_words[0].left(1) if not other_words.is_empty() else "L"
		if other_words.size()>1:other+=other_words[-1].left(1)
		else:other=str(people[i].name).left(2)
		if other.to_upper()==initials.to_upper():return initials.left(1).to_upper()+str(index+1)
	return initials.to_upper()

func creator_member_id(index:int) -> String:
	return "player" if index==0 else "housemate_%d" % index

func creator_member_index(id:String) -> int:
	return 0 if id=="player" else int(id.get_slice("_",1))

func creator_connection(other_index:int) -> String:
	var profiles:Dictionary={}
	for index:int in range(household_profiles.size()):profiles[creator_member_id(index)]=household_profiles[index]
	var result:Dictionary=LifeFamilyGraph.create(profiles,creator_family_links)
	if not bool(result.ok):return "housemates"
	var a:String=creator_member_id(creator_index)
	var b:String=creator_member_id(other_index)
	var role:String=LifeFamilyGraph.relationship(result.graph,a,b)
	if role!="none":return role
	for pair:Dictionary in result.partners:
		if (str(pair.a)==a and str(pair.b)==b) or (str(pair.a)==b and str(pair.b)==a):return "partners"
	return "housemates"

func family_role_label(role:String) -> String:
	return str({"housemates":"Housemate","none":"Housemate","siblings":"Sibling","parent":"Parent","child":"Child","grandparent":"Grandparent","grandchild":"Grandchild","ancestor":"Ancestor","descendant":"Descendant","parent_sibling":"Parent’s sibling","sibling_child":"Sibling’s child","cousin":"Cousin","relative":"Relative","partners":"Partner"}.get(role,"Relative"))

func show_creator_connections() -> void:
	close_overlay();overlay_open=true;menus.shade()
	card(Vector2(391,151),Vector2(659,598),P.WHITE,24,overlay)
	small_caps("People already in your story",Vector2(425,174),Vector2(592,25),overlay)
	text_label("How are you connected?",Vector2(422,218),Vector2(593,58),35,P.INK,true,overlay)
	var selected_name=text_label(str(profile.name),Vector2(426,287),Vector2(587,34),23,P.TEAL,true,overlay)
	selected_name.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS;selected_name.size=Vector2(587,34)
	paragraph("Choose who each person is to this Lifelet. Parents must be adults in an older age stage. Shared parents connect siblings automatically.",Vector2(428,337),Vector2(578,74),16,P.MUTED,overlay)
	var scroll=ScrollContainer.new();rect(scroll,Vector2(424,433),Vector2(590,216),overlay)
	var column=VBoxContainer.new();column.add_theme_constant_override("separation",15);scroll.add_child(column)
	for i:int in range(household_profiles.size()):
		if i==creator_index:continue
		var row=Control.new();row.custom_minimum_size=Vector2(568,53);column.add_child(row)
		var name_label=text_label(str(household_profiles[i].name),Vector2(2,3),Vector2(285,41),20,P.INK,true,row)
		name_label.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS;name_label.size=Vector2(285,41)
		name_label.tooltip_text=str(household_profiles[i].name);name_label.mouse_filter=Control.MOUSE_FILTER_PASS
		var choice=OptionButton.new()
		var roles:Array[String]=["housemates","siblings","partners","parent","child"]
		for label:String in ["Housemates","Siblings","Partners","My parent","My child"]:choice.add_item(label)
		var current:String=creator_connection(i)
		if current not in roles:
			roles.append(current);choice.add_item(family_role_label(current));choice.set_item_disabled(roles.size()-1,true)
		choice.select(roles.find(current))
		rect(choice,Vector2(300,3),Vector2(263,42),row)
		choice.set_meta("connection_member",i)
		choice.item_selected.connect(func(selected:int):set_creator_connection(i,roles[selected]))
	button("Back to creating",Vector2(426,680),Vector2(586,44),close_overlay,true,overlay)

func set_creator_connection(other_index:int,role:String) -> void:
	if other_index<0 or other_index>=household_profiles.size() or other_index==creator_index:return
	var a:String=creator_member_id(creator_index)
	var b:String=creator_member_id(other_index)
	var links:Array=creator_family_links.filter(func(link:Dictionary):return not ((str(link.a)==a and str(link.b)==b) or (str(link.a)==b and str(link.b)==a)))
	if role=="parent":links.append({"a":b,"b":a,"role":"parent"})
	elif role=="child":links.append({"a":a,"b":b,"role":"parent"})
	else:links.append({"a":a,"b":b,"role":role})
	var validator=LifeHousehold.new()
	validator.new_household(household_profiles)
	var result:Dictionary=validator.configure_family(links)
	validator.free()
	if result.ok:creator_family_links=links
	show_creator_connections()
	if not result.ok:show_notice(str(result.error))

func _minimal_sibling_links(links:Array) -> Array:
	var result:Array=[]
	var groups:Dictionary={}
	for link:Dictionary in links:
		groups[str(link.a)]=str(link.a);groups[str(link.b)]=str(link.b)
	for link:Dictionary in links:
		if str(link.role)!="siblings":result.append(link);continue
		var a:String=str(link.a);var b:String=str(link.b)
		while groups[a]!=a:a=groups[a]
		while groups[b]!=b:b=groups[b]
		if a!=b:groups[b]=a;result.append(link)
	return result

func _refresh_aged_member(id: String) -> void:
	var member: LifeSim = household.member_sim(id)
	if member == null: return
	var actor: LifeActor = world.actors.get(id) as LifeActor
	if is_instance_valid(actor):
		var appearance: Dictionary = member.character.duplicate(true)
		appearance["low_detail"] = bool(actor.profile.get("low_detail", false))
		actor.configure(appearance)
	for i: int in range(household.members.size()):
		if str(household.members[i].id) == id and i < household_profiles.size():
			household_profiles[i] = member.character.duplicate(true)
	if mode in ["live", "build"]: draw_live()

func show_life_settings() -> void:
	_begin_pause_overlay();menus.shade()
	card(Vector2(445,177),Vector2(550,546),P.WHITE,24,overlay)
	text_label("Life at your pace",Vector2(476,207),Vector2(486,60),35,P.INK,true,overlay)
	paragraph("Choose how quickly your household grows. Changing the pace keeps each Lifelet's progress through their current age.",Vector2(479,286),Vector2(478,75),17,P.MUTED,overlay)
	small_caps("Lifespan",Vector2(480,389),Vector2(477,25),overlay)
	var pace := OptionButton.new()
	pace.name="LifespanSetting"
	for label: String in ["Short", "Normal", "Long"]: pace.add_item(label)
	pace.select(["short","normal","long"].find(str(sim.lifecycle.lifespan)))
	rect(pace,Vector2(478,425),Vector2(480,43),overlay)
	var automatic := CheckButton.new()
	automatic.name="AutomaticAgingSetting"
	automatic.text="Automatic birthdays"
	automatic.button_pressed=bool(sim.lifecycle.auto_age)
	rect(automatic,Vector2(478,490),Vector2(480,42),overlay)
	paragraph("With automatic birthdays off, Lifelets keep their age until you choose to celebrate a birthday.",Vector2(480,549),Vector2(474,65),14,P.MUTED,overlay)
	button("Apply",Vector2(478,641),Vector2(230,44),func():
		household.set_aging(["short","normal","long"][pace.selected],automatic.button_pressed)
		close_overlay();refresh_hud(),true,overlay)
	button("Cancel",Vector2(725,641),Vector2(233,44),close_overlay,false,overlay)

func show_birthday() -> void:
	_begin_pause_overlay();menus.shade()
	var next: String=LifeLifecycle.next_stage(str(sim.character.age_stage))
	if next.is_empty():close_overlay();return
	card(Vector2(450,250),Vector2(540,399),P.WHITE,24,overlay)
	text_label("A new chapter",Vector2(481,282),Vector2(476,54),35,P.INK,true,overlay)
	paragraph("Celebrate %s's birthday and become %s. Your personality, friendships and learned skills stay with you." % [sim.character.name,LifeLifecycle.with_article(next)],Vector2(484,371),Vector2(470,117),19,P.INK,overlay)
	button("Celebrate · §30",Vector2(483,554),Vector2(271,48),func():close_overlay();queue_nearest("fridge","birthday"),true,overlay)
	button("Keep this age",Vector2(768,554),Vector2(188,48),close_overlay,false,overlay)

func creator_age_stages() -> Array:
	var stages: Array=[]
	for age: String in LifeLifecycle.STAGES:
		if age in ["young_adult","adult"] or (is_instance_valid(preview) and preview.has_method("supports_age") and preview.call("supports_age",age)):
			stages.append(age)
	return stages

func set_creator_age(value: String) -> void:
	if value not in creator_age_stages():return
	var previous: String=LifeLifecycle.stage_for(profile)
	profile["age_stage"]=value
	profile["life_stage"]=LifeLifecycle.eligibility(value)
	var validator:=LifeHousehold.new()
	validator.new_household(household_profiles)
	var result:Dictionary=validator.configure_family(creator_family_links)
	validator.free()
	if not bool(result.ok):
		profile.age_stage=previous;profile.life_stage=LifeLifecycle.eligibility(previous)
		show_notice(str(result.error))
	refresh_preview()

func show_school_record() -> void:
	_begin_pause_overlay();menus.shade()
	var school: Dictionary=LifeEducation.summary(sim.education)
	card(Vector2(430,164),Vector2(580,574),P.WHITE,24,overlay)
	text_label("Growing every day",Vector2(461,193),Vector2(518,60),35,P.INK,true,overlay)
	text_label(str(school.school),Vector2(465,278),Vector2(510,40),24,P.TEAL,true,overlay)
	text_label("Grade %s · %d%% attendance" % [school.grade,roundi(float(school.attendance)*100)],Vector2(465,329),Vector2(510,38),20,P.INK,false,overlay)
	paragraph("Online classes run Monday to Friday. Start between 08:00 and 14:00 at a desk; lessons take three hours. Do homework to prepare for your next class.",Vector2(465,389),Vector2(505,91),17,P.MUTED,overlay)
	var classes:String="%d %s attended" % [sim.education.attended,"class" if int(sim.education.attended)==1 else "classes"]
	var assignments:String="%d %s" % [sim.education.homework,"assignment" if int(sim.education.homework)==1 else "assignments"]
	text_label("%s · %d missed · %s" % [classes,sim.education.missed,assignments],Vector2(465,504),Vector2(506,30),14,P.INK,false,overlay)
	paragraph("Graduation needs at least three attended classes, 70% attendance and a C grade. Your school record stays with you as you grow.",Vector2(465,555),Vector2(505,63),14,P.MUTED,overlay)
	button("Back to life",Vector2(464,653),Vector2(512,45),close_overlay,true,overlay)

func frame_creator_camera() -> void:
	if not is_instance_valid(preview):return
	var center:Vector3=preview.call("get_portrait_center") if preview.has_method("get_portrait_center") else Vector3(0,1.52,0)
	var height:float=float(preview.call("get_display_height")) if preview.has_method("get_display_height") else 1.76
	if creator_tab=="Face":
		var ratio:float=clampf(height/1.76,.8,1.1)
		world.camera.position=center+Vector3(0,.07*ratio,1.37*ratio)
		world.camera.look_at(center,Vector3.UP)
	else:
		world.camera.position=Vector3(0,height*.67045,height*2.47159)
		world.camera.look_at(Vector3(0,height*.54545,0),Vector3.UP)

func show_school_history() -> void:
	_begin_pause_overlay();menus.shade()
	card(Vector2(430,174),Vector2(580,552),P.WHITE,24,overlay)
	text_label("The years that shaped you",Vector2(460,202),Vector2(518,58),29,P.INK,true,overlay)
	paragraph("Your school milestones stay part of your Lifelet's story.",Vector2(465,286),Vector2(505,48),17,P.MUTED,overlay)
	var row:int=0
	for record:Dictionary in sim.education.records:
		var y:float=360+row*117
		var school:String="Willow School" if str(record.stage)=="child" else "Morrow Secondary"
		var outcome:String={"completed":"Completed","graduated":"Graduated","unfinished":"Coursework incomplete"}.get(str(record.outcome),"Recorded")
		text_label(school,Vector2(465,y),Vector2(510,34),22,P.TEAL,true,overlay)
		text_label("%s · Grade %s · Day %d" % [outcome,record.grade,record.day],Vector2(466,y+44),Vector2(505,31),15,P.INK,false,overlay)
		row+=1
	button("Back to life",Vector2(464,647),Vector2(512,45),close_overlay,true,overlay)

func show_family_tree(focus_id:String="") -> void:
	var previous_scroll:ScrollContainer=overlay.find_child("FamilyTreeScroll",true,false) as ScrollContainer
	var scroll_position:Vector2i=Vector2i(previous_scroll.scroll_horizontal,previous_scroll.scroll_vertical) if is_instance_valid(previous_scroll) else Vector2i.ZERO
	if focus_id.is_empty():focus_id=household.selected_id()
	var focus:LifeSim=household.member_sim(focus_id)
	if focus==null:return
	_begin_pause_overlay();menus.shade()
	card(Vector2(166,87),Vector2(1108,725),P.WHITE,24,overlay)
	small_caps("Your roots, your people",Vector2(202,107),Vector2(1010,25),overlay)
	text_label("A family, connected.",Vector2(199,144),Vector2(1018,59),39,P.INK,true,overlay)
	var subtitle:Label=text_label("The people in %s’s household. Select a Lifelet to see their connections." % str(focus.character.name),Vector2(203,213),Vector2(1028,42),17,P.MUTED,false,overlay)
	subtitle.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS;subtitle.size=Vector2(1028,42)
	var links:Array=household.get_family_links()
	var parents:Array=household.call("family_parent_links")
	var levels:Dictionary=_family_generation_levels(links,parents)
	var rows:Dictionary={}
	for member:Dictionary in household.members:
		var level:int=int(levels[str(member.id)])
		if not rows.has(level):rows[level]=[]
		rows[level].append(member)
	var widest:int=1
	var deepest:int=0
	for level:int in rows:widest=maxi(widest,rows[level].size());deepest=maxi(deepest,level)
	var scroll:=ScrollContainer.new();scroll.name="FamilyTreeScroll"
	rect(scroll,Vector2(200,265),Vector2(1040,430),overlay)
	var diagram:=Control.new();diagram.name="FamilyDiagram"
	diagram.custom_minimum_size=Vector2(maxf(1020,widest*222+32),maxf(426,(deepest+1)*138+12))
	diagram.mouse_filter=Control.MOUSE_FILTER_PASS;scroll.add_child(diagram)
	var positions:Dictionary={}
	for level:int in rows:
		var row:Array=rows[level]
		var left:float=(diagram.custom_minimum_size.x-row.size()*222+22)*.5
		for i:int in range(row.size()):positions[str(row[i].id)]=Vector2(left+i*222,24+level*138)
	diagram.draw.connect(func():
		for edge:Dictionary in links:
			var a:Vector2=positions[str(edge.a)]
			var b:Vector2=positions[str(edge.b)]
			var role:String=str(edge.role)
			if role=="parent":
				var start:Vector2=a+Vector2(100,112)
				var finish:Vector2=b+Vector2(100,0)
				var midway:float=(start.y+finish.y)*.5
				diagram.draw_polyline(PackedVector2Array([start,Vector2(start.x,midway),Vector2(finish.x,midway),finish]),P.TEAL,2.5,true)
				diagram.draw_circle(finish,4,P.TEAL)
			elif role in ["partners","siblings"]:
				var start:Vector2=a+Vector2(100,0)
				var finish:Vector2=b+Vector2(100,0)
				var bridge:float=minf(start.y,finish.y)-18
				var color:Color=Color("c67d68") if role=="partners" else Color("aab5a9")
				diagram.draw_polyline(PackedVector2Array([start,Vector2(start.x,bridge),Vector2(finish.x,bridge),finish]),color,2,true))
	for member:Dictionary in household.members:
		var id:String=str(member.id)
		var person:Dictionary=member.sim.character
		var position:Vector2=positions[id]
		var tile:=Control.new();tile.name="FamilyCard_"+id;rect(tile,position,Vector2(200,112),diagram)
		card(Vector2.ZERO,Vector2(200,112),Color("e6efe5") if id==focus_id else Color("f4f5ee"),16,tile)
		model_thumbnail("character",Vector2(7,5),Vector2(60,75),true,tile,person)
		var name_button:Button=button(str(person.name),Vector2(70,9),Vector2(122,45),func():show_family_tree(id),false,tile)
		name_button.name="FamilyFocus_"+id;name_button.add_theme_font_size_override("font_size",13)
		name_button.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS;name_button.tooltip_text=str(person.name)
		text_label(str(LifeLifecycle.LABELS[person.age_stage]),Vector2(74,58),Vector2(117,24),12,P.MUTED,false,tile)
		var relation:String=str(household.call("family_relationship",focus_id,id))
		if relation=="none" and focus.romantic_partner==id:relation="partners"
		text_label("You are viewing" if id==focus_id else family_role_label(relation),Vector2(13,84),Vector2(174,26),14,P.TEAL,id==focus_id,tile)
	text_label("Parent & child",Vector2(207,705),Vector2(153,25),12,P.TEAL,false,overlay)
	text_label("Partners",Vector2(374,705),Vector2(108,25),12,Color("b86e5b"),false,overlay)
	text_label("Declared siblings",Vector2(496,705),Vector2(165,25),12,P.MUTED,false,overlay)
	button("People",Vector2(203,747),Vector2(218,43),show_relationships,false,overlay)
	button("Back to life",Vector2(986,747),Vector2(249,43),close_overlay,true,overlay)
	_restore_family_scroll(scroll,diagram.get_node("FamilyCard_"+focus_id),scroll_position)

func _restore_family_scroll(scroll:ScrollContainer,focused:Control,position:Vector2i) -> void:
	await get_tree().process_frame
	if not is_instance_valid(scroll) or not is_instance_valid(focused):return
	scroll.scroll_horizontal=position.x;scroll.scroll_vertical=position.y
	scroll.ensure_control_visible(focused)

func _family_generation_levels(links:Array,parents:Array) -> Dictionary:
	var pairs:Array=[]
	for edge:Dictionary in links:
		if str(edge.role) in ["partners","siblings"]:pairs.append([str(edge.a),str(edge.b)])
	for first:int in range(parents.size()):
		for second:int in range(first+1,parents.size()):
			if str(parents[first].b)==str(parents[second].b):pairs.append([str(parents[first].a),str(parents[second].a)])
	var accepted:Array=[]
	var levels:Dictionary=_family_level_trial(parents,[])
	for pair:Array in pairs:
		var trial:Array=accepted.duplicate(true);trial.append(pair)
		var candidate:Dictionary=_family_level_trial(parents,trial)
		# Unusual cross-generation partnerships can contradict a shared row.
		# Keep true ancestry readable rather than forcing a cyclic layout.
		if not candidate.is_empty():accepted=trial;levels=candidate
	return levels

func _family_level_trial(parents:Array,aligned:Array) -> Dictionary:
	var result:Dictionary={}
	for member:Dictionary in household.members:result[str(member.id)]=0
	for iteration:int in range(household.members.size()*2+1):
		var changed:bool=false
		for edge:Dictionary in parents:
			var next:int=int(result[str(edge.a)])+1
			if int(result[str(edge.b)])<next:result[str(edge.b)]=next;changed=true
		for pair:Array in aligned:
			var level:int=maxi(int(result[str(pair[0])]),int(result[str(pair[1])]))
			for id:String in pair:
				if int(result[id])<level:result[id]=level;changed=true
		if not changed:return result
	return {}
