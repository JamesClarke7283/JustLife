"""Bounded Bob/Curls study built on immutable, reviewed JustLife v18 sources.

blender -b -t 4 --python art/experiments/hair_v19/create_hair_v19.py -- --age adult
Use --age child for the second proportion study; --export writes excluded staging GLBs.
No production file or shared generator is modified.
"""
import ast, bpy, hashlib, json, math, os, random, struct, sys, tempfile
from pathlib import Path
from mathutils import Vector, Matrix
from math import sin, cos, pi, sqrt

STAGE=Path(__file__).resolve().parent
PROJECT=STAGE.parents[2]
AGE=sys.argv[sys.argv.index('--age')+1] if '--age' in sys.argv else 'adult'
assert AGE in ['adult','child','teen','elder']
BASE=PROJECT/'art'
SOURCE=BASE/('characters.blend' if AGE=='adult' else f'characters_{AGE}.blend')
GENERATOR=PROJECT/'tools/create_characters.py'
BASELINE_HASHES=json.loads((PROJECT/'art/source/character_v18_production_hashes.json').read_text())
assert hashlib.sha256(SOURCE.read_bytes()).hexdigest()==BASELINE_HASHES[str(SOURCE.relative_to(PROJECT))], 'Hair v19 requires the reviewed v18 source; review and update the experiment before using a different baseline.'
bpy.ops.wm.open_mainfile(filepath=str(SOURCE))
root=bpy.data.objects['Character'];head=bpy.data.objects['Head']
hair=bpy.data.materials['Hair'];highlight=bpy.data.materials['Hair_highlight'];shadow=bpy.data.materials['Hair_shadow']

# Reuse the exact accepted age field without executing the v18 scene generator.
tree=ast.parse(GENERATOR.read_text())
names={'smoothstep','interpolate_age_height','age_warp'}
nodes=[n for n in tree.body if isinstance(n,ast.FunctionDef) and n.name in names]
nodes += [n for n in tree.body if isinstance(n,ast.Assign) and any(isinstance(t,ast.Name) and t.id=='AGE_Z' for t in n.targets)]
exec(compile(ast.Module(body=nodes,type_ignores=[]),str(GENERATOR),'exec'))

def descendants(ob):
    yield ob
    for child in ob.children:yield from descendants(child)

def nonhair_signature():
    output={}
    for ob in descendants(root):
        if ob.type!='MESH' or ob.name.startswith(('Hair_Bob','Hair_Curls')):continue
        h=hashlib.sha256()
        for row in ob.matrix_world:
            h.update(struct.pack('<4f',*row))
        sets=list(ob.data.shape_keys.key_blocks) if ob.data.shape_keys else [None]
        for key in sets:
            if key:h.update(key.name.encode());h.update(struct.pack('<f',key.value))
            for point in key.data if key else ob.data.vertices:h.update(struct.pack('<3f',*point.co))
        for vertex in ob.data.vertices:
            for group in vertex.groups:h.update(struct.pack('<If',group.group,group.weight))
        for poly in ob.data.polygons:
            h.update(struct.pack('<'+'I'*len(poly.vertices),*poly.vertices))
        output[ob.name]=h.hexdigest()
    return output

bpy.context.view_layer.update();before=nonhair_signature()
for group_name in ['Hair_Bob','Hair_Curls']:
    for ob in reversed(list(descendants(bpy.data.objects[group_name]))):bpy.data.objects.remove(ob,do_unlink=True)

def parent_keep(ob,parent):
    bpy.context.view_layer.update();world=ob.matrix_world.copy();ob.parent=parent;ob.matrix_world=world;return ob

def group(name):
    ob=bpy.data.objects.new(name,None);bpy.context.collection.objects.link(ob);return parent_keep(ob,head)

def mesh(name,vertices,faces,material=hair,parent=None,sub=0):
    data=bpy.data.meshes.new(name);data.from_pydata(vertices,[],faces);data.update()
    ob=bpy.data.objects.new(name,data);bpy.context.collection.objects.link(ob);data.materials.append(material)
    for poly in data.polygons:poly.use_smooth=True
    if sub:
        modifier=ob.modifiers.new('Flowing surface','SUBSURF');modifier.levels=sub;modifier.render_levels=sub
    if parent:parent_keep(ob,parent)
    return ob

