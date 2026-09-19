"""Original JustLife garden plants: garden trees, shrubs and flower plantings, Blender 5.2.2.

Run headless from the project root:
blender -b --factory-startup -t 2 --python-exit-code 2 --python tools/create_garden_plants.py
Add --only <name> to rebuild a single kind. The script refuses to replace any existing
output, so it is re-runnable only into a clean asset directory.

Coordinates are Godot metres (x right, y up, z toward the front) mapped to Blender by
xyz(); masses are closed lobed volumes built from editable point rings rather than bare
sphere primitives, so the foliage stays branch-led like the shipped field maples. Every
model carries exactly one mesh object named Tint: the recolourable surface for the kind
(tree bark, shrub foliage, flower blooms). No downloaded mesh, texture or bitmap input
exists anywhere in this file.
"""
import bpy, bmesh, argparse, json, math, pathlib, random, sys
from mathutils import Vector

ROOT = pathlib.Path(__file__).resolve().parents[1]
ART = ROOT/'art/garden_plants'; MODELS = ROOT/'assets/models'
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.context.scene.unit_settings.system='METRIC'
bpy.context.scene.unit_settings.scale_length=1.0

M = {}
def mat(name, hexcolor, rough=.65, metal=0, emit=0.0):
    rgb=[int(hexcolor[i:i+2],16)/255 for i in (0,2,4)]
    linear=[v/12.92 if v<=.04045 else ((v+.055)/1.055)**2.4 for v in rgb]
    m=bpy.data.materials.new(name); m.diffuse_color=(*linear,1)
    m.use_nodes=True; p=m.node_tree.nodes.get('Principled BSDF')
    p.inputs['Base Color'].default_value=m.diffuse_color
    p.inputs['Roughness'].default_value=rough; p.inputs['Metallic'].default_value=metal
    M[name]=m; return m
for n,h,r in [
    ('bark','6E5744',.92),('bark_light','8A6E52',.92),('bark_pale','A18A6B',.9),
    ('leaf_dark','3F6B3E',.88),('leaf_mid','4F7C45',.88),('leaf_light','6C9A54',.88),
    ('leaf_olive','5F7B42',.9),('leaf_sage','8A9B74',.9),('leaf_lime','8FAE5E',.88),
    ('leaf_blue','5C7A6E',.9),('leaf_bronze','7A6A3C',.9),('leaf_burgundy','7A4340',.9),
    ('soil','42352D',.95),('stone','B6B2A6',.8),
    ('bloom_white','F4F0E2',.6),('bloom_cream','EFE2B8',.6),('bloom_yellow','E8C44A',.55),
    ('bloom_gold','D99A2B',.55),('bloom_orange','DC7F35',.55),('bloom_red','C4503F',.55),
    ('bloom_pink','DE93AC',.55),('bloom_rose','C4677F',.55),('bloom_magenta','B4508A',.55),
    ('bloom_purple','8A6BB0',.55),('bloom_violet','6B5AA0',.55),('bloom_blue','7189C8',.55),
    ('bloom_lilac','B8A6D6',.55),('bloom_peach','E7A98A',.55),('bloom_crimson','A83A44',.55),
    ('tint_neutral','C9C6BC',.6)]:
    mat(n,h,r)

ACTIVE=[]            # named parts of the item being built that are not the recolourable surface
TINT=[]              # parts that are baked into the single recolourable Tint surface
SINK=[ACTIVE]        # helpers append here; the tinted() block redirects it into TINT

class tinted:
    """Parts created inside this block become the recolourable Tint mesh."""
    def __enter__(self): SINK.append(TINT)
    def __exit__(self,*exc): SINK.pop()

SPREAD=[1.0,1.0,1.0]   # per-kind x / y / z stretch for part positions
def xyz(p): return (p[0]*SPREAD[0],-p[2]*SPREAD[2],p[1]*SPREAD[1])
def part(o): SINK[-1].append(o); return o
def finish(o,n,m): o.name=n; o.data.materials.append(M[m]); return part(o)

def box(n,p,s,m,bevel=.02):
    bpy.ops.mesh.primitive_cube_add(size=1,location=xyz(p)); o=bpy.context.object
    o.dimensions=(s[0],s[2],s[1]); bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
    if bevel:
        mod=o.modifiers.new('Soft clipped edges','BEVEL'); mod.width=bevel; mod.segments=3
        mod=o.modifiers.new('Weighted corner normals','WEIGHTED_NORMAL')
    return finish(o,n,m)

def ell(n,p,s,m,seg=(16,8),rot=None):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=seg[0],ring_count=seg[1],location=xyz(p)); o=bpy.context.object
    o.scale=(s[0],s[2],s[1]); bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
    if rot: o.rotation_euler=rot
    for f in o.data.polygons: f.use_smooth=True
    return finish(o,n,m)

def cyl(n,p,r,h,m,top=None,axis='Y',verts=20):
    bpy.ops.mesh.primitive_cone_add(vertices=verts,radius1=r,radius2=r if top is None else top,depth=h,location=xyz(p)); o=bpy.context.object
    if axis=='X': o.rotation_euler=(0,math.pi/2,0)
    elif axis=='Z': o.rotation_euler=(math.pi/2,0,0)
    bevel=o.modifiers.new('Rounded rims','BEVEL'); bevel.width=.01; bevel.segments=2
    for f in o.data.polygons: f.use_smooth=True
    return finish(o,n,m)

def rod(n,a,b,r,m,verts=8):
    av,bv=Vector(xyz(a)),Vector(xyz(b)); d=bv-av
    bpy.ops.mesh.primitive_cylinder_add(vertices=verts,radius=r,depth=d.length,location=(av+bv)/2); o=bpy.context.object
    o.rotation_euler=d.to_track_quat('Z','Y').to_euler()
    for f in o.data.polygons: f.use_smooth=True
    return finish(o,n,m)

def torus(n,p,major,minor,m,seg=(20,8)):
    bpy.ops.mesh.primitive_torus_add(major_segments=seg[0],minor_segments=seg[1],major_radius=major,minor_radius=minor,location=xyz(p)); o=bpy.context.object
    for f in o.data.polygons: f.use_smooth=True
    return finish(o,n,m)

def newmesh(name,verts,faces,m,smooth=True):
    data=bpy.data.meshes.new(name+' authored geometry'); data.from_pydata(verts,[],faces); data.update()
    bm=bmesh.new(); bm.from_mesh(data); bmesh.ops.remove_doubles(bm,verts=bm.verts,dist=1e-5)
    bmesh.ops.recalc_face_normals(bm,faces=bm.faces); bm.to_mesh(data); bm.free()
    if smooth:
        for f in data.polygons: f.use_smooth=True
    o=bpy.data.objects.new(name,data); bpy.context.scene.collection.objects.link(o)
    return finish(o,name,m)

