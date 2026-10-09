extends RefCounted
class_name LifeKitchenFurnishings
## Cabinet geometry and modular join dimensions, shared by the shop and world.
const STYLES: Array[String] = ["shaker", "slab", "farmhouse", "drawers", "slatted"]
const COLORS: Array[String] = ["417a71", "f4f1ea", "e6d8c5", "ab7951", "624435", "1f3b6b", "3a3d42", "8faf9f", "c97c66", "c9a05a"]
const STYLE_LABELS := {"shaker":"Shaker", "slab":"Modern slab", "farmhouse":"Farmhouse", "drawers":"Drawer stack", "slatted":"Slatted wood"}
const UNITS: Array[String] = ["counter", "corner_counter", "fridge", "stove", "sink"]
const SURFACES := {"counter":.952, "corner_counter":.952, "dining":.847, "table":.527, "coffee_table":.484, "desk":.872, "study_desk":.715}

static func cabinet(kind: String) -> bool:
	return kind in ["counter", "corner_counter", "sink", "fridge"]

static func model_scale(kind: String) -> Vector3:
	# The appliance meshes were authored narrower than their modular footprint.
	# Match their joining edge while retaining the oven's animated child nodes.
	if kind == "fridge":return Vector3(.9/.87,1,1)
	if kind == "stove":return Vector3(1.05/1.02,1,1)
	if kind == "coffee_machine":return Vector3(.55,.55,.55)
	return Vector3.ONE

static func _box(parent: Node3D, label: String, at: Vector3, size: Vector3, color: String) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = label+"_%d"%parent.get_child_count()
	var mesh := BoxMesh.new();mesh.size = size;node.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(color);material.roughness = .62
	node.material_override = material;node.position = at;parent.add_child(node)
	return node

static func build(kind: String, variant: Dictionary) -> Node3D:
	if kind == "fridge":return _fridge(variant)
	if kind == "sink" and str(variant.get("size","")) in ["bathroom_single","bathroom_double"]:return _bathroom_sink(variant)
	var root := Node3D.new();root.name = "KitchenCabinet"
	var corner: bool = kind == "corner_counter"
	var width: float = .8 if corner else 1.05
	var color: String = str(variant.get("color", "417a71"))
	var style: String = str(variant.get("style", "shaker"))
	_box(root,"ToeKick",Vector3(0,.065,-.025),Vector3(width-.08,.13,.67),"383735")
	_box(root,"TintCarcass",Vector3(0,.49,-.025),Vector3(width,.72,.75),color)
	_box(root,"StoneWorktop",Vector3(0,.9,0),Vector3(width,.10,.8),"eee8d9")
	_front(root,style,color,width-.05)
	if corner:
		# A square return has two finished working faces and a continuous top.
		var return_face := Node3D.new();return_face.name = "CornerReturn";root.add_child(return_face)
		return_face.rotation_degrees.y = 90
		_front(return_face,style,color,.75)
	if kind == "sink":
		# Keep the authored basin and brass tap exactly where their use poses
		# expect them; only the cabinet beneath gets a new style and finish.
		var fittings:Node3D=load("res://assets/models/sink.glb").instantiate()
		for mesh:MeshInstance3D in fittings.find_children("*","MeshInstance3D",true,false):
			if str(mesh.name).begins_with("Basin") or str(mesh.name).begins_with("Tap"):
				# Detach these authored pieces from their inherited scene. Packing
				# a partially deleted scene would restore its old cabinet in previews.
				mesh.owner=null;mesh.get_parent().remove_child(mesh);root.add_child(mesh)
		fittings.free()
	return root

static func _bathroom_sink(variant:Dictionary)->Node3D:
	var root:=Node3D.new();root.name="BathroomVanity"
	var double:bool=str(variant.get("size",""))=="bathroom_double"
	var width:float=1.4 if double else .7
	var depth:float=.55 if double else .45
	var color:String=str(variant.get("color","417a71"))
	_box(root,"TintVanity",Vector3(0,.46,0),Vector3(width-.04,.78,depth-.04),color)
	_box(root,"StoneWorktop",Vector3(0,.90,0),Vector3(width,.10,depth),"eee8d9")
	for x:float in ([-.35,.35] if double else [0.]):
		# Separate bowl rims, dark basin bottoms and brass taps make the two
		# wash places readable instead of stretching a single sink across them.
		_box(root,"BasinBottom",Vector3(x,.955,0),Vector3(.40,.015,.24),"c8d7d3")
		for side:float in [-1.,1.]:
			_box(root,"BasinRim",Vector3(x+side*.215,.975,0),Vector3(.025,.04,.29),"faf6ea")
			_box(root,"BasinRim",Vector3(x,.975,side*.14),Vector3(.455,.04,.025),"faf6ea")
		_box(root,"TapStem",Vector3(x,1.03,-depth*.38),Vector3(.025,.16,.025),"c8a562")
		_box(root,"TapSpout",Vector3(x,1.105,-depth*.23),Vector3(.025,.025,depth*.34),"c8a562")
	return root