def convert(ob):
    bpy.ops.object.select_all(action='DESELECT');ob.select_set(True);bpy.context.view_layer.objects.active=ob
    bpy.ops.object.convert(target='MESH');return bpy.context.object

def tube(name,points,radii,parent,flat=.62,sides=12):
    points=[Vector(p) for p in points];vertices=[]
    for i,p in enumerate(points):
        tangent=(points[min(i+1,len(points)-1)]-points[max(0,i-1)]).normalized()
        normal=Vector((p.x/.13,(p.y-.014)/.12,(p.z-1.623)/.145)).normalized()
        across=tangent.cross(normal).normalized();normal=across.cross(tangent).normalized()
        for j in range(sides):
            a=2*pi*j/sides;vertices.append(p+across*radii[i]*cos(a)+normal*radii[i]*sin(a)*flat)
    faces=[]
    for i in range(len(points)-1):
        for j in range(sides):faces.append((i*sides+j,i*sides+(j+1)%sides,(i+1)*sides+(j+1)%sides,(i+1)*sides+j))
    faces.extend([tuple(range(sides-1,-1,-1)),tuple((len(points)-1)*sides+j for j in range(sides))])
    return mesh(name,vertices,faces,parent=parent,sub=1)

def shell(name,surface,parent,rows=60,columns=144,thickness=.010):
    vertices=[surface(2*pi*j/columns,.006+.994*i/(rows-1)) for i in range(rows) for j in range(columns)]
    faces=[]
    for i in range(rows-1):
        for j in range(columns):faces.append(tuple(reversed((i*columns+j,i*columns+(j+1)%columns,(i+1)*columns+(j+1)%columns,(i+1)*columns+j))))
    faces.append(tuple(range(columns)))
    ob=mesh(name,vertices,faces,parent=parent,sub=1)
    solid=ob.modifiers.new('Continuous hair volume','SOLIDIFY');solid.thickness=thickness;solid.offset=-1
    return ob

def normal_at(surface,a,t):
    da=surface(a+.001,t)-surface(a-.001,t)
    dt=surface(a,min(.999,t+.001))-surface(a,max(.005,t-.001))
    normal=da.cross(dt).normalized()
    p=surface(a,t);outward=Vector((p.x,p.y-.014,(p.z-1.623)*.65))
    if normal.dot(outward)<0:normal=-normal
    return normal

# A single jaw-length envelope gives the Bob an uninterrupted silhouette. Its
# long side, shorter tucked side, and uneven nape replace identical tube locks.
bob=group('Hair_Bob')
def bob_surface(a,t):
    aa=math.atan2(sin(a),cos(a));opening=1-smoothstep(.62,1.23,abs(aa))
    hem=1.506+.011*sin(a)+.004*sin(3*a+.7)
    hem=hem*(1-opening)+(1.674-.018*sin(a+.45))*opening
    z=1.772-(1.772-hem)*t
    upper=sqrt(max(.00002,1-((z-1.623)/.150)**2)) if z>1.623 else 1.0
    taper=1-.17*smoothstep(1.59,1.49, z) if z<1.59 else 1.0
    # The broad wave directions converge toward an off-center crown and sweep
    # around the head; the smaller grooves stay part of the same surface.
    flow=a+.16*sin(pi*t)*sin(a-.35)
    broad=.0040*cos(9*flow+.9*sin(2*a))+.0015*cos(17*flow-.7*t)
    broad*=smoothstep(.05,.30,t)*(1-.30*t)
    longer_side=.008*max(0,-sin(flow))*smoothstep(.35,.72,t)
    rx=(.134+broad+longer_side)*upper*taper;ry=(.133+broad*.8)*upper*(1-.05*smoothstep(.57,1,t))
    return Vector((.024*(1-t)**2+rx*sin(flow),.014-ry*cos(flow),z+.003*sin(7*flow)*t**5))
bob_core=shell('Hair_Bob_Continuous',bob_surface,bob,thickness=.013)

