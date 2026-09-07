extends Node

const P = preload("res://scripts/palette.gd")
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
var profile: Dictionary = {"name":"Mara Vale","frame":0,"hair":1,"skin_color":"d9a17d","hair_color":"54382a","top_color":"c97c66","bottom_color":"eadfc9","body_scale":1.0,"height_scale":1.0,"traits":["Creative","Outgoing","Foodie"],"aspiration":"Maker"}
var selected_lot: int = 0
var path: PackedVector3Array = []
var path_index: int = 0
var walk_only: bool = false
var pending_action: Dictionary = {}
var time_label: Label
var funds_label: Label
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
var skill_labels: Dictionary = {}
var relationship_labels: Dictionary = {}
var career_labels: Dictionary = {}
var goal_labels: Dictionary = {}

func _ready() -> void:
	DisplayServer.window_set_title("JustLife — make room for your story")
	world=LifeWorld.new()
	world.name="World"
	add_child(world)
	sim=LifeSim.new()
	sim.name="Simulation"
	add_child(sim)
	sim.notice.connect(show_notice)
	sim.action_started.connect(on_action_started)
	sim.action_finished.connect(on_action_finished)
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
	show_creator()
	if "--smoke-live" in OS.get_cmdline_user_args():start_household()
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--capture="):capture_milestone.call_deferred(argument.get_slice("=",1))

func capture_milestone(which:String) -> void:
	if which in ["live","build"]:start_household();sim.set_speed(0)
	if which=="build":set_build_mode(true)
	if which=="lots":show_lot_selection()
	await get_tree().create_timer(2.0).timeout
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://art/screenshots")
	get_viewport().get_texture().get_image().save_png("res://art/screenshots/%s.png" % which)
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
	var l=text_label(value,p,s,font_size,color,false,parent)
	l.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	l.vertical_alignment=VERTICAL_ALIGNMENT_TOP
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
	return b

func line(p:Vector2,s:Vector2,parent:Node=ui) -> void:
	var n=ColorRect.new()
	n.color=P.LINE
	n.mouse_filter=Control.MOUSE_FILTER_IGNORE
	rect(n,p,s,parent)

func small_caps(value:String,p:Vector2,s:Vector2=Vector2(260,24),parent:Node=ui) -> Label:
	return text_label(value.to_upper(),p,s,11,P.MUTED,false,parent)

func clear_ui() -> void:
	for child in ui.get_children():child.free()
	need_bars.clear();need_values.clear()
	skill_labels.clear();relationship_labels.clear();career_labels.clear();goal_labels.clear()
	queue_box=null;time_label=null;funds_label=null;mood_label=null;action_label=null;action_bar=null
	last_queue=""
	close_overlay()

