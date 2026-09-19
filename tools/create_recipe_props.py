"""Original JustLife herb-pasta and harvest-bake art, Blender 5.2.1.
Run from this art candidate: blender -b --python tools/create_recipe_props.py.
Canonical GLBs are metre-scaled, Y-up; editable .blend roots are studio placed.
Utility mesh construction follows the original garden-supper generator.
"""
from pathlib import Path
import bpy, bmesh, math, random, json, hashlib
from mathutils import Vector
ROOT=Path(__file__).resolve().parents[1]
ART=ROOT/"art/recipes"
EVIDENCE=ART/"studio"
MODELS=ROOT/"assets/models"
for directory in (ART,EVIDENCE,MODELS):directory.mkdir(parents=True,exist_ok=True)
bpy.ops.wm.read_factory_settings(use_empty=True)
scene=bpy.context.scene
scene.unit_settings.system="METRIC"
scene.unit_settings.scale_length=1.0
asset_collection=bpy.data.collections.new("JustLife recipe variations — editable originals")
scene.collection.children.link(asset_collection)
M={}
ACTIVE=[]

def material(name, color, roughness=.58, metal=0):
    rgb = [int(color[i:i+2], 16)/255 for i in (0, 2, 4)]
    rgb = [v/12.92 if v <= .04045 else ((v+.055)/1.055)**2.4 for v in rgb]
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = (*rgb, 1)
    mat.use_nodes = True
    p = mat.node_tree.nodes.get("Principled BSDF")
    p.inputs["Base Color"].default_value = (*rgb, 1)
    p.inputs["Roughness"].default_value = roughness
    p.inputs["Metallic"].default_value = metal
    M[name] = mat

def link(obj):
    for col in list(obj.users_collection):
        col.objects.unlink(obj)
    asset_collection.objects.link(obj)
    ACTIVE.append(obj)
    return obj

def empty(name, location=(0, 0, 0), parent=None):
    obj = bpy.data.objects.new(name, None)
    asset_collection.objects.link(obj)
    obj.location = location
    obj.parent = parent
    obj.empty_display_size = .02
    ACTIVE.append(obj)
    return obj

def mesh(name, verts, faces, mat, parent=None, smooth=False):
    data = bpy.data.meshes.new(name + " geometry")
    data.from_pydata(verts, [], faces)
    data.update()
    bm = bmesh.new()
    bm.from_mesh(data)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=.0000001)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(data)
    bm.free()
    obj = bpy.data.objects.new(name, data)
    asset_collection.objects.link(obj)
    ACTIVE.append(obj)
    data.materials.append(M[mat])
    for face in data.polygons:
        face.use_smooth = smooth
    obj.parent = parent
    return obj

def bevel(obj, width=.001, segments=3):
    mod = obj.modifiers.new("Soft crafted edges", "BEVEL")
    mod.width = width
    mod.segments = segments
    obj.modifiers.new("Weighted corner normals", "WEIGHTED_NORMAL")
    return obj

def lathe(name, profile, mat, parent, ellipse=1.0, segments=80):
    verts = [(r*math.cos(i*math.tau/segments), r*math.sin(i*math.tau/segments)*ellipse, z)
             for r, z in profile for i in range(segments)]
    faces = []
    for j in range(len(profile)):
        nxt = (j+1) % len(profile)
        for i in range(segments):
            k = (i+1) % segments
            faces.append((j*segments+i, j*segments+k, nxt*segments+k, nxt*segments+i))
    return mesh(name, verts, faces, mat, parent, True)