def flowing_patch(name,surface,parent,a0,a1,t0,t1,width,lift):
    rows=44;columns=11;vertices=[]
    for i in range(rows):
        u=i/(rows-1);t=t0+(t1-t0)*u
        center=a0+(a1-a0)*(u*u*(3-2*u))
        span=width*(.50+.50*sin(pi*u))*(1-.87*u**5)
        for j in range(columns):
            q=-1+2*j/(columns-1);a=center+span*q
            point=surface(a,t);normal=normal_at(surface,a,t)
            fullness=max(0,1-q*q)**1.7*sin(pi*u)**.65
            vertices.append(point+normal*(-.001+lift*fullness))
    faces=[tuple(reversed((i*columns+j,i*columns+j+1,(i+1)*columns+j+1,(i+1)*columns+j))) for i in range(rows-1) for j in range(columns-1)]
    ob=mesh(name,vertices,faces,parent=parent,sub=1)
    solid=ob.modifiers.new('Rooted lock depth','SOLIDIFY');solid.thickness=.003;solid.offset=-1
    return ob

# Three unequal overlapping sweeps cross the forehead from the side part. They
# are raised sheets whose boundaries are seated in the core rather than tubes.
flowing_patch('Hair_Bob_Main_sweep',bob_surface,bob,.43,-.92,.16,.99,.31,.009)
flowing_patch('Hair_Bob_Upper_sweep',bob_surface,bob,.22,-1.40,.11,.78,.22,.006)
flowing_patch('Hair_Bob_Tucked_sweep',bob_surface,bob,.77,1.39,.20,.88,.18,.005)

# The Curls envelope is one softly varied volume. Large curls are hooked/S-like
# ridges that grow out of that volume, not a field of separate spherical beads.
curls=group('Hair_Curls')
def curls_surface(a,t):
    front=(cos(a)+1)/2;limit=2.12*(1-front)+1.22*front
    phi=.008+(limit-.008)*t
    lobes=(.0058*sin(5*a+phi*3)+.0036*sin(9*a-phi*4)+.0018*sin(15*a+phi*8))*sin(phi)
    return Vector(((.140+lobes)*sin(phi)*sin(a),.014-(.132+lobes)*sin(phi)*cos(a),1.623+(.157+lobes*.8)*cos(phi)+.007*sin(a-.5)*sin(phi)**2))
rng=random.Random(903)
curl_samples=[]
for i in range(58):
    a=i*pi*(3-sqrt(5))+.27
    # Distribute curls by area, with fewer small marks at the tapered nape.
    t=sqrt((i+.45)/58)*.95
    center=curls_surface(a,t);normal=normal_at(curls_surface,a,t)
    horizontal=Vector((cos(a),sin(a),0)).normalized();vertical=normal.cross(horizontal).normalized()
    radius=rng.uniform(.012,.023);rotation=rng.uniform(-pi,pi);turn=rng.uniform(1.15,1.72)*pi
    points=[];radii=[]
    for j in range(29):
        u=j/28;angle=rotation+turn*u
        r=radius*(1-.22*u)
        offset=horizontal*(r*cos(angle))+vertical*(r*sin(angle))
        raw=center+offset
        # Reproject the complete curl onto its envelope before raising the
        # centerline. Both tapered ends intersect the continuous base volume.
        aa=math.atan2(raw.x,-(raw.y-.014))
        unit=Vector((raw.x/.140,(raw.y-.014)/.132,(raw.z-1.623)/.157)).normalized()
        phi=math.acos(max(-1,min(1,unit.z)));front=(cos(aa)+1)/2;limit=2.12*(1-front)+1.22*front
        tt=max(.01,min(.996,(phi-.008)/(limit-.008)))
        base=curls_surface(aa,tt);nn=normal_at(curls_surface,aa,tt)
        # This curl becomes a smooth displacement field within the shared
        # envelope. No separate loop or tube can float above the scalp.
        curl_samples.append((base,.0085*(radius/.017)**.35,sin(pi*u)**.6,i))

from collections import defaultdict
from itertools import product
grid=defaultdict(list);cell_size=.022
for sample in curl_samples:grid[tuple(math.floor(v/cell_size) for v in sample[0])].append(sample)
neighbors=list(product(range(-1,2),repeat=3))
def curl_relief(a,t):
    point=curls_surface(a,t);cell=tuple(math.floor(v/cell_size) for v in point)
    strengths={}
    for delta in neighbors:
        for p,width,amount,index in grid.get(tuple(c+d for c,d in zip(cell,delta)),[]):
            distance=(point-p).length_squared
            if distance>width*width*7:continue
            value=amount*math.exp(-distance/(width*width))
            strengths[index]=max(strengths.get(index,0),value)
    amplitude=min(1.3,sum(value**4 for value in strengths.values())**.25)
    return point+normal_at(curls_surface,a,t)*(.008*amplitude)