def tube(n,points,radii,m,sides=8):
    """Tapered branch: authored centre line and radii, bark fluting subordinate to it."""
    pts=[Vector(xyz(p)) for p in points]; verts=[]; faces=[]
    for i,p in enumerate(pts):
        direction=(pts[min(i+1,len(pts)-1)]-pts[max(i-1,0)]).normalized()
        side=direction.cross(Vector((0,0,1)))
        if side.length<.05: side=direction.cross(Vector((1,0,0)))
        side.normalize(); other=direction.cross(side).normalized()
        for j in range(sides):
            angle=math.tau*j/sides
            r=max(.016,radii[i])*(1+.05*math.sin(j*3.0+i*.7))
            verts.append(p+r*(math.cos(angle)*side+math.sin(angle)*other))
    for i in range(len(pts)-1):
        for j in range(sides):
            faces.append((i*sides+j,i*sides+(j+1)%sides,(i+1)*sides+(j+1)%sides,(i+1)*sides+j))
    faces.append(tuple(reversed(range(sides))))
    faces.append(tuple((len(pts)-1)*sides+j for j in range(sides)))
    return newmesh(n,verts,faces,m)

def profile(t,kind):
    """Vertical span (0 at the base) and horizontal radius of a lobed mass."""
    rise,ring=(1-math.cos(math.pi*t))/2, math.sin(math.pi*t)
    if kind=='ball': return rise,ring
    if kind=='flat': return rise,ring**.4
    if kind=='tall': return rise,ring**1.7
    if kind=='tear': return rise,ring**.45*(.3+.7*t)
    if kind=='strand': return rise,ring**.28*(.2+.8*t)
    raise ValueError(kind)

def lump(n,p,s,m,kind='ball',seed=0,rings=5,segments=14,spin=0,centre_y=False):
    """Irregular lobed foliage mass from editable rings; p is the centre in x/z and, unless
    centre_y, the base in y. centre_y=True places p[1] at the middle of the mass so the low
    ring is open and surrounding branches can stand proud of it."""
    rx,ry,rz=s; oy=p[1]-ry if centre_y else p[1]
    verts=[xyz((p[0],oy,p[2]))]; faces=[]
    for i in range(1,rings):
        t=i/rings; rise,ring=profile(t,kind)
        for j in range(segments):
            a=math.tau*j/segments+spin
            r=ring*(1+.17*math.sin(3*a+seed)+.10*math.sin(5*a-seed*.7)+.055*math.sin(7*a+seed*1.4))
            verts.append(xyz((p[0]+rx*r*math.cos(a),oy+ry*rise,p[2]+rz*r*math.sin(a))))
    top=len(verts); verts.append(xyz((p[0],oy+ry,p[2])))
    for j in range(segments): faces.append((0,1+j,1+(j+1)%segments))
    for i in range(rings-2):
        for j in range(segments):
            faces.append((1+i*segments+j,1+i*segments+(j+1)%segments,
                          1+(i+1)*segments+(j+1)%segments,1+(i+1)*segments+j))
    last=1+(rings-2)*segments
    for j in range(segments): faces.append((top,last+(j+1)%segments,last+j))
    return newmesh(n,verts,faces,m)

def aim(o,gdir):
    """Rotate a part whose long axis is local Godot -z onto a Godot direction."""
    d=Vector(xyz(gdir)); o.rotation_mode='QUATERNION'
    o.rotation_quaternion=Vector((0,1,0)).rotation_difference(d.normalized())
    return o

def blade(n,base,tip,width,m,thick=.012):
    """Flat leaf blade spanning two Godot points; base and tip are clamped to the soil line."""
    base=(base[0],max(base[1],0.0),base[2]); tip=(tip[0],max(tip[1],0.0),tip[2])
    dx,dy,dz=tip[0]-base[0],tip[1]-base[1],tip[2]-base[2]
    length=math.sqrt(dx*dx+dy*dy+dz*dz)
    o=ell(n,(base[0]+dx/2,base[1]+dy/2,base[2]+dz/2),(width,thick,length/2),m,seg=(12,6))
    return aim(o,(dx,dy,dz))

def fit_scale(target):
    """Scale the whole item uniformly about the ground line so its height reaches the
    catalogue height, never exceeding the catalogue width or depth. Columnar and flat
    styles legitimately stay narrower of their own accord; they are left as authored."""
    objects=ACTIVE+TINT
    tw,th,td=target
    bpy.context.view_layer.update()
    corners=[o.matrix_world@Vector(v.co) for o in objects for v in o.data.vertices]
    size=[max(c[i] for c in corners)-min(c[i] for c in corners) for i in range(3)]
    width,depth,height=size[0],size[1],size[2]
    if height<=0: return 1.0
    factor=min(th/height, tw/width, td/depth)
    if factor<=1.005: return 1.0
    for o in objects:
        o.location=(o.location[0]*factor,o.location[1]*factor,o.location[2]*factor)
        o.scale=(factor,factor,factor)
    bpy.ops.object.select_all(action='DESELECT')
    for o in objects: o.select_set(True)
    bpy.context.view_layer.objects.active=objects[0]
    bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
    return factor

def seat_on_ground():
    """Drop or lift the item so its lowest authored point rests exactly on y=0: a leaning
    trunk's flared foot and a flower's soil-hugging foliage must not sink below the plot."""
    objects=ACTIVE+TINT
    bpy.context.view_layer.update()
    low=min((o.matrix_world@Vector(v.co)).z for o in objects for v in o.data.vertices)
    if abs(low)<1e-4: return
    for o in objects: o.location.z-=low

def merged(name,objects,m):
    """Bake the parts of the recolourable surface into one mesh, keeping their shading."""
    bpy.context.view_layer.update()
    retired=bpy.data.meshes.get(name)
    if retired: retired.name=name+' of the previous kind'
    verts=[]; faces=[]; flags=[]
    for o in objects:
        off=len(verts); basis=o.matrix_basis
        verts.extend(tuple(basis@v.co) for v in o.data.vertices)
        for face in o.data.polygons:
            faces.append(tuple(off+i for i in face.vertices)); flags.append(face.use_smooth)
    for o in objects:
        data=o.data; bpy.data.objects.remove(o,do_unlink=True)
        if data.users==0: bpy.data.meshes.remove(data)
    data=bpy.data.meshes.new(name); data.from_pydata(verts,[],faces); data.update()
    for face,flag in zip(data.polygons,flags): face.use_smooth=flag
    bm=bmesh.new(); bm.from_mesh(data); bmesh.ops.recalc_face_normals(bm,faces=bm.faces); bm.to_mesh(data); bm.free()
    data.materials.append(M[m])
    o=bpy.data.objects.new(name,data); bpy.context.scene.collection.objects.link(o)
    return part(o)