def tube(name, points, radius, mat, parent, sides=10, closed=False):
    verts = []
    for i, pt in enumerate(points):
        direction = Vector(points[(i+1) % len(points)])-Vector(points[i-1 if i else (-1 if closed else 0)])
        direction.normalize()
        axis = direction.cross(Vector((0, 0, 1)))
        if axis.length < .01:
            axis = direction.cross(Vector((1, 0, 0)))
        axis.normalize()
        other = direction.cross(axis).normalized()
        for j in range(sides):
            verts.append(Vector(pt)+radius*(math.cos(j*math.tau/sides)*axis+math.sin(j*math.tau/sides)*other))
    faces = []
    for i in range(len(points) if closed else len(points)-1):
        for j in range(sides):
            faces.append((i*sides+j, i*sides+(j+1)%sides, ((i+1)%len(points))*sides+(j+1)%sides, ((i+1)%len(points))*sides+j))
    if not closed:
        faces += [tuple(reversed(range(sides))), tuple((len(points)-1)*sides+j for j in range(sides))]
    return mesh(name, verts, faces, mat, parent, True)

def grain(name, p, scale, mat, parent, angle=0):
    # Small independent grains; joined for efficient runtime drawing after modeling.
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=2, radius=1, location=p)
    obj = link(bpy.context.object)
    obj.name = name
    obj.scale = scale
    obj.rotation_euler.z = angle
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    obj.data.materials.append(M[mat])
    for poly in obj.data.polygons:
        poly.use_smooth = True
    obj.parent = parent
    return obj

def prism(name, outline, height, mat, parent, position=(0, 0, 0), rotation=0, edge=.001):
    count = len(outline)
    verts = [(x, y, z) for z in [-height/2, height/2] for x, y in outline]
    faces = [tuple(reversed(range(count))), tuple(range(count, count*2))]
    faces += [(i, (i+1)%count, (i+1)%count+count, i+count) for i in range(count)]
    obj = mesh(name, verts, faces, mat, parent)
    obj.location = position
    obj.rotation_euler.z = rotation
    if edge:
        bevel(obj, edge, 2)
    return obj

def leaf(p, angle, parent, scale=1):
    verts = []
    for j in range(9):
        t = j/8
        width = math.sin(math.pi*t)**.8*.012*scale
        y = (t-.5)*.054*scale
        center_z = math.sin(t*math.pi)*.004*scale
        verts += [(-width, y, center_z-.002*scale), (0, y, center_z), (width, y, center_z-.002*scale)]
    faces = []
    for j in range(8):
        for k in range(2):
            faces.append((j*3+k, j*3+k+1, (j+1)*3+k+1, (j+1)*3+k))
    obj = mesh("Basil pointed leaf", verts, faces, "Basil leaf", parent, True)
    obj.location = p
    obj.rotation_euler.z = angle
    solid = obj.modifiers.new("Leaf thickness", "SOLIDIFY")
    solid.thickness = .0006
    tube("Basil midrib", [(0, (t/8-.5)*.052*scale, math.sin(t/8*math.pi)*.004*scale+.0005) for t in range(9)],
         .00045, "Basil vein", obj, 6)

def bake_runtime_mesh(name, source_objects, parent):
    """Merge source components while retaining editable originals in the .blend."""
    verts, faces, material_indices, smooth_faces, materials = [], [], [], [], []
    deps = bpy.context.evaluated_depsgraph_get()
    inverse = parent.matrix_world.inverted()
    for obj in source_objects:
        evaluated = obj.evaluated_get(deps)
        data = evaluated.to_mesh()
        matrix = inverse @ obj.matrix_world
        offset = len(verts)
        verts.extend(matrix @ v.co for v in data.vertices)
        for polygon in data.polygons:
            faces.append(tuple(offset+i for i in polygon.vertices))
            mat = data.materials[polygon.material_index]
            if mat not in materials: materials.append(mat)
            material_indices.append(materials.index(mat))
            smooth_faces.append(polygon.use_smooth)
        evaluated.to_mesh_clear()
    data = bpy.data.meshes.new(name)
    data.from_pydata(verts, [], faces)
    for mat in materials: data.materials.append(mat)
    for i, polygon in enumerate(data.polygons):
        polygon.material_index = material_indices[i]
        polygon.use_smooth = smooth_faces[i]
    data.update()
    obj = bpy.data.objects.new(name, data)
    asset_collection.objects.link(obj)
    obj.parent = parent
    return obj