static func _fridge(variant:Dictionary) -> Node3D:
	var root:Node3D=load("res://assets/models/fridge.glb").instantiate()
	root.name="KitchenFridge"
	var color:String=str(variant.get("color","417a71"))
	var style:String=str(variant.get("style","shaker"))
	# The authored carcass is .77 m deep inside a .85 m placement footprint.
	# Shift it back by .04 m, so its physical back meets that footprint edge.
	# The door and handle retain their relative geometry and remain in front.
	for child:Node in root.get_children():
		if child is Node3D:child.position.z-=.04
	for mesh:MeshInstance3D in root.find_children("*","MeshInstance3D",true,false):
		var label:String=str(mesh.name)
		# A pinned note rests on the raised finish rather than being cut into
		# stripes by slats or crossed by the farmhouse braces.
		if label.begins_with("Note") and style!="slab":mesh.position.z+=.024
		if label.begins_with("Refrigerator") or label.begins_with("Freezer") or label.begins_with("Fresh"):
			mesh.name="Tint"+label
			var material:=StandardMaterial3D.new();material.albedo_color=Color(color);material.roughness=.62
			mesh.material_override=material
	# Finish the real freezer and fresh-food doors, keeping their seam and
	# working handles visible in every style.
	for door:Vector2 in [Vector2(1.56,.50),Vector2(.65,1.23)]:
		var y:float=door.x;var height:float=door.y
		if style in ["shaker","farmhouse"]:
			for side:float in [-1.0,1.0]:
				_box(root,"TintDoorStile",Vector3(side*.35,y,.412),Vector3(.045,height-.06,.022),color)
				_box(root,"TintDoorRail",Vector3(0,y+side*(height*.5-.05),.412),Vector3(.74,.045,.022),color)
			if style == "farmhouse":
				for direction:float in [-1.0,1.0]:
					var brace:=_box(root,"TintCrossBrace",Vector3(0,y,.414),Vector3(.032,sqrt(.62*.62+pow(height-.15,2)),.022),color)
					brace.rotation.z=direction*atan2(.62,height-.15)
		elif style == "drawers":
			for fraction:float in [-.25,.25]:
				_box(root,"DrawerSeam",Vector3(0,y+height*fraction,.414),Vector3(.74,.012,.018),"383735")
		elif style == "slatted":
			for index:int in 9:
				_box(root,"TintDoorSlat",Vector3(-.34+float(index)*.085,y,.415),Vector3(.04,height-.06,.025),color)
	return root

static func _front(root: Node3D, style: String, color: String, width: float) -> void:
	if style == "drawers":
		for index: int in 3:
			var y: float = .24 + float(index)*.23
			_box(root,"TintDrawer%d"%index,Vector3(0,y,.369),Vector3(width,.21,.035),color)
			_box(root,"DrawerPull%d"%index,Vector3(0,y+.055,.405),Vector3(width*.36,.023,.04),"c8a562")
		return
	for side: int in 2:
		var x: float = (-1 if side == 0 else 1)*width*.25
		var span: float = width*.5-.015
		_box(root,"TintDoor%d"%side,Vector3(x,.47,.37),Vector3(span,.68,.025),color)
		if style in ["shaker", "farmhouse"]:
			for rail: float in [-1.0,1.0]:
				_box(root,"TintStile",Vector3(x+rail*(span*.5-.025),.47,.39),Vector3(.045,.68,.02),color)
				_box(root,"TintRail",Vector3(x,.47+rail*.315,.39),Vector3(span,.045,.02),color)
			if style == "farmhouse":
				for direction: float in [-1.0,1.0]:
					var brace := _box(root,"TintCrossBrace",Vector3(x,.47,.398),Vector3(.032,sqrt(pow(span-.08,2)+.52*.52),.018),color)
					brace.rotation.z = direction*atan2(span-.08,.52)
		elif style == "slatted":
			for index: int in 7:
				_box(root,"TintSlat",Vector3(x-span*.43+float(index)*span*.143,.47,.395),Vector3(span*.075,.66,.025),color)
		var handle_y: float = .62 if style == "slab" else .68
		_box(root,"CabinetPull",Vector3(x,handle_y,.418),Vector3(span*.42,.02,.035),"30373b" if style == "slab" else "c8a562")