def merge_tint():
    """Collapse every part built inside tinted() into the single Tint surface. The surface
    keeps the material its parts use most, so an un-recoloured model still reads correctly
    (bark stays bark, foliage stays green, blooms stay bloom-coloured) while the catalogue
    can override that one named surface for a player's colour choice."""
    if not TINT: return None
    tally={}
    for o in TINT:
        for material in o.data.materials:
            tally[material.name]=tally.get(material.name,0)+1
    dominant=max(tally,key=lambda k:tally[k]) if tally else 'tint_neutral'
    surface=merged('Tint',list(TINT),dominant); del TINT[:]; return surface

def ball_mass(prefix,center,radius,count,seed,m,kind='ball',size=.52,squash=1.0):
    """Unequal lumps filling a crown volume, not one sphere primitive: lump centres ride on
    the surface of a sphere so the silhouette stays round while the perimeter stays broken."""
    R=random.Random(seed); cx,cy,cz=center; b=radius*size
    lump(prefix,(cx,cy,cz),(b,b*squash,b),m,kind,seed,centre_y=True)
    for i in range(count):
        a=math.tau*i/count+R.uniform(-.28,.28); ph=R.uniform(-1.05,1.05)
        u=R.uniform(.58,.78); s=b*R.uniform(.72,1.05)
        lump(prefix,(cx+math.cos(a)*math.cos(ph)*u*radius,cy+math.sin(ph)*u*radius*squash,cz+math.sin(a)*math.cos(ph)*u*radius),
             (s,s*squash,s),m,kind,seed+i*2.7,centre_y=True)

def ground_clump(seed,m='leaf_dark',width=.5,height=.15,count=5):
    """Low planting foliage at the foot of a bedding or border flower: flat masses seated on
    the soil line, so only their upper half shows and the bed keeps a soft carpet edge."""
    R=random.Random(seed)
    lump('Ground foliage',(0,0,0),(width*.32,height,width*.32),m,'flat',seed)
    for i in range(count):
        a=math.tau*i/count+R.uniform(-.3,.3); d=R.uniform(.5,.82)*width*.32
        r=width*.2*R.uniform(.8,1.15)
        lump('Ground foliage',(math.cos(a)*d,0,math.sin(a)*d),(r,height*.8,r),m if i%2 else 'leaf_mid','flat',seed+i*3.1)

def ray_bloom(name,center,r,petals,petal_m,core_m,seed=0,pitch=.06,core=.44):
    """Flat rayed head: disc plus radiating petals."""
    cx,cy,cz=center
    for i in range(petals):
        a=math.tau*i/petals+seed
        ell(name+' petal',(cx+math.sin(a)*r*.62,cy+math.sin(seed+i)*.004,cz+math.cos(a)*r*.62),
            (r*.2,.012,r*.52),petal_m,seg=(10,6),rot=(pitch,a,0))
    ell(name+' disc',(cx,cy+.004,cz),(r*core,.02,r*core),core_m,seg=(14,8))

# ---------------------------------------------------------------- Trees (kind tree_garden)
# Authored footprint 1.8 x 1.8 m, height 2.4 m; the catalogue scales small/medium/large.
# The Tint of a garden tree is its bark: trunk, boughs and branch tips.

def tree_crown(spread=.95,low=1.55,up=2.2,radius=.72,count=9,seed=1,kind='ball',squash=1.0,
               m='leaf_mid',tips=6,tip_len=.3,tip_r=.032):
    R=random.Random(seed)
    for i in range(tips):
        a=math.tau*i/tips+.4*seed; d=R.uniform(.34,.56)*spread
        base=(math.sin(a)*d*.45,R.uniform(.75,.9)*low,math.cos(a)*d*.45)
        tip=(math.sin(a)*(d+tip_len),R.uniform(.95,1.02)*up,math.cos(a)*(d+tip_len))
        with tinted(): tube('Outer branch',[base,tip],[tip_r,tip_r*.4],'bark')
    ball_mass('Crown foliage',(0,(low+up)*.5,0),radius,count,seed,m,kind=kind,squash=squash)

def tree_garden_a():
    with tinted():
        tube('Trunk',[(0,0,0),(.03,.2,0),(.02,.55,0),(-.04,.95,.02)],[.16,.125,.108,.092],'bark')
        for a,h,rad in [(.5,1.0,.062),(2.4,1.12,.056),(4.3,1.22,.05)]:
            tube('Bough',[(.02,h-.1,0),(math.sin(a)*.3,h+.3,math.cos(a)*.3),(math.sin(a)*.62,h+.6,math.cos(a)*.62)],[rad,rad*.62,.022],'bark')
    tree_crown(spread=1.02,seed=11,radius=.83,count=9)

def tree_garden_b():
    with tinted():
        tube('Trunk',[(0,0,0),(.02,.3,0),(-.02,.7,0),(.02,1.1,0)],[.15,.12,.10,.084],'bark')
        for a,h in [(.7,.62),(2.8,.82),(4.9,.52)]:
            tube('Steep bough',[(0,h,0),(math.sin(a)*.14,h+.52,math.cos(a)*.14),(math.sin(a)*.22,h+1.05,math.cos(a)*.22)],[.055,.038,.018],'bark')
    ball_mass('Columnar foliage',(0,1.5,0),.3,7,21,'leaf_dark',kind='tall',squash=2.1)
    lump('Crown tip',(-.02,2.3,0),(.15,.22,.15),'leaf_mid','tall',22)

def tree_garden_c():
    with tinted():
        tube('Trunk',[(0,0,0),(-.02,.36,0),(.03,.86,0)],[.155,.12,.098],'bark')
        tube('Arching bough',[(0,.78,0),(.08,1.04,0),(.44,1.38,.05),(.78,1.68,.09)],[.055,.045,.032,.014],'bark')
    lump('Weeping crown',(0,1.92,.05),(.82,.32,.82),'leaf_mid','ball',31)
    R=random.Random(31)
    for i in range(9):
        a=math.tau*i/9
        d=R.uniform(.38,.56); top=R.uniform(1.8,2.04)
        x,z=math.sin(a)*d,math.cos(a)*d
        lump('Weeping strand',(x,top-.72-.08*(i%3),z),(.19,.6,.19),'leaf_dark' if i%2 else 'leaf_mid','strand',31+i*2.1)

def tree_garden_d():
    with tinted(): tube('Trunk',[(0,0,0),(.01,.4,0),(-.02,.85,0)],[.15,.12,.095],'bark')
    for r,h,m in [(.88,.8,'leaf_dark'),(.72,1.18,'leaf_mid'),(.56,1.56,'leaf_dark'),(.4,1.92,'leaf_mid'),(.25,2.18,'leaf_dark')]:
        cyl('Tiered branch whorl',(0,h,0),r,.2,m,top=r*.3,verts=16)
    lump('Conifer tip',(0,2.22,0),(.15,.16,.15),'leaf_mid','tall',41,rings=4,segments=10)