curl_mesh=shell('Hair_Curls_Sculpted_volume',curl_relief,curls,rows=84,columns=192,thickness=.017)

# Bake precisely the existing adult head proportion and accepted age field into
# these new rigid hair meshes, then attach them to the retained Head node.
anchor=Vector((0,.005,1.458))
for group_object in [bob,curls]:
    for ob in list(descendants(group_object)):
        if ob.type not in ['MESH','CURVE']:continue
        ob=convert(ob)
        triangles=sum(len(poly.vertices)-2 for poly in ob.data.polygons)
        budget=36000 if ob.name.startswith('Hair_Curls') else 22000
        if triangles>budget:
            bpy.context.view_layer.objects.active=ob
            reduction=ob.modifiers.new('Hair surface retopology','DECIMATE');reduction.ratio=budget/triangles;reduction.use_collapse_triangulate=True
            bpy.ops.object.modifier_apply(modifier=reduction.name)
        for vertex in ob.data.vertices:vertex.co=age_warp(anchor+(vertex.co-anchor)*.91)
        for poly in ob.data.polygons:poly.use_smooth=True
        if not ob.data.uv_layers:
            uv=ob.data.uv_layers.new(name='SurfaceUV')
            for poly in ob.data.polygons:
                for loop in poly.loop_indices:
                    point=ob.data.vertices[ob.data.loops[loop].vertex_index].co;uv.data[loop].uv=(point.x+.5,point.z)

bpy.context.view_layer.update();after=nonhair_signature()
assert before==after,'Hair-only study changed accepted non-hair geometry, morphs, weights or transforms'
root['hair_revision']=19;root['hair_study_revision']=3
(STAGE/f'{AGE}_preservation.json').write_text(json.dumps({'baseline':str(SOURCE.relative_to(PROJECT)),'unchanged_meshes':len(before),'hashes':before},indent=2)+'\n')

def reset_morphs():
    for ob in descendants(root):
        if ob.type=='MESH' and ob.data.shape_keys:
            for key in ob.data.shape_keys.key_blocks:
                if key.name!='Basis':key.value=0

def export(suffix):
    reset_morphs();bpy.ops.object.select_all(action='DESELECT')
    for ob in descendants(root):ob.select_set(True)
    bpy.context.view_layer.objects.active=root
    destination=PROJECT/'assets/models'/f'character_{AGE}_hair_v19_grip{suffix}.glb'
    with tempfile.TemporaryDirectory(prefix='.justlife-export-',dir=destination.parent) as tmp:
        tmp=Path(tmp);(tmp/'.gdignore').touch();path=tmp/destination.name
        bpy.ops.export_scene.gltf(filepath=str(path),export_format='GLB',use_selection=True,export_apply=True,export_yup=True,export_animations=False,export_morph=True,export_skins=True,export_extras=True,export_cameras=False,export_lights=False)
        os.replace(path,destination)

if '--export' in sys.argv:export('')

styles=['Hair_Crop','Hair_Bob','Hair_Curls']
def show(style):
    for name in styles:
        for ob in descendants(bpy.data.objects[name]):ob.hide_render=name!=style

show('Hair_Bob');reset_morphs()
bpy.context.preferences.filepaths.save_version=0
bpy.ops.wm.save_as_mainfile(filepath=str(STAGE/f'characters_{AGE}_hair_v19.blend'))
sc=bpy.context.scene;cam=sc.camera;ratio={'adult':1,'child':.82,'teen':.91,'elder':1}[AGE]
center=Vector((0,-.008 if AGE!='elder' else -.04,root['head_height']+.139*ratio))
cam.data.ortho_scale=.47*ratio;sc.render.resolution_x=900;sc.render.resolution_y=900;sc.cycles.samples=32
views={'front':(0,-3,.03),'left':(-3,0,0),'right':(3,0,0),'back':(0,3,.02)}
for style in ['Hair_Bob','Hair_Curls']:
    show(style)
    for label,offset in views.items():
        cam.location=center+Vector(offset);cam.rotation_euler=(center-cam.location).to_track_quat('-Z','Y').to_euler()
        sc.render.filepath=str(STAGE/f'{AGE}_{style.lower()}_{label}.png');bpy.ops.render.render(write_still=True)
print('HAIR V19 COMPLETE',AGE,'unchanged non-hair meshes',len(before))
