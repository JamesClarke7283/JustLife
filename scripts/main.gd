extends Node

const P = preload("res://scripts/palette.gd")
const Land = preload("res://scripts/land.gd")
const Properties = preload("res://scripts/properties.gd")
const LifeGroceries = preload("res://scripts/groceries.gd")
const Variants = preload("res://scripts/catalog_variants.gd")
const LifeLog = preload("res://scripts/logger.gd")
const LifeWantsManager = preload("res://scripts/wants_manager.gd")
const CREATOR_FACE_GROUPS: Dictionary = {
	"Shape":["face_round","jaw_strong","chin_length","face_length"],
	"Eyes":["eye_spacing","brow_arch"],
	"Nose":["nose_wide","nose_length","nose_bridge"],
	"Mouth":["lip_fullness","mouth_width"],
}
const CREATOR_FACE_LABELS: Dictionary = {
	"face_round":"Cheek fullness", "jaw_strong":"Jaw definition", "chin_length":"Chin length", "face_length":"Face length",
	"eye_spacing":"Eye spacing", "brow_arch":"Brow arch", "nose_wide":"Nose width", "nose_length":"Nose length",
	"nose_bridge":"Nose bridge", "lip_fullness":"Lip fullness", "mouth_width":"Mouth width",
}
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
var creator_face_group: String = "Shape"
var creator_outfit_category: String = "everyday"
var _studio_render_restore: Dictionary = {}
var creator_purpose: String = ""
var cover_beat: Node3D
var cover_beat_time: float = 0.0
var panel_tab: String = "Needs"
var catalog_category: String = "All"
var catalog_search: String = ""
var portrait_stale: bool = false
var profile: Dictionary = {"name":"Mara Vale","frame":0,"hair":1,"skin_color":"d9a17d","hair_color":"54382a","top_color":"c97c66","bottom_color":"eadfc9","shoe_color":"e9e4d9","body_scale":1.0,"height_scale":1.0,"outfit":0,"eye_color":"547365","traits":["Creative","Outgoing","Foodie"],"aspiration":"Maker"}
var selected_lot: int = 0
## Which Lifelets are ticked to come on the trip being planned, and where they
## are going.
var party_selection: Array[String] = []
var _pending_trip_destination: String = ""
## The homes this household owns, which one it lives in, and the insurance on
## each. Rides the save beside the land and the layouts.
var properties: Dictionary = Properties.fresh()
var path: PackedVector3Array = []
var path_index: int = 0
var walk_only: bool = false
var pending_action: Dictionary = {}
var time_label: Label
var funds_label: Label
var age_label: Label
var mood_label: Label
var mood_ring: Panel
var mood_pill: Panel
var moodlet_tiles: Array = []
var selection_marker: MeshInstance3D
var marker_time: float = 0.0
var action_label: Label
var action_context: Label
var action_bar: ProgressBar
var cancel_action_button: Button
var household_chips: Dictionary = {}
## The household's pets in the life box, by pet id, so a chip can be refreshed in
## place the way a person's chip is.
var pet_chips: Dictionary = {}
var away_phases: Dictionary = {}
var need_bars: Dictionary = {}
var need_fills: Dictionary = {}
var need_values: Dictionary = {}
var pregnancy_meter: ProgressBar
var pregnancy_label: Label
## The temporary-energy pool's own card, bar and value. Its colour is
## deliberately darker than the energy need's teal so the two never read as the
## same meter; the pool itself lives on the simulation.
var second_wind_card: Panel
var second_wind_bar: ProgressBar
var second_wind_value: Label
const SECOND_WIND_COLOR: Color = Color("2f6b57")
var queue_box: HBoxContainer
var queue_caption: Label
var queue_toggle: Button
var queue_collapsed: bool = false
var last_queue: String = ""
var notice_label: Label
var notice_card: Panel
var notice_time: float = 0
var hud_refresh: float = 0
var elapsed: float = 0
var creator_spin: float = -.16
var camera_drag: bool = false
var camera_pan_button: int = MOUSE_BUTTON_NONE
var creator_drag: bool = false
var last_mouse: Vector2
var pause_before_menu: int = 1
var speed_before_build: int = 1
var overlay_pauses_sim: bool = false
var overlay_open: bool = false
## Raised while a button inside the Wishes panel redraws that panel. The panel
## keeps the simulation running, so a press rebuilds it from the current whims
## rather than leaving the player reading cards whose slot has already refreshed.
var wishes_redrawing: bool = false
var selected_item: Dictionary = {}
var build_undo: Array = []
var build_transactions:LifeBuildTransactions
var audio_player: AudioStreamPlayer
var chime_player: AudioStreamPlayer
var ambience_player: AudioStreamPlayer
var music_player: AudioStreamPlayer
var sound_enabled: bool = true
var music_enabled: bool = true
## Automatic saving. The player chooses the interval; the default is five
## minutes. `autosave_wait` counts real seconds of play since the last write, and
## only advances while the household is actually living, so a paused menu or a
## build session never spends the interval.
const AUTOSAVE_CHOICES: Array[int] = [0, 1, 2, 5, 10, 15, 20, 30, 45, 60]
const AUTOSAVE_DEFAULT_MINUTES: int = 5
var autosave_minutes: int = AUTOSAVE_DEFAULT_MINUTES
var autosave_wait: float = 0.0
## The slot an autosave writes to, so repeated writes update one file instead of
## filling the picker. Empty means no autosave slot has been made yet.
var autosave_slot: String = ""
## Pets: the live bodies the household owns. `pets` is the shop view; the saved
## record lives in the household, so a load always rebuilds the same animals.
var pet_shop: LifePetShopFlow
var pet_actors: Dictionary = {}
var pet_arrivals: Dictionary = {}
## Each pet's own errand: which need sent it, where it is going and how far it
## has got. The controller owns this, like the household's own routes.
## The pet the camera and HUD are following, or "" while a Lifelet is. A pet is
## not controllable in the way a person is, so this only changes what is watched.
var selected_pet_id: String = ""

var pet_errands: Dictionary = {}
## The point at which a pet stops what it is doing and sees to itself. Below a
## third of a need, so an animal acts on a genuine want rather than topping up.
const PET_NEED_URGENT: float = 35.0
var pending_move: Dictionary = {}
## The catalogue kind a food-truck order has already paid for. Placement reads
## it and clears it, so the delivery cannot be charged twice and a placement the
## player abandons simply drops the flag with the ghost.
var pending_delivery: Dictionary = {}
## The paint a car will be bought in, chosen from the swatch row before the
## ghost is placed. It is not the car's own record: `on_placement` copies it
## onto the entry, which is where the colour really lives.
var pending_paint: String = ""
var loading_game: bool = false
var floor_color: String = "cfa97e"
var reconciling_targets: bool = false
var route_generation: int = 0
var load_epoch: int = 0
var walk_destination: Vector3 = Vector3.ZERO
var waiting_for_target: bool = false
var wait_started: float = -1.0
var wait_review: float = -1.0
var wait_destination: Vector3 = Vector3.INF
var resume_activity: bool = false
var skill_labels: Dictionary = {}
var skill_bars: Dictionary = {}
var skill_progress_labels: Dictionary = {}
var relationship_labels: Dictionary = {}
var career_labels: Dictionary = {}
var goal_labels: Dictionary = {}
var current_venue: String = "home"
var home_layout: Array = []
var venue_layouts: Dictionary = {}
var stories_button: Button
var speed_buttons: Dictionary = {}
var live_floor_buttons: Dictionary = {}
var menus:LifeMenus
var has_active_game:bool=false
var active_save_id:String=""
var active_save_name:String=""
var menu_resume_speed:int=1
var menu_game_mode:String="live"
var save_preview:Image
var build_quote:Label
var build_quote_card:Panel
var roof_visibility_button:Button
var release_probe:RefCounted
var creator_family_links:Array=[]
var activity_bubbles:Control
var sanitation_flow:LifeSanitationFlow
## The weekly food truck. It owns the van's schedule and the shop's money; the
## controller only asks it to present the van and routes its click to the shop.
var food_truck:LifeFoodTruck
## The game day the controller last reconciled the van against, so the arrival
## notice fires once when the clock turns the day over and not every frame.
var _truck_seen_day:int=-1
## Whether the van's solid band is currently in the navigation graph, so the
## graph is rebuilt on a real arrival or departure and never on a quiet frame.
var _truck_parked:bool=false
var meal_flow:LifeMealFlow
var household_flow:LifeHouseholdFlow
var idle_space:RefCounted
var guest_status_card:Control
## The doorstep card: somebody has rung the bell and is waiting outside.
var bell_status_card:Control
var bell_status_text:Label
var bell_let_in_button:Button
var bell_turn_away_button:Button
var guest_status_text:Label
var guest_welcome_button:Button
var residents:LifeResidents
var adoption_flow:LifeAdoptionFlow
var traversal:LifeTraversal

## Every service a live game owns, created in one place. `_ready` calls this, and
## so does any component fixture that needs a controller whose availability,
## routing and meal rules behave as they do in play: hand-building `world` and
## `household` and leaving the rest unset produces a controller shape that never
## exists at runtime, so its answers prove nothing about the real game.
func setup_services() -> void:
	world=LifeWorld.new()
	world.name="World"
	add_child(world)
	meal_flow=LifeMealFlow.new();meal_flow.app=self;add_child(meal_flow)
	household_flow=LifeHouseholdFlow.new(self);add_child(household_flow)
	sanitation_flow=LifeSanitationFlow.new();sanitation_flow.app=self;add_child(sanitation_flow)
	# The weekly food truck owns its own schedule, wallet charge and delivery
	# receipt; the controller owns only the van's presentation in the world.
	food_truck=LifeFoodTruck.new(self);add_child(food_truck)
	idle_space=preload("res://scripts/idle_space.gd").new();idle_space.app=self
	adoption_flow=LifeAdoptionFlow.new(self)
	pet_shop=LifePetShopFlow.new(self)
	residents=LifeResidents.new(self)
	traversal=LifeTraversal.new(self)
	household_profiles=[profile]
	household=LifeHousehold.new()
	household.name="Household"
	add_child(household)
	# Cover bought through the phone is written through to the house's own
	# record, so the property panel and the sims never disagree.
	household.insurance_changed.connect(_on_insurance_changed)
	household.extras_provider=household_flow.get_state
	# The controller owns the world's layout, so it is the one that can say
	# where the household's post boxes stand.
	household.post_box_provider=func()->Array[String]:
		var out:Array[String]=[]
		if not is_instance_valid(world):return out
		for item:Dictionary in world.items:
			if str(item.get("kind",""))=="post_box":out.append(str(item.id))
		return out
	household.set_home_value_provider(home_value)
	household.extras_restore_provider=household_flow.restore
	household.new_household(household_profiles)
	sim=household.selected()
	build_transactions=LifeBuildTransactions.new(self)


func _ready() -> void:
	LifeLog.initialize()
	LifeLog.info("LIFECYCLE", "JustLife engine started", {"cmdline": OS.get_cmdline_args()})
	# Check before opening the menu: its save listing can initialize storage.
	if "--release-check" in OS.get_cmdline_user_args() and not preload("res://scripts/release_probe.gd").isolated_environment():
		set_process(false)
		printerr("Release check requires isolated XDG_DATA_HOME and JUSTLIFE_DATA_DIR before game startup.")
		get_tree().quit(2)
		return
	get_tree().set_auto_accept_quit(false)
	DisplayServer.window_set_title("JustLife — make room for your story")
	setup_services()
	_connect_live_nodes()
	var canvas=CanvasLayer.new()
	canvas.name="Interface"
	add_child(canvas)
	activity_bubbles=preload("res://scripts/activity_bubbles.gd").new()
	activity_bubbles.name="ActivityBubbles"
	activity_bubbles.app=self
	canvas.add_child(activity_bubbles)
	ui=Control.new()
	ui.name="UI"
	# The layers are positioned and scaled by _fit_interface, so they anchor at
	# the canvas origin; a full-rect preset would let the viewport override the
	# size after _ready and fight the fit.
	ui.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	ui.mouse_filter=Control.MOUSE_FILTER_IGNORE
	ui.theme=P.theme()
	canvas.add_child(ui)
	overlay=Control.new()
	overlay.name="Overlay"
	overlay.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	overlay.mouse_filter=Control.MOUSE_FILTER_IGNORE
	overlay.theme=ui.theme
	canvas.add_child(overlay)
	# Every screen positions its controls in a 1440x900 design space. The
	# project stretches with `canvas_items`/`expand`, so a wider or taller window
	# grows the canvas and would otherwise leave the whole interface pinned to the
	# top-left. Fit and centre the design instead, so the HUD reads as intended at
	# any window shape.
	get_viewport().size_changed.connect(_fit_interface)
	_fit_interface()
	setup_audio()
	menus=LifeMenus.new(self)
	show_main_menu()
	if "--smoke-live" in OS.get_cmdline_user_args():start_household()
	if "--release-check" in OS.get_cmdline_user_args():
		release_probe=preload("res://scripts/release_probe.gd").new()
		release_probe.run.call_deferred(self)
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--capture="):capture_milestone.call_deferred(argument.get_slice("=",1))

## The interface is authored in a 1440x900 design space, but the project
## stretches with `canvas_items`/`expand`, so a widescreen window produces a
## canvas that is 900 units tall and wider than 1440. Anchoring the whole design
## to the left would leave a dead strip beside the HUD, so the design keeps its
## authored height and the screens that span the canvas read `interface_width()`.
func _fit_interface() -> void:
	if not is_instance_valid(ui) or not is_instance_valid(overlay):return
	var window: Vector2 = get_viewport().get_visible_rect().size
	# Height is the tight axis on every supported window shape; scale the design
	# so it always fills the canvas vertically, then centre it horizontally.
	var scale_factor: float = window.y / 900.0
	var fitted: Vector2 = Vector2(1440.0, 900.0) * scale_factor
	var margin: Vector2 = Vector2((window.x - fitted.x) * .5, 0.0)
	for layer: Control in [ui, overlay]:
		layer.position = margin
		layer.size = Vector2(1440.0, 900.0)
		layer.scale = Vector2(scale_factor, scale_factor)
		layer.pivot_offset = Vector2.ZERO
	if is_instance_valid(activity_bubbles):
		activity_bubbles.scale = Vector2(scale_factor, scale_factor)

## Width available to the interface, in the design space the screens author in.
## A 16:10 canvas reports 1440; a widescreen canvas reports the real width so a
## spanning screen can reach both edges instead of hugging the left.
func interface_width() -> float:
	if not is_instance_valid(ui):return 1440.0
	var window: Vector2 = get_viewport().get_visible_rect().size
	return maxf(1440.0, window.x / maxf(ui.scale.x, 0.0001))

## The full visible interface rect, for scrims and click-outside backdrops.
func interface_size() -> Vector2:
	return Vector2(interface_width(),900.0)

## A layer child's canvas position is `position + local * scale`, so the local
## coordinate for a desired canvas x is `(x - position) / scale`. Screens that
## must reach the real canvas edges use this instead of assuming the design's
## origin sits at canvas zero.
func interface_local_x(canvas_x: float) -> float:
	if not is_instance_valid(ui):return canvas_x
	return (canvas_x - ui.position.x) / maxf(ui.scale.x, 0.0001)

func _connect_live_nodes() -> void:
	household.physical_snapshot_provider=_physical_snapshot_context
	for member:Dictionary in household.members:
		member.sim.autonomy_activity_available=_activity_available_for_member.bind(str(member.id))
		member.sim.social_witness=Callable(self,"_members_can_see_each_other")
	var sender:LifeHousehold=household
	household.notice.connect(show_notice)
	household.member_action_started.connect(_member_action_started)
	household.member_action_finished.connect(_member_action_finished)
	household.baby_born.connect(_on_baby_born)
	household.member_passed.connect(_on_member_passed)
	household.pregnancy_began.connect(_on_pregnancy_began)
	household.member_age_changed.connect(func(id: String, _previous: String, _current: String): _refresh_aged_member.call_deferred(id,load_epoch,sender))
	world.object_clicked.connect(on_object_clicked)
	# The world owns the ghost's own style and size, so the check describes the
	# object actually being placed rather than a default of its family.
	world.placement_reach_check=func(kind:String,p:Vector3,angle:float)->bool:
		if not is_instance_valid(build_transactions):return true
		var data:Dictionary=LifeCatalog.get_item(kind)
		var proposal:Dictionary={"id":"ghost","kind":kind,"x":p.x,"z":p.z,"rotation":angle,"level":world.view_level}
		proposal.merge(Variants.record(data,world.placement_style,"",world.placement_size),true)
		var proposed:Array=world.serialize_items();proposed.append(proposal)
		return build_transactions.furnishing_error(proposed).is_empty()
	world.ground_clicked.connect(on_ground_clicked)
	world.placement_requested.connect(on_placement)
	world.construction_requested.connect(on_construction)

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
	if is_instance_valid(player):print("JUSTLIFE_PACKED_AUDIO voice=",player._voice_streams.size()," ambience=",is_instance_valid(ambience_player.stream)," click=",is_instance_valid(audio_player.stream)," music=",is_instance_valid(music_player.stream))
	print("JUSTLIFE_CAPTURE ",which)
	# Free the scene, then quit from a timer signal so the shutdown does not
	# depend on this freed object's coroutine: the settle lets the audio and
	# rendering servers release their streams and textures cleanly.
	if is_instance_valid(audio_player):audio_player.stop()
	if is_instance_valid(ambience_player):ambience_player.stop()
	if is_instance_valid(music_player):music_player.stop()
	var settle:SceneTreeTimer=get_tree().create_timer(0.25)
	var tree:=get_tree()
	settle.timeout.connect(func():tree.quit())
	queue_free()
	await settle.timeout

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
	if serif:l.add_theme_font_override("font",P.display_font())
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

func icon_button(icon_name:String,hint:String,p:Vector2,s:Vector2,callback:Callable) -> Button:
	var b:=button("",p,s,callback)
	b.icon=load("res://assets/ui/"+icon_name+".svg")
	b.icon_alignment=HORIZONTAL_ALIGNMENT_CENTER
	b.add_theme_constant_override("icon_max_width",24)
	for state:String in ["normal","hover","focus"]:
		b.add_theme_color_override("icon_"+state+"_color",P.INK)
	for state:String in ["pressed","hover_pressed"]:
		b.add_theme_color_override("icon_"+state+"_color",P.WHITE)
	b.tooltip_text=hint
	b.accessibility_name=hint
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
	_clear_pointer_drags()
	for child in ui.get_children():
		ui.remove_child(child)
		child.queue_free()
	need_bars.clear();need_values.clear();need_fills.clear();speed_buttons.clear();live_floor_buttons.clear()
	household_chips.clear();pet_chips.clear();cancel_action_button=null
	skill_labels.clear();skill_bars.clear();skill_progress_labels.clear();relationship_labels.clear();career_labels.clear();goal_labels.clear()
	queue_box=null;queue_card=null;queue_scroll=null;queue_caption=null;queue_toggle=null;time_label=null;funds_label=null;mood_label=null;action_label=null;action_context=null;action_bar=null;mood_ring=null;mood_pill=null;moodlet_tiles.clear()
	pregnancy_meter=null;pregnancy_label=null
	build_quote=null;build_quote_card=null;roof_visibility_button=null
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
	# The three-step strip sits on the 3D sky, so it keeps a soft card behind it.
	card(Vector2(448,22),Vector2(622,62),Color("f9faf2",.88),14)
	var names=["01  Create a Lifelet","02  Find a home","03  Live your story"]
	for i in range(3):
		var c=P.TEAL if i==current else P.INK
		text_label(names[i],Vector2(465+i*190,34),Vector2(185,28),14,c)
		if i==current:line(Vector2(466+i*190,73),Vector2(145,2))

func show_creator(purpose:String="") -> void:
	# The purpose is set by this entry alone, so a pending birth can never leak
	# the baby creator into the new-game, milestone or recovery paths.
	creator_purpose=purpose
	close_overlay(false)
	cancel_placement()
	mode="creator"
	_set_studio_render_quality(true)
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
	# The outdoor sun's 60 m shadow map cannot resolve millimetre facial detail.
	# A local portrait key gives the face clean shadows; live daylight restores
	# the sun's energy when the studio is removed.
	world.sun.light_energy=0.0
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
	var key=SpotLight3D.new()
	key.name="PortraitKey"
	stage.add_child(key)
	key.position=Vector3(-1.6,2.6,2.8)
	key.look_at(Vector3(0,1.15,0),Vector3.UP)
	key.light_color=Color("fff5eb")
	key.light_energy=3.0
	key.light_size=.18
	key.spot_range=6.0
	key.spot_angle=47.0
	key.spot_attenuation=1.0
	key.shadow_enabled=true
	key.shadow_bias=.05
	key.shadow_normal_bias=1.0
	var fill=OmniLight3D.new()
	fill.name="PortraitFill"
	fill.position=Vector3(1.8,1.7,2.0)
	fill.light_color=Color("e9f1ff")
	fill.light_energy=.8
	fill.omni_range=6.0
	stage.add_child(fill)
	var rim=OmniLight3D.new()
	rim.name="PortraitRim"
	rim.position=Vector3(.5,2.2,-1.6)
	rim.light_color=Color("fff2dc")
	rim.light_energy=.8
	rim.light_specular=.2
	rim.omni_range=5.0
	stage.add_child(rim)
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
	# The character is the focal point, with all styling choices on one side. The
	# card is sized after the tab is drawn, from the controls that tab really
	# built: the Look tab's rows of hairstyles and the Style tab's necklace row
	# both used to run past a fixed 614-px card.
	var card_top:float=126.0
	var card_bottom:float=126.0+614.0
	var card_panel:=card(Vector2(1080,card_top),Vector2(322,614),Color("f9faf3"))
	# The card spans x 1080..1402 and the canvas ends at 1440, so four tabs have
	# 20 px of left margin and 4 px between them: a wider pitch ran the last tab
	# (Style) off the canvas, clipping it where a player could not press it.
	for i in range(4):
		var tab_name:String=["Look","Face","Wardrobe","Style"][i]
		var tab_button=button(tab_name,Vector2(1100+i*74,144),Vector2(70,40),func():set_creator_tab(tab_name),creator_tab==tab_name)
		compact_button(tab_button);tab_button.size=Vector2(70,40)
	if creator_tab=="Look":
		# Every section stacks from this cursor: label, then its content at
		# label+6, then the next section at content end + gap. The fixed offsets
		# the sections used before put the ten authored hairstyles' third row
		# (Braids and Topknot) straight across the hair-colour label and swatches,
		# and ran the row off the card's edge. Wrapping palettes now push the
		# sections under them down, and the cursor's end is what the card must
		# contain.
		var label_height:float=16.0
		var section_gap:float=8.0
		var y:float=194.0
		var content_top:float=y+label_height+6.0
		small_caps("Gender",Vector2(1102,y),Vector2(180,label_height))
		var gender_group := ButtonGroup.new()
		# Keep the existing saved model choice: 0 = female, 1 = male.
		for i in range(2):
			var gender_name:String=["Female","Male"][i]
			var selected:bool=int(profile.get("frame",0))==i
			var choice=button(gender_name,Vector2(1100+i*146,content_top),Vector2(137,36),func():set_creator_gender(i),selected)
			choice.name="Creator"+gender_name
			choice.toggle_mode=true
			choice.button_group=gender_group
			choice.set_pressed_no_signal(selected)
			choice.tooltip_text="Create a %s Lifelet" % gender_name.to_lower()
		y=content_top+36.0+section_gap
		small_caps("Skin tone",Vector2(1102,y),Vector2(180,label_height))
		# Offer exactly the authored generator palettes. The creator previously
		# showed 6 of the 12 skin tones, 6 of the 10 hair colours and 5 of the 8
		# eye colours the model and Surprise me already use, so a hand-built
		# Lifelet could not reach half the looks the game ships. `swatches` wraps
		# inside the card and reports the height it really used.
		content_top=y+label_height+6.0
		y=content_top+swatches(preload("res://scripts/character_identity.gd").SKIN_TONES,"skin_color",Vector2(1100,content_top),26,6)+section_gap
		small_caps("Hairstyle",Vector2(1102,y),Vector2(180,label_height))
		var hair_names:Array=["Crop","Bob","Curls","Pony","Long","Buzz","Waves","Bun","Braids","Topknot"]
		var hair_tips:Array=["A relaxed swept crop","A softly sculpted bob","Natural rounded curls","A swept-back ponytail","Long layered lengths","A close buzz cut","Loose shoulder-length waves","A sleek twisted updo","Two front plaits with ties","A high gathered topknot"]
		# Only styles this stage's model authors are offered, so a choice is
		# never silently replaced when the Lifelet is created.
		var offered_hair:Array=range(hair_names.size())
		if is_instance_valid(preview) and preview.has_method("authored_hair_styles"):
			offered_hair=preview.authored_hair_styles()
		# Four columns of 72 px stepping 75, so the last one ends at 1397 inside
		# the card's 1402 edge. As 73-px columns stepping 80 from x=1100 the row
		# reached x=1413, past the card and over the canvas margin.
		var style_columns:int=4
		var style_stride:float=75.0
		var style_size:Vector2=Vector2(72.0,30.0)
		content_top=y+label_height+6.0
		for slot:int in range(offered_hair.size()):
			var i:int=int(offered_hair[slot])
			var b=button(hair_names[i],Vector2(1100.0+float(slot%style_columns)*style_stride,content_top+floori(float(slot)/float(style_columns))*36.0),style_size,func():profile.hair=i;refresh_preview(),int(profile.get("hair",0))==i)
			compact_button(b);b.size=style_size
			b.tooltip_text=hair_tips[i]
		var style_rows:int=ceilf(float(offered_hair.size())/float(style_columns))
		y=content_top+float(style_rows)*36.0-6.0+section_gap
		small_caps("Hair color",Vector2(1102,y),Vector2(180,label_height))
		var hair_colors:Array=preload("res://scripts/character_identity.gd").HAIR_COLORS.duplicate()
		# An elder's own released palette is the one the game greys them toward;
		# offering it keeps every colour the model can actually show.
		if str(profile.get("age_stage",""))=="elder":
			hair_colors.append_array(preload("res://scripts/character_identity.gd").ELDER_HAIR_COLORS)
		content_top=y+label_height+6.0
		y=content_top+swatches(hair_colors,"hair_color",Vector2(1100,content_top),26,6)+section_gap
		small_caps("Eyes",Vector2(1102,y),Vector2(180,label_height))
		content_top=y+label_height+6.0
		y=content_top+swatches(preload("res://scripts/character_identity.gd").EYE_COLORS,"eye_color",Vector2(1100,content_top),24,8)+section_gap
		# `height_scale` and `shoe_color` already ride every save, the resident
		# catalogue, and LifeActor's model scale and shoe recolour, but the creator
		# offered no way to set height at all. These controls write exactly the
		# fields the generator and the saved profiles already use, so nothing
		# downstream changes and old saves with no such keys keep their defaults.
		# Build and Height sit side by side: each is a two-number scale, so they
		# share one row instead of stacking two labels and two tracks.
		small_caps("Build",Vector2(1102,y),Vector2(134,label_height))
		small_caps("Height",Vector2(1243,y),Vector2(134,label_height))
		content_top=y+label_height+6.0
		var slider=HSlider.new()
		slider.name="CreatorBuild"
		slider.min_value=.85;slider.max_value=1.15;slider.step=.01;slider.value=profile.body_scale
		slider.tooltip_text="Body width, from Slender to Fuller."
		rect(slider,Vector2(1103,content_top),Vector2(134,24))
		slider.value_changed.connect(set_body_scale)
		var height_slider=HSlider.new()
		height_slider.name="CreatorHeight"
		height_slider.min_value=.93;height_slider.max_value=1.08;height_slider.step=.01
		height_slider.value=clampf(float(profile.get("height_scale",1.0)),.93,1.08)
		height_slider.tooltip_text="How tall this Lifelet stands, from Shorter to Taller. Everyone keeps their own height."
		rect(height_slider,Vector2(1244,content_top),Vector2(134,24))
		height_slider.value_changed.connect(set_height_scale)
		y=content_top+24.0+section_gap
		small_caps("Shoes",Vector2(1102,y),Vector2(180,label_height))
		content_top=y+label_height+6.0
		card_bottom=content_top+swatches(["e9e4d9","3b302c","573c37","39444f","a26d56","292f32"],"shoe_color",Vector2(1100,content_top),26,6)+22.0
	elif creator_tab=="Style":
		# Same stacking rule as the Look tab: each section's rows decide where the
		# next one starts, because the male and female makeup sets are different
		# lengths. The "none" option sits beside its label rather than under the
		# swatches, which keeps the tallest (female) set clear of the card's own
		# bottom edge and of the "Find my home" button beneath the card.
		var style_y:float=306.0
		text_label("Makeup and jewelry",Vector2(1100,207),Vector2(287,37),25,P.INK,true)
		var limited:bool=LifeCharacterIdentity.is_male(profile)
		paragraph("Try anything on and see it on your Lifelet straight away. %s" % ("A limited men's set is offered." if limited else "The full set is offered; men wear jewelry too."),Vector2(1102,250),Vector2(274,46),14)
		small_caps("Lip colour",Vector2(1102,style_y),Vector2(140,24))
		var no_lips=button("No lip colour",Vector2(1222,style_y),Vector2(153,24),func():profile.makeup_lips=LifeCharacterIdentity.MAKEUP_NONE;refresh_preview())
		compact_button(no_lips);no_lips.size=Vector2(153,24)
		no_lips.tooltip_text="Wear a bare lip."
		style_y+=26.0
		style_y+=swatches(LifeCharacterIdentity.makeup_lip_colors(profile),"makeup_lips",Vector2(1100,style_y),26,6)+8.0
		# Any shade, not only the suggested ones: the picker opens a real colour
		# wheel and writes back the chosen hex, which the face then wears.
		makeup_colour_row(Vector2(1100,style_y),"makeup_lips","Pick any lip shade")
		style_y+=32.0+16.0
		small_caps("Eye look",Vector2(1102,style_y),Vector2(140,24))
		var no_eyes=button("No eye look",Vector2(1222,style_y),Vector2(153,24),func():profile.makeup_eyes=LifeCharacterIdentity.MAKEUP_NONE;refresh_preview())
		compact_button(no_eyes);no_eyes.size=Vector2(153,24)
		no_eyes.tooltip_text="Wear a bare eye."
		style_y+=26.0
		style_y+=swatches(LifeCharacterIdentity.makeup_eye_colors(profile),"makeup_eyes",Vector2(1100,style_y),26,6)+8.0
		makeup_colour_row(Vector2(1100,style_y),"makeup_eyes","Pick any eyeliner shade")
		style_y+=32.0+16.0
		small_caps("Earrings",Vector2(1102,style_y),Vector2(180,18))
		var ear_styles:Array=["none","stud","hoop","chain"]
		var ear_labels:Array=["None","Stud","Hoop","Chain"]
		for i:int in range(ear_styles.size()):
			var style:String=str(ear_styles[i])
			var b=button(str(ear_labels[i]),Vector2(1100+i*70,style_y+22),Vector2(64,30),func():profile.jewelry_ears=style;refresh_preview(),str(profile.get("jewelry_ears","none"))==style)
			compact_button(b);b.size=Vector2(64,30)
		style_y+=22.0+30.0+16.0
		small_caps("Jewelry metal",Vector2(1102,style_y),Vector2(180,18))
		style_y+=24.0
		style_y+=swatches(LifeCharacterIdentity.JEWELRY_METALS,"jewelry_metal",Vector2(1100,style_y),26,6)+16.0
		var neck=button("Necklace: on" if bool(profile.get("jewelry_neck",false)) else "Necklace: off",Vector2(1100,style_y),Vector2(275,34),func():profile.jewelry_neck=not bool(profile.get("jewelry_neck",false));refresh_preview())
		neck.tooltip_text="A chain at the throat. Anyone may wear one."
		card_bottom=style_y+34.0+18.0
	elif creator_tab=="Face":
		text_label("A face of your own",Vector2(1100,207),Vector2(287,37),25,P.INK,true)
		paragraph("Shape their features. Turn your Lifelet to see every angle.",Vector2(1102,264),Vector2(274,52),15)
		var groups:Array=CREATOR_FACE_GROUPS.keys()
		for group_index:int in groups.size():
			var group_name:String=groups[group_index]
			var group_button=button(group_name,Vector2(1100+group_index*71,322),Vector2(66,36),func():set_creator_face_group(group_name),creator_face_group==group_name)
			group_button.add_theme_font_size_override("font_size",13)
		var features:Array=CREATOR_FACE_GROUPS[creator_face_group]
		for i in range(features.size()):
			var key:String=features[i]
			var label_text:String=CREATOR_FACE_LABELS[key]
			small_caps(label_text,Vector2(1102,379+i*66),Vector2(260,21))
			var slider=HSlider.new();slider.min_value=-1 if key in LifeActor.SIGNED_IDENTITY_KEYS else 0;slider.max_value=1;slider.step=.01;slider.value=float(profile.get(key,0))
			slider.tooltip_text=label_text
			slider.name="FaceFeature_"+key
			rect(slider,Vector2(1105,402+i*66),Vector2(271,28))
			slider.value_changed.connect(func(value:float):profile[key]=value;preview.set_face_feature(key,value))
		button("Reset face",Vector2(1102,681),Vector2(275,40),func():
			for key:String in LifeActor.IDENTITY_KEYS:profile[key]=0.0
			refresh_preview())
		card_bottom=681.0+40.0+18.0
	else:
		LifeCharacterIdentity.ensure_wardrobe(profile)
		creator_outfit_category=LifeCharacterIdentity.normalize_category(profile.get("outfit_category",creator_outfit_category))
		small_caps("Outfit type",Vector2(1102,200))
		var categories:Array=LifeCharacterIdentity.OUTFIT_CATEGORIES
		for i in range(categories.size()):
			var category:String=str(categories[i])
			var category_button=button(LifeCharacterIdentity.category_label(category),Vector2(1100+(i%3)*97,226+floori(float(i)/3)*36),Vector2(89,32),func():set_creator_outfit_category(category),creator_outfit_category==category)
			compact_button(category_button);category_button.size=Vector2(89,32)
			category_button.tooltip_text=str(LifeCharacterIdentity.OUTFIT_CATEGORY_BLURBS.get(category,""))
		text_label(LifeCharacterIdentity.category_label(creator_outfit_category)+" look",Vector2(1100,300),Vector2(290,30),22,P.INK,true)
		paragraph(str(LifeCharacterIdentity.OUTFIT_CATEGORY_BLURBS.get(creator_outfit_category,"")),Vector2(1102,330),Vector2(269,36),14)
		small_caps("Top",Vector2(1102,368))
		var outfit_names:Array=LifeCharacterIdentity.get_category_tops(creator_outfit_category)
		var outfit_tips:Array=LifeCharacterIdentity.get_category_top_tips(creator_outfit_category)
		var bottom_names:Array=LifeCharacterIdentity.get_category_bottoms(creator_outfit_category)
		var offered_outfits:Array=range(outfit_names.size())
		var offered_bottoms:Array=range(bottom_names.size())
		if is_instance_valid(preview) and preview.has_method("authored_wardrobe"):
			var wardrobe:Dictionary=preview.authored_wardrobe()
			if profile.get("age_stage", "adult") == "baby":
				offered_outfits=wardrobe.outfits
				offered_bottoms=wardrobe.bottoms
		for slot:int in range(offered_outfits.size()):
			var i:int=int(offered_outfits[slot])
			var b=button(outfit_names[i],Vector2(1100+(slot%3)*97,392+floori(float(slot)/3)*36),Vector2(89,32),func():set_creator_clothing("outfit",i),int(profile.get("outfit",0))==i)
			compact_button(b);b.size=Vector2(89,32)
			b.tooltip_text=outfit_tips[i]
		small_caps("Bottoms",Vector2(1102,470))
		for slot:int in range(offered_bottoms.size()):
			var i:int=int(offered_bottoms[slot])
			button(bottom_names[i],Vector2(1100+slot*146,494),Vector2(137,32),func():set_creator_clothing("bottom",i),int(profile.get("bottom",0))==i)
		var palettes:Dictionary=LifeCharacterIdentity.get_category_palettes(creator_outfit_category)
		small_caps("Top color",Vector2(1102,524))
		swatches(palettes.top,"top_color",Vector2(1100,546),28,8)
		small_caps("Bottom color",Vector2(1102,582))
		swatches(palettes.bottom,"bottom_color",Vector2(1100,604),28,8)
		small_caps("Shoes",Vector2(1102,640))
		swatches(palettes.shoes,"shoe_color",Vector2(1100,662),26,8)
		var set_preset=func(top_col:String,bot_col:String,shoe_col:String=""):
			profile.top_color=top_col
			profile.bottom_color=bot_col
			if not shoe_col.is_empty():
				profile.shoe_color=shoe_col
			LifeCharacterIdentity.store_current(profile)
			refresh_preview()
		small_caps("Complete palette",Vector2(1102,696))
		var b_coastal=button("Coastal",Vector2(1100,720),Vector2(88,32),func():set_preset.call("efeadb","51697c","e9e4d9"))
		compact_button(b_coastal);b_coastal.size=Vector2(88,32)
		var b_earthy=button("Earthy",Vector2(1197,720),Vector2(88,32),func():set_preset.call("c97c66","eadfc9","49382e"))
		compact_button(b_earthy);b_earthy.size=Vector2(88,32)
		var b_sage=button("Sage",Vector2(1294,720),Vector2(88,32),func():set_preset.call("417a71","493e37","32292a"))
		compact_button(b_sage);b_sage.size=Vector2(88,32)
		card_bottom=720.0+32.0+18.0
	# The card is resized once the tab is drawn, from the y that tab's own last
	# control reached. Its child order is untouched, so it still draws behind the
	# tab buttons and controls created after it.
	if is_instance_valid(card_panel):
		card_panel.size=Vector2(322.0,maxf(614.0,card_bottom-card_top))
	icon_button("rotate_left","Turn Lifelet left",Vector2(626,726),Vector2(48,42),func():creator_spin-=.5;preview.rotation.y=creator_spin).name="CreatorTurnLeft"
	icon_button("rotate_right","Turn Lifelet right",Vector2(769,726),Vector2(48,42),func():creator_spin+=.5;preview.rotation.y=creator_spin).name="CreatorTurnRight"
	text_label("DRAG TO ROTATE",Vector2(380,782),Vector2(160,24),11,P.MUTED)
	if creator_purpose=="baby":
		# The baby's creator is the ordinary creator with the baby stage seeded:
		# same drawing, same control handlers, one confirm instead of a move-in.
		small_caps("A new arrival",Vector2(42,743),Vector2(162,24))
		text_label("Everything here belongs to the new baby. Name them and make the face your own — or roll the dice for a surprise.",Vector2(42,772),Vector2(1000,32),15,P.MUTED)
		var dice=button("Roll the dice",Vector2(742,802),Vector2(322,62),roll_baby_dice)
		dice.tooltip_text="Randomise the baby's name and gender, keeping the rest of the family's look."
		button("Welcome the baby  →",Vector2(1080,802),Vector2(322,62),confirm_baby_creator,true)
		return
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

func try_for_baby(item:Dictionary) -> void:
	var result:Dictionary=household.begin_try_for_baby(bound_member_id,str(item.id))
	if not bool(result.ok):
		show_notice(str(result.get("error","Try for Baby is unavailable right now.")))
		return
	_start_cover_beat(str(result.session_id),str(item.id))
	refresh_hud()
	show_notice("The covers rustle over the pair. Stay close for the whole moment, or click the bed again to stop.")

func _start_cover_beat(token:String,bed_id:String) -> void:
	_end_cover_beat()
	var item:Dictionary=_find_item(bed_id)
	if item.is_empty():return
	# Original cover overlay: a rounded quilt drawn procedurally over the pair
	# (the bed model's own linen stays put), ruffling and swelling as the beat
	# runs. The session token ties the animation to the live household state.
	var node:=Node3D.new()
	node.name="BabyCoverBeat"
	item.node.add_child(node)
	var mesh:=MeshInstance3D.new()
	var shape:=SphereMesh.new()
	shape.radius=.62
	shape.height=1.24
	shape.radial_segments=18
	shape.rings=8
	mesh.mesh=shape
	mesh.name="Quilt"
	var material:=StandardMaterial3D.new()
	material.albedo_color=Color("ded6e8")
	material.roughness=.95
	mesh.material_override=material
	node.add_child(mesh)
	cover_beat=node
	cover_beat_time=0.0
	cover_beat.set_meta("token",token)

func _end_cover_beat() -> void:
	if is_instance_valid(cover_beat):cover_beat.queue_free()
	cover_beat=null
	cover_beat_time=0.0

func _update_cover_beat(delta:float) -> void:
	if not is_instance_valid(cover_beat):
		return
	if mode!="live" or household.cooperation_state(str(cover_beat.get_meta("token",""))).is_empty():
		_end_cover_beat()
		return
	cover_beat_time+=delta*clampf(float(household.speed),0.0,3.0)
	var swell:float=.5+.5*sin(cover_beat_time*2.2)
	var mesh:MeshInstance3D=cover_beat.get_node_or_null("Quilt")
	if is_instance_valid(mesh):
		mesh.scale=Vector3(1.0+.06*swell,1.0+.10*swell,1.0+.05*swell)
		mesh.rotation.z=.05*sin(cover_beat_time*3.4)
	var item:Dictionary=_find_item(str(cover_beat.get_parent().name))
	if not item.is_empty():
		var data:Dictionary=LifeCatalog.get_item(str(item.kind))
		cover_beat.position=Vector3(0,float(data.get("height",1.4))*.62,0)

## The player can let the dice settle the two things they were going to pick:
## the baby's name and gender. The rest of the child (face, skin, hair) keeps
## the family's inherited look that the conception roll already chose.
func roll_baby_dice() -> void:
	if creator_purpose!="baby":return
	var rng:=RandomNumberGenerator.new()
	rng.randomize()
	var rolled:Dictionary=LifeBabyPlan.roll({},{},rng.randi_range(1,LifeBabyPlan.MAX_BIRTHS))
	profile.name=str(rolled.get("name","Wren Vale"))
	var gender:String=str(rolled.get("gender","female"))
	profile["gender"]=gender
	profile.frame=LifeBabyPlan.frame_for(gender)
	refresh_preview()
	show_notice("The dice decided: %s, a %s." % [str(profile.name),gender])

func confirm_baby_creator() -> void:
	if creator_purpose!="baby" or household.members.size()>=LifeHousehold.MAX_MEMBERS:
		show_notice("Your household already has eight Lifelets.");return
	_ensure_baby_surname(profile)
	if str(profile.name).strip_edges().is_empty():profile.name="Wren Vale"
	var spawn:Vector3=world.lot_exit_position(household.members.size())
	var destination:Vector3=world.lot_return_position(household.members.size())
	# Capture the live home before the baby joins so a rebuild can never reverse
	# purchases, walls or an upper storey made since the last save.
	if current_venue=="home":home_layout=world.serialize_items()
	else:venue_layouts[current_venue]=world.serialize_items()
	var result:Dictionary=household.commit_baby(profile,spawn,destination,world.serialize_items())
	if not bool(result.ok):
		show_notice(str(result.error));return
	var id:String=str(result.child)
	var baby:LifeSim=household.member_sim(id)
	# Match adoption: spawn into the live home instead of tearing the world down
	# with setup_live, which locked the welcome-home path and could drop the baby.
	creator_purpose=""
	creator_family_links=[]
	household_profiles.clear()
	for member:Dictionary in household.members:
		household_profiles.append(member.sim.character.duplicate(true))
	spawn_actor(id,baby.character,spawn)
	motion_states[id]=_empty_motion()
	household.stock_baby_supplies()
	household.register_targets(world.simulation_targets())
	_member_action_started(id,baby.get_current_action())
	close_overlay(false)
	draw_live()
	show_notice("Welcome to the family, %s. Select their household portrait to help them settle in." % str(baby.character.name).split(" ")[0])

func show_baby_creator() -> void:
	# The baby creator is the ordinary creator with the baby stage seeded, so
	# the drawing and every control handler are the same code path.
	var baby:Dictionary=household.pending_baby_profile()
	if baby.is_empty():return
	# Keep the parents in the household profile list so canceling the creator
	# cannot leave the live bar pointing at a draft-only list.
	var kept:Array=[]
	for member:Dictionary in household.members:
		kept.append(member.sim.character.duplicate(true))
	creator_purpose="baby"
	creator_tab="Look"
	creator_family_links=[]
	profile=baby.duplicate(true)
	profile["age_stage"]="baby"
	profile["life_stage"]="minor"
	_ensure_baby_surname(profile)
	creator_index=0
	household_profiles=kept
	household_profiles.append(profile)
	creator_index=household_profiles.size()-1
	show_creator("baby")

## Keep or restore the primary parent's surname on a newborn name field.
func _ensure_baby_surname(baby:Dictionary) -> void:
	var family:String=LifeBabyPlan.surname_of(baby)
	if not family.is_empty():return
	var mother:LifeSim=household.member_sim(str(household.pregnancy.get("mother_id","")))
	var father:LifeSim=household.member_sim(str(household.pregnancy.get("father_id","")))
	# The mother carries the pregnancy, so her surname is the primary default when
	# the rolled name has none or the player cleared it to a first name alone.
	if is_instance_valid(mother):family=LifeBabyPlan.surname_of(mother.character)
	if family.is_empty() and is_instance_valid(father):family=LifeBabyPlan.surname_of(father.character)
	if family.is_empty():return
	var first:String=str(baby.get("name","")).strip_edges().split(" ",false)[0] if not str(baby.get("name","")).strip_edges().is_empty() else "Wren"
	baby["name"]=first+" "+family

func set_creator_tab(value:String) -> void:
	creator_tab=value
	frame_creator_camera()
	draw_creator()

## The gender buttons set both the authored model frame and the declared gender,
## so a chosen gender is what the household, the save and the model all agree on
## (a stale declared gender otherwise wins over the frame, ignoring the click).
func set_creator_gender(frame:int) -> void:
	profile.frame=frame
	profile["gender"]="male" if frame==1 else "female"
	refresh_preview()

func set_creator_face_group(value:String) -> void:
	if not CREATOR_FACE_GROUPS.has(value):return
	creator_face_group=value
	draw_creator()

func set_creator_outfit_category(category:String) -> void:
	LifeCharacterIdentity.ensure_wardrobe(profile)
	profile.outfit_category=creator_outfit_category
	LifeCharacterIdentity.store_current(profile)
	creator_outfit_category=LifeCharacterIdentity.normalize_category(category)
	LifeCharacterIdentity.apply_category(profile,creator_outfit_category)
	refresh_preview()

func set_creator_clothing(key:String,value:Variant) -> void:
	profile[key]=value
	profile.outfit_category=creator_outfit_category
	LifeCharacterIdentity.store_current(profile)
	refresh_preview()

func _set_studio_render_quality(enabled:bool) -> void:
	var viewport:Viewport=get_viewport()
	if enabled:
		if _studio_render_restore.is_empty():
			_studio_render_restore={"msaa":viewport.msaa_3d,"scale":viewport.scaling_3d_scale}
		# At portrait distance reduced-resolution specular edges shimmer. The
		# single-character studio can render native pixels and cleaner edges;
		# restore the player's world settings when returning to a busy lot.
		viewport.msaa_3d=maxi(viewport.msaa_3d,Viewport.MSAA_4X)
		viewport.scaling_3d_scale=maxf(viewport.scaling_3d_scale,1.0)
	elif not _studio_render_restore.is_empty():
		viewport.msaa_3d=int(_studio_render_restore.msaa)
		viewport.scaling_3d_scale=float(_studio_render_restore.scale)
		_studio_render_restore.clear()

func toggle_trait(tr:String) -> void:
	if profile.traits.has(tr):profile.traits.erase(tr)
	elif profile.traits.size()<3:profile.traits.append(tr)
	else:show_notice("Choose up to three traits. Deselect one to try another.")
	draw_creator()

## A swatch's own panel style. `LifePalette.panel()` sets 18 px content margins,
## which would force a small swatch button to a 36 px minimum and make adjacent
## swatches overlap. A swatch carries no text, so its margins are zero.
func swatch_panel(color: Color, radius: int, border: Color, width: int) -> StyleBoxFlat:
	var s: StyleBoxFlat = P.panel(color, radius, border, width)
	s.content_margin_left = 0.0
	s.content_margin_right = 0.0
	s.content_margin_top = 0.0
	s.content_margin_bottom = 0.0
	return s

## Draw a colour row that wraps inside the creator card. `width` is the usable
## inner width, so a longer authored palette stays on screen instead of running
## past the card edge. The stride always exceeds the swatch, so neighbours never
## overlap and every swatch stays clickable. Returns the height the rows really
## occupy, so a caller can stack the next section under however many rows the
## authored palette wrapped into instead of guessing a fixed offset.
func swatches(colors:Array,key:String,p:Vector2,diameter:float,gap:float,width:float=276.0) -> float:
	return color_row(colors,str(profile.get(key,"")),p,diameter,gap,width,func(c:String):
		profile[key]=c
		if key in ["top_color","bottom_color","shoe_color"]:
			LifeCharacterIdentity.store_current(profile)
		refresh_preview())

## A row of round colour choices. `chosen` marks the current one, and `on_pick`
## receives the hex shade the player tapped. Every colour row in the game — the
## Lifelet's clothes, a pet's coat, a car's paint — is this row, so a new palette
## is a list of shades and a callback rather than another layout.
func color_row(colors:Array,chosen:String,p:Vector2,diameter:float,gap:float,width:float,on_pick:Callable) -> float:
	var stride:float=diameter+gap
	var per_row:int=maxi(1,int((width+gap)/stride))
	var rows:int=maxi(1,ceili(float(colors.size())/float(per_row)))
	for i in range(colors.size()):
		var c:String=colors[i]
		var at:Vector2=p+Vector2((i%per_row)*stride,floori(float(i)/per_row)*stride)
		var b=button("",at,Vector2(diameter,diameter),on_pick.bind(c))
		b.tooltip_text=c
		b.custom_minimum_size=Vector2.ZERO
		var selected:bool=chosen==c
		b.add_theme_stylebox_override("normal",swatch_panel(Color(c),int(diameter/2),P.TEAL if selected else Color("ffffff"),3))
		b.add_theme_stylebox_override("hover",swatch_panel(Color(c).lightened(.1),int(diameter/2),P.TEAL,3))
		b.add_theme_stylebox_override("pressed",swatch_panel(Color(c).darkened(.1),int(diameter/2),P.TEAL,3))
		b.add_theme_stylebox_override("focus",swatch_panel(Color.TRANSPARENT,int(diameter/2),P.GOLD,2))
		# The size must be set after the styles, because the previous style's
		# minimum would otherwise win and stretch the swatch.
		b.size=Vector2(diameter,diameter)
		if selected:
			b.text="•"
			# The dot stays legible on a pale swatch as well as a dark one.
			b.add_theme_color_override("font_color",Color.WHITE if Color(c).get_luminance()<.55 else P.INK)
	return float(rows-1)*stride+diameter

func refresh_preview() -> void:
	if not is_instance_valid(preview):return
	preview.scale=Vector3.ONE
	preview.configure(profile)
	frame_creator_camera()
	draw_creator()

## A row that opens a real colour picker for a makeup shade. The authored
## palette beside it is a set of suggestions, not a limit: whatever shade the
## player mixes is written straight into the look and worn on the face.
func makeup_colour_row(p:Vector2,key:String,hint:String) -> void:
	# The preview chip shows the shade currently worn, or the picker's own
	# default while nothing is on, so the row always reads as this Lifelet's lip
	# or eye colour rather than an empty box.
	var worn:String=LifeCharacterIdentity.makeup_value(profile,key)
	var shown:Color=Color.from_string(worn,Color("b5453f")) if worn!=LifeCharacterIdentity.MAKEUP_NONE else Color("b5453f")
	var chip:=Panel.new()
	chip.mouse_filter=Control.MOUSE_FILTER_IGNORE
	chip.add_theme_stylebox_override("panel",swatch_panel(shown,10,P.TEAL if worn!=LifeCharacterIdentity.MAKEUP_NONE else Color("ffffff"),3))
	rect(chip,p,Vector2(22,22))
	var picker=button("Custom colour…",p+Vector2(30,0),Vector2(245,26),func():open_makeup_picker(key,hint))
	picker.tooltip_text=hint+" — choose exactly the shade you want."

## Open the engine's own colour picker over the creator. It writes back the
## chosen shade and repaints the Lifelet, so a custom lipstick or eyeliner is
## seen on the face before the Lifelet is made. It lives on the overlay layer,
## because a live colour change redraws the creator's own layer.
func open_makeup_picker(key:String,hint:String) -> void:
	var current:String=LifeCharacterIdentity.makeup_value(profile,key)
	var picker:=ColorPicker.new()
	picker.name="MakeupPicker"
	picker.color=Color.from_string(current,Color("b5453f")) if current!=LifeCharacterIdentity.MAKEUP_NONE else Color("b5453f")
	picker.edit_alpha=false
	picker.color_mode=ColorPicker.MODE_OKHSL
	picker.picker_shape=ColorPicker.SHAPE_HSV_WHEEL
	var holder:=Panel.new()
	holder.name="MakeupPickerHolder"
	holder.add_theme_stylebox_override("panel",P.panel(P.WHITE,18))
	rect(holder,Vector2(560,170),Vector2(380,520),overlay)
	overlay_open=true
	text_label(hint,Vector2(580,186),Vector2(340,30),20,P.INK,true,overlay)
	rect(picker,Vector2(576,224),Vector2(348,384),overlay)
	# A live write: dragging the wheel recolours the face immediately, so the
	# player is choosing on their own Lifelet rather than on a swatch.
	picker.color_changed.connect(func(colour:Color):
		profile[key]=colour.to_html(false)
		refresh_preview())
	# The picker keeps whatever the wheel currently holds; Cancel restores the
	# shade the Lifelet arrived with, so the two buttons really differ.
	picker_original={key:current}
	button("Use this shade",Vector2(580,626),Vector2(168,38),_close_makeup_picker.bind(key,true),true,overlay)
	button("Cancel",Vector2(760,626),Vector2(164,38),_close_makeup_picker.bind(key,false),false,overlay)

## Close the creator's colour picker. `keep` leaves the mixed shade in the look;
## otherwise the shade is put back exactly as it was before the picker opened.
func _close_makeup_picker(key:String,keep:bool) -> void:
	if not keep:
		profile[key]=str(picker_original.get(key,LifeCharacterIdentity.MAKEUP_NONE))
	elif LifeCharacterIdentity.makeup_value(profile,key)==LifeCharacterIdentity.MAKEUP_NONE:
		profile[key]=Color("b5453f").to_html(false)
	close_overlay()
	refresh_preview()

func set_body_scale(value:float) -> void:
	profile.body_scale=clampf(value,.85,1.15)
	if is_instance_valid(preview):
		preview.scale=Vector3.ONE
		preview.visual.scale=Vector3(profile.body_scale,clampf(float(profile.get("height_scale",1.0)),.93,1.08),profile.body_scale)

func set_height_scale(value:float) -> void:
	profile.height_scale=clampf(value,.93,1.08)
	set_body_scale(float(profile.get("body_scale",1.0)))

func randomize_person() -> void:
	var styling:Dictionary={}
	if is_instance_valid(preview) and preview.has_method("authored_hair_styles"):
		var wardrobe:Dictionary=preview.authored_wardrobe()
		styling={"hair":preview.authored_hair_styles(),"outfits":wardrobe.outfits,"bottoms":wardrobe.bottoms}
	# Merge in place: this Dictionary is also the selected household member.
	profile.merge(preload("res://scripts/character_identity.gd").generate(randi(),profile,household_profiles,styling),true)
	refresh_preview()

func show_lot_selection() -> void:
	var guardian: bool = false
	for person: Dictionary in household_profiles:
		if LifeLifecycle.stage_for(person) in ["teen","young_adult","adult","elder"]: guardian = true
	if not guardian:
		show_notice("A child needs a teen or adult in the household."); return
	if str(profile.name).strip_edges().is_empty():profile.name="Mara Vale"
	mode="lots"
	_set_studio_render_quality(false)
	clear_ui()
	if stage:stage.visible=false
	world.sun.light_energy=.8
	world.sun.rotation_degrees=Vector3(-52,-35,0)
	# The starter houses are the property policy's own list, so the opening
	# picker and a mid-game move offer the same homes by the same rules.
	selected_lot=clampi(selected_lot,0,Properties.starters().size()-1)
	world.create_home(LifeCatalog.starter_layout(int(Properties.type_info(Properties.starters()[selected_lot]).layout)))
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
	var starter_ids:Array[String]=Properties.starters()
	for i in range(starter_ids.size()):
		var info:Dictionary=Properties.type_info(starter_ids[i])
		var b=button(str(info.label),Vector2(54,331+i*95),Vector2(292,50),func():selected_lot=i;show_lot_selection(),selected_lot==i)
		b.alignment=HORIZONTAL_ALIGNMENT_LEFT
		text_label(str(info.tagline),Vector2(61,382+i*95),Vector2(282,30),12,P.MUTED)
	var chosen:Dictionary=Properties.type_info(starter_ids[selected_lot])
	text_label("%d BED  /  %d BATH  /  %d ROOMS  /  GARDEN" % [int(chosen.beds),int(chosen.baths),int(chosen.rooms)],Vector2(57,640),Vector2(280,27),11,P.MUTED)
	card(Vector2(476,750),Vector2(920,118),Color("f9faf2"))
	small_caps("Move-in ready",Vector2(500,764))
	text_label(str(chosen.label),Vector2(498,795),Vector2(360,43),30,P.INK,true)
	text_label("Household funds after move-in\nℒ %s" % ("4,500" if not bool(chosen.price) else "2,500"),Vector2(814,782),Vector2(310,58),14,P.MUTED)
	button("Start living  →",Vector2(1136,779),Vector2(234,62),start_household,true)
	button("←  Back to my Lifelet",Vector2(40,805),Vector2(280,50),show_creator)


## Every home the household may live in, as a mid-game move: the starter houses
## it can still choose, and the larger ones it can buy. The list, the price and
## every refusal come from `LifeProperties`, so the panel and the move agree.
func show_property_panel() -> void:
	_begin_pause_overlay()
	var background:ColorRect=ColorRect.new()
	background.color=Color(.08,.17,.15,.28)
	rect(background,Vector2(interface_local_x(0.0),0),interface_size(),overlay)
	card(Vector2(398,84),Vector2(644,772),P.WHITE,24,overlay)
	small_caps("Where you live",Vector2(430,104),Vector2(580,25),overlay)
	text_label("Homes & property",Vector2(428,136),Vector2(584,50),31,P.INK,true,overlay)
	paragraph(Properties.describe(properties),Vector2(430,192),Vector2(580,40),15,P.MUTED,overlay)
	var scroll:ScrollContainer=ScrollContainer.new()
	scroll.name="PropertyList"
	rect(scroll,Vector2(430,240),Vector2(580,520),overlay)
	var column:VBoxContainer=VBoxContainer.new()
	column.add_theme_constant_override("separation",8)
	scroll.add_child(column)
	for offer:Dictionary in Properties.offers(properties,sim.funds):
		var house_id:String=str(offer.id)
		var row:Control=Control.new()
		row.name="PropertyRow_"+house_id
		row.custom_minimum_size=Vector2(560,72)
		column.add_child(row)
		var title:String=str(offer.label)+(" · Current home" if bool(offer.current) else "")
		if bool(offer.owned) and not bool(offer.current):title+=" · Owned"
		var move:Button=button(title,Vector2.ZERO,Vector2(560,36),func():_move_house(house_id),bool(offer.current),row)
		move.name="Property_"+house_id
		move.disabled=not bool(offer.available)
		var detail:String="%d bed · %d bath · %d rooms" % [int(offer.beds),int(offer.baths),int(offer.rooms)]
		if not bool(offer.owned):detail+=" · ℒ%s to buy" % commas(int(offer.price))
		detail+=" · ℒ%s to move" % commas(int(offer.cost))
		var policy:Dictionary=offer.policy
		detail+=" · insured (ℒ%s)" % commas(int(policy.premium)) if not policy.is_empty() else " · uninsured"
		move.tooltip_text=str(offer.reason) if not bool(offer.available) else str(offer.description)
		var note:Label=text_label(str(offer.reason) if not bool(offer.available) else detail,
			Vector2(6,40),Vector2(548,24),11,P.CORAL if not bool(offer.available) else P.MUTED,false,row)
		note.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
	# The insurance of the home the household actually lives in, so a second
	# property's cover is bought and cancelled where it is lived in.
	var current_id:String=Properties.active(properties)
	var insured:bool=false
	if not current_id.is_empty():
		var held:Dictionary=Properties.policy(properties,current_id)
		insured=not held.is_empty()
		text_label("Insurance on this home: %s" % (str(held.label) if insured else "none"),
			Vector2(432,770),Vector2(300,26),14,P.INK if insured else P.MUTED,false,overlay)
		button("Cancel insurance" if insured else "Insure this home · ℒ600",
			Vector2(740,766),Vector2(270,34),func():_toggle_property_insurance(insured),false,overlay)
	# A second policy product, so a bigger house can be covered more heavily.
	if not insured:
		button("Premium cover · ℒ900",Vector2(430,812),Vector2(280,34),func():_buy_property_policy("premium"),false,overlay)
	# Baby & Child cover sits under home insurance: a separate ℒ500 product that
	# can be bought alongside burglar cover once the household has children.
	var baby_held:bool=not str(Properties.house(properties,current_id).get("baby_policy","")).is_empty() if not current_id.is_empty() else false
	if not current_id.is_empty() and not baby_held:
		button("Baby & Child Insurance · ℒ500",Vector2(430,848),Vector2(280,34),func():_buy_property_policy("baby"),false,overlay)
	button("Back to life",Vector2(740,812),Vector2(270,34),close_overlay,true,overlay)


## Buy the named policy on the house the household lives in.
func _buy_property_policy(policy_id:String) -> void:
	var house_id:String=Properties.active(properties)
	var result:Dictionary=Properties.buy_policy(properties,house_id,policy_id,household.funds)
	if not bool(result.ok):
		show_notice(str(result.error));show_property_panel();return
	properties=result.state
	household.set_funds(int(result.funds))
	_apply_property_insurance()
	show_notice("Cover taken out on this home for ℒ%s." % commas(int(result.cost)))
	show_property_panel()


## Cancel the cover on the house the household lives in.
func _toggle_property_insurance(insured:bool) -> void:
	var house_id:String=Properties.active(properties)
	if insured:
		var result:Dictionary=Properties.cancel_policy(properties,house_id)
		if not bool(result.ok):show_notice(str(result.error))
		else:properties=result.state;_apply_property_insurance();show_notice("Cover cancelled on this home.")
	else:
		_buy_property_policy("home")
		return
	show_property_panel()


## Buy a home and move the household into it, rebuilding the world from its own
## saved layout. The house left behind keeps its land and its policy.
func _move_house(house_id:String) -> void:
	var house:Dictionary=Properties.houses(properties).get(house_id,{})
	var type_id:String=str(house.get("type",house_id))
	# The home being left is saved with its land *before* the move is quoted, so
	# the record the move carries already holds it and a later move back returns
	# to the same house on the same plot with the same furnishings.
	var leaving:String=Properties.active(properties)
	if not leaving.is_empty() and properties.get("houses",{}).has(leaving):
		properties.houses[leaving]["layout"]=world.serialize_items()
		properties.houses[leaving]["land"]=LifeBuildingState.land.duplicate(true)
	var result:Dictionary=Properties.move_into(properties,type_id,household.funds,house_id,LifeBuildingState.land)
	if not bool(result.ok):
		show_notice(str(result.error));show_property_panel();return
	properties=result.state
	household.set_funds(int(result.funds))
	_apply_property_insurance()
	# The new home is built from its own saved layout, or from its type's starter
	# layout when it has never been lived in.
	var target:Dictionary=Properties.house(properties,house_id)
	var layout:Array=target.get("layout",[])
	if layout.is_empty():layout=LifeCatalog.starter_layout(int(Properties.type_info(type_id).layout))
	current_venue="home"
	LifeBuildingState.set_land(target.get("land",{}))
	home_layout=layout
	setup_live(layout)
	refresh_hud()
	show_notice("Moved in to %s for ℒ%s." % [str(target.get("name","your new home")),commas(int(result.cost))])
	close_overlay()

func select_creator_member(index:int) -> void:
	if index<0 or index>=household_profiles.size():return
	creator_index=index
	profile=household_profiles[index]
	LifeCharacterIdentity.ensure_wardrobe(profile)
	creator_outfit_category=LifeCharacterIdentity.normalize_category(profile.get("outfit_category","everyday"))
	refresh_preview()

func add_creator_member() -> void:
	if household_profiles.size()>=LifeHousehold.MAX_MEMBERS:return
	var person:Dictionary=preload("res://scripts/character_identity.gd").generate(randi(),profile,household_profiles)
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
	residents.reset()
	load_epoch+=1
	has_active_game=true
	active_save_id="";active_save_name=""
	for person:Dictionary in household_profiles:person.erase("world_state")
	floor_color="cfa97e"
	current_venue="home"
	# The house the household starts in becomes its first property, so moving
	# later has somewhere to move back to.
	var starter_ids:Array[String]=Properties.starters()
	var starter_type:String=starter_ids[clampi(selected_lot,0,starter_ids.size()-1)]
	properties=Properties.fresh()
	var granted:Dictionary=Properties.grant(properties,starter_type,starter_type,Land.fresh())
	if bool(granted.ok):properties=granted.state
	home_layout=LifeCatalog.starter_layout(int(Properties.type_info(starter_type).layout))
	venue_layouts.clear()
	loading_game=true
	household.new_household(household_profiles)
	var family_result:Dictionary=household.configure_family(creator_family_links)
	if not family_result.ok:
		loading_game=false;has_active_game=false;show_creator();show_notice(str(family_result.error));return
	sim=household.selected()
	bound_member_id=household.selected_id()
	LifeBuildingState.set_land(Land.fresh())
	setup_live(home_layout)
	loading_game=false
	show_notice("Welcome home, %s. Click a furnishing to choose what happens next." % str(sim.character.name).split(" ")[0])

func setup_live(layout:Array) -> void:
	_set_studio_render_quality(false)
	close_overlay(false)
	pending_move.clear()
	route_generation+=1
	mode="live"
	if stage:stage.visible=false
	# The household's land is set before anything is built, because the ground,
	# the hedge, the navigation region, the compatibility grid and the camera pan
	# are all derived from it. At home it is the saved land; anywhere else it is
	# the starting plot, since a venue is not the household's to expand.
	if current_venue=="home":
		var saved_land:Variant=sim.character.get("world_state",{}).get("land") if sim.character.get("world_state",{}) is Dictionary else null
		LifeBuildingState.set_land(saved_land)
	else:
		LifeBuildingState.set_land({})
	if current_venue=="home":world.create_home(layout)
	elif current_venue in LifeNeighborhood.RESIDENT_HOMES:world.create_resident_home(current_venue,layout)
	else:world.create_public_venue(current_venue,layout)
	world.live_enabled=true
	world.set_build(false)
	# The visited venue drives hosted-activity credits: which home the
	# household is enjoying, and whose hospitality that is.
	for member:Dictionary in household.members:
		member.sim.visited_venue="" if current_venue=="home" else current_venue
		# Routine residents carry their anchor object position so companion
		# credits demand co-presence at the same furnishing.
		member.sim.companion_anchors.clear()
		for resident_id:String in LifeResidentCatalogue.IDS:
			var routine:Dictionary=LifeResidentCatalogue.PEOPLE[resident_id].get("routine",{})
			if str(routine.get("venue",""))!=current_venue:continue
			var kind:String=str(routine.get("anchor_kind",""))
			for item:Dictionary in world.items:
				if str(item.id).begins_with(current_venue) and str(item.kind)==kind:
					member.sim.companion_anchors[resident_id]=Vector3(float(item.x),.16,float(item.z))
					break
	world.camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	world.camera.size=16.0
	world.camera_angle=.62
	world.camera_elevation=.82
	world.camera_target=Vector3(0,0,.25)
	world.update_camera()
	world.sun.rotation_degrees=Vector3(-52,-35,0)
	world.environment.background_color=Color("cddfd6")
	world.sun.light_energy=.8
	motion_states.clear()
	traversal.reset()
	away_phases.clear()
	for i in range(household.members.size()):
		var member:Dictionary=household.members[i]
		spawn_actor(member.id,member.sim.character,Vector3(-.7+(i%2)*.65,.16,2.8+(i/2)*.48))
		member.sim.autonomy_activity_available=_activity_available_for_member.bind(str(member.id))
		motion_states[member.id]=_empty_motion()
	bound_member_id=household.selected_id()
	_bind_member(bound_member_id)
	player.set_selected(true)
	residents.attach(current_venue)
	path.clear();path_index=0;walk_only=false
	pending_action={}
	_restore_world_state(sim.character.get("world_state",{}))
	for member:Dictionary in household.members:
		var away:Dictionary=member.sim.get_away_state()
		world.set_actor_away(str(member.id),str(away.get("phase",""))=="away",not away.is_empty())
	sanitation_flow.sync_world(household.journeys.is_empty())
	household.register_targets(world.simulation_targets(),household.journeys.is_empty())
	for member:Dictionary in household.members:
		var member_actor:LifeActor=world.actors[member.id]
		var saved:Variant=member.sim.character.get("world_state",{})
		if member.id!=household.selected_id() and saved is Dictionary and household.journeys.is_empty():
			var at:Vector3=_saved_vector(saved.get("player"),member_actor.position)
			var cell:Vector2i=Vector2i(roundi(at.x*4),roundi(at.z*4))
			if not world.navigation.region.has_point(cell) or world.navigation.is_point_solid(cell):
				cell=world.nearest_free(at)
				at=Vector3(cell.x*.25,.16,cell.y*.25)
			member_actor.position=Vector3(at.x,.16,at.z)
			member_actor.rotation.y=_saved_number(saved.get("player_rotation"),0,-1000,1000)
	if not household.journeys.is_empty():
		for id:String in household.journeys.members:
			var record:Dictionary=household.journeys.members[id]
			world.actors[id].position=LifeJourneyState.vector(record.position)
			world.actors[id].rotation.y=float(record.yaw)
	build_undo.clear()
	_sync_actor_sound()
	sync_pets()
	_place_missing_memorials()
	_sync_food_truck()
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

## ---------------------------------------------------------- weekly food truck

## Present the van when the shared clock says today is a visit, and remove it
## when it is not. Called from `setup_live` after the world exists, so a fresh
## start, a load and a trip home all agree about whether the van is outside. The
## navigation graph is rebuilt only when the van actually arrives or leaves, and
## its band is a plain obstacle record, so the van never enters `items`, the
## saved layout or the catalogue.
func _sync_food_truck() -> void:
	if not is_instance_valid(food_truck):return
	food_truck.sync_world()
	var parked:bool=food_truck.present()
	if parked==_truck_parked:return
	_truck_parked=parked
	world.extra_obstacles=_truck_obstacles()
	world.rebuild_navigation()


## The van's solid band, in the shape `furnishing_obstacles` produces.
func _truck_obstacles() -> Array:
	if not food_truck.present():return []
	var park:Vector3=LifeFoodTruck.PARK
	# The van is yawed a quarter turn, so its own 2.33 m length lies along x.
	# The van parks on the street side of the sidewalk, so its footprint reaches
	# past the lot's own edge. An obstacle is only valid when the lot encloses it,
	# so the band is clipped to the lot: the part the player can actually walk on
	# is still blocked, and the layout is never refused because a parked van
	# stuck out over the pavement.
	var half:=Vector2(2.33,1.40)*.5
	var band:=Rect2(Vector2(park.x,park.z)-half,half*2).intersection(LifeBuildingState.lot())
	if band.size.x<=0.0 or band.size.y<=0.0:return []
	return [{"id":"food_truck","level":0,"x":band.get_center().x,"z":band.get_center().y,"w":band.size.x,"d":band.size.y}]


## The van's own arrival, driven by the shared clock: the household advances the
## day, this sees the change, and the van is presented. Nothing calls it by hand,
## and the notice fires exactly once per visiting day because the day it has
## already announced is remembered.
func _tick_food_truck() -> void:
	if not is_instance_valid(food_truck) or current_venue!="home":return
	_sync_food_truck()
	if not food_truck.present():return
	var visit_day:int=int(household.day)
	if _truck_seen_day==visit_day:return
	_truck_seen_day=visit_day
	show_notice("A delivery van has parked on the sidewalk for the day. It is open %s–%s; click it to order." % [LifeFoodTruck._clock(LifeFoodTruck.OPEN_MINUTES),LifeFoodTruck._clock(LifeFoodTruck.CLOSE_MINUTES)])


## Open the weekly food truck's shop. A click on the van arrives here, so there
## is one shop and one set of prices.
func show_food_truck() -> void:
	if not is_instance_valid(food_truck):return
	LifeFoodTruckMenu.show_shop(self)

## --------------------------------------------------------------- pets

## Rebuild every live pet from the household's saved record. Called after the
## world is created, so a load always resumes the same animals in their places.
func sync_pets() -> void:
	for id:String in pet_actors.keys():
		var stale:LifePetActor=pet_actors[id]
		if is_instance_valid(stale):stale.queue_free()
	pet_actors.clear()
	pet_arrivals.clear()
	pet_errands.clear()
	if not is_instance_valid(world) or not is_instance_valid(world.house):return
	var pets:Array=household.pets.get("pets",[])
	var taken:Array[Vector3]=[]
	for index:int in range(pets.size()):
		var pet:Dictionary=pets[index]
		# A saved pet is already home: it stands at its own indoor spot rather
		# than walking in again, so a reload never restages the arrival.
		var at:Vector3=pet_home_spot(index,taken)
		taken.append(at)
		spawn_pet(str(pet.id),pet,at,at)
	_sync_pet_sound()
	_refresh_pet_targets()

## Create one pet body. A pet bought here walks in from the street; a pet that
## is already home simply stands at its spot.
func spawn_pet(id:String,pet:Dictionary,spawn:Vector3,destination:Vector3) -> LifePetActor:
	var actor:=LifePetActor.new()
	actor.name=id.capitalize()
	# Configure before entering the tree: the actor builds its model once, from
	# the real pet, instead of building a throwaway default in _ready first.
	actor.configure(id,str(pet.get("species","cat")),LifePets.appearance(pet),str(pet.get("name","")),str(pet.get("sex","female")))
	world.house.add_child(actor)
	actor.position=spawn
	actor.set_meta("display_name",str(pet.get("name","")))
	pet_actors[id]=actor
	_pet_pick_body(actor,id)
	if destination.distance_to(spawn)>.01:pet_arrivals[id]={"destination":destination,"path":world.path_to(spawn,destination),"index":0}
	if not pet_arrivals.has(id):actor.position=destination
	return actor

## A pet is picked like anyone else: its own body carries the item identity, so
## clicking it opens its card through the ordinary clicked-object path.
func _pet_pick_body(actor:LifePetActor,id:String) -> void:
	var body:=StaticBody3D.new()
	body.collision_layer=LifeWorld.PICK_GROUND|LifeWorld.PICK_UPPER
	body.input_ray_pickable=true
	body.set_meta("item_id",id)
	actor.add_child(body)
	var shape:=CollisionShape3D.new()
	var capsule:=CapsuleShape3D.new()
	capsule.height=float(LifePetActor.SPECIES_HEIGHT.get(actor.species,0.30))
	capsule.radius=0.22
	shape.shape=capsule
	shape.position.y=capsule.height*.5
	body.add_child(shape)
	world.pick_extras[id]={"id":id,"kind":"pet","label":str(actor.display_name),"node":actor,"size":Vector2(.6,.6)}

## Where a pet settles in the home. It prefers a clear indoor tile beside the
## household's food and water bowl, then the nearest clear floor tile to a few
## room seeds. Every candidate must be a real, non-solid ground tile that the
## household's own placement rules leave standing-clear, so a pet never settles
## inside furniture or on top of a Lifelet. A bowl on the patio is a place to
## eat, not a home, so the search stays indoors and falls back to the curbside
## places the household returns on only when the home has no free floor at all.
func pet_home_spot(index:int=0, taken:Array[Vector3]=[]) -> Vector3:
	var seeds:Array[Vector3]=[]
	var bowl:Dictionary=world.closest_item("pet_bowl",Vector3.ZERO)
	if not bowl.is_empty():
		var near:Vector3=Vector3(bowl.node.position.x,.16,bowl.node.position.z)
		seeds.append_array([near+Vector3(.75,0,.5),near+Vector3(-.75,0,.5),near+Vector3(.75,0,-.5),near+Vector3(-.75,0,-.5)])
	# Clear floor in the living room, then the rest of the ground floor, so
	# several pets spread out instead of stacking on one tile.
	seeds.append_array([
		Vector3(-1.5,0,1.5),Vector3(1.5,0,1.5),Vector3(-1.5,0,3.5),Vector3(1.5,0,3.5),
		Vector3(0,0,-1.5),Vector3(-3,0,1.0),Vector3(3,0,1.0),Vector3(0,0,4.0),
		Vector3(-4.5,0,-2.0),Vector3(4.5,0,-2.0),Vector3(-4.5,0,2.5),Vector3(4.5,0,2.5),
		Vector3(0,0,2.0),Vector3(-2.5,0,-3.5),Vector3(2.5,0,-3.5),
	])
	for seed:Vector3 in seeds:
		var cell:Vector2i=world.nearest_free(seed)
		var at:Vector3=Vector3(cell.x*.25,.16,cell.y*.25)
		if world.point_level(at)!=0:continue
		if world.outdoor_cell(cell):continue
		if _pet_spot_blocked(at):continue
		if taken.any(func(other:Vector3)->bool:return other.distance_to(at)<.7):continue
		return at
	return world.lot_return_position(index)

## The walk a pet takes when it first comes home: from the street to its own
## clear indoor spot. Returning Vector3.INF means no route exists yet, so the
## purchase is refused before any money changes hands.
func pet_arrival_destination(from:Vector3) -> Vector3:
	var taken:Array[Vector3]=[]
	for id:String in pet_actors:
		var body:LifePetActor=pet_actors[id]
		if is_instance_valid(body):taken.append(body.position)
	var at:Vector3=pet_home_spot(household.pets.get("pets",[]).size(),taken)
	if _pet_spot_blocked(at):return Vector3.INF
	var walk:PackedVector3Array=world.path_to(from,at)
	if walk.is_empty() or walk[-1].distance_to(at)>=.001:return Vector3.INF
	return at

func _pet_spot_blocked(at:Vector3) -> bool:
	if not meal_flow.standing_geometry_clear(at):return true
	for id:String in world.actors:
		var body:LifeActor=world.actors[id]
		if body.visible and Vector2(body.position.x-at.x,body.position.z-at.z).length()<.7:return true
	for id:String in pet_actors:
		var pet:LifePetActor=pet_actors[id]
		if pet.visible and Vector2(pet.position.x-at.x,pet.position.z-at.z).length()<.7:return true
	return false

## Walk an arriving pet in, then let it idle. Returning true means the pet moved.
func _advance_pet_arrivals(delta:float) -> bool:
	if pet_arrivals.is_empty():return false
	var speed:float=float(sim.speed)
	if speed<=0.0:return false
	var moved:bool=false
	for id:String in pet_arrivals.keys():
		var actor:LifePetActor=pet_actors.get(id)
		if not is_instance_valid(actor):
			pet_arrivals.erase(id)
			continue
		var record:Dictionary=pet_arrivals[id]
		var walk:PackedVector3Array=record.path
		var destination:Vector3=record.destination
		if walk.is_empty() or int(record.index)>=walk.size():
			pet_arrivals.erase(id)
			actor.position=destination
			continue
		var budget:float=delta*speed*2.0
		var refused:bool=false
		while int(record.index)<walk.size() and budget>0.000001:
			var point:Vector3=walk[int(record.index)]
			var distance:float=actor.position.distance_to(point)
			if distance<0.001:
				record.index=int(record.index)+1
				continue
			var step:float=minf(distance,budget)
			var next:Vector3=actor.position.move_toward(point,step)
			if _pet_step_blocked(actor,next):
				refused=true
				break
			var direction:Vector3=next-actor.position
			actor.rotation.y=lerp_angle(actor.rotation.y,atan2(direction.x,direction.z),minf(delta*6.0,1.0))
			actor.position=next
			budget-=step
			moved=true
			if distance<=step+0.000001:record.index=int(record.index)+1
		if refused:
			# A blocked arrival learns the corridor and takes the detour, so a pet
			# never stands in the doorway pushing at a body it cannot pass.
			world.lot_navigation.penalize_segment(world.point_level(actor.position),actor.position,walk[mini(int(record.index),walk.size()-1)])
			var detour:PackedVector3Array=_pet_route(id,actor.position,destination)
			if not detour.is_empty():
				record.path=detour
				record.index=0
				pet_arrivals[id]=record
		if actor.position.distance_to(destination)<0.05:
			pet_arrivals.erase(id)
			actor.position=destination
	return moved

func _pet_step_blocked(actor:LifePetActor,next:Vector3) -> bool:
	# The step test mirrors a Lifelet's own: the destination tile and the whole
	# swept path are measured against real geometry, and a body only refuses a
	# step that comes closer than it already is. A whole-segment bounding box
	# would fatten a diagonal step into a wall and wedge the animal forever.
	var from:Vector3=actor.position
	if world.point_level(next)<0 or not world.lot_navigation.point_clear(0,next):return true
	return not _pet_path_clear(actor,from,next)

## Whether a pet may sweep from one point to another without closing on a person
## or another animal. Mirrors the household walker's own body rule so a pet in a
## crowded room waits and slips past exactly as a Lifelet does, and never steps
## through somebody it could simply walk around.
func _pet_path_clear(actor:LifePetActor,from:Vector3,to:Vector3) -> bool:
	var step:Vector3=to-from
	var bodies:Array[Vector3]=[]
	for id:String in world.actors:
		var body:LifeActor=world.actors[id]
		if body.visible:bodies.append(body.position)
	for id:String in pet_actors:
		var pet:LifePetActor=pet_actors[id]
		if pet!=actor and is_instance_valid(pet) and pet.visible:bodies.append(pet.position)
	for at:Vector3 in bodies:
		if not _pet_same_floor(to,at):continue
		var before:float=from.distance_to(at);var after:float=to.distance_to(at)
		var part:float=clampf((at-from).dot(step)/maxf(.00000001,step.length_squared()),0.0,1.0)
		var closest:float=from.lerp(to,part).distance_to(at)
		if before<LifeTraversal.BODY_GAP:
			if after<=before+.000001 or closest<before-.000001:return false
		elif closest<LifeTraversal.BODY_GAP-.000001:return false
	return true

## Whether two points share a floor, so an upstairs body never blocks a step
## taken on the ground floor beneath them.
func _pet_same_floor(a:Vector3,b:Vector3) -> bool:
	return absf(a.y-b.y)<.6

## Pets are presentation for the household clock: a paused day freezes them too.
func _sync_pet_sound() -> void:
	var running:bool=mode=="live" and is_instance_valid(sim) and sim.speed>0
	for id:String in pet_actors:
		var actor:LifePetActor=pet_actors[id]
		if is_instance_valid(actor):actor.speed=1.0 if running else 0.0

func _refresh_pet_targets() -> void:
	if not is_instance_valid(world):return
	var targets:Array=world.simulation_targets()
	for id:String in pet_actors:
		var record:Dictionary=_pet_record(id)
		if record.is_empty():continue
		var actor:LifePetActor=pet_actors[id]
		if not is_instance_valid(actor):continue
		targets.append({"id":id,"kind":"pet","label":str(record.name),"position":actor.position})

## The saved record for one pet. The household owns the lookup, so the card,
## the life box and the interactions all read the same record.
func _pet_record(id:String) -> Dictionary:
	return household.pet_record(id)

func _tick_pets(delta:float) -> void:
	if pet_actors.is_empty():return
	var running:bool=mode=="live" and sim.speed>0
	var moving:bool=_advance_pet_arrivals(delta) if running else false
	# A pet looks after itself: its needs drain on the same clock the household
	# runs on, and it walks to the bowl or to its own bed when one runs low.
	if running:
		moving=_tick_pet_autonomy(delta,float(sim.speed)) or moving
	for id:String in pet_actors.keys():
		var actor:LifePetActor=pet_actors.get(id)
		if not is_instance_valid(actor):
			pet_actors.erase(id)
			continue
		var busy:bool=moving and (pet_arrivals.has(id) or _pet_errand(id).get("walking",false))
		actor.animate(delta,busy,float(sim.speed) if running else 0.0)
	_refresh_pet_targets()

## One pet's own errand: where it is going and what it is doing there. The
## controller owns this, exactly as it owns the household's own routes.
func _pet_errand(id:String) -> Dictionary:
	return pet_errands.get(id,{})

## Advance every pet's needs and let each animal act on them. A pet whose need is
## low walks to the furnishing that answers it and uses it until the need is met;
## otherwise it settles at its own spot. Hunger and thirst share the bowl, a nap
## uses the pet's own bed, and a dog's dirty coat is washed by a person rather
## than by the animal, so only the household can mend that one.
func _tick_pet_autonomy(delta:float,speed:float) -> bool:
	var hours:float=delta*speed/60.0
	if hours<=0.0:return false
	var moved:bool=false
	for id:String in pet_actors.keys():
		var actor:LifePetActor=pet_actors.get(id)
		if not is_instance_valid(actor):continue
		var record:Dictionary=_pet_record(id)
		if record.is_empty():continue
		# The household's own clock already drains a pet's condition through
		# `LifePetCare.tick`, so this only reads it. A cat keeps itself clean the
		# way a cat does, which `LifePetCare` models as its own grooming term, so
		# its coat stays up without the household's help.
		var care:Dictionary=record.get("care",{})
		if not care is Dictionary:
			care=LifePetCare.fresh()
			record["care"]=care
		var needs:Dictionary=care.get("needs",{})
		if not needs is Dictionary or needs.is_empty():continue
		# The needs an animal acts on are `LifePetCare`'s own names, which map onto
		# the errands below: hunger and thirst to the bowl, energy to its bed,
		# bladder and fun to the garden.
		# An animal still walking in has not settled yet, so it acts only once it
		# has arrived: two walkers on one body would drag it off its own route.
		if pet_arrivals.has(id):continue
		if _pet_errand(id).is_empty() and _pet_needs_errand(record,needs):
			if _start_pet_errand(id,actor,record,needs):moved=true
		# With its indoor needs comfortable, a pet takes itself outside: a tree
		# for a wee, or the garden for a wander and a play.
		if _pet_errand(id).is_empty():
			if _start_pet_outdoor_errand(id,actor,record,needs):moved=true
		var errand:Dictionary=_pet_errand(id)
		if errand.is_empty():continue
		if _advance_pet_errand(id,actor,record,needs,hours,delta,speed):moved=true
	return moved

## Whether this pet wants to go and do something about a need. Returned as the
## need's own name so the errand knows what it is for.
func _pet_needs_errand(record:Dictionary,needs:Dictionary) -> String:
	# Hunger first, then a tired animal's bed. The names are `LifePetCare`'s own,
	# so the condition the HUD draws and the errand the animal takes agree.
	for need:String in ["hunger","energy"]:
		if float(needs.get(need,100.0))<PET_NEED_URGENT:
			return need
	# A dirty dog waits for a person, so there is no errand for cleanliness.
	return ""

## Outdoor errands: a wee at a tree, or simply a wander and a play in the
## garden. An animal only does this once its indoor needs are comfortable, so it
## never leaves a full bowl or a warm bed to go outside.
func _pet_outdoor_wanted(record:Dictionary,needs:Dictionary) -> String:
	for need:String in ["hunger","energy"]:
		if float(needs.get(need,100.0))<PET_NEED_URGENT:
			return ""
	# A full bladder, then plain restlessness: both are answered outside.
	if float(needs.get("bladder",100.0))<PET_NEED_URGENT:
		return "bladder"
	if float(needs.get("fun",100.0))<PET_NEED_URGENT:
		return "fun"
	return ""

## Where a pet goes outside: a tree to wee at, or a clear patch of garden to
## wander and play in. Both are real outdoor cells, so a pet never ends up
## inside a wall or on a neighbour's floor.
func _pet_outdoor_spot(want:String) -> Vector3:
	if want=="bladder":
		var tree:Vector3=_pet_tree_spot()
		if tree.is_finite():return tree
	# A wander: a few clear outdoor places near the front garden.
	for seed:Vector3 in [Vector3(3.0,0,7.5),Vector3(-3.0,0,7.5),Vector3(4.5,0,6.5),Vector3(-4.5,0,6.5),Vector3(0,0,8.0)]:
		var cell:Vector2i=world.nearest_outdoor(seed)
		var at:Vector3=Vector3(cell.x*.25,.16,cell.y*.25)
		if _pet_spot_blocked(at):continue
		return at
	return Vector3.INF

## The route a pet takes to an errand. Bodies are treated as obstacles exactly
## as a Lifelet's route does, so a pet that has been blocked replans around the
## person or animal in its way rather than walking into them again. Returns an
## empty array when no route avoids them, so the caller keeps its current plan.
func _pet_route(id:String,from:Vector3,to:Vector3) -> PackedVector3Array:
	var occupied:Array[Vector3]=[]
	for other:String in world.actors:
		var body:LifeActor=world.actors[other]
		if other!=id and is_instance_valid(body) and body.visible:occupied.append(body.position)
	for other:String in pet_actors:
		var pet:LifePetActor=pet_actors[other]
		if other!=id and is_instance_valid(pet) and pet.visible:occupied.append(pet.position)
	var result:Dictionary=world.lot_navigation.route_avoiding(
		LifeLotNavigation.floor_location(world.point_level(from),from),
		LifeLotNavigation.floor_location(world.point_level(to),to),
		occupied,LifeTraversal.ROUTE_CLEARANCE)
	if not bool(result.ok):return PackedVector3Array()
	for segment:Dictionary in result.segments:
		if str(segment.kind)!="floor":return PackedVector3Array()
	return result.points

## The base of a landscape tree the pet can wee against. A tree is the outdoor
## fixture the household already has, so no new furnishing is needed for this.
func _pet_tree_spot() -> Vector3:
	for tree:Node3D in world.landscape_trees:
		if not is_instance_valid(tree):continue
		if world.point_level(tree.position)!=0:continue
		for offset:Vector3 in [Vector3(.5,0,.5),Vector3(-.5,0,.5),Vector3(.5,0,-.5),Vector3(-.5,0,-.5)]:
			var at:=Vector3(tree.position.x+offset.x,.16,tree.position.z+offset.z)
			var cell:=Vector2i(roundi(at.x*4),roundi(at.z*4))
			if not world.outdoor_cell(cell):continue
			at=Vector3(cell.x*.25,.16,cell.y*.25)
			if _pet_spot_blocked(at):continue
			return at
	return Vector3.INF

## Send a pet out of doors for a wee or a play. It walks out through the front
## door, does what it went for, then comes home and settles.
func _start_pet_outdoor_errand(id:String,actor:LifePetActor,record:Dictionary,needs:Dictionary) -> bool:
	var want:String=_pet_outdoor_wanted(record,needs)
	if want.is_empty():return false
	var at:Vector3=_pet_outdoor_spot(want)
	if not at.is_finite():return false
	var walk:PackedVector3Array=_pet_route(id,actor.position,at)
	if walk.is_empty() and actor.position.distance_to(at)>=.25:return false
	pet_errands[id]={"need":want,"kind":"outdoors","target":"","at":at,"path":walk,"index":0,"phase":"walking","elapsed":0.0,"walking":true}
	return true

## Send a pet to the furnishing that answers its need. An animal with nothing to
## walk to simply waits: the need stays low until the household places a bowl or
## a bed, and its own card says so.
func _start_pet_errand(id:String,actor:LifePetActor,record:Dictionary,needs:Dictionary) -> bool:
	var need:String=_pet_needs_errand(record,needs)
	if need.is_empty():return false
	var kind:String="pet_bowl" if need in ["hunger","thirst"] else _pet_bed_kind(str(record.get("species","cat")))
	var target:Dictionary=world.closest_item(kind,actor.position)
	if target.is_empty():return false
	var at:Vector3=_pet_errand_spot(target)
	if not at.is_finite():return false
	var walk:PackedVector3Array=_pet_route(id,actor.position,at)
	if walk.is_empty() and actor.position.distance_to(at)>=.2:return false
	pet_errands[id]={"need":need,"kind":kind,"target":str(target.id),"at":at,"path":walk,"index":0,"phase":"walking","elapsed":0.0,"walking":true}
	return true

## The bed a species sleeps in. A cat has its own cosy bed and a dog its own
## cushioned one, so an animal always goes to the bed bought for it.
func _pet_bed_kind(species:String) -> String:
	return "pet_bed_cat" if species=="cat" else "pet_bed_dog"

## Where a pet stands to use a furnishing: a clear tile beside it, found with the
## same clear-tile search a pet's own home spot uses, so a bowl placed anywhere
## on the lot still has somewhere legal to stand.
func _pet_errand_spot(item:Dictionary) -> Vector3:
	var base:Vector3=item.node.position
	var level:int=world.item_level(item)
	for offset:Vector3 in [Vector3(.55,0,0),Vector3(-.55,0,0),Vector3(0,0,.55),Vector3(0,0,-.55),Vector3(.4,0,.4),Vector3(-.4,0,.4),Vector3(.4,0,-.4),Vector3(-.4,0,-.4),Vector3(.9,0,0),Vector3(0,0,.9)]:
		var wanted:=Vector3(base.x+offset.x,LifeBuildingState.level_y(level),base.z+offset.z)
		var cell:Vector2i=world.nearest_free(wanted)
		var at:=Vector3(cell.x*.25,LifeBuildingState.level_y(level),cell.y*.25)
		if world.point_level(at)!=level:continue
		if _pet_spot_blocked(at):continue
		return at
	return Vector3.INF

## Walk a pet along its errand, then let it use the furnishing until the need is
## met. It then walks back to its own spot and settles, so a pet is never parked
## inside furniture and never left standing at a bowl for the rest of the day.
func _advance_pet_errand(id:String,actor:LifePetActor,record:Dictionary,needs:Dictionary,hours:float,delta:float,speed:float) -> bool:
	var errand:Dictionary=pet_errands.get(id,{})
	if errand.is_empty():return false
	var moved:bool=false
	if str(errand.phase)=="walking":
		var walk:PackedVector3Array=errand.path
		var budget:float=delta*speed*1.4
		var refused:bool=false
		while int(errand.index)<walk.size() and budget>0.0:
			var point:Vector3=walk[int(errand.index)]
			var distance:float=actor.position.distance_to(point)
			if distance>.001:
				var direction:Vector3=point-actor.position
				actor.rotation.y=atan2(direction.x,direction.z)
			var step:float=minf(distance,budget)
			var next:Vector3=actor.position.move_toward(point,step)
			if _pet_step_blocked(actor,next):
				refused=true
				break
			actor.position=next;budget-=step;moved=true
			if distance<=step+.00001:errand.index=int(errand.index)+1
		if refused:
			# A refused step means this corridor is not truly walkable: penalise
			# it, exactly as a Lifelet learns it, and walk the detour instead.
			# Without this a pet would push against the same wall all day.
			world.lot_navigation.penalize_segment(world.point_level(actor.position),actor.position,walk[mini(int(errand.index),walk.size()-1)])
			var detour:PackedVector3Array=_pet_route(id,actor.position,Vector3(errand.at))
			if not detour.is_empty():
				errand.path=detour
				errand.index=0
		if int(errand.index)>=walk.size() or actor.position.distance_to(Vector3(errand.at))<.12:
			errand.phase="using"
		pet_errands[id]=errand
		return moved
	# Using the furnishing: the need mends until it is comfortable again.
	var need:String=str(errand.need)
	var restored:float=0.0
	match need:
		"hunger": restored=LifePets.FEED_AMOUNT
		"thirst": restored=LifePets.WATER_AMOUNT
		"energy": restored=LifePets.SLEEP_PER_HOUR
		# A wee at a tree, or a play in the garden, settles in a moment rather
		# than over a helping: the animal has already done the work by walking out.
		"bladder":
			needs[need]=LifePets.RELIEF_AMOUNT
			pet_errands.erase(id)
			_pet_walk_home(id,actor,record,needs)
			return moved
		"fun":
			needs[need]=clampf(maxf(float(needs[need]),LifePets.PLAY_AMOUNT),0.0,100.0)
			pet_errands.erase(id)
			_pet_walk_home(id,actor,record,needs)
			return moved
	if need=="energy":
		# A nap is the household's own bed rest, measured in game hours.
		needs[need]=clampf(float(needs[need])+restored*hours,0.0,100.0)
	else:
		# A meal or a drink is a single helping, taken over a few game minutes.
		errand.elapsed=float(errand.get("elapsed",0.0))+hours*60.0
		var share:float=minf(1.0,float(errand.elapsed)/12.0)
		var before:float=float(needs[need])
		needs[need]=clampf(maxf(before,float(LifePets.NEED_START.get(need,80.0))-restored)+restored*share,0.0,100.0)
	var satisfied:bool=float(needs[need])>=LifePets.NEED_URGENT+30.0
	if not satisfied:
		pet_errands[id]=errand
		return moved
	# Done: walk home and settle.
	pet_errands.erase(id)
	_pet_walk_home(id,actor,record,needs)
	return moved

## Send a finished pet back to its own spot in the house. An animal that never
## left, or whose route is blocked, simply stays where it is.
func _pet_walk_home(id:String,actor:LifePetActor,record:Dictionary,needs:Dictionary) -> void:
	var home:Vector3=pet_home_spot(_pet_index(id))
	if actor.position.distance_to(home)<.25:return
	var back:PackedVector3Array=_pet_route(id,actor.position,home)
	if not back.is_empty():
		pet_arrivals[id]={"destination":home,"path":back,"index":0}

## A pet's index in the household's own roster, so it returns to its own spot.
func _pet_index(id:String) -> int:
	var pets:Array=household.pets.get("pets",[])
	for index:int in range(pets.size()):
		if str(pets[index].get("id",""))==id:return index
	return 0

## Put the whole pet population on one floor view's layer, so a pet upstairs is
## hidden while the ground floor is shown and vice versa.
func refresh_pet_layers() -> void:
	for id:String in pet_actors:
		var actor:LifePetActor=pet_actors[id]
		if not is_instance_valid(actor):continue
		for child:Node in actor.get_children():
			if child is CollisionObject3D:
				child.collision_layer=LifeWorld.PICK_UPPER if world.point_level(actor.position)==1 else LifeWorld.PICK_GROUND

## A pet card: what it is, what it is wearing, how it is doing, and everything
## this Lifelet can do with it. The actions come from the household's own policy,
## so a baby is offered nothing, a child is offered the trick it can teach, and an
## unavailable option states its reason rather than disappearing silently.
func show_pet_card(id:String) -> void:
	var record:Dictionary=_pet_record(id)
	if record.is_empty():return
	close_overlay();overlay_open=true;dismiss_layer()
	# The card is as tall as its action list: a cat offers one action and a dog
	# offers two, so a fixed height would clip one of them.
	var offered:Array=sim.get_actions_for("pet",id) if is_instance_valid(sim) else []
	var rows:int=maxi(offered.size(),1)
	var height:float=452.0+float(rows)*38.0+56.0
	var p:=Vector2(clampf(get_viewport().get_visible_rect().size.x*.5-200,300,1064),clampf((900.0-height)*.5,60,200))
	card(p,Vector2(400,height),P.WHITE,17,overlay)
	text_label(str(record.name),p+Vector2(19,14),Vector2(360,37),24,P.INK,true,overlay)
	text_label("%s · %s" % [LifePets.species_label(str(record.species)),str(LifePets.SEX_LABELS[record.sex])],p+Vector2(20,52),Vector2(360,26),16,P.TEAL,false,overlay)
	paragraph("%s coat, %s markings, %s." % [str(LifePets.COAT_LENGTH_LABELS[record.coat_length]),str(LifePets.MARKING_LABELS[record.marking]).to_lower(),"mixed gradient" if float(record.gradient)>.35 else "solid"],p+Vector2(20,84),Vector2(362,40),14,P.MUTED,overlay)
	var actor:LifePetActor=pet_actors.get(id)
	if is_instance_valid(actor):pet_thumbnail(p+Vector2(19,132),Vector2(362,210),record,overlay)
	# What the animal has actually learned, and how far the next lesson has got.
	var learned:Array=LifePets.TRICKS.filter(func(t:String)->bool:return (record.get("tricks",[]) as Array).has(t))
	var progress:Dictionary=record.get("trick_progress",{})
	var next:String=household_flow.next_trick(id) if is_instance_valid(household_flow) else ""
	var tricks_text:String="Knows no tricks yet."
	if not learned.is_empty():
		tricks_text="Knows: "+", ".join(learned)+"."
	if not next.is_empty() and int(progress.get(next,0))>0:
		tricks_text+=" %s is coming along (%d/%d)." % [next,int(progress.get(next,0)),LifePets.TRICK_SESSIONS]
	small_caps("Tricks",p+Vector2(20,352),Vector2(362,20),overlay)
	paragraph(tricks_text,p+Vector2(20,374),Vector2(362,42),14,P.MUTED,overlay)
	if int(record.get("affection",0))>0:
		paragraph("%d cuddles so far." % int(record.get("affection",0)),p+Vector2(20,416),Vector2(362,22),13,P.MUTED,overlay)
	# Every action the simulation offers for this animal, with the same reasons.
	var row:float=0.0
	for action:Dictionary in offered:
		var b:=button(str(action.label),p+Vector2(19,446+row*38),Vector2(362,34),_queue_pet_action.bind(id,str(action.id)),false,overlay)
		b.disabled=not bool(action.get("available",false))
		b.tooltip_text=str(action.get("unavailable_reason","")) if not bool(action.get("available",false)) else str(action.description)
		row+=1.0
	button("Back to life",p+Vector2(19,height-48),Vector2(174,38),close_overlay,false,overlay)
	button("Main menu",p+Vector2(207,height-48),Vector2(174,38),show_main_menu,false,overlay)

## Queue one of the pet card's own actions, exactly as the interaction menu does
## for a furnishing: the walk, the beat and its completion all run the ordinary
## activity pipeline, so a taught trick and a tummy rub are real activities.
func _queue_pet_action(pet_id:String,action_id:String) -> void:
	var record:Dictionary=_pet_record(pet_id)
	var item:Dictionary={"id":pet_id,"kind":"pet","label":str(record.get("name","Your pet"))}
	close_overlay()
	queue_interaction(item,action_id)

## The spin of each live pet preview, keyed by SubViewport instance id, so a
## drag that turns the animal survives the model being rebuilt on a coat change.
var pet_preview_spin: Dictionary = {}
## Each live pet preview's camera rig, keyed the same way.
var pet_preview_rig: Dictionary = {}
## Whether a pet preview's picture is currently being dragged.
var pet_preview_dragging: Dictionary = {}
## The angle a pet preview opens at: a three-quarter view, so the animal reads as
## a body with a head and a tail rather than a flat side-on silhouette.
const PET_PREVIEW_START_SPIN: float = 0.6

func pet_thumbnail(p:Vector2,s:Vector2,pet:Dictionary,parent:Node=ui) -> void:
	var sv:=SubViewport.new()
	sv.size=Vector2i(int(s.x*2),int(s.y*2))
	sv.own_world_3d=true
	sv.transparent_bg=true
	sv.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	sv.msaa_3d=Viewport.MSAA_2X
	parent.add_child(sv)
	var view:=TextureRect.new()
	view.texture=sv.get_texture()
	view.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	rect(view,p,s,parent)
	var root:=Node3D.new();sv.add_child(root)
	var path:String="res://assets/models/pet_%s.glb" % str(pet.get("species","cat"))
	if not ResourceLoader.exists(path):return
	var model:=LifePetActor.new()
	# Configured detached, so the preview builds its model once.
	model.configure("preview",str(pet.get("species","cat")),LifePets.appearance(pet),str(pet.get("name","")),str(pet.get("sex","female")))
	root.add_child(model)
	# The animal's own measured bounds, so the framing follows what was built
	# instead of a per-species constant that leaves the model tiny in the box.
	var bounds:AABB=_preview_bounds(model)
	var focus:Vector3=bounds.get_center()
	var span:float=maxf(maxf(bounds.size.x,bounds.size.y),bounds.size.z)
	var cam:=Camera3D.new();root.add_child(cam)
	cam.projection=Camera3D.PROJECTION_ORTHOGONAL
	# The preview boxes are wider than they are tall, and an orthogonal camera's
	# `size` is a vertical extent unless it keeps width instead. Fitting only one
	# axis left the animal a few pixels across in a wide box, so the camera keeps
	# width and the framing fits the animal on BOTH axes: the width shows the
	# animal's long axis and the height shows its standing height.
	cam.keep_aspect=Camera3D.KEEP_WIDTH
	var aspect:float=maxf(float(sv.size.x)/maxf(float(sv.size.y),1.0),0.05)
	var horizontal:float=maxf(maxf(bounds.size.x,bounds.size.z),span*.35)
	cam.size=maxf(maxf(horizontal,span*.75)*1.18,bounds.size.y*1.30*aspect)
	var spin:float=float(pet_preview_spin.get(sv.get_instance_id(),PET_PREVIEW_START_SPIN))
	_place_pet_preview_camera(cam,focus,span,spin)
	pet_preview_rig[sv.get_instance_id()]={"camera":cam,"focus":focus,"span":span}
	# Drag the picture to turn the animal. The pet card and the shop both use it.
	view.mouse_filter=Control.MOUSE_FILTER_STOP
	view.mouse_default_cursor_shape=Control.CURSOR_POINTING_HAND
	view.gui_input.connect(_pet_preview_input.bind(sv.get_instance_id()))
	var light:=DirectionalLight3D.new();root.add_child(light);light.rotation_degrees=Vector3(-38,-32,0);light.light_energy=.7
	var env:=WorldEnvironment.new();var e:=Environment.new();e.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;e.ambient_light_color=Color.WHITE;e.ambient_light_energy=.35;env.environment=e;root.add_child(env)
	freeze_viewport.call_deferred(sv.get_instance_id())

## Put a pet preview's camera at `spin` radians around the animal.
func _place_pet_preview_camera(cam:Camera3D,focus:Vector3,span:float,spin:float) -> void:
	var radius:float=maxf(span*1.9,0.6)
	cam.position=focus+Vector3(sin(spin)*radius,span*.30,cos(spin)*radius)
	cam.look_at(focus)

## The real bounds of a preview model, from every mesh under it. A model whose
## meshes are not ready yet falls back to a small sensible box.
func _preview_bounds(model:Node3D) -> AABB:
	var found:=false
	var bounds:=AABB()
	for node:Node in model.find_children("*","MeshInstance3D",true,false):
		var mesh:MeshInstance3D=node as MeshInstance3D
		if mesh==null or mesh.mesh==null:continue
		var local:AABB=mesh.mesh.get_aabb()
		var at:Transform3D=model.global_transform.affine_inverse()*mesh.global_transform
		var box:AABB=at*local
		bounds=box if not found else bounds.merge(box)
		found=true
	if not found:return AABB(Vector3(-.3,0,-.3),Vector3(.6,.5,.6))
	return bounds

## Turn a previewed animal by dragging its picture.
func _pet_preview_input(event:InputEvent,viewport_id:int) -> void:
	if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT:
		pet_preview_dragging[viewport_id]=event.pressed
		return
	if not (event is InputEventMouseMotion) or not bool(pet_preview_dragging.get(viewport_id,false)):return
	var rig:Variant=pet_preview_rig.get(viewport_id)
	if not rig is Dictionary:return
	var spin:float=float(pet_preview_spin.get(viewport_id,0.0))+event.relative.x*.02
	pet_preview_spin[viewport_id]=spin
	var camera:Camera3D=rig.get("camera")
	if is_instance_valid(camera):
		_place_pet_preview_camera(camera,rig.get("focus",Vector3.ZERO),float(rig.get("span",0.4)),spin)

## Refresh the shop's own live preview while the picker is open.
func preview_pet(draft:Dictionary) -> void:
	if not overlay_open:return
	var holder:Node=overlay.get_node_or_null("PetPreviewHolder")
	if holder==null:return
	for child:Node in holder.get_children():
		holder.remove_child(child)
		child.queue_free()
	pet_thumbnail(Vector2.ZERO,Vector2(240,66),draft,holder)

func draw_live() -> void:
	clear_ui()
	card(Vector2(22,18),Vector2(257,62),P.WHITE,14)
	logo(Vector2(36,29))
	button("Explore",Vector2(296,27),Vector2(95,43),show_neighborhood)
	stories_button=button("Stories",Vector2(400,27),Vector2(95,43),show_stories)
	stories_button.add_theme_font_size_override("font_size",13)
	if current_venue!="home":
		text_label(str(LifeNeighborhood.place_name(current_venue)),Vector2(306,86),Vector2(610,40),23,P.INK,true)
	card(Vector2(504,18),Vector2(432,57),P.WHITE,14)
	button("Live",Vector2(514,27),Vector2(116,39),func():set_build_mode(false),mode=="live")
	button("Build & buy",Vector2(638,27),Vector2(150,39),func():set_build_mode(true),mode=="build")
	button("My Lifelet",Vector2(796,27),Vector2(130,39),show_person)
	button("Phone",Vector2(952,27),Vector2(153,43),adoption_flow.show_phone).name="HouseholdPhone"
	card(Vector2(1125,18),Vector2(293,62),P.WHITE,14)
	funds_label=text_label("ℒ 2,500",Vector2(1145,29),Vector2(170,38),25,P.TEAL)
	icon_button("menu","Pause menu (Esc)",Vector2(1357,27),Vector2(48,42),show_menu).name="PauseMenu"
	# Live floor viewing changes only visibility and camera height.
	if mode=="live" and current_venue=="home":
		for level:int in [0,1]:
			var floor_button:=button("Ground" if level==0 else "Upper",Vector2(1306,383+49*level),Vector2(99,42),func():set_live_view_level(level),world.view_level==level)
			floor_button.name="LiveGroundView" if level==0 else "LiveUpperView"
			floor_button.disabled=not _live_floor_available(level)
			floor_button.tooltip_text="View ground floor (Page Down)" if level==0 else ("View upper floor (Page Up)" if not floor_button.disabled else "Build an upper floor to view it (Page Up)")
			live_floor_buttons[level]=floor_button
	# Camera affordances remain visible above the household controls.
	icon_button("zoom_out","Zoom out (mouse wheel)",Vector2(1359,530),Vector2(46,42),func():world.camera.size=minf(world.camera.size+LifeWorld.CAMERA_BUTTON_ZOOM_STEP,LifeWorld.CAMERA_MAX_ZOOM)).name="CameraZoomOut"
	icon_button("zoom_in","Zoom in (mouse wheel)",Vector2(1359,481),Vector2(46,42),func():world.camera.size=maxf(world.camera.size-LifeWorld.CAMERA_BUTTON_ZOOM_STEP,LifeWorld.CAMERA_MIN_ZOOM)).name="CameraZoomIn"
	icon_button("rotate_left","Rotate camera left (Q)",Vector2(1306,530),Vector2(46,42),func():world.camera_angle-=PI/4;world.update_camera()).name="CameraRotateLeft"
	icon_button("rotate_right","Rotate camera right (E)",Vector2(1306,481),Vector2(46,42),func():world.camera_angle+=PI/4;world.update_camera()).name="CameraRotateRight"
	button("Walls",Vector2(1306,585),Vector2(99,38),func():world.set_cutaway(not world.cutaway))
	if mode=="build":draw_build_catalog()
	else:
		draw_goal_card()
		draw_household_bar()
		draw_queue()
	refresh_hud()

func _live_floor_available(level:int) -> bool:
	if level==0:return true
	if level!=1 or world.construction.building_state.is_empty():return false
	for floor:Dictionary in world.construction.building_state.floors:
		if int(floor.level)==1:return true
	return false

func set_live_view_level(level:int) -> void:
	if mode!="live" or current_venue!="home" or overlay_open or not _live_floor_available(level):return
	if get_viewport().gui_get_focus_owner() is LineEdit or get_viewport().gui_get_focus_owner() is TextEdit:return
	if world.set_view_level(level):draw_live()

func center_lifelet() -> void:
	if mode!="live" or overlay_open:return
	if get_viewport().gui_get_focus_owner() is LineEdit or get_viewport().gui_get_focus_owner() is TextEdit:return
	var selected_id:String=household.selected_id()
	var actor:LifeActor=world.actors.get(selected_id)
	if not is_instance_valid(actor):return
	if current_venue=="home":
		var level:int=world.point_level(actor.position)
		var route:Dictionary=traversal.routes.get(selected_id,{})
		var supported:bool=level==0 or (level==1 and world.construction.floor_contains(Vector2(actor.position.x,actor.position.z),1))
		if str(route.get("phase",""))!="transit" and supported and _live_floor_available(level):
			world.set_view_level(level)
	world.camera_target=actor.position
	world.update_camera()
	draw_live()

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
		var skill:Dictionary=sim.skills[skill_name]
		var mastered:bool=int(skill.level)>=10
		var progress:float=100.0 if mastered else clampf(float(skill.xp)/(int(skill.level)*50.0)*100.0,0,100)
		if skill_bars.has(skill_name):skill_bars[skill_name].value=progress
		if skill_progress_labels.has(skill_name):
			skill_progress_labels[skill_name].text="MAX" if mastered else "%d%%" % int(progress)
			skill_progress_labels[skill_name].tooltip_text="Skill mastered" if mastered else "%d / %d experience toward level %d" % [int(skill.xp),int(skill.level)*50,int(skill.level)+1]
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
			career_labels.work.disabled=not sim.get_action_availability("school_day").available
			career_labels.work.tooltip_text=str(sim.get_action_availability("school_day").reason)
			career_labels.homework.disabled=sim.is_away() or not sim.get_action_availability("homework").available
		else:
			career_labels.title.text=sim.career.title
			var requirement:Dictionary=sim.promotion_requirement()
			career_labels.details.text="Weekdays 09–17 · ℒ%d full day" % sim.career.salary+("" if requirement.is_empty() or bool(requirement.met) else "  ·  Next: %s %d" % [str(requirement.skill).capitalize(),int(requirement.level)])
			career_labels.work.disabled=not sim.get_action_availability("career_day").available
			career_labels.work.tooltip_text=str(sim.get_action_availability("career_day").reason)
	if not goal_labels.is_empty():
		var current:Dictionary={}
		for want:Dictionary in sim.wants:
			if not bool(want.complete):current=want;break
		goal_labels.title.text="A lovely beginning" if current.is_empty() else str(current.label)
		goal_labels.description.text="You have made your first wishes happen. Keep making this life yours." if current.is_empty() else str(current.description)
		goal_labels.reward.text="" if current.is_empty() else "+%d satisfaction" % int(current.reward)

func draw_household_bar() -> void:
	household_chips.clear()
	pet_chips.clear()
	# The switcher carries the household's people and every pet it owns, so the
	# animals live in the same life box as the Lifelets rather than only in the
	# room. A pet chip wears the pet's own portrait and opens its card.
	var pet_list:Array=household.pets.get("pets",[])
	var switcher_count:int=household.members.size()+pet_list.size()
	if switcher_count>1:
		var switcher_height:float=89.0+52.0 if not pet_list.is_empty() else 89.0
		card(Vector2(20,618.0-(52.0 if not pet_list.is_empty() else 0.0)),Vector2(maxi(128,switcher_count*35+16),switcher_height),P.WHITE,12).name="HouseholdSwitcher"
		var household_caption:=small_caps("Household",Vector2(28,624.0-(52.0 if not pet_list.is_empty() else 0.0)),Vector2(108,20))
		household_caption.add_theme_color_override("font_color",P.INK)
		var chip_top:float=657.0-(52.0 if not pet_list.is_empty() else 0.0)
		for i in range(household.members.size()):
			var member:Dictionary=household.members[i]
			# Portrait chips match the pet row: the baby's face (and every other
			# Lifelet) is visible in the life box, not only as initials.
			var chip=button("",Vector2(28+i*35,chip_top),Vector2(31,44),func():select_household_member(i),i==household.selected_index)
			chip.name="HouseholdChip_"+str(member.id)
			model_thumbnail("character",Vector2(29+i*35,chip_top+1),Vector2(29,42),true,ui,member.sim.character)
			compact_button(chip)
			chip.size=Vector2(31,44)
			chip.tooltip_text=str(member.sim.character.name)+" · Click to control"
			household_chips[str(member.id)]=chip
		if not pet_list.is_empty():
			var pet_caption:=small_caps("Pets",Vector2(28,chip_top+48),Vector2(108,18))
			pet_caption.add_theme_color_override("font_color",P.INK)
			for index:int in range(pet_list.size()):
				var pet:Dictionary=pet_list[index]
				var pet_id:String=str(pet.id)
				var pet_chip=button("",Vector2(28+index*35,chip_top+66),Vector2(31,34),func():show_pet_card(pet_id),pet_id==selected_pet_id)
				pet_chip.name="PetChip_"+pet_id
				# The chip wears the animal itself, so a household with two cats can
				# tell them apart from the life box without opening either card.
				pet_thumbnail(Vector2(29+index*35,chip_top+67),Vector2(29,32),pet,ui)
				pet_chip.tooltip_text="%s · %s · Click to open" % [str(pet.name),LifePets.species_label(str(pet.species))]
				compact_button(pet_chip)
				pet_chip.size=Vector2(31,34)
				pet_chips[pet_id]=pet_chip
	var bar_width:float=interface_width()-40.0
	card(Vector2(interface_local_x(20.0),718),Vector2(bar_width,162),P.WHITE,18)
	line(Vector2(304,738),Vector2(1,121))
	line(Vector2(964,738),Vector2(1,121))
	card(Vector2(36,739),Vector2(73,90),P.PALE,12)
	# A 3D portrait uses the same customized model as the live actor.
	model_thumbnail("character",Vector2(36,732),Vector2(73,105),true)
	mood_ring=Panel.new()
	mood_ring.mouse_filter=Control.MOUSE_FILTER_IGNORE
	var ring_box:StyleBoxFlat=StyleBoxFlat.new()
	ring_box.bg_color=Color(1,1,1,0)
	ring_box.set_border_width_all(3)
	ring_box.set_corner_radius_all(14)
	mood_ring.add_theme_stylebox_override("panel",ring_box)
	rect(mood_ring,Vector2(36,732),Vector2(73,105))
	var household_name=text_label(str(sim.character.name),Vector2(123,739),Vector2(174,31),22,P.INK,true)
	household_name.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
	household_name.size=Vector2(174,31)
	household_name.tooltip_text=str(sim.character.name)
	household_name.mouse_filter=Control.MOUSE_FILTER_PASS
	mood_pill=Panel.new()
	mood_pill.mouse_filter=Control.MOUSE_FILTER_IGNORE
	var pill_box:StyleBoxFlat=StyleBoxFlat.new()
	pill_box.bg_color=Color(P.TEAL.r,P.TEAL.g,P.TEAL.b,.16)
	pill_box.set_corner_radius_all(13)
	mood_pill.add_theme_stylebox_override("panel",pill_box)
	rect(mood_pill,Vector2(120,775),Vector2(172,30))
	mood_label=text_label("Feeling inspired",Vector2(124,778),Vector2(165,26),14,P.TEAL)
	age_label=text_label(str(LifeLifecycle.LABELS[str(sim.character.age_stage)]),Vector2(124,810),Vector2(160,25),12,P.MUTED)
	age_label.mouse_filter=Control.MOUSE_FILTER_PASS
	moodlet_tiles.clear()
	for i in range(4):
		var tile:Panel=Panel.new()
		var tile_box:StyleBoxFlat=StyleBoxFlat.new()
		tile_box.set_corner_radius_all(5)
		tile.add_theme_stylebox_override("panel",tile_box)
		rect(tile,Vector2(39+i*18,811),Vector2(16,16))
		var mark:Label=text_label("",Vector2(0,0),Vector2(16,16),11,P.WHITE,false,tile)
		mark.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
		mark.name="Mark"
		tile.gui_input.connect(func(event:InputEvent):
			if event is InputEventMouseButton and event.pressed and event.button_index==MOUSE_BUTTON_LEFT:show_person())
		moodlet_tiles.append(tile)
	var center_button:=button("Center",Vector2(42,841),Vector2(111,27),center_lifelet)
	center_button.name="CenterLifelet"
	center_button.tooltip_text="Show this Lifelet and their floor; keep the current floor during stair transit"
	# The action column owns x>=326 (its progress bar starts at 328). Wishes and
	# Rewards share the space between Center and that column without crossing it,
	# so neither button is swallowed by Cancel action.
	var wishes_button:=button("Wishes",Vector2(165,841),Vector2(76,27),show_wishes)
	compact_button(wishes_button)
	var rewards_button:=button("Rewards",Vector2(245,841),Vector2(76,27),show_rewards)
	compact_button(rewards_button)
	action_context=text_label("TODAY IS YOURS",Vector2(327,738),Vector2(286,23),11,P.MUTED)
	action_context.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
	action_context.mouse_filter=Control.MOUSE_FILTER_PASS
	action_label=text_label("Enjoying a moment",Vector2(326,770),Vector2(286,36),21,P.INK,true)
	action_label.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
	action_bar=ProgressBar.new()
	action_bar.show_percentage=false
	rect(action_bar,Vector2(328,818),Vector2(274,7))
	cancel_action_button=button("Cancel action",Vector2(326,842),Vector2(144,26),cancel_current_action)
	time_label=text_label(sim.get_clock_text(),Vector2(652,736),Vector2(280,33),18,P.INK)
	time_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	time_label.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
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
	# Temporary energy is its own pool with its own darker bar, so a coffee's
	# lift is never confused with the ordinary energy need. The card sits in the
	# HUD band the queue strip leaves free and appears only while there is a
	# second wind left to show, exactly as the moodlet tiles do.
	second_wind_card=card(Vector2(24,336),Vector2(262,72),Color("f8faf2",.92),14)
	second_wind_card.name="SecondWindCard"
	second_wind_card.mouse_filter=Control.MOUSE_FILTER_IGNORE
	var wind_caption:=small_caps("Second wind",Vector2(18,8),Vector2(190,20),second_wind_card)
	wind_caption.add_theme_color_override("font_color",P.INK)
	wind_caption.tooltip_text=LifeSim.SECOND_WIND_TOOLTIP
	second_wind_value=text_label("0",Vector2(18,30),Vector2(58,26),20,SECOND_WIND_COLOR,true,second_wind_card)
	second_wind_value.tooltip_text=LifeSim.SECOND_WIND_TOOLTIP
	second_wind_bar=ProgressBar.new()
	second_wind_bar.name="SecondWindBar"
	second_wind_bar.show_percentage=false
	rect(second_wind_bar,Vector2(80,38),Vector2(164,9),second_wind_card)
	second_wind_bar.mouse_filter=Control.MOUSE_FILTER_PASS
	var wind_fill:StyleBoxFlat=P.panel(SECOND_WIND_COLOR,5)
	wind_fill.content_margin_top=0;wind_fill.content_margin_bottom=0
	second_wind_bar.add_theme_stylebox_override("fill",wind_fill)
	second_wind_bar.add_theme_stylebox_override("background",P.panel(Color("cfd8d2"),5))
	second_wind_bar.tooltip_text=LifeSim.SECOND_WIND_TOOLTIP
	if panel_tab=="Needs":
		var nms=["hunger","energy","hygiene","bladder","fun","social"]
		for i in range(6):
			var key:String=nms[i]
			var p=Vector2(989+(i%2)*208,779+(i/2)*29)
			var title:Label=text_label(key.capitalize(),p,Vector2(69,22),12)
			title.tooltip_text=_need_tooltip(key,80.0)
			title.mouse_filter=Control.MOUSE_FILTER_PASS
			title.gui_input.connect(func(event:InputEvent):_need_row_clicked(event,key))
			var b=ProgressBar.new();b.show_percentage=false
			rect(b,p+Vector2(69,8),Vector2(105,7))
			b.mouse_filter=Control.MOUSE_FILTER_PASS
			b.gui_input.connect(func(event:InputEvent):_need_row_clicked(event,key))
			var fill:StyleBoxFlat=P.panel(P.TEAL,5)
			fill.content_margin_top=0;fill.content_margin_bottom=0
			b.add_theme_stylebox_override("fill",fill)
			need_bars[key]=b;need_fills[key]=fill
			var value:Label=text_label("80",p+Vector2(181,0),Vector2(24,22),12,P.INK)
			value.tooltip_text=_need_tooltip(key,80.0)
			value.mouse_filter=Control.MOUSE_FILTER_PASS
			value.gui_input.connect(func(event:InputEvent):_need_row_clicked(event,key))
			need_values[key]=value
		# A pregnancy is not a need, but it is a meter the mother watches fill.
		# It appears under the needs grid only while somebody is expecting.
		pregnancy_meter=null;pregnancy_label=null
		if household.pregnancy_mother_id()==bound_member_id:
			var pp:=Vector2(989,858)
			pregnancy_label=text_label("Pregnancy",pp,Vector2(120,19),12,P.TEAL)
			pregnancy_label.tooltip_text="The baby is on the way. The meter fills toward the birth."
			pregnancy_meter=ProgressBar.new();pregnancy_meter.show_percentage=false
			rect(pregnancy_meter,pp+Vector2(120,8),Vector2(290,7))
			var pfill:StyleBoxFlat=P.panel(Color("d98cb0"),5)
			pfill.content_margin_top=0;pfill.content_margin_bottom=0
			pregnancy_meter.add_theme_stylebox_override("fill",pfill)
			pregnancy_meter.add_theme_stylebox_override("background",P.panel(Color("e6dcd4"),5))
	elif panel_tab=="Skills":
		for i in range(mini(8,sim.skills.size())):
			var key:String=sim.skills.keys()[i]
			var p=Vector2(989+(i%2)*208,779+(i/2)*25)
			text_label(key.capitalize(),p,Vector2(87,22),12)
			var progress_text:Label=text_label("0%",p+Vector2(89,0),Vector2(44,22),10,P.MUTED)
			progress_text.mouse_filter=Control.MOUSE_FILTER_PASS
			skill_progress_labels[key]=progress_text
			skill_labels[key]=text_label("Level %d" % sim.skills[key].level,p+Vector2(137,0),Vector2(62,22),12,P.TEAL)
			var progress_bar:=ProgressBar.new();progress_bar.show_percentage=false
			rect(progress_bar,p+Vector2(0,20),Vector2(196,3))
			skill_bars[key]=progress_bar
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
		career_labels["work"]=button("Go to school",Vector2(1241,779),Vector2(149,37),_go_to_school,true)
		career_labels["homework"]=button("Homework",Vector2(1241,824),Vector2(149,32),func():queue_nearest("desk","homework"))
		button("School record →",Vector2(989,848),Vector2(230,24),show_school_record)
	else:
		career_labels["title"]=text_label(sim.career.title,Vector2(989,778),Vector2(235,28),19,P.INK,true)
		var requirement:Dictionary=sim.promotion_requirement()
		var details_text:String="Level %d  ·  ℒ%d / shift" % [sim.career.level,sim.career.salary]
		if not requirement.is_empty() and not bool(requirement.met):details_text+="  ·  Next: %s %d" % [str(requirement.skill).capitalize(),int(requirement.level)]
		career_labels["details"]=text_label(details_text,Vector2(990,814),Vector2(234,27),12,P.MUTED)
		career_labels["details"].tooltip_text="" if requirement.is_empty() else ("Promotion to %s needs %s level %d and full performance." % [str(requirement.next_title),str(requirement.skill).capitalize(),int(requirement.level)])
		career_labels["work"]=button("Go to work",Vector2(1241,779),Vector2(149,37),_go_to_work,true)
		button("Career details",Vector2(1241,824),Vector2(149,32),show_career_record)
		if sim.character.traits.has("Active"):
			# An Active Lifelet's own habit: out of the front door and around the
			# block, offered beside the work departure it shares a target with.
			button("Morning run",Vector2(989,848),Vector2(230,24),_morning_run)

func _update_selection_marker(delta: float) -> void:
	# The selected Lifelet wears a floating gem tinted by their current mood.
	if selection_marker==null:
		selection_marker=MeshInstance3D.new()
		selection_marker.name="SelectionMarker"
		var gem:SphereMesh=SphereMesh.new()
		gem.radius=.11;gem.height=.27;gem.radial_segments=4;gem.rings=2
		selection_marker.mesh=gem
		var shine:StandardMaterial3D=StandardMaterial3D.new()
		shine.roughness=.25;shine.metallic=.15
		shine.emission_enabled=true;shine.emission_energy=.55
		selection_marker.material_override=shine
		selection_marker.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		world.add_child(selection_marker)
	marker_time+=delta
	var actor:Node3D=world.actors.get(household.selected_id())
	var show:bool=mode in ["live","build"] and is_instance_valid(actor) and actor.is_visible_in_tree() and not sim.is_away()
	selection_marker.visible=show
	if not show:return
	var height:float=float(actor.call("get_display_height")) if actor.has_method("get_display_height") else 1.76
	selection_marker.global_position=actor.to_global(Vector3(0,height+.26+sin(marker_time*2.2)*.035,0))
	selection_marker.rotate_y(delta*1.6)
	var tone:Color=sim.get_mood().color
	var shine:StandardMaterial3D=selection_marker.material_override
	shine.albedo_color=tone
	shine.emission=tone


## The queued actions for the controlled Lifelet. They used to be drawn in a
## bare strip at y=650, floating over the middle of the 3D scene with no
## background, which read as detached chrome. They now sit in their own card
## directly under the goal card, alongside the other HUD cards, and the card is
## only present while something is actually queued.
var queue_card: Panel
var queue_scroll: ScrollContainer

func draw_queue() -> void:
	queue_card=card(Vector2(24,268),Vector2(262,58),Color("f8faf2",.92),14)
	queue_card.mouse_filter=Control.MOUSE_FILTER_IGNORE
	# Children of a card position inside it, so the caption and the strip use the
	# card's own local coordinates rather than the canvas ones they had before.
	queue_caption=small_caps("Queue",Vector2(12,4),Vector2(65,18),queue_card)
	queue_caption.add_theme_color_override("font_color",P.INK)
	queue_toggle=button("−",Vector2(236,4),Vector2(20,20),_toggle_queue,false,queue_card)
	compact_button(queue_toggle)
	queue_toggle.tooltip_text="Collapse action queue"
	queue_scroll=ScrollContainer.new()
	queue_scroll.vertical_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	queue_scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_AUTO
	rect(queue_scroll,Vector2(72,6),Vector2(160,46),queue_card)
	queue_box=HBoxContainer.new()
	queue_box.add_theme_constant_override("separation",8)
	queue_scroll.add_child(queue_box)
	queue_box.custom_minimum_size=Vector2(0,42)
	_update_queue_collapse()

func _toggle_queue() -> void:
	queue_collapsed=not queue_collapsed
	_update_queue_collapse()

func _update_queue_collapse() -> void:
	if not is_instance_valid(queue_card) or not is_instance_valid(queue_scroll) or not is_instance_valid(queue_toggle):
		return
	if queue_collapsed:
		queue_scroll.visible=false
		queue_card.size=Vector2(96,26)
		queue_toggle.position=Vector2(72,3)
		queue_toggle.text="+"
		queue_toggle.tooltip_text="Expand action queue"
	else:
		queue_scroll.visible=true
		queue_card.size=Vector2(262,58)
		queue_toggle.position=Vector2(236,4)
		queue_toggle.text="−"
		queue_toggle.tooltip_text="Collapse action queue"

func refresh_hud() -> void:
	if portrait_stale and mode=="live" and not overlay_open:
		# A changed top deserves a fresh portrait; redraw once, outside modal panels.
		portrait_stale=false
		draw_live()
		return
	_refresh_guest_status()
	if household and bound_member_id!=household.selected_id():return
	if mode not in ["live","build"]:return
	for value in speed_buttons:speed_buttons[value].set_pressed_no_signal(int(value)==sim.speed)
	_refresh_progress_labels()
	if funds_label:
		funds_label.text="ℒ %s" % commas(sim.funds)
		var keeps:PackedStringArray=household.keepsake_lines() if household else PackedStringArray()
		funds_label.tooltip_text="Household purse, in %s." % P.CURRENCY_NAME if keeps.is_empty() else "Purse plus family keepsakes:\n• "+ "\n• ".join(keeps)
	if time_label:time_label.text=sim.get_clock_text()+ ("  ·  Paused" if sim.speed==0 else "")
	if mood_label:
		var mood=sim.get_mood()
		var strength:int=0
		for entry:Dictionary in sim.moodlets:
			if int(entry.strength)>strength:strength=int(entry.strength)
		mood_label.text=str(mood.label)+(" +%d" % strength if strength>0 else "")
		mood_label.add_theme_color_override("font_color",mood.color)
		var effect:Dictionary=LifeSim.emotion_effect(str(mood.label))
		mood_label.tooltip_text=str(mood.description)+("" if effect.is_empty() else "\n"+str(effect.summary))
		if mood_ring:
			var ring:StyleBoxFlat=mood_ring.get_theme_stylebox("panel")
			var worst:float=100.0
			for key:String in sim.needs:worst=minf(worst,float(sim.needs[key]))
			ring.border_color=Color("cf6b5a") if worst<15.0 else (Color("dca657") if worst<35.0 else mood.color)
		if mood_pill:
			var pill:StyleBoxFlat=mood_pill.get_theme_stylebox("panel")
			pill.bg_color=Color(mood.color.r,mood.color.g,mood.color.b,.16)
		for i in range(moodlet_tiles.size()):
			var tile:Panel=moodlet_tiles[i]
			var index:int=sim.moodlets.size()-1-i
			if index<0:
				tile.visible=false
				continue
			tile.visible=true
			var entry:Dictionary=sim.moodlets[index]
			var box:StyleBoxFlat=tile.get_theme_stylebox("panel")
			var tone:Color=LifeSim.emotion_color(str(entry.emotion))
			box.bg_color=Color(tone.r,tone.g,tone.b,.9)
			var mark:Label=tile.get_node_or_null("Mark") as Label
			if mark:mark.text=str(entry.emotion).left(1)
			tile.tooltip_text="%s · %s · %d min" % [str(entry.emotion),str(entry.description),int(entry.remaining)]
	for key in need_bars:
		var value:float=sim.needs[key]
		need_bars[key].value=value
		var c=P.TEAL if value>45 else (P.GOLD if value>22 else P.CORAL)
		if need_fills.has(key):need_fills[key].bg_color=c
		need_values[key].text=str(int(value))
		need_bars[key].tooltip_text=_need_tooltip(key,value)
		need_values[key].tooltip_text=_need_tooltip(key,value)
	if is_instance_valid(pregnancy_meter):
		var progress:float=household.pregnancy_progress()
		pregnancy_meter.value=maxf(0.0,progress)*100.0
		if is_instance_valid(pregnancy_label):
			pregnancy_label.text="Pregnancy · %d%%" % int(maxf(0.0,progress)*100.0)
	if is_instance_valid(second_wind_card):
		# The card is chrome for a pool that is usually empty, so it shows only
		# while a coffee is still working; the bar reads the second wind and
		# never the ordinary energy need.
		var wind:float=clampf(sim.second_wind,0.0,LifeSim.SECOND_WIND_MAX)
		second_wind_card.visible=wind>0.0
		second_wind_bar.value=wind
		second_wind_value.text=str(int(round(wind)))
		var wind_text:String="Second wind · %d of %d. %s" % [int(round(wind)),int(LifeSim.SECOND_WIND_MAX),LifeSim.SECOND_WIND_TOOLTIP]
		second_wind_bar.tooltip_text=wind_text
		second_wind_value.tooltip_text=wind_text
	var away:Dictionary=sim.get_away_state()
	for id:String in household_chips:
		var chip:Button=household_chips[id]
		if not is_instance_valid(chip):continue
		var member:LifeSim=household.member_sim(id)
		var member_away:Dictionary=member.get_away_state()
		chip.modulate=P.WHITE if member_away.is_empty() else Color("9aafa9")
		chip.tooltip_text=str(member.character.name)+" · "+(_away_status(member_away) if not member_away.is_empty() else "At home · Click to control")
	if is_instance_valid(cancel_action_button):
		cancel_action_button.text="Come home early" if str(away.get("phase",""))=="away" else "Cancel action"
		cancel_action_button.disabled=str(away.get("phase",""))=="returning"
	var action=sim.get_current_action()
	var together:Dictionary=household.cooperative_presentation(bound_member_id) if not str(action.get("cooperation_id","")).is_empty() else {}
	var partner:LifeSim=household.member_sim(str(together.get("partner_id","")))
	# A shared dance is presented as the group rather than as one partner: the
	# WITH line names the count, and the label says who is still dancing.
	var dancing:bool=str(together.get("kind",""))==LifeDancePlan.SESSION_KIND
	var dancer_count:int=int(together.get("dancer_count",0))
	if action_context:
		action_context.text=("DANCING WITH %d OTHERS" % maxi(0,dancer_count-1)) if dancing else ("WITH "+str(partner.character.name).to_upper() if partner else "TODAY IS YOURS")
		var meal_company:String=meal_flow.company_label(bound_member_id)
		if not meal_company.is_empty():action_context.text=meal_company
		action_context.tooltip_text=("Dancing with %d Lifelets at the record player" % dancer_count) if dancing else ("Learning with "+str(partner.character.name) if partner else "")
	if action_label:
		action_label.text="Enjoying a moment" if action.is_empty() else ((("Waiting for " if waiting_for_target else "Walking to ") if action.phase=="approach" else "")+str(action.label))
		if str(action.get("id","")) in ["school_day","career_day"] and str(action.get("phase",""))=="approach":action_label.text="Walking to work" if str(action.id)=="career_day" else "Walking to school"
		if str(action.get("id",""))=="arrive_home":action_label.text="Waiting for a clear path" if bool(adoption_flow.blocked.get(bound_member_id,false)) else "Walking home"
		# A Lifelet stepping back for somebody, or squeezing past a crowd, says so.
		if str(action.get("phase",""))=="approach" and traversal.standing_off(bound_member_id):action_label.text="Making way, then "+str(action.label).to_lower()
		elif str(action.get("phase",""))=="approach" and traversal.squeezing(bound_member_id):action_label.text="Squeezing past to "+str(action.label).to_lower()
		if partner:
			if str(together.get("phase",""))=="active":
				action_label.text="Learning together" if str(together.role)=="learner" else "Helping with homework"
			elif bool(together.get("ready",false)):
				action_label.text="Waiting for "+str(partner.character.name)
			else:action_label.text="Meeting at the desk"
		if dancing:
			if str(together.get("phase",""))=="active":action_label.text="Dancing together"
			elif bool(together.get("ready",false)):action_label.text="Waiting for the others to reach the record player"
			else:action_label.text="Meeting at the record player"
		var meal_title:String=meal_flow.action_title(action)
		if not meal_title.is_empty():action_label.text=meal_title
		if traversal.active(bound_member_id):
			var route:Dictionary=traversal.routes[bound_member_id]
			if bool(route.safety):action_label.text="Reaching the landing"
			elif str(route.phase)=="waiting":action_label.text="Waiting for the stairs"
			elif str(route.phase)=="transit":
				var leg:Dictionary=route.legs[int(route.cursor)]
				action_label.text="Going upstairs" if int(leg.direction)==1 else "Going downstairs"
			elif action.is_empty():action_label.text="Walking"
		elif walk_only and action.is_empty():action_label.text="Walking"
		action_label.tooltip_text=action_label.text+(" · With "+str(partner.character.name)+". Canceling ends the activity for both Lifelets." if partner else "")
		action_label.mouse_filter=Control.MOUSE_FILTER_PASS
		action_label.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
	if not away.is_empty():
		if action_context:
			action_context.text=str(sim.career.title).to_upper() if str(away.activity)=="career" else str(LifeEducation.summary(sim.education).school).to_upper()
			action_context.tooltip_text="Weekdays · 09:00–17:00" if str(away.activity)=="career" else "Weekdays · 08:00–15:00"
		if action_label:action_label.text=_away_status(away);action_label.tooltip_text=action_label.text
	if action_bar:action_bar.value=0 if action.is_empty() else float(action.progress)*100
	if queue_box:
		var key:String=bound_member_id+str(away.get("phase",""))+str(sim.action_queue.map(func(a:Dictionary):return a.id+":"+str(a.phase)+":"+str(a.get("cooperation_id",""))))
		if key!=last_queue:
			last_queue=key
			for c in queue_box.get_children():
				queue_box.remove_child(c)
				c.queue_free()
			for i in range(sim.action_queue.size()):
				var a:Dictionary=sim.action_queue[i]
				var b=Button.new();b.custom_minimum_size=Vector2(150,42)
				queue_box.add_child(b)
				b.size=Vector2(150,42)
				compact_button(b)
				b.custom_minimum_size=Vector2(150,42)
				var shared:bool=not str(a.get("cooperation_id","")).is_empty()
				var chip_dance:bool=str(a.id)==LifeDancePlan.ACTION_ID
				var chip_view:Dictionary=household.cooperative_presentation(bound_member_id) if chip_dance else {}
				var queue_title:String=(("Dance together · %d Lifelets" % int(chip_view.get("dancer_count",1))) if chip_dance else ("Learn together" if str(a.id)=="homework" else "Help with homework")) if shared else str(a.label)
				if str(a.id) in ["school_day","career_day"] and not away.is_empty():queue_title=("At work" if str(a.id)=="career_day" else "At school") if str(away.phase)=="away" else "Coming home"
				# Two activities can share a label but differ in target — two
				# cooks, or a read at either bookshelf. Naming the target tells the
				# player which chip cancels which activity.
				var target_kind:String=_queue_target_kind(a)
				if not target_kind.is_empty():queue_title+=" · "+target_kind
				var title=text_label(queue_title,Vector2(8,5),Vector2(118,31),12,P.INK,false,b)
				title.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
				title.size=Vector2(118,31)
				var returning:bool=str(a.id) in ["school_day","career_day"] and str(away.get("phase",""))=="returning"
				b.disabled=returning
				if not returning:text_label("×",Vector2(130,5),Vector2(16,31),16,P.MUTED,false,b)
				b.tooltip_text=queue_title+(" · With "+str(partner.character.name) if shared and partner else "")+(" · Click to cancel for both Lifelets" if shared else " · Click to cancel this activity")
				if chip_dance:b.tooltip_text=queue_title+" · Canceling one dancer leaves the others dancing"
				if returning:b.tooltip_text="Coming home · Available after reaching the front garden"
				b.pressed.connect(func():cancel_current_action(i))
		if is_instance_valid(queue_caption):
			queue_caption.text="Next up" if sim.action_queue.size()>1 else "Queue"
		# The queue card is only meaningful while something is queued.
		if is_instance_valid(queue_card):
			queue_card.visible=not sim.action_queue.is_empty()

func commas(value:int) -> String:
	var s=str(value)
	var out=""
	for i in range(s.length()):
		if i>0 and (s.length()-i)%3==0:out+="," 
		out+=s[i]
	return out

## A live model preview. `style`, `size` and `variant_color` describe which member
## of a variant family to show, so the thumbnail beside a cell or a choice is the
## object the player would actually get.
func model_thumbnail(kind:String,p:Vector2,s:Vector2,portrait:bool=false,parent:Node=ui,appearance:Dictionary={},style:String="",size:String="",variant_color:String="") -> void:
	# Resolve the model before building any node: a catalogued kind whose art is
	# not yet on disk leaves the cell blank rather than leaving a live but empty
	# viewport behind and reporting an engine error.
	var data:Dictionary={}
	var packed:Resource=null
	if not portrait:
		data=LifeCatalog.get_item(kind)
		packed=_variant_model(kind,style,data)
		if packed==null:return
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
		model=packed.instantiate()
		if model==null:return
		root.add_child(model)
		var model_scale:float=Variants.size_scale(size)
		if not is_equal_approx(model_scale,1.0):model.scale=Vector3.ONE*model_scale
		if not variant_color.is_empty():_tint_preview(model,data,variant_color)
	var cam=Camera3D.new();root.add_child(cam)
	cam.projection=Camera3D.PROJECTION_ORTHOGONAL
	if portrait:
		var center:Vector3=model.call("get_portrait_center") if model.has_method("get_portrait_center") else Vector3(0,1.52,0)
		var height:float=float(model.call("get_display_height")) if model.has_method("get_display_height") else 1.76
		var ratio:float=clampf(height/1.76,.8,1.1)
		cam.size=.71*ratio;cam.position=Vector3(.06,center.y+.02*ratio,3);cam.look_at(center-Vector3(0,.07*ratio,0))
	else:
		# A three-quarter view whose elevation follows the model's own
		# proportions, not a fixed rise. A low, long vehicle is looked at almost
		# level so it reads along its length; a piece as tall as it is wide (a
		# chair, a wardrobe) still gets the steep view that suits it. The old
		# camera sat 2.3 m up for everything, so a 4.19 m car 1.48 m tall was
		# viewed at the same steep angle as a chair and read as a vertical
		# incline. The footprint and height come from the variant, so a size
		# choice frames itself too.
		var framed:Vector2=Variants.footprint(data,size)
		var framed_height:float=Variants.height(data,size)
		var span:float=maxf(maxf(framed.x,framed.y),framed_height)
		var focus:Vector3=Vector3(0,framed_height*.44,0)
		var elevation:float=clampf(framed_height/span*.55,.12,.45)
		cam.size=span*1.45
		cam.position=focus+Vector3(span*.78,span*elevation,span*1.02)
		cam.look_at(focus)
	var light=DirectionalLight3D.new();root.add_child(light);light.rotation_degrees=Vector3(-38,-32,0);light.light_energy=.65
	var env=WorldEnvironment.new();var e=Environment.new();e.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;e.ambient_light_color=Color.WHITE;e.ambient_light_energy=.32;env.environment=e;root.add_child(env)
	freeze_viewport.call_deferred(sv.get_instance_id())

## The packed model for one style of a kind, or null when its art is not on
## disk. One place decides that, so every caller of a model — the thumbnail, the
## ghost and the placed body — agrees about what exists.
func _variant_model(kind:String,style:String,data:Dictionary) -> Resource:
	var model_path:String=Variants.model_path(kind,Variants.style_or_default(style,data))
	if not ResourceLoader.exists(model_path):return null
	var packed:Resource=load(model_path)
	return packed if packed is PackedScene else null


## Paint a preview's own `Tint` surface, which is the same surface a placed
## furnishing's colour overrides, so a preview and its purchase always match.
func _tint_preview(model:Node3D,data:Dictionary,color:String) -> void:
	if not Variants.color_offered(color,data):return
	var tint:=StandardMaterial3D.new()
	tint.albedo_color=Color(color)
	tint.roughness=.62
	tint.metallic=.04
	for node:Node in model.find_children("*","MeshInstance3D",true,false):
		var mesh_node:MeshInstance3D=node
		if Variants.is_tint(mesh_node.name):mesh_node.material_override=tint

func freeze_viewport(viewport_id:int) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var viewport=instance_from_id(viewport_id)
	if is_instance_valid(viewport):viewport.render_target_update_mode=SubViewport.UPDATE_ONCE

func set_build_mode(value:bool) -> void:
	if value and residents.home_visit.active():show_notice("Say goodbye and wait for your guest to leave before building.");return
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
		build_transactions.clear_history()
		mode="live"
		sim.set_speed(speed_before_build)
	world.set_build(value)
	if value:world.construction.quote_provider=build_transactions.prepare
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
	build_quote.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	build_quote.custom_maximum_size=Vector2(408,-1)
	build_quote.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	var catalog_width:float=interface_width()-40.0
	card(Vector2(interface_local_x(20.0),643),Vector2(catalog_width,239),P.WHITE,18)
	small_caps("Make yourself at home",Vector2(40,657))
	text_label("Build & buy",Vector2(38,687),Vector2(210,42),29,P.INK,true)
	# The filter row grows with the catalogue, so it scrolls sideways rather than
	# running the last category off the canvas where it could not be pressed.
	var category_scroll:=ScrollContainer.new()
	category_scroll.name="CatalogCategories"
	category_scroll.vertical_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	rect(category_scroll,Vector2(294,663),Vector2(940,37))
	var category_row:=HBoxContainer.new()
	category_row.add_theme_constant_override("separation",6)
	category_scroll.add_child(category_row)
	for category:String in LifeCatalog.CATEGORIES + ["Land"]:
		var tab=button(category,Vector2.ZERO,Vector2(112,35),func():catalog_category=category;draw_live(),catalog_category==category,category_row)
		tab.name="CatalogCategory_"+category
		compact_button(tab);tab.size=Vector2(112,35)
	button("Undo",Vector2(1250,663),Vector2(144,35),undo_build)
	var storage_button=button("Storage",Vector2(214,745),Vector2(78,37),show_storage)
	compact_button(storage_button)
	storage_button.tooltip_text="Your household storage unit. Store furnishing away, take it out, or sell it."
	# The catalogue strip begins at x=292; the level and storage controls share
	# that left column in full, so none of them may extend into the strip or the
	# strip would swallow their clicks.
	var ground_button=button("Ground",Vector2(40,745),Vector2(78,37),func():set_build_level(0),world.view_level==0)
	compact_button(ground_button)
	var upper_button=button("Upper",Vector2(127,745),Vector2(78,37),func():set_build_level(1),world.view_level==1)
	compact_button(upper_button)
	var search:=LineEdit.new();search.placeholder_text="Search furnishings";search.text=catalog_search
	rect(search,Vector2(40,792),Vector2(232,34))
	search.text_changed.connect(func(value:String):
		catalog_search=value
		draw_live()
		var boxes:Array=ui.find_children("","LineEdit",true,false)
		if not boxes.is_empty():
			var box:LineEdit=boxes.front()
			box.grab_focus();box.caret_column=box.text.length())
	paragraph("Click to place  ·  R rotate  ·  Esc cancel",Vector2(41,834),Vector2(232,40),12)
	if catalog_category=="Land":
		show_land_panel()
		return
	if catalog_category=="Structure":
		button("Wall",Vector2(305,725),Vector2(146,46),func():begin_construction("wall"))
		button("Room",Vector2(461,725),Vector2(146,46),func():begin_construction("room"))
		button("Door",Vector2(617,725),Vector2(146,46),func():begin_construction("door"))
		button("Floor",Vector2(773,725),Vector2(146,46),func():begin_construction("floor"))
		button("Stairs",Vector2(929,725),Vector2(146,46),func():begin_construction("stairs"))
		button("Remove floor / stairs",Vector2(1085,725),Vector2(294,46),func():begin_construction("remove_structure"))
		if world.construction.tool=="paint":
			# While the paint tool is active the wall swatches take this row and
			# the floor finishes drop one row down, so both stay reachable.
			for i in range(8):
				var colour:String=["eae7d7","8faf9f","e6d8c5","c8d7e0","d9b7a3","7d8a99","efd9a0","a3ad7a"][i]
				var swatch=button("",Vector2(305+i*58,791),Vector2(50,32),func():world.construction.paint_material=colour;draw_live())
				swatch.tooltip_text=["Cream","Sage","Blush","Sky","Clay","Dusk","Butter","Moss"][i]+" wall paint"
				swatch.add_theme_stylebox_override("normal",P.panel(Color(colour),16,P.TEAL if world.construction.paint_material==colour else Color("ffffff"),3))
				swatch.add_theme_stylebox_override("hover",P.panel(Color(colour).lightened(.1),16,P.TEAL,3))
				if world.construction.paint_material==colour:swatch.text="•";swatch.add_theme_color_override("font_color",Color.WHITE)
			button("Warm oak",Vector2(305,836),Vector2(146,31),func():change_floor("cfa97e"))
			button("Pale stone",Vector2(461,836),Vector2(146,31),func():change_floor("dcd6c6"))
			button("Walnut",Vector2(617,836),Vector2(146,31),func():change_floor("896953"))
		else:
			button("Warm oak",Vector2(305,784),Vector2(150,47),func():change_floor("cfa97e"))
			button("Pale stone",Vector2(465,784),Vector2(150,47),func():change_floor("dcd6c6"))
			button("Walnut",Vector2(625,784),Vector2(150,47),func():change_floor("896953"))
		button("Wall view",Vector2(785,784),Vector2(130,47),func():world.set_cutaway(not world.cutaway))
		button("Remove wall",Vector2(925,784),Vector2(140,47),func():begin_construction("erase"))
		var paint=button("Paint wall",Vector2(1075,784),Vector2(150,47),func():begin_construction("paint"),world.construction.tool=="paint")
		paint.tooltip_text="Pick the tool, choose a swatch, then click a wall to repaint that segment."
		var whole=button("Whole room",Vector2(1235,784),Vector2(144,47),func():
			world.construction.paint_scope="wall" if world.construction.paint_scope=="room" else "room"
			draw_live(),world.construction.paint_scope=="room")
		whole.tooltip_text="Paints the enclosed room on the side you click; a wall shared with the next room changes for both rooms."
		button("New roof",Vector2(305,841),Vector2(146,31),func():begin_construction("roof"))
		button("Edit roof",Vector2(461,841),Vector2(146,31),func():begin_construction("roof_edit"))
		button("Remove roof",Vector2(617,841),Vector2(146,31),func():begin_construction("roof_remove"))
		button("Low",Vector2(773,841),Vector2(85,31),func():set_roof_pitch(.25),is_equal_approx(world.construction.roof_pitch,.25))
		button("Medium",Vector2(868,841),Vector2(85,31),func():set_roof_pitch(.5),is_equal_approx(world.construction.roof_pitch,.5))
		button("Steep",Vector2(963,841),Vector2(85,31),func():set_roof_pitch(.75),is_equal_approx(world.construction.roof_pitch,.75))
		roof_visibility_button=button("Hide roofs" if world.construction.roofs_visible else "Show roofs",Vector2(1058,841),Vector2(144,31),func():world.construction.set_roof_visibility(not world.construction.roofs_visible);draw_live())
		button("Sage",Vector2(1212,841),Vector2(78,31),func():set_roof_finish("57736a"),world.construction.roof_material=="57736a")
		button("Slate",Vector2(1300,841),Vector2(79,31),func():set_roof_finish("56606b"),world.construction.roof_material=="56606b")
		return
	if LifeCatalog.paints(world.placement_kind):
		# A paintable furnishing is being placed, so the swatch row replaces the
		# catalogue strip: the player picks the finish, then the spot. Leaving
		# the strip up would offer a second purchase mid-placement anyway.
		draw_car_paint_row()
		return
	var scroll=ScrollContainer.new()
	scroll.name="CatalogStrip"
	scroll.vertical_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	rect(scroll,Vector2(292,717),Vector2(1108,153))
	var row=HBoxContainer.new();row.add_theme_constant_override("separation",10);scroll.add_child(row)
	for kind in LifeCatalog.ITEMS:
		var data:Dictionary=LifeCatalog.ITEMS[kind]
		if catalog_category!="All" and data.category!=catalog_category:continue
		if not catalog_search.strip_edges().is_empty() and not (str(data.label).to_lower().contains(catalog_search.strip_edges().to_lower()) or str(kind).contains(catalog_search.strip_edges().to_lower())):continue
		var cell=Control.new();cell.custom_minimum_size=Vector2(152,140);row.add_child(cell)
		# A family with choices asks the player which one they want before the
		# ghost appears, so a click never silently buys the first style.
		var varied:bool=Variants.has_variants(data)
		var b=button("",Vector2.ZERO,Vector2(152,137),func():pick_furnishing(kind) if varied else begin_purchase(kind),false,cell)
		b.name="Catalog_"+kind
		var from_price:int=Variants.price(data,"")
		var to_price:int=Variants.price(data,"large") if Variants.sizes(data).size()>1 else from_price
		b.tooltip_text=data.label+(" · ℒ%d" % from_price if to_price==from_price else " · ℒ%d–ℒ%d" % [from_price,to_price])
		var seats:int=Variants.seats(data,str(Variants.size_or_default("",data)))
		if seats>1:b.tooltip_text+=" · seats %d" % seats
		if varied:b.tooltip_text+=" · choose style, colour and size"
		model_thumbnail(kind,Vector2(8,2),Vector2(136,88),false,cell,{},str(Variants.style_or_default("",data)),str(Variants.size_or_default("",data)))
		var l=text_label(data.label,Vector2(9,91),Vector2(135,20),11,P.INK,false,cell);l.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
		text_label("ℒ %d" % from_price if to_price==from_price else "ℒ %d–%d" % [from_price,to_price],Vector2(10,112),Vector2(130,20),13,P.TEAL,false,cell)

## Buy a business and hire people to run it. The skill and level each one needs
## are shown, and the purse pays, so running a business is what a long career at
## a high rung actually buys.
func show_business_panel() -> void:
	_begin_pause_overlay()
	var background:ColorRect=ColorRect.new()
	background.color=Color(.08,.17,.15,.28)
	rect(background,Vector2(interface_local_x(0.0),0),interface_size(),overlay)
	card(Vector2(430,84),Vector2(580,780),P.WHITE,24,overlay)
	small_caps("What you have built",Vector2(462,104),Vector2(516,24),overlay)
	text_label("Businesses",Vector2(460,132),Vector2(520,48),31,P.INK,true,overlay)
	var owned:Dictionary=household.business
	if owned.is_empty():
		paragraph("Buy a business once your Lifelet is skilled enough to run one. An owner earns its takings every day, and can hire housemates to work there.",
			Vector2(462,186),Vector2(516,54),14,P.MUTED,overlay)
	else:
		var info:Dictionary=LifeBusiness.info(str(owned.id))
		paragraph("You run the %s. It takes ℒ%s a day and has earned ℒ%s so far." % [
			str(info.label),commas(household.business_income()),commas(int(owned.get("earned",0)))],
			Vector2(462,186),Vector2(516,54),14,P.TEAL,overlay)
		# Hire a housemate, one row each, showing the fee and any refusal.
		var hire_y:float=250.0
		text_label("Staff",Vector2(462,hire_y-24),Vector2(516,22),13,P.MUTED,false,overlay)
		for member:Dictionary in household.members:
			var member_id:String=str(member.id)
			var name:String=str(member.sim.character.name)
			var roster:Array=owned.get("staff",[])
			var employed:bool=roster.has(name)
			var reason:String=LifeBusiness.hire_error(str(owned.id),roster,household.funds)
			if employed:reason="Already works here."
			var row:Button=button(("%s  ✓" if employed else "%s · hire for ℒ%s") % [name.split(" ")[0],commas(LifeBusiness.hire_cost(str(owned.id)))],
				Vector2(462,hire_y),Vector2(516,36),func():_hire_employee(member_id),employed,overlay)
			row.name="Hire_"+member_id
			row.disabled=not reason.is_empty()
			row.tooltip_text=reason if not reason.is_empty() else "Hire %s to work at the business." % name.split(" ")[0]
			hire_y+=44.0
	var scroll:ScrollContainer=ScrollContainer.new()
	scroll.name="BusinessList"
	rect(scroll,Vector2(462,470),Vector2(516,300),overlay)
	var column:VBoxContainer=VBoxContainer.new()
	column.add_theme_constant_override("separation",8)
	scroll.add_child(column)
	for offer:Dictionary in household.business_offers(household.selected_id()):
		var business_id:String=str(offer.id)
		var row:Control=Control.new()
		row.name="BusinessRow_"+business_id
		row.custom_minimum_size=Vector2(498,62)
		column.add_child(row)
		var buy:Button=button("%s · ℒ%s" % [str(offer.label),commas(int(offer.cost))],
			Vector2.ZERO,Vector2(498,32),func():_buy_business(business_id),bool(offer.owned),row)
		buy.name="Business_"+business_id
		buy.disabled=not bool(offer.available)
		buy.tooltip_text=str(offer.reason) if not bool(offer.available) else "Buys the business outright. It then earns money every day."
		var note:Label=text_label(str(offer.reason) if not bool(offer.available) else "%s · ℒ%s a day when staffed · room for %d" % [str(offer.requirements),commas(int(offer.income)),int(offer.staff)],
			Vector2(4,34),Vector2(492,24),11,P.CORAL if not bool(offer.available) else P.MUTED,false,row)
		note.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
	button("Back to work",Vector2(462,788),Vector2(516,42),show_careers,true,overlay)


## Buy one business and show the panel again with its new state.
func _buy_business(business_id:String) -> void:
	var result:Dictionary=household.buy_business(business_id,household.selected_id())
	if not bool(result.ok):
		show_notice(str(result.error))
	else:
		refresh_hud()
		show_notice("You now run the %s." % str(LifeBusiness.info(business_id).label))
	show_business_panel()


## Hire one housemate and show the panel again.
func _hire_employee(member_id:String) -> void:
	var result:Dictionary=household.hire_employee(member_id)
	if not bool(result.ok):
		show_notice(str(result.error))
	else:
		refresh_hud()
		show_notice("Hired. The business pays more with more people working.")
	show_business_panel()


## The land panel: buy the neighbouring plot on any side the lot can grow, and
## watch the ground it would add.
##
## Every offer is priced and gated by `LifeLand` (preloaded as `Land`), so a greyed-out button and a
## refused purchase state exactly the same reason.
func show_land_panel() -> void:
	button("Land",Vector2(305,725),Vector2(146,46),func():pass,true)
	var note:String=Land.describe(LifeBuildingState.land)
	text_label(note,Vector2(463,731),Vector2(420,34),14,P.MUTED,false).autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	var offers:Array=Land.offers(LifeBuildingState.land,sim.funds)
	var x:float=305.0
	for side_index:int in range(offers.size()):
		var offer:Dictionary=offers[side_index]
		var side:String=str(offer.side)
		var bought:int=int(offer.plots)
		var label:String="Buy %s plot · ℒ%s" % [side.to_lower(),commas(int(offer.price))]
		if bought>0:label="Buy %s plot (%d) · ℒ%s" % [side.to_lower(),bought+1,commas(int(offer.price))]
		var buy:Button=button(label,Vector2(x,791),Vector2(230,46),func():_buy_land(side),false)
		buy.name="BuyLand_"+side
		buy.disabled=not bool(offer.available)
		if not bool(offer.available):buy.tooltip_text=str(offer.reason)
		else:buy.tooltip_text="Extends the lot %s by one plot. The lawn, hedge and boundaries all move." % side
		text_label(str(offer.reason) if not bool(offer.available) else "%d bought on this side." % bought,
			Vector2(x+4,841),Vector2(222,24),11,P.CORAL if not bool(offer.available) else P.MUTED,false)
		x+=242.0
	button("Undo",Vector2(1250,725),Vector2(144,35),undo_build)
	button("Wall",Vector2(305,847),Vector2(120,31),func():begin_construction("wall"))
	button("Room",Vector2(433,847),Vector2(120,31),func():begin_construction("room"))


## Buy one neighbouring plot, through the same transaction the build tools use.
func _buy_land(side:String) -> void:
	var result:Dictionary=build_transactions.buy_land(side)
	if not bool(result.ok):
		show_notice(str(result.error));draw_live();return
	refresh_hud()
	show_notice("A new plot %s. The garden is %s" % [side,Land.describe(LifeBuildingState.land)])
	draw_live()

## The paint row for a paintable kind, shown in place of the catalogue strip
## while that furnishing is being placed. It is the same swatch row the Lifelet's
## wardrobe and a pet's collar use, so choosing a car's colour needs no second
## idiom; the pick only changes the shade the next placement records.
func draw_car_paint_row() -> void:
	var chosen:String=pending_paint if LifeCatalog._shade(pending_paint) else LifeCatalog.paint_of({"kind":world.placement_kind})
	small_caps("Paint",Vector2(40,745),Vector2(140,24))
	color_row(LifeCatalog.CAR_PAINTS,chosen,Vector2(292,742),38,12,720,func(shade:String):
		pending_paint=shade
		draw_live())
	paragraph("Choose the finish, then click an open spot. R rotates; Esc cancels.",Vector2(40,782),Vector2(232,66),12)

func change_floor(color:String) -> void:
	if mode=="build":
		var quote:Dictionary=build_transactions.prepare({"op":"structure","tool":"finish","level":world.view_level,"material":color})
		if not bool(quote.ok):show_notice(str(quote.error));return
		var result:Dictionary=build_transactions.commit(quote)
		if not bool(result.ok):show_notice(str(result.error));return
		build_undo.append({"architecture":result.receipt,"level":world.view_level})
		if world.view_level==0:floor_color=color
		refresh_hud();show_notice("A fresh finish for your home.");return
	if world.construction.building_state.is_empty() and color==floor_color:return
	_apply_floor_color(color)
	show_notice("A fresh finish for your home.")

func _apply_floor_color(color:String) -> void:
	if world.view_level==0:floor_color=color
	if current_venue!="home" or not is_instance_valid(world.house):return
	if not world.construction.building_state.is_empty():
		var state:Dictionary=world.construction.snapshot()
		for floor:Dictionary in state.floors:
			if int(floor.level)==world.view_level:floor.material=color
		world.construction.restore(state)
		return
	for node in world.house.get_children():
		if node is MeshInstance3D and node.mesh is BoxMesh and node.mesh.size.x==12 and node.mesh.size.z==10:
			node.material_override=world.material(color)

func build_protection_context() -> Dictionary:
	return LifeBuildProtection.snapshot(self)

func _build_snapshot(funds_delta:int=0) -> Dictionary:
	return {"layout":world.serialize_items(),"funds_delta":funds_delta,"floor":floor_color,"level":world.view_level}

func set_build_level(level:int) -> void:
	if mode!="build" or level not in [0,1]:return
	cancel_placement()
	if world.construction.building_state.is_empty():
		var migrated:Dictionary=build_transactions.current()
		if not bool(migrated.ok):show_notice(str(migrated.error));return
		world.construction.restore(migrated.state);world.rebuild_navigation()
	world.set_view_level(level)
	world.construction.quote_provider=build_transactions.prepare
	if level==1 and not world.construction.has_upper_floor():
		# Second-storey guidance: switching to Upper with no slab yet starts
		# the floor tool itself, so the recipe is one press plus a drag.
		begin_construction("floor")
		show_notice("No upper floor yet, so the Floor tool is ready. Click two corners anywhere over the rooms below — the slab fits itself to the two bearing walls, so a rough rectangle buys the whole floor. Then choose Stairs; it snaps onto the free edge beside the opening.")
	draw_live()

func set_roof_pitch(value:float)->void:
	if mode!="build":return
	world.construction.roof_pitch=value;draw_live()

func set_roof_finish(value:String)->void:
	if mode!="build":return
	world.construction.roof_material=value;draw_live()

func begin_construction(tool:String) -> void:
	if mode!="build":return
	cancel_placement()
	world.construction.quote_provider=build_transactions.prepare
	world.begin_construction(tool)
	if tool in ["roof","roof_edit","roof_remove"]:
		world.set_cutaway(false);world.construction.set_roof_visibility(tool!="roof")
		if tool=="roof":world.placement_angle=0;show_notice("Choose two roof corners. R rotates the ridge; select a pitch and finish before confirming.")
		elif tool=="roof_edit":show_notice("Select a roof, then its two new corners. R rotates; pitch and finish changes are free.")
		else:show_notice("Point at a roof to review its removal. Esc cancels.")
	elif tool=="floor" and world.view_level==0:show_notice("This paints the ground-floor finish. For a second storey, press Upper first — it starts the upper floor tool for you.")
	elif tool=="stairs":world.placement_angle=0;show_notice("Point near the upper slab's free edge. R rotates; the stair snaps to the nearest clear spot with its opening and guard included.")
	elif tool=="remove_structure":show_notice("Point at a floor or staircase to review its removal. Esc cancels.")
	else:show_notice("Click two corners to create a %s. Esc cancels." % tool if tool in ["wall","room","floor"] else "Click a wall to %s. Esc cancels." % ("add a doorway" if tool=="door" else "remove it"))

func on_construction(data:Dictionary) -> void:
	if mode!="build":return
	if data.has("error"):show_notice(str(data.error));return
	if not bool(data.get("valid",false)):return
	if data.get("build_quote") is Dictionary:
		var result:Dictionary=build_transactions.commit(data.build_quote)
		if not bool(result.ok):show_notice(str(result.error));return
		build_undo.append({"architecture":result.receipt,"level":world.view_level})
		world.construction.anchored=false;world.construction.proposal.clear()
		if world.construction.tool in ["roof","roof_edit","roof_remove"]:world.construction.roof_edit_id="";world.construction.set_roof_visibility(true)
		# A staircase is a complete single placement. Clear its ghost before
		# the unchanged pointer can preview another stair in that occupied spot.
		if world.construction.tool=="stairs":world.construction.cancel()
		world.construction.refresh_decorations()
		_refresh_sim_targets(false);refresh_hud()
		var follow_up:=""
		if world.construction.tool=="floor" and world.view_level==1:
			follow_up=" Upper floor added — now choose Stairs and point at its lower end along its edge."
		show_notice("Your structure is in place. %sℒ%d.%s"%["−" if int(result.cost)>=0 else "+",absi(int(result.cost)),follow_up])
		return
	show_notice("Preview this structure again before confirming it.")

func on_placement(kind:String,p:Vector3,angle:float,style:String="",size:String="") -> void:
	if mode!="build" or not LifeCatalog.ITEMS.has(kind):return
	var data:Dictionary=LifeCatalog.get_item(kind)
	var variant:Dictionary=Variants.resolve(data,{"style":style,"size":size})
	if not world.can_place(kind,p,angle,variant.style,variant.size):
		show_notice("Hang this against a wall." if LifeCatalog.wall_mounted(kind) and not world.wall_behind(kind,p,angle,variant.size) else "That space needs a little more room.");return
	var moving:bool=not pending_move.is_empty() and str(pending_move.entry.kind)==kind
	if not pending_move.is_empty() and not moving:cancel_placement()
	# A delivery was already paid for at the truck's counter, so its placement
	# charges nothing; the flag is consumed here and nowhere else, so the order
	# costs the purse exactly once and an abandoned placement does not re-charge.
	var delivered:bool=not pending_delivery.is_empty() and str(pending_delivery.kind)==kind
	if not pending_delivery.is_empty():pending_delivery={}
	# The family's own price, resolved the way the catalogue quotes it: a fence
	# prices from the footprint it covers and a sized family from its size table,
	# so a bare `.price` read crashed on every family that sells either way.
	var price:int=0 if (moving or delivered) else Variants.price(data,variant.size)
	if sim.funds<price:show_notice("You need ℒ%d for this furnishing." % price);return
	var snapshot:Dictionary=pending_move.snapshot if moving else _build_snapshot(price)
	var entry:Dictionary={"id":str(pending_move.entry.id) if moving else "placed_%d" % Time.get_ticks_usec(),"kind":kind,"x":p.x,"z":p.z,"rotation":angle}
	if world.view_level==1:entry["level"]=1
	entry.merge(Variants.record(data,variant.style,variant.color,variant.size),true)
	if moving and pending_move.entry.has("lit"):entry["lit"]=pending_move.entry["lit"] # A moved lamp keeps its switch state.
	if LifeCatalog.paints(kind):
		# A car keeps the finish it was bought or moved with: the row's choice
		# for a new one, the record's own shade when an existing car is moved.
		entry["paint"]=str(pending_move.entry.get("paint","")) if moving else pending_paint
		if not LifeCatalog._shade(str(entry["paint"])):entry["paint"]=LifeCatalog.paint_of({"kind":kind})
	var proposed:Array=world.serialize_items();proposed.append(entry)
	var problem:String=build_transactions.furnishing_error(proposed)
	if not problem.is_empty():show_notice(problem);return
	var protection:Dictionary=build_protection_context()
	_cancel_all_cooperative_actions()
	world.add_item(entry)
	if _find_item(str(entry.id)).is_empty():return
	build_undo.append(snapshot)
	household.set_funds(sim.funds-price)
	build_transactions.furnishing_rebuilt(protection)
	# A post box bought today should already hold what the household has waiting.
	if kind=="post_box":sync_post()
	if moving:
		pending_move.clear()
		world.clear_placement()
	_refresh_sim_targets()
	refresh_hud()
	play_click()
	show_notice("%s moved into place." % LifeCatalog.ITEMS[kind].label if moving else "%s added to your home. −ℒ%d" % [LifeCatalog.ITEMS[kind].label,price])

func undo_build() -> void:
	if mode!="build":return
	cancel_placement()
	if build_undo.is_empty():show_notice("There are no furnishing changes to undo yet.");return
	var data:Dictionary=build_undo.back()
	if data.get("architecture") is Dictionary:
		var result:Dictionary=build_transactions.undo(data.architecture)
		if not bool(result.ok):show_notice(str(result.error));return
		build_undo.pop_back();world.set_view_level(int(data.get("level",0)))
		for floor:Dictionary in world.construction.building_state.floors:
			if int(floor.level)==0:floor_color=str(floor.material);break
		world.construction.refresh_decorations();_refresh_sim_targets(false);refresh_hud()
		show_notice("Your last structure change was undone.");return
	var funds_delta:int=int(data.get("funds_delta",0))
	if sim.funds+funds_delta<0:
		show_notice("You need ℒ%d to restore that furnishing." % -funds_delta);return
	var historical_structure:Dictionary={}
	for entry:Dictionary in data.layout:
		if str(entry.get("kind",""))=="__construction":historical_structure=entry;break
	if not build_transactions.matches_history_structure(historical_structure,str(data.get("floor",floor_color))):
		show_notice("Undo the later structure change before restoring this furnishing.");return
	var furnishing_layout:Array=data.layout.filter(func(entry:Dictionary)->bool:return str(entry.get("kind",""))!="__construction")
	var checked_layout:Array=furnishing_layout.duplicate(true);checked_layout.append(world.construction.snapshot())
	var layout_error:String=build_transactions.furnishing_error(checked_layout)
	if not layout_error.is_empty():show_notice(layout_error);return
	var protection:Dictionary=build_protection_context()
	build_undo.pop_back()
	_cancel_all_cooperative_actions()
	world.clear_placement()
	for item in world.items:item.node.queue_free()
	world.items.clear()
	# A furnishing undo restores only furnishings. The identical live structure
	# retains its current revision and authenticated architectural history.
	for entry:Dictionary in furnishing_layout:world.add_item(entry,false)
	world.construction.refresh_decorations()
	world.rebuild_navigation()
	build_transactions.furnishing_rebuilt(protection)
	household.set_funds(sim.funds+funds_delta)
	world.set_view_level(int(data.get("level",0)))
	if world.construction.building_state.is_empty():_apply_floor_color(str(data.get("floor",floor_color)))
	else:floor_color=str(data.get("floor",floor_color))
	_refresh_sim_targets()
	refresh_hud()
	show_notice("Your last furnishing change was undone.")

## Order the weekly shop from the computer. Every basket the shop delivers is
## listed with its price, what it fills the kitchen by and its own refusal, so
## a greyed-out row and a refused order state exactly the same reason.
func show_grocery_order() -> void:
	_begin_pause_overlay()
	var background:ColorRect=ColorRect.new()
	background.color=Color(.08,.17,.15,.28)
	rect(background,Vector2(interface_local_x(0.0),0),interface_size(),overlay)
	card(Vector2(452,150),Vector2(536,600),P.WHITE,24,overlay)
	small_caps("Order online",Vector2(484,172),Vector2(476,24),overlay)
	text_label("The weekly shop",Vector2(482,200),Vector2(480,46),31,P.INK,true,overlay)
	paragraph(household.kitchen(),Vector2(484,254),Vector2(476,44),15,P.TEAL,overlay)
	paragraph("An organic delivery van brings it to the door. Order before 6pm and it comes later today; after that, tomorrow.",
		Vector2(484,306),Vector2(476,44),13,P.MUTED,overlay)
	var y:float=362.0
	for offer:Dictionary in household.grocery_offers():
		var basket_id:String=str(offer.id)
		var label:String="%s · ℒ%s" % [str(offer.label),commas(int(offer.price))]
		var buy:Button=button(label,Vector2(484,y),Vector2(476,44),func():_order_groceries(basket_id),false,overlay)
		buy.name="Grocery_"+basket_id
		buy.disabled=not bool(offer.available)
		buy.tooltip_text=str(offer.reason) if not bool(offer.available) else str(offer.description)
		text_label(str(offer.reason) if not bool(offer.available) else "%d meals' worth." % int(offer.meals),
			Vector2(490,y+46),Vector2(464,22),11,P.CORAL if not bool(offer.available) else P.MUTED,false,overlay)
		y+=74.0
	button("Back to life",Vector2(484,y+6),Vector2(476,44),close_overlay,true,overlay)


## Order one basket and show the panel again with its new state.
func _order_groceries(basket_id:String) -> void:
	var result:Dictionary=household.order_groceries(basket_id)
	if not bool(result.ok):
		show_notice(str(result.error))
	else:
		refresh_hud()
		show_notice("Groceries ordered. A delivery of %d meals arrives %s." % [int(result.meals),"today" if int(result.day)==household.day else "tomorrow"])
	show_grocery_order()


## Keep the delivery van in step with the household's order: it stands outside
## while a delivery is on its way, and leaves once the shopping is carried in.
func _sync_delivery_van() -> void:
	if not is_instance_valid(world) or current_venue != "home":
		return
	if LifeGroceries.has_order(household.groceries):
		world.show_delivery_van()
	else:
		world.hide_delivery_van()


## The household storage unit. Every stored furnishing can be taken out (which
## begins an ordinary placement, so the destination is validated like any
## purchase) or sold for its usual value. It holds up to MAX_STORAGE items.
func show_storage() -> void:
	if mode!="build":return
	cancel_placement()
	overlay_open=true;dismiss_layer()
	var p=Vector2(430,150)
	card(p,Vector2(580,600),P.WHITE,22,overlay)
	text_label("Storage unit",p+Vector2(34,24),Vector2(500,49),32,P.INK,true,overlay)
	paragraph("Furnishings kept here are out of the way but not gone. Take one out to place it again, or sell it on. Holding %d of %d." % [household_flow.storage_count(),LifeHouseholdFlow.MAX_STORAGE],p+Vector2(36,84),Vector2(508,58),15,P.MUTED,overlay)
	var scroll=ScrollContainer.new();rect(scroll,p+Vector2(32,158),Vector2(516,356),overlay)
	var column=VBoxContainer.new();column.add_theme_constant_override("separation",10);scroll.add_child(column)
	if household_flow.storage.is_empty():
		paragraph("Nothing is in storage yet. In Build & buy, click a furnishing and choose Put in storage.",p+Vector2(44,196),Vector2(492,80),17,P.MUTED,overlay)
	for entry:Dictionary in household_flow.storage.duplicate():
		var kind:String=str(entry.kind)
		if not LifeCatalog.ITEMS.has(kind):continue
		var row=Control.new();row.custom_minimum_size=Vector2(492,62);column.add_child(row)
		var label:=text_label(str(LifeCatalog.ITEMS[kind].label),Vector2(4,6),Vector2(280,26),17,P.INK,true,row)
		label.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
		text_label("Level %d" % (int(entry.get("level",0))+1),Vector2(4,32),Vector2(120,22),12,P.MUTED,false,row)
		var take=button("Take out",Vector2(292,10),Vector2(96,42),func():withdraw_stored(str(entry.id)),false,row)
		take.tooltip_text="Place this furnishing back into the home."
		var sale=button("Sell  +ℒ%d" % sale_value(kind,str(entry.get("size",""))),Vector2(394,10),Vector2(96,42),func():sell_stored(str(entry.id)),false,row)
	button("Back to Build & buy",p+Vector2(32,522),Vector2(516,48),func():close_overlay();draw_live(),true,overlay)

## Withdraw a stored furnishing and begin placing it. The placement path is the
## ordinary one, so the same reach/support checks that guard a purchase apply.
func withdraw_stored(id:String) -> void:
	var result:Dictionary=household_flow.withdraw_furnishing(id)
	if not bool(result.ok):show_notice(str(result.error));show_storage();return
	var record:Dictionary=result.record
	var kind:String=str(record.kind)
	# A withdrawn car comes out in the finish it was stored with. The record is
	# the authority, so the paint follows it rather than the catalogue default.
	pending_paint=LifeCatalog.paint_of(record)
	# A withdrawn item reuses its own identity so an in-flight action that still
	# names it can find the furnishing once it lands, exactly like a move.
	pending_move={"entry":record,"snapshot":_build_snapshot(),"from_storage":true}
	close_overlay()
	world.begin_placement(kind,str(record.get("style","")),str(record.get("size","")))
	world.placement_angle=float(record.get("rotation",0))
	_refresh_sim_targets(false)
	refresh_hud()
	show_notice("Place the %s. Esc returns it to storage." % LifeCatalog.ITEMS[kind].label.to_lower())

## Sell a stored furnishing outright and credit the household.
func sell_stored(id:String) -> void:
	var result:Dictionary=household_flow.sell_stored(id)
	if not bool(result.ok):show_notice(str(result.error));return
	household.set_funds(sim.funds+int(result.credit))
	refresh_hud()
	show_storage()
	show_notice("Sold the %s from storage. +ℒ%d" % [LifeCatalog.ITEMS[str(result.kind)].label, int(result.credit)])

func on_object_clicked(item:Dictionary,screen:Vector2) -> void:
	if bool(item.get("transient_puddle",false)) and mode=="build":show_notice("Return to Live mode to mop this puddle.");return
	selected_item=item
	if mode=="build":
		if bool(item.get("transient_food",false)):
			close_overlay();show_notice("Food and dishes can be handled in Live mode.");return
		if not LifeCatalog.ITEMS.has(str(item.kind)):
			show_notice("Lifelets can be visited in Live mode.");return
		show_build_object(item,screen);return
	if mode=="live":
		if household.member_sim(str(item.id)) and str(item.id)!=household.selected_id():
			show_housemate_interactions(item,screen)
		elif str(item.id)==household.selected_id():show_person()
		elif str(item.get("kind",""))=="pet":show_interactions(item,screen)
		elif str(item.get("kind",""))=="food_truck":show_food_truck()
		else:show_interactions(item,screen)

func close_overlay(restore_speed:bool=true) -> void:
	if mode=="travel" and residents and not residents.trip.is_empty() and restore_speed:return
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
	rect(bg,Vector2(interface_local_x(0.0),0),interface_size(),overlay)
	bg.pressed.connect(close_overlay)

func switch_lamp(item:Dictionary) -> void:
	if str(item.kind)=="floor_lamp":
		var lamp:Dictionary=_find_item(str(item.id))
		if lamp.is_empty():return
		world.set_item_lit(lamp,not world.item_lit(lamp))
		show_notice("The reading lamp glows warm." if world.item_lit(lamp) else "The reading lamp goes dark.")
		return
	var room:String=str(item.get("room",""))
	if room.is_empty():return
	for entry:Dictionary in world.indoor_lights:
		if str(entry.room)!=room:continue
		var light:OmniLight3D=entry.light
		var lit:bool=is_instance_valid(light) and light.visible
		world.set_indoor_lights(not lit,[room])
		show_notice("The %s light is on." % room if not lit else "The %s light is off." % room)
		return


func show_interactions(item:Dictionary,screen:Vector2) -> void:
	close_overlay();overlay_open=true;dismiss_layer()
	# Callers hand over several shapes: a placed furnishing record, a bare
	# member id, a transient light. Normalise the keys this panel reads so a
	# missing one draws an empty panel instead of aborting mid-draw.
	item=item.duplicate()
	for key:String in ["kind","id","label"]:
		if not item.has(key):item[key]=""
	# Pets use the household care menu (feed, play, tricks, walk) rather than the
	# older tummy-rub-only list, so a click on a dog opens the same interaction
	# panel every other object uses.
	var actions:Array=household.pet_actions(str(item.id),bound_member_id) if str(item.kind)=="pet" else sim.get_actions_for(str(item.kind),str(item.id))
	if str(item.kind)=="meal":actions.append({"id":"call_to_meal","label":"Call everyone to eat","cost":0,"duration":0,"available":true,"description":"Invite available hungry household members and your welcomed guest. Busy Lifelets keep their plans."})
	# A served dish or a plated serving can be offered to somebody by name, so the
	# household can ask who actually wants food instead of only calling everyone.
	if (str(item.kind)=="meal" or str(item.kind)=="plate") and meal_flow.offerable_food(str(item.id)):
		actions.append({"id":"ask_who_wants_food","label":"Ask who wants food…","cost":0,"duration":0,"available":true,"description":"Ask each household Lifelet whether they want a serving. Anyone not hungry says no."})
	# A beat already in progress offers its own stop, so the invitation in its
	# notice has a control the player can actually press.
	for running:Variant in household.cooperations:
		if not running is Dictionary:continue
		var session:Dictionary=running
		if LifeBabyPlan.session_kind(session)!=LifeBabyPlan.SESSION_KIND:continue
		actions.insert(0,{"id":"stop_try_for_baby","label":"Stop the moment","cost":0,"duration":0,"available":true,"description":"End it now. Nothing is decided unless the whole moment finishes."})
		break
	if str(item.kind) in ["desk","computer"] and str(sim.character.age_stage) in ["child","teen"]:
		var availability:Dictionary=sim.get_action_availability("homework",str(item.id))
		var reason:String=str(availability.reason)
		if not sim.action_queue.is_empty():reason="Finish or cancel this Lifelet’s current activity first."
		actions.insert(mini(2,actions.size()),{"id":"supported_homework","label":"Do homework together…","cost":0,"duration":45,"available":reason.is_empty(),"unavailable_reason":reason,"description":"Choose a trusted household adult to help. Learn together and strengthen your friendship."})
	if str(item.kind)=="stereo" and not _find_item(str(item.id)).is_empty():
		# The solo record stays first; the shared dance sits beside it and opens
		# the partner panel rather than queueing a lone action.
		var dance_reason:String=sim.get_action_availability(LifeDancePlan.ACTION_ID,str(item.id)).reason
		actions.insert(mini(1,actions.size()),{"id":"dance_together","label":"Dance together…","cost":0,"duration":35,"available":dance_reason.is_empty(),"unavailable_reason":dance_reason,"description":"Put on one record and dance with up to five household Lifelets at once."})
	if str(item.kind)=="floor_lamp" and not _find_item(str(item.id)).is_empty():
		var lamp:Dictionary=_find_item(str(item.id))
		actions.append({"id":"switch_light","label":"Switch off" if world.item_lit(lamp) else "Switch on","cost":0,"duration":0,"available":true,"description":"A warm pool of light for evenings in."})
	elif str(item.kind)=="room_light":
		var room:String=str(item.get("room",""))
		var lit:bool=bool(item.get("lit",true))
		actions.append({"id":"switch_light","label":"Switch off" if lit else "Switch on","cost":0,"duration":0,"available":true,"description":"%s's own ceiling light. A dark room is cosy; a bright one is easier to work in." % room.capitalize()})
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
		if int(a.cost)>0 and str(a.id)!="cook":label_text+="   ℒ%d" % a.cost
		var b=Button.new();b.text=label_text;b.custom_minimum_size=Vector2(300,44)
		b.add_theme_font_size_override("font_size",13)
		b.tooltip_text=str(a.get("unavailable_reason","")) if not bool(a.available) else str(a.description)+"  ·  %d min" % a.duration
		if str(a.id)=="cook" and bool(a.available):b.tooltip_text="Choose a recipe. Each dish lists its servings, price, time and Cooking level."
		b.disabled=not bool(a.available)
		b.pressed.connect(func():
			play_click()
			if str(a.id)=="cook":meal_flow.show_recipes(str(item.id))
			elif str(a.id)=="choose_leftovers":meal_flow.show_leftovers(str(item.id))
			elif str(a.id)=="switch_light":switch_lamp(item);close_overlay()
			elif str(a.id)=="call_to_meal":
				var joined:int=meal_flow.call_to_meal(str(item.id));close_overlay();show_notice("%d Lifelets are coming to eat." % joined)
			elif str(a.id)=="ask_who_wants_food":show_food_offers(str(item.id))
			elif str(a.id)=="change_in_wardrobe" or str(a.id)=="change_in_mirror":show_wardrobe_panel(str(item.id))
			elif str(a.id)=="do_makeup":show_wardrobe_panel(str(item.id),"makeup")
			elif str(a.id)=="change_jewelry":show_wardrobe_panel(str(item.id),"jewelry")
			elif str(a.id)=="read_post":show_post_box()
			elif str(a.id)=="order_groceries":show_grocery_order()
			elif str(a.id)=="supported_homework":show_homework_helpers(item)
			elif str(a.id)==LifeDancePlan.ACTION_ID:show_dance_partners(item)
			elif str(a.id)==LifeBabyPlan.ACTION_ID:try_for_baby(item);close_overlay()
			elif str(a.id)=="stop_try_for_baby":
				household.cancel_cooperative_action(bound_member_id)
				_end_cover_beat();close_overlay()
			else:queue_interaction(item,a.id);close_overlay())
		column.add_child(b)
	if actions.is_empty():paragraph("A little detail that makes this place home.",pos+Vector2(18,80),Vector2(304,55),13,P.MUTED,overlay)

func show_homework_helpers(item:Dictionary) -> void:
	_begin_pause_overlay()
	var helpers:Array=household.homework_helpers(bound_member_id,str(item.id))
	var list_height:float=clampf(helpers.size()*87.0-10.0,77.0,320.0)
	var panel_height:float=340.0+list_height
	var top:float=(900.0-panel_height)*.5
	var shade=ColorRect.new();shade.color=Color(.08,.17,.15,.28);rect(shade,Vector2(interface_local_x(0.0),0),interface_size(),overlay)
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

## Who may join a shared dance at this music player. Each row is a real choice:
## the selected household members walk to the record player and dance to one
## shared clock. A member who cannot join says why instead of being hidden.
func show_dance_partners(item:Dictionary) -> void:
	_begin_pause_overlay()
	var partners:Array=household.dance_partners(str(item.id),bound_member_id)
	var list_height:float=clampf(partners.size()*76.0-10.0,66.0,320.0)
	var panel_height:float=336.0+list_height
	var top:float=(900.0-panel_height)*.5
	var shade=ColorRect.new();shade.color=Color(.08,.17,.15,.28);rect(shade,Vector2(interface_local_x(0.0),0),interface_size(),overlay)
	card(Vector2(338,top),Vector2(764,panel_height),P.WHITE,24,overlay)
	small_caps("One record, one room",Vector2(373,top+22),Vector2(670,23),overlay)
	text_label("Dance together",Vector2(370,top+60),Vector2(686,57),36,P.INK,true,overlay)
	paragraph("Choose who dances with %s. Up to %d Lifelets fit around the record player, and everyone dances for the whole 35-minute record." % [str(sim.character.name),LifeDancePlan.MAX_DANCERS],Vector2(374,top+132),Vector2(686,77),16,P.MUTED,overlay)
	var scroll=ScrollContainer.new();scroll.name="DancePartners";rect(scroll,Vector2(371,top+227),Vector2(692,list_height),overlay)
	var column=VBoxContainer.new();column.add_theme_constant_override("separation",10);scroll.add_child(column)
	# The inviting Lifelet stays in the panel as a selected, disabled row so the
	# player can count the group and read its size before pressing Dance.
	var joinable:int=1
	for partner:Dictionary in partners:
		if bool(partner.available):joinable+=1
	var lead_row=Control.new();lead_row.custom_minimum_size=Vector2(670,66);column.add_child(lead_row)
	card(Vector2.ZERO,Vector2(670,66),Color("f3f4ed"),12,lead_row)
	text_label(str(sim.character.name),Vector2(17,8),Vector2(425,27),20,P.INK,true,lead_row)
	paragraph("Dancing · choosing the record",Vector2(17,36),Vector2(425,26),12,P.MUTED,lead_row)
	var lead_action:Button=button("Joins",Vector2(464,12),Vector2(189,43),func():pass,true,lead_row)
	lead_action.disabled=true
	for partner:Dictionary in partners:
		var row=Control.new();row.custom_minimum_size=Vector2(670,66);column.add_child(row)
		card(Vector2.ZERO,Vector2(670,66),Color("f3f4ed"),12,row)
		text_label(str(partner.name),Vector2(17,8),Vector2(425,27),20,P.INK,true,row)
		paragraph(str(partner.reason) if not bool(partner.available) else "Ready to dance",Vector2(17,36),Vector2(425,26),12,P.MUTED,row)
		var dance:Button=button("Dance",Vector2(464,12),Vector2(189,43),_queue_dance_together.bind(str(item.id),[bound_member_id,str(partner.id)]),true,row)
		dance.name="DancePartner_"+str(partner.id)
		dance.disabled=not bool(partner.available)
		dance.tooltip_text=str(partner.reason)
	var cap_reason:String=("Only %d Lifelets fit around the record player." % LifeDancePlan.MAX_DANCERS) if joinable>LifeDancePlan.MAX_DANCERS else ""
	paragraph(cap_reason if not cap_reason.is_empty() else "%d of %d places would be filled. Canceling one dancer leaves the others dancing." % [joinable,LifeDancePlan.MAX_DANCERS],Vector2(374,top+list_height+243),Vector2(680,47),13,P.MUTED,overlay)
	button("Back to life",Vector2(820,top+list_height+292),Vector2(246,34),close_overlay,false,overlay)

func _dance_positions(item:Dictionary,member_ids:Array) -> Dictionary:
	# One real standing spot per dancer, spread around the record player and
	# snapped to clear floor. The first dancer keeps the stereo's own approach
	# point; the rest take the ring behind it.
	var result:Dictionary={}
	var offsets:Array[Vector3]=LifeDancePlan.ring_offsets(member_ids.size())
	var base:Vector3=world.approach(item)
	for index:int in member_ids.size():
		var member_id:String=str(member_ids[index])
		var at:Vector3=base
		if index>0:
			var wanted:Vector3=item.node.global_transform*offsets[index]
			wanted.y=base.y
			at=world.nearest_clear_point(wanted,world.item_level(item))
			if not at.is_finite():at=world.approach(item)
		result[member_id]=at
	return result

func _queue_dance_together(furniture_id:String,member_ids:Array) -> void:
	var item:Dictionary=_find_item(furniture_id)
	if item.is_empty():show_notice("This music player is no longer here.");return
	# Re-check the same cap the panel showed, so a direct call cannot smuggle a
	# sixth dancer past the refusal.
	var plan:Dictionary=household.dance_plan(furniture_id,member_ids)
	if not bool(plan.ok):show_notice(str(plan.error));return
	var positions:Dictionary=_dance_positions(item,plan.members)
	var result:Dictionary=household.queue_dance_together(furniture_id,plan.members,positions)
	if not bool(result.ok):show_notice(str(result.error));return
	close_overlay();refresh_hud()
	show_notice("The record goes on. Everyone meets at the music player.")

## Ask the household, one Lifelet at a time, whether they want a serving of this
## dish. Each row is a real invitation: the answer is spoken, and a Lifelet who
## is full, tired or busy declines instead of being signed up for a meal.
func show_food_offers(target_id:String) -> void:
	_begin_pause_overlay()
	var item:Dictionary=_find_item(target_id)
	var label:String="food"
	var servings:int=0
	var batch:Dictionary=household.meals.batch(target_id)
	if not batch.is_empty():
		label=str(LifeMeals.RECIPES[str(batch.recipe)].label).to_lower()
		servings=int(batch.remaining)
	else:
		var plate:Dictionary=household.meals.portion(target_id)
		if not plate.is_empty():
			var dish:Dictionary=household.meals.batch(str(plate.batch))
			label=("a serving of "+str(LifeMeals.RECIPES[str(dish.recipe)].label).to_lower()) if not dish.is_empty() else "a serving"
			servings=1
	var people:Array=meal_flow.food_invitees()
	var row_count:int=maxi(1,people.size())
	var list_height:float=clampf(row_count*76.0-10.0,66.0,320.0)
	var panel_height:float=336.0+list_height
	var top:float=(900.0-panel_height)*.5
	var shade=ColorRect.new();shade.color=Color(.08,.17,.15,.28);rect(shade,Vector2(interface_local_x(0.0),0),interface_size(),overlay)
	card(Vector2(338,top),Vector2(764,panel_height),P.WHITE,24,overlay)
	small_caps("Food is better shared",Vector2(373,top+22),Vector2(670,23),overlay)
	text_label("Anyone want some?",Vector2(370,top+60),Vector2(686,57),36,P.INK,true,overlay)
	paragraph(("There are %d servings of %s left. " % [servings,label]) if servings>1 else ("There is %s here. " % label)+"Ask each Lifelet in turn — someone who is full, tired or busy will say no, and the food stays for later.",Vector2(374,top+132),Vector2(686,77),16,P.MUTED,overlay)
	var scroll=ScrollContainer.new();scroll.name="FoodOffers";rect(scroll,Vector2(371,top+227),Vector2(692,list_height),overlay)
	var column=VBoxContainer.new();column.add_theme_constant_override("separation",10);scroll.add_child(column)
	for person:Dictionary in people:
		var row=Control.new();row.name="FoodOffer_"+str(person.id);row.custom_minimum_size=Vector2(670,66);column.add_child(row)
		card(Vector2.ZERO,Vector2(670,66),Color("f3f4ed"),12,row)
		var member_sim:LifeSim=person.sim
		text_label(str(person.name),Vector2(17,8),Vector2(425,27),20,P.INK,true,row)
		paragraph("Hunger %d · %s" % [int(member_sim.needs.hunger),str(member_sim.get_mood().label)],Vector2(17,36),Vector2(425,26),12,P.MUTED,row)
		var offer:Button=button("Offer a serving",Vector2(464,12),Vector2(189,43),_offer_food.bind(str(person.id),target_id),true,row)
		offer.name="FoodOfferButton_"+str(person.id)
	if people.is_empty():paragraph("Everyone is already eating, or busy with something else. Try again once they are free.",Vector2(378,top+242),Vector2(669,75),17,P.MUTED,overlay)
	button("Back to life",Vector2(820,top+list_height+288),Vector2(246,34),close_overlay,false,overlay)

func _offer_food(person_id:String,target_id:String) -> void:
	show_notice(meal_flow.ask_to_share(person_id,target_id))
	refresh_hud()
	show_food_offers(target_id)

## The wardrobe, at a wardrobe, a full-length mirror or a dressing table. Every
## option is shown on the Lifelet standing in front of it before anything is
## bought, and each row prices itself: trying on is free, keeping it costs the
## row's price. Buying a look saves it to that outfit category, so it is the
## look the Lifelet wears from then on.
func show_wardrobe_panel(furniture_id: String, tab: String = "clothes") -> void:
	_begin_pause_overlay()
	wardrobe_tab = tab
	var person: LifeSim = sim
	var look: Dictionary = person.character.duplicate(true)
	# The panel previews on the real Lifelet, so what is shown is what is worn.
	world.set_actor_preview(bound_member_id, look)
	var shade=ColorRect.new();shade.color=Color(.08,.17,.15,.28);rect(shade,Vector2(interface_local_x(0.0),0),interface_size(),overlay)
	# The card carries a second column: the working look drawn close up. The
	# actor at the furniture stands behind the card, so a try-on there is not
	# visible; this panel is what actually shows the piece being worn.
	card(Vector2(180,86),Vector2(1080,742),P.WHITE,24,overlay)
	small_caps("A change of look",Vector2(216,106),Vector2(420,23),overlay)
	text_label("Wardrobe",Vector2(212,144),Vector2(500,57),38,P.INK,true,overlay)
	var tabs:Array=["clothes","hair","makeup","jewelry"]
	var tab_labels:Array=["Clothes","Hair","Makeup","Jewelry"]
	for index:int in range(tabs.size()):
		var chosen:String=str(tabs[index])
		var b:Button=button(tab_labels[index],Vector2(216+index*124,214),Vector2(116,36),func():show_wardrobe_panel(furniture_id,chosen),chosen==wardrobe_tab,overlay)
		b.name="WardrobeTab_"+chosen
	# What the household can afford, and what this Lifelet may wear.
	var can_afford:bool=true
	paragraph("Shown on %s now. Trying a look on is free; saving it to the wardrobe costs the price beside it." % str(person.character.get("name","your Lifelet")),Vector2(216,262),Vector2(520,40),15,P.MUTED,overlay)
	# The preview column, framed for this tab: a close face for hair, makeup and
	# jewelry, and the whole figure for clothes.
	card(Vector2(1002,262),Vector2(242,444),Color("f3f4ed"),18,overlay)
	small_caps("Trying on",Vector2(1018,278),Vector2(210,18),overlay)
	wardrobe_preview(Vector2(1018,302),Vector2(210,332),look,wardrobe_tab,overlay)
	wardrobe_preview_caption=paragraph("",Vector2(1018,644),Vector2(210,50),12,P.MUTED,overlay)
	show_wardrobe_caption(look)
	var scroll=ScrollContainer.new();scroll.name="WardrobeOptions";rect(scroll,Vector2(214,308),Vector2(768,398),overlay)
	var column=VBoxContainer.new();column.add_theme_constant_override("separation",8);scroll.add_child(column)
	if wardrobe_tab=="clothes":
		_wardrobe_clothes(column,look,furniture_id)
	elif wardrobe_tab=="hair":
		_wardrobe_hair(column,look,furniture_id)
	elif wardrobe_tab=="makeup":
		_wardrobe_makeup(column,look,furniture_id)
	else:
		_wardrobe_jewelry(column,look,furniture_id)
	button("Back to life",Vector2(216,724),Vector2(240,40),func():
		world.clear_actor_preview(bound_member_id)
		close_overlay(),true,overlay)
	button("Buy this look  ·  ℒ%d" % WARDROBE_LOOK_PRICE,Vector2(856,724),Vector2(244,40),func():buy_wardrobe_look(furniture_id),false,overlay).name="WardrobeBuy"
func show_post_box() -> void:
	close_overlay();overlay_open=true;dismiss_layer()
	var letters:Array=household.mail.get("letters",[])
	var p:=Vector2(440,140)
	card(p,Vector2(560,620),P.WHITE,22,overlay)
	small_caps("From the post box",p+Vector2(32,22),Vector2(496,22),overlay)
	text_label("The post",p+Vector2(30,48),Vector2(300,42),30,P.INK,true,overlay)
	var unread:int=LifeMail.unread(household.mail).size()
	text_label("%d unread of %d" % [unread,letters.size()],p+Vector2(360,52),Vector2(170,30),14,P.TEAL,false,overlay)
	var scroll:=ScrollContainer.new()
	scroll.name="PostList"
	rect(scroll,p+Vector2(26,104),Vector2(508,424),overlay)
	var column:=VBoxContainer.new()
	column.add_theme_constant_override("separation",10)
	scroll.add_child(column)
	if letters.is_empty():
		var empty:Label=paragraph("Nothing has been posted yet. Bills, and letters about the household's own days, arrive here.",Vector2.ZERO,Vector2(480,60),15,P.MUTED,column)
		empty.custom_minimum_size=Vector2(480,60)
	for entry:Dictionary in letters:
		var row:=Control.new()
		row.name="Post_"+str(entry.get("id",""))
		row.custom_minimum_size=Vector2(480,86)
		column.add_child(row)
		card(Vector2.ZERO,Vector2(480,86),Color("f3f4ed") if bool(entry.get("read",false)) else P.WHITE,12,row)
		var title:Label=text_label(str(entry.get("title","")),Vector2(16,8),Vector2(330,24),17,P.INK,true,row)
		title.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
		text_label(LifeMail.summary(entry),Vector2(16,34),Vector2(330,20),12,P.TEAL if LifeMail.is_bill(entry) else P.MUTED,false,row)
		paragraph(str(entry.get("body","")),Vector2(16,54),Vector2(330,28),11,P.MUTED,row)
		if not bool(entry.get("read",false)):
			var open_button=button("Pay it" if LifeMail.is_bill(entry) else "Read",Vector2(356,26),Vector2(108,36),func():_read_mail(str(entry.get("id",""))),LifeMail.is_bill(entry),row)
			open_button.name="PostAction_"+str(entry.get("id",""))
		else:
			small_caps("Read",Vector2(370,36),Vector2(90,22),row)
	button("Back to life",p+Vector2(30,540),Vector2(502,48),close_overlay,false,overlay)

## Open one letter. A bill's own letter settles it, so the box and the phone's
## bill panel are two doors into the same ledger rather than two ledgers.

func _read_mail(id:String) -> void:
	var result:Dictionary=household.read_mail(id)
	if not bool(result.ok):
		show_notice(str(result.get("error","That letter could not be opened.")))
		show_post_box()
		return
	var paid:int=int(result.get("paid",0))
	if paid>0:show_notice("Bill paid: ℒ%d. The utilities are in good standing." % paid)
	else:show_notice("You read %s." % str((result.get("letter",{}) as Dictionary).get("title","the letter")).to_lower())
	refresh_hud()
	show_post_box()


## Post the household's own mail. Called when the world is built and on each new
## day, so a letter is written once per event rather than once per frame. A bill
## already in the box is not posted twice, and a milestone letter is written once
## per subject.
func sync_post() -> void:
	if not is_instance_valid(household) or not household.owns_post_box():return
	household.post_bill()
	if household.members.is_empty():return
	var who:String=str(sim.character.name)
	household.post_milestone("utility", who)


var wardrobe_tab: String = "clothes"
## The live caption under the preview, replaced on every try-on.
var wardrobe_preview_caption: Label
## The shade a Lifelet was wearing when a makeup colour picker opened, so
## cancelling the picker restores it instead of leaving the mixed shade on.
var picker_original: Dictionary = {}

## Show a working look on the panel's own close-up preview. The SubViewport holds
## its own Lifelet, configured from the look being built, so the piece is visible
## the moment its row is pressed. The actor at the furniture is updated too, and
## keeps the look if it is bought.
func preview_wardrobe_look(look: Dictionary) -> void:
	world.set_actor_preview(bound_member_id,look)
	if not overlay_open:return
	var holder:Control=overlay.get_node_or_null("WardrobePreview") as Control
	if holder!=null:_fill_wardrobe_preview(holder,look,wardrobe_tab)
	show_wardrobe_caption(look)

## One line naming what the working look currently shows, so the preview is
## readable rather than only visual.
func show_wardrobe_caption(look: Dictionary) -> void:
	if not is_instance_valid(wardrobe_preview_caption):return
	var worn:Array[String]=[]
	match wardrobe_tab:
		"clothes":
			var tops:Array=LifeCharacterIdentity.get_category_tops(str(look.get("outfit_category","everyday")))
			var index:int=int(look.get("outfit",0))
			worn.append(str(tops[index]) if index<tops.size() else "Top %d" % (index+1))
			worn.append("Trousers" if int(look.get("bottom",0))==0 else "Shorts")
			worn.append("Top #"+str(look.get("top_color","")).to_upper())
			worn.append("Bottoms #"+str(look.get("bottom_color","")).to_upper())
			worn.append("Shoes #"+str(look.get("shoe_color","")).to_upper())
		"hair":
			var style:int=clampi(int(look.get("hair",0)),0,LifeActor.HAIR_NAMES.size()-1)
			worn.append(str(LifeActor.HAIR_NAMES[style]).trim_prefix("Hair_"))
			worn.append("Hair #"+str(look.get("hair_color","")).to_upper())
			worn.append("Eyes #"+str(look.get("eye_color","")).to_upper())
		"makeup":
			var lips:String=LifeCharacterIdentity.makeup_value(look,"makeup_lips")
			var eyes:String=LifeCharacterIdentity.makeup_value(look,"makeup_eyes")
			worn.append("Lips: bare" if lips==LifeCharacterIdentity.MAKEUP_NONE else "Lips #"+lips.to_upper())
			worn.append("Eyes: bare" if eyes==LifeCharacterIdentity.MAKEUP_NONE else "Eyes #"+eyes.to_upper())
		_:
			var ears:String=str(look.get("jewelry_ears",LifeCharacterIdentity.MAKEUP_NONE))
			worn.append("Earrings: none" if ears==LifeCharacterIdentity.MAKEUP_NONE else "Earrings: "+ears)
			worn.append("Necklace: on" if bool(look.get("jewelry_neck",false)) else "Necklace: none")
			worn.append("Metal #"+str(look.get("jewelry_metal",LifeCharacterIdentity.JEWELRY_METALS[0])).to_upper())
	wardrobe_preview_caption.text=" · ".join(worn)

## Draw the close-up preview into `parent`, named so a try-on can replace it.
func wardrobe_preview(p:Vector2,s:Vector2,look:Dictionary,tab:String,parent:Node) -> void:
	var holder:=Control.new()
	holder.name="WardrobePreview"
	holder.mouse_filter=Control.MOUSE_FILTER_IGNORE
	rect(holder,p,s,parent)
	_fill_wardrobe_preview(holder,look,tab)

func _fill_wardrobe_preview(holder:Control,look:Dictionary,tab:String) -> void:
	for child:Node in holder.get_children():
		holder.remove_child(child)
		child.queue_free()
	var sv:=SubViewport.new()
	sv.size=Vector2i(int(holder.size.x*2),int(holder.size.y*2))
	sv.own_world_3d=true
	sv.transparent_bg=true
	sv.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	sv.msaa_3d=Viewport.MSAA_4X
	holder.add_child(sv)
	var view:=TextureRect.new()
	view.texture=sv.get_texture()
	view.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	view.mouse_filter=Control.MOUSE_FILTER_IGNORE
	rect(view,Vector2.ZERO,holder.size,holder)
	var root:=Node3D.new();sv.add_child(root)
	# A detached LifeActor shows exactly the look the panel is building: the same
	# model, hairstyle, makeup, jewelry and outfit the bought look would keep.
	# It is added to the tree before `configure`, because configuring needs the
	# model's global transform to cache its joint rest poses.
	var model:=LifeActor.new()
	model.voice_enabled=false
	root.add_child(model)
	model.configure(look)
	var center:Vector3=model.get_portrait_center()
	var height:float=model.get_display_height()
	var cam:=Camera3D.new();root.add_child(cam)
	cam.projection=Camera3D.PROJECTION_ORTHOGONAL
	if tab=="clothes":
		cam.size=maxf(height*1.06,1.5)
		cam.position=Vector3(.9,height*.55,2.4)
		cam.look_at(Vector3(0,height*.48,0))
	else:
		# A close face: the whole point of the panel for hair, makeup and jewelry.
		cam.size=maxf(height*.30,.42)
		cam.position=Vector3(.04,center.y+.01*height,2.0)
		cam.look_at(center-Vector3(0,.02*height,0))
	var light:=DirectionalLight3D.new();root.add_child(light);light.rotation_degrees=Vector3(-34,-30,0);light.light_energy=.72
	var env:=WorldEnvironment.new();var e:=Environment.new();e.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;e.ambient_light_color=Color.WHITE;e.ambient_light_energy=.36;env.environment=e;root.add_child(env)
	freeze_viewport.call_deferred(sv.get_instance_id())

## What one saved look costs. A whole outfit, a makeup set or a jewelry set is a
## wardrobe purchase rather than a per-swatch charge, so a Lifelet can be
## restyled for a sensible price instead of paying for every colour.
const WARDROBE_LOOK_PRICE: int = 60

## One buyable row: shows the option, previews it on the Lifelet when pressed,
## and states its price. `apply` is given the working look to mutate.
func _wardrobe_row(column: VBoxContainer, label: String, detail: String, price: int, chosen: bool, apply: Callable) -> void:
	var row=Control.new();row.custom_minimum_size=Vector2(744,56);column.add_child(row)
	card(Vector2.ZERO,Vector2(744,56),Color("f3f4ed") if not chosen else Color("e4efe9"),12,row)
	text_label(label,Vector2(16,7),Vector2(470,25),19,P.INK,true,row)
	paragraph(detail,Vector2(16,31),Vector2(470,22),12,P.MUTED,row)
	text_label("free to try" if price<=0 else "ℒ%d" % price,Vector2(500,16),Vector2(120,24),15,P.TEAL if price>0 else P.MUTED,false,row)
	var try_on:Button=button("Try on",Vector2(628,10),Vector2(104,36),apply,false,row)
	try_on.tooltip_text="Show this on your Lifelet before you buy it."

func _wardrobe_clothes(column: VBoxContainer, look: Dictionary, furniture_id: String) -> void:
	# Every top this model authors, in this outfit category's own palette, plus
	# the bottoms and shoes, so the panel offers the whole everyday wardrobe.
	var wardrobe: Dictionary = player.authored_wardrobe()
	var names: Array = LifeCharacterIdentity.get_category_tops(str(look.get("outfit_category","everyday")))
	var palettes: Dictionary = LifeCharacterIdentity.get_category_palettes(str(look.get("outfit_category","everyday")))
	for index: Variant in wardrobe.get("outfits", [0]):
		var i:int=int(index)
		var label:String=str(names[i]) if i<names.size() else "Outfit %d" % (i+1)
		_wardrobe_row(column,label,"A saved top for this outfit type.",WARDROBE_LOOK_PRICE,int(look.get("outfit",0))==i,func():
			look["outfit"]=i
			preview_wardrobe_look(look))
	for index: Variant in wardrobe.get("bottoms", [0]):
		var i:int=int(index)
		_wardrobe_row(column,"Trousers" if i==0 else "Shorts","A saved lower half for this outfit type.",WARDROBE_LOOK_PRICE,int(look.get("bottom",0))==i,func():
			look["bottom"]=i
			preview_wardrobe_look(look))
	var top_colors:Array=palettes.get("top",[])
	for colour:Variant in top_colors:
		var hex:String=str(colour)
		_wardrobe_row(column,"Top colour  "+hex.to_upper(),"Recolours the top you are wearing.",0,str(look.get("top_color",""))==hex,func():
			look["top_color"]=hex
			preview_wardrobe_look(look))
	for colour:Variant in palettes.get("shoes",[]):
		var hex:String=str(colour)
		_wardrobe_row(column,"Shoes  "+hex.to_upper(),"Recolours your shoes.",0,str(look.get("shoe_color",""))==hex,func():
			look["shoe_color"]=hex
			preview_wardrobe_look(look))

## Every hairstyle this Lifelet's own model authors, each shown on them before it
## is kept, with the hair colours underneath it.
func _wardrobe_hair(column: VBoxContainer, look: Dictionary, furniture_id: String) -> void:
	var styles: Array = player.authored_hair_styles()
	paragraph("Ten styles are authored, and the panel offers the ones this Lifelet's own model carries. Anything you try is shown on them straight away.",Vector2.ZERO,Vector2(744,26),12,P.MUTED,column)
	for index: Variant in styles:
		var i: int = int(index)
		var label: String = LifeActor.HAIR_NAMES[i].trim_prefix("Hair_")
		_wardrobe_row(column,"Hair · "+label,"A different cut for this Lifelet.",WARDROBE_LOOK_PRICE,int(look.get("hair",0))==i,func():
			look["hair"]=i
			preview_wardrobe_look(look))
	var colours: Array = LifeCharacterIdentity.HAIR_COLORS.duplicate()
	if str(look.get("age_stage",""))=="elder":colours.append_array(LifeCharacterIdentity.ELDER_HAIR_COLORS)
	for colour: Variant in colours:
		var hex: String = str(colour)
		_wardrobe_row(column,"Hair colour  "+hex.to_upper(),"Recolours the hair you are wearing.",0,str(look.get("hair_color",""))==hex,func():
			look["hair_color"]=hex
			preview_wardrobe_look(look))
	var eyes: Array = LifeCharacterIdentity.EYE_COLORS
	for colour: Variant in eyes:
		var hex: String = str(colour)
		_wardrobe_row(column,"Eye colour  "+hex.to_upper(),"Recolours the eyes.",0,str(look.get("eye_color",""))==hex,func():
			look["eye_color"]=hex
			preview_wardrobe_look(look))


func _wardrobe_makeup(column: VBoxContainer, look: Dictionary, furniture_id: String) -> void:
	var limited:bool=LifeCharacterIdentity.is_male(look)
	paragraph("Every option here is shown on your Lifelet first. %s Pick any shade you like on the custom row." % ("A limited men's set is offered." if limited else "The full set is offered."),Vector2.ZERO,Vector2(744,22),12,P.MUTED,column)
	for colour:Variant in LifeCharacterIdentity.makeup_lip_colors(look):
		var hex:String=str(colour)
		_wardrobe_row(column,"Lip colour  "+hex.to_upper(),"A lip tint from %s set." % ("the limited men's" if limited else "the full"),WARDROBE_LOOK_PRICE,LifeCharacterIdentity.makeup_value(look,"makeup_lips")==hex,func():
			look["makeup_lips"]=hex
			preview_wardrobe_look(look))
	# Any shade, not only the suggested palette: the picker writes the chosen
	# colour into the working look and repaints the Lifelet straight away.
	_wardrobe_custom_row(column,"Lip colour of your own","Mix exactly the lipstick you want.",look,"makeup_lips",furniture_id)
	_wardrobe_row(column,"No lip colour","Wear a bare lip.",0,LifeCharacterIdentity.makeup_value(look,"makeup_lips")==LifeCharacterIdentity.MAKEUP_NONE,func():
		look["makeup_lips"]=LifeCharacterIdentity.MAKEUP_NONE
		preview_wardrobe_look(look))
	for colour:Variant in LifeCharacterIdentity.makeup_eye_colors(look):
		var hex:String=str(colour)
		_wardrobe_row(column,"Eye look  "+hex.to_upper(),"A lid and cheek tint.",WARDROBE_LOOK_PRICE,LifeCharacterIdentity.makeup_value(look,"makeup_eyes")==hex,func():
			look["makeup_eyes"]=hex
			preview_wardrobe_look(look))
	_wardrobe_custom_row(column,"Eyeliner of your own","Mix exactly the shade you want.",look,"makeup_eyes",furniture_id)
	_wardrobe_row(column,"No eye look","Wear a bare eye.",0,LifeCharacterIdentity.makeup_value(look,"makeup_eyes")==LifeCharacterIdentity.MAKEUP_NONE,func():
		look["makeup_eyes"]=LifeCharacterIdentity.MAKEUP_NONE
		preview_wardrobe_look(look))

## A wardrobe row whose "Try on" opens the engine's colour picker, so a Lifelet
## can wear any lip or eyeliner shade rather than only the authored suggestions.
func _wardrobe_custom_row(column: VBoxContainer, label: String, detail: String, look: Dictionary, key: String, furniture_id: String) -> void:
	var row=Control.new();row.custom_minimum_size=Vector2(744,56);column.add_child(row)
	var worn:String=LifeCharacterIdentity.makeup_value(look,key)
	var chosen:bool=worn!=LifeCharacterIdentity.MAKEUP_NONE
	card(Vector2.ZERO,Vector2(744,56),Color("f3f4ed") if not chosen else Color("e4efe9"),12,row)
	text_label(label,Vector2(16,7),Vector2(470,25),19,P.INK,true,row)
	paragraph(detail,Vector2(16,31),Vector2(470,22),12,P.MUTED,row)
	text_label("worn  #"+worn.to_upper() if chosen else "free to try",Vector2(500,16),Vector2(120,24),15,P.TEAL if chosen else P.MUTED,false,row)
	var pick:Button=button("Pick a shade",Vector2(628,10),Vector2(104,36),func():open_wardrobe_makeup_picker(key,look,furniture_id),false,row)
	pick.tooltip_text="Choose any shade with a colour wheel; it is shown on your Lifelet at once."

## The wardrobe's colour picker. It writes into the panel's working look and
## repaints the close-up, so a custom shade is tried on before it is bought.
func open_wardrobe_makeup_picker(key:String,look:Dictionary,furniture_id:String) -> void:
	var current:String=LifeCharacterIdentity.makeup_value(look,key)
	var picker:=ColorPicker.new()
	picker.name="MakeupPicker"
	picker.color=Color.from_string(current,Color("b5453f")) if current!=LifeCharacterIdentity.MAKEUP_NONE else Color("b5453f")
	picker.edit_alpha=false
	picker.color_mode=ColorPicker.MODE_OKHSL
	picker.picker_shape=ColorPicker.SHAPE_HSV_WHEEL
	rect(picker,Vector2(380,236),Vector2(560,380),overlay)
	overlay_open=true
	card(Vector2(360,196),Vector2(600,470),P.WHITE,20,overlay)
	text_label("Pick a shade of your own",Vector2(380,206),Vector2(560,32),22,P.INK,true,overlay)
	picker.color_changed.connect(func(colour:Color):
		look[key]=colour.to_html(false)
		preview_wardrobe_look(look)
		show_wardrobe_caption(look))
	# Remember what the Lifelet was wearing, so Cancel can restore it exactly.
	picker_original={key:LifeCharacterIdentity.makeup_value(look,key)}
	# Use keeps the mixed shade; Cancel drops it, so the two really differ. Both
	# reopen the wardrobe, because the picker replaced that panel.
	button("Use this shade",Vector2(380,626),Vector2(268,38),_keep_picked_shade.bind(key,look,furniture_id,true),true,overlay)
	button("Cancel",Vector2(668,626),Vector2(268,38),_keep_picked_shade.bind(key,look,furniture_id,false),false,overlay)

## Finish the picker. The live `color_changed` writes have already repainted the
## Lifelet with the mixed shade; cancelling puts the original shade back, and
## either way the wardrobe reopens on the working look.
func _keep_picked_shade(key:String,look:Dictionary,furniture_id:String,keep:bool) -> void:
	if keep:
		if LifeCharacterIdentity.makeup_value(look,key)==LifeCharacterIdentity.MAKEUP_NONE:
			look[key]=Color("b5453f").to_html(false)
	else:
		look[key]=str(picker_original.get(key,LifeCharacterIdentity.MAKEUP_NONE))
	close_overlay()
	show_wardrobe_panel(furniture_id,"makeup")
	preview_wardrobe_look(look)

func _wardrobe_jewelry(column: VBoxContainer, look: Dictionary, furniture_id: String) -> void:
	# Men's jewelry is the same authored surfaces: a male Lifelet may wear any of
	# these, so the set offered is not split by gender.
	for option:Variant in ["none","stud","hoop","chain"]:
		var style:String=str(option)
		var labels:Dictionary={"none":"No earrings","stud":"A simple stud","hoop":"A small hoop","chain":"Ear chain"}
		_wardrobe_row(column,str(labels[style]),"Worn on both ears.",WARDROBE_LOOK_PRICE if style!="none" else 0,str(look.get("jewelry_ears","none"))==style,func():
			look["jewelry_ears"]=style
			preview_wardrobe_look(look))
	_wardrobe_row(column,"A necklace" if not bool(look.get("jewelry_neck",false)) else "No necklace","A chain at the throat.",WARDROBE_LOOK_PRICE,bool(look.get("jewelry_neck",false)),func():
		look["jewelry_neck"]=not bool(look.get("jewelry_neck",false))
		preview_wardrobe_look(look))
	for metal:Variant in LifeCharacterIdentity.JEWELRY_METALS:
		var hex:String=str(metal)
		_wardrobe_row(column,"Metal  "+hex.to_upper(),"Recolours every piece you are wearing.",0,LifeCharacterIdentity.jewelry_metal(look)==hex,func():
			look["jewelry_metal"]=hex
			preview_wardrobe_look(look))

## Keep the look currently on the Lifelet. The wardrobe charges one look price,
## and the saved outfit category then wears it.
func buy_wardrobe_look(furniture_id: String) -> void:
	var look:Dictionary=world.actor_preview(bound_member_id)
	if look.is_empty():show_notice("Nothing is being shown on your Lifelet.");return
	if household.funds<WARDROBE_LOOK_PRICE:
		show_notice("You need ℒ%d to save this look." % WARDROBE_LOOK_PRICE);return
	household.set_funds(household.funds-WARDROBE_LOOK_PRICE)
	var target:LifeSim=sim
	for key:String in ["outfit","bottom","top_color","bottom_color","shoe_color","outfit_category","hair","hair_color","eye_color","makeup_lips","makeup_eyes","jewelry_ears","jewelry_metal","jewelry_neck"]:
		if look.has(key):target.character[key]=look[key]
	LifeCharacterIdentity.store_current(target.character)
	world.clear_actor_preview(bound_member_id)
	player.apply_wardrobe(target.character)
	close_overlay()
	refresh_hud()
	show_notice("The look is yours. −ℒ%d" % WARDROBE_LOOK_PRICE)


func _supported_homework_plan(item:Dictionary,helper_id:String) -> Dictionary:
	if not world.actors.has(bound_member_id) or not world.actors.has(helper_id):return {"ok":false,"error":"Both Lifelets must be here to learn together."}
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
	close_overlay()
	if bool(item.get("transient_food",false)) or not LifeCatalog.ITEMS.has(str(item.get("kind",""))):return
	overlay_open=true;dismiss_layer()
	var p=Vector2(clampf(screen.x-140,300,1100),clampf(screen.y-70,99,440))
	card(p,Vector2(290,228),P.WHITE,17,overlay)
	text_label(item.label,p+Vector2(18,14),Vector2(261,38),22,P.INK,true,overlay)
	button("Sell  +ℒ%d" % sale_value(str(item.kind),str(item.get("size",""))),p+Vector2(16,71),Vector2(258,40),func():sell_item(item);close_overlay(),false,overlay)
	button("Move furnishing",p+Vector2(16,122),Vector2(258,40),func():move_item(item);close_overlay(),false,overlay)
	var store=button("Put in storage",p+Vector2(16,173),Vector2(258,40),func():store_item(item);close_overlay(),false,overlay)
	store.tooltip_text="File this furnishing away in the household storage unit ("+str(household_flow.storage_count())+"/%d used)." % LifeHouseholdFlow.MAX_STORAGE

func store_item(item:Dictionary) -> void:
	if mode!="build":return
	var existing:Dictionary=_find_item(str(item.get("id","")))
	if existing.is_empty() or bool(existing.get("transient_food",false)) or not LifeCatalog.ITEMS.has(str(existing.get("kind",""))):return
	cancel_placement()
	var entry:Dictionary={"id":str(existing.id),"kind":str(existing.kind),"x":existing.node.position.x,"z":existing.node.position.z,"rotation":existing.node.rotation_degrees.y,"level":world.item_level(existing)}
	if _find_item(str(existing.id)).has("lit"):entry["lit"]=bool(existing.get("lit",true))
	if LifeCatalog.paints(str(existing.kind)):entry["paint"]=LifeCatalog.paint_of(existing)
	var result:Dictionary=household_flow.store_furnishing(entry)
	if not bool(result.ok):show_notice(str(result.error));return
	var protection:Dictionary=build_protection_context()
	_cancel_all_cooperative_actions()
	world.remove_item(str(existing.id))
	build_transactions.furnishing_rebuilt(protection)
	_refresh_sim_targets()
	refresh_hud()
	show_notice("%s is in storage. Open Storage to take it out or sell it." % LifeCatalog.ITEMS[str(existing.kind)].label)

func sell_item(item:Dictionary) -> void:
	if mode!="build":return
	var existing:Dictionary=_find_item(str(item.get("id","")))
	if existing.is_empty() or bool(existing.get("transient_food",false)) or not LifeCatalog.ITEMS.has(str(existing.get("kind",""))):return
	cancel_placement()
	var proposed:Array=world.serialize_items().filter(func(entry:Dictionary)->bool:return str(entry.get("id",""))!=str(existing.id))
	var problem:String=build_transactions.furnishing_error(proposed)
	if not problem.is_empty():show_notice(problem);return
	var protection:Dictionary=build_protection_context()
	var credit:int=sale_value(str(existing.kind),str(existing.get("size","")))
	build_undo.append(_build_snapshot(-credit))
	_cancel_all_cooperative_actions()
	world.remove_item(existing.id)
	build_transactions.furnishing_rebuilt(protection)
	household.set_funds(sim.funds+credit)
	_refresh_sim_targets()
	refresh_hud()

func move_item(item:Dictionary) -> void:
	if mode!="build" or bool(item.get("transient_food",false)) or not LifeCatalog.ITEMS.has(str(item.get("kind",""))):return
	cancel_placement()
	var snapshot:Dictionary=_build_snapshot()
	var original:Dictionary={}
	for entry:Dictionary in snapshot.layout:
		if str(entry.get("id",""))==str(item.get("id","")) and entry.has("id"):original=entry.duplicate(true)
	if original.is_empty():return
	var proposed:Array=world.serialize_items().filter(func(entry:Dictionary)->bool:return str(entry.get("id",""))!=str(original.id))
	var problem:String=build_transactions.furnishing_error(proposed)
	if not problem.is_empty():show_notice(problem);return
	var protection:Dictionary=build_protection_context()
	_cancel_all_cooperative_actions()
	pending_move={"entry":original,"snapshot":snapshot}
	world.remove_item(str(original.id))
	build_transactions.furnishing_rebuilt(protection)
	# A move must ghost the object the player actually picked up: a family whose
	# art is styled (shrubs, fences, hot tubs, pools, trees) ships no base model,
	# so asking for the bare kind loaded a missing path and `instantiate()` on
	# the null resource crashed the game every time the player moved one.
	world.begin_placement(str(original.kind),str(original.get("style","")),str(original.get("size","")))
	world.placement_angle=float(original.get("rotation",0))
	# Keep actions attached to this ID until the move is committed or canceled.
	_refresh_sim_targets(false)
	refresh_hud()
	show_notice("Place the furnishing in its new spot. Esc puts it back.")

func begin_purchase(kind:String) -> void:
	cancel_placement()
	# A fresh car starts on the catalogue's own shade; the row can change it.
	pending_paint=LifeCatalog.paint_of({"kind":kind})
	world.begin_placement(kind)
	draw_live()

## The style, colour and size chooser for one catalogue family. The player sees
## each choice on the real model before buying, and the price under the picks
## follows the size they settled on. Confirming begins the ordinary placement, so
## the support, doorway and wallet rules are exactly the ones a plain purchase
## already answers to.
##
## The whole panel is rebuilt on every choice, carrying the working choice with
## it: a swatch press asks for exactly the panel it should now be looking at,
## rather than patching a drawn panel in place.
func pick_furnishing(kind:String,working:Dictionary={}) -> void:
	var data:Dictionary=LifeCatalog.get_item(kind)
	if data.is_empty():return
	if working.is_empty():working=Variants.resolve(data,{})
	close_overlay();overlay_open=true;dismiss_layer()
	var p:=Vector2(400,110)
	var panel_width:float=640.0
	var shade=ColorRect.new();shade.color=Color(.08,.17,.15,.28);rect(shade,Vector2(interface_local_x(0.0),0),interface_size(),overlay)
	card(p,Vector2(panel_width,680),P.WHITE,24,overlay)
	small_caps("Choose your %s" % str(data.label).to_lower(),p+Vector2(30,22),Vector2(panel_width-60,24),overlay)
	text_label(str(data.label),p+Vector2(28,48),Vector2(panel_width-56,44),30,P.INK,true,overlay)
	# The preview redraws with the panel, so the player always sees the object
	# the picks currently describe.
	var preview_holder:=Control.new()
	preview_holder.name="VariantPreview"
	rect(preview_holder,p+Vector2(28,100),Vector2(panel_width-56,180),overlay)
	model_thumbnail(kind,p+Vector2(28,100),Vector2(panel_width-56,180),false,preview_holder,{},str(working.style),str(working.size),str(working.color))
	var y:float=296.0
	var styles:Array=Variants.styles(data)
	if styles.size()>1:
		small_caps("Style",p+Vector2(30,y),Vector2(200,22),overlay)
		y+=28
		var style_scroll:=ScrollContainer.new()
		style_scroll.vertical_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
		rect(style_scroll,p+Vector2(28,y),Vector2(panel_width-56,44),overlay)
		var style_row:=HBoxContainer.new();style_row.add_theme_constant_override("separation",8)
		style_scroll.add_child(style_row)
		for style_id:String in styles:
			var held:Dictionary=working.duplicate(true)
			held["style"]=style_id
			var option=button(Variants.style_label(str(style_id)),Vector2.ZERO,Vector2(124,40),pick_furnishing.bind(kind,held),str(style_id)==str(working.style),style_row)
			option.name="VariantStyle_"+str(style_id)
			option.tooltip_text=str(style_id)
			compact_button(option);option.size=Vector2(124,40)
		y+=56
	var sizes:Array=Variants.sizes(data)
	if sizes.size()>1:
		small_caps("Size",p+Vector2(30,y),Vector2(200,22),overlay)
		y+=28
		var size_scroll:=ScrollContainer.new()
		size_scroll.vertical_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
		rect(size_scroll,p+Vector2(28,y),Vector2(panel_width-56,44),overlay)
		var size_row:=HBoxContainer.new();size_row.add_theme_constant_override("separation",8)
		size_scroll.add_child(size_row)
		for size_id:String in sizes:
			var held:Dictionary=working.duplicate(true)
			held["size"]=size_id
			var option=button("%s · ℒ%d" % [Variants.size_label(str(size_id)),Variants.price(data,str(size_id))],Vector2.ZERO,Vector2(178,40),pick_furnishing.bind(kind,held),str(size_id)==str(working.size),size_row)
			option.name="VariantSize_"+str(size_id)
			var holds:int=Variants.seats(data,str(size_id))
			if holds>0:option.tooltip_text="Holds %d." % holds
			compact_button(option);option.size=Vector2(178,40)
		y+=56
	var colors:Array=Variants.colors(data)
	if colors.size()>1:
		small_caps("Colour",p+Vector2(30,y),Vector2(200,22),overlay)
		y+=28
		# Ten or more swatches wrap inside the panel, so every colour stays
		# reachable rather than running past the card edge.
		var per_row:int=10
		var swatch:float=40.0
		var gap:float=8.0
		for i:int in colors.size():
			var column:int=i%per_row
			var line:int=i/per_row
			var at:=p+Vector2(28.0+float(column)*(swatch+gap),y+float(line)*(swatch+gap))
			var chosen:bool=str(colors[i])==str(working.color)
			var held:Dictionary=working.duplicate(true)
			held["color"]=colors[i]
			var chip=button("•" if chosen else "",at,Vector2(swatch,swatch),pick_furnishing.bind(kind,held),false,overlay)
			chip.name="VariantColor_%d" % i
			chip.tooltip_text=str(colors[i])
			chip.add_theme_stylebox_override("normal",P.panel(Color(colors[i]),14,P.TEAL if chosen else Color("dbe2d7"),3 if chosen else 1))
			chip.add_theme_stylebox_override("hover",P.panel(Color(colors[i]).lightened(.08),14,P.TEAL,3))
			if chosen:chip.add_theme_color_override("font_color",Color.WHITE)
			compact_button(chip);chip.size=Vector2(swatch,swatch)
		y+=float(ceili(float(colors.size())/float(per_row)))*(swatch+gap)+6.0
	var price:int=Variants.price(data,str(working.size))
	var holds:int=Variants.seats(data,str(working.size))
	var detail:String="ℒ%d" % price
	if holds>0:detail+="  ·  holds %d" % holds
	text_label(detail,p+Vector2(28,y+4),Vector2(panel_width-56,30),20,P.TEAL,false,overlay)
	button("Place it · ℒ%d" % price,p+Vector2(28,y+42),Vector2(280,48),func():close_overlay();begin_purchase_variant(kind,working),true,overlay).name="VariantConfirm"
	button("Back",p+Vector2(324,y+42),Vector2(panel_width-352,48),func():close_overlay();draw_live(),false,overlay)

## Begin placing the exact object the picker described.
func begin_purchase_variant(kind:String,working:Dictionary) -> void:
	cancel_placement()
	world.begin_placement(kind,str(working.get("style","")),str(working.get("size","")))

func cancel_placement() -> void:
	if not is_instance_valid(world):return
	world.clear_placement()
	if not pending_move.is_empty():
		# A withdrawal that the player escapes returns to storage; a move puts
		# the furnishing back where it was.
		if bool(pending_move.get("from_storage",false)):
			household_flow.store_furnishing(pending_move.entry)
		else:
			world.add_item(pending_move.entry)
		pending_move.clear()
		_refresh_sim_targets()

func _find_item(id:String) -> Dictionary:
	for item:Dictionary in world.items:
		if str(item.id)==id:return item
	return {}

## Which furnishing a queued action will really use, for the queue chip. Two
## queued cooks must be distinguishable, and `cook` is offered by both the fridge
## and the stove while always routing to the stove, so the id the action stores
## is the truth to report. A position-only action (a walk, a departure) has no
## furnishing and returns "".
func _queue_target_kind(action:Dictionary) -> String:
	var target_id:String=str(action.get("target_id",""))
	if target_id.is_empty():return ""
	var item:Dictionary=_find_item(target_id)
	if item.is_empty():return ""
	var kind:String=str(item.get("kind",""))
	if kind.is_empty() or not LifeCatalog.ITEMS.has(kind):return ""
	return str(LifeCatalog.ITEMS[kind].label).to_lower()

func _refresh_sim_targets(replan:bool=true,reconcile_food:bool=true) -> void:
	if not is_instance_valid(household) or household.members.is_empty():return
	meal_flow.sync_world(reconcile_food)
	_store_motion()
	var prior:String=bound_member_id
	household.register_targets(world.simulation_targets())
	for member:Dictionary in household.members:
		_bind_member(member.id)
		_refresh_member_targets(replan)
		_store_motion()
	_bind_member(prior)
	traversal.courtesy.reconcile(traversal,replan)
	meal_flow.sync_oven_presentations()
	_reconstruct_paused_cooking()

## What everything placed in the home is worth. A household bill reads this at
## the moment it is issued, so the amount follows the house the player has built.
## What one placed furnishing sells for: seven tenths of the price of the size it
## actually is, so a large furnishing sells for more than the small one it was
## bought alongside.
func sale_value(kind:String,size:String="") -> int:
	return int(Variants.price(LifeCatalog.get_item(kind),size)*.7)

## What everything placed in the home is worth. A household bill reads this at
## the moment it is issued, so the amount follows the house the player has built.
func home_value() -> int:
	var value:int=0
	var furnishings:Array=home_layout
	if current_venue=="home" and is_instance_valid(world):
		furnishings=world.items
	for item:Dictionary in furnishings:
		var kind:String=str(item.get("kind",""))
		if kind.is_empty() or not LifeCatalog.ITEMS.has(kind):continue
		if bool(item.get("transient_food",false)) or bool(item.get("transient_puddle",false)) or bool(item.get("derived",false)):continue
		value+=Variants.price(LifeCatalog.get_item(kind),str(item.get("size","")))
	return value

func _refresh_member_targets(replan:bool=true) -> void:
	if not is_instance_valid(sim) or not is_instance_valid(world.house):return
	sim.meal_service=meal_flow
	sim.sanitation_service=sanitation_flow
	sim.household_service=household_flow
	sim.social_witness=Callable(self,"_members_can_see_each_other")
	if sim.is_away():
		if str(sim.get_away_state().get("phase",""))=="returning":away_phases.erase(bound_member_id)
		return
	var targets:Array=world.simulation_targets()
	var by_id:Dictionary={}
	for target:Dictionary in targets:by_id[str(target.id)]=target
	sim.register_targets(targets.filter(func(target:Dictionary):return str(target.id)!=bound_member_id))
	var interrupted_social:bool=false
	var keep_courtesy_endpoint:bool=false
	reconciling_targets=true
	for index:int in range(sim.action_queue.size()-1,-1,-1):
		var action:Dictionary=sim.action_queue[index]
		if str(action.id)=="arrive_home":continue
		var target_id:String=str(action.target_id)
		if not pending_move.is_empty() and target_id==str(pending_move.entry.id):continue
		if not pending_move.is_empty() and str(action.id)=="eat_meal" and str(household.meals.portion(str(action.get("meal_plate",""))).get("host",""))==str(pending_move.entry.id):continue
		if not by_id.has(target_id):
			if index==0 and str(action.id) in LifeSim.SOCIAL_ACTIONS:interrupted_social=true
			sim.cancel_action(index)
			continue
		# Queued socials resolve when they start. A current social retains its
		# admitted endpoint until the shared reconciliation below can replan it.
		if str(action.id) in LifeSim.SOCIAL_ACTIONS:continue
		var destination:Vector3=world.lot_exit_position(_member_index(bound_member_id)) if str(action.id) in ["school_day","career_day","morning_run"] else by_id[target_id].position
		if str(action.id)=="cook" and str(action.get("recipe",""))=="harvest_bake":
			var oven:Dictionary=_find_item(target_id)
			if not oven.is_empty() and str(oven.kind)=="stove":destination=world.oven_approach(oven)
		if str(action.id)=="eat_meal" and bool(action.get("meal_standing",false)):
			destination=action.target_position
			if not meal_flow.standing_geometry_clear(destination):
				meal_flow.carry_diner_plate(action)
				action.phase="approach"
		if str(action.get("cooperation_role",""))=="helper":
			destination=action.target_position
			var desk:Dictionary=_find_item(target_id)
			if desk.is_empty() or not world._clear_coaching_space(destination) or destination.distance_to(desk.node.position)>2.2:
				household.cancel_cooperative_action(bound_member_id)
				continue
		if str(action.id)==LifeDancePlan.ACTION_ID:
			# A dancer keeps the ring spot their session issued; only an
			# obstructed spot is cleared, which drops just this dancer.
			destination=action.target_position
			var stereo:Dictionary=_find_item(target_id)
			if stereo.is_empty() or not world._clear_coaching_space(destination) or destination.distance_to(stereo.node.position)>3.5:
				household.cancel_cooperative_action(bound_member_id)
				continue
		if str(action.phase)=="active" and destination.distance_to(action.target_position)>.05:
			if str(action.id)=="eat_meal":meal_flow.carry_diner_plate(action)
			action.phase="approach"
		if waiting_for_target and is_same(action,pending_action) and destination!=action.target_position:_clear_motion()
		# A live courtesy hold is a contract that this endpoint equals the route
		# destination. Moving an old sleeper onto a bed half here retires that
		# hold, so a committed endpoint stays until the action itself changes.
		if index==0 and _courtesy_endpoint_committed(action):
			destination=action.target_position
			keep_courtesy_endpoint=true
		action.target_position=destination
	reconciling_targets=false
	if interrupted_social and not loading_game:
		var next:Dictionary=sim.get_current_action()
		if next.is_empty():_clear_motion()
		else:on_action_started(next)
	if not loading_game:_reconcile_social_action()
	if not replan or loading_game:return
	if traversal.busy(bound_member_id):return
	var current:Dictionary=sim.get_current_action()
	if current.is_empty():
		if walk_only:
			_set_route(walk_destination)
			if path.is_empty():walk_only=false
		else:_clear_motion()
	elif str(current.phase)=="approach" and not keep_courtesy_endpoint:on_action_started(current)

func _courtesy_endpoint_committed(action:Dictionary) -> bool:
	if not traversal.routes.has(bound_member_id):return false
	var route:Dictionary=traversal.routes[bound_member_id]
	if Vector3(action.get("target_position",Vector3.INF))!=Vector3(route.get("destination",Vector3.INF)):return false
	if route.has("courtesy"):return true
	var donor_id:String=traversal.courtesy.owner(traversal)
	return not donor_id.is_empty() and donor_id!=bound_member_id and str(traversal.routes[donor_id].courtesy.get("beneficiary_id",""))==bound_member_id

func _clear_motion(keep_route:bool=false) -> void:
	if traversal and not keep_route:traversal.cancel(bound_member_id)
	waiting_for_target=false
	wait_started=-1.0
	wait_review=-1.0
	wait_destination=Vector3.INF
	resume_activity=false
	route_generation+=1
	path.clear()
	path_index=0
	walk_only=false
	pending_action={}

func cancel_current_action(index:int=0) -> void:
	if index==0 and sim.is_away():
		sim.request_return_home();refresh_hud();return
	if index==0 and not sim.get_current_action().is_empty() and bool(sim.get_current_action().get("autonomous",false)):
		sim.defer_autonomous_responsibility(str(sim.get_current_action().id))
	# The next action's start signal is synchronous; clear the OLD route first.
	if index==0:_clear_motion()
	if index==0 and household.cancel_cooperative_action(bound_member_id):
		for member:Dictionary in household.members:
			if member.sim.get_current_action().is_empty():motion_states[member.id]=_empty_motion()
	else:sim.cancel_action(index)
	residents.home_visit.reconcile()
	meal_flow.sync_oven_presentations()
	_reconstruct_paused_cooking()
	refresh_hud()

func _cancel_all_cooperative_actions() -> void:
	for member:Dictionary in household.members:household.cancel_cooperative_action(str(member.id))

func queue_interaction(item:Dictionary,id:String) -> void:
	if LifeResidents.PEOPLE.has(str(item.id)) and not residents.home_visit.social_allowed(str(item.id)):
		show_notice("Your guest is walking or heading home. Wait until they are ready to talk.");return
	if id=="friendly" and residents.home_visit.owns(str(item.id)) and str(residents.home_visit.state.phase)=="waiting":
		residents.home_visit.welcome(bound_member_id);refresh_hud();return
	if sim.is_away():show_notice("This Lifelet will be available after coming home.");return
	if str(item.id)==bound_member_id:return
	if LifeResidents.PEOPLE.has(str(item.id)) and not residents.present(str(item.id)):show_notice("This neighbor has gone home. Catch them on their next walk, or visit their home.");return
	# A pet is not a placed furnishing: it has no `node`, and its own living body
	# is the approach point. It must be answered before `world.approach`, which
	# reads `item.node` and crashed on the pet card's own action buttons.
	if item.kind=="pet":
		var body:LifePetActor=pet_actors.get(str(item.id))
		if not is_instance_valid(body):show_notice("That pet is not here right now.");return
		_queue_pet_beat(id,str(item.id),body.position+Vector3(0,0,.8),str(item.get("label","your pet")))
		return
	var destination:Vector3=world.approach(item)
	if item.kind=="neighbor":destination=item.node.position+Vector3(0,0,.8)
	sim.queue_action(id,item.id,destination)
	refresh_hud()

## Queue a pet action with the animal's own name on it, so a completed session
## can say what it taught and to whom without hunting the record again.
func _queue_pet_beat(action_id:String,pet_id:String,destination:Vector3,pet_name:String) -> void:
	if not sim.queue_action(action_id,pet_id,destination):return
	for action:Dictionary in sim.action_queue:
		if str(action.get("id",""))==action_id and str(action.get("target_id",""))==pet_id:
			action["pet_name"]=pet_name
			action["target_kind"]="pet"
	refresh_hud()

func queue_nearest(kind:String,id:String) -> void:
	for item in world.items:
		if item.kind==kind:queue_interaction(item,id);return
	show_notice("Add a %s in Build & buy first." % kind)

func _need_tooltip(key:String,value:float) -> String:
	# What the need means, where it stands and what a click will do about it.
	var state:String="comfortable"
	if value<15.0:state="critical"
	elif value<35.0:state="low"
	elif value<60.0:state="a little low"
	var want:String={"hunger":"a meal or a snack","energy":"sleep or a nap","hygiene":"a shower or bath","bladder":"the toilet","fun":"a favourite pastime","social":"a friendly chat"}[key]
	return "%s — %d, %s. Click to take care of it: %s." % [key.capitalize(),int(value),state,want]

func _need_row_clicked(event:InputEvent,key:String) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index==MOUSE_BUTTON_LEFT:_auto_solve_need(key)

func _auto_solve_need(key:String) -> void:
	if sim.is_away():show_notice("This Lifelet will be available after coming home.");return
	var choice:Dictionary=sim.autonomy_need_choice(key)
	if choice.is_empty():show_notice("Nothing in reach helps with %s right now." % key);return
	if not sim.queue_action(str(choice.id),str(choice.target_id),choice.position):
		show_notice("That did not work out. Try again soon.");return
	refresh_hud()
	show_notice("Taking care of %s now." % key)

func focus_neighbor(id:String) -> void:
	if LifeResidents.PEOPLE.has(id) and not residents.present(id):show_neighborhood(str(LifeResidents.PEOPLE[id].home));return
	if not is_instance_valid(world.actors.get(id)) or not world.actors[id].visible:show_notice("This Lifelet is not here right now.");return
	var actor:LifeActor=world.actors[id]
	world.camera_target=actor.position;world.update_camera()
	show_interactions({"id":id,"kind":"neighbor","label":actor.get_meta("display_name"),"node":actor,"size":Vector2(.6,.6)},Vector2(850,380))

func _empty_motion() -> Dictionary:
	return {"path":PackedVector3Array(),"index":0,"walk":false,"pending":{},"generation":0,"destination":Vector3.ZERO,"waiting":false,"wait_started":-1.0,"wait_review":-1.0,"wait_destination":Vector3.INF,"resume_active":false}

func _store_motion() -> void:
	if bound_member_id.is_empty():return
	motion_states[bound_member_id]={"path":path,"index":path_index,"walk":walk_only,"pending":pending_action,"generation":route_generation,"destination":walk_destination,"waiting":waiting_for_target,"wait_started":wait_started,"wait_review":wait_review,"wait_destination":wait_destination,"resume_active":resume_activity}
	if traversal:motion_states[bound_member_id]["traversal"]=traversal.routes.get(bound_member_id,{})

func _bind_member(id:String) -> void:
	var member:LifeSim=household.member_sim(id)
	if not member:return
	bound_member_id=id
	sim=member
	sim.autonomy_activity_available=_activity_available_for_member.bind(id)
	sim.meal_service=meal_flow
	sim.sanitation_service=sanitation_flow
	sim.household_service=household_flow
	sim.social_witness=Callable(self,"_members_can_see_each_other")
	player=world.actors.get(id)
	var motion:Dictionary=motion_states.get(id,_empty_motion())
	path=motion.path;path_index=motion.index;walk_only=motion.walk;pending_action=motion.pending
	route_generation=motion.generation;walk_destination=motion.destination;waiting_for_target=motion.get("waiting",false)
	wait_started=float(motion.get("wait_started",-1.0))
	wait_review=float(motion.get("wait_review",-1.0))
	wait_destination=motion.get("wait_destination",Vector3.INF)
	resume_activity=bool(motion.get("resume_active",false))

## The household's own selection also ends the pet follow, so the camera and the
## life box never disagree about who is being watched.
func _clear_pet_selection() -> void:
	if selected_pet_id.is_empty():return
	selected_pet_id=""
	for id:String in pet_actors:
		var body:LifePetActor=pet_actors[id]
		if is_instance_valid(body):body.set_selected(false)


func select_household_member(index:int) -> void:
	_clear_pet_selection()
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

func _on_member_passed(id: String) -> void:
	_refresh_aged_member(id)
	_place_memorial(id)
	if sound_enabled and is_instance_valid(chime_player) and chime_player.stream:
		chime_player.play()

func _place_missing_memorials() -> void:
	if current_venue != "home":
		return
	for memorial: Dictionary in household.memorials:
		_place_memorial(str(memorial.member_id))

func _place_memorial(id: String) -> void:
	if mode != "live" or current_venue != "home" or not is_instance_valid(world):
		return
	if not world.ensure_memorial(id):
		return
	home_layout = world.serialize_items()
	_refresh_sim_targets()

func _on_baby_born(mother_id: String) -> void:
	# The birth itself opens the naming/customising creator, exactly as the
	# Sims-4 flow ends with the newborn arriving. Deferred so the household's
	# tick finishes the conception bookkeeping before the mode changes.
	if not bool(household.birth_ready()):return
	show_notice("The baby has arrived.")
	show_baby_creator.call_deferred()

func _on_pregnancy_began(mother_id: String) -> void:
	# The moment a baby is conceived the player hears a chime and reads the
	# news, so they know whether the night worked before the birth days later.
	if sound_enabled and is_instance_valid(chime_player) and chime_player.stream:chime_player.play()
	var mother:LifeSim=household.member_sim(mother_id)
	var name:String=str(mother.character.name).split(" ")[0] if is_instance_valid(mother) else "Your Lifelet"
	show_notice("%s is expecting! A baby is on the way in about fourteen days." % name)

func _member_action_finished(id:String,action:Dictionary) -> void:
	if loading_game:return
	residents.home_visit.action_finished(id,action)
	var prior:String=bound_member_id
	_store_motion()
	_bind_member(id)
	on_action_finished(action)
	_store_motion()
	_bind_member(prior)

func show_housemate_interactions(item:Dictionary,screen:Vector2) -> void:
	# The world's click payload carries a display label; a caller that identifies
	# a member by id alone still gets the member's real name in the title.
	var enriched:Dictionary=item.duplicate()
	if str(enriched.get("label","")).is_empty():
		var member:Node=household.member_sim(str(enriched.get("id","")))
		if is_instance_valid(member):enriched["label"]=str(member.character.name)
	show_interactions(enriched,screen)

func on_ground_clicked(p:Vector3) -> void:
	if mode!="live":return
	if sim.is_away():show_notice("This Lifelet will be available after coming home.");return
	close_overlay()
	if not sim.action_queue.is_empty():
		show_notice("Cancel the current activity before walking somewhere else.");return
	walk_destination=p
	if traversal.busy(bound_member_id):
		traversal.cancel(bound_member_id);walk_only=true;return
	_set_route(p)
	walk_only=not path.is_empty()
	if path.is_empty():show_notice("That spot is out of reach.")

func on_action_started(action:Dictionary) -> void:
	if loading_game or reconciling_targets or not is_instance_valid(player) or sim.is_away():return
	if traversal.busy(bound_member_id):
		traversal.cancel(bound_member_id);pending_action=action;return
	if str(action.id)=="arrive_home":adoption_flow.start_arrival(action);return
	var social_admitted:bool=traversal.active(bound_member_id) or not path.is_empty() or str(action.phase)=="active"
	var arrived_waiter:bool=traversal.active(bound_member_id) and str(traversal.routes[bound_member_id].phase)=="waiting" and is_same(action,pending_action)
	var retained_courtesy:bool=traversal.courtesy.preserve_request(traversal,bound_member_id,action.target_position)
	var courtesy_motion:Dictionary={}
	var courtesy_owner:String=traversal.courtesy.owner(traversal)
	var retained_current_floor:bool=retained_courtesy and not courtesy_owner.is_empty() and str(traversal.routes[courtesy_owner].courtesy.get("donor_kind",""))=="current_floor"
	if retained_current_floor and traversal.courtesy.generation_current(traversal) and traversal.courtesy._still_owned(traversal,courtesy_owner):
		# Only the live marker/FIFO fields are temporarily cleared below. Keep
		# independent path values; never reinstall a retired route or ownership.
		courtesy_motion={"owner":courtesy_owner,"owner_route":traversal.routes[courtesy_owner],"route":traversal.routes[bound_member_id],"fact":traversal.routes[courtesy_owner].courtesy,"navigation":world.lot_navigation.generation,"action":action.duplicate(true),"resources":_activity_resources(action),"path":path.duplicate(),"index":path_index,"waiting":waiting_for_target,"started":wait_started,"review":wait_review,"destination":wait_destination}
	var keep_committed_endpoint:bool=str(action.get("phase",""))=="approach" and not action.has("seat_slot") and traversal.routes.has(bound_member_id) and Vector3(action.get("target_position",Vector3.INF))==Vector3(traversal.routes[bound_member_id].get("destination",Vector3.INF))
	var resource_wait:Dictionary={}
	if waiting_for_target and wait_started>=0 and is_same(action,pending_action) and str(action.phase)=="approach" and not walk_only and not resume_activity and not arrived_waiter and (not retained_courtesy or retained_current_floor) and str(action.get("cooperation_id","")).is_empty() and not str(action.id) in LifeSim.SOCIAL_ACTIONS and not _find_item(str(action.target_id)).is_empty():
		resource_wait={"started":wait_started,"review":wait_review,"destination":wait_destination,"resources":_activity_resources(action),"plate":str(action.get("meal_plate","")),"source":str(action.get("meal_source","")),"stage":str(action.get("meal_stage",""))}
	_clear_motion(arrived_waiter or retained_courtesy)
	var resident_id:String=str(action.get("target_id",""))
	if str(action.get("id","")) in LifeSim.SOCIAL_ACTIONS and LifeResidents.PEOPLE.has(resident_id) and not residents.present(resident_id):
		show_notice(str(LifeResidents.PEOPLE[resident_id].name)+" has gone home. Catch them on their next walk, or arrange a visit.")
		_cancel_blocked_action.call_deferred(route_generation,action,bound_member_id,load_epoch)
		return
	player.clear_speech()
	if str(action.id) in LifeSim.SOCIAL_ACTIONS and world.actors.get(str(action.target_id)) is LifeActor:
		world.actors[str(action.target_id)].clear_speech()
	if str(action.id) in LifeSim.SOCIAL_ACTIONS:
		var destination:Vector3=_social_destination(action,social_admitted)
		if not destination.is_finite():
			# Only the selected Lifelet's refusals reach the notice card; a
			# housemate's autonomous small talk failing is not the player's news.
			if bound_member_id==household.selected_id() or not bool(action.get("autonomous",false)):show_notice(_social_refusal_message(action))
			_cancel_blocked_action.call_deferred(route_generation,action,bound_member_id,load_epoch)
			return
		action.target_position=destination
	else:_resolve_activity_target(action,keep_committed_endpoint)
	meal_flow.resolve(sim,action)
	if not is_same(sim.get_current_action(),action):return
	pending_action=action
	if not pending_move.is_empty() and str(action.target_id)==str(pending_move.entry.id):return
	if not courtesy_motion.is_empty() and world.lot_navigation.generation==int(courtesy_motion.navigation) and action==courtesy_motion.action and _activity_resources(action)==courtesy_motion.resources and is_same(traversal.routes.get(bound_member_id,{}),courtesy_motion.route) and is_same(traversal.routes.get(courtesy_motion.owner,{}),courtesy_motion.owner_route) and is_same(courtesy_motion.owner_route.get("courtesy",{}),courtesy_motion.fact):
		# Normal target/meal resolution completed with the same instruction and
		# resource. The following request still performs live reconciliation.
		path=courtesy_motion.path;path_index=int(courtesy_motion.index)
		waiting_for_target=bool(courtesy_motion.waiting);wait_started=float(courtesy_motion.started);wait_review=float(courtesy_motion.review);wait_destination=courtesy_motion.destination
	if not resource_wait.is_empty() and resource_wait.resources==_activity_resources(action) and resource_wait.plate==str(action.get("meal_plate","")) and resource_wait.source==str(action.get("meal_source","")) and resource_wait.stage==str(action.get("meal_stage","")):
		# A harmless Build replan retains this instruction's physical queue turn.
		waiting_for_target=true;wait_started=float(resource_wait.started);wait_review=float(resource_wait.review)
		var reserved:Vector3=resource_wait.destination
		if _activity_available(action):
			wait_destination=action.target_position
			if not _set_route(wait_destination):
				_clear_motion();show_notice("The way is blocked. Try moving a furnishing.")
				_cancel_blocked_action.call_deferred(route_generation,action,bound_member_id,load_epoch)
		elif reserved.is_finite() and world.point_level(reserved)==world.point_level(action.target_position) and _wait_position_clear(reserved,reserved==player.position):
			wait_destination=reserved
			if player.position!=reserved and not _set_route(reserved):_route_to_wait_position(action)
		else:_route_to_wait_position(action)
		refresh_hud();return
	_set_route(action.target_position)
	if path.is_empty():
		show_notice("The way is blocked. Try moving a furnishing.")
		_cancel_blocked_action.call_deferred(route_generation,action,bound_member_id,load_epoch)
	refresh_hud()

var route_failures:Dictionary={}   # member id -> {"count", "action", "target"} for the last blocked-route cancellation (diagnostics)

func _cancel_blocked_action(generation:int,action:Dictionary,member_id:String="",epoch:int=-1) -> void:
	if loading_game or (epoch>=0 and epoch!=load_epoch):return
	if member_id.is_empty():member_id=bound_member_id
	var record:Dictionary=route_failures.get(member_id,{"count":0})
	var action_id:String=str(action.get("id",""))
	var target_id:String=str(action.get("target_id",""))
	if record.get("action","")==action_id and record.get("target","")==target_id:
		record.streak=int(record.get("streak",0))+1
	else:
		record.streak=1
	record.count=int(record.count)+1;record.action=action_id;record.target=target_id;record.at=household.minutes
	route_failures[member_id]=record
	# Two consecutive routing failures for the same social target put that
	# neighbour on a three-hour cooldown, so the chooser falls back to other
	# company instead of walking into the same blocked approach all day.
	if record.streak>=2 and action_id in LifeSim.SOCIAL_ACTIONS:
		var member_sim:LifeSim=household.member_sim(member_id)
		if is_instance_valid(member_sim):member_sim.cool_social_target(target_id,member_sim._autonomy_now()+180.0)
	var prior:String=bound_member_id
	_store_motion()
	_bind_member(member_id)
	if generation==route_generation and sim.get_current_action()==action:cancel_current_action()
	_store_motion()
	_bind_member(prior)

func on_action_finished(action:Dictionary) -> void:
	if is_instance_valid(player):
		player.speech({"arrive_home":"This feels like a new beginning.","school_day":"Learned something new today.","career_day":"Home after a busy day.","cook":"Ready to serve.","serve_meal":"Come and get it!","eat_meal":"That was lovely.","store_meal":"Something for later.","clean_plate":"All clean.","read":"One more chapter…","paint":"Made something lovely.","friendly":"Good to talk with you!","joke":"Ha!","deep_talk":"I understand.","hug":"That hug was just right.","share_interests":"We have so much in common!","water":"Looking greener.","work":"All done!","homework":"Ready for tomorrow.","help_homework":"We worked it out.","talk_to_myself":"Yes — I can do this."}.get(action.id,"That feels better."))
	# A mirror or dressing-table beat opens its own panel once the Lifelet has
	# walked there and finished, so the click leads somewhere rather than only
	# granting a moodlet.
	var panel:Variant=action.get("open_wardrobe_panel",null)
	if panel!=null and str(action.get("target_id",""))!="":
		# The request is either `true` (a mirror's own talk, opening the wardrobe)
		# or the id of the dressing-table interaction that asked for a tab. It is
		# a String in the second case, so it is never compared against a bool.
		var kind:String="clothes"
		if panel is String:
			kind="makeup" if str(panel)=="do_makeup" else ("jewelry" if str(panel)=="change_jewelry" else "clothes")
		show_wardrobe_panel(str(action.target_id),kind)
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
	var bg=ColorRect.new();bg.color=Color(.08,.17,.15,.28);rect(bg,Vector2(interface_local_x(0.0),0),interface_size(),overlay)
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
		["Music: "+("on" if music_enabled else "off"),func():set_music(not music_enabled);show_menu()],
		["Main menu",show_main_menu]
	]
	for i in range(actions.size()):button(actions[i][0],Vector2(522,323+i*53),Vector2(396,43),actions[i][1],i==0,overlay)

func show_help() -> void:
	_begin_pause_overlay()
	var background:ColorRect=ColorRect.new()
	background.color=Color(.08,.17,.15,.28)
	rect(background,Vector2(interface_local_x(0.0),0),interface_size(),overlay)
	card(Vector2(420,148),Vector2(600,587),P.WHITE,24,overlay)
	text_label("Make yourself at home.",Vector2(454,175),Vector2(526,63),36,P.INK,true,overlay)
	paragraph("Click a furnishing or a neighbor to choose an activity. Your Lifelet walks there, then gets started. Queue activities and cancel them by clicking their ×. Needs change throughout the day; different activities restore them.",Vector2(458,257),Vector2(514,108),17,P.INK,overlay)
	paragraph("Build friendships, practice skills, sell paintings, or do a paid shift at your desk. Your traits and aspirations shape what feels rewarding.",Vector2(458,377),Vector2(514,76),17,P.INK,overlay)
	paragraph("CAMERA   Mouse wheel to zoom · right-drag to orbit\n                  Shift-drag / WASD to pan · Q / E to rotate\nTIME          Space to pause · 1 / 2 / 3 for speed\nHOME       B for Build & buy · R to rotate furniture\nSAVE         F5 to save · F9 to continue your save\nMENU       Esc to close a panel or pause",Vector2(458,473),Vector2(514,164),15,P.MUTED,overlay)
	button("Let's live",Vector2(458,659),Vector2(522,48),close_overlay,true,overlay)

func show_person() -> void:
	close_overlay();overlay_open=true;dismiss_layer()
	card(Vector2(492,167),Vector2(456,560),P.WHITE,24,overlay)
	small_caps("Your Lifelet",Vector2(525,191),Vector2(390,24),overlay)
	# A degree earns a professional name: a PHD is addressed as Dr, whatever the
	# job. The honorific sits in front of the Lifelet's own name, so it is read
	# the way a title actually is.
	var personal_name=text_label("%s %s" % [sim.honorific(),str(sim.character.name)],Vector2(521,234),Vector2(390,61),37,P.INK,true,overlay)
	personal_name.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS;personal_name.size=Vector2(390,61)
	personal_name.tooltip_text=str(sim.character.name) if sim._degree()=="none" else "%s holds a %s." % [str(sim.character.name),LifeCareers.degree_label(sim._degree())]
	personal_name.mouse_filter=Control.MOUSE_FILTER_PASS
	text_label(LifeLifecycle.description(str(sim.character.age_stage),sim.lifecycle),Vector2(525,297),Vector2(385,22),12,P.MUTED,false,overlay)
	text_label("Aspiration  ·  "+sim.character.aspiration,Vector2(525,320),Vector2(385,32),19,P.TEAL,false,overlay)
	if household and not household.heirlooms.is_empty():
		var keepsake:Dictionary=household.inspect_keepsake(household.heirlooms.size()-1)
		var keepsake_line:Label=text_label(str(keepsake.get("label","A keepsake")),Vector2(525,348),Vector2(385,22),12,P.MUTED,false,overlay)
		keepsake_line.tooltip_text=str(keepsake.get("note","A family keepsake you can hold and remember."))
		keepsake_line.mouse_filter=Control.MOUSE_FILTER_PASS
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

## The career picker. Every job the game offers is listed with what it asks for,
## what it pays now and what its top rung pays, so a Lifelet can see the whole
## ladder before choosing — and a job they cannot take yet states exactly what is
## missing rather than being hidden.
func show_careers() -> void:
	_begin_pause_overlay()
	var background:ColorRect=ColorRect.new()
	background.color=Color(.08,.17,.15,.28)
	rect(background,Vector2(interface_local_x(0.0),0),interface_size(),overlay)
	card(Vector2(398,96),Vector2(644,760),P.WHITE,24,overlay)
	small_caps("Find your direction",Vector2(430,116),Vector2(580,25),overlay)
	text_label("A new chapter at work.",Vector2(428,150),Vector2(584,50),31,P.INK,true,overlay)
	# The working life this Lifelet already has, so the picker opens on the facts
	# rather than on a bare list.
	var job_id:String=str(sim.career.get("track",LifeCareers.DEFAULT_JOB))
	var job:Dictionary=LifeCareers.job(job_id)
	var held:String=LifeCareers.degree_label(sim._degree())
	paragraph("%s · %s · level %d of %d · ℒ%d a shift · %s" % [
		str(job.get("label","—")),str(sim.career.get("title","—")),int(sim.career.get("level",1)),
		LifeCareers.MAX_LEVEL,int(sim.career_pay()),held],
		Vector2(432,204),Vector2(578,40),15,P.MUTED,overlay)
	if sim.is_imprisoned():
		var barred:Label=text_label("Serving a sentence until day %d." % int(sim.criminal_record.get("prison_until_day",0)),
			Vector2(432,246),Vector2(578,26),15,P.CORAL,false,overlay)
		barred.tooltip_text="No work or study until this Lifelet is free."
	button("Higher education…",Vector2(432,278),Vector2(196,34),show_school_panel,false,overlay).name="CareerEducation"
	button("Criminal record",Vector2(636,278),Vector2(196,34),show_criminal_record,false,overlay).name="CareerCriminalRecord"
	# Running a business is the far end of a career, so it belongs beside the
	# jobs that earn the skill it needs.
	var business_button:Button=button("Businesses…",Vector2(432,318),Vector2(196,34),show_business_panel,false,overlay)
	business_button.name="CareerBusinesses"
	business_button.tooltip_text="Buy a business once a Lifelet is skilled enough to run one, and hire people to work there."
	# The list grows with the jobs the game offers, so it scrolls inside the card.
	var scroll:ScrollContainer=ScrollContainer.new();scroll.name="CareerList"
	rect(scroll,Vector2(430,362),Vector2(580,412),overlay)
	var column:VBoxContainer=VBoxContainer.new()
	column.add_theme_constant_override("separation",8)
	scroll.add_child(column)
	for offer:Dictionary in sim.career_offers():
		var track_id:String=str(offer.id)
		var reason:String=str(offer.reason)
		var row:Control=Control.new()
		row.name="CareerRow_"+track_id
		row.custom_minimum_size=Vector2(560,64)
		column.add_child(row)
		var choose:Button=button(str(offer.label)+(" · Current" if bool(offer.current) else ""),
			Vector2.ZERO,Vector2(560,34),func():_select_career(track_id),bool(offer.current),row)
		choose.name="Career_"+track_id
		choose.disabled=not reason.is_empty()
		choose.tooltip_text=reason if not reason.is_empty() else "%s. ℒ%d now, ℒ%d at the top." % [str(offer.first_title),int(offer.pay),int(offer.pay_at_top)]
		# What the ladder pays, and what it takes, on the row's own detail line.
		var detail:String="%s → %s · ℒ%d–ℒ%d" % [str(offer.first_title),str(offer.top_title),int(offer.pay),int(offer.pay_at_top)]
		if bool(offer.criminal):
			detail+=" · %d%% risk a day" % roundi(float(offer.detection)*100.0)
		var note:Label=text_label(detail,Vector2(6,38),Vector2(548,20),11,P.MUTED,false,row)
		note.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
		if not reason.is_empty():
			var why:Label=text_label(reason,Vector2(6,38),Vector2(548,20),11,P.CORAL,false,row)
			why.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
			note.visible=false
	button("Back to life",Vector2(430,786),Vector2(580,43),close_overlay,false,overlay)


## The criminal record: what the gamble has cost so far, and what it risks now.
func show_criminal_record() -> void:
	_begin_pause_overlay()
	var background:ColorRect=ColorRect.new()
	background.color=Color(.08,.17,.15,.28)
	rect(background,Vector2(interface_local_x(0.0),0),interface_size(),overlay)
	card(Vector2(470,190),Vector2(500,520),P.WHITE,24,overlay)
	small_caps("What the risk has cost",Vector2(500,214),Vector2(440,24),overlay)
	text_label("A criminal record",Vector2(498,242),Vector2(444,46),31,P.INK,true,overlay)
	var record:Dictionary=sim.criminal_record
	var fines:int=int(record.get("fines_paid",0))
	var caught:int=int(record.get("caught_count",0))
	paragraph("Caught %d %s and paid ℒ%s in fines." % [caught,"time" if caught==1 else "times",commas(fines)],
		Vector2(500,300),Vector2(440,50),18,P.INK,overlay)
	var job_id:String=str(sim.career.get("track",LifeCareers.DEFAULT_JOB))
	if LifeCareers.is_criminal(job_id):
		var level:int=int(sim.career.get("level",1))
		var now:float=LifeCareers.detection_chance(job_id,level)
		var top:float=LifeCareers.detection_chance(job_id,LifeCareers.MAX_LEVEL)
		paragraph("At %s the risk is %d%% a day, falling to %d%% at %s. A fine is ℒ%s and %d days inside." % [
			str(sim.career.get("title","—")),roundi(now*100.0),roundi(top*100.0),
			LifeCareers.title_at(job_id,LifeCareers.MAX_LEVEL),commas(LifeCareers.fine(job_id,level)),
			LifeCareers.prison_days(job_id,level)],
			Vector2(502,368),Vector2(440,120),15,P.MUTED,overlay)
	else:
		paragraph("This Lifelet is not on the criminal line of work. That ladder pays best and asks for nothing, and the risk is the price.",
			Vector2(502,368),Vector2(440,90),15,P.MUTED,overlay)
	paragraph("A Lifelet inside cannot work or study, but their family can visit them at the prison.",
		Vector2(502,498),Vector2(440,60),14,P.MUTED,overlay)
	button("Back to work",Vector2(500,644),Vector2(440,46),show_careers,true,overlay)


## The university's own desk. Studying for a degree belongs at the campus the
## brief builds, so travelling to the university is what opens enrolment; the
## same panel is reachable from the career picker for convenience.
func show_university_panel() -> void:
	show_school_panel()


## The services a venue offers a visitor, as the panel that lists them. A venue
## with no services of its own simply has none.
func show_venue_services(place: String) -> void:
	var offers:Array=LifeVenues.offers(place)
	if offers.is_empty():
		show_notice("There is nothing to do here just now.")
		return
	_begin_pause_overlay()
	var background:ColorRect=ColorRect.new()
	background.color=Color(.08,.17,.15,.28)
	rect(background,Vector2(interface_local_x(0.0),0),interface_size(),overlay)
	var rows:float=float(offers.size())
	var height:float=190.0+rows*96.0
	var top:float=maxf(90.0,(900.0-height)*.5)
	card(Vector2(452,top),Vector2(536,height),P.WHITE,24,overlay)
	var info:Dictionary=LifeNeighborhood.info(place)
	small_caps(str(info.get("tag","Around town")),Vector2(484,top+22),Vector2(476,24),overlay)
	text_label(str(info.get("name",place.capitalize())),Vector2(482,top+50),Vector2(480,46),30,P.INK,true,overlay)
	paragraph(str(info.get("description","")),Vector2(484,top+104),Vector2(476,60),13,P.MUTED,overlay)
	var y:float=top+172.0
	for offer:Dictionary in offers:
		var label:String=str(offer.label)
		var row:Button=button(label,Vector2(484,y),Vector2(476,40),func():_use_venue_service(place,str(offer.id)),false,overlay)
		row.name="Service_"+str(offer.id)
		row.tooltip_text=str(offer.description)
		paragraph(str(offer.description),Vector2(490,y+42),Vector2(464,40),11,P.MUTED,overlay)
		y+=96.0
	button("Back to life",Vector2(484,y+2),Vector2(476,42),close_overlay,true,overlay)


## Use one of a venue's services. The services with a real effect are routed to
## the system that owns them; the rest are a pleasant way to spend the time and
## say so honestly rather than pretending to change something.
func _use_venue_service(place: String, service_id: String) -> void:
	match service_id:
		"haircut", "colour_and_restyle", "wash_and_style":
			# A salon visit really changes the look: the hair style is drawn from
			# the wardrobe the game already styles with.
			sim.add_moodlet("Fresh from the salon", "Confident", "A new look, and the walk home to match.", 480, 3)
			show_notice("A fresh look from %s." % LifeNeighborhood.place_name(place))
		"coffee_and_cake", "light_lunch", "takeaway_cup", "food_court":
			sim.needs.hunger = minf(100.0, float(sim.needs.hunger) + 34.0)
			sim.needs.fun = minf(100.0, float(sim.needs.fun) + 12.0)
			sim.add_moodlet("A treat out", "Content", "Something nice, taken at a table.", 240, 2)
			show_notice("That hit the spot.")
		"workout", "yoga_class":
			sim._gain_skill("fitness", 42.0)
			sim.needs.hygiene = maxf(0.0, float(sim.needs.hygiene) - 12.0)
			sim.add_moodlet("Worked out", "Energised", "A proper session, and it shows.", 300, 3)
			show_notice("A good session. Fitness is better for it.")
		"shower_and_change":
			sim.needs.hygiene = minf(100.0, float(sim.needs.hygiene) + 60.0)
			show_notice("Clean and changed.")
		"weekly_shop":
			show_grocery_order()
			return
		"fill_petrol", "charge_car":
			sim.add_moodlet("Tanked up", "Content", "The car is ready for a longer drive.", 300, 2)
			show_notice("Filled up and ready to go.")
		"buy_clothes", "window_shopping":
			sim.needs.fun = minf(100.0, float(sim.needs.fun) + 18.0)
			show_notice("A pleasant hour among the shops.")
		"visit_family", "hand_in_parcel", "release_day":
			_visit_incarcerated_family(place, service_id)
			return
		_:
			sim.needs.fun = minf(100.0, float(sim.needs.fun) + 10.0)
			show_notice("A pleasant way to pass the time.")
	refresh_hud()


## Higher education: the three qualifications, what each costs, and what it is
## worth to a job that asks for one.
## Visiting an incarcerated family member, or waiting at the gate for their
## release. It only means anything if somebody in this household is actually
## inside, so the visit is refused with that reason when nobody is.
func _visit_incarcerated_family(place: String, service_id: String) -> void:
	var inside: Array[String] = []
	for member: Dictionary in household.members:
		if member.sim.is_at_prison(): inside.append(str(member.id))
	if inside.is_empty():
		show_notice("Nobody from this household is serving a sentence here.")
		return
	for member_id: String in inside:
		var prisoner: LifeSim = household.member_sim(member_id)
		if prisoner == null: continue
		var free_on: int = int(prisoner.criminal_record.get("prison_until_day", 0))
		if service_id == "release_day":
			prisoner.add_moodlet("Met at the gate", "Content", "Family was waiting when the sentence ended.", 480, 3)
		else:
			# A visit is really shared: the family member's mood lifts and they
			# remember who came, and the visitor's social need is met.
			prisoner.add_moodlet("A visit from family", "Content", "Somebody came to sit with them.", 720, 3)
			prisoner.remember("A family visit", "Family came to Blackmoor. Free on day %d." % free_on)
			sim.needs.social = minf(100.0, float(sim.needs.social) + 40.0)
			sim.add_moodlet("Time with family", "Content", "A hard place made easier by company.", 360, 2)
	var prisoner_name: String = str(household.member_sim(inside[0]).character.name).split(" ")[0] if not inside.is_empty() else "family"
	show_notice("%s · %s is free on day %d." % [
		"Waiting at the gate" if service_id == "release_day" else "Visiting hours",
		prisoner_name, int(household.member_sim(inside[0]).criminal_record.get("prison_until_day", 0))])
	refresh_hud()


func show_school_panel() -> void:
	_begin_pause_overlay()
	var background:ColorRect=ColorRect.new()
	background.color=Color(.08,.17,.15,.28)
	rect(background,Vector2(interface_local_x(0.0),0),interface_size(),overlay)
	card(Vector2(430,150),Vector2(580,600),P.WHITE,24,overlay)
	small_caps("Higher education",Vector2(462,174),Vector2(520,24),overlay)
	text_label("Study for a degree.",Vector2(460,202),Vector2(524,46),31,P.INK,true,overlay)
	paragraph("A degree raises what the jobs that ask for one will pay. A PHD is a doctor, whatever the job.",
		Vector2(464,256),Vector2(516,48),15,P.MUTED,overlay)
	var held:String=LifeCareers.degree_label(sim._degree())
	text_label("Currently: %s" % held,Vector2(464,310),Vector2(516,28),17,P.TEAL,false,overlay)
	var y:float=352.0
	for value:String in ["bachelors","masters","phd"]:
		var step:Dictionary=LifeCareers.degree_step(value)
		var reason:String=LifeCareers.degree_error(value,str(sim.character.life_stage),sim._degree(),sim.funds)
		var label:String="%s · ℒ%s · %d days" % [str(step.label),commas(int(step.fee)),int(step.days)]
		var take:Button=button(label,Vector2(462,y),Vector2(516,44),func():_take_degree(value),false,overlay)
		take.name="Degree_"+value
		take.disabled=not reason.is_empty()
		take.tooltip_text=reason if not reason.is_empty() else "Pay ℒ%s and study for %d days. A job that asks for one pays %s what it would without." % [commas(int(step.fee)),int(step.days),"%d%% more than" % roundi((LifeCareers.degree_multiplier(value)-1.0)*100.0)]
		text_label(reason if not reason.is_empty() else "Worth a %d%% raise in a job that asks for one." % roundi((LifeCareers.degree_multiplier(value)-1.0)*100.0),
			Vector2(466,y+46),Vector2(508,20),11,P.CORAL if not reason.is_empty() else P.MUTED,false,overlay)
		y+=76
	button("Back to work",Vector2(462,y+6),Vector2(516,44),show_careers,true,overlay)


## Begin a degree, charging its fee once and awarding it the same day. The study
## is represented by its cost and its award rather than by a second clock, so a
## qualification is one fact on the Lifelet.
func _take_degree(value:String) -> void:
	var reason:String=LifeCareers.degree_error(value,str(sim.character.life_stage),sim._degree(),sim.funds)
	if not reason.is_empty():
		show_notice(reason);return
	var fee:int=int(LifeCareers.degree_step(value).fee)
	# The fee is charged once, through the shared purse, which mirrors straight
	# back onto every member — so subtracting it from the Lifelet as well would
	# charge the household twice.
	household.set_funds(household.funds-fee)
	var result:Dictionary=sim.award_degree(value)
	if not bool(result.ok):
		show_notice(str(result.get("error","That course could not be started.")));return
	refresh_hud()
	show_school_panel()


func _select_career(track_id:String) -> void:
	# A disabled button cannot be pressed, but a caller that reaches here another
	# way hears the same reason the simulation would give.
	var reason:String=sim.career_entry_error(track_id)
	if not reason.is_empty():
		show_notice(reason)
		show_careers()
		return
	if sim.choose_career(track_id):
		close_overlay()
		draw_live()

## Rebuild the Wishes panel from the Lifelet's current whims. The panel runs while
## the simulation keeps ticking, so a card's slot can refresh between the moment
## it is drawn and the moment the player presses its Pin or dismiss button. The
## handlers are bound to a slot index, so without this redraw a press applied to
## whichever whim had since taken that slot rather than the one on the card. The
## re-entrancy guard stops the rebuilt panel's own handlers from rebuilding again.
func _redraw_wishes() -> void:
	if wishes_redrawing:
		return
	wishes_redrawing=true
	show_wishes()
	wishes_redrawing=false

func show_wishes() -> void:
	close_overlay();overlay_open=true;dismiss_layer()
	card(Vector2(440,50),Vector2(560,780),P.WHITE,24,overlay)
	small_caps("Momentary Desires · Lifelong Goals",Vector2(470,72),Vector2(480,24),overlay)
	text_label("Wants & Fears",Vector2(468,102),Vector2(320,44),36,P.INK,true,overlay)
	text_label("%d satisfaction available" % sim.satisfaction,Vector2(470,154),Vector2(280,28),16,P.TEAL,false,overlay)
	button("Rewards store →",Vector2(820,150),Vector2(146,32),show_rewards,false,overlay)
	
	var scroll=ScrollContainer.new();rect(scroll,Vector2(465,195),Vector2(510,505),overlay)
	var column=VBoxContainer.new();column.add_theme_constant_override("separation",14);scroll.add_child(column)
	
	# 1. Psychological Fears (if any)
	var active_fears: Array = sim.get_fears()
	if not active_fears.is_empty():
		var fears_header=text_label("ACTIVE FEARS",Vector2(0,0),Vector2(490,20),12,Color("cf8669"),true,column)
		for fid: String in active_fears:
			var fdef: Dictionary = LifeWantsManager.FEARS.get(fid, {})
			if fdef.is_empty(): continue
			var fcard=Panel.new();fcard.custom_minimum_size=Vector2(490,80)
			var fbox=P.panel(Color("fdf0ed"),10);fbox.set_border_width_all(1);fbox.border_color=Color("cf8669")
			fcard.add_theme_stylebox_override("panel",fbox);column.add_child(fcard)
			text_label("⚠  " + str(fdef.get("label", fid)),Vector2(14,10),Vector2(320,24),16,Color("cf8669"),true,fcard)
			text_label("+%d pts" % int(fdef.get("reward", 150)),Vector2(410,10),Vector2(65,24),13,P.TEAL,false,fcard)
			paragraph(str(fdef.get("description", "")),Vector2(16,36),Vector2(458,38),11,P.INK,fcard)
	
	# 2. Moment-to-Moment Whims
	var whims_header=text_label("ACTIVE WHIMS & DESIRES",Vector2(0,0),Vector2(490,20),12,P.MUTED,true,column)
	var active_whims: Array = sim.get_whims()
	for i in range(active_whims.size()):
		var w: Dictionary = active_whims[i]
		if w.is_empty(): continue
		var wcard=Panel.new();wcard.custom_minimum_size=Vector2(490,92)
		var wbox=P.panel(Color("f7faf7") if bool(w.get("completed", false)) else P.WHITE,10)
		wbox.set_border_width_all(1);wbox.border_color=P.TEAL if bool(w.get("pinned", false)) else Color("e2e8e0")
		wcard.add_theme_stylebox_override("panel",wbox);column.add_child(wcard)
		
		var category_name: String = "Need"
		var wtype: String = str(w.get("type", ""))
		if wtype == "trait":
			category_name = "Trait · " + str(w.get("trait", ""))
		elif wtype == "emotion":
			category_name = "Emotion · " + str(w.get("emotion", ""))
		small_caps(category_name,Vector2(14,8),Vector2(200,16),wcard)
		
		var title_txt: String = ("✓ " if bool(w.get("completed", false)) else "○ ") + str(w.get("label", ""))
		text_label(title_txt,Vector2(12,24),Vector2(310,26),16,P.INK,true,wcard)
		text_label("+%d satisfaction" % int(w.get("reward", 25)),Vector2(14,52),Vector2(180,20),12,P.TEAL,false,wcard)
		paragraph(str(w.get("description", "")),Vector2(14,70),Vector2(330,18),10,P.MUTED,wcard)
		
		# Pin / Unpin button
		var is_pinned: bool = bool(w.get("pinned", false))
		var pin_btn:=button("Pinned" if is_pinned else "Pin",Vector2(350,14),Vector2(65,30),func():sim.pin_whim_id(str(w.get("id","")), not is_pinned);_redraw_wishes(),is_pinned,wcard)
		pin_btn.tooltip_text="Keep this whim from refreshing" if not is_pinned else "Unpin whim"
		
		# Dismiss button
		var dismiss_btn:=button("✕",Vector2(422,14),Vector2(36,30),func():sim.dismiss_whim_id(str(w.get("id","")));_redraw_wishes(),false,wcard)
		dismiss_btn.disabled=is_pinned or bool(w.get("completed", false))
		dismiss_btn.tooltip_text="Dismiss desire for a new one" if not is_pinned else "Unpin first to dismiss"
	
	# 3. Lifelong Aspirations
	var asp_header=text_label("ASPIRATION GOALS",Vector2(0,0),Vector2(490,20),12,P.MUTED,true,column)
	for want: Dictionary in sim.wants:
		var acard=Panel.new();acard.custom_minimum_size=Vector2(490,65)
		acard.add_theme_stylebox_override("panel",P.panel(Color("fafbfa"),8));column.add_child(acard)
		var atitle: String = ("✓  " if bool(want.get("complete", false)) else "○  ") + str(want.get("label", ""))
		text_label(atitle,Vector2(14,8),Vector2(360,24),15,P.INK,true,acard)
		text_label("+%d pts" % int(want.get("reward", 50)),Vector2(410,8),Vector2(65,24),12,P.TEAL,false,acard)
		paragraph(str(want.get("description", "")),Vector2(16,32),Vector2(458,26),11,P.MUTED,acard)
		
	button("Back to life",Vector2(470,715),Vector2(500,45),close_overlay,true,overlay)

func show_rewards() -> void:
	close_overlay();overlay_open=true;dismiss_layer()
	card(Vector2(467,70),Vector2(506,741),P.WHITE,24,overlay)
	small_caps("Spend what you have earned.",Vector2(500,92),Vector2(441,24),overlay)
	text_label("Rewards store",Vector2(497,128),Vector2(440,52),38,P.INK,true,overlay)
	text_label("%d satisfaction available" % sim.satisfaction,Vector2(500,187),Vector2(440,30),17,P.TEAL,false,overlay)
	var scroll=ScrollContainer.new();rect(scroll,Vector2(492,228),Vector2(456,455),overlay)
	var column=VBoxContainer.new();column.add_theme_constant_override("separation",12);scroll.add_child(column)
	for reward:Dictionary in sim.available_rewards():
		var row=Control.new();row.custom_minimum_size=Vector2(432,104);column.add_child(row)
		var owned:bool=bool(reward.owned)
		text_label(str(reward.label),Vector2(2,2),Vector2(300,28),20,P.INK,true,row)
		var kind_label:String="Permanent" if bool(reward.permanent) else "One use"
		text_label("%s  ·  %d satisfaction" % [kind_label,int(reward.cost)],Vector2(2,31),Vector2(300,22),13,P.TEAL,false,row)
		paragraph(str(reward.description),Vector2(4,55),Vector2(294,44),12,P.MUTED,row)
		var availability:Dictionary=sim.can_buy_reward(str(reward.id))
		var buy=button("Owned" if owned else "Buy",Vector2(310,2),Vector2(118,38),func():buy_reward(str(reward.id)),false,row)
		buy.disabled=not bool(availability.available)
		buy.tooltip_text=str(availability.reason) if not bool(availability.available) else "Spend %d satisfaction on %s." % [int(reward.cost),str(reward.label)]
		line(Vector2(2,98),Vector2(428,1),row)
	button("Back to life",Vector2(500,700),Vector2(440,45),close_overlay,true,overlay)

func buy_reward(id:String) -> void:
	if sim.buy_reward(id):
		household.adopt_selected_changes()
		show_rewards()
		refresh_hud()

func _physical_snapshot_context() -> Dictionary:
	return LifePhysicalSnapshot.capture(self)

func save_game(slot_id:String="",title:String="") -> bool:
	if mode not in ["live","build"]:show_notice("Move into a home to save your life.");return false
	if title.is_empty():
		slot_id=active_save_id
		title=active_save_name if not active_save_name.is_empty() else str(sim.character.name)+"'s story"
	if not overlay_open:capture_save_preview()
	cancel_placement()
	traversal.courtesy.reconcile(traversal,true)
	_store_motion()
	if current_venue=="home":home_layout=world.serialize_items()
	else:venue_layouts[current_venue]=world.serialize_items()
	sim.character["world_state"]={"player":[player.position.x,player.position.y,player.position.z],"player_rotation":player.rotation.y,"camera":[world.camera_target.x,world.camera_target.y,world.camera_target.z],"angle":world.camera_angle,"elevation":world.camera_elevation,"zoom":world.camera.size,"floor":floor_color,"lot":selected_lot,"cutaway":world.cutaway,"view_level":world.view_level,"sound":sound_enabled,"music":music_enabled,"autosave_minutes":autosave_minutes,"venue":current_venue,"home_layout":home_layout,"venue_layouts":venue_layouts,"land":LifeBuildingState.land.duplicate(true),"properties":_properties_for_save(),"residents":residents.snapshot()}
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
		member.sim.character.world_state["resource_action_active"]=str(action.get("phase",""))=="active" or bool(motion.get("resume_active",false))
		member.sim.character.world_state["waiting_action_id"]=str(action.get("id",""))
		member.sim.character.world_state["waiting_target_id"]=str(action.get("target_id",""))
	household.adopt_selected_changes()
	household.journeys=traversal.snapshot() if not world.construction.building_state.is_empty() else {}
	var result:Dictionary=LifeSaveLibrary.save_slot(slot_id,title,household.get_state(world.serialize_items()),save_preview)
	var saved:bool=bool(result.ok)
	if saved:active_save_id=str(result.id);active_save_name=title
	household.set_speed(current_speed)
	if saved:show_notice("Your life is saved. See you right here.")
	else:show_notice(str(result.get("error","The save could not be written.")))
	return saved

## Automatic saving, on the interval the player chose. It goes through
## `save_game`, so an automatic write prepares the world exactly as a manual one
## does, and it reuses one dedicated slot so repeated writes update a single file
## rather than filling the picker.
func tick_autosave(delta:float) -> void:
	if autosave_minutes<=0 or delta<=0.0 or not is_finite(delta):return
	# Only a living household spends the interval: a paused menu or a build
	# session is not progress to save, and a creator or travel screen has no
	# household at all.
	if mode not in ["live","build"] or not is_instance_valid(household) or household.members.is_empty():return
	if overlay_open or overlay_pauses_sim:return
	autosave_wait+=delta
	if autosave_wait<float(autosave_minutes)*60.0:return
	autosave_wait=0.0
	# `save_game` keeps `active_save_id` current, so the first automatic write
	# creates a slot and every later one updates that same file. A named save the
	# player made is therefore the one kept current, and a household that has
	# never been named gets its own automatic slot.
	var first:bool=active_save_id.is_empty()
	var saved:bool=save_game("","Automatic save" if first else "")
	if saved and first:autosave_slot=active_save_id
	if saved:show_notice("Saved automatically.")

func _restore_world_state(value:Variant) -> void:
	if not value is Dictionary:return
	var state:Dictionary=value
	var position:Vector3=_saved_vector(state.get("player"),player.position)
	if household.journeys.is_empty():
		var cell:Vector2i=Vector2i(roundi(position.x*4),roundi(position.z*4))
		if not world.navigation.region.has_point(cell) or world.navigation.is_point_solid(cell):
			cell=world.nearest_free(position)
			position=Vector3(cell.x*.25,.16,cell.y*.25)
		position.y=.16
	player.position=position
	player.rotation.y=_saved_number(state.get("player_rotation"),0.0,-1000.0,1000.0)
	var target:Vector3=_saved_vector(state.get("camera"),world.camera_target)
	world.camera_target=Vector3(clampf(target.x,LifeBuildingState.lot().position.x+3,LifeBuildingState.lot().end.x-3),clampf(target.y,-2,5),clampf(target.z,LifeBuildingState.lot().position.y+3,LifeBuildingState.lot().end.y-3))
	world.camera_angle=_saved_number(state.get("angle"),world.camera_angle,-1000.0,1000.0)
	world.camera_elevation=_saved_number(state.get("elevation"),world.camera_elevation,LifeWorld.CAMERA_MIN_PITCH,LifeWorld.CAMERA_MAX_PITCH)
	world.camera.size=_saved_number(state.get("zoom"),world.camera.size,LifeWorld.CAMERA_MIN_ZOOM,LifeWorld.CAMERA_MAX_ZOOM)
	selected_lot=int(_saved_number(state.get("lot"),float(selected_lot),0.0,2.0))
	var saved_floor:Variant=state.get("floor",floor_color)
	if world.construction.building_state.is_empty():
		if saved_floor is String and _valid_hex_color(saved_floor):_apply_floor_color(saved_floor)
		else:_apply_floor_color(floor_color)
	elif saved_floor is String and _valid_hex_color(saved_floor):
		# Canonical slabs already carry their own finishes; restore only the
		# remembered ground-floor choice used by Build and the next save.
		floor_color=saved_floor
	if state.get("cutaway") is bool:world.set_cutaway(state.cutaway)
	if not household.journeys.is_empty():world.set_view_level(int(state.get("view_level",maxi(0,world.point_level(player.position)))))
	if state.get("sound") is bool:set_sound(state.sound)
	if state.get("music") is bool:set_music(state.music)
	# The autosave interval is a player setting, so it rides the same record the
	# sound and music choices do. An older save carries no key and keeps the
	# default; JSON hands the number back as a float, and a key outside the
	# offered choices is ignored rather than adopted.
	if state.has("autosave_minutes"):
		var restored:int=int(_saved_number(state.get("autosave_minutes"),float(AUTOSAVE_DEFAULT_MINUTES),0.0,1000000.0))
		if restored in AUTOSAVE_CHOICES:autosave_minutes=restored
	world.update_camera()

## Buy home insurance for the house the household lives in. It is one purchase
## whichever screen asks for it — the phone or the property panel — so both write
## through to the house's own record and cannot disagree about what is covered.
func buy_home_insurance(policy_id: String = "home") -> Dictionary:
	# A household with no property record at all keeps the sim's own policy, so
	# this still works for a household that predates the property system.
	var house_id: String = Properties.active(properties)
	if house_id.is_empty() or not Properties.owns(properties, house_id):
		return household.buy_insurance(policy_id)
	var bought: Dictionary = Properties.buy_policy(properties, house_id, policy_id, household.funds)
	if not bool(bought.ok):
		return {"ok": false, "error": str(bought.error)}
	properties = bought.state
	household.set_funds(int(bought.funds))
	_apply_property_insurance()
	return {"ok": true, "premium": int(bought.cost), "label": str(LifeSim.INSURANCE_POLICIES.get(policy_id, {}).get("label", "Home insurance"))}


## Give up the cover on the house the household lives in.
func cancel_home_insurance() -> Dictionary:
	var house_id: String = Properties.active(properties)
	if house_id.is_empty() or not Properties.owns(properties, house_id):
		return household.cancel_insurance()
	var result: Dictionary = Properties.cancel_policy(properties, house_id)
	if not bool(result.ok):
		return {"ok": false, "error": str(result.error)}
	properties = result.state
	_apply_property_insurance()
	return {"ok": true}


## Keep the property record in step with cover bought through the phone, so the
## two never disagree about what the house carries.
func _on_insurance_changed(policy_id: String) -> void:
	var house_id: String = Properties.active(properties)
	if house_id.is_empty() or not Properties.owns(properties, house_id):
		return
	if properties.houses[house_id].get("policy", "") == policy_id:
		return
	properties.houses[house_id]["policy"] = policy_id


## Apply the live home's own policy to the household's sims. A house carries its
## own cover, so moving into a house that is insured — or out of one that is —
## changes what a break-in there costs, and moving into an uninsured house really
## leaves the household uncovered.
##
## A household that has never recorded a property keeps whatever policy its sims
## hold, because the phone's own insurance purchase predates the property system
## and a load must not quietly cancel cover the player bought. Once the household
## owns the house it lives in, that house's record is the final word — and the
## phone writes through to it, so the two can never disagree.
func _apply_property_insurance() -> void:
	var house_id:String=Properties.active(properties)
	if house_id.is_empty() or not Properties.owns(properties,house_id):
		return
	var policy_id:String=str(Properties.policy(properties,house_id).get("id",""))
	for member:Dictionary in household.members:
		member.sim.insurance_policy_id=policy_id
	household._sync_bill_mirror()


## The property record as it should be saved: the house being lived in is
## updated with the live layout and land first, so moving away and back returns
## to the same house on the same plot with the same furnishings.
func _properties_for_save() -> Dictionary:
	var record:Dictionary=properties.duplicate(true)
	var lived:String=str(record.get("active",""))
	if not lived.is_empty() and record.get("houses",{}).has(lived) and current_venue=="home":
		record.houses[lived]["layout"]=home_layout.duplicate(true)
		record.houses[lived]["land"]=LifeBuildingState.land.duplicate(true)
	return record


func _restore_properties(value:Variant) -> void:
	properties=Properties.from_save(value)
	_apply_property_insurance()


## Open the property panel from the house menu.
func _property_panel_available() -> bool:
	return mode=="live" and current_venue=="home" and not residents.home_visit.active()


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
	var visit_error:String=LifeHomeVisit.validate_saved(read_result.data)
	if not visit_error.is_empty():show_notice(visit_error);return
	if read_result.data.has("journeys"):
		var prepared:Dictionary=_prepare_loaded_world(read_result.data)
		if not bool(prepared.ok):show_notice(str(prepared.error));return
		_adopt_loaded_world(prepared,slot_id,str(read_result.get("name","")))
		return
	var legacy_guest_error:String=_legacy_visit_error(read_result.data)
	if not legacy_guest_error.is_empty():show_notice(legacy_guest_error);return
	loading_game=true
	load_epoch+=1
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
		if LifeNeighborhood.has(place):
			current_venue=place
			for member:Dictionary in household.members:member.sim.visited_venue="" if place=="home" else place
		home_layout=_safe_layout(saved_world.get("home_layout",[]))
		_restore_properties(saved_world.get("properties"))
		var saved_venues:Variant=saved_world.get("venue_layouts",{})
		if saved_venues is Dictionary:
			for key:String in saved_venues:
				if key in LifeNeighborhood.PLACES and key!="home":venue_layouts[key]=_safe_layout(saved_venues[key])
	residents.restore(saved_world.get("residents",{}) if saved_world is Dictionary else {})
	bound_member_id=household.selected_id()
	household_profiles=[]
	for member:Dictionary in household.members:household_profiles.append(member.sim.character.duplicate(true))
	creator_index=household.selected_index
	profile=household_profiles[creator_index]
	floor_color="cfa97e"
	setup_live(result.world)
	if not household.journeys.is_empty():
		_restore_journeys()
	else:
		loading_game=false
		_refresh_sim_targets(true,false)
		_restore_resource_waits()
	loading_game=false
	meal_flow.sync_oven_presentations()
	residents.home_visit.meal.present(true)
	meal_flow.sync_world(false)
	_reconstruct_paused_cooking()
	_reconstruct_paused_rest()
	_sync_actor_sound()
	show_notice("Welcome back, %s." % sim.character.name)

func _legacy_visit_error(data:Dictionary) -> String:
	var found:Variant=LifeHomeVisit.saved_visit(data)
	if found==null or found.value.visit.is_empty():return ""
	# Legacy household loads retain their original format. Validate the guest
	# against an isolated real lot and the very same post-snap body positions
	# before the existing load path can mutate the current household.
	var candidate=get_script().new()
	candidate.loading_game=true;candidate.mode="live";candidate.current_venue="home"
	candidate.household=LifeHousehold.new();candidate.add_child(candidate.household)
	var checked:Dictionary=candidate.household.restore_state(data)
	if not bool(checked.ok):candidate.free();return str(checked.error)
	candidate.sim=candidate.household.selected();candidate.bound_member_id=candidate.household.selected_id()
	var viewport:=SubViewport.new();viewport.own_world_3d=true;viewport.size=Vector2i(2,2)
	viewport.render_target_update_mode=SubViewport.UPDATE_DISABLED;add_child(viewport)
	candidate.world=LifeWorld.new();viewport.add_child(candidate.world)
	candidate.world.set_process(false);candidate.world.set_process_unhandled_input(false)
	candidate.world.create_home(checked.world)
	if not candidate.world.last_layout_error.is_empty():
		var error:String=candidate.world.last_layout_error;viewport.free();candidate.free();return error
	candidate.traversal=LifeTraversal.new(candidate)
	candidate.residents=LifeResidents.new(candidate)
	candidate.residents.restore(found.residents)
	for index:int in candidate.household.members.size():
		var member:Dictionary=candidate.household.members[index]
		var saved:Dictionary=member.sim.character.get("world_state",{})
		var point:Vector3=_saved_vector(saved.get("player"),Vector3(-.7+(index%2)*.65,.16,2.8+(index/2)*.48))
		var cell:=Vector2i(roundi(point.x*4),roundi(point.z*4))
		if not candidate.world.navigation.region.has_point(cell) or candidate.world.navigation.is_point_solid(cell):
			cell=candidate.world.nearest_free(point);point=Vector3(cell.x*.25,.16,cell.y*.25)
		point.y=.16
		candidate.spawn_actor(str(member.id),member.sim.character,point)
		candidate.motion_states[str(member.id)]=candidate._empty_motion()
		var away:Dictionary=member.sim.get_away_state()
		candidate.world.set_actor_away(str(member.id),str(away.get("phase",""))=="away",not away.is_empty())
	candidate.residents.attach("home")
	candidate.meal_flow=LifeMealFlow.new();candidate.meal_flow.app=candidate;candidate.add_child(candidate.meal_flow)
	candidate.meal_flow.sync_world(false)
	var error:String=candidate.residents.home_visit.physical_error()
	if error.is_empty():candidate.residents.home_visit.meal.present(true)
	viewport.free();candidate.free()
	return error

func _prepare_loaded_world(data:Dictionary) -> Dictionary:
	var visit_error:String=LifeHomeVisit.validate_saved(data)
	if not visit_error.is_empty():return {"ok":false,"error":visit_error}
	# Use the same controller/service implementation against an isolated world.
	# Its root remains off-tree so _ready cannot create menus or start a game.
	# Only the viewport/world enter the tree to provide real skeleton transforms.
	var candidate=get_script().new()
	candidate.loading_game=true;candidate.mode="live";candidate.sound_enabled=false
	candidate.household=LifeHousehold.new()
	candidate.add_child(candidate.household)
	candidate.household_flow=LifeHouseholdFlow.new(candidate);candidate.add_child(candidate.household_flow)
	# The extras are validated and restored through the same provider the live
	# household uses, so a load cannot silently drop the household's books or bins.
	candidate.household.extras_provider=candidate.household_flow.get_state
	candidate.household.extras_restore_provider=candidate.household_flow.restore
	var checked:Dictionary=candidate.household.restore_state(data)
	if not bool(checked.ok):candidate.free();return checked
	candidate.sim=candidate.household.selected();candidate.bound_member_id=candidate.household.selected_id()
	var context:Dictionary=candidate.sim.character.world_state
	candidate.current_venue=str(context.get("venue","home"))
	candidate.home_layout=context.get("home_layout",[]).duplicate(true)
	candidate.venue_layouts=context.get("venue_layouts",{}).duplicate(true)
	var viewport:=SubViewport.new();viewport.own_world_3d=true;viewport.size=Vector2i(2,2)
	viewport.render_target_update_mode=SubViewport.UPDATE_DISABLED
	add_child(viewport)
	candidate.world=LifeWorld.new();viewport.add_child(candidate.world)
	candidate.world.set_process(false);candidate.world.set_process_unhandled_input(false)
	if candidate.current_venue=="home":candidate.world.create_home(checked.world)
	elif candidate.current_venue in LifeNeighborhood.RESIDENT_HOMES:candidate.world.create_resident_home(candidate.current_venue,checked.world)
	else:candidate.world.create_public_venue(candidate.current_venue,checked.world)
	if not candidate.world.last_layout_error.is_empty():
		var error:String=candidate.world.last_layout_error
		viewport.free();candidate.free();return {"ok":false,"error":error}
	candidate.residents=LifeResidents.new(candidate)
	candidate.residents.restore(context.get("residents",{}))
	candidate.traversal=LifeTraversal.new(candidate)
	candidate.meal_flow=LifeMealFlow.new();candidate.meal_flow.app=candidate;candidate.add_child(candidate.meal_flow)
	candidate.sanitation_flow=LifeSanitationFlow.new();candidate.sanitation_flow.app=candidate;candidate.add_child(candidate.sanitation_flow)
	for member:Dictionary in candidate.household.members:
		var id:String=str(member.id)
		candidate.spawn_actor(id,member.sim.character,LifeJourneyState.vector(data.journeys.members[id].position))
		candidate.motion_states[id]=candidate._empty_motion()
		var away:Dictionary=member.sim.get_away_state()
		candidate.world.set_actor_away(id,str(away.get("phase",""))=="away",not away.is_empty())
	candidate.residents.attach(candidate.current_venue)
	candidate._bind_member(candidate.household.selected_id())
	# The weekly van's obstacle is part of the walkable graph, so the candidate
	# must present and sync it before any route is restored: `_sync_food_truck`
	# rebuilds navigation when the van's presence changes, and a rebuild after
	# restore bumps the graph generation and orphans every restored route with it
	# (the next live frame then re-plans a donor and mints a new identity). Doing
	# it here keeps the candidate's graph and routes on one generation. The
	# service is the controller's own, which `_ready` has not yet created
	# off-tree, so the candidate makes its own.
	candidate.food_truck=LifeFoodTruck.new(candidate)
	candidate.add_child(candidate.food_truck)
	candidate._sync_food_truck()
	var restored:Dictionary=candidate._restore_journeys()
	if not bool(restored.ok):viewport.free();candidate.free();return restored
	var guest_error:String=candidate.residents.home_visit.physical_error()
	if not guest_error.is_empty():viewport.free();candidate.free();return {"ok":false,"error":guest_error}
	candidate.residents.home_visit.meal.present(true)
	candidate.meal_flow.sync_world(false)
	candidate._reconstruct_paused_cooking()
	candidate._reconstruct_paused_rest()
	return {"ok":true,"candidate":candidate,"viewport":viewport,"truck_parked":candidate._truck_parked,"truck_seen_day":candidate._truck_seen_day}

func _adopt_loaded_world(prepared:Dictionary,slot_id:String,title:String="") -> void:
	var candidate:Node=prepared.candidate
	var old_world:LifeWorld=world;var old_household:LifeHousehold=household;var old_meal_flow:LifeMealFlow=meal_flow;var old_sanitation_flow:LifeSanitationFlow=sanitation_flow
	var old_household_flow:LifeHouseholdFlow=household_flow
	# Every fallible layout, route and actual pose operation finished above.
	# Commit the prepared nodes/services together, then retire the old world.
	loading_game=true;load_epoch+=1
	world=candidate.world;household=candidate.household
	world.reparent(self,false);household.reparent(self,false)
	traversal=candidate.traversal;traversal.app=self
	residents=candidate.residents;residents.app=self
	# The candidate presented the weekly van and synced its obstacle into the
	# graph it restored routes against, so the adopting controller takes both the
	# service and its parked state: rebuilding the same graph here would bump the
	# generation and orphan every route that was just restored.
	if is_instance_valid(candidate.food_truck):
		if is_instance_valid(food_truck):food_truck.queue_free()
		food_truck=candidate.food_truck
		food_truck.app=self
		food_truck.reparent(self,false)
	_truck_parked=bool(prepared.get("truck_parked",false))
	_truck_seen_day=int(prepared.get("truck_seen_day",-1))
	meal_flow=candidate.meal_flow;meal_flow.app=self;meal_flow.reparent(self,false)
	sanitation_flow=candidate.sanitation_flow;sanitation_flow.app=self;sanitation_flow.reparent(self,false)
	household_flow=candidate.household_flow;household_flow.app=self;household_flow.reparent(self,false)
	motion_states=candidate.motion_states
	current_venue=candidate.current_venue;home_layout=candidate.home_layout;venue_layouts=candidate.venue_layouts
	_connect_live_nodes()
	# The loaded household bills against the world it just adopted, so the
	# provider must point at this controller, not the candidate that built it.
	household.set_home_value_provider(home_value)
	sim=household.selected();bound_member_id=household.selected_id();_bind_member(bound_member_id)
	has_active_game=true;active_save_id=slot_id;active_save_name=title
	household_profiles=[]
	for member:Dictionary in household.members:household_profiles.append(member.sim.character.duplicate(true))
	creator_index=household.selected_index;profile=household_profiles[creator_index]
	close_overlay(false);pending_move.clear();build_undo.clear();away_phases.clear();mode="live"
	if is_instance_valid(stage):stage.visible=false
	world.live_enabled=true;world.set_build(false);world.set_process(true);world.set_process_unhandled_input(true)
	world.camera.current=true
	_restore_world_state(sim.character.world_state)
	player.set_selected(true)
	prepared.viewport.free();candidate.free()
	stage=null;preview=null
	old_world.visible=false;old_world.queue_free();old_household.queue_free();old_meal_flow.queue_free();old_sanitation_flow.queue_free();old_household_flow.queue_free()
	loading_game=false;_sync_actor_sound();sync_pets();sync_post();draw_live()
	show_notice("Welcome back, %s." % sim.character.name)

func _restore_journeys() -> Dictionary:
	var restored:Dictionary=traversal.restore(household.journeys)
	if not bool(restored.ok):return restored
	# Build food picking/presentation without repairing the ledger or beginning
	# an action. All body positions and stair owners are already installed.
	meal_flow.sync_world(false)
	sanitation_flow.sync_world(false)
	household.register_targets(world.simulation_targets(),false)
	for member:Dictionary in household.members:
		var id:String=str(member.id);var motion:Dictionary=motion_states[id]
		var current:Dictionary=member.sim.get_current_action()
		var resident_id:String=str(current.get("target_id",""))
		if str(current.get("id","")) in LifeSim.SOCIAL_ACTIONS and LifeResidents.PEOPLE.has(resident_id) and str(current.get("phase","")) in ["approach","active"] and not residents.present(resident_id):
			return {"ok":false,"error":"A saved conversation refers to a neighbor who has already gone home."}
		var saved:Dictionary=member.sim.character.world_state
		motion.pending=current
		motion.wait_started=float(saved.get("resource_wait_started",-1.0))
		motion.waiting=motion.wait_started>=0 and str(current.get("phase",""))=="approach"
		motion.wait_review=motion.wait_started
		if motion.waiting:
			# An arrived resource waiter has no saved movement. Its existing
			# body remains the reserved point until ordinary admission chooses
			# a new route; never reconstruct a path to the occupied action.
			var saved_motion:Dictionary=household.journeys.members[id].get("motion",{})
			motion.wait_destination=LifeJourneyState.vector(saved_motion.destination) if not saved_motion.is_empty() else world.actors[id].position
		motion.resume_active=bool(saved.get("resource_action_active",false)) and str(current.get("phase",""))=="approach"
		member.sim.meal_service=meal_flow
		member.sim.sanitation_service=sanitation_flow
		member.sim.household_service=household_flow
		if str(current.get("phase","")) in ["approach","active"] and str(current.get("id","")) in ["plant_wee","mop_puddle"]:
			var target_error:String=sanitation_flow.restore_action_error(id,current)
			if not target_error.is_empty():return {"ok":false,"error":"The saved sanitation activity cannot resume: "+target_error}
		if not current.is_empty() and str(current.phase)=="approach" and not traversal.active(id) and not motion.waiting and not member.sim.is_away():
			var built:Dictionary=traversal.request(id,current.target_position)
			if not bool(built.ok):return built
			motion.path=built.points;motion.index=0;motion.traversal=traversal.routes[id]
		meal_flow.present_actor(id)
	var occupied:Dictionary=traversal.validate_occupancy()
	if not bool(occupied.ok):return occupied
	var painted:Dictionary=traversal.reconstruct()
	if not bool(painted.ok):return painted
	_bind_member(household.selected_id())
	var courtesy_loaded:Dictionary=traversal.validate_current_floor_courtesy()
	if not bool(courtesy_loaded.ok):return courtesy_loaded
	meal_flow.sync_world(false)
	sanitation_flow.sync_world(false)
	sanitation_flow.reconstruct_actors()
	return {"ok":true}

func _reconstruct_paused_cooking() -> void:
	if mode!="build" and sim.speed>0:return
	var prior:String=bound_member_id
	_store_motion()
	for member:Dictionary in household.members:
		_bind_member(str(member.id))
		var was_cooking:bool=not player.cooking_presentation.is_empty()
		meal_flow.present_actor(str(member.id))
		var state:Dictionary=meal_flow.oven_presentation(str(member.id))
		if not player.has_method("reconstruct_cooking_pose") or (state.is_empty() and not was_cooking):continue
		var action:Dictionary=sim.get_current_action()
		if not state.is_empty() and player.position.distance_to(action.target_position)<.02:
			_update_activity_facing(0.0,action,"cook")
		else:player.clear_activity_anchor()
		player.reconstruct_cooking_pose()
	_bind_member(prior)

func _reconstruct_paused_rest() -> void:
	if household.speed>0:return
	var prior:String=bound_member_id
	for member:Dictionary in household.members:
		var current:Dictionary=member.sim.get_current_action()
		var action_id:String=str(current.get("id",""))
		if member.sim.speed>0 or member.sim.is_away() or str(current.get("phase",""))!="active" or action_id not in ["sleep","nap"]:continue
		_bind_member(str(member.id))
		_update_activity_facing(0.0,current,action_id)
		player.reconstruct_rest_pose(action_id)
	_bind_member(prior)

func _restore_resource_waits() -> void:
	var now:float=(household.day-1)*1440.0+household.minutes
	for member:Dictionary in household.members:
		var action:Dictionary=member.sim.get_current_action()
		var saved:Variant=member.sim.character.get("world_state",{})
		if not saved is Dictionary or action.is_empty() or str(action.phase)!="approach":continue
		if str(saved.get("waiting_action_id",""))!=str(action.id) or str(saved.get("waiting_target_id",""))!=str(action.target_id):continue
		var started:float=_saved_number(saved.get("resource_wait_started",-1.0),-1.0,-1.0,now)
		var was_active:bool=saved.get("resource_action_active",false) is bool and bool(saved.get("resource_action_active",false))
		if not saved.has("resource_action_active"):
			# Older saves already retain the paid flag after begin_current_action.
			# Preserve their unfinished occupant when no arrived wait was saved.
			was_active=started<0 and bool(action.get("paid",false))
		if started>=0 or was_active:
			var motion:Dictionary=motion_states[str(member.id)]
			motion["wait_started"]=started
			motion["resume_active"]=was_active
			motion["waiting"]=true
			motion["path"]=PackedVector3Array()
			motion["index"]=0
	_bind_member(household.selected_id())

func setup_audio() -> void:
	audio_player=AudioStreamPlayer.new();add_child(audio_player)
	if ResourceLoader.exists("res://assets/audio/soft_click.wav"):
		audio_player.stream=load("res://assets/audio/soft_click.wav")
	audio_player.volume_db=0
	chime_player=AudioStreamPlayer.new();add_child(chime_player)
	if ResourceLoader.exists("res://assets/audio/chime_pregnancy.wav"):
		chime_player.stream=load("res://assets/audio/chime_pregnancy.wav")
	chime_player.volume_db=0
	ambience_player=AudioStreamPlayer.new();add_child(ambience_player)
	if ResourceLoader.exists("res://assets/audio/ambience_garden.wav"):
		var stream:AudioStreamWAV=load("res://assets/audio/ambience_garden.wav").duplicate()
		stream.loop_mode=AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin=0
		stream.loop_end=int(stream.get_length()*stream.mix_rate)
		ambience_player.stream=stream
		ambience_player.volume_db=0
		ambience_player.play()
	setup_music()

## "Summit Dawn" is the game's own theme: a full-length forward loop with the
## file's quiet head and tail as the seam, so the join has nothing to click on.
## It is loaded from disk rather than through the importer for the same reason
## the voices are, so the music never waits on asset import to be heard.
func setup_music() -> void:
	music_player=AudioStreamPlayer.new()
	music_player.name="SummitDawn"
	add_child(music_player)
	var path:String="res://assets/audio/Summit Dawn.wav"
	if not FileAccess.file_exists(path) and not ResourceLoader.exists(path):return
	var stream:AudioStreamWAV=AudioStreamWAV.load_from_file(path) if FileAccess.file_exists(path) else load(path) as AudioStreamWAV
	if stream==null:return
	stream=stream.duplicate()
	stream.loop_mode=AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin=0
	stream.loop_end=int(stream.get_length()*stream.mix_rate)
	music_player.stream=stream
	music_player.volume_db=-8.0
	if sound_enabled and music_enabled:music_player.play()
	else:music_player.stream_paused=true

func set_sound(enabled:bool) -> void:
	sound_enabled=enabled
	if is_instance_valid(ambience_player):ambience_player.stream_paused=not enabled
	if not enabled and is_instance_valid(audio_player):audio_player.stop()
	if not enabled and is_instance_valid(chime_player):chime_player.stop()
	if is_instance_valid(music_player):
		music_player.stream_paused=not (enabled and music_enabled)
		if not enabled and music_player.playing:music_player.stop()
	_sync_actor_sound()

## The music switch is independent of the sound switch: the menu offers music on
## its own, so a household can keep life sounds while turning the theme off.
## Changing the setting takes effect immediately and rides the save.
func set_music(enabled:bool) -> void:
	music_enabled=enabled
	if not is_instance_valid(music_player):return
	if enabled and sound_enabled:
		music_player.stream_paused=false
		if not music_player.playing:music_player.play()
	else:
		music_player.stream_paused=true

func _sync_actor_sound() -> void:
	if not is_instance_valid(world):return
	var enabled:bool=sound_enabled and mode=="live" and is_instance_valid(sim) and sim.speed>0
	_sync_pet_sound()
	for actor:LifeActor in world.actors.values():
		if is_instance_valid(actor):actor.voice_enabled=enabled
	if is_instance_valid(preview):preview.voice_enabled=false

func play_click() -> void:
	if sound_enabled and audio_player and audio_player.stream:audio_player.play()

func quit_game() -> void:
	if is_queued_for_deletion():return
	LifeLog.info("LIFECYCLE", "Game quit requested")
	var tree:SceneTree=get_tree()
	queue_free()
	# Let the audio server release stopped playbacks before engine teardown.
	tree.create_timer(.2).timeout.connect(tree.quit,CONNECT_ONE_SHOT)

func _exit_tree() -> void:
	_set_studio_render_quality(false)
	for audio:AudioStreamPlayer in [audio_player,ambience_player,music_player]:
		if is_instance_valid(audio):
			audio.stream_paused=false
			audio.stop()
			audio.stream=null
	LifeLog.shutdown()

func _process(delta:float) -> void:
	elapsed+=delta
	if is_instance_valid(notice_card):
		notice_time-=delta
		if notice_time<.5:notice_card.modulate.a=clampf(notice_time*2,0,1)
		if notice_time<=0:notice_card.queue_free()
	if mode=="creator":
		if is_instance_valid(preview):preview.animate(delta,1,false,"")
		return
	if mode=="travel":residents.tick_trip(delta);return
	if mode not in ["live","build"]:return
	if mode=="live":
		_update_cover_beat(delta)
		residents.publish_targets()
		meal_flow.sync_world(household.speed>0)
		_sync_delivery_van()
		_store_motion()
		if household.speed>0:_reconcile_social_routes()
		var selected_id:String=household.selected_id()
		var autonomy_values:Dictionary={}
		for member:Dictionary in household.members:
			autonomy_values[member.id]=member.sim.autonomy
			if bool(motion_states.get(member.id,_empty_motion()).walk) or traversal.busy(str(member.id)):member.sim.autonomy=false
		var day_before:int=household.day
		household.tick(delta)
		# A new day is when the post could have something new in it, so the box is
		# refilled once per day rather than checked every frame.
		if household.day!=day_before:sync_post()
		sanitation_flow.sync_world()
		for member:Dictionary in household.members:member.sim.autonomy=autonomy_values[member.id]
		idle_space.update(delta)
		world.daylight(household.minutes)
		world.begin_activity_frame(household.speed<=0)
		var away_targets_changed:bool=false
		for member:Dictionary in household.members:
			_bind_member(member.id)
			away_targets_changed=_sync_away_presence() or away_targets_changed
			var moving:bool=_advance_away_movement(delta) if sim.is_away() else _advance_movement(delta)
			var action:Dictionary=sim.get_current_action()
			var action_id:String="" if action.is_empty() or action.phase!="active" else action.id
			if not str(action.get("cooperation_id","")).is_empty() and action_id.is_empty():
				var shared:Dictionary=household.cooperative_presentation(bound_member_id)
				if bool(shared.get("ready",false)) and str(shared.get("role",""))=="learner":action_id="homework_wait"
			meal_flow.present_actor(bound_member_id)
			_update_activity_facing(delta,action,action_id)
			# A wardrobe preview is the player's own working look. The ordinary
			# sync would overwrite it with the saved one on the next frame, so the
			# preview owns the actor until the panel is closed.
			if not player.has_meta("preview_profile") and LifeCharacterIdentity.wardrobe_fields(player.profile)!=LifeCharacterIdentity.wardrobe_fields(sim.character):
				player.apply_wardrobe(sim.character)
				if member.id==selected_id and not overlay_open:portrait_stale=true
			# A mother's bump grows with the household pregnancy clock.
			if is_instance_valid(player):
				var bump:float=-1.0
				if household.pregnancy_mother_id()==str(member.id):bump=household.pregnancy_progress()
				player.pregnancy_bump=bump if bump>=0.0 else 0.0
			player.animate(delta,float(sim.speed),moving,action_id)
			_store_motion()
		meal_flow.sync_world(household.speed>0)
		_bind_member(selected_id)
		_update_selection_marker(delta)
		if away_targets_changed:_refresh_sim_targets(false)
		residents.tick(delta)
		_tick_resident_contacts()
		traversal.courtesy.consider(traversal)
		_tick_pets(delta)
		_tick_food_truck()
		tick_autosave(delta)
		hud_refresh+=delta
		if hud_refresh>.25:hud_refresh=0;refresh_hud()
	if mode=="build":
		_update_selection_marker(delta)
		refresh_build_quote()
	if not overlay_open and not get_viewport().gui_get_focus_owner() is LineEdit:
		var pan=Vector2.ZERO
		if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP):pan.y-=1
		if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN):pan.y+=1
		if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):pan.x-=1
		if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):pan.x+=1
		if pan.length()>0:
			var side=Vector3(cos(world.camera_angle),0,-sin(world.camera_angle))
			var forward=Vector3(sin(world.camera_angle),0,cos(world.camera_angle))
			world.camera_target+=(side*pan.x+forward*pan.y)*delta*LifeWorld.CAMERA_PAN_SPEED
			world.camera_target.x=clampf(world.camera_target.x,LifeBuildingState.lot().position.x+3,LifeBuildingState.lot().end.x-3);world.camera_target.z=clampf(world.camera_target.z,LifeBuildingState.lot().position.y+3,LifeBuildingState.lot().end.y-3)
			world.update_camera()

func _advance_movement(delta:float) -> bool:
	if not is_instance_valid(player) or sim.speed<=0:return false
	if traversal.safety(bound_member_id):
		var moved:bool=_advance_path(delta)
		if not traversal.active(bound_member_id):
			var next:Dictionary=sim.get_current_action()
			if not next.is_empty():on_action_started(next)
			elif walk_only:_set_route(walk_destination)
			else:_clear_motion()
		return moved
	var current_social:Dictionary=sim.get_current_action()
	var guest_id:String=str(current_social.get("target_id",""))
	if str(current_social.get("id","")) in LifeSim.SOCIAL_ACTIONS and LifeResidents.PEOPLE.has(guest_id):
		if not residents.present(guest_id) or (residents.home_visit.owns(guest_id) and str(residents.home_visit.state.phase)=="leaving" and not residents.home_visit.social_allowed(guest_id,current_social)):
			cancel_current_action();show_notice("This neighbor is heading home. Catch up another time.");return false
	var current_arrival:Dictionary=sim.get_current_action()
	if str(current_arrival.get("id",""))=="arrive_home":return adoption_flow.advance_arrival(delta,current_arrival)
	if not walk_only and sim.action_queue.is_empty():
		# An idle Lifelet asked to step aside for somebody blocked on it keeps
		# that short walk; anything else idle releases its route.
		if traversal.making_way(bound_member_id):
			var aside:Dictionary=traversal.advance(bound_member_id,delta,sim.speed)
			return bool(aside.moving)
		_clear_motion();return false
	if waiting_for_target:
		var action:Dictionary=sim.get_current_action()
		# A waiter turned away by a full couch holds no place of its own, and it
		# claims every place so that it really conflicts and waits. A cushion that
		# has since freed must be re-claimed here, or the waiter would keep testing
		# against its own all-places claim and never sit down. A shared bed keeps
		# its own halved rule, where a partner may already share and a stranger
		# waits on the whole-bed claim, so it is left alone.
		if str(action.get("cooperation_id","")).is_empty() and str(action.get("seat_slot","")).is_empty() and not str(action.get("id","")) in LifeSim.SOCIAL_ACTIONS:
			var held:Dictionary=_find_item(str(action.get("target_id","")))
			if not held.is_empty() and world.seat_capacity(held)>1 and str(held.kind) not in world.SHARED_BEDS:
				var reserved:Vector3=action.target_position
				_assign_seat_slot(action,held)
				# No place was free after all, so leave the instruction exactly
				# as it was rather than moving a still-waiting Lifelet's target.
				if str(action.get("seat_slot","")).is_empty():action.target_position=reserved
		if _activity_available(action):
			# Keep the arrived reservation until the Lifelet has walked back
			# from their queue position. New arrivals cannot steal this turn.
			var destination:Vector3=action.target_position
			if world.construction.building_state.is_empty():
				var cell:Vector2i=world.nearest_free(destination)
				destination=Vector3(cell.x*.25,.16,cell.y*.25)
			if player.position.distance_to(destination)<.01:
				waiting_for_target=false
				wait_started=-1.0
				wait_destination=Vector3.INF
				resume_activity=false
				path.clear();path_index=0
				household.begin_action(bound_member_id)
				return false
			if wait_destination!=destination:
				_set_route(destination)
				wait_destination=destination
		else:
			_reconsider_waiting_activity()
			if not waiting_for_target:return false
			if not wait_destination.is_finite() or wait_destination.distance_to(action.target_position)<.1:
				_route_to_wait_position(action)
		return _advance_path(delta)
	if _queue_near_busy_activity():return _advance_path(delta)
	var was_moving:bool=_advance_path(delta)
	if was_moving and path_index>=path.size():
		path.clear();path_index=0
		var should_begin:bool=not walk_only
		walk_only=false
		if should_begin:
			if wait_started<0:wait_started=(household.day-1)*1440.0+household.minutes
			if _activity_available(sim.get_current_action()):
				wait_started=-1.0
				household.begin_action(bound_member_id)
			else:
				waiting_for_target=true
				_route_to_wait_position(sim.get_current_action())
	return was_moving

func _queue_near_busy_activity()->bool:
	# The occupied activity anchor cannot also hold the arriving body. Enter
	# its queue from clear nearby floor with supported access to its anchor or waiter.
	if walk_only or resume_activity or world.construction.building_state.is_empty():return false
	var action:Dictionary=sim.get_current_action()
	if str(action.get("phase",""))!="approach" or not str(action.get("cooperation_id","")).is_empty():return false
	if str(action.get("id","")) in LifeSim.SOCIAL_ACTIONS or _find_item(str(action.get("target_id",""))).is_empty():return false
	if traversal.busy(bound_member_id) or traversal.safety(bound_member_id):return false
	if traversal.courtesy.preserve_request(traversal,bound_member_id,action.target_position):return false
	var destination:Vector3=action.target_position
	var level:int=world.point_level(player.position)
	if level<0 or level!=world.point_level(destination) or not traversal._free(bound_member_id,player.position):return false
	var near_anchor:bool=player.position.distance_to(destination)<=1.0 and (world.lot_navigation.segment_clear(level,player.position,destination) or _near_active_resource_owner(action,level))
	if not near_anchor and not _near_arrived_resource_waiter(action,level):return false
	if _activity_available(action):return false
	waiting_for_target=true
	wait_started=(household.day-1)*1440.0+household.minutes
	wait_review=-1.0
	wait_destination=Vector3.INF
	if near_anchor:_route_to_wait_position(action)
	else:
		# Joining behind a reached waiter owns this clear physical queue point.
		wait_destination=player.position
		traversal.cancel(bound_member_id);path.clear();path_index=0
	return true

func _near_arrived_resource_waiter(action:Dictionary,level:int)->bool:
	var wanted:Array[String]=_activity_resources(action)
	var courtesy_owner:String=traversal.courtesy.owner(traversal)
	for member:Dictionary in household.members:
		var id:String=str(member.id)
		if id==bound_member_id or not world.actors.has(id):continue
		var motion:Dictionary=motion_states.get(id,_empty_motion())
		if not bool(motion.waiting) or float(motion.wait_started)<0 or bool(motion.walk) or bool(motion.resume_active):continue
		var other:Dictionary=member.sim.get_current_action()
		if str(other.get("phase",""))!="approach" or not is_same(other,motion.pending) or not str(other.get("cooperation_id","")).is_empty() or str(other.get("id","")) in LifeSim.SOCIAL_ACTIONS:continue
		if traversal.busy(id) or traversal.safety(id):continue
		if not courtesy_owner.is_empty() and id in [courtesy_owner,str(traversal.routes[courtesy_owner].courtesy.beneficiary_id)]:continue
		var actor:LifeActor=world.actors[id];var reserved:Vector3=motion.wait_destination
		if not actor.visible or not reserved.is_finite() or actor.position.distance_to(reserved)>=.01 or world.point_level(actor.position)!=level or player.position.distance_to(actor.position)>1.0:continue
		var shared:bool=false
		var held:Array[String]=_activity_resources(other)
		for resource:String in wanted:
			if not resource.begins_with("standing:") and held.has(resource):shared=true;break
		if not shared:continue
		if _near_resource_body(id,level):return true
	return false

func _near_active_resource_owner(action:Dictionary,level:int)->bool:
	var wanted:Array[String]=_activity_resources(action)
	var courtesy_owner:String=traversal.courtesy.owner(traversal)
	for member:Dictionary in household.members:
		var id:String=str(member.id)
		if id==bound_member_id or not world.actors.has(id):continue
		var other:Dictionary=member.sim.get_current_action()
		if str(other.get("phase",""))!="active" or not bool(other.get("paid",false)) or not str(other.get("cooperation_id","")).is_empty() or str(other.get("id","")) in LifeSim.SOCIAL_ACTIONS:continue
		if traversal.busy(id) or traversal.safety(id):continue
		if not courtesy_owner.is_empty() and id in [courtesy_owner,str(traversal.routes[courtesy_owner].courtesy.beneficiary_id)]:continue
		var actor:LifeActor=world.actors[id]
		if not actor.visible or actor.position!=action.target_position or world.point_level(actor.position)!=level or player.position.distance_to(actor.position)>1.0:continue
		var shared:bool=false
		for resource:String in _activity_resources(other):
			if not resource.begins_with("standing:") and wanted.has(resource):shared=true;break
		if shared and _near_resource_body(id,level):return true
	return false

func _near_resource_body(id:String,level:int)->bool:
	# Nearby access can bend around a corner; only its owner's endpoint is
	# exempt. This proves queue proximity, never traversal or action arrival.
	var actor:LifeActor=world.actors[id]
	var occupied:Array[Vector3]=traversal._occupied(bound_member_id)
	occupied.erase(actor.position) # Exempt only this peer's occupied endpoint.
	for moving_id:String in traversal.routes:
		if moving_id==bound_member_id:continue
		var stair_wait:Vector3=traversal.routes[moving_id].wait
		if stair_wait.is_finite():occupied.append(stair_wait)
	var reserved_body:bool=false
	for queued:Dictionary in household.members:
		var queued_id:String=str(queued.id)
		if queued_id in [bound_member_id,id]:continue
		var waiting:Dictionary=motion_states.get(queued_id,_empty_motion())
		var point:Vector3=waiting.wait_destination
		if bool(waiting.waiting) and point.is_finite():
			occupied.append(point)
			if traversal._same_floor(player.position,point) and player.position.distance_to(point)<.8:reserved_body=true
	if reserved_body:return false
	var witness:Dictionary=world.lot_navigation.route_avoiding(LifeLotNavigation.floor_location(level,player.position),LifeLotNavigation.floor_location(level,actor.position),occupied,LifeTraversal.ROUTE_CLEARANCE)
	return bool(witness.ok) and float(witness.distance)<=1.0 and witness.segments.all(func(leg:Dictionary)->bool:return str(leg.kind)=="floor" and int(leg.level)==level)

func _set_route(destination:Vector3) -> bool:
	path_index=0
	if not world.construction.building_state.is_empty():
		var result:Dictionary=traversal.request(bound_member_id,destination)
		path=result.points if bool(result.ok) else PackedVector3Array()
		return bool(result.ok)
	path=world.path_to(player.position,destination)
	return not path.is_empty()

func _advance_path(delta:float) -> bool:
	if traversal.active(bound_member_id):
		var result:Dictionary=traversal.advance(bound_member_id,delta,sim.speed)
		if bool(result.finished):path_index=path.size()
		if not str(result.error).is_empty():
			show_notice(str(result.error))
			# A walk that stays blocked by bodies is abandoned for autonomous
			# actions, and the Lifelet chooses again shortly rather than in
			# fifteen minutes; a player's own instruction keeps its notice.
			var current:Dictionary=sim.get_current_action()
			if str(result.error)==traversal.STANDOFF_ERROR:
				if not current.is_empty() and bool(current.get("autonomous",false)):
					sim.retry_autonomy_soon()
					_cancel_blocked_action.call_deferred(route_generation,current,bound_member_id,load_epoch)
				elif current.is_empty() and walk_only:
					# A plain walk that cannot get through is dropped, so the Lifelet's
					# autonomy is not left suspended behind an unfinished stroll.
					walk_only=false;_clear_motion()
				elif not current.is_empty():
					# A player's instruction or an arrival tries a fresh route from here
					# instead of standing on a dead one.
					traversal.cancel(bound_member_id)
					_set_route(current.target_position)
		return bool(result.moving) or bool(result.finished)
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
	return was_moving

func _route_to_wait_position(action:Dictionary) -> void:
	var origin:Vector3=action.target_position
	for radius:int in range(1,7):
		for x:int in range(-radius,radius+1):
			for z:int in range(-radius,radius+1):
				if absi(x)!=radius and absi(z)!=radius:continue
				var destination:Vector3=origin+Vector3(x*.75,0,z*.75)
				if not _wait_position_clear(destination):continue
				var route:PackedVector3Array=world.path_to(player.position,destination)
				if route.is_empty() or route[-1].distance_to(destination)>.1:continue
				wait_destination=destination
				_set_route(destination)
				return
	# A completely packed room keeps its existing position and reservation;
	# autonomy can still reconsider another activity after the bounded wait.
	wait_destination=player.position
	traversal.cancel(bound_member_id)
	path.clear();path_index=0

func _wait_position_clear(destination:Vector3,arrived_owner:bool=false) -> bool:
	arrived_owner=arrived_owner and destination==player.position and not world.construction.building_state.is_empty()
	if not world.construction.building_state.is_empty():
		if not traversal._free(bound_member_id,destination):return false
	for offset:Vector2 in [] if arrived_owner else [Vector2.ZERO,Vector2(.25,0),Vector2(-.25,0),Vector2(0,.25),Vector2(0,-.25)]:
		if not world.construction.building_state.is_empty():
			if not world.lot_navigation.point_clear(world.point_level(destination),destination+Vector3(offset.x,0,offset.y)):return false
			continue
		var cell:Vector2i=Vector2i(roundi((destination.x+offset.x)*4),roundi((destination.z+offset.y)*4))
		if not world.navigation.region.has_point(cell) or world.navigation.is_point_solid(cell):return false
	for id:String in world.actors:
		if id==bound_member_id:continue
		if world.actors[id].position.distance_to(destination)<(LifeTraversal.BODY_GAP if arrived_owner else .8):return false
	for member:Dictionary in household.members:
		var current:Dictionary=member.sim.get_current_action()
		if not current.is_empty() and destination.distance_to(current.target_position)<.8:return false
		if str(member.id)==bound_member_id:continue
		var motion:Dictionary=motion_states.get(str(member.id),_empty_motion())
		var reserved:Vector3=motion.get("wait_destination",Vector3.INF)
		var retained_peer:bool=arrived_owner and world.actors.has(str(member.id)) and world.actors[str(member.id)].position==reserved
		if bool(motion.waiting) and reserved.is_finite() and reserved.distance_to(destination)<(LifeTraversal.BODY_GAP if retained_peer else .8):return false
	return true

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
	if not sim.reconsider_waiting_autonomy(blocked,waited):
		motion_states[bound_member_id]=prior
		_bind_member(bound_member_id)
		wait_review=now+15.0

func _clear_pointer_drags() -> void:
	camera_pan_button=MOUSE_BUTTON_NONE
	camera_drag=false
	creator_drag=false

func _notification(what:int) -> void:
	if what==NOTIFICATION_WM_WINDOW_FOCUS_OUT:_clear_pointer_drags()
	elif what==NOTIFICATION_WM_CLOSE_REQUEST:quit_game()

func _camera_input_allowed() -> bool:
	var focus=get_viewport().gui_get_focus_owner()
	return mode in ["live","build"] and not overlay_open and not (focus is LineEdit or focus is TextEdit)

func _pan_camera_drag(position:Vector2,relative:Vector2) -> void:
	var plane=Plane(Vector3.UP,world.camera_target.y)
	var previous:Variant=plane.intersects_ray(world.camera.project_ray_origin(position-relative),world.camera.project_ray_normal(position-relative))
	var current:Variant=plane.intersects_ray(world.camera.project_ray_origin(position),world.camera.project_ray_normal(position))
	if not previous is Vector3 or not current is Vector3:return
	var movement:Vector3=previous-current
	world.camera_target.x=clampf(world.camera_target.x+movement.x,-16,16)
	world.camera_target.z=clampf(world.camera_target.z+movement.z,-12,12)
	world.update_camera()

func _input(event:InputEvent) -> void:
	# The town map pans and zooms inside its own panel. These are observed here,
	# before the GUI layer, because a press that lands on a pin belongs to that
	# pin: only a real drag is claimed, and then its release is consumed so a pan
	# never also selects the place the drag started on.
	if overlay_open and _neighborhood_gesture(event):return
	# A drag that starts in the world keeps its release even over a HUD control.
	if event is InputEventMouseButton and not event.pressed:
		if event.button_index==camera_pan_button:
			camera_pan_button=MOUSE_BUTTON_NONE
			get_viewport().set_input_as_handled()
		if event.button_index==MOUSE_BUTTON_RIGHT:camera_drag=false
		if event.button_index==MOUSE_BUTTON_LEFT:creator_drag=false
	if event is InputEventMouseMotion and camera_pan_button!=MOUSE_BUTTON_NONE:
		var held_mask:int=1 << (camera_pan_button-1)
		if not _camera_input_allowed() or not (event.button_mask & held_mask):
			_clear_pointer_drags()
			return
		_pan_camera_drag(event.position,event.relative)
		get_viewport().set_input_as_handled()

func _unhandled_input(event:InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode==KEY_ESCAPE:
			if overlay_open:close_overlay()
			elif mode=="build" and _has_placement_tool():
				cancel_placement()
				# The paint row stands in for the catalogue strip while a car is
				# being placed, so cancelling has to put the strip back.
				if mode=="build":draw_live()
			elif mode in ["live","build"]:show_menu()
			get_viewport().set_input_as_handled()
			return
		if get_viewport().gui_get_focus_owner() is LineEdit:return
		if overlay_open:return
		if mode in ["live","build"]:
			match event.keycode:
				KEY_PAGEUP:
					if mode=="live" and current_venue=="home":set_live_view_level(1);get_viewport().set_input_as_handled()
				KEY_PAGEDOWN:
					if mode=="live" and current_venue=="home":set_live_view_level(0);get_viewport().set_input_as_handled()
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
		if event.pressed and _camera_input_allowed():
			if event.button_index==MOUSE_BUTTON_MIDDLE or (event.shift_pressed and event.button_index in [MOUSE_BUTTON_LEFT,MOUSE_BUTTON_RIGHT]):
				camera_pan_button=event.button_index
				camera_drag=false
				get_viewport().set_input_as_handled()
				return
		if event.button_index==MOUSE_BUTTON_RIGHT:camera_drag=event.pressed;last_mouse=event.position
		if mode=="creator" and event.button_index==MOUSE_BUTTON_LEFT:
			creator_drag=event.pressed;last_mouse=event.position
		if mode in ["live","build"]:
			if event.button_index==MOUSE_BUTTON_WHEEL_UP:world.camera.size=maxf(world.camera.size-LifeWorld.CAMERA_WHEEL_STEP,LifeWorld.CAMERA_MIN_ZOOM)
			if event.button_index==MOUSE_BUTTON_WHEEL_DOWN:world.camera.size=minf(world.camera.size+LifeWorld.CAMERA_WHEEL_STEP,LifeWorld.CAMERA_MAX_ZOOM)
			if event.button_index==MOUSE_BUTTON_LEFT and event.pressed:world.pick(event.position)
	if event is InputEventMouseMotion:
		if mode=="creator" and creator_drag:
			creator_spin+=event.relative.x*.012;preview.rotation.y=creator_spin
		elif camera_drag and mode in ["live","build"]:
			if not (event.button_mask & MOUSE_BUTTON_MASK_RIGHT):
				camera_drag=false
				return
			world.camera_angle-=event.relative.x*LifeWorld.CAMERA_ORBIT_PER_PIXEL
			world.camera_elevation=clampf(world.camera_elevation+event.relative.y*LifeWorld.CAMERA_PITCH_PER_PIXEL,LifeWorld.CAMERA_MIN_PITCH,LifeWorld.CAMERA_MAX_PITCH)
			world.update_camera()

func _has_placement_tool() -> bool:
	return not world.placement_kind.is_empty() or (is_instance_valid(world.construction) and not world.construction.tool.is_empty())

func _update_activity_facing(delta:float,action:Dictionary,action_id:String) -> void:
	if player.has_method("clear_activity_anchor"):player.clear_activity_anchor()
	if action_id.is_empty():return
	if action_id=="eat_meal":
		var meal_anchor:Dictionary=meal_flow.eating_anchor(bound_member_id,action)
		player.set_activity_anchor(meal_anchor.position,meal_anchor.yaw,meal_anchor.kind,action_id,meal_anchor)
		return
	var item:Dictionary=_find_item(str(action.target_id))
	if not item.is_empty():
		var attention:Variant=null
		if not str(action.get("cooperation_id","")).is_empty():
			var shared:Dictionary=household.cooperative_presentation(bound_member_id)
			var partner_actor:LifeActor=world.actors.get(str(shared.get("partner_id","")))
			if is_instance_valid(partner_actor):attention=partner_actor.to_global(partner_actor.get_portrait_center())
		if action_id=="help_homework":
			var at:Vector3=action.target_position
			var toward:Vector3=item.node.to_global(Vector3(0,.9,.3))-at
			var anchor:Dictionary={"position":at,"yaw":atan2(toward.x,toward.z),"kind":"standing"}
			if attention is Vector3:anchor["attention_target"]=attention
			player.set_activity_anchor(at,anchor.yaw,"standing",action_id,anchor)
			return
		if action_id=="dance_together":
			# Each dancer holds their own ring spot and faces the record player,
			# exactly as a homework helper stands at their own desk position.
			var at:Vector3=action.target_position
			var toward:Vector3=item.node.to_global(Vector3(0,.6,0))-at
			var anchor:Dictionary={"position":at,"yaw":atan2(toward.x,toward.z),"kind":"standing"}
			player.set_activity_anchor(at,anchor.yaw,"standing",action_id,anchor)
			return
		var landmarks:Dictionary=player.get_body_landmarks() if player.has_method("get_body_landmarks") else {}
		if action_id=="cook":landmarks.merge({"recipe":str(action.get("recipe","")),"cooking_position":action.target_position})
		if action_id=="mop_puddle":landmarks["standing_position"]=action.target_position
		if action.has("seat_slot"):landmarks["seat_slot"]=str(action.seat_slot)
		var anchor:Dictionary=world.activity_anchor(item,action_id,landmarks)
		if attention is Vector3:anchor["attention_target"]=attention
		if player.has_method("set_activity_anchor"):
			player.set_activity_anchor(anchor.position,anchor.yaw,anchor.kind,action_id,anchor)
		else:
			player.rotation.y=lerp_angle(player.rotation.y,anchor.yaw,minf(delta*6,1))
		return
	if world.actors.has(str(action.target_id)):
		if sim.speed<=0 and residents.home_visit.owns(str(action.target_id)):return
		var direction:Vector3=world.actors[str(action.target_id)].position-player.position
		player.rotation.y=lerp_angle(player.rotation.y,atan2(direction.x,direction.z),minf(delta*6,1))

func _members_can_see_each_other(first:String,second:String)->bool:
	# Two household members share a moment only if they are physically visible to
	# each other: both present and no wall between them. Absent actors (away at
	# work, or never spawned in a headless simulation) are never witnesses.
	var a:LifeActor=world.actors.get(first)
	var b:LifeActor=world.actors.get(second)
	if not is_instance_valid(a) or not is_instance_valid(b):return false
	if not a.visible or not b.visible:return false
	if bool(a.get_meta("away",false)) or bool(b.get_meta("away",false)):return false
	return world.sight_line_clear(a.position,b.position)

func _social_point_clear(point:Vector3,target:LifeActor,tolerance:float=0.0)->bool:
	if not point.is_finite() or not target.visible:return false
	if absf(point.y-target.position.y)>.1:return false
	var distance:float=point.distance_to(target.position)
	if distance<maxf(0.0,LifeTraversal.ROUTE_CLEARANCE-tolerance) or distance>1.6:return false
	if not world.sight_line_clear(point,target.position):return false
	if not world.construction.building_state.is_empty():
		if not traversal._free(bound_member_id,point):return false
	else:
		var cell:=Vector2i(roundi(point.x*4),roundi(point.z*4))
		if not world.navigation.region.has_point(cell) or world.navigation.is_point_solid(cell):return false
	for id:String in world.actors:
		if id==bound_member_id:continue
		var other:LifeActor=world.actors[id]
		if other.visible and absf(point.y-other.position.y)<.1 and point.distance_to(other.position)<LifeTraversal.ROUTE_CLEARANCE:return false
	return true

func _social_refusal_message(action:Dictionary)->String:
	if traversal.busy(str(action.get("target_id",""))):return "This Lifelet is using the stairs. Try talking after they reach the next floor."
	return "There is no clear place for this conversation right now."

func _social_destination(action:Dictionary,preserve:bool=true)->Vector3:
	if traversal.busy(str(action.get("target_id",""))):return Vector3.INF
	var target:LifeActor=world.actors.get(str(action.get("target_id","")))
	if not is_instance_valid(target) or not target.visible or bool(target.get_meta("away",false)):return Vector3.INF
	# Keep the admitted endpoint exactly while the conversation remains nearby.
	# Published actor targets are suggestions, not replacements for owned routes.
	var previous:Vector3=action.get("target_position",Vector3.INF)
	if preserve and _social_point_clear(previous,target):return previous
	var canonical:bool=not world.construction.building_state.is_empty()
	var target_level:int=world.point_level(target.position)
	var from_level:int=world.point_level(player.position)
	if canonical and (target_level<0 or from_level<0):return Vector3.INF
	var offsets:Array[Vector3]=[Vector3(0,0,1),Vector3(1,0,0),Vector3(0,0,-1),Vector3(-1,0,0),Vector3(.75,0,.75),Vector3(.75,0,-.75),Vector3(-.75,0,-.75),Vector3(-.75,0,.75)]
	var best:Vector3=Vector3.INF;var best_distance:float=INF
	var occupied:Array[Vector3]=[]
	if canonical:occupied=traversal._occupied(bound_member_id)
	for offset:Vector3 in offsets:
		var point:Vector3=target.position+offset
		point.x=snappedf(point.x,.25);point.z=snappedf(point.z,.25)
		if not _social_point_clear(point,target):continue
		var points:PackedVector3Array=[]
		if canonical:
			var route:Dictionary=world.lot_navigation.route_avoiding(LifeLotNavigation.floor_location(from_level,player.position),LifeLotNavigation.floor_location(target_level,point),occupied,LifeTraversal.ROUTE_CLEARANCE)
			if not bool(route.ok):continue
			points=route.points
		else:points=world.path_to(player.position,point)
		if points.is_empty() or points[-1]!=point:continue
		var length:float=0.0
		for index:int in range(1,points.size()):length+=points[index-1].distance_to(points[index])
		if length<best_distance:best_distance=length;best=point
	return best

func _reconcile_social_action()->void:
	var action:Dictionary=sim.get_current_action()
	if action.is_empty() or str(action.id) not in LifeSim.SOCIAL_ACTIONS or str(action.phase) not in ["approach","active"] or traversal.busy(bound_member_id):return
	var destination:Vector3=_social_destination(action)
	if not destination.is_finite():
		show_notice(_social_refusal_message(action))
		cancel_current_action();return
	var changed:bool=destination!=Vector3(action.target_position)
	if changed:action.target_position=destination;action.phase="approach"
	var missing_route:bool=str(action.phase)=="approach" and not traversal.active(bound_member_id) and path.is_empty()
	if changed or missing_route:on_action_started(action)
var _contact_minute:int=-1

## Once per game minute, a visiting resident may start a contact with a
## household member who is physically nearby on the lot.
func _tick_resident_contacts()->void:
	var minute:int=int(sim.minutes)
	if minute==_contact_minute:return
	_contact_minute=minute
	# A neighbor who reaches the front path rings the doorbell instead of walking
	# in. The household answers: let them in, or ask them to leave.
	residents.home_visit.consider_ring()
	var positions:Dictionary={}
	for member:Dictionary in household.members:
		var member_sim:LifeSim=member.sim
		if member_sim.is_away() or str(member_sim.get_current_action().get("id",""))=="sleep":continue
		var actor:LifeActor=world.actors.get(str(member.id))
		if not is_instance_valid(actor):continue
		positions[str(member.id)]=actor.position
	if positions.is_empty():return
	for resident_id:String in LifeResidents.PEOPLE:
		var state:Dictionary=residents.locations.get(residents.active_place,{}).get(resident_id,{})
		var actor:LifeActor=world.actors.get(resident_id)
		if state.is_empty() or not is_instance_valid(actor):continue
		# A resident who is merely nearby across a partition must not start a
		# chat through it: only members the resident can actually see qualify.
		var visible_positions:Dictionary={}
		for member_id:String in positions:
			if world.sight_line_clear(actor.position,positions[member_id]):visible_positions[member_id]=positions[member_id]
		if visible_positions.is_empty():continue
		var contact:Dictionary=residents.resident_initiation(resident_id,str(state.get("phase","")),actor.position,visible_positions,LifeEducation.weekday(sim.day),sim.minutes,sim.day)
		if not contact.is_empty():_apply_resident_contact(contact)

func _apply_resident_contact(contact:Dictionary)->void:
	var member_sim:LifeSim=household.member_sim(str(contact.member))
	if not is_instance_valid(member_sim):return
	residents.apply_contact(contact,member_sim)
	show_notice(str(contact.notice))

func _reconcile_social_routes()->void:
	var prior:String=bound_member_id
	_store_motion()
	for member:Dictionary in household.members:
		_bind_member(str(member.id))
		if not sim.is_away():_reconcile_social_action()
		_store_motion()
	_bind_member(prior)


func _resolve_activity_target(action:Dictionary,keep_committed_endpoint:bool=false) -> void:
	if str(action.id) in ["school_day","career_day","morning_run"]:
		action.target_position=world.lot_exit_position(_member_index(bound_member_id));return
	if world.actors.has(str(action.target_id)):
		action.target_position=world.actors[str(action.target_id)].position+Vector3(0,0,.9)
		return
	var item:Dictionary=_find_item(str(action.target_id))
	# The route is cleared just before this runs. A caller that already matched
	# this approach to that route asks us to keep the endpoint: naming a bed
	# half would move a saved Sleep the moment Build drops its courtesy hold.
	if not item.is_empty() and world.seat_capacity(item)>1 and not keep_committed_endpoint:_assign_seat_slot(action,item)
	var wanted:String=""
	if action.id=="cook" and not item.is_empty() and item.kind=="fridge":wanted="stove"
	if action.id=="watch" and not item.is_empty() and item.kind=="tv":wanted="sofa"
	if wanted.is_empty():return
	var best:Dictionary=world.closest_item(wanted,item.node.position)
	if wanted=="sofa":
		# Any lounge seat works for television. Prefer the nearest seat nobody is
		# using, so two Lifelets can watch the same set from different seats.
		var seats:Array=[]
		for lounge:String in ["sofa","loveseat","armchair"]:
			for candidate:Dictionary in world.items:
				if str(candidate.kind)==lounge and world.item_level(candidate)==world.item_level(item) and candidate.node.position.distance_to(item.node.position)<=5.0:seats.append(candidate)
		seats.sort_custom(func(a:Dictionary,b:Dictionary)->bool:return a.node.position.distance_to(item.node.position)<b.node.position.distance_to(item.node.position))
		var free_seat:Dictionary={}
		for seat:Dictionary in seats:
			var trial:Dictionary=action.duplicate(true)
			trial.target_id=seat.id;trial.target_position=world.approach(seat)
			# A two-seater is tested per seat, so a full loveseat does not look free.
			if world.seat_capacity(seat)>1:_assign_seat_slot(trial,seat)
			if _activity_available_for_member(trial,bound_member_id):free_seat=seat;break
		if not free_seat.is_empty():best=free_seat
		elif not seats.is_empty():best=seats.front()
	if not best.is_empty():
		action.target_id=best.id
		action.target_position=world.approach(best)
		if world.seat_capacity(best)>1:_assign_seat_slot(action,best)

## Give this Lifelet one of a furnishing's own places. How many places it has is
## the catalogue's own seat count for the size that was bought, so a large garden
## table really seats ten and a loveseat two. A bed keeps its named halves for a
## partnered pair: the first partner takes one half, the second the other, and
## anyone else is refused the bed entirely by the availability gate rather than
## being seated on a half.
func _assign_seat_slot(action:Dictionary,item:Dictionary) -> void:
	var shared_bed:bool=str(item.kind) in world.SHARED_BEDS
	var slots:Array[String]=world.seat_slots(item)
	var taken:Array=[]
	var partner_in_bed:bool=false
	for member:Dictionary in household.members:
		if member.id==bound_member_id:continue
		var other:Dictionary=member.sim.get_current_action()
		if other.is_empty() or str(other.get("target_id",""))!=str(item.id) or not other.has("seat_slot"):continue
		taken.append(str(other.seat_slot))
		if shared_bed and _is_my_partner(str(member.id)):partner_in_bed=true
	if shared_bed and not taken.is_empty() and not partner_in_bed:
		# Someone else already lies here and they are not this member's partner:
		# claim the free half AND the whole bed, so the availability gate refuses
		# it instead of seating a housemate on the edge.
		action["seat_slot"]="right" if taken.has("left") else "left"
		action.target_position=world.slot_approach(item,str(action.seat_slot))
		return
	if shared_bed and partner_in_bed:
		action["seat_slot"]="right" if taken.has("left") else "left"
		action.target_position=world.slot_approach(item,str(action.seat_slot))
		return
	# Otherwise take the first place this furnishing still has free, so a table
	# for ten seats ten people in turn rather than only ever its two end places.
	var taken_slot:bool=action.has("seat_slot") and taken.has(str(action.seat_slot))
	if not action.has("seat_slot") or taken_slot:
		for slot:String in slots:
			if not taken.has(slot):
				action["seat_slot"]=slot
				break
	action.target_position=world.slot_approach(item,str(action.get("seat_slot","")))

func _is_my_partner(member_id:String) -> bool:
	var mine:LifeSim=household.member_sim(bound_member_id)
	return mine!=null and not str(mine.romantic_partner).is_empty() and str(mine.romantic_partner)==member_id

func _activity_available(action:Dictionary) -> bool:
	return _activity_available_for_member(action,bound_member_id)

func _activity_available_for_member(action:Dictionary,member_id:String) -> bool:
	if action.is_empty():return false
	if not residents.home_visit.welcome_start_allowed(action):return false
	if str(action.get("id","")) in LifeSim.SOCIAL_ACTIONS and LifeResidents.PEOPLE.has(str(action.get("target_id",""))):
		if not residents.present(str(action.target_id)) or not residents.home_visit.social_allowed(str(action.target_id),action):return false
	if meal_flow.standing_place_blocks(member_id,action) or meal_flow.guest_blocks(action):return false
	var wanted:Array[String]=_activity_resources(action)
	var session_id:String=str(action.get("cooperation_id",""))
	# Read the requesting member without rebinding the movement controller
	# while Household.tick is advancing another member. Live bound fields
	# take precedence over its last stored motion; other members use that store.
	var member_sim:LifeSim=household.member_sim(member_id)
	var own_motion:Dictionary=motion_states.get(member_id,_empty_motion())
	var own_wait_started:float=wait_started if member_id==bound_member_id else float(own_motion.get("wait_started",-1.0))
	var own_resume:bool=resume_activity if member_id==bound_member_id else bool(own_motion.get("resume_active",false))
	var resuming_owner:bool=own_resume and is_instance_valid(member_sim) and action==member_sim.get_current_action()
	for member:Dictionary in household.members:
		if member.id==member_id:continue
		var other:Dictionary=member.sim.get_current_action()
		if other.is_empty():continue
		var other_session:String=str(other.get("cooperation_id",""))
		if not session_id.is_empty() and session_id==other_session:continue
		var other_wait:Dictionary=motion_states.get(str(member.id),_empty_motion())
		if other.phase!="active" and other_session.is_empty() and not bool(other_wait.get("resume_active",false)):
			# A saved active owner resumes its existing paid activity before
			# arrived waiters; it is not a new request at the back of the queue.
			if resuming_owner:continue
			if not bool(other_wait.waiting):continue
			var earlier:float=float(other_wait.get("wait_started",-1.0))
			if earlier<0:continue
			# An arrived Lifelet keeps their place when an earlier actor in the
			# household array finishes and immediately requests the same object.
			if own_wait_started>=0 and earlier>own_wait_started:continue
			if own_wait_started>=0 and is_equal_approx(earlier,own_wait_started) and str(member.id)>member_id:continue
		for resource_id:String in _activity_resources(other):
			if wanted.has(resource_id):
				# A partner sleeping in the other half of the same bed is the
				# one allowed conflict: the two halves are distinct resources,
				# so only the whole-bed claim overlaps and that overlap is
				# exactly what sharing means.
				if _partner_shares_bed(action,member_id,str(member.id),other,resource_id):continue
				return false
	return true

func _partner_shares_bed(action:Dictionary,member_id:String,holder_id:String,other:Dictionary,resource_id:String) -> bool:
	var item:Dictionary=_find_item(str(action.get("target_id","")))
	if item.is_empty() or str(item.kind) not in world.SHARED_BEDS:return false
	if str(other.get("target_id",""))!=str(item.id):return false
	if resource_id!=str(item.id):return false
	var mine:LifeSim=household.member_sim(member_id)
	if mine==null or str(mine.romantic_partner).is_empty():return false
	return str(mine.romantic_partner)==holder_id

func _activity_resources(action:Dictionary) -> Array[String]:
	if str(action.get("id","")) in ["school_day","career_day","morning_run"]:return []
	var target_id:String=str(action.get("target_id",""))
	var item:Dictionary=_find_item(target_id)
	var resources:Array[String]=[]
	if item.is_empty():resources.append(target_id)
	else:
		for resource_id:String in world.activity_resource_ids(item,str(action.get("seat_slot",""))):
			resources.append(resource_id)
	if action.has("target_position"):
		var at:Vector3=action.target_position
		var cell:Vector2i=Vector2i(roundi(at.x*2),roundi(at.z*2))
		resources.append("standing:%d:%d:%d" % [world.point_level(at),cell.x,cell.y])
		if str(action.get("cooperation_role",""))=="helper":
			for offset:Vector2i in [Vector2i(1,0),Vector2i(-1,0),Vector2i(0,1),Vector2i(0,-1)]:
				resources.append("standing:%d:%d:%d" % [world.point_level(at),cell.x+offset.x,cell.y+offset.y])
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
		var row=Control.new();row.custom_minimum_size=Vector2(450,126 if LifeResidents.PEOPLE.has(id) else 83);column.add_child(row)
		button(rel.name,Vector2.ZERO,Vector2(444,38),func():focus_neighbor(id),false,row)
		text_label("%s · Friendship %d · Romance %d" % [rel.status,rel.friendship,rel.romance],Vector2(8,44),Vector2(438,30),13,P.MUTED,false,row)
		if LifeResidents.PEOPLE.has(id):
			var visit=button("Visit home  →",Vector2(8,83),Vector2(206,34),func():show_neighborhood(str(LifeResidents.PEOPLE[id].home)),false,row)
			visit.name="VisitResident_"+id;visit.disabled=not residents.can_visit(id)
			var invite=button("Invite over",Vector2(224,83),Vector2(212,34),func():invite_neighbor(id),false,row)
			invite.name="InviteResident_"+id;invite.disabled=not residents.home_visit.requirement(id).is_empty();invite.tooltip_text=residents.home_visit.requirement(id)
			visit.tooltip_text="Reach 20 friendship to arrange a visit." if visit.disabled else str(str(LifeNeighborhood.info(LifeResidents.PEOPLE[id].home).get("tag","")))
	button("Family tree",Vector2(486,699),Vector2(222,43),show_family_tree,false,overlay)
	button("Back to life",Vector2(724,699),Vector2(230,43),close_overlay,true,overlay)

func compact_button(b:Button) -> void:
	b.add_theme_font_size_override("font_size",12)
	for style_name:String in ["normal","hover","pressed","focus","disabled"]:
		var style:StyleBox=b.get_theme_stylebox(style_name).duplicate()
		style.content_margin_left=4;style.content_margin_right=4;style.content_margin_top=4;style.content_margin_bottom=4
		b.add_theme_stylebox_override(style_name,style)

func _safe_layout(value:Variant) -> Array:
	# A legacy public venue can retain a canonical two-floor home. Its current
	# journeys are empty; preserve the nested home's complete validated records.
	if value is Array and value.any(func(entry:Variant):return entry is Dictionary and str(entry.get("kind",""))=="__construction" and entry.has("version")):
		return value.duplicate(true) if world.validate_home_layout(value).is_empty() else []
	if not household.journeys.is_empty():return value.duplicate(true) if value is Array else []
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

## The town map's authored size, in map units. Pins and scenery are placed in
## these coordinates and the whole thing is multiplied by the current zoom, so
## zooming spreads the town out instead of only magnifying one corner.
const MAP_BASE: Vector2 = Vector2(1500.0, 1000.0)
const MAP_PIN: Vector2 = Vector2(170.0, 53.0)
## How far the map may shrink before it is nonsense, and how far it may grow.
## The real outward limit is "the whole town fits the viewport", which depends on
## the window, so the fit zoom is derived rather than fixed; `MAP_MIN_ZOOM` only
## stops a very small window from collapsing the town to nothing.
const MAP_MIN_ZOOM: float = 0.25
const MAP_MAX_ZOOM: float = 2.0
const MAP_ZOOM_STEP: float = 0.15
## Where each place sits on the map, in map units. The layout follows the town's
## own geography: the two lanes along the bottom and the hill road up to the
## library and the cottages. Every visitable place has its own pin.
const MAP_POINTS: Dictionary = {
	"home": Vector2(180, 690),
	"park": Vector2(600, 780),
	"maya_home": Vector2(960, 860),
	"leo_home": Vector2(1300, 830),
	"library": Vector2(1100, 520),
	"studio": Vector2(740, 130),
	"priya_home": Vector2(280, 150),
	"tom_home": Vector2(1160, 190),
}

## The map's own state, kept across rebuilds so selecting a place or travelling
## does not throw the player back to the middle of the town.
var map_zoom: float = 0.0
var map_selected: String = ""
var map_scroll: ScrollContainer
var map_canvas: Control
## Drag state for panning the map: where the press landed, whether the pointer
## is still down, and whether it has moved far enough to count as a drag.
var map_dragging: bool = false
var map_panned: bool = false
var map_press: Vector2 = Vector2.ZERO
## Whether the next trip takes only the selected Lifelet. It outlives a rebuild,
## so switching between map pins keeps the player's choice.
func show_neighborhood(chosen:String="") -> void:
	if chosen.is_empty():chosen=current_venue
	map_selected=chosen
	_begin_pause_overlay()
	var shade=ColorRect.new();shade.color=Color(.08,.17,.15,.28);rect(shade,Vector2(interface_local_x(0.0),0),interface_size(),overlay)
	card(Vector2(120,86),Vector2(1200,742),P.WHITE,24,overlay)
	small_caps("A place to belong",Vector2(156,106),Vector2(600,24),overlay)
	text_label("Around Juniper Bay",Vector2(154,142),Vector2(750,52),38,P.INK,true,overlay)
	# The map is a scrollable, zoomable canvas: every place in the neighbourhood
	# has a pin, the town's own roads and greenery are drawn behind them, and the
	# player can zoom in to read a cluster or out to see the whole town at once.
	map_scroll=ScrollContainer.new()
	map_scroll.name="NeighborhoodMap"
	rect(map_scroll,Vector2(150,236),Vector2(760,544),overlay)
	map_scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_AUTO
	map_scroll.vertical_scroll_mode=ScrollContainer.SCROLL_MODE_AUTO
	map_canvas=Control.new()
	map_canvas.name="NeighborhoodCanvas"
	map_canvas.mouse_filter=Control.MOUSE_FILTER_PASS
	map_scroll.add_child(map_canvas)
	map_canvas.draw.connect(_draw_neighborhood_map)
	var data:Dictionary=LifeNeighborhood.PLACES[chosen]
	small_caps(str(data.tag),Vector2(940,244),Vector2(341,45),overlay)
	text_label(str(data.name),Vector2(938,296),Vector2(342,46),28,P.INK,true,overlay)
	paragraph(str(data.description),Vector2(940,356),Vector2(340,140),16,P.MUTED,overlay)
	paragraph(_travel_caption(str(data.name)),Vector2(940,498),Vector2(340,88),13,P.MUTED,overlay)
	var go=button("Travel here  →",Vector2(940,600),Vector2(344,44),func():travel_to(chosen),true,overlay)
	go.name="MapTravel"
	var resident:String=str(data.get("resident",""))
	go.disabled=chosen==current_venue or (not resident.is_empty() and not residents.can_visit(resident))
	# Who comes along: remote's own party picker, which lists everyone who can
	# travel and names why anyone cannot, so nobody is silently left behind.
	var choose:Button=button("Choose who goes…",Vector2(940,650),Vector2(344,34),func():show_trip_party(chosen),false,overlay)
	choose.name="ChooseTripParty"
	choose.disabled=go.disabled
	choose.tooltip_text="Pick only some of the household; anyone left behind stays home."
	if not resident.is_empty() and not residents.can_visit(resident):
		go.text="Meet them first · 20 friendship"
		go.tooltip_text="Say hello when they walk past your home. Get to know them, then arrange a visit."
	# Zoom controls, beside the map so the gesture is discoverable without a wheel.
	button("−",Vector2(150,790),Vector2(44,30),func():zoom_neighborhood_map(-MAP_ZOOM_STEP),false,overlay).name="MapZoomOut"
	button("+",Vector2(202,790),Vector2(44,30),func():zoom_neighborhood_map(MAP_ZOOM_STEP),false,overlay).name="MapZoomIn"
	button("Fit the whole town",Vector2(254,790),Vector2(184,30),func():zoom_neighborhood_map(-99.0),false,overlay).name="MapZoomFit"
	button("Back to life",Vector2(940,716),Vector2(344,35),close_overlay,false,overlay)
	_layout_neighborhood_map()

## Draw the town behind the pins. Everything is multiplied by the zoom, so the
## roads, water, greenery and crossings stay registered with the pins at every
## magnification.
func _draw_neighborhood_map() -> void:
	if not is_instance_valid(map_canvas):return
	var zoom:float=maxf(map_zoom,0.001)
	var size:Vector2=MAP_BASE*zoom
	map_canvas.draw_style_box(P.panel(Color("e5ebd8"),18),Rect2(Vector2.ZERO,size))
	var p:=func(v:Vector2)->Vector2:return v*zoom
	# The river, then the two lanes along the valley and the hill road up to the
	# cottages, drawn wide to thin so a crossing reads as a bridge.
	map_canvas.draw_polyline(PackedVector2Array([p.call(Vector2(24,880)),p.call(Vector2(360,820)),p.call(Vector2(700,850)),p.call(Vector2(1040,800)),p.call(Vector2(1476,820))]),Color("91b9b2"),42.0*zoom,true)
	map_canvas.draw_polyline(PackedVector2Array([p.call(Vector2(60,640)),p.call(Vector2(420,600)),p.call(Vector2(780,640)),p.call(Vector2(1140,600)),p.call(Vector2(1450,620))]),Color("f7f3df"),25.0*zoom,true)
	map_canvas.draw_polyline(PackedVector2Array([p.call(Vector2(420,600)),p.call(Vector2(700,420)),p.call(Vector2(980,300)),p.call(Vector2(1180,300))]),Color("f7f3df"),21.0*zoom,true)
	map_canvas.draw_polyline(PackedVector2Array([p.call(Vector2(700,420)),p.call(Vector2(620,760))]),Color("f7f3df"),19.0*zoom,true)
	map_canvas.draw_polyline(PackedVector2Array([p.call(Vector2(980,300)),p.call(Vector2(1080,520))]),Color("f7f3df"),19.0*zoom,true)
	# Greens, then the town's own buildings, so a pin always names something real.
	for at:Vector2 in [Vector2(90,300),Vector2(150,420),Vector2(560,180),Vector2(1300,120),Vector2(1420,420),Vector2(760,960),Vector2(1120,940),Vector2(300,940),Vector2(1380,700)]:
		map_canvas.draw_circle(p.call(at),22.0*zoom,Color("a2bb84"))
		map_canvas.draw_circle(p.call(at)-Vector2(5,5)*zoom,14.0*zoom,Color("b5cb99"))
	for at:Vector2 in [Vector2(210,520),Vector2(880,60),Vector2(940,80),Vector2(520,900),Vector2(1240,700),Vector2(640,540),Vector2(1400,900)]:
		map_canvas.draw_style_box(P.panel(Color("c3bfa5"),4),Rect2(p.call(at),Vector2(34,30)*zoom))

## Rebuild the pins and the canvas size for the current zoom. Pin buttons keep
## their authored size at every zoom, so a name stays readable when the town is
## zoomed out; only the town's own coordinates scale.
func _layout_neighborhood_map() -> void:
	if not is_instance_valid(map_canvas):return
	if map_zoom<=0.0:map_zoom=_neighborhood_fit_zoom()
	var zoom:float=map_zoom
	for child:Node in map_canvas.get_children():
		map_canvas.remove_child(child)
		child.queue_free()
	var size:Vector2=MAP_BASE*zoom
	map_canvas.custom_minimum_size=size
	map_canvas.size=size
	for id:String in MAP_POINTS:
		var data:Dictionary=LifeNeighborhood.PLACES[id]
		var at:Vector2=(MAP_POINTS[id] as Vector2)*zoom
		if id==current_venue:
			text_label("YOU ARE HERE",at+Vector2(4,-20),Vector2(166,20),10,P.TEAL,false,map_canvas)
		var pin=button(str(data.name),at,MAP_PIN,func():show_neighborhood(id),id==map_selected,map_canvas)
		pin.add_theme_font_size_override("font_size",13)
		# The pin's own text sets a minimum width larger than its cell, which
		# would push it into its neighbour; the pin size stays authoritative.
		compact_button(pin)
		pin.custom_minimum_size=Vector2.ZERO
		pin.size=MAP_PIN
	map_canvas.queue_redraw()

## The zoom at which the whole authored town fits inside the map viewport. The
## outermost pins sit at the canvas edge and are drawn at their authored size, so
## the pin's own footprint is added to the canvas before the ratio is taken;
## otherwise "Fit the whole town" would still leave the corner pins clipped.
func _neighborhood_fit_zoom() -> float:
	if not is_instance_valid(map_scroll):return 1.0
	var view:Vector2=map_scroll.size
	if view.x<=0.0 or view.y<=0.0:return 1.0
	var extent:Vector2=MAP_BASE+MAP_PIN
	return clampf(minf(view.x/extent.x,view.y/extent.y),MAP_MIN_ZOOM,MAP_MAX_ZOOM)

## Zoom the map, keeping the point the player is looking at under the cursor.
## A step of -99 or more means "fit the whole town".
func zoom_neighborhood_map(step:float) -> void:
	if not is_instance_valid(map_canvas) or not is_instance_valid(map_scroll):return
	var before:float=map_zoom
	var target:float=_neighborhood_fit_zoom() if step<=-99.0 else clampf(map_zoom+step,MAP_MIN_ZOOM,MAP_MAX_ZOOM)
	if is_equal_approx(target,before):return
	# Remember the map point at the centre of the viewport so zooming holds the
	# player's place instead of snapping back to the town's corner.
	var view:Vector2=map_scroll.size
	var centre:Vector2=(Vector2(map_scroll.scroll_horizontal,map_scroll.scroll_vertical)+view*.5)/maxf(before,0.001)
	map_zoom=target
	_layout_neighborhood_map()
	var restored:Vector2=centre*map_zoom-view*.5
	map_scroll.scroll_horizontal=int(clampf(restored.x,0.0,maxf(0.0,MAP_BASE.x*map_zoom-view.x)))
	map_scroll.scroll_vertical=int(clampf(restored.y,0.0,maxf(0.0,MAP_BASE.y*map_zoom-view.y)))

## The map's own gestures — dragging to pan and the wheel to zoom — handled
## before the GUI. Returns true only for an event the map really consumed, so a
## plain press still reaches the pin underneath and selects that place.
func _neighborhood_gesture(event:InputEvent) -> bool:
	if not is_instance_valid(map_scroll):return false
	if event is InputEventMouseButton:
		if event.button_index not in [MOUSE_BUTTON_LEFT,MOUSE_BUTTON_MIDDLE,MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:return false
		if not map_scroll.get_global_rect().has_point(event.position):return false
		if event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
			if not event.pressed:return false
			zoom_neighborhood_map(MAP_ZOOM_STEP if event.button_index==MOUSE_BUTTON_WHEEL_UP else -MAP_ZOOM_STEP)
			get_viewport().set_input_as_handled()
			return true
		if event.pressed:
			map_dragging=true
			map_panned=false
			map_press=event.position
			return false
		if not map_dragging:return false
		map_dragging=false
		var panned:bool=map_panned
		map_panned=false
		if panned:
			# The pin's own release never arrives, so the drag cannot also select
			# whatever place happened to be under the pointer when it started.
			get_viewport().set_input_as_handled()
		return panned
	if event is InputEventMouseMotion and map_dragging:
		if not map_panned and event.position.distance_to(map_press)<4.0:return false
		map_panned=true
		map_scroll.scroll_horizontal-=int(event.relative.x)
		map_scroll.scroll_vertical-=int(event.relative.y)
		get_viewport().set_input_as_handled()
		return true
	return false

## What the travel button will really do. Who comes along is the party picker's
## own choice, so the caption names the town and the time rather than a mode.
func _travel_caption(destination:String) -> String:
	return "A shared car takes the household across town in 15 minutes; use **Choose who goes** to take only some of them. Drag the map to look around; the wheel zooms."

func travel_to(destination:String) -> void:
	if mode not in ["live","build"] or not LifeNeighborhood.has(destination) or destination==current_venue:return
	var resident:String=str(LifeNeighborhood.info(destination).get("resident",""))
	if not resident.is_empty() and not residents.can_visit(resident):show_notice("Get to know this neighbor first. Visits open at 20 friendship.");return
	# The party picker's own choice decides who boards; an untouched party is
	# everyone who can come.
	residents.begin_trip(destination,party_selection)

## Who goes on the trip. Everyone who can travel is listed and ticked; a Lifelet
## who is working, at school or on the stairs is shown with the reason they
## cannot come, so nothing is silently left behind.
##
## `reset` defaults the party to everyone who can come, and is used only when the
## panel is first opened. Redrawing after a tick keeps the player's own choices,
## because a redraw that re-ticked everybody would undo the pick they just made.
func show_trip_party(destination:String, reset:bool = true) -> void:
	# Remembered, because every untick redraws this panel and must come back to
	# the same destination.
	_pending_trip_destination=destination
	var options:Array=residents.party_options()
	if reset:
		party_selection.clear()
		for entry:Dictionary in options:
			if bool(entry.available):party_selection.append(str(entry.id))
	else:
		# A Lifelet who has since become unavailable is dropped rather than
		# travelling while busy.
		for member_id:String in party_selection.duplicate():
			var still_ok:bool=false
			for entry:Dictionary in options:
				if str(entry.id)==member_id and bool(entry.available):still_ok=true
			if not still_ok:party_selection.erase(member_id)
	_begin_pause_overlay()
	var shade=ColorRect.new();shade.color=Color(.08,.17,.15,.28);rect(shade,Vector2(interface_local_x(0.0),0),interface_size(),overlay)
	card(Vector2(470,150),Vector2(500,600),P.WHITE,24,overlay)
	small_caps("Who is coming",Vector2(502,172),Vector2(440,24),overlay)
	text_label("Off to %s" % str(LifeNeighborhood.place_name(destination)),Vector2(500,200),Vector2(444,46),30,P.INK,true,overlay)
	paragraph("Tick who is coming along. Anyone left behind stays home and carries on with their own day.",Vector2(502,254),Vector2(440,44),14,P.MUTED,overlay)
	var y:float=312.0
	for entry:Dictionary in options:
		var member_id:String=str(entry.id)
		var chosen:bool=party_selection.has(member_id)
		var label:String=str(entry.name).split(" ")[0]+("  ✓" if chosen else "")
		var row:Button=button(label,Vector2(502,y),Vector2(440,42),
			func():_toggle_party_member(member_id),chosen,overlay)
		row.name="TripParty_"+member_id
		row.disabled=not bool(entry.available)
		row.tooltip_text=str(entry.reason) if not bool(entry.available) else "Comes along on the trip."
		if not bool(entry.available):
			text_label(str(entry.reason),Vector2(508,y+44),Vector2(430,20),11,P.CORAL,false,overlay)
		y+=68.0
	var go:Button=button("Travel  →",Vector2(502,y+8),Vector2(440,46),func():_start_trip(destination),true,overlay)
	go.name="TripPartyGo"
	go.disabled=party_selection.is_empty()
	go.tooltip_text="Travel with the Lifelets you have chosen." if not party_selection.is_empty() else "Choose at least one Lifelet to come along."
	button("Back",Vector2(502,y+62),Vector2(440,36),func():show_neighborhood(destination),false,overlay)


## Tick or untick one Lifelet for the trip.

func _toggle_party_member(member_id:String) -> void:
	if party_selection.has(member_id):party_selection.erase(member_id)
	else:party_selection.append(member_id)
	show_trip_party(_pending_trip_destination,false)


## Leave with the chosen party.

func _start_trip(destination:String) -> void:
	_pending_trip_destination=destination
	if residents.begin_trip(destination,party_selection):
		party_selection.clear()



func show_stories() -> void:
	_begin_pause_overlay()
	var shade=ColorRect.new();shade.color=Color(.08,.17,.15,.28);rect(shade,Vector2(interface_local_x(0.0),0),interface_size(),overlay)
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
	_set_studio_render_quality(false)
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
		# A birth that was waiting to be named must not be stranded by leaving
		# the creator: reopen it as soon as the household is live again.
		if household.birth_ready():show_baby_creator.call_deferred()
	else:load_game()

func new_game() -> void:
	if has_active_game:
		show_replace_life("new","")
		return
	_begin_new_game()

func _begin_new_game() -> void:
	has_active_game=false;active_save_id="";active_save_name=""
	profile={"name":"Mara Vale","frame":0,"hair":1,"skin_color":"d9a17d","hair_color":"54382a","top_color":"c97c66","bottom_color":"eadfc9","shoe_color":"e9e4d9","body_scale":1.0,"height_scale":1.0,"outfit":0,"eye_color":"547365","traits":["Creative","Outgoing","Foodie"],"aspiration":"Maker"}
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
	# A panel can close and Save can run in the same input frame. Draw the current
	# scene before readback without advancing play or deferring this save's preview.
	RenderingServer.force_draw(false,0.0)
	var rendered:Image=get_viewport().get_texture().get_image()
	if rendered==null or rendered.is_empty():return
	var dimensions:Vector2i=rendered.get_size()
	var section=Rect2i(int(dimensions.x*.21),int(dimensions.y*.22),int(dimensions.x*.61),int(dimensions.y*.49))
	save_preview=rendered.get_region(section)
	save_preview.resize(640,380,Image.INTERPOLATE_LANCZOS)

func refresh_build_quote() -> void:
	if is_instance_valid(roof_visibility_button):roof_visibility_button.text="Hide roofs" if world.construction.roofs_visible else "Show roofs"
	if not is_instance_valid(build_quote_card) or not is_instance_valid(world.construction):return
	var structure:LifeConstruction=world.construction
	build_quote_card.visible=not structure.tool.is_empty()
	if not build_quote_card.visible:return
	if structure.tool=="roof_edit" and structure.roof_edit_id.is_empty():
		build_quote.text="Select a roof to edit · Esc to cancel";build_quote.add_theme_color_override("font_color",P.INK);return
	if not structure.anchored and structure.tool in ["wall","room","floor","roof","roof_edit"]:
		build_quote.text="Click the first corner · Esc to cancel"
		build_quote.add_theme_color_override("font_color",P.INK)
		return
	var proposal:Dictionary=structure.proposal
	if proposal.is_empty():build_quote.text="Point at the structure · Esc to cancel";return
	var cost:int=int(proposal.get("cost",0))
	if not bool(proposal.get("valid",false)):
		build_quote.text=str(proposal.get("error","That space overlaps or is outside your lot"))
		build_quote.add_theme_color_override("font_color",Color("a84f43"))
	elif cost>sim.funds:
		build_quote.text="ℒ%d · You need ℒ%d more" % [cost,cost-sim.funds]
		build_quote.add_theme_color_override("font_color",Color("a84f43"))
	else:
		build_quote.text=("Refund ℒ%d" % -cost if cost<0 else "ℒ%d" % cost)+" · Click to confirm"
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

func _refresh_aged_member(id: String,epoch:int=-1,sender:LifeHousehold=null) -> void:
	if (epoch>=0 and epoch!=load_epoch) or (sender!=null and sender!=household):return
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
	card(Vector2(445,150),Vector2(550,620),P.WHITE,24,overlay)
	text_label("Life at your pace",Vector2(476,180),Vector2(486,60),35,P.INK,true,overlay)
	paragraph("Choose how quickly your household grows. Changing the pace keeps each Lifelet's progress through their current age.",Vector2(479,256),Vector2(478,75),17,P.MUTED,overlay)
	small_caps("Lifespan",Vector2(480,345),Vector2(477,25),overlay)
	var pace := OptionButton.new()
	pace.name="LifespanSetting"
	for label: String in ["Short", "Normal", "Long"]: pace.add_item(label)
	pace.select(["short","normal","long"].find(str(sim.lifecycle.lifespan)))
	rect(pace,Vector2(478,381),Vector2(480,43),overlay)
	var automatic := CheckButton.new()
	automatic.name="AutomaticAgingSetting"
	automatic.text="Automatic birthdays"
	automatic.button_pressed=bool(sim.lifecycle.auto_age)
	rect(automatic,Vector2(478,440),Vector2(480,42),overlay)
	small_caps("Save automatically",Vector2(480,494),Vector2(477,25),overlay)
	var autosave := OptionButton.new()
	autosave.name="AutosaveSetting"
	for minutes: int in AUTOSAVE_CHOICES:
		autosave.add_item("Off" if minutes==0 else ("Every minute" if minutes==1 else "Every %d minutes" % minutes))
	autosave.select(AUTOSAVE_CHOICES.find(autosave_minutes))
	rect(autosave,Vector2(478,530),Vector2(480,43),overlay)
	paragraph("Your life is written to its own save on this interval while the household is living. A menu or Build session pauses it.",Vector2(480,585),Vector2(474,52),14,P.MUTED,overlay)
	button("Apply",Vector2(478,660),Vector2(230,44),func():
		household.set_aging(["short","normal","long"][pace.selected],automatic.button_pressed)
		autosave_minutes=AUTOSAVE_CHOICES[autosave.selected]
		autosave_wait=0.0
		close_overlay();refresh_hud(),true,overlay)
	button("Cancel",Vector2(725,660),Vector2(233,44),close_overlay,false,overlay)

func show_birthday() -> void:
	_begin_pause_overlay();menus.shade()
	var next: String=LifeLifecycle.next_stage(str(sim.character.age_stage))
	if next.is_empty():close_overlay();return
	card(Vector2(450,250),Vector2(540,399),P.WHITE,24,overlay)
	text_label("A new chapter",Vector2(481,282),Vector2(476,54),35,P.INK,true,overlay)
	paragraph("Celebrate %s's birthday and become %s. Your personality, friendships and learned skills stay with you." % [sim.character.name,LifeLifecycle.with_article(next)],Vector2(484,371),Vector2(470,117),19,P.INK,overlay)
	button("Celebrate · ℒ30",Vector2(483,554),Vector2(271,48),func():close_overlay();queue_nearest("fridge","birthday"),true,overlay)
	button("Keep this age",Vector2(768,554),Vector2(188,48),close_overlay,false,overlay)

func creator_age_stages() -> Array:
	if creator_purpose=="baby":return ["baby"]
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
	paragraph("School runs weekdays, 08:00–15:00. Arrive by 09:00; late arrivals until 12:00 reduce performance. Your Lifelet walks to the street and returns after school. Homework prepares the next day.",Vector2(465,389),Vector2(505,91),17,P.MUTED,overlay)
	var classes:String="%d %s attended" % [sim.education.attended,"class" if int(sim.education.attended)==1 else "classes"]
	var assignments:String="%d %s" % [sim.education.homework,"assignment" if int(sim.education.homework)==1 else "assignments"]
	text_label("%s · %d missed · %s · %d min late" % [classes,sim.education.missed,assignments,int(sim.education.get("late_minutes",0.0))],Vector2(465,504),Vector2(506,30),14,P.INK,false,overlay)
	paragraph("Graduation needs at least three attended classes, 70% attendance and a C grade. Your school record stays with you as you grow.",Vector2(465,555),Vector2(505,63),14,P.MUTED,overlay)
	var online:Button=button("Online classes",Vector2(464,653),Vector2(216,45),func():close_overlay();queue_nearest("desk","school"),false,overlay)
	online.tooltip_text="Optional three-hour class at a home computer. It shares today’s attendance credit with school."
	online.disabled=not sim.get_action_availability("school").available or sim.is_away()
	button("Back to life",Vector2(693,653),Vector2(283,45),close_overlay,true,overlay)

func frame_creator_camera() -> void:
	if not is_instance_valid(preview):return
	var center:Vector3=preview.call("get_portrait_center") if preview.has_method("get_portrait_center") else Vector3(0,1.52,0)
	var height:float=float(preview.call("get_display_height")) if preview.has_method("get_display_height") else 1.76
	if creator_tab=="Face":
		var ratio:float=clampf(height/1.76,.8,1.1)
		# Give small facial edits enough screen space to judge, with headroom
		# for taller hairstyles below the creator's progress header.
		world.camera.position=center+Vector3(0,.055*ratio,1.10*ratio)
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
	var parent_routes:Array=_family_parent_routes(links,positions)
	diagram.draw.connect(func():
		for route:Dictionary in parent_routes:
			diagram.draw_polyline(route.points,P.WHITE,6.0,true)
			diagram.draw_polyline(route.points,P.TEAL,2.5,true)
			var tip:Vector2=route.points[-1]
			diagram.draw_polyline(PackedVector2Array([tip+Vector2(-3,-6),tip,tip+Vector2(3,-6)]),P.TEAL,2.5,true)
		for edge:Dictionary in links:
			var a:Vector2=positions[str(edge.a)]
			var b:Vector2=positions[str(edge.b)]
			var role:String=str(edge.role)
			if role in ["partners","siblings"]:
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
	text_label("Parent → child",Vector2(207,705),Vector2(153,25),12,P.TEAL,false,overlay)
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

func _member_index(id:String) -> int:
	for index:int in range(household.members.size()):
		if str(household.members[index].id)==id:return index
	return 0

func _away_status(state:Dictionary) -> String:
	if str(state.get("activity",""))=="visit":
		var place:String=str(LifeNeighborhood.PLACES.get(str(state.get("destination","")),{}).get("name","across town"))
		if str(state.get("phase",""))=="returning":return "Coming home from "+place
		return "Out at "+place+" · Home soon"
	# A sentence, not a curriculum: a Lifelet inside is simply not here until the
	# household's own release tick brings them home.
	if str(state.get("activity",""))=="prison":
		return "Inside until day %d" % int(state.get("return_day",0))
	var career_state:bool=str(state.get("activity",""))=="career"
	var activity:String="work" if career_state else "school"
	if str(state.get("phase",""))=="returning":return "Coming home from "+activity
	# A Lifelet at work is at their own workplace, so the HUD names where they
	# actually are rather than a generic "work".
	if career_state and is_instance_valid(sim):
		var place:String=LifeCareers.workplace(str(sim.career.get("track","")))
		if not place.is_empty():activity=place
	var until:int=int(state.get("return_minutes",900))
	return "At %s · Back %02d:%02d" % [activity,until/60,until%60]

func _sync_away_presence() -> bool:
	var state:Dictionary=sim.get_away_state()
	var phase:String=str(state.get("phase",""))
	var changed:bool=world.set_actor_away(bound_member_id,phase=="away",not state.is_empty())
	var previous:String=str(away_phases.get(bound_member_id,""))
	if phase!=previous:
		away_phases[bound_member_id]=phase
		_clear_motion()
		if phase=="returning":
			# Re-enter the rendered lot only at its sidewalk. Saved return walks
			# retain their actual position; saved away members reappear at exit.
			if previous=="away" or not player.visible:player.position=_saved_vector(state.get("exit_position"),world.lot_exit_position(_member_index(bound_member_id)))
			var destination:Vector3=_return_destination(_member_index(bound_member_id))
			if destination.is_finite():
				_set_route(destination)
				if path.is_empty():show_notice("The return path is blocked. Clear the front garden to let this Lifelet come home.")
			else:
				# Every nearby return spot is occupied; try again shortly rather
				# than leaving the Lifelet stranded at the curb forever.
				show_notice("The front garden is crowded. Making room to come home.")
	return changed

## A clear curb spot for a returning Lifelet. The household's assigned return
## position is preferred, but if it is occupied (a housemate standing there, or
## furniture placed over it) nearby free spots are tried, so a returning member
## is not left stuck behind a body or a chair.
func _return_destination(member_index:int) -> Vector3:
	var preferred:Vector3=world.lot_return_position(member_index)
	if _wait_position_clear(preferred):return preferred
	# Keep a returning member's fallback clear of the household's other return
	# spots, so two members never resolve to the same crowded corner.
	var taken:Array[Vector3]=[]
	for member:Dictionary in household.members:
		if str(member.id)==bound_member_id:continue
		var motion:Dictionary=motion_states.get(str(member.id),_empty_motion())
		var reserved:Vector3=motion.get("wait_destination",Vector3.INF)
		if reserved.is_finite():taken.append(reserved)
	for radius:int in range(1,8):
		for x:int in range(-radius,radius+1):
			for z:int in range(-radius,radius+1):
				if absi(x)!=radius and absi(z)!=radius:continue
				var at:=preferred+Vector3(x*.75,0,z*.75)
				if not _wait_position_clear(at):continue
				if taken.any(func(point:Vector3)->bool:return point.distance_to(at)<.8):continue
				var level:int=world.point_level(at)
				if level<0:continue
				if world.construction.building_state.is_empty():
					var cell:=Vector2i(roundi(at.x*4),roundi(at.z*4))
					if not world.navigation.region.has_point(cell) or world.navigation.is_point_solid(cell):continue
					if world.path_to(player.position,at).is_empty():continue
				else:
					var route:Dictionary=world.lot_navigation.route_avoiding(LifeLotNavigation.floor_location(world.point_level(player.position),player.position),LifeLotNavigation.floor_location(level,at),traversal._occupied(bound_member_id),LifeTraversal.ROUTE_CLEARANCE)
					if not bool(route.ok):continue
				return at
	return Vector3.INF

func _advance_away_movement(delta:float) -> bool:
	var state:Dictionary=sim.get_away_state()
	if str(state.get("phase",""))!="returning" or sim.speed<=0:return false
	var moved:bool=_advance_path(delta)
	if moved and path_index>=path.size():
		_clear_motion()
		away_phases[bound_member_id]=""
		sim.complete_away_return()
	elif not moved and path.is_empty():
		# A return whose route could not start (a body or furniture now fills the
		# only way in) keeps trying from the current spot instead of standing
		# still at the curb for the rest of the day.
		var destination:Vector3=_return_destination(_member_index(bound_member_id))
		if destination.is_finite():_set_route(destination)
	return moved

func _go_to_school() -> void:
	if sim.queue_action("school_day","lot_exit",world.lot_exit_position(_member_index(bound_member_id))):refresh_hud()

func _go_to_work() -> void:
	if sim.queue_action("career_day","lot_exit",world.lot_exit_position(_member_index(bound_member_id))):refresh_hud()

func _morning_run() -> void:
	if sim.queue_action("morning_run","lot_exit",world.lot_exit_position(_member_index(bound_member_id))):refresh_hud()

func show_career_record() -> void:
	_begin_pause_overlay()
	card(Vector2(430,178),Vector2(580,553),P.WHITE,24,overlay)
	small_caps("Your working life",Vector2(467,209),Vector2(502,24),overlay)
	text_label(str(sim.career.title),Vector2(465,254),Vector2(510,46),27,P.TEAL,true,overlay)
	paragraph("Work runs weekdays, 09:00–17:00. Arrive by 10:00; late arrivals until noon reduce performance. Pay reflects actual time at work. Missing a weekday lowers performance.",Vector2(466,319),Vector2(505,114),17,P.MUTED,overlay)
	var record:Dictionary=sim.career.get("schedule",LifeCareerSchedule.fresh(sim.day))
	text_label("%d shifts completed · %d missed · %d min late"%[record.attended,record.missed,int(record.late_minutes)],Vector2(466,449),Vector2(505,35),16,P.INK,false,overlay)
	paragraph("A home shift is an optional six-hour alternative. It shares today's paid attendance with going to work.",Vector2(466,498),Vector2(505,56),14,P.MUTED,overlay)
	var remote:Button=button("Work from home",Vector2(465,580),Vector2(243,43),func():close_overlay();queue_nearest("desk","job"),false,overlay)
	remote.disabled=sim.is_away() or not sim.get_action_availability("job").available
	var change:Button=button("Find a job",Vector2(720,580),Vector2(251,43),show_careers,false,overlay)
	change.disabled=sim.is_away()
	button("Back to life",Vector2(465,653),Vector2(506,43),close_overlay,true,overlay)


func _family_parent_routes(links:Array,positions:Dictionary) -> Array:
	# Each actual edge has a separate port at both cards. Shared middle-row
	# junctions implied that every adult parented every child in a blended family.
	var routes:Array=[]
	var parents:Array=links.filter(func(edge:Dictionary)->bool:return str(edge.role)=="parent")
	for edge:Dictionary in parents:
		var outgoing:Array=parents.filter(func(other:Dictionary)->bool:return str(other.a)==str(edge.a))
		var incoming:Array=parents.filter(func(other:Dictionary)->bool:return str(other.b)==str(edge.b))
		var start_x:float=36.0+128.0*float(outgoing.find(edge)+1)/float(outgoing.size()+1)
		var end_x:float=36.0+128.0*float(incoming.find(edge)+1)/float(incoming.size()+1)
		var start:Vector2=positions[str(edge.a)]+Vector2(start_x,112)
		var finish:Vector2=positions[str(edge.b)]+Vector2(end_x,0)
		var gap:float=(finish.y-start.y)*.42
		var control_a:Vector2=start+Vector2(0,gap)
		var control_b:Vector2=finish-Vector2(0,gap)
		var points:=PackedVector2Array()
		for step:int in range(33):
			var t:float=float(step)/32.0;var reverse:float=1.0-t
			points.append(reverse*reverse*reverse*start+3.0*reverse*reverse*t*control_a+3.0*reverse*t*t*control_b+t*t*t*finish)
		routes.append({"a":str(edge.a),"b":str(edge.b),"points":points})
	return routes

func invite_neighbor(id:String)->void:
	if residents.home_visit.invite(id):close_overlay();_refresh_guest_status()

func _refresh_guest_status()->void:
	if not is_instance_valid(ui) or not residents:return
	if not residents.home_visit.ringing():
		if is_instance_valid(bell_status_card):bell_status_card.queue_free()
		bell_status_card=null
	if residents.home_visit.ringing():
		_refresh_bell_status()
		return
	if mode!="live" or not residents.home_visit.active():
		if is_instance_valid(guest_status_card):guest_status_card.queue_free()
		guest_status_card=null;return
	if not is_instance_valid(guest_status_card):
		guest_status_card=card(Vector2(1038,206),Vector2(374,126),P.WHITE,16)
		guest_status_card.name="GuestStatus"
		guest_status_text=text_label("",Vector2(14,10),Vector2(346,54),15,P.INK,true,guest_status_card)
		guest_status_text.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
		guest_welcome_button=button("Welcome in",Vector2(14,76),Vector2(166,36),func():residents.home_visit.welcome(household.selected_id()),true,guest_status_card)
		guest_welcome_button.name="WelcomeGuest"
		var goodbye=button("Say goodbye",Vector2(192,76),Vector2(168,36),func():residents.home_visit.goodbye(),false,guest_status_card)
		goodbye.name="GoodbyeGuest"
	var visit:Dictionary=residents.home_visit.state
	var phase:String=str(visit.phase)
	var label:String={"arriving":"Walking over","waiting":"At your door","entering":"Coming inside","inside":"Visiting your home","leaving":"Heading home"}.get(phase,"")
	var welcoming:bool=phase=="waiting" and not visit.greeting.is_empty() and str(residents.home_visit._welcome_action.get("phase",""))=="active"
	if welcoming:label="Being welcomed"
	if residents.home_visit.meal.active():label=residents.home_visit.meal.label()
	guest_status_text.text=str(LifeResidents.PEOPLE[str(visit.guest)].name)+" · "+label
	if phase=="waiting" and not welcoming:
		var remaining:int=maxi(0,ceili(float(visit.arrived_at)+LifeHomeVisit.WELCOME_MINUTES-residents.home_visit._now()))
		guest_status_text.text+="\nWelcome within %d game min" % remaining
	elif phase=="inside":
		var remaining:int=maxi(0,ceili(float(visit.phase_at)+LifeHomeVisit.STAY_MINUTES-residents.home_visit._now()))
		guest_status_text.text+="\nLeaving in %d game min" % remaining
	guest_welcome_button.visible=phase=="waiting"
	guest_welcome_button.disabled=phase!="waiting" or not visit.greeting.is_empty()
	guest_welcome_button.text="Welcoming" if welcoming else ("Welcome queued" if not visit.greeting.is_empty() else "Welcome in")
	var goodbye_button:Button=guest_status_card.get_node("GoodbyeGuest")
	goodbye_button.position.x=192 if phase=="waiting" else 14
	goodbye_button.size.x=168 if phase=="waiting" else 346
	goodbye_button.disabled=phase=="leaving"

## The doorbell card: who rang, how long they will wait, and the household's two
## answers. Turning them away is always available; letting them in is refused
## with its reason when the visit cannot start.
func _refresh_bell_status()->void:
	var visit:LifeHomeVisit=residents.home_visit
	if not is_instance_valid(bell_status_card):
		bell_status_card=card(Vector2(1038,206),Vector2(374,148),P.WHITE,16)
		bell_status_card.name="DoorbellStatus"
		bell_status_text=text_label("",Vector2(14,10),Vector2(346,54),15,P.INK,true,bell_status_card)
		bell_status_text.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
		var let_in:Button=button("Let them in",Vector2(14,74),Vector2(166,34),func():answer_doorbell("let_in"),true,bell_status_card)
		let_in.name="DoorbellLetIn"
		bell_let_in_button=let_in
		var away:Button=button("Ask them to leave",Vector2(192,74),Vector2(168,34),func():answer_doorbell("turn_away"),false,bell_status_card)
		away.name="DoorbellTurnAway"
		bell_turn_away_button=away
	var bell:Dictionary=visit.bell
	if bell.is_empty():return
	var guest:String=str(bell.guest)
	var waited:int=maxi(0,ceili(float(bell.rang_at)+LifeHomeVisit.RING_WAIT_MINUTES-visit._bell_now()))
	bell_status_text.text="%s · At the door\nWaiting %d game min" % [str(LifeResidents.PEOPLE[guest].name),waited]
	var let_in_reason:String=visit.requirement(guest)
	bell_let_in_button.disabled=not let_in_reason.is_empty()
	bell_let_in_button.tooltip_text=let_in_reason if not let_in_reason.is_empty() else "Welcome them inside the way you would an invited guest."
	bell_turn_away_button.disabled=false

func answer_doorbell(choice:String) -> void:
	var visit:LifeHomeVisit=residents.home_visit
	if choice=="let_in":visit.let_in()
	else:visit.turn_away()
	_refresh_guest_status()
	refresh_hud()

func _cancel_guest_conversations(guest:String,retained:Dictionary) -> void:
	_store_motion()
	var previous:String=bound_member_id
	for member:Dictionary in household.members:
		for index:int in range(member.sim.action_queue.size()-1,-1,-1):
			var action:Dictionary=member.sim.action_queue[index]
			if str(action.get("target_id",""))!=guest or str(action.get("id","")) not in LifeSim.SOCIAL_ACTIONS or is_same(action,retained):continue
			_bind_member(str(member.id));cancel_current_action(index);_store_motion()
	_bind_member(previous)
