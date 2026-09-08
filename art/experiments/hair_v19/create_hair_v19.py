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
# Preserve the recolorable material names and exact base colors. Broad specular
# lobes amplified r13's molded appearance; geometry is rebuilt below as well.
for material in [hair,highlight,shadow]:
    shader=material.node_tree.nodes.get('Principled BSDF')
    shader.inputs['Roughness'].default_value=max(.79,float(shader.inputs['Roughness'].default_value))
    shader.inputs['Specular IOR Level'].default_value=.27

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

def shell(name,surface,parent,rows=84,columns=192,thickness=.010,fitted=False):
    # A single welded pole avoids the old subdivided 192-sided crown ngon.
    # It also keeps a continuous, closed scalp surface under the hair relief.
    ring_t=[.008+.992*i/(rows-1) for i in range(rows)]
    pole=sum((surface(2*pi*j/columns,0) for j in range(columns)),Vector())/columns
    vertices=[pole]+[surface(2*pi*j/columns,t) for t in ring_t for j in range(columns)]
    faces=[(0,1+j,1+(j+1)%columns) for j in range(columns)]
    for i in range(rows-1):
        for j in range(columns):
            q=1+i*columns+j;qn=1+i*columns+(j+1)%columns
            faces.append((q,1+(i+1)*columns+j,1+(i+1)*columns+(j+1)%columns,qn))
    # A concentric inner envelope stays inside concave curl grooves. Normal-
    # offset solidification previously folded its inner skin through tight
    # turns, leaving small visible dark/skin slivers after simplification.
    count=len(vertices);center=Vector((0,.014,1.60));factor=1-thickness/.15
    if fitted:
        inner=[]
        for index,point in enumerate(vertices):
            t=0.0 if index==0 else ring_t[(index-1)//columns]
            radial=.88 if name.startswith('Hair_Bob') else .92
            # Roll the lip inward and upward. The previous concentric shell
            # put its fringe underside below the outer edge and left a cavity.
            z=point.z-.009*(1-t)**2+.009*t**6
            inner.append(Vector((point.x*radial,.014+(point.y-.014)*radial,z)))
        vertices += inner
    else:
        vertices += [center+(point-center)*factor for point in vertices.copy()]
    outer_faces=faces.copy()
    faces += [tuple(count+index for index in reversed(face)) for face in outer_faces]
    rim=1+(rows-1)*columns
    faces += [(rim+j,count+rim+j,count+rim+(j+1)%columns,rim+(j+1)%columns) for j in range(columns)]
    return mesh(name,vertices,faces,parent=parent,sub=0 if fitted else 1)

def normal_at(surface,a,t):
    da=surface(a+.001,t)-surface(a-.001,t)
    dt=surface(a,min(.999,t+.001))-surface(a,max(.005,t-.001))
    normal=da.cross(dt).normalized()
    p=surface(a,t);outward=Vector((p.x,p.y-.014,(p.z-1.623)*.65))
    if normal.dot(outward)<0:normal=-normal
    return normal

# An asymmetric, side-parted jaw-length bob. The side and nape belong to one
# surface, while flowing relief makes unequal locks instead of repeated tubes.
bob=group('Hair_Bob')
def bob_surface(a,t):
    aa=math.atan2(sin(a),cos(a))
    # Long left side and an ear-length tucked right side. The fringe falls
    # diagonally from the right part instead of ending in a straight cap rim.
    opening=1-smoothstep(.42,1.28,abs(aa))
    hem=1.494+.018*sin(a)+.005*sin(3*a+.7)
    hem+=.081*math.exp(-((aa-1.54)/.39)**2)
    fringe=1.679+.029*sin(a-.12)-.014*math.exp(-((aa+.40)/.31)**2)
    hem=hem*(1-opening)+fringe*opening
    z=1.779-(1.779-hem)*t
    dome=sqrt(max(0,1-((z-1.621)/.158)**2)) if z>1.621 else 1.0
    taper=1-.14*smoothstep(1.591,1.49,z)
    flow=a+.26*sin(pi*t)*sin(a-.35)
    # Nonuniform broad sections follow the part to the hem; fine grooves are
    # geometry, so the asset has the same strand read after glTF export.
    section=8.2*flow+.80*sin(2*flow)+.20*sin(5*flow)-.70*t
    broad=.0028*cos(section)+.00085*cos(section*2.3+.4)
    strand=.00010*sin(39*flow+1.2*sin(3*flow)-2*t)
    variation=(broad+strand)*smoothstep(.03,.25,t)
    variation*=1-.86*opening*smoothstep(.79,1,t)
    lift=.008*max(0,-sin(flow))*smoothstep(.30,.65,t)
    ear_clearance=.016*math.exp(-((aa+1.57)/.36)**2)*smoothstep(.35,.55,t)*(1-smoothstep(.80,1,t))
    rx=(.136+variation+lift+ear_clearance)*dome*taper
    ry=(.135+variation*.8)*dome*(1-.055*smoothstep(.50,1,t))
    # Slight scalloping finishes the lower layers without opening the scalp.
    tips=(.003*sin(section)+.0014*sin(section*2.3))*t**9*(1-opening)
    return Vector((.019*(1-t)**2+rx*sin(flow),.014-ry*cos(flow),z+tips))
def bob_relief(a,t):
    # Broad lock flow is part of the shared surface, so a child age warp or
    # profile view cannot reveal the borders of overlapping sheet meshes.
    displacement=0.0
    sweeps=[(.57,-.82,.08,.98,.46,.006),(.53,-1.65,.04,.91,.37,.0045),(.69,1.45,.15,.99,.28,.0035),(-.62,-1.51,.37,.995,.25,.0035)]
    for a0,a1,t0,t1,width,lift in sweeps:
        u=(t-t0)/(t1-t0)
        if not 0<u<1:continue
        center=a0+(a1-a0)*(u*u*(3-2*u))
        span=width*(.36+.64*sin(pi*u))*(1-.91*u**5)
        q=math.atan2(sin(a-center),cos(a-center))/span
        if abs(q)>=1:continue
        displacement+=lift*(1-q*q)**2*sin(pi*u)**.65
    return bob_surface(a,t)+normal_at(bob_surface,a,t)*displacement
bob_core=shell('Hair_Bob_Continuous',bob_relief,bob,rows=64,columns=160,thickness=.006,fitted=True)

# An irregular curly crop with a tapered temple/nape and a fuller, asymmetric
# crown. Its curl relief grows out of one volume; no spherical beads are used.
curls=group('Hair_Curls')
def curls_limit(a):
    front=(cos(a)+1)/2
    return 2.06*(1-front)+1.28*front+.055*sin(7*a+.7)+.025*sin(13*a-1.1)
def curls_surface_r13(a,t):
    phi=curls_limit(a)*t
    wave=(.0032*sin(5*a+phi*1.5)+.0012*sin(9*a-phi*2))*sin(phi)
    # The lower edge tucks inward as real short hair does at the temples.
    taper=1-.075*smoothstep(.78,1,t)
    rx=(.140+wave)*taper;ry=(.134+wave)*taper
    return Vector((rx*sin(phi)*sin(a)-.008*sin(phi)**2,.014-ry*sin(phi)*cos(a),1.622+(.166+wave*.65)*cos(phi)+.007*sin(a-.5)*sin(phi)**2))
def study_region(a):
    distance=abs(math.atan2(sin(a+.55),cos(a+.55)))
    return 1-smoothstep(1.65,2.45,distance)

def curls_surface(a,t):
    point=curls_surface_r13(a,t)
    # Close-fitting roots replace the detached helmet edge in the front/left
    # study region. The back remains a visible r13 control for this checkpoint.
    inset=(.006+.008*smoothstep(.58,1,t))*study_region(a)
    normal=normal_at(curls_surface_r13,a,t)
    return point-normal*inset

rng=random.Random(903)
curl_samples=[]
# Four overlapping bands of unequal hooked curls and S-shaped locks grow away from the crown.
# Stable flow and fewer sections keep individual curves readable instead of
# the previous random circular embossing and broad melted-looking dimples.
index=0
for row,(center_t,count) in enumerate([(.17,4),(.40,8),(.64,12),(.87,15)]):
    for j in range(count):
        center_a=2*pi*(j+.32*(row%2))/count+.18+rng.uniform(-.06,.06)
        center_t_j=center_t+rng.uniform(-.024,.024)
        phi=curls_limit(center_a)*center_t_j
        radius=rng.uniform(.013,.021)
        width_a=min(.66,radius/(.14*max(.24,sin(phi))))
        height_t=.139+rng.uniform(-.020,.020)
        hooked=(j+row)%3!=0
        def lock_parameter(u):
            if hooked:
                angle=-pi*.5+1.63*pi*u
                radius_taper=1-.30*u
                aa=center_a+width_a*1.2*radius_taper*cos(angle)
                tt=center_t_j+height_t*.67*radius_taper*sin(angle)+.015*(u-.5)
            else:
                aa=center_a+width_a*(.84*sin(2*pi*(u-.12))+.12*sin(pi*u))
                tt=center_t_j+height_t*(2*u-1)
            return aa,max(.009,min(.995,tt))
        for k in range(49):
            u=k/48
            aa,tt=lock_parameter(u)
            base=curls_surface(aa,tt)
            amount=.24+.76*sin(pi*u)**.65
            taper=1-.30*u if hooked else 1
            curl_samples.append((base,.0090*(radius/.017)**.3*taper,amount,index,False))
            # Subordinate strand ridges follow the true tangents of each curl.
            a0,t0=lock_parameter(max(0,u-.002));a1,t1=lock_parameter(min(1,u+.002))
            tangent=(curls_surface(a1,t1)-curls_surface(a0,t0)).normalized()
            cross=normal_at(curls_surface,aa,tt).cross(tangent).normalized()
            for strand,offset in enumerate([-.0036,.0036]):
                curl_samples.append((base+cross*offset*taper,.0018,amount,index*2+strand,True))
        index+=1

from collections import defaultdict
from itertools import product
grid=defaultdict(list);cell_size=.022
for sample in curl_samples:grid[tuple(math.floor(v/cell_size) for v in sample[0])].append(sample)
neighbors=list(product(range(-1,2),repeat=3))
def curl_relief(a,t):
    point=curls_surface(a,t);cell=tuple(math.floor(v/cell_size) for v in point)
    strengths={};fibers={}
    for delta in neighbors:
        for p,width,amount,index,is_fiber in grid.get(tuple(c+d for c,d in zip(cell,delta)),[]):
            distance=(point-p).length_squared
            if distance>width*width*7:continue
            value=amount*math.exp(-distance/(width*width))
            field=fibers if is_fiber else strengths
            field[index]=max(field.get(index,0),value)
    amplitude=min(1.45,sum(value**4 for value in strengths.values())**.25)
    # Fade to zero at the welded crown pole and tuck the curl roots inside the
    # scalloped lower edge. This prevents crown spikes and floating hairlines.
    fade=smoothstep(.02,.11,t)*(1-.78*smoothstep(.945,1,t))
    fine=min(1.35,sum(value**4 for value in fibers.values())**.25)
    return point+normal_at(curls_surface,a,t)*((.014*amplitude+.0009*fine)*fade*(1-study_region(a)))
curl_mesh=shell('Hair_Curls_Sculpted_volume',curl_relief,curls,rows=64,columns=160,thickness=.004,fitted=True)

# Separate, solid tapered locks emerge from buried roots and overlap along the
# crown-to-temple flow. Their free ends and changing depth are real geometry;
# they are not Gaussian O/S glyphs embossed on the base surface.
def curl_lock(name,a0,t0,length,width,direction,phase):
    rings=34;sides=12
    centers=[];frames=[];widths=[];depths=[]
    for index in range(rings):
        u=index/(rings-1)
        bend=1.36*pi*u
        angle=a0+direction*(.24*sin(bend)+.10*u)
        t=t0+length*u+.025*sin(bend)
        t=max(.012,min(.992,t))
        base=curls_surface(angle,t)
        normal=normal_at(curls_surface,angle,t)
        # The root begins inside the shared short undercoat, then rises over
        # the older layer before the tip narrows and folds back into the flow.
        lift=-.004*(1-u)**4+(.010+.003*sin(phase))*sin(pi*u)**.85+.003*u
        centers.append(base+normal*lift)
        frames.append(normal)
        taper=(.33+.67*sin(pi*u)**.8)*(1-.93*u**6)
        widths.append(width*taper)
        depths.append((.0036+.0010*sin(phase))*(.45+.55*sin(pi*u))*(1-.80*u**5))
    vertices=[];faces=[]
    for index,(center,normal,width_value,depth) in enumerate(zip(centers,frames,widths,depths)):
        tangent=(centers[min(index+1,rings-1)]-centers[max(0,index-1)]).normalized()
        across=tangent.cross(normal).normalized()
        outward=across.cross(tangent).normalized()
        if outward.dot(normal)<0:outward=-outward
        for side in range(sides):
            q=2*pi*side/sides
            # Subordinate lengthwise strand bands break a broad smooth lobe
            # without the sub-pixel high-frequency ridges that pinched in r13.
            strand=1+.075*cos(3*q+phase)
            vertices.append(center+across*(cos(q)*width_value)+outward*(sin(q)*depth*strand))
    for index in range(rings-1):
        for side in range(sides):
            q=index*sides+side;next_side=index*sides+(side+1)%sides
            faces.append((q,next_side,next_side+sides,q+sides))
    faces.append(tuple(reversed(range(sides))))
    faces.append(tuple((rings-1)*sides+side for side in range(sides)))
    result=mesh(name,vertices,faces,parent=curls)
    import bmesh
    bm=bmesh.new();bm.from_mesh(result.data)
    bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces))
    bm.to_mesh(result.data);bm.free()
    return result