func logo(p:Vector2=Vector2(34,25)) -> void:
	# Original sprout emblem, with a quiet editorial wordmark.
	var mark=Control.new()
	mark.mouse_filter=Control.MOUSE_FILTER_IGNORE
	rect(mark,p,Vector2(34,38))
	mark.draw.connect(func():
		mark.draw_line(Vector2(17,31),Vector2(17,15),P.TEAL,2,true)
		mark.draw_colored_polygon(PackedVector2Array([Vector2(17,20),Vector2(5,17),Vector2(4,6),Vector2(14,9)]),P.TEAL)
		mark.draw_colored_polygon(PackedVector2Array([Vector2(18,15),Vector2(20,4),Vector2(31,3),Vector2(28,13)]),P.TEAL))
	text_label("JustLife",p+Vector2(43,-3),Vector2(190,44),33,P.INK,true)

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
	button("Continue saved life",Vector2(1215,28),Vector2(193,40),load_game)
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
	small_caps("Personality  ·  choose three",Vector2(60,406))
	var trait_names=["Creative","Outgoing","Active","Bookworm","Foodie","Neat"]
	var descriptions={"Creative":"Build creative skill faster. Making art lifts your mood.","Outgoing":"Social connections come naturally; loneliness matters more.","Active":"Energy lasts longer and naps take less time.","Bookworm":"Reading and studying are especially rewarding.","Foodie":"Cooking is more enjoyable and builds skill faster.","Neat":"Hygiene lasts longer and showers lift your mood."}
	for i in range(trait_names.size()):
		var tr:String=trait_names[i]
		var b=button(tr,Vector2(58+(i%2)*142,440+(i/2)*44),Vector2(134,35),func():toggle_trait(tr),profile.traits.has(tr))
		b.tooltip_text=descriptions[tr]
	small_caps("Life aspiration",Vector2(60,584))
	var op=OptionButton.new()
	for a in ["Maker","Connected","Successful","Balanced"]:op.add_item(a)
	op.select(["Maker","Connected","Successful","Balanced"].find(profile.aspiration))
	rect(op,Vector2(58,617),Vector2(276,42))
	op.item_selected.connect(func(i:int):profile.aspiration=["Maker","Connected","Successful","Balanced"][i];draw_creator())
	var asp_desc={"Maker":"Fill your life with things you create.","Connected":"Turn new faces into lasting friendships.","Successful":"Build your skills. Make a living you love.","Balanced":"Find joy in the everyday."}
	paragraph(asp_desc[profile.aspiration],Vector2(60,674),Vector2(275,36),13)
	# The character is the focal point, with all styling choices on one side.
	card(Vector2(1080,126),Vector2(322,614),Color("f9faf3"))
	button("Look",Vector2(1100,144),Vector2(138,40),func():creator_tab="Look";draw_creator(),creator_tab=="Look")
	button("Wardrobe",Vector2(1246,144),Vector2(138,40),func():creator_tab="Wardrobe";draw_creator(),creator_tab=="Wardrobe")
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
		small_caps("Build",Vector2(1102,586))
		var slider=HSlider.new()
		slider.min_value=.85;slider.max_value=1.15;slider.step=.01;slider.value=profile.body_scale
		rect(slider,Vector2(1105,623),Vector2(270,30))
		slider.value_changed.connect(set_body_scale)
		text_label("Slender",Vector2(1102,658),Vector2(120,25),12,P.MUTED)
		var l=text_label("Fuller",Vector2(1290,658),Vector2(85,25),12,P.MUTED);l.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT
	else:
		small_caps("Everyday collection",Vector2(1102,204))
		text_label("Easy, everyday style",Vector2(1100,236),Vector2(290,36),24,P.INK,true)
		paragraph("Soft tailoring, natural textures, and colors that feel like you.",Vector2(1102,282),Vector2(269,55),15)
		small_caps("Top",Vector2(1102,364))
		swatches(["c97c66","417a71","efeadb","7195b3","bd9b68","3d4145"],"top_color",Vector2(1100,400),40,7)
		small_caps("Trousers",Vector2(1102,470))
		swatches(["eadfc9","3e5955","51697c","493e37","b88a72","292f32"],"bottom_color",Vector2(1100,507),40,7)
		paragraph("Choose a complete palette",Vector2(1102,581),Vector2(275,25),13)
		button("Coastal",Vector2(1100,621),Vector2(88,41),func():profile.top_color="efeadb";profile.bottom_color="51697c";refresh_preview())
		button("Earthy",Vector2(1197,621),Vector2(88,41),func():profile.top_color="c97c66";profile.bottom_color="eadfc9";refresh_preview())
		button("Sage",Vector2(1294,621),Vector2(88,41),func():profile.top_color="417a71";profile.bottom_color="493e37";refresh_preview())
	button("↶",Vector2(626,726),Vector2(48,42),func():creator_spin-=.5;preview.rotation.y=creator_spin)
	button("↷",Vector2(769,726),Vector2(48,42),func():creator_spin+=.5;preview.rotation.y=creator_spin)
	text_label("DRAG TO ROTATE",Vector2(657,782),Vector2(160,24),11,P.MUTED)
	text_label("Your story starts with you.",Vector2(42,802),Vector2(370,42),24,P.INK,true)
	button("Surprise me",Vector2(867,815),Vector2(160,50),randomize_person)
	button("Find my home  →",Vector2(1080,802),Vector2(322,62),show_lot_selection,true)

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
		var s=P.panel(Color(c),int(diameter/2),P.TEAL if profile[key]==c else Color("ffffff"),3)
		b.add_theme_stylebox_override("normal",s)
		b.add_theme_stylebox_override("hover",P.panel(Color(c).lightened(.1),int(diameter/2),P.TEAL,3))
		if profile[key]==c:b.text="•";b.add_theme_color_override("font_color",Color.WHITE)

