"""Original JustLife field maples: branch-led stylized foliage, Blender 5.2.1.

Run with a fresh private output root:
blender -b -t 4 --python tools/create_vegetation.py -- --output-root /absolute/new/root
This entry point writes only the native tree pair, their two GLBs and tree manifest.
No source game, furniture, character, or references are read or modified.
"""
from pathlib import Path
import argparse, hashlib, json, math, sys
import bpy, bmesh
from mathutils import Vector, Matrix

args = sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else []
parser = argparse.ArgumentParser(); parser.add_argument('--output-root', type=Path, required=True)
ROOT = parser.parse_args(args).output_root.resolve()
ART = ROOT/'art/vegetation'; MODELS = ROOT/'assets/models'
ART.mkdir(parents=True, exist_ok=True); MODELS.mkdir(parents=True, exist_ok=True)
for destination in (ART/'field_maples.blend', MODELS/'tree_field_maple_a.glb', MODELS/'tree_field_maple_b.glb'):
    if destination.exists(): raise RuntimeError('Refusing to replace an existing tree candidate: '+str(destination))
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.context.scene.unit_settings.system = 'METRIC'
bpy.context.scene.unit_settings.scale_length = 1.0

# Blender +Z is height; export_yup maps it to Godot +Y. All exported object
# transforms are identity, roots coincide at the trunk foot, and source variants
# are separated by collections rather than scene-space offsets.

def linear(v): return v/12.92 if v <= .04045 else ((v+.055)/1.055)**2.4

def color(hex): return tuple(linear(int(hex[i:i+2],16)/255) for i in (0,2,4))

def material(name, rough):
    m = bpy.data.materials.new(name); m.use_nodes = True
    p = m.node_tree.nodes.get('Principled BSDF')
    p.inputs['Base Color'].default_value = (1,1,1,1)
    p.inputs['Roughness'].default_value = rough
    attr = m.node_tree.nodes.new('ShaderNodeVertexColor'); attr.layer_name='TreeColor'
    m.node_tree.links.new(attr.outputs['Color'], p.inputs['Base Color'])
    m.diffuse_color = (*color('789467' if 'foliage' in name else '887051'),1)
    return m
WOOD = material('JustLife field maple warm bark', .91)
LEAF = material('JustLife field maple muted foliage', .93)


def collection(name):
    c=bpy.data.collections.new(name);bpy.context.scene.collection.children.link(c);return c


def mesh(name, verts, faces, col):
    data=bpy.data.meshes.new(name+' editable geometry');data.from_pydata(verts,[],faces);data.update()
    bm=bmesh.new();bm.from_mesh(data);bmesh.ops.recalc_face_normals(bm,faces=bm.faces);bm.to_mesh(data);bm.free()
    obj=bpy.data.objects.new(name,data);col.objects.link(obj)
    return obj


def tube(name, points, radii, col, sides=10):
    points=[Vector(p) for p in points];verts=[];faces=[]
    for i,p in enumerate(points):
        direction=(points[min(i+1,len(points)-1)]-points[max(i-1,0)]).normalized()
        side=direction.cross(Vector((0,1,0)))
        if side.length < .05: side=direction.cross(Vector((1,0,0)))
        side.normalize();other=direction.cross(side).normalized()
        for j in range(sides):
            angle=math.tau*j/sides
            # Bark fluting stays subordinate to the branch silhouette.
            r=max(.022,radii[i])*(1+.045*math.sin(j*3.0+i*.7))
            verts.append(p+r*(math.cos(angle)*side+math.sin(angle)*other))
    for i in range(len(points)-1):
        for j in range(sides):faces.append((i*sides+j,i*sides+(j+1)%sides,(i+1)*sides+(j+1)%sides,(i+1)*sides+j))
    faces.append(tuple(reversed(range(sides))))
    faces.append(tuple((len(points)-1)*sides+j for j in range(sides)))
    return mesh(name,verts,faces,col)


