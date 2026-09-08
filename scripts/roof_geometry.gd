extends RefCounted
class_name LifeRoofGeometry
## Parameterized original roof using the Blender-authored native tile/trim kit.
## Geometry is rebuilt at real thickness; complete fixture GLBs are never scaled.
const EAVE:float=.28
const SHELL:float=.10
const TILE_SIZE:=Vector2(.36,.32)
const KIT="res://assets/models/roof_gable_modules.glb"

const Rules=preload("res://scripts/roof_rules.gd")
static func parameters(record:Dictionary)->Dictionary:return Rules.parameters(record)
static func envelope(record:Dictionary)->AABB:return Rules.envelope(record)

static func _material(hex:String,roughness:float=.75)->StandardMaterial3D:
	var material:=StandardMaterial3D.new();material.albedo_color=Color(hex);material.roughness=roughness;return material

static func _triangle(a:Vector3,b:Vector3,c:Vector3,normal:Vector3,vertices:PackedVector3Array,normals:PackedVector3Array,uvs:PackedVector2Array)->void:
	# Godot front faces are clockwise. Keep explicit geometric outward normals.
	if (c-a).cross(b-a).dot(normal)<0:
		var swap:Vector3=b;b=c;c=swap
	for point:Vector3 in [a,b,c]:vertices.append(point);normals.append(normal);uvs.append(Vector2(point.x,point.z+point.y))

static func _mesh(vertices:PackedVector3Array,normals:PackedVector3Array,uvs:PackedVector2Array,material:Material)->ArrayMesh:
	var arrays:Array=[];arrays.resize(Mesh.ARRAY_MAX);arrays[Mesh.ARRAY_VERTEX]=vertices;arrays[Mesh.ARRAY_NORMAL]=normals;arrays[Mesh.ARRAY_TEX_UV]=uvs
	var mesh:=ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays);mesh.surface_set_material(0,material);return mesh

static func _extrude(parent:Node3D,name:String,contour:PackedVector2Array,z0:float,z1:float,material:Material)->MeshInstance3D:
	var profile:PackedVector2Array=contour.duplicate()
	if Geometry2D.is_polygon_clockwise(profile):profile.reverse()
	var triangles:PackedInt32Array=Geometry2D.triangulate_polygon(profile)
	var vertices:=PackedVector3Array();var normals:=PackedVector3Array();var uvs:=PackedVector2Array()
	for end:int in [0,1]:
		var z:float=z0 if end==0 else z1;var normal:=Vector3(0,0,-1 if end==0 else 1)
		for index:int in range(0,triangles.size(),3):
			var a:Vector2=profile[triangles[index]];var b:Vector2=profile[triangles[index+1]];var c:Vector2=profile[triangles[index+2]]
			_triangle(Vector3(a.x,a.y,z),Vector3(b.x,b.y,z),Vector3(c.x,c.y,z),normal,vertices,normals,uvs)
	for index:int in range(profile.size()):
		var a:Vector2=profile[index];var b:Vector2=profile[(index+1)%profile.size()];var edge:Vector2=b-a;var normal:=Vector3(edge.y,-edge.x,0).normalized()
		var one:=Vector3(a.x,a.y,z0);var two:=Vector3(b.x,b.y,z0);var three:=Vector3(b.x,b.y,z1);var four:=Vector3(a.x,a.y,z1)
		_triangle(one,two,three,normal,vertices,normals,uvs);_triangle(one,three,four,normal,vertices,normals,uvs)
	var node:=MeshInstance3D.new();node.name=name;node.mesh=_mesh(vertices,normals,uvs,material);parent.add_child(node);return node

static func _box(parent:Node3D,name:String,low:Vector3,high:Vector3,material:Material)->MeshInstance3D:
	return _extrude(parent,name,PackedVector2Array([Vector2(low.x,low.y),Vector2(high.x,low.y),Vector2(high.x,high.y),Vector2(low.x,high.y)]),low.z,high.z,material)