lock_rng=random.Random(1403)
lock_index=0
for band,(start_t,length,count) in enumerate([(.055,.48,7),(.30,.47,11),(.57,.40,15)]):
    for index in range(count):
        a0=2*pi*(index+.40*(band%2))/count+.10
        if study_region(a0)<.52:continue
        jitter=lock_rng.uniform(-.05,.05)
        curl_lock('Hair_Curls_Lock_%02d'%lock_index,a0+jitter,start_t+lock_rng.uniform(-.016,.016),
                  length+lock_rng.uniform(-.035,.025),lock_rng.uniform(.0115,.0160),
                  -1 if sin(a0)<0 else 1,lock_rng.uniform(-pi,pi))
        lock_index+=1

# Bake precisely the existing adult head proportion and accepted age field into
# these new rigid hair meshes, then attach them to the retained Head node.
anchor=Vector((0,.005,1.458))
for group_object in [bob,curls]:
    for ob in list(descendants(group_object)):
        if ob.type not in ['MESH','CURVE']:continue
        ob=convert(ob)
        triangles=sum(len(poly.vertices)-2 for poly in ob.data.polygons)
        budget=36000 if ob.name.startswith('Hair_Curls') else 22000
        if triangles>budget and ob.name not in ['Hair_Bob_Continuous','Hair_Curls_Sculpted_volume']:
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
root['hair_revision']=19;root['hair_study_revision']=14
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
if '--skip-render' in sys.argv:
    print('HAIR V19 COMPLETE',AGE,'unchanged non-hair meshes',len(before));sys.exit(0)
sc=bpy.context.scene;cam=sc.camera;ratio={'adult':1,'child':.82,'teen':.91,'elder':1}[AGE]
center=Vector((0,-.008 if AGE!='elder' else -.04,root['head_height']+.139*ratio))
cam.data.ortho_scale=.47*ratio;sc.render.resolution_x=900;sc.render.resolution_y=900;sc.cycles.samples=32
views={'front':(0,-3,.03),'left':(-3,0,0),'right':(3,0,0),'threequarter':(1.8,-3,.03),'back':(0,3,.02)}
for style in ['Hair_Bob','Hair_Curls']:
    show(style)
    for label,offset in views.items():
        cam.location=center+Vector(offset);cam.rotation_euler=(center-cam.location).to_track_quat('-Z','Y').to_euler()
        sc.render.filepath=str(STAGE/f'{AGE}_{style.lower()}_{label}.png');bpy.ops.render.render(write_still=True)
print('HAIR V19 COMPLETE',AGE,'unchanged non-hair meshes',len(before))
