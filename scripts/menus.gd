extends RefCounted
class_name LifeMenus
## Main menu and a named save library. All screens use the game's shared UI theme.
const P=preload("res://scripts/palette.gd")
var app:Node
var picker_mode:String="load"
var picker_selection:String=""
var name_input:LineEdit
var save_draft:String=""

func _init(owner_app:Node) -> void:
	app=owner_app

func main_menu() -> void:
	app.clear_ui()
	var veil=ColorRect.new();veil.color=Color("f8f6ef")
	app.rect(veil,Vector2.ZERO,Vector2(504,900))
	app.logo(Vector2(55,44))
	app.small_caps("A life made by you",Vector2(61,179),Vector2(370,27))
	app.text_label("Little moments.\nEndless stories.",Vector2(56,218),Vector2(426,150),54,P.INK,true)
	app.paragraph("Make a home, find your people, and see where the everyday takes you.",Vector2(62,405),Vector2(359,86),20)
	var continuing:bool=app.has_active_game or not LifeSaveLibrary.latest_id().is_empty()
	var resume=app.button("Continue your life  →",Vector2(60,541),Vector2(374,57),app.continue_life,true)
	resume.disabled=not continuing
	app.button("New game",Vector2(60,614),Vector2(374,51),app.new_game)
	app.button("Saved lives",Vector2(60,678),Vector2(374,51),func():show_picker("load"))
	app.button("Sound: "+("on" if app.sound_enabled else "off"),Vector2(60,789),Vector2(181,41),func():app.set_sound(not app.sound_enabled);main_menu())
	app.button("Quit",Vector2(253,789),Vector2(181,41),func():app.get_tree().quit())
	app.small_caps("JustLife · an original life simulation",Vector2(61,853),Vector2(393,22))
	app.card(Vector2(905,65),Vector2(447,124),Color("fffdf7"),20)
	app.small_caps("Make room for your story",Vector2(930,82),Vector2(395,22))
	app.text_label("Welcome to Juniper Lane.",Vector2(929,112),Vector2(396,49),28,P.INK,true)
	app.card(Vector2(574,756),Vector2(777,92),Color("fffdf7"),18)
	app.text_label("Create. Connect. Come home.",Vector2(600,772),Vector2(710,37),28,P.INK,true)
	app.text_label("Your Lifelets. Your neighborhood. Your next chapter.",Vector2(602,814),Vector2(707,23),15,P.MUTED)

func shade() -> void:
	var bg=ColorRect.new();bg.color=Color(.08,.17,.15,.52)
	app.rect(bg,Vector2.ZERO,Vector2(1440,900),app.overlay)