for spec in [
    ("Cream stoneware","EFE9DA",.29), ("Muted teal glaze","537F76",.28),
    ("Pasta gold","DFC17C",.45), ("Pasta toasted folds","C8A058",.54),
    ("Pasta butter","EDCF8D",.39), ("Basil leaf","55835A",.56),
    ("Basil vein","82A26D",.60), ("Roasted tomato","B95D47",.49),
    ("Parmesan","EEE1AD",.63), ("Roasted squash","D39045",.59),
    ("Tender greens","557755",.57), ("Baked cream","E8CC93",.52),
    ("Golden crust","A97536",.63), ("Toasted crust","824B26",.66),
    ("Crust highlight","DDB270",.62), ("Ground","E5DFD1",.78),
]:material(*spec)


def metadata(root, recipe, serving):
    root["original_artwork"]="JustLife original "+recipe+"; modeled without external assets"
    root["unit"]="metre"
    root["recipe"]=recipe
    root["bottom_y_m"]=0.0
    root["food_node"]="Food"
    if serving:
        for side in [-1,1]:empty("GripLeft" if side<0 else "GripRight",(side*.2395,0,.046),root)
        root["grip_left_godot"]=[-.2395,.046,0]
        root["grip_right_godot"]=[.2395,.046,0]
    else:
        empty("Grip",(0,0,.009),root)
        root["grip_godot"]=[0,.009,0]


def plate(root):
    lathe("Dinner plate with low rolled edge",[(0,.003),(.065,.003),(.075,0),(.083,.001),(.112,.008),(.141,.016),(.149,.020),(.150,.023),(.148,.026),(.140,.026),(.119,.017),(.088,.012),(0,.012)],"Cream stoneware",root)
    lathe("Teal line at rim",[(.143,.0244),(.147,.026),(.148,.0258),(.147,.0242)],"Muted teal glaze",root)


def ear_handles(root, glaze="Cream stoneware"):
    for side in [-1,1]:
        points=[(side*(.190+.052*math.sin(t*math.pi)),-.040*math.cos(t*math.pi),.044+.002*math.sin(t*math.pi)) for t in [i/24 for i in range(25)]]
        tube("Open ceramic carrying ear",points,.007,glaze,root,10)


def rounded_outline(hx,hy,radius,segments=9):
    result=[]
    for cx,cy,angle in [(hx-radius,hy-radius,0),(-hx+radius,hy-radius,math.pi/2),(-hx+radius,-hy+radius,math.pi),(hx-radius,-hy+radius,3*math.pi/2)]:
        for i in range(segments):
            a=angle+i*math.pi/2/(segments-1)
            result.append((cx+radius*math.cos(a),cy+radius*math.sin(a)))
    return result


def rounded_loft(name,profiles,mat,parent):
    verts=[]
    for hx,hy,r,z in profiles:verts.extend((x,y,z) for x,y in rounded_outline(hx,hy,r))
    n=36
    faces=[(j*n+i,j*n+(i+1)%n,((j+1)%len(profiles))*n+(i+1)%n,((j+1)%len(profiles))*n+i) for j in range(len(profiles)) for i in range(n)]
    return mesh(name,verts,faces,mat,parent,True)


def ribbon_noodle(name,points,width,thickness,mat,parent,phase):
    verts=[]
    for i,p in enumerate(points):
        tangent=Vector(points[min(len(points)-1,i+1)])-Vector(points[max(0,i-1)])
        tangent.normalize()
        side=tangent.cross(Vector((0,0,1))).normalized()
        normal=side.cross(tangent).normalized()
        twist=.40*math.sin(i*.19+phase)
        side,normal=side*math.cos(twist)+normal*math.sin(twist),normal*math.cos(twist)-side*math.sin(twist)
        for j in range(8):
            a=math.tau*j/8
            verts.append(Vector(p)+side*width*math.cos(a)+normal*thickness*math.sin(a))
    faces=[(i*8+j,i*8+(j+1)%8,(i+1)*8+(j+1)%8,(i+1)*8+j) for i in range(len(points)-1) for j in range(8)]
    faces+=[tuple(reversed(range(8))),tuple((len(points)-1)*8+j for j in range(8))]
    return mesh(name,verts,faces,mat,parent,True)