def fan(name, center, size, yaw, tilt, seed, col):
    """Unequal, shallow lobed branch foliage, not a spherical primitive.
    Upper/under surfaces and a broken plan contour are built from editable rings.
    These source masses overlap; one volume remesh removes their closed join lines.
    """
    center=Vector(center);sx,sy,thick=size;segments=28
    # Each broad branch fan has its own off-centre crest and irregular perimeter.
    rings=[(.0,-.24),(.38,-.22),(.80,-.12),(1.0,.02),(.83,.47),(.47,.83),(.0,1.0)]
    verts=[];faces=[];transform=Matrix.Rotation(yaw,3,'Z')@Matrix.Rotation(tilt,3,'Y')
    for ring,(radius,height) in enumerate(rings):
        for j in range(segments):
            a=math.tau*j/segments
            edge=1+.11*math.sin(3*a+seed)+.065*math.sin(5*a-seed*.6)+.033*math.sin(9*a+seed*1.7)
            # Vary the rim height gently; no horizontal dinner-plate boundary.
            h=height+.095*radius*math.sin(2*a+seed)+.045*radius*math.sin(5*a-seed)
            shift=.10*(1-radius)
            p=Vector((sx*(radius*edge*math.cos(a)-shift),sy*(radius*edge*math.sin(a)+shift*.4),thick*h))
            verts.append(center+transform@p)
    for r in range(len(rings)-1):
        for j in range(segments): faces.append((r*segments+j,r*segments+(j+1)%segments,(r+1)*segments+(j+1)%segments,(r+1)*segments+j))
    obj=mesh(name,verts,faces,col)
    bm=bmesh.new();bm.from_mesh(obj.data);bmesh.ops.remove_doubles(bm,verts=bm.verts,dist=.000001);bmesh.ops.recalc_face_normals(bm,faces=bm.faces);bm.to_mesh(obj.data);bm.free()
    return obj


def merged_copy(name, objects, runtime):
    verts=[];faces=[]
    for obj in objects:
        offset=len(verts)
        verts.extend(tuple(obj.matrix_world@v.co) for v in obj.data.vertices)
        faces.extend(tuple(offset+i for i in face.vertices) for face in obj.data.polygons)
    return mesh(name,verts,faces,runtime)


def apply_modifier(obj, mod):
    [o.select_set(False) for o in bpy.data.objects];obj.select_set(True);bpy.context.view_layer.objects.active=obj
    bpy.ops.object.modifier_apply(modifier=mod.name)


def bake_volume(obj, voxel, triangles):
    remesh=obj.modifiers.new('Merge connected authored branch volumes','REMESH')
    remesh.mode='VOXEL';remesh.voxel_size=voxel;remesh.use_smooth_shade=True
    apply_modifier(obj,remesh)
    smooth=obj.modifiers.new('Soften voxel edges without rounding silhouette','SMOOTH');smooth.factor=.34;smooth.iterations=2
    apply_modifier(obj,smooth)
    obj.data.calc_loop_triangles()
    target=min(1.0,triangles/max(1,len(obj.data.loop_triangles)))
    dec=obj.modifiers.new('Baked ordinary-distance geometry','DECIMATE');dec.ratio=target
    apply_modifier(obj,dec)
    for p in obj.data.polygons:p.use_smooth=True