static func _cropped_tile(width:float,depth:float,material:Material)->ArrayMesh:
	# Re-loft the authored native bevel profile for edge pieces. No change to
	# the .020m height, .007m bevel or leading-butt shape of a full-sized tile.
	var bevel:float=minf(.007,minf(width,depth)*.12)
	var poly:PackedVector2Array=PackedVector2Array([Vector2(-width*.5+bevel,-depth*.5),Vector2(width*.5-bevel,-depth*.5),Vector2(width*.5,-depth*.5+bevel),Vector2(width*.5,depth*.5-bevel),Vector2(width*.5-bevel,depth*.5),Vector2(-width*.5+bevel,depth*.5),Vector2(-width*.5,depth*.5-bevel),Vector2(-width*.5,-depth*.5+bevel)])
	var points:Array[Vector3]=[]
	for layer:int in range(3):
		var inset:float=.002 if layer==2 else 0.0
		for point:Vector2 in poly:
			var height:float=.012+.008*(.5-point.y/depth)
			points.append(Vector3(point.x*(1-2*inset/width),0.0 if layer==0 else height-.003 if layer==1 else height,point.y*(1-2*inset/depth)))
	points.append(Vector3(0,.019,0))
	var vertices:=PackedVector3Array();var normals:=PackedVector3Array();var uvs:=PackedVector2Array()
	for index:int in range(1,7):_triangle(points[0],points[index],points[index+1],Vector3.DOWN,vertices,normals,uvs)
	for ring:int in [0,1]:
		for index:int in range(8):
			var next:int=(index+1)%8;var one:Vector3=points[ring*8+index];var two:Vector3=points[ring*8+next];var three:Vector3=points[(ring+1)*8+next];var four:Vector3=points[(ring+1)*8+index]
			var normal:Vector3=(two-one).cross(three-one).normalized()
			if normal.dot(Vector3(one.x,0,one.z))<0:normal=-normal
			_triangle(one,two,three,normal,vertices,normals,uvs);_triangle(one,three,four,normal,vertices,normals,uvs)
	for index:int in range(8):
		var one:Vector3=points[16+index];var two:Vector3=points[16+(index+1)%8];var three:Vector3=points[24];var normal:Vector3=(two-one).cross(three-one).normalized()
		if normal.y<0:normal=-normal
		_triangle(one,two,three,normal,vertices,normals,uvs)
	return _mesh(vertices,normals,uvs,material)

static func _native(parent:Node3D,name:String,mesh:Mesh,at:Vector3,length:float)->MeshInstance3D:
	var node:=MeshInstance3D.new();node.name=name;node.mesh=mesh;node.position=at;node.scale.z=length;parent.add_child(node);node.set_meta("native_module",true);return node