def pasta_food(root,serving):
    rng=random.Random(621 if serving else 713)
    group=empty("Food",(0,0,.023 if serving else .015),root)
    group["consumption_axis"]="+Y in Godot"
    rx,ry=(.172,.116) if serving else (.079,.070)
    height=.047 if serving else .035
    # An irregular bottom layer of folded noodles, not a smooth solid mound.
    count=82 if serving else 30
    for k in range(count):
        angle=rng.random()*math.tau
        radius=math.sqrt(rng.random())*.76
        cx,cy=math.cos(angle)*rx*radius,math.sin(angle)*ry*radius
        loop_r=rng.uniform(.013,.034) if serving else rng.uniform(.010,.023)
        stretch=rng.uniform(.65,1.5)
        rotation=rng.random()*math.tau
        phase=rng.random()*math.tau
        turns=rng.uniform(.6,1.15)
        center_r=math.sqrt((cx/rx)**2+(cy/ry)**2)
        base=.004+height*max(0,1-center_r**1.45)*rng.uniform(.36,.98)
        pts=[]
        for j in range(61):
            t=j/60;a=t*math.tau*turns+phase
            local_x=loop_r*math.cos(a)*(1+.12*math.sin(3*a))
            local_y=loop_r*stretch*math.sin(a)
            x=cx+local_x*math.cos(rotation)-local_y*math.sin(rotation)
            y=cy+local_x*math.sin(rotation)+local_y*math.cos(rotation)
            edge=math.sqrt((x/rx)**2+(y/ry)**2)
            if edge>.99:x*=.99/edge;y*=.99/edge
            z=base+.006*math.sin(a*1.8+phase)+.003*math.cos(a*3.1)
            pts.append((x,y,max(.003,z)))
        ribbon_noodle("Curled hand-cut ribbon noodle",pts,.0035 if serving else .0031,.00125,["Pasta gold","Pasta butter","Pasta toasted folds"][k%3],group,phase)
    for x,y,a,scale in [(-.32,.10,-.5,1.0),(.31,-.26,.6,.86),(.19,.43,2.0,.80)]:
        z=height*.94+.009
        leaf((x*rx,y*ry,z),a,group,scale*(1.15 if serving else .75))
    for i in range(13 if serving else 5):
        a=rng.random()*math.tau;r=rng.uniform(.25,.8)
        p=(math.cos(a)*rx*r,math.sin(a)*ry*r,height*(1-r**1.5)+.010)
        grain("Roasted tomato garnish",p,(.009,.005,.0035) if serving else (.006,.004,.0028),"Roasted tomato",group,rng.random()*math.tau)
    for i in range(24 if serving else 10):
        a=rng.random()*math.tau;r=math.sqrt(rng.random())*.8
        p=(math.cos(a)*rx*r,math.sin(a)*ry*r,height*(1-r**1.5)+.011)
        shard=[(-.004,-.002),(.005,-.001),(.003,.003),(-.003,.002)]
        prism("Fine parmesan shaving",shard,.0008,"Parmesan",group,p,rng.random()*math.tau,.0002)
    return group