func refresh_preview() -> void:
	preview.scale=Vector3.ONE
	preview.configure(profile)
	draw_creator()

func set_body_scale(value:float) -> void:
	profile.body_scale=clampf(value,.85,1.15)
	if is_instance_valid(preview):
		preview.scale=Vector3.ONE
		preview.visual.scale=Vector3(profile.body_scale,clampf(float(profile.height_scale),.93,1.08),profile.body_scale)

func randomize_person() -> void:
	profile.name=["Mara Vale","Alex Rowan","Ellis Park","Jules Rivera","Noa Ellis","Robin Ash"][randi()%6]
	profile.frame=randi()%2;profile.hair=randi()%3
	profile.skin_color=["f2d1b1","e7b98f","d9a17d","b77e58","925c40","613e30"][randi()%6]
	profile.hair_color=["2a2420","54382a","89563a","c2a16b","dfccb0"][randi()%5]
	profile.top_color=["c97c66","417a71","efeadb","7195b3"][randi()%4]
	profile.bottom_color=["eadfc9","3e5955","51697c","493e37"][randi()%4]
	refresh_preview()

func show_lot_selection() -> void:
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

func start_household() -> void:
	profile.erase("world_state")
	floor_color="cfa97e"
	sim.new_household(profile)
	if selected_lot==2:sim.funds=4500
	setup_live(LifeCatalog.starter_layout(selected_lot))
	show_notice("Welcome home, %s. Click a furnishing to choose what happens next." % str(profile.name).split(" ")[0])

func setup_live(layout:Array) -> void:
	close_overlay(false)
	pending_move.clear()
	route_generation+=1
	mode="live"
	if stage:stage.visible=false
	world.create_home(layout)
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
	player=spawn_actor("player",sim.character,Vector3(-.7,.16,2.8))
	player.set_selected(true)
	spawn_actor("maya",{"name":"Maya Chen","frame":0,"hair":2,"skin_color":"b77e58","hair_color":"2a2420","top_color":"417a71","bottom_color":"eadfc9"},Vector3(7.0,.16,3.2))
	spawn_actor("leo",{"name":"Leo Morgan","frame":1,"hair":0,"skin_color":"e7b98f","hair_color":"89563a","top_color":"7195b3","bottom_color":"493e37"},Vector3(-7,.16,4.5))
	path.clear();path_index=0;walk_only=false
	pending_action={}
	_restore_world_state(sim.character.get("world_state",{}))
	sim.register_targets(world.simulation_targets())
	build_undo.clear()
	_sync_actor_sound()
	draw_live()
	var current=sim.get_current_action()
	if not current.is_empty():on_action_started(current)

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
	if id!="player":
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
	for skill_name:String in skill_labels:
		skill_labels[skill_name].text="Level %d" % int(sim.skills[skill_name].level)
	for id:String in relationship_labels:
		var relationship:Dictionary=sim.relationships[id]
		relationship_labels[id].text="%s · %d" % [relationship.status,int(relationship.friendship)]
	if not career_labels.is_empty():
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
	card(Vector2(20,718),Vector2(1400,162),P.WHITE,18)
	line(Vector2(304,738),Vector2(1,121))
	line(Vector2(964,738),Vector2(1,121))
	card(Vector2(36,739),Vector2(73,90),P.PALE,12)
	# A 3D portrait uses the same customized model as the live actor.
	model_thumbnail("character",Vector2(36,732),Vector2(73,105),true)
	text_label(str(sim.character.name),Vector2(123,739),Vector2(174,31),22,P.INK,true)
	mood_label=text_label("Feeling inspired",Vector2(124,778),Vector2(165,26),14,P.TEAL)
	text_label("Young adult",Vector2(124,810),Vector2(160,25),12,P.MUTED)
	button("Center",Vector2(42,841),Vector2(111,27),func():world.camera_target=player.position;world.update_camera())
	button("Wishes",Vector2(165,841),Vector2(111,27),show_wishes)
	text_label("TODAY IS YOURS",Vector2(327,738),Vector2(220,23),11,P.MUTED)
	action_label=text_label("Enjoying a moment",Vector2(326,770),Vector2(286,36),21,P.INK,true)
	action_bar=ProgressBar.new()
	action_bar.show_percentage=false
	rect(action_bar,Vector2(328,818),Vector2(274,7))
	button("Cancel action",Vector2(326,842),Vector2(144,26),cancel_current_action)
	time_label=text_label(sim.get_clock_text(),Vector2(652,736),Vector2(280,33),18,P.INK)
	time_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	var speeds=[0,1,3,8]
	var names=["Ⅱ","▶","▶▶","▶▶▶"]
	for i in range(4):button(names[i],Vector2(659+i*67,781),Vector2(59,43),func():set_game_speed(speeds[i]))
	text_label("SPACE  PAUSE   ·   1 / 2 / 3  SPEED",Vector2(663,841),Vector2(269,25),11,P.MUTED)
	for i in range(4):
		var tab_name:String=["Needs","Skills","People","Career"][i]
		button(tab_name,Vector2(984+i*103,732),Vector2(96,33),func():panel_tab=tab_name;draw_live(),panel_tab==tab_name)
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
		for i in range(5):
			var key:String=sim.skills.keys()[i]
			var p=Vector2(989+(i%2)*208,781+(i/2)*28)
			text_label(key.capitalize(),p,Vector2(130,22),12)
			skill_labels[key]=text_label("Level %d" % sim.skills[key].level,p+Vector2(137,0),Vector2(62,22),12,P.TEAL)
	elif panel_tab=="People":
		for i in range(2):
			var id:String=["maya","leo"][i]
			var rel:Dictionary=sim.relationships[id]
			button(rel.name,Vector2(988+i*208,781),Vector2(192,35),func():focus_neighbor(id))
			relationship_labels[id]=text_label("%s  ·  %d" % [rel.status,rel.friendship],Vector2(991+i*208,825),Vector2(194,25),12,P.MUTED)
	else:
		career_labels["title"]=text_label(sim.career.title,Vector2(989,778),Vector2(235,28),19,P.INK,true)
		career_labels["details"]=text_label("Level %d  ·  §%d / shift" % [sim.career.level,sim.career.salary],Vector2(990,814),Vector2(234,27),12,P.MUTED)
		career_labels["work"]=button("Work a shift",Vector2(1241,779),Vector2(149,37),func():queue_nearest("desk","job"),true)
		button("Find a job",Vector2(1241,824),Vector2(149,32),show_careers)