def tree_garden_e():
    with tinted():
        for a in (.4,2.5,4.6):
            tube('Vase stem',[(math.sin(a)*.16,0,math.cos(a)*.16),
                              (math.sin(a)*.26,.6,math.cos(a)*.26),
                              (math.sin(a)*.66,1.16,math.cos(a)*.66)],[.058,.046,.025],'bark')
        for a in (1.4,3.6):
            tube('Outer stem',[(math.sin(a)*.2,0,math.cos(a)*.2),
                               (math.sin(a)*.44,.56,math.cos(a)*.44),
                               (math.sin(a)*.82,.98,math.cos(a)*.82)],[.05,.038,.02],'bark')
    tree_crown(spread=1.0,low=1.5,up=2.3,radius=.74,count=10,seed=51,tips=7,tip_len=.24,tip_r=.026)

def tree_garden_f():
    with tinted():
        tube('Pollarded trunk',[(0,0,0),(.02,.32,0),(-.02,.74,0),(.03,1.42,0)],[.17,.14,.118,.098],'bark')
        for a in (.2,1.9,3.6,5.3):
            tube('Pollard arm',[(math.sin(a)*.16,1.5,math.cos(a)*.16),(math.sin(a)*.48,1.66,math.cos(a)*.48),
                                (math.sin(a)*.76,1.78,math.cos(a)*.76)],[.082,.06,.028],'bark')
    ball_mass('Flat crown',(0,2.06,0),.74,11,61,'leaf_mid',kind='flat',size=.62,squash=.42)

def tree_garden_g():
    with tinted():
        tube('Trunk',[(0,0,0),(.015,.4,0),(-.015,.86,0),(.01,1.34,0)],[.14,.115,.096,.082],'bark')
        for a in (.9,2.7,4.4):
            tube('Appressed bough',[(.01,1.34,0),(math.sin(a)*.13,1.76,math.cos(a)*.13),
                                    (math.sin(a)*.21,2.2,math.cos(a)*.21)],[.05,.034,.016],'bark')
    ball_mass('Fastigiate crown',(0,1.8,0),.3,8,71,'leaf_mid',kind='tall',squash=2.6)

def tree_garden_h():
    R=random.Random(81)
    with tinted():
        tube('Trunk',[(0,0,0),(.02,.28,0),(-.02,.62,0),(.03,.98,0)],[.145,.118,.098,.082],'bark')
        for a in (.8,2.5,4.2):
            tube('Rounded bough',[(.02,.88,0),(math.sin(a)*.28,1.2,math.cos(a)*.28),
                                  (math.sin(a)*.44,1.42,math.cos(a)*.44)],[.05,.042,.02],'bark')
        for i in range(9):
            a=math.tau*i/9+.3; d=R.uniform(.3,.62)
            ell('Ripe fruit',(math.sin(a)*d,R.uniform(1.52,1.98),math.cos(a)*d),(.045,.045,.045),'bloom_red',seg=(10,6))
    tree_crown(spread=.95,low=1.4,up=2.16,radius=.78,count=10,seed=82,tips=7,tip_len=.3,tip_r=.028)

def tree_garden_i():
    with tinted(): tube('Palm trunk',[(0,0,0),(.05,.52,0),(.03,1.04,0),(-.04,1.56,0),(.02,2.02,0)],[.15,.13,.115,.1,.088],'bark')
    R=random.Random(91)
    for i in range(9):
        a=math.tau*i/9; d=R.uniform(.6,.74); droop=R.uniform(.14,.3)
        base=(math.sin(a)*.1,2.06,math.cos(a)*.1)
        mid=(math.sin(a)*(d+.16),2.08,math.cos(a)*(d+.16))
        tip=(math.sin(a)*d,2.06-droop,math.cos(a)*d)
        blade('Palm frond',base,mid,.1,'leaf_dark',thick=.014)
        blade('Palm frond tip',mid,tip,.07,'leaf_mid',thick=.012)
    lump('Crown bud',(0,2.08,0),(.11,.12,.11),'leaf_olive','ball',92,rings=4,segments=10)

def tree_garden_j():
    with tinted():
        tube('Leaning trunk',[(0,0,0),(.13,.34,0),(.28,.62,-.02),(.36,.92,.02)],[.18,.15,.128,.114],'bark')
        for a in (.3,2.2,3.9):
            tube('Gnarly bough',[(.34+math.sin(a)*.06,.9,math.cos(a)*.06),(.4+math.sin(a)*.38,1.3,math.cos(a)*.38),
                                 (.46+math.sin(a)*.56,1.6,math.cos(a)*.56)],[.07,.05,.022],'bark')
    ball_mass('Wide gnarly crown',(.36,1.86,0),.74,11,101,'leaf_mid',kind='ball',size=.56)

TREES={'a':tree_garden_a,'b':tree_garden_b,'c':tree_garden_c,'d':tree_garden_d,'e':tree_garden_e,
       'f':tree_garden_f,'g':tree_garden_g,'h':tree_garden_h,'i':tree_garden_i,'j':tree_garden_j}

# @@SHRUBS@@
# ---------------------------------------------------------------- Shrubs (kind shrub)
# Authored footprint 0.8 x 0.8 m, height 0.7 m. The Tint of a shrub is its foliage mass,
# so every shrub except the two clipped formal shapes builds its greenery inside tinted().

def shrub_foliage(specs):
    """specs: (x, z, width, depth, base, height, profile, material, seed)."""
    for x,z,w,d,base,h,kind,m,seed in specs:
        lump('Foliage',(x,base,z),(w*.5,h,d*.5),m,kind,seed)

def shrub_01():   # rounded dome of overlapping lobes
    with tinted(): shrub_foliage([(0,0,.7,.7,0,.38,'ball','leaf_mid',1),(.07,.04,.52,.52,.12,.52,'ball','leaf_dark',2),(-.06,-.04,.42,.44,.3,.4,'ball','leaf_light',3)])

def shrub_02():   # spiky architectural yucca
    with tinted(): shrub_foliage([(0,0,.4,.4,0,.2,'ball','leaf_sage',11)])
    for i in range(10):
        a=math.tau*i/10
        blade('Yucca blade',(math.sin(a)*.05,.1,math.cos(a)*.05),(math.sin(a)*.26,.66,math.cos(a)*.26),.05,'leaf_olive',thick=.016)

def shrub_03():   # sprawling ground juniper, deliberately lower than the domes
    with tinted():
        for i in range(8):
            a=i*2.39; d=.14+i*.011
            lump('Sprawling runner',(math.sin(a)*d,0,math.cos(a)*d),(.2,.45,.2),'leaf_sage','flat',21+i,rings=4,segments=10)