func show_picker(which:String="load",selected:String="") -> void:
	if is_instance_valid(name_input):save_draft=name_input.text
	picker_mode=which
	app._begin_pause_overlay()
	shade()
	var slots:Array=LifeSaveLibrary.list_saves()
	var storage_error:String=LifeSaveLibrary.storage_error()
	if selected.is_empty():selected=picker_selection
	if not slots.any(func(s:Dictionary):return str(s.id)==selected):selected="" if slots.is_empty() else str(slots[0].id)
	picker_selection=selected
	app.card(Vector2(195,97),Vector2(1050,706),P.WHITE,24,app.overlay)
	app.small_caps("A place for every story",Vector2(229,116),Vector2(950,28),app.overlay)
	app.text_label("Save your life." if which=="save" else "Your saved lives.",Vector2(227,155),Vector2(842,61),41,P.INK,true,app.overlay)
	app.button("Close",Vector2(1106,125),Vector2(102,41),app.close_overlay,false,app.overlay)
	app.paragraph("Choose a life to return to, or keep a fresh chapter of your current household." if which=="save" else "Pick up exactly where you left off.",Vector2(232,230),Vector2(929,39),16,P.MUTED,app.overlay)
	var scroll=ScrollContainer.new();app.rect(scroll,Vector2(228,290),Vector2(531,381),app.overlay)
	var column=VBoxContainer.new();column.add_theme_constant_override("separation",12);scroll.add_child(column)
	var selected_slot:Dictionary={}
	var selected_row:Control
	for slot:Dictionary in slots:
		if str(slot.id)==selected:selected_slot=slot
		var row=Control.new();row.custom_minimum_size=Vector2(510,104);column.add_child(row)
		if str(slot.id)==selected:selected_row=row
		var b=app.button("",Vector2.ZERO,Vector2(506,104),func():show_picker(which,str(slot.id)),false,row)
		b.set_meta("save_id",str(slot.id))
		if str(slot.id)==selected:b.add_theme_stylebox_override("normal",P.panel(P.PALE,13,P.TEAL,2))
		var title:Label=app.text_label(str(slot.name),Vector2(20,12),Vector2(465,33),23,P.INK,true,row)
		title.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
		title.size=Vector2(465,33)
		app.text_label("Day %d  ·  %s Lifelet%s" % [int(slot.get("day",1)),str(slot.get("members",[]).size()),"" if slot.get("members",[]).size()==1 else "s"],Vector2(22,49),Vector2(462,24),13,P.TEAL,false,row)
		app.text_label(_date_text(slot.get("saved_at",0)),Vector2(22,76),Vector2(460,21),12,P.MUTED,false,row)
	if is_instance_valid(selected_row):reveal_save.call_deferred(scroll,selected_row)
	if not storage_error.is_empty():
		app.text_label("Your saves need attention.",Vector2(240,338),Vector2(497,42),28,P.INK,true,app.overlay)
		app.paragraph(storage_error,Vector2(243,399),Vector2(451,150),17,P.MUTED,app.overlay)
	elif slots.is_empty():
		app.text_label("Your first story starts here.",Vector2(240,338),Vector2(497,42),28,P.INK,true,app.overlay)
		app.paragraph("Saved households will appear here with the day, everyone who lives there, and a glimpse of home.",Vector2(243,399),Vector2(451,95),17,P.MUTED,app.overlay)
		if which=="load":app.button("Create a household",Vector2(244,532),Vector2(440,48),app.new_game,true,app.overlay)
	app.line(Vector2(779,288),Vector2(1,389),app.overlay)
	if not selected_slot.is_empty():
		show_preview(selected_slot,Vector2(810,292),Vector2(396,219))
		var names:String=", ".join(PackedStringArray(selected_slot.get("members",[])))
		if not bool(selected_slot.get("valid",true)):names=str(selected_slot.get("error","This save could not be read."))
		var members_scroll=ScrollContainer.new();app.rect(members_scroll,Vector2(813,530),Vector2(390,77),app.overlay)
		var members_text=app.paragraph(names,Vector2.ZERO,Vector2(368,76),17,P.INK,members_scroll)
		members_text.custom_minimum_size.x=368
		members_text.tooltip_text=names
		var load_button=app.button("Load selected life  →",Vector2(811,619),Vector2(393,49),func():app.request_load_save(selected),true,app.overlay)
		load_button.disabled=not bool(selected_slot.get("valid",true))
		var erase=app.button("Delete save…",Vector2(1028,718),Vector2(175,42),func():confirm_delete(selected_slot),false,app.overlay)
		erase.add_theme_color_override("font_color",Color("a84f43"))
	if which=="save":
		app.line(Vector2(230,686),Vector2(978,1),app.overlay)
		name_input=LineEdit.new();name_input.max_length=60;name_input.placeholder_text="Name this life"
		name_input.text=save_draft if not save_draft.is_empty() else (app.active_save_name if not app.active_save_name.is_empty() else str(app.sim.character.name)+"'s story")
		app.rect(name_input,Vector2(230,714),Vector2(348,47),app.overlay)
		app.button("Save as new",Vector2(595,714),Vector2(174,47),func():write_save("",name_input.text),true,app.overlay)
		if not selected_slot.is_empty():app.button("Overwrite…",Vector2(785,714),Vector2(167,47),func():confirm_overwrite(selected_slot),false,app.overlay)
	elif not selected_slot.is_empty():
		app.paragraph("Each save keeps its own household, home, and story.",Vector2(234,714),Vector2(702,50),15,P.MUTED,app.overlay)