def pasta(serving):
    global ACTIVE
    ACTIVE=[]
    root=empty("HerbPastaServing" if serving else "HerbPastaPlate")
    metadata(root,"herb_pasta",serving)
    if serving:
        bowl=lathe("Single shell teal exterior and cream interior",[(0,.003),(.128,.003),(.145,0),(.159,.004),(.182,.021),(.200,.050),(.207,.064),(.205,.067),(.198,.064),(.191,.049),(.174,.029),(.149,.015),(0,.015)],"Muted teal glaze",root,.78)
        # One watertight shell. Assign its inward-facing and upward rim faces
        # cream; never duplicate a second closed bowl over this surface.
        bowl.data.materials.append(M["Cream stoneware"])
        for face in bowl.data.polygons:
            radial=face.normal.x*face.center.x+face.normal.y*face.center.y/(.78*.78)
            inside=radial < -.0001 or (face.normal.z > .7 and face.center.z >= .014)
            face.material_index=1 if inside or face.center.z>.063 else 0
        ear_handles(root,"Muted teal glaze")
    else:plate(root)
    pasta_food(root,serving)
    return root,ACTIVE.copy()


def baked_layer(name,hx,hy,z,height,mat,parent,seed):
    rng=random.Random(seed)
    # Slightly irregular cut edges expose genuine layers without a perfect block.
    outline=rounded_outline(hx,hy,min(.009,hx*.18),5)
    outline=[(x+rng.uniform(-.0014,.0014),y+rng.uniform(-.0014,.0014)) for x,y in outline]
    return prism(name,outline,height,mat,parent,(0,0,z),0,.0014)


def bake_filling(parent,hx,hy,seed):
    baked_layer("Deep squash and vegetable filling",hx,hy,.015,.030,"Roasted squash",parent,seed)
    baked_layer("Soft cream between roasted vegetables",hx*.99,hy*.98,.039,.022,"Baked cream",parent,seed+2)
    rng=random.Random(seed)
    for side in [-1,1]:
        count=max(4,int(hx/.020))
        for i in range(count):
            x=-hx*.90+hx*1.80*i/(count-1)+rng.uniform(-.003,.003)
            y=side*(hy-.001);z=.025+rng.uniform(-.005,.006)
            grain("Exposed roasted courgette skin",(x,y,z),(.009,.004,.013),"Tender greens",parent,rng.uniform(-.2,.2))
            grain("Tender courgette cut face",(x,y+side*.002,z+.0005),(.0065,.003,.009),"Baked cream",parent,0)
            grain("Roasted squash visible at cut edge",(x+.007,y-side*.002,.046),(.008,.004,.006),"Roasted squash",parent,rng.random())
    for i in range(18):
        x=rng.uniform(-hx*.85,hx*.85);y=rng.uniform(-hy*.86,hy*.86)
        grain("Vegetable chunk beneath browned cheese",(x,y,.048),(.011,.008,.008),"Roasted squash" if i%2 else "Tender greens",parent,rng.random()*math.tau)


def rough_crust(parent,hx,hy,seed):
    nx,ny=33,25
    verts=[]
    def crust_height(x,y):
        return .055+.0045*math.sin(x*85+seed)*math.cos(y*70-seed)+.002*math.cos(x*173+y*151)
    for j in range(ny):
        for i in range(nx):
            x=-hx+2*hx*i/(nx-1);y=-hy+2*hy*j/(ny-1)
            if i in [0,nx-1]:x+=.0025*math.sin(y*112+seed)
            if j in [0,ny-1]:y+=.0025*math.sin(x*123-seed)
            verts.append((x,y,crust_height(x,y)))
    faces=[]
    for j in range(ny-1):
        for i in range(nx-1):
            a=j*nx+i;faces.append((a,a+1,a+nx+1,a+nx))
    top=mesh("Continuous irregular golden gratin surface",verts,faces,"Crust highlight",parent,True)
    solid=top.modifiers.new("Soft browned cheese depth","SOLIDIFY");solid.thickness=.005
    rng=random.Random(seed)
    # Large, uneven roasted patches remain readable at the game camera scale.
    for i in range(22 if hx>.1 else 8):
        x=rng.uniform(-hx*.83,hx*.83);y=rng.uniform(-hy*.83,hy*.83)
        z=crust_height(x,y)+.0015
        grain("Irregular browned cheese mound",(x,y,z),(rng.uniform(.008,.018),rng.uniform(.005,.012),rng.uniform(.002,.004)),"Golden crust" if i%3 else "Toasted crust",parent,rng.random()*math.tau)
    for i in range(14 if hx>.1 else 5):
        x=rng.uniform(-hx*.83,hx*.83);y=rng.uniform(-hy*.83,hy*.83);z=crust_height(x,y)+.003
        grain("Roasted vegetable emerging through topping",(x,y,z),(.009,.006,.004),"Roasted squash" if i%2 else "Tender greens",parent,rng.random()*math.tau)
    for i in range(20):
        x=rng.uniform(-hx*.9,hx*.9);y=rng.uniform(-hy*.9,hy*.9)
        grain("Chopped herb in gratin",(x,y,crust_height(x,y)+.0014),(.002,.001,.0007),"Tender greens",parent,rng.random()*math.tau)