static func create(record:Dictionary)->Node3D:
	var p:Dictionary=parameters(record);var model:=Node3D.new();model.name="Roof_"+str(record.id)
	model.position=Vector3(float(record.x),.16+3.0*int(record.level)+2.6,float(record.z));model.rotation_degrees.y=float(record.rotation)
	model.set_meta("roof_id",str(record.id));model.set_meta("building_level",int(record.level));model.set_meta("parameters",record.duplicate(true));model.set_meta("envelope",envelope(record))
	var kit:Node3D=load(KIT).instantiate()
	var native_tile:Mesh=(kit.find_child("Tile_036x032",true,false) as MeshInstance3D).mesh
	var native_fascia:Mesh=(kit.find_child("Fascia_100",true,false) as MeshInstance3D).mesh
	var native_lip:Mesh=(kit.find_child("OakLip_100",true,false) as MeshInstance3D).mesh
	var cream:Material=_material("e4dccb");var oak:Material=_material("927353");var ridge:Material=_material("40554e")
	var top:Callable=func(x:float)->float:return p.height-p.pitch*absf(x)+SHELL*p.sec
	var lower_x:float=p.x-SHELL*p.sn;var lower_y:float=p.height-p.pitch*lower_x;var fy:float=top.call(p.x)-.025
	for side:int in [-1,1]:
		var label:String="Left" if side<0 else "Right"
		_extrude(model,"RoofDeck_"+label,PackedVector2Array([Vector2(0,p.height),Vector2(side*lower_x,lower_y),Vector2(side*p.x,lower_y+SHELL*p.cs),Vector2(side*SHELL*p.sn,p.height+SHELL*p.cs)]),-p.z+.012,p.z-.012,oak)
		_native(model,"EaveFascia_"+label,native_fascia,Vector3(side*(p.x-.03),fy,0),2*p.z-.20)
		_native(model,"EaveOakLip_"+label,native_lip,Vector3(side*(p.x-.0535),fy-.145,0),2*p.z-.20)
		for end:int in [-1,1]:
			_extrude(model,"RakeFascia_%s_%d"%[label,end],PackedVector2Array([Vector2(0,top.call(0)-.025),Vector2(side*p.x,fy),Vector2(side*p.x,fy-.18),Vector2(0,top.call(0)-.205)]),minf(end*(p.z-.10),end*p.z),maxf(end*(p.z-.10),end*p.z),cream)
	for end:int in [-1,1]:
		var za:float=end*(p.length*.5-.08);var zb:float=end*p.length*.5
		_extrude(model,"GableInfill_%d"%end,PackedVector2Array([Vector2(-p.span*.5,0),Vector2(p.span*.5,0),Vector2(0,p.height)]),minf(za,zb),maxf(za,zb),cream)
		_box(model,"GableOakTie_%d"%end,Vector3(-p.span*.5,.015,minf(za,zb)-.004),Vector3(p.span*.5,.085,maxf(za,zb)+.004),oak)
	var ridge_width:float=minf(.16,p.x*.28);var ridge_profile:=PackedVector2Array()
	for index:int in range(9):
		var x:float=-ridge_width+2*ridge_width*index/8.0;ridge_profile.append(Vector2(x,top.call(x)+.018+.047*(1-pow(x/ridge_width,2))))
	for index:int in range(8,-1,-1):ridge_profile.append(ridge_profile[index]-Vector2(0,.027))
	var count:int=maxi(1,ceili((2*p.z-.04)/.80));var section:float=(2*p.z-.04)/count
	for index:int in range(count):_extrude(model,"RidgeCap_%02d"%index,ridge_profile,-p.z+.02+index*section,-p.z+.02+(index+1)*section-.002,ridge)
	var groups:Dictionary={};var tile_count:int=0;var native_count:int=0
	var slope_length:float=(p.x-.065)*p.sec;var ridge_length:float=2*p.z-.04
	for side:int in [-1,1]:
		var row:int=0;var along_slope:float=0.0
		while along_slope<slope_length-.01:
			var depth:float=minf(.32,slope_length-along_slope);var xc:float=.04+(along_slope+depth*.5)/p.sec
			var col:int=0;var along_ridge:float=0.0
			while along_ridge<ridge_length-.01:
				var width:float=minf(.36,ridge_length-along_ridge);var zc:float=-p.z+.02+along_ridge+width*.5
				var shade:int=posmod(row*37+col*17+side,4);var key:String="%.5f_%.5f_%d"%[width,depth,shade]
				if not groups.has(key):
					var hex:String=["57736a","526e64","5c776e","506b62"][shade] if str(record.material)=="57736a" else str(record.material)
					var material:Material=_material(hex,.80);var mesh:Mesh
					if is_equal_approx(width,.36) and is_equal_approx(depth,.32):mesh=native_tile.duplicate();mesh.surface_set_material(0,material)
					else:mesh=_cropped_tile(width,depth,material)
					groups[key]={"mesh":mesh,"transforms":[]}
				var basis:=Basis(Vector3(0,0,-side),Vector3(side*p.sn,p.cs,0),Vector3(side*p.cs,-p.sn,0))
				groups[key].transforms.append(Transform3D(basis,Vector3(side*xc,top.call(xc)+.002,zc)))
				tile_count+=1
				if is_equal_approx(width,.36) and is_equal_approx(depth,.32):native_count+=1
				along_ridge+=width+.006;col+=1
			along_slope+=depth+.005;row+=1
	for key:String in groups:
		var group:Dictionary=groups[key];var mesh:=MultiMesh.new();mesh.transform_format=MultiMesh.TRANSFORM_3D;mesh.mesh=group.mesh;mesh.instance_count=group.transforms.size()
		for index:int in range(mesh.instance_count):mesh.set_instance_transform(index,group.transforms[index])
		var node:=MultiMeshInstance3D.new();node.name="RoofTiles_"+key;node.multimesh=mesh;model.add_child(node)
	model.set_meta("tile_count",tile_count);model.set_meta("native_tile_count",native_count)
	for side:int in [-1,1]:
		for end:int in [-1,1]:
			var marker:=Marker3D.new();marker.name="Support_%d_%d"%[side,end];marker.position=Vector3(side*p.span*.5,0,end*p.length*.5);model.add_child(marker)
	for end:int in [-1,1]:
		var marker:=Marker3D.new();marker.name="RidgeStart" if end<0 else "RidgeEnd";marker.position=Vector3(0,p.height,end*p.length*.5);model.add_child(marker)
	kit.free();return model