func draw_queue() -> void:
	queue_box=HBoxContainer.new()
	queue_box.add_theme_constant_override("separation",8)
	rect(queue_box,Vector2(326,657),Vector2(830,49))
	queue_box.mouse_filter=Control.MOUSE_FILTER_IGNORE

func refresh_hud() -> void:
	if mode not in ["live","build"]:return
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
		action_label.text="Enjoying a moment" if action.is_empty() else (("Walking to " if action.phase=="approach" else "")+str(action.label))
		action_label.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
	if action_bar:action_bar.value=0 if action.is_empty() else float(action.progress)*100
	if queue_box:
		var key:String=str(sim.action_queue.map(func(a:Dictionary):return a.id+":"+str(a.phase)))
		if key!=last_queue:
			last_queue=key
			for c in queue_box.get_children():c.free()
			for i in range(sim.action_queue.size()):
				var a:Dictionary=sim.action_queue[i]
				var b=Button.new();b.text=str(a.label)+"   ×";b.custom_minimum_size=Vector2(110,40);b.add_theme_font_size_override("font_size",12)
				b.tooltip_text="Click to cancel this activity"
				b.pressed.connect(func():cancel_current_action(i))
				queue_box.add_child(b)

func commas(value:int) -> String:
	var s=str(value)
	var out=""
	for i in range(s.length()):
		if i>0 and (s.length()-i)%3==0:out+="," 
		out+=s[i]
	return out

func model_thumbnail(kind:String,p:Vector2,s:Vector2,portrait:bool=false,parent:Node=ui) -> void:
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
		model=LifeActor.new();root.add_child(model);model.configure(sim.character)
	else:
		model=load("res://assets/models/%s.glb" % kind).instantiate();root.add_child(model)
	var cam=Camera3D.new();root.add_child(cam)
	cam.projection=Camera3D.PROJECTION_ORTHOGONAL
	if portrait:
		cam.size=.71;cam.position=Vector3(.06,1.54,3);cam.look_at(Vector3(0,1.45,0))
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
	if not is_instance_valid(world.house):return
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
	if mode=="live":show_interactions(item,screen)