def bake_piece(parent,center,hx,hy,seed,with_base=True):
    root=empty("Cut gratin portion",center,parent)
    if with_base:bake_filling(root,hx,hy,seed)
    rough_crust(root,hx,hy,seed)
    return root


def bake(serving):
    global ACTIVE
    ACTIVE=[]
    root=empty("HarvestBakeServing" if serving else "HarvestBakePlate")
    metadata(root,"harvest_bake",serving)
    if serving:
        profiles=[(.001,.001,.0005,.003),(.149,.094,.023,.003),(.158,.102,.023,0),(.170,.113,.024,.003),(.190,.135,.031,.027),(.207,.151,.037,.045),(.207,.151,.037,.050),(.203,.147,.035,.052),(.197,.141,.033,.049),(.183,.127,.029,.027),(.163,.107,.022,.014),(.001,.001,.0005,.014)]
        rounded_loft("Shallow rectangular oven dish",profiles,"Cream stoneware",root)
        rounded_loft("Teal oven rim",[(.201,.145,.034,.049),(.205,.149,.036,.053),(.209,.153,.038,.050),(.207,.151,.037,.047)],"Muted teal glaze",root)
        ear_handles(root)
    else:plate(root)
    group=empty("Food",(0,0,.016 if serving else .015),root)
    group["consumption_axis"]="+Y in Godot"
    if serving:
        # One deep casserole, not an array of flat individual cracker panels.
        bake_filling(group,.162,.106,904)
        rough_crust(group,.163,.107,910)
        leaf((.010,.030,.066),.4,group,.82)
        leaf((.026,.049,.066),-.2,group,.66)
    else:
        piece=bake_piece(group,(0,0,0),.063,.045,983)
        piece.rotation_euler.z=-.20
        leaf((.035,.031,.066),-.7,group,.70)
        # A few crumbs are outside the cut portion, so it reads as plated food.
        for p in [(-.070,-.016,.001),(.064,-.039,.001),(.062,.047,.001)]:
            grain("Fallen baked crumb",p,(.0031,.002,.0014),"Golden crust",group,.3)
    return root,ACTIVE.copy()


assets=[("meal_herb_pasta_serving",*pasta(True)),("meal_herb_pasta_plate",*pasta(False)),("meal_harvest_bake_serving",*bake(True)),("meal_harvest_bake_plate",*bake(False))]
for filename,root,objs in assets:
    empty_names={obj:obj.name for obj in bpy.data.objects if obj.type=="EMPTY"}
    for obj,name in empty_names.items():obj.name="SOURCE_"+name
    for obj in objs:
        if obj.type=="EMPTY":obj.name=empty_names[obj].split(".")[0]
    bpy.context.view_layer.update()
    food_group=next(obj for obj in objs if obj.type=="EMPTY" and obj.name=="Food")
    food_parts=set(food_group.children_recursive)
    groups=[("FoodGeometry",[o for o in food_parts if o.type=="MESH"],food_group),("DishGeometry",[o for o in objs if o.type=="MESH" and o not in food_parts],root)]
    baked=[bake_runtime_mesh(name,parts,parent) for name,parts,parent in groups]
    bpy.ops.object.select_all(action="DESELECT")
    for obj in [o for o in objs if o.type=="EMPTY" and o.parent not in food_parts]+baked:obj.select_set(True)
    # Portion empties are authoring detail; runtime food is one batched child.
    for obj in objs:
        if obj in food_parts:obj.select_set(False)
    bpy.context.view_layer.objects.active=root
    bpy.ops.export_scene.gltf(filepath=str(MODELS/(filename+".glb")),export_format="GLB",use_selection=True,export_apply=True,export_extras=True,export_yup=True,export_animations=False,export_cameras=False,export_lights=False)
    for obj in baked:
        data=obj.data;bpy.data.objects.remove(obj,do_unlink=True);bpy.data.meshes.remove(data)
    for i,obj in enumerate(empty_names):obj.name="RESTORE_%d"%i
    for obj,name in empty_names.items():obj.name=name