def vertex_colors(obj, foliage, variant):
    data=obj.data
    colors=data.color_attributes.new(name='TreeColor',type='FLOAT_COLOR',domain='POINT')
    low=color('52745a' if foliage else '6d5943');high=color('8fa571' if foliage else '947950')
    for vertex in data.vertices:
        p=vertex.co;n=vertex.normal
        if foliage:
            # Very broad color drift supports the shape; no random per-leaf noise.
            mix=.44+.19*n.z+.12*math.sin(p.x*1.7+p.y*.6+variant)+.06*math.sin(p.z*3.1-p.y*2)
        else:mix=.48+.13*math.sin(p.z*2+p.x*9)+.08*n.x
        mix=max(.12,min(.89,mix))
        colors.data[vertex.index].color=tuple(a+(b-a)*mix for a,b in zip(low,high))+(1,)
    data.materials.append(LEAF if foliage else WOOD)
    data.color_attributes.active_color=colors
    obj['justlife_original_art']='Field maples v28: authored branching and unequal foliage fans'
    obj['root_contract']='Identity local transform; origin at trunk-ground contact; static mesh'


# Points, radii, and foliage masses are deliberately specified, not stochastic.
TREES={
'a':{
 'title':'Spreading field maple',
 'branches':[
  ([(0,0,0),(.025,-.025,.55),(0,.015,1.14),(.06,.025,1.65),(-.10,.05,2.18),(-.30,.06,2.92),(-.39,.12,3.62)],[.125,.107,.092,.078,.060,.036,.012]),
  ([(.0,.015,1.2),(-.27,-.035,1.68),(-.68,-.075,2.12),(-1.02,-.10,2.63),(-1.10,-.04,2.83)],[.076,.062,.044,.022,.006]),
  ([(.04,.025,1.58),(.38,.12,1.99),(.71,.27,2.43),(.99,.37,2.97)],[.065,.054,.034,.009]),
  ([(-.035,.05,1.96),(.07,.41,2.24),(.14,.72,2.75),(.18,.91,3.20)],[.056,.044,.026,.008]),
  ([(-.10,.05,2.18),(-.04,-.35,2.40),(.19,-.67,2.63),(.28,-.95,2.90)],[.046,.035,.024,.007]),
  ([(-.34,.10,3.34),(-.62,.22,3.49),(-.85,.35,3.66)],[.025,.014,.004]),
  ([(.61,.23,2.3),(.84,-.04,2.59),(1.14,-.19,2.78)],[.033,.020,.005]),
 ],
 'fans':[
  ((-.40,.10,3.22),(.91,.75,.90),-.18,-.10,.55),
  ((-.80,-.06,2.57),(.72,.81,.59),-.37,.13,1.72),
  ((.66,.23,2.92),(.83,.70,.67),.45,-.13,2.45),
  ((.16,-.60,2.71),(.73,.69,.63),-.22,.18,4.30),
  ((.11,.67,3.10),(.68,.72,.60),.15,-.21,3.41),
 ]},
'b':{
 'title':'Upright field maple',
 'branches':[
  ([(0,0,0),(-.025,.018,.65),(.005,-.018,1.25),(-.045,.02,1.86),(.11,.08,2.43),(.16,.11,3.08),(.08,.12,3.87)],[.119,.102,.087,.070,.052,.031,.008]),
  ([(.005,-.018,1.23),(-.29,-.12,1.69),(-.55,-.20,2.15),(-.64,-.19,2.72),(-.74,-.12,3.08)],[.073,.060,.041,.024,.006]),
  ([(-.04,.02,1.85),(.34,.11,2.14),(.62,.16,2.66),(.65,.25,3.23)],[.056,.045,.027,.006]),
  ([(.03,.035,2.18),(.20,-.34,2.42),(.28,-.58,2.93),(.26,-.62,3.27)],[.045,.034,.019,.005]),
  ([(.12,.09,2.57),(-.01,.43,2.83),(-.15,.68,3.29),(-.18,.67,3.59)],[.033,.024,.013,.004]),
  ([(-.48,-.18,2.02),(-.74,.03,2.35),(-.97,.20,2.56)],[.031,.020,.006]),
 ],
 'fans':[
  ((.10,.09,3.34),(.70,.72,.89),.32,-.04,1.23),
  ((-.61,-.11,2.62),(.76,.75,.83),-.48,-.15,2.70),
  ((.55,.21,2.96),(.65,.70,.75),.20,.19,3.20),
  ((.21,-.48,2.95),(.64,.67,.73),-.08,.12,4.45),
 ]}}