func close_overlay(restore_speed:bool=true) -> void:
	if is_instance_valid(overlay):
		for child in overlay.get_children():child.free()
	overlay_open=false
	if overlay_pauses_sim:
		overlay_pauses_sim=false
		if restore_speed and is_instance_valid(sim) and mode in ["live","build"]:
			sim.set_speed(0 if mode=="build" else pause_before_menu)
		_sync_actor_sound()

func _begin_pause_overlay() -> void:
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
	var actions:Array=sim.get_actions_for(item.kind)
	var h:float=91+actions.size()*55
	var pos=Vector2(clampf(screen.x-145,300,1096),clampf(screen.y-70,99,700-h))
	card(pos,Vector2(310,h),P.WHITE,17,overlay)
	text_label(item.label,pos+Vector2(19,14),Vector2(270,37),24,P.INK,true,overlay)
	small_caps("What would you like to do?",pos+Vector2(20,54),Vector2(270,21),overlay)
	for i in range(actions.size()):
		var a:Dictionary=actions[i]
		var label_text:String=a.label
		if int(a.cost)>0:label_text+="   §%d" % a.cost
		var b=button(label_text,pos+Vector2(14,85+i*55),Vector2(282,44),func():queue_interaction(item,a.id);close_overlay(),false,overlay)
		b.add_theme_font_size_override("font_size",13)
		b.tooltip_text=a.description+"  ·  %d min" % a.duration
		b.disabled=not a.available
	if actions.is_empty():paragraph("A little detail that makes this place home.",pos+Vector2(18,70),Vector2(274,47),13,P.MUTED,overlay)

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
	if not is_instance_valid(sim) or not is_instance_valid(world.house):return
	var targets:Array=world.simulation_targets()
	var by_id:Dictionary={}
	for target:Dictionary in targets:by_id[str(target.id)]=target
	sim.register_targets(targets)
	reconciling_targets=true
	for index:int in range(sim.action_queue.size()-1,-1,-1):
		var action:Dictionary=sim.action_queue[index]
		var target_id:String=str(action.target_id)
		if not pending_move.is_empty() and target_id==str(pending_move.entry.id):continue
		if not by_id.has(target_id):
			sim.cancel_action(index)
			continue
		var destination:Vector3=by_id[target_id].position
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
	route_generation+=1
	path.clear()
	path_index=0
	walk_only=false
	pending_action={}

func cancel_current_action(index:int=0) -> void:
	# The next action's start signal is synchronous; clear the OLD route first.
	if index==0:_clear_motion()
	sim.cancel_action(index)
	refresh_hud()

func queue_interaction(item:Dictionary,id:String) -> void:
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
	pending_action=action
	if not pending_move.is_empty() and str(action.target_id)==str(pending_move.entry.id):return
	path=world.path_to(player.position,action.target_position)
	if path.is_empty():
		show_notice("The way is blocked. Try moving a furnishing.")
		_cancel_blocked_action.call_deferred(route_generation,action)
	refresh_hud()

func _cancel_blocked_action(generation:int,action:Dictionary) -> void:
	if loading_game or generation!=route_generation:return
	if sim.get_current_action()==action:cancel_current_action()