# One matched studio comparison: pasta left, oven bake right, one plate per dish.
for index,(_,root,_) in enumerate(assets):
    root.location=(-.31 if index<2 else .31,.12 if index%2==0 else -.19,0)
studio=bpy.data.collections.new("Studio — excluded from exports");scene.collection.children.link(studio)
def studio_link(obj):
    for col in list(obj.users_collection):col.objects.unlink(obj)
    studio.objects.link(obj)
bpy.ops.mesh.primitive_plane_add(size=200,location=(0,0,-.001));ground=bpy.context.object;ground.name="Warm studio ground";ground.data.materials.append(M["Ground"]);studio_link(ground)
bpy.ops.object.camera_add(location=(0,-1.5,1.45));camera=bpy.context.object;camera.rotation_euler=(Vector((0,0,.022))-camera.location).to_track_quat("-Z","Y").to_euler();camera.data.type="ORTHO";camera.data.ortho_scale=1.29;scene.camera=camera;studio_link(camera)
for p,energy,size in [((-.70,-.55,1.15),65,.8),((.8,.12,.90),38,.7),((-.1,.8,.8),40,.65)]:
    bpy.ops.object.light_add(type="AREA",location=p);light=bpy.context.object;light.data.energy=energy;light.data.shape="DISK";light.data.size=size;light.rotation_euler=(Vector((0,0,.02))-light.location).to_track_quat("-Z","Y").to_euler();studio_link(light)
scene.world=bpy.data.worlds.new("Warm recipe studio");scene.world.use_nodes=True
scene.world.node_tree.nodes.get("Background").inputs[0].default_value=(.30,.32,.31,1)
scene.world.node_tree.nodes.get("Background").inputs[1].default_value=.45
scene.render.engine="CYCLES";scene.cycles.samples=48;scene.cycles.use_denoising=True
scene.render.resolution_x=1400;scene.render.resolution_y=950;scene.render.resolution_percentage=100
scene.view_settings.view_transform="AgX";scene.view_settings.exposure=-1.05
scene.render.image_settings.file_format="PNG";scene.render.filepath=str(EVIDENCE/"recipe_comparison.png")
bpy.ops.wm.save_as_mainfile(filepath=str(ART/"recipe_variants.blend"))
bpy.ops.render.render(write_still=True)
manifest={"original_artwork":True,"source":"art/recipes/recipe_variants.blend","generator":"tools/create_recipe_props.py","preview":"art/recipes/studio/recipe_comparison.png","source_sha256":hashlib.sha256((ART/"recipe_variants.blend").read_bytes()).hexdigest(),"generator_sha256":hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),"blender_version":bpy.app.version_string,"assets":{}}
for filename,root,objs in assets:
    p=MODELS/(filename+".glb");manifest["assets"][filename]={"path":str(p.relative_to(ROOT)),"root":root.name,"sha256":hashlib.sha256(p.read_bytes()).hexdigest(),"source_objects":len(objs),"bytes":p.stat().st_size}
(ART/"manifest.json").write_text(json.dumps(manifest,indent=2)+"\n")
print("JUSTLIFE_RECIPE_VARIANTS_READY",json.dumps(manifest))