def shrub_04():   # upright flowering fuchsia
    with tinted(): shrub_foliage([(0,0,.5,.5,0,.12,'flat','leaf_dark',31)])
    for i in range(7):
        a=math.tau*i/7
        rod('Flower stem',(math.sin(a)*.06,.16,math.cos(a)*.06),(math.sin(a)*.26,.6,math.cos(a)*.26),.009,'leaf_mid')
        ell('Urn bloom',(math.sin(a)*.27,.64,math.cos(a)*.27),(.07,.09,.07),
            ['bloom_magenta','bloom_pink','bloom_purple','bloom_lilac'][i%4],seg=(10,8))

def shrub_05():   # low mat
    with tinted(): shrub_foliage([(0,0,.68,.66,0,.5,'flat','leaf_mid',41),(.18,-.12,.42,.36,0,.38,'flat','leaf_light',42),(-.2,.11,.38,.4,0,.34,'flat','leaf_dark',43)])

def shrub_06():   # ball on a standard
    cyl('Standard stem',(0,.15,0),.035,.3,'bark_pale',verts=10)
    with tinted():
        shrub_foliage([(0,0,.36,.36,.26,.5,'tear','leaf_dark',51)])
        for i in range(5):
            a=math.tau*i/5
            lump('Skirt foliage',(math.sin(a)*.3,.05,math.cos(a)*.3),(.12,.1,.12),'leaf_mid','ball',52+i)

def shrub_07():   # box-clipped cube, a formal shape; the clipped foliage is the tintable mass
    with tinted(): box('Clipped boxwood',(0,.29,0),(.64,.58,.64),'leaf_dark',.01)
    box('Top ridge',(0,.59,0),(.56,.05,.56),'leaf_mid',.008)

def shrub_08():   # tiered variegated shrub
    with tinted():
        shrub_foliage([(0,0,.76,.76,0,.2,'ball','leaf_dark',71),(0,0,.58,.58,.26,.18,'ball','leaf_light',72),(0,0,.4,.4,.46,.18,'ball','leaf_mid',73)])
        ell('Tip tuft',(0,.66,0),(.16,.1,.16),'leaf_lime',seg=(12,8))

def shrub_09():   # wide low spreader
    with tinted(): shrub_foliage([(0,0,.7,.68,0,.48,'flat','leaf_light',81),(.14,.1,.42,.4,0,.36,'flat','leaf_mid',82),(-.13,-.08,.36,.38,0,.32,'flat','leaf_dark',83)])

def shrub_10():   # clipped cone, a formal shape
    with tinted():
        shrub_foliage([(0,0,.42,.42,0,.16,'ball','leaf_dark',91)])
        cyl('Cone foliage',(0,.3,0),.32,.6,'leaf_olive',top=.05,verts=16)
        cyl('Cone upper tier',(0,.5,0),.17,.36,'leaf_mid',top=.03,verts=16)
        torus('Cone base rim',(0,.04,0),.32,.035,'leaf_dark',seg=(18,8))

def shrub_11():   # soft mound with seed heads
    with tinted():
        shrub_foliage([(0,0,.7,.7,0,.5,'ball','leaf_mid',101)])
        for i in range(8):
            a=math.tau*i/8
            ell('Seed head',(math.sin(a)*.28,.5+(i%2)*.07,math.cos(a)*.28),(.032,.032,.032),'bloom_cream',seg=(8,6))

def shrub_12():   # clipped yew pyramid
    with tinted():
        cyl('Conical clipped yew',(0,.33,0),.32,.66,'leaf_dark',top=.06,verts=14)
        cyl('Second tier',(0,.36,0),.22,.44,'leaf_mid',top=.05,verts=14)
        ell('Clipped finial',(0,.66,0),(.09,.07,.09),'leaf_light',seg=(10,6))

def shrub_13():   # loose open canes carrying oval leaves
    for i in range(7):
        a=math.tau*i/7
        rod('Shrub cane',(math.sin(a)*.05,0,math.cos(a)*.05),(math.sin(a)*.2,.42,math.cos(a)*.2),.014,'bark_light')
    with tinted():
        for i in range(7):
            a=math.tau*i/7; b=a+.5
            blade('Oval leaf',(math.sin(a)*.21,.34,math.cos(a)*.21),(math.sin(a)*.36,.56,math.cos(a)*.36),.08,'leaf_mid')
            blade('Oval leaf',(math.sin(b)*.18,.2,math.cos(b)*.18),(math.sin(b)*.32,.44,math.cos(b)*.32),.07,'leaf_mid')

def shrub_14():   # clipped ring stacked on a short block, then a domed crown
    box('Clipped block',(0,.08,0),(.64,.16,.64),'leaf_dark',.01)
    torus('Clipped ring',(0,.28,0),.3,.13,'leaf_dark',seg=(22,10))
    with tinted():
        lump('Ring crown',(0,.42,0),(.2,.16,.2),'leaf_mid','ball',141,rings=4,segments=12)
        ell('Domе crown',(0,.6,0),(.14,.08,.14),'leaf_light',seg=(14,8))

def shrub_15():   # berry shrub on a short stem
    cyl('Shrub trunk',(0,.09,0),.026,.18,'bark_light',verts=8)
    with tinted(): shrub_foliage([(0,0,.7,.68,.2,.46,'ball','leaf_dark',151)])
    for i in range(6):
        a=math.tau*i/6
        ell('Berry',(math.sin(a)*.2,.4+(i%2)*.07,math.cos(a)*.2),(.035,.035,.035),'bloom_orange',seg=(8,6))

def shrub_16():   # flat-topped layered spreader
    with tinted():
        shrub_foliage([(0,0,.78,.78,0,.24,'flat','leaf_mid',161),(0,0,.6,.6,.24,.22,'flat','leaf_light',162),(0,0,.42,.42,.44,.2,'flat','leaf_lime',163)])
        ell('Flattened top',(0,.64,0),(.26,.06,.26),'leaf_dark',seg=(14,8))

def shrub_17():   # burgundy fountain of arching canes
    with tinted(): shrub_foliage([(0,0,.3,.3,0,.22,'ball','leaf_burgundy',171)])
    for i in range(9):
        a=math.tau*i/9
        rod('Arching cane',(math.sin(a)*.04,.16,math.cos(a)*.04),(math.sin(a)*.4,.66,math.cos(a)*.4),.009,'bark_light')
        ell('Autumn leaf',(math.sin(a)*.3,.5,math.cos(a)*.3),(.06,.012,.06),'leaf_bronze',seg=(10,6))

def shrub_18():   # upright blue conifer shrub
    with tinted(): shrub_foliage([(0,0,.62,.62,0,.42,'tall','leaf_blue',181)])
    for i in range(5):
        a=math.tau*i/5
        rod('Upright shoot',(math.sin(a)*.1,.2,math.cos(a)*.1),(math.sin(a)*.16,.7,math.cos(a)*.16),.008,'leaf_mid')