func on_action_finished(action:Dictionary) -> void:
	if is_instance_valid(player):
		player.speech({"cook":"Delicious!","read":"One more chapter…","paint":"Made something lovely.","friendly":"Lovely to meet you!","joke":"Ha!","deep_talk":"I understand.","water":"Looking greener.","work":"All done!"}.get(action.id,"That feels better."))
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
	card(Vector2(490,191),Vector2(460,500),P.WHITE,24,overlay)
	small_caps("Take a little pause",Vector2(526,212),Vector2(385,25),overlay)
	text_label("Life at your pace.",Vector2(523,246),Vector2(390,57),37,P.INK,true,overlay)
	var actions=[
		["Resume",close_overlay],
		["Save this life",func():save_game();close_overlay()],
		["Continue saved life",func():load_game()],
		["How to play",func():show_help()],
		["Sound: "+("on" if sound_enabled else "off"),func():set_sound(not sound_enabled);show_menu()],
		["Create another Lifelet",func():show_creator()]
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
	text_label(sim.character.name,Vector2(521,234),Vector2(390,61),37,P.INK,true,overlay)
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
	button("Back to life",Vector2(524,649),Vector2(389,48),close_overlay,true,overlay)

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

func save_game() -> void:
	if mode not in ["live","build"]:show_notice("Move into a home to save your life.");return
	cancel_placement()
	sim.character["world_state"]={"player":[player.position.x,player.position.y,player.position.z],"player_rotation":player.rotation.y,"camera":[world.camera_target.x,world.camera_target.y,world.camera_target.z],"angle":world.camera_angle,"elevation":world.camera_elevation,"zoom":world.camera.size,"floor":floor_color,"lot":selected_lot,"cutaway":world.cutaway,"sound":sound_enabled}
	# Store the user's live speed, not a temporary menu/build pause.
	var current_speed:int=sim.speed
	sim.speed=speed_before_build if mode=="build" else (pause_before_menu if overlay_pauses_sim else current_speed)
	var saved:bool=sim.save_game(world.serialize_items())
	sim.speed=current_speed
	if saved:show_notice("Your life is saved. See you right here.")
	else:show_notice("The save could not be written.")

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

func load_game() -> void:
	loading_game=true
	route_generation+=1
	var result:Dictionary=sim.load_game()
	if not result.ok:
		loading_game=false
		show_notice(str(result.error));return
	profile=sim.character.duplicate(true)
	floor_color="cfa97e"
	setup_live(result.world)
	loading_game=false
	_refresh_sim_targets()
	_sync_actor_sound()
	show_notice("Welcome back, %s." % sim.character.name)

func setup_audio() -> void:
	audio_player=AudioStreamPlayer.new();add_child(audio_player)
	if FileAccess.file_exists("res://assets/audio/soft_click.wav"):
		audio_player.stream=AudioStreamWAV.load_from_file("res://assets/audio/soft_click.wav")
	audio_player.volume_db=0
	ambience_player=AudioStreamPlayer.new();add_child(ambience_player)
	if FileAccess.file_exists("res://assets/audio/ambience_garden.wav"):
		var stream:AudioStreamWAV=AudioStreamWAV.load_from_file("res://assets/audio/ambience_garden.wav")
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
		# A manual walk is a player order, so autonomy waits until arrival.
		var autonomous:bool=sim.autonomy
		if walk_only:sim.autonomy=false
		sim.tick(delta)
		sim.autonomy=autonomous
		world.daylight(sim.minutes)
		var moving:bool=_advance_movement(delta)
		var action:Dictionary=sim.get_current_action()
		var action_id:String="" if action.is_empty() or action.phase!="active" else action.id
		if action_id!="":
			var target_node:Node3D=null
			var item:Dictionary=_find_item(str(action.target_id))
			if not item.is_empty():target_node=item.node
			elif world.actors.has(str(action.target_id)):target_node=world.actors[str(action.target_id)]
			if is_instance_valid(target_node):
				var direction:Vector3=target_node.position-player.position
				player.rotation.y=lerp_angle(player.rotation.y,atan2(direction.x,direction.z),minf(delta*6,1))
		player.animate(delta,float(sim.speed),moving,action_id)
		for id:String in ["maya","leo"]:
			var actor:LifeActor=world.actors[id]
			var talking:bool=not action.is_empty() and str(action.target_id)==id and action_id!=""
			if talking:
				var direction:Vector3=player.position-actor.position
				actor.rotation.y=lerp_angle(actor.rotation.y,atan2(direction.x,direction.z),minf(delta*4,1))
			actor.animate(delta,float(sim.speed),false,action_id if talking else "")
		hud_refresh+=delta
		if hud_refresh>.25:hud_refresh=0;refresh_hud()
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
		if should_begin:sim.begin_current_action()
	return was_moving

func _unhandled_input(event:InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if get_viewport().gui_get_focus_owner() is LineEdit:return
		if event.keycode==KEY_ESCAPE:
			if overlay_open:close_overlay()
			elif mode=="build" and _has_placement_tool():cancel_placement()
			elif mode in ["live","build"]:show_menu()
			get_viewport().set_input_as_handled()
			return
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
				KEY_F9:load_game()
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