func show_preview(slot:Dictionary,p:Vector2,s:Vector2) -> void:
	app.card(p,s,P.PALE,13,app.overlay)
	var path:String=str(slot.get("preview_path",""))
	if not path.is_empty() and FileAccess.file_exists(path):
		var img:Image=Image.load_from_file(path)
		if img and not img.is_empty():
			var texture=TextureRect.new();texture.texture=ImageTexture.create_from_image(img)
			texture.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;texture.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_COVERED
			texture.clip_contents=true;app.rect(texture,p+Vector2(3,3),s-Vector2(6,6),app.overlay)
			return
	app.text_label("A life worth returning to.",p+Vector2(22,77),s-Vector2(44,132),26,P.TEAL,true,app.overlay)

func _date_text(value:Variant) -> String:
	if value is String:return "Saved "+str(value).replace("T"," · ").left(24)
	if value is float or value is int:
		if float(value)>0:return "Saved "+Time.get_datetime_string_from_unix_time(int(value)).replace("T"," · ")
	return "Earlier save"

func confirm_delete(slot:Dictionary) -> void:
	if is_instance_valid(name_input):save_draft=name_input.text
	app._begin_pause_overlay();shade()
	app.card(Vector2(447,227),Vector2(546,425),P.WHITE,24,app.overlay)
	app.small_caps("Delete saved life",Vector2(480,249),Vector2(477,24),app.overlay)
	app.text_label("Say goodbye to this save?",Vector2(477,293),Vector2(480,54),31,P.INK,true,app.overlay)
	app.paragraph('“%s”' % str(slot.name),Vector2(482,366),Vector2(472,68),20,P.INK,app.overlay)
	var detail:Label=app.text_label("Day %d · %d Lifelets" % [int(slot.get("day",1)),slot.get("members",[]).size()],Vector2(483,438),Vector2(470,27),15,P.TEAL,false,app.overlay)
	detail.tooltip_text=", ".join(PackedStringArray(slot.get("members",[])))
	app.paragraph("This permanently removes this saved file. Your other saves and the household currently playing are kept.",Vector2(482,478),Vector2(472,58),14,P.MUTED,app.overlay)
	app.button("Keep save",Vector2(481,565),Vector2(222,49),func():show_picker(picker_mode,str(slot.id)),true,app.overlay).grab_focus()
	var erase=app.button("Delete permanently",Vector2(716,565),Vector2(241,49),func():delete_confirmed(str(slot.id)),false,app.overlay)
	erase.add_theme_color_override("font_color",Color("a84f43"))

func delete_confirmed(id:String) -> void:
	var result:Dictionary=LifeSaveLibrary.delete_slot(id)
	if result.ok:
		if app.active_save_id==id:app.active_save_id="";app.active_save_name=""
		picker_selection=""
	show_picker(picker_mode)
	app.show_notice("The selected save was deleted." if result.ok else str(result.get("error","The save could not be deleted.")))

func confirm_overwrite(slot:Dictionary) -> void:
	var chosen_name:String=name_input.text
	save_draft=chosen_name
	app._begin_pause_overlay();shade()
	app.card(Vector2(461,281),Vector2(519,313),P.WHITE,24,app.overlay)
	app.text_label("Replace this saved chapter?",Vector2(491,309),Vector2(455,57),29,P.INK,true,app.overlay)
	app.paragraph('“%s” will be replaced with your current household.' % str(slot.name),Vector2(495,397),Vector2(445,75),18,P.INK,app.overlay)
	app.button("Cancel",Vector2(494,508),Vector2(204,48),func():show_picker("save",str(slot.id)),true,app.overlay)
	app.button("Replace save",Vector2(714,508),Vector2(232,48),func():write_save(str(slot.id),chosen_name),false,app.overlay)

func write_save(id:String,title:String) -> void:
	if title.strip_edges().is_empty():app.show_notice("Give this life a name first.");return
	if app.save_game(id,title):app.close_overlay()

func reveal_save(scroll:ScrollContainer,row:Control) -> void:
	await app.get_tree().process_frame
	if is_instance_valid(scroll) and is_instance_valid(row):scroll.ensure_control_visible(row)