def shrub_19():   # formal rope-swag topiary on a short clear stem
    cyl('Topiary stem',(0,.16,0),.035,.32,'bark_pale',verts=10)
    torus('Rope swag ring',(0,.42,0),.3,.1,'leaf_burgundy',seg=(22,10))
    with tinted():
        for i in range(4):
            a=math.tau*i/4
            ell('Topiary ball',(math.sin(a)*.25,.5,math.cos(a)*.25),(.17,.16,.17),'leaf_dark',seg=(12,8))
        ell('Topiary crown',(0,.62,0),(.16,.1,.16),'leaf_mid',seg=(14,8))

def shrub_20():   # low mounded flowering heather
    for i in range(12):
        a=math.tau*i/12
        rod('Heather stem',(math.sin(a)*.12,0,math.cos(a)*.12),(math.sin(a)*.28,.46+(i%3)*.06,math.cos(a)*.28),.007,'leaf_dark')
        ell('Heather bell',(math.sin(a)*.28,.5+(i%3)*.06,math.cos(a)*.28),(.03,.045,.03),
            ['bloom_magenta','bloom_rose','bloom_purple'][i%3],seg=(8,6))
    with tinted(): shrub_foliage([(0,0,.6,.6,0,.22,'flat','leaf_mid',201)])

SHRUBS={f'{i:02d}':globals()[f'shrub_{i:02d}'] for i in range(1,21)}

# ---------------------------------------------------------------- Flowers (kind flowers)
# Authored footprint 0.5 x 0.5 m, height 0.45 m. The Tint of a flower planting is its
# bloom, so every flower head and its colour mass is built inside tinted().

def stem_to(name,tip,r=.009,m='leaf_mid'):
    x,y,z=tip
    rod(name,(x*.3,0,z*.3),(x,y,z),r,m)

def foliage_rosette(m='leaf_dark'):
    for i in range(8):
        a=math.tau*i/8
        blade('Rosette leaf',(math.sin(a)*.04,0,math.cos(a)*.04),(math.sin(a)*.17,.06,math.cos(a)*.17),.05,m)

def flower_01():   # daisy bedding
    foliage_rosette()
    ground_clump(1,'leaf_dark',.5,.14,5)
    with tinted():
        for i in range(3):
            a=math.tau*i/3+.5; x,z=math.sin(a)*.08,math.cos(a)*.08
            stem_to('Daisy stem',(x,.32,z),.008)
            ray_bloom('Daisy',(x,.33,z),.08,12,'bloom_white','bloom_yellow',seed=i*.9)