manifest={'status':'PRIVATE_VISUAL_PROTOTYPE_NOT_QUALIFIED','blender':bpy.app.version_string,'provenance':'Original authored points and branch fan meshes in create_vegetation.py; no external image or mesh inputs','units':'metres; native Blender +Z up, glTF +Y up','geometry_contract':'Each GLB has two top-level mesh nodes with identity transforms and no wrapper objects, rigs, cameras, lights, animations or textures. Godot import root must be checked before integration.','variants':{}}
runtimes={}
for index,(key,spec) in enumerate(TREES.items()):
    source=collection('SOURCE '+key.upper()+' - '+spec['title'])
    runtime=collection('EXPORT '+key.upper()+' - two immediate meshes')
    branches=[tube('Editable '+key+' bough '+str(i),points,radii,source) for i,(points,radii) in enumerate(spec['branches'])]
    fans=[fan('Editable '+key+' foliage fan '+str(i),*specification,source) for i,specification in enumerate(spec['fans'])]
    wood=merged_copy('Tree_'+key.upper()+'_branching_trunk',branches,runtime)
    # Merge forks for smooth continuous joins rather than overlapping cylinder ends.
    bake_volume(wood,.010,740)
    ground=min(v.co.z for v in wood.data.vertices)
    for vertex in wood.data.vertices:vertex.co.z-=ground
    foliage=merged_copy('Tree_'+key.upper()+'_connected_foliage',fans,runtime)
    bake_volume(foliage,.070,1700)
    vertex_colors(wood,False,index);vertex_colors(foliage,True,index)
    for obj in branches+fans: obj.hide_render=True;obj.hide_set(True)
    source.hide_render=True
    # Only A is shown by default in the native scene. Both variants retain ground roots.
    if key=='b':
        for obj in (wood,foliage):obj.hide_set(True)
    runtimes[key]=[wood,foliage]
    bounds=[tuple(v.co) for obj in (wood,foliage) for v in obj.data.vertices]
    parts=[]
    for obj in (wood,foliage):
        obj.data.calc_loop_triangles()
        parts.append({'name':obj.name,'vertices':len(obj.data.vertices),'triangles':len(obj.data.loop_triangles),'materials':len(obj.data.materials)})
    manifest['variants'][key]={'title':spec['title'],'parts':parts,'bounds_blender':{'minimum':[min(p[i] for p in bounds) for i in range(3)],'maximum':[max(p[i] for p in bounds) for i in range(3)]},'ground_origin':[0,0,0]}

# Persist editable construction and baked runtime objects before exporting.
[o.select_set(False) for o in bpy.data.objects]
for obj in runtimes['a']:obj.select_set(True)
bpy.context.view_layer.objects.active=runtimes['a'][1]
bpy.ops.wm.save_as_mainfile(filepath=str(ART/'field_maples.blend'))
for key,objects in runtimes.items():
    [o.select_set(False) for o in bpy.data.objects]
    for obj in objects:obj.hide_set(False);obj.select_set(True)
    path=MODELS/('tree_field_maple_'+key+'.glb')
    bpy.ops.export_scene.gltf(filepath=str(path),export_format='GLB',use_selection=True,export_yup=True,export_apply=True,export_animations=False,export_cameras=False,export_lights=False,export_vertex_color='MATERIAL',export_extras=True)
    manifest['variants'][key]['glb_sha256']=hashlib.sha256(path.read_bytes()).hexdigest()
    manifest['variants'][key]['glb_bytes']=path.stat().st_size
manifest['native_sha256']=hashlib.sha256((ART/'field_maples.blend').read_bytes()).hexdigest()
(ART/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
print('TREE_PROTOTYPE_OK '+json.dumps(manifest,sort_keys=True))
