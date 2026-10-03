extends RefCounted
## Container-owned rows keep every tool and swatch in its own hit rectangle.
const P=preload("res://scripts/palette.gd")
const Edits=preload("res://scripts/building_edits.gd")
const COLORS:Array[String]=["eae7d7","8faf9f","e6d8c5","c8d7e0","d9b7a3","7d8a99","efd9a0","a3ad7a","f4b6c8","6aa6e0"]
const CARPET_COLORS:Array[String]=["decfaf","8faf9f","e6d8c5","c8d7e0","d9b7a3","7d8a99","efd9a0","a3ad7a","f4b6c8","6aa6e0"]
static func row(parent:Node)->HBoxContainer:
	var box:=HBoxContainer.new();box.add_theme_constant_override("separation",8);parent.add_child(box);return box
static func action(app:Node,parent:Node,label:String,callback:Callable,selected:bool=false,width:float=124)->Button:
	var button:Button=app.button(label,Vector2.ZERO,Vector2(width,36),callback,selected,parent)
	button.custom_minimum_size=Vector2(width,36);app.compact_button(button);return button
static func swatches(app:Node,parent:Node,colors:Array,current:String,choose:Callable,prefix:String)->void:
	var strip:HBoxContainer=row(parent)
	for color:String in colors:
		var chip:Button=action(app,strip,"•" if color==current else "",choose.bind(color),false,42)
		chip.name=prefix+color;chip.tooltip_text="#"+color
		chip.add_theme_stylebox_override("normal",P.panel(Color(color),10,P.TEAL if color==current else Color.WHITE,3))
		chip.add_theme_stylebox_override("hover",P.panel(Color(color).lightened(.1),10,P.TEAL,3))
static func draw(app:Node)->void:
	var construction:Node=app.world.construction
	var scroll:=ScrollContainer.new();scroll.name="StructureTools"
	scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_AUTO;scroll.vertical_scroll_mode=ScrollContainer.SCROLL_MODE_AUTO
	app.rect(scroll,Vector2(300,718),Vector2(1108,164))
	var body:=VBoxContainer.new();body.name="StructureToolsBody";body.add_theme_constant_override("separation",8);scroll.add_child(body)
	var tools:HBoxContainer=row(body)
	for entry:Array in [["Wall","wall"],["Room","room"],["Door","door"],["Floor slab","floor"],["Stairs","stairs"],["Grab wall","grab"],["Delete","delete"]]:
		var tool:String=entry[1]
		var button:Button=action(app,tools,entry[0],app.begin_construction.bind(tool),construction.tool==tool)
		button.name="BuildTool_"+tool
		if tool=="delete":button.tooltip_text="Delete a wall, floor, stairs or furnishing with a refund."
		if tool=="grab":button.tooltip_text="Move a wall; connected walls and outward floor extensions follow."
	action(app,tools,"Upstairs presets",app.show_upstairs_presets,false,148).name="UpstairsPresets"
	var finishes:HBoxContainer=row(body)
	action(app,finishes,"Paint Room",func():
		construction.paint_scope="room"
		if construction.paint_palette=="home" and not Edits.HOME_PAINT_STYLES.has(construction.paint_pattern):construction.paint_pattern="solid"
		app.begin_construction("paint"),construction.tool=="paint").name="BuildTool_paint"
	action(app,finishes,"Carpet",app.begin_construction.bind("carpet"),construction.tool=="carpet").name="BuildTool_carpet"
	for option:Array in [["Warm oak","cfa97e"],["Pale stone","dcd6c6"],["Walnut","896953"]]:
		action(app,finishes,option[0],app.change_floor.bind(option[1]),construction.tool=="floor_finish" and construction.floor_finish_color==option[1])
	action(app,finishes,"Full house" if app.world.cutaway else "Lower walls",app.toggle_house_view)
	var storey:Button=action(app,finishes,"Add storey",app.show_add_storey,false,124)
	storey.name="AddStorey"
	storey.tooltip_text="Raise the house a storey: a new floor, the outer walls and the roof go up together. Four storeys at most."
	if construction.tool=="paint":
		var styles:HBoxContainer=row(body)
		for palette:String in ["home","nursery"]:
			action(app,styles,palette.capitalize(),func():
				construction.paint_palette=palette;construction.paint_pattern="solid" if palette=="home" else "stars";app.draw_live(),construction.paint_palette==palette,90)
		var nursery:Dictionary=LifeCatalog.get_item("nursery_paint")
		var patterns:Array=Edits.HOME_PAINT_STYLES if construction.paint_palette=="home" else LifeCatalogVariants.styles(nursery)
		for style:String in patterns:
			action(app,styles,style.replace("_"," ").capitalize(),func():construction.paint_pattern=style;app.draw_live(),construction.paint_pattern==style,120).name="PaintStyle_"+style
		var colors:Array=COLORS if construction.paint_palette=="home" else LifeCatalogVariants.colors(nursery)
		swatches(app,body,colors,construction.paint_material,func(color:String):construction.paint_material=color;app.draw_live(),"PaintColor_")
	elif construction.tool=="carpet":
		var styles:HBoxContainer=row(body)
		for style:String in Edits.CARPET_STYLES:
			action(app,styles,style.capitalize(),func():construction.carpet_style=style;app.draw_live(),construction.carpet_style==style).name="CarpetStyle_"+style
		swatches(app,body,CARPET_COLORS,construction.carpet_color,func(color:String):construction.carpet_color=color;app.draw_live(),"CarpetColor_")
	var roofs:HBoxContainer=row(body)
	for entry:Array in [["New roof","roof"],["Edit roof","roof_edit"],["Delete roof","roof_remove"]]:action(app,roofs,entry[0],app.begin_construction.bind(entry[1]))
	for style:String in ["gabled","hipped","flat","mansard","a_frame"]:
		action(app,roofs,style.replace("_"," ").capitalize(),app.set_roof_style.bind(style),construction.roof_style==style,124).name="RoofStyle_"+style
	var roof_options:HBoxContainer=row(body)
	for option:Array in [["Low",.25],["Medium",.5],["Steep",.75]]:action(app,roof_options,option[0],app.set_roof_pitch.bind(option[1]),is_equal_approx(construction.roof_pitch,option[1]),90)
	app.roof_visibility_button=action(app,roof_options,"Hide roofs" if construction.roofs_visible else "Show roofs",func():
		construction.set_roof_visibility(not construction.roofs_visible)
		if construction.roofs_visible:app.world.set_cutaway(false)
		app.draw_live())
	for color:String in ["57736a","56606b","8b5a3c","4a5568","c4a574","6b3a4a","2f4f4f","b87333"]:
		var chip:Button=action(app,roof_options,"",app.set_roof_finish.bind(color),false,40)
		chip.name="RoofTint_"+color;chip.tooltip_text="#"+color
		chip.add_theme_stylebox_override("normal",P.panel(Color(color),10,P.TEAL if construction.roof_material==color else Color.WHITE,2))