def flower_02():   # lavender spike
    for i in range(8):
        a=math.tau*i/8
        blade('Narrow leaf',(math.sin(a)*.05,.02,math.cos(a)*.05),(math.sin(a)*.1,.24,math.cos(a)*.1),.02,'leaf_sage',thick=.008)
    with tinted():
        for i in range(9):
            x,z=(i%3-1)*.12,(i//3-1)*.12
            stem_to('Lavender stem',(x,.42,z),.007,'leaf_sage')
            for k in range(4):
                ell('Spike floret',(x,.28+k*.045,z),(.032,.03,.032),'bloom_lilac',seg=(8,6))

def flower_03():   # tall trumpet lilies
    ground_clump(3,'leaf_mid',.46,.13,5)
    for i in range(5):
        a=math.tau*i/5
        blade('Strap leaf',(math.sin(a)*.05,.02,math.cos(a)*.05),(math.sin(a)*.18,.3,math.cos(a)*.18),.03,'leaf_mid')
    with tinted():
        for i in range(4):
            a=math.tau*i/4+.3
            x,z=math.sin(a)*.07,math.cos(a)*.07
            stem_to('Lily stem',(x,.44,z),.008)
            for k in range(6):
                p=math.tau*k/6
                ell('Trumpet petal',(x+math.sin(p)*.035,.43,z+math.cos(p)*.035),(.02,.055,.02),'bloom_orange' if i%2 else 'bloom_yellow',seg=(8,6),rot=(.5,p,0))

def flower_04():   # bluebell spray of nodding bells
    ground_clump(4,'leaf_mid',.44,.11,5)
    for i in range(6):
        a=math.tau*i/6
        blade('Linear leaf',(math.sin(a)*.05,0,math.cos(a)*.05),(math.sin(a)*.2,.28,math.cos(a)*.2),.03,'leaf_mid')
    with tinted():
        for i in range(4):
            a=math.tau*i/4+.4; x,z=math.sin(a)*.11,math.cos(a)*.11
            stem_to('Bell stem',(x,.4,z),.007)
            for k in range(4):
                ell('Nodding bell',(x+(k%2)*.04,.28+k*.045,z+(k%2)*.03),(.036,.05,.036),'bloom_blue',seg=(8,6),rot=(.3,0,0))

def flower_05():   # allium umbel
    foliage_rosette('leaf_olive')
    ground_clump(5,'leaf_mid',.5,.12,5)
    with tinted():
        for i in range(3):
            a=math.tau*i/3; x,z=math.sin(a)*.07,math.cos(a)*.07
            stem_to('Allium stem',(x,.36,z),.008)
            ell('Umbel head',(x,.37,z),(.075,.06,.075),'bloom_violet',seg=(12,8))

def flower_06():   # pom-pom marigold
    foliage_rosette('leaf_mid')
    ground_clump(6,'leaf_mid',.5,.14,5)
    with tinted():
        for i in range(5):
            a=math.tau*i/5; x,z=math.sin(a)*.12,math.cos(a)*.12
            stem_to('Marigold stem',(x,.28,z),.008)
            ell('Pom-pom head',(x,.29,z),(.05,.042,.05),'bloom_gold',seg=(12,8))
            ell('Pom-pom crown',(x,.32,z),(.034,.022,.034),'bloom_orange',seg=(10,6))

def flower_07():   # foxglove raceme
    for i in range(7):
        a=math.tau*i/7
        blade('Broad leaf',(math.sin(a)*.05,.02,math.cos(a)*.05),(math.sin(a)*.15,.16,math.cos(a)*.15),.05,'leaf_dark')
    ground_clump(7,'leaf_mid',.5,.16,5)
    with tinted():
        rod('Foxglove spire',(0,.02,0),(0,.42,0),.013,'leaf_mid')
        for k in range(7):
            a=k*.7
            ell('Raceme flower',(math.sin(a)*.06,.18+k*.038,math.cos(a)*.06),(.04,.036,.04),'bloom_pink' if k%2 else 'bloom_lilac',seg=(8,6))

def flower_08():   # cup poppies
    foliage_rosette('leaf_sage')
    ground_clump(8,'leaf_sage',.5,.13,5)
    with tinted():
        for i in range(4):
            a=math.tau*i/4+.2; x,z=math.sin(a)*.11,math.cos(a)*.11
            stem_to('Poppy stem',(x,.34,z),.008)
            for k in range(5):
                p=math.tau*k/5
                ell('Cupped petal',(x+math.sin(p)*.04,.33,z+math.cos(p)*.04),(.04,.034,.04),'bloom_red',seg=(8,6))
            ell('Poppy centre',(x,.35,z),(.017,.014,.017),'bloom_crimson',seg=(8,6))

def flower_09():   # star dahlia
    foliage_rosette()
    ground_clump(9,'leaf_mid',.5,.13,5)
    with tinted():
        for i in range(3):
            a=math.tau*i/3+.5; x,z=math.sin(a)*.09,math.cos(a)*.09
            stem_to('Dahlia stem',(x,.32,z),.008)
            for k in range(8):
                p=math.tau*k/8
                ell('Star petal',(x+math.sin(p)*.07,.33,z+math.cos(p)*.07),(.055,.015,.013),'bloom_purple',seg=(10,6),rot=(0,p,0))
            ell('Dahlia heart',(x,.34,z),(.022,.018,.022),'bloom_yellow',seg=(8,6))

def flower_10():   # dense cluster bedding
    foliage_rosette('leaf_sage')
    ground_clump(10,'leaf_sage',.5,.14,5)
    with tinted():
        for i in range(9):
            a=math.tau*i/9; d=.11+(i%2)*.06
            x,z=math.sin(a)*d,math.cos(a)*d
            ell('Cluster bloom',(x,.27+(i%3)*.06,z),(.07,.042,.07),'bloom_white' if i%2 else 'bloom_cream',seg=(10,8))

def flower_11():   # tall cottage delphinium
    for i in range(7):
        a=math.tau*i/7
        blade('Cut leaf',(math.sin(a)*.06,.02,math.cos(a)*.06),(math.sin(a)*.17,.2,math.cos(a)*.17),.045,'leaf_mid')
    ground_clump(11,'leaf_mid',.5,.16,5)
    with tinted():
        rod('Delphinium spire',(0,.02,0),(0,.44,0),.015,'leaf_mid')
        for k in range(8):
            a=k*1.1
            ell('Spur bloom',(math.sin(a)*.065,.15+k*.038,math.cos(a)*.065),(.038,.034,.038),['bloom_blue','bloom_violet','bloom_lilac'][k%3],seg=(8,6))

def flower_12():   # low cushion carpet, deliberately flatter than the bedding plantings
    for i in range(8):
        a=math.tau*i/8
        blade('Cushion leaf',(math.sin(a)*.05,0,math.cos(a)*.05),(math.sin(a)*.22,.08,math.cos(a)*.22),.055,'leaf_dark')
    ground_clump(12,'leaf_dark',.46,.1,5)
    with tinted():
        for i in range(11):
            a=math.tau*i/11; d=.08+(i%3)*.05
            x,z=math.sin(a)*d,math.cos(a)*d
            ray_bloom('Aster',(x,.24+(i%3)*.035,z),.07,8,'bloom_magenta','bloom_yellow',seed=i*.9)

def flower_13():   # sunflowers on tall stems
    for i in range(4):
        a=math.tau*i/4
        blade('Coarse leaf',(math.sin(a)*.05,.02,math.cos(a)*.05),(math.sin(a)*.16,.26,math.cos(a)*.16),.07,'leaf_dark')
    with tinted():
        for i in range(2):
            a=i*2.4+.6; x,z=math.sin(a)*.08,math.cos(a)*.08
            stem_to('Sunflower stem',(x,.38,z),.011)
            ray_bloom('Sunflower',(x,.4,z),.11,14,'bloom_yellow','bloom_gold',seed=i*1.3)

def flower_14():   # tulip bed
    for i in range(7):
        a=math.tau*i/7
        blade('Tulip leaf',(math.sin(a)*.05,0,math.cos(a)*.05),(math.sin(a)*.17,.3,math.cos(a)*.17),.03,'leaf_mid')
    ground_clump(14,'leaf_mid',.5,.12,5)
    with tinted():
        for i in range(6):
            a=math.tau*i/6+.2; d=.08+(i%2)*.07
            x,z=math.sin(a)*d,math.cos(a)*d
            stem_to('Tulip stem',(x,.32,z),.009)
            ell('Cup bloom',(x,.34,z),(.04,.055,.04),['bloom_red','bloom_pink','bloom_yellow','bloom_white','bloom_rose','bloom_crimson'][i],seg=(10,8))

def flower_15():   # mixed planting of several flower colours
    foliage_rosette('leaf_mid')
    ground_clump(15,'leaf_mid',.5,.14,5)
    with tinted():
        palette=['bloom_yellow','bloom_pink','bloom_white','bloom_purple','bloom_red','bloom_blue','bloom_orange','bloom_lilac']
        for i in range(8):
            a=math.tau*i/8+.3; d=.07+(i%3)*.06
            x,z=math.sin(a)*d,math.cos(a)*d
            stem_to('Mixed stem',(x,.26+(i%5)*.035,z),.008)
            ray_bloom('Mixed bloom',(x,.27+(i%5)*.035,z),.065,8,palette[i],'bloom_gold',seed=i*.7)

def flower_16():   # second mixed planting, taller heads
    for i in range(6):
        a=math.tau*i/6
        blade('Mixed leaf',(math.sin(a)*.05,.02,math.cos(a)*.05),(math.sin(a)*.17,.18,math.cos(a)*.17),.05,'leaf_dark')
    with tinted():
        palette=['bloom_orange','bloom_magenta','bloom_blue','bloom_cream','bloom_rose','bloom_violet']
        for i in range(7):
            a=math.tau*i/7+.4; d=.1+(i%2)*.06
            x,z=math.sin(a)*d,math.cos(a)*d
            stem_to('Mixed stem',(x,.34,z),.008)
            ell('Round bloom',(x,.35,z),(.055,.05,.055),palette[i%6],seg=(10,8))

def flower_17():   # globe-headed craspedia
    foliage_rosette('leaf_sage')
    with tinted():
        for i in range(7):
            a=math.tau*i/7; d=.08+(i%2)*.06
            x,z=math.sin(a)*d,math.cos(a)*d
            stem_to('Globe stem',(x,.34,z),.006,'leaf_sage')
            ell('Globe head',(x,.35,z),(.045,.045,.045),'bloom_gold',seg=(10,8))

def flower_18():   # airy cloud of tiny blooms
    for i in range(6):
        a=math.tau*i/6
        blade('Fine leaf',(math.sin(a)*.05,.02,math.cos(a)*.05),(math.sin(a)*.13,.16,math.cos(a)*.13),.02,'leaf_sage',thick=.008)
    ground_clump(18,'leaf_sage',.44,.1,5)
    with tinted():
        for i in range(13):
            a=i*2.399; d=.13*(i%4)/3+.04
            x,y,z=math.sin(a)*d,.22+(i%5)*.045,math.cos(a)*d
            rod('Cloud stem',(x*.4,.14,z*.4),(x,y,z),.005,'leaf_sage')
            ell('Tiny bloom',(x,y,z),(.022,.022,.022),'bloom_white' if i%3 else 'bloom_pink',seg=(8,6))

def flower_19():   # bearded iris
    for i in range(7):
        a=math.tau*i/7
        blade('Sword leaf',(math.sin(a)*.05,0,math.cos(a)*.05),(math.sin(a)*.13,.34,math.cos(a)*.13),.028,'leaf_mid')
    ground_clump(19,'leaf_mid',.5,.12,5)
    with tinted():
        for i in range(4):
            a=math.tau*i/4+.5; x,z=math.sin(a)*.1,math.cos(a)*.1
            stem_to('Iris stem',(x,.36,z),.008)
            for k in range(3):
                p=math.tau*k/3
                ell('Falls petal',(x+math.sin(p)*.045,.31,z+math.cos(p)*.045),(.035,.05,.035),'bloom_violet',seg=(8,6),rot=(.9,p,0))
            ell('Iris standard',(x,.38,z),(.045,.035,.045),'bloom_purple',seg=(10,8))

def flower_20():   # tall gladiolus spike
    for i in range(6):
        a=math.tau*i/6
        blade('Sword leaf',(math.sin(a)*.05,.02,math.cos(a)*.05),(math.sin(a)*.16,.34,math.cos(a)*.16),.03,'leaf_mid')
    ground_clump(20,'leaf_mid',.5,.14,5)
    with tinted():
        rod('Gladiolus spike',(0,.02,0),(0,.44,0),.013,'leaf_dark')
        for k in range(8):
            a=k*.95
            ell('Spike bloom',(math.sin(a)*.06,.16+k*.038,math.cos(a)*.06),(.04,.032,.04),
                ['bloom_rose','bloom_pink','bloom_red','bloom_peach'][k%4],seg=(8,6))

FLOWERS={f'{i:02d}':globals()[f'flower_{i:02d}'] for i in range(1,21)}

# ---------------------------------------------------------------- Catalogue and export
CATALOG={}
for _key,_fn in TREES.items(): CATALOG['tree_garden_'+_key]=_fn
for _key,_fn in SHRUBS.items(): CATALOG['shrub_'+_key]=_fn
for _key,_fn in FLOWERS.items(): CATALOG['flowers_'+_key]=_fn

parser=argparse.ArgumentParser()
parser.add_argument('--only',choices=tuple(CATALOG))
parser.add_argument('--output-root',type=pathlib.Path,default=ROOT)
args=parser.parse_args(sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else [])
ROOT=args.output_root.resolve(); ART=ROOT/'art/garden_plants'; MODELS=ROOT/'assets/models'
selected={args.only:CATALOG[args.only]} if args.only else dict(CATALOG)
targets=[MODELS/(name+'.glb') for name in selected]+[ART/'garden_plants.blend',ART/'garden_plants_report.json']
clashes=[str(p) for p in targets if p.exists()]
if clashes: raise RuntimeError('Refusing to replace an existing garden plant output: '+', '.join(clashes))
MODELS.mkdir(parents=True,exist_ok=True); ART.mkdir(parents=True,exist_ok=True)

report={'blender':bpy.app.version_string,
        'provenance':'Original primitives, authored point tubes and ring-built foliage masses in create_garden_plants.py; no external mesh, texture or bitmap input',
        'units':'metres; authored in Blender +Z up, exported +Y up; each model root is an Empty at the origin with identity transforms',
        'contract':'exactly one mesh named Tint per model (tree bark / shrub foliage / flower blooms); no cameras, lights, animations or textures',
        'kinds':{'tree_garden':len(TREES),'shrub':len(SHRUBS),'flowers':len(FLOWERS)}, 'items':{}}
previous=None
for index,(name,fn) in enumerate(selected.items()):
    # Park the previous item's recolourable surface so this item can claim the name Tint.
    for o in bpy.data.objects:
        if o.name.startswith('Tint'):
            # Names derive from the item name, so a repeated clean build is byte-stable.
            o.name=o.data.name=(previous or 'unused')+'_recolourable_surface'
    del ACTIVE[:]; del TINT[:]
    kind='tree_garden' if name.startswith('tree') else ('shrub' if name.startswith('shrub') else 'flowers')
    SPREAD[:]={'tree_garden':(1.0,1.0,1.0),'shrub':(1.05,1.0,1.05),'flowers':(1.04,1.0,1.04)}[kind]
    before=set(bpy.data.objects.keys())
    fn()
    fit_scale({'tree_garden':(1.8,2.4,1.8),'shrub':(0.8,0.7,0.8),'flowers':(0.5,0.45,0.5)}[kind])
    seat_on_ground()
    tint=merge_tint()
    if tint is None: raise RuntimeError(name+' did not author a recolourable Tint surface')
    parts=[bpy.data.objects[k] for k in bpy.data.objects.keys() if k not in before]
    root=bpy.data.objects.new(name,None); bpy.context.scene.collection.objects.link(root)
    for o in parts:
        if o.parent is None: o.parent=root
    bpy.ops.object.select_all(action='DESELECT')
    root.select_set(True)
    for o in parts: o.select_set(True)
    bpy.context.view_layer.objects.active=root
    path=MODELS/(name+'.glb')
    bpy.ops.export_scene.gltf(filepath=str(path),export_format='GLB',use_selection=True,export_apply=True,
                              export_animations=False,export_cameras=False,export_lights=False)
    bpy.context.view_layer.update()
    coords=[o.matrix_world@Vector(v.co) for o in parts for v in o.data.vertices]
    size=[max(c[i] for c in coords)-min(c[i] for c in coords) for i in range(3)]
    triangles=0
    dag=bpy.context.evaluated_depsgraph_get()
    for o in parts:
        # Modifiers (bevels) are applied by the exporter, so count the evaluated mesh.
        evaluated=o.evaluated_get(dag); baked=evaluated.to_mesh()
        baked.calc_loop_triangles(); triangles+=len(baked.loop_triangles); evaluated.to_mesh_clear()
    report['items'][name]={'file':str(path.relative_to(ROOT)),'bytes':path.stat().st_size,'parts':len(parts),
        'triangles':triangles,
        'footprint_m':{'width':round(size[0],3),'depth':round(size[2],3),'height':round(size[1],3)},
        'tint':{'mesh':tint.data.name,'materials':[m.name for m in tint.data.materials],'vertices':len(tint.data.vertices)}}
    root.location=((index%7)*3.2,(index//7)*3.2,0); previous=name; SPREAD[:]=(1.0,1.0,1.0)
    print('built '+name+' '+str(path.stat().st_size)+' bytes '+str(triangles)+' tris')

bpy.ops.wm.save_as_mainfile(filepath=str(ART/'garden_plants.blend'))
report['native_blend']=str((ART/'garden_plants.blend').relative_to(ROOT))
(ART/'garden_plants_report.json').write_text(json.dumps(report,indent=2)+'\n')
print('JUSTLIFE_GARDEN_PLANTS_COMPLETE',len(selected))
