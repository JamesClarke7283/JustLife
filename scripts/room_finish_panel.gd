extends RefCounted
## The clicked room stays selected while the player reviews finishes and cost.
const Tools=preload("res://scripts/build_buy_panel.gd")
const P=preload("res://scripts/palette.gd")
const Edits=preload("res://scripts/building_edits.gd")

static func show_room(app:Node,point:Vector3,working:Dictionary={}) -> void:
	if app.mode!="build" or not point.is_finite():return
	var current:Dictionary=app.build_transactions.current()
	if not bool(current.ok):app.show_notice(str(current.error));return
	var region:Dictionary=Edits._enclosed_cells(current.state,app.world.view_level,Vector2(point.x,point.z))
	if region.is_empty() or bool(region.get("escaped",true)):
		app.show_notice("Choose the floor inside a walled room.");return
	var choice:Dictionary={"mode":"","style":"plain","color":"decfaf","level":app.world.view_level}
	choice.merge(working,true)
	app.close_overlay();app.overlay_open=true;app.dismiss_layer()
	var origin:=Vector2(220,175)
	app.card(origin,Vector2(1000,550),P.WHITE,20,app.overlay).name="RoomFinishPanel"
	app.text_label("Room finishes",origin+Vector2(28,20),Vector2(944,40),28,P.INK,true,app.overlay)
	app.text_label("Choose a finish for the room you clicked. Review the price before applying it.",origin+Vector2(28,66),Vector2(944,38),15,P.MUTED,false,app.overlay)
	var body:=VBoxContainer.new();body.add_theme_constant_override("separation",16)
	app.rect(body,origin+Vector2(28,126),Vector2(944,300),app.overlay)
	var modes:HBoxContainer=Tools.row(body)
	for mode:String in ["paint","floor"]:
		var next:Dictionary=choice.duplicate(true)
		next.mode=mode;next.style="solid" if mode=="paint" else "plain";next.color="8faf9f" if mode=="paint" else "decfaf"
		Tools.action(app,modes,"Paint Room" if mode=="paint" else "Floor colours & styles",show_room.bind(app,point,next),str(choice.mode)==mode,260).name="RoomFinish_"+mode
	if str(choice.mode)=="paint":
		var styles:HBoxContainer=Tools.row(body)
		for style:String in Edits.HOME_PAINT_STYLES:
			var next:Dictionary=choice.duplicate(true);next.style=style
			Tools.action(app,styles,style.replace("_"," ").capitalize(),show_room.bind(app,point,next),str(choice.style)==style,180).name="RoomStyle_"+style
	elif str(choice.mode)=="floor":
		var finishes:HBoxContainer=Tools.row(body)
		for entry:Array in [["Warm oak","oak","cfa97e"],["Pale stone","stone","dcd6c6"],["Walnut","walnut","896953"]]:
			var next:Dictionary=choice.duplicate(true);next.style=entry[1];next.color=entry[2]
			Tools.action(app,finishes,entry[0],show_room.bind(app,point,next),str(choice.style)==entry[1],180).name="RoomStyle_"+str(entry[1])
		var carpets:HBoxContainer=Tools.row(body)
		for style:String in Edits.CARPET_STYLES:
			var next:Dictionary=choice.duplicate(true);next.style=style
			if str(next.color) not in Tools.CARPET_COLORS:next.color=Tools.CARPET_COLORS[0]
			Tools.action(app,carpets,style.capitalize()+" carpet",show_room.bind(app,point,next),str(choice.style)==style,180).name="RoomStyle_"+style
	if str(choice.mode)=="paint" or str(choice.style) in Edits.CARPET_STYLES and str(choice.mode)=="floor":
		var colors:Array=Tools.COLORS if str(choice.mode)=="paint" else Tools.CARPET_COLORS
		Tools.swatches(app,body,colors,str(choice.color),func(color:String):
			var next:Dictionary=choice.duplicate(true);next.color=color;show_room(app,point,next),"RoomColor_")
	app.button("Cancel",origin+Vector2(28,480),Vector2(220,42),app.close_overlay,false,app.overlay)
	if str(choice.mode).is_empty():return
	# Finishes do not change the room geometry. Price them without rebuilding
	# the entire navigation graph on each swatch; Apply performs the full check.
	var quote:Dictionary=Edits.propose(current.state,operation(point,choice),app.sim.funds)
	var available:bool=bool(quote.ok)
	app.text_label("This room · ℒ%d" % int(quote.cost) if available else str(quote.error),origin+Vector2(28,390),Vector2(944,68),15,P.TEAL if available else P.CORAL,false,app.overlay)
	var apply:Button=app.button("Apply to this room",origin+Vector2(674,480),Vector2(298,42),func():
		var checked:Dictionary=app.build_transactions.prepare(operation(point,choice),true)
		if not bool(checked.ok):app.show_notice(str(checked.error));return
		app.close_overlay();app.on_construction({"valid":true,"build_quote":checked}),true,app.overlay)
	apply.name="RoomFinishApply";apply.disabled=not available

static func operation(point:Vector3,choice:Dictionary)->Dictionary:
	var result:Dictionary={"op":"structure","level":int(choice.level),"px":point.x,"pz":point.z,"material":str(choice.color)}
	if str(choice.mode)=="paint":result.merge({"tool":"paint","scope":"room","palette":"home","pattern":str(choice.style)})
	elif str(choice.style) in Edits.CARPET_STYLES:result.merge({"tool":"carpet","style":str(choice.style)})
	else:result["tool"]="floor_finish"
	return result
