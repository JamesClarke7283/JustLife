"""Original JustLife garden-living, kids-play, riding and ready-made garden models.

Run: blender -b --factory-startup -t 2 --python-exit-code 2 --python tools/create_outdoor_garden.py

Coordinates are Godot metres: x right, y up, z toward the front of the prop.
Every model of a colour-variant kind carries exactly one mesh named `Tint`, the
surface a player's colour choice repaints at runtime. Geometry is authored only
from primitives; no downloaded mesh, image or reference bitmap is involved.
"""
import bpy, math, random, pathlib, argparse, sys
from mathutils import Vector, Matrix
ROOT = pathlib.Path(__file__).resolve().parents[1]
random.seed(53)
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.context.scene.unit_settings.system = 'METRIC'
bpy.context.scene.unit_settings.scale_length = 1.0
M = {}
def mat(name, hexcolor, rough=.65, metal=0, emit=0.0):
    rgb=[int(hexcolor[i:i+2],16)/255 for i in (0,2,4)]
    linear=[v/12.92 if v<=.04045 else ((v+.055)/1.055)**2.4 for v in rgb]
    m=bpy.data.materials.new(name); m.diffuse_color=(*linear,1)
    m.use_nodes=True; p=m.node_tree.nodes.get('Principled BSDF'); p.inputs['Base Color'].default_value=m.diffuse_color
    p.inputs['Roughness'].default_value=rough; p.inputs['Metallic'].default_value=metal
    if emit:
        p.inputs['Emission Color'].default_value=m.diffuse_color; p.inputs['Emission Strength'].default_value=emit
    M[name]=m; return m
for n,h in [('oak','AB7951'),('oak_light','D7AE7E'),('walnut','624435'),('cream','EFE9DA'),('white','FAF6EA'),
            ('teal','417A71'),('teal_light','86ADA0'),('coral','C97C66'),('gold','C8A562'),('dark','263E3C'),
            ('black','1D292B'),('green','48794B'),('leaf_light','749752'),('soil','42352D'),('blue','7CA4AA'),
            ('screen','406C72'),('linen','DECFAF'),('rust','9A5A44'),('brick','8C5A4A'),('mustard','D2A24B'),
            ('plum','6E5470'),('sky','9EC1CF'),('rose','D9A0A0'),('graphite','4A4F55'),('ivory','F6F1E4'),
            ('pine','3E6B4F'),('lime','A8C36B'),('blossom','EFA9C1'),('stone','A8A395'),('granite','6E6F6A'),
            ('sand','E3D3AE'),('slate','5C6B73'),('bark','6A5344'),('moss','6C8A57')]: mat(n,h)
mat('flame','F2A93B',.9,0,6.0); mat('ember','E0602A',.9,0,2.5)
mat('steel','B9BEC2',.35,.45); mat('brass','C8A562',.4,.35); mat('glass','F2F7FA',.3,0,1.0); mat('glow','FFF3D0',.4,0,5.0)
active=[]
def xyz(p): return (p[0],-p[2],p[1])
def finish(o,n,m):
    o.name=n; o.data.materials.append(M[m]); active.append(o); return o
def box(n,p,s,m,bevel=.03):
    bpy.ops.mesh.primitive_cube_add(size=1,location=xyz(p)); o=bpy.context.object; o.dimensions=(s[0],s[2],s[1])
    bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
    if bevel:
        mod=o.modifiers.new('Soft crafted edges','BEVEL'); mod.width=bevel; mod.segments=3
        mod=o.modifiers.new('Weighted corner normals','WEIGHTED_NORMAL')
    return finish(o,n,m)
def ell(n,p,s,m,seg=20,ring=12):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=seg,ring_count=ring,location=xyz(p)); o=bpy.context.object
    o.scale=(s[0],s[2],s[1]); bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
    for f in o.data.polygons:f.use_smooth=True
    return finish(o,n,m)
def cyl(n,p,r,h,m,top=None,axis='Y',seg=32):
    bpy.ops.mesh.primitive_cone_add(vertices=seg,radius1=r,radius2=r if top is None else top,depth=h,location=xyz(p)); o=bpy.context.object
    if axis=='X':o.rotation_euler=(0,math.pi/2,0)
    elif axis=='Z':o.rotation_euler=(math.pi/2,0,0)
    bevel=o.modifiers.new('Rounded rims','BEVEL'); bevel.width=.012; bevel.segments=3
    for f in o.data.polygons:f.use_smooth=True
    return finish(o,n,m)
def rod(n,a,b,r,m):
    av,bv=Vector(xyz(a)),Vector(xyz(b)); d=bv-av
    bpy.ops.mesh.primitive_cylinder_add(vertices=12,radius=r,depth=d.length,location=(av+bv)/2); o=bpy.context.object
    o.rotation_euler=d.to_track_quat('Z','Y').to_euler(); return finish(o,n,m)
def torus(n,p,major,minor,m,axis='Y'):
    bpy.ops.mesh.primitive_torus_add(major_segments=36,minor_segments=10,major_radius=major,minor_radius=minor,location=xyz(p)); o=bpy.context.object
    if axis=='Z':o.rotation_euler=(math.pi/2,0,0)
    elif axis=='X':o.rotation_euler=(0,math.pi/2,0)
    for f in o.data.polygons:f.use_smooth=True
    return finish(o,n,m)
def rock(n,p,s,m='granite',sub=1,seed=0):
    """s = Godot half extents (x, z, y); p is where the boulder's centre sits."""
    rng=random.Random(seed)
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=sub,radius=1,location=xyz(p)); o=bpy.context.object
    o.scale=(s[0],s[1],s[2]); o.rotation_euler=(rng.uniform(-.35,.35),rng.uniform(0,3.14),rng.uniform(-.35,.35))
    bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
    for f in o.data.polygons:f.use_smooth=False
    return finish(o,n,m)
def foliage(x,y,z,scale=1,leaves=7,color='green'):
    for i in range(leaves):
        a=i*2.399; height=(.42+(i%3)*.12)*scale
        end=(x+math.sin(a)*.22*scale,y+height,z+math.cos(a)*.22*scale)
        rod('Leaf stem',(x,y,z),end,.010*scale,'green')
        leaf=ell('Satin leaf',end,(.10*scale,.17*scale,.04*scale),color if i%2 else 'leaf_light',12,8)
        leaf.rotation_euler=(.5*math.sin(a),.45,a)
def turn(objs,cx,cz,yaw):
    """Yaw a cluster about the vertical axis through its own centre."""
    T=Matrix.Translation((cx,-cz,0)); R=Matrix.Rotation(yaw,4,'Z')
    for o in objs:o.matrix_basis=T @ R @ T.inverted() @ o.matrix_basis
def merge(name,objs,m):
    """Join primitives into one surface, for Tints that are composite parts."""
    keep=[active.index(o) for o in objs]
    for o in objs:
        bpy.ops.object.select_all(action='DESELECT'); o.select_set(True); bpy.context.view_layer.objects.active=o
        for mod in list(o.modifiers):bpy.ops.object.modifier_apply(modifier=mod.name)
    bpy.ops.object.select_all(action='DESELECT')
    for o in objs:o.select_set(True)
    bpy.context.view_layer.objects.active=objs[0]
    bpy.ops.object.join()
    o=objs[0]; o.name=name
    o.data.materials.clear(); o.data.materials.append(M[m])
    for p in o.data.polygons:p.material_index=0
    for i in sorted(keep[1:],reverse=True):del active[i]
    return o
def tint(o):o.name='Tint'; return o
def tilt(o,x=0.0,y=0.0,z=0.0):o.rotation_euler=(x,y,z); return o

# ================================================================ Cooking
def _bbq_round():
    for x in (-.31,.31):
        for z in (-.30,.30):rod('Trolley leg',(x,0,z),(x*.88,.66,z*.92),.022,'graphite')
    box('Trolley shelf',(0,.16,0),(.70,.03,.60),'graphite',.01)
    for s in (-1,1):rod('Handle post',(s*.24,.62,-.26),(s*.24,.68,-.26),.014,'steel')
    rod('Trolley handle',(-.24,.68,-.26),(.24,.68,-.26),.016,'steel')
    box('Ash pan',(0,.60,0),(.46,.04,.42),'black',.01)
    ell('Kettle bowl',(0,.76,0),(.26,.17,.31),'graphite')
    cyl('Grill grate',(0,.89,0),.23,.02,'steel')
    ell('Kettle lid',(0,1.00,0),(.25,.12,.31),'dark')
    torus('Lid joint',(0,.82,0),.21,.014,'steel')
    for x in (-.11,.11):rod('Lid handle post',(x,1.07,0),(x,1.11,0),.012,'black')
    rod('Lid handle',(-.11,1.11,0),(.11,1.11,0),.014,'black')
    for x in (-.18,0,.18):box('Bowl vent',(x,.74,.27),(.05,.10,.02),'black',0)
    for s in (-1,1):
        box('Side shelf',(s*.37,.72,0),(.16,.03,.62),'oak',.01)
        box('Shelf lip',(s*.44,.75,0),(.03,.02,.62),'oak_light',.006)
        for z in (-.26,.26):rod('Shelf brace',(s*.26,.62,z),(s*.36,.70,z*.9),.014,'graphite')
    tint(box('Trolley front panel',(0,.44,.31),(.58,.30,.05),'coral',.02))
    for x in (-.13,.13):cyl('Control knob',(x,.46,.27),.022,.02,'gold',axis='Z')
    rod('Tool hook',(-.22,.70,.34),(-.22,.58,.34),.010,'steel')
    rod('Tool hook',(.22,.70,.34),(.22,.58,.34),.010,'steel')
    for s in (-1,1):torus('Trolley wheel',(s*.31,.105,-.32),.075,.028,'black',axis='Z')

def _bbq_barrel():
    cyl('Barrel body',(0,.60,0),.30,.78,'graphite',axis='X')
    for s in (-1,1):
        for t in (-1,1):rod('Barrel leg',(s*.24,.38,t*.22),(s*.34,.02,t*.26),.026,'graphite')
    box('Ash pan',(0,.38,0),(.52,.05,.36),'black',.01)
    box('Grill grate',(0,.90,0),(.62,.03,.44),'steel',.006)
    ell('Barrel hood',(0,.96,-.22),(.29,.09,.13),'dark')
    for s in (-1,1):
        rod('Hood hinge',(s*.30,.90,-.32),(s*.30,.99,-.16),.014,'black')
        torus('Drum handle',(s*.40,.64,0),.065,.014,'steel',axis='Z')
    box('Drum door',(0,.54,.27),(.36,.24,.04),'graphite',.01)
    for x in (-.12,0,.12):box('Drum vent',(x,.32,.27),(.05,.05,.02),'black',0)
    box('Front shelf',(0,.64,.31),(.60,.03,.14),'oak',.01)
    for s in (-1,1):rod('Shelf brace',(s*.23,.60,.24),(s*.23,.63,.30),.014,'steel')
    tint(torus('Barrel band',(0,.60,0),.30,.05,'coral',axis='X'))
    for s in (-1,1):torus('Barrel hoop',(s*.30,.60,0),.31,.018,'steel',axis='X')

def _bbq_brick():
    box('Brick plinth',(0,.34,0),(.84,.60,.60),'brick',.01)
    box('Work ledge',(0,.64,.03),(.88,.06,.64),'stone',.01)
    box('Brick apron',(0,.74,0),(.84,.08,.60),'brick',.01)
    box('Firebox opening',(0,.26,.29),(.48,.44,.04),'black',0)
    for i in range(3):ell('Ember',(-.13+i*.13,.18,.30),(.05,.03,.05),'ember',12,8)
    box('Grill grate',(0,.44,.27),(.44,.02,.14),'steel',.006)
    box('Chimney stack',(0,.90,-.23),(.44,.32,.32),'brick',.01)
    box('Chimney cap',(0,1.11,-.23),(.50,.06,.32),'stone',.01)
    box('Chimney flashing',(0,.74,-.23),(.50,.14,.32),'stone',.01)
    tint(box('Chimney painted band',(0,1.02,-.23),(.48,.10,.32),'coral',.01))
    rod('Skewer rail',(-.18,.80,.30),(.18,.80,.30),.010,'steel')
    for x in (-.18,.18):rod('Skewer',(x,.80,.30),(x,.74,.32),.008,'steel')
    for s in (-1,1):rod('Poker hook',(s*.34,.68,.30),(s*.34,.68,.22),.010,'steel')

def _garden_chair(cx,cz,yaw):
    n0=len(active)
    box('Chair seat',(cx,.44,cz),(.44,.05,.42),'teal',.03)
    box('Chair back',(cx,.74,cz-.19),(.44,.42,.05),'teal',.03)
    rod('Chair back top',(cx-.22,.95,cz-.19),(cx+.22,.95,cz-.19),.020,'walnut')
    for dx in (-.18,.18):
        for dz in (-.16,.16):rod('Chair leg',(cx+dx,0,cz+dz),(cx+dx*.9,.42,cz+dz*.9),.020,'walnut')
        rod('Chair arm',(cx+dx,.58,cz),(cx+dx,.58,cz-.20),.016,'walnut')
        rod('Arm post',(cx+dx,.42,cz-.20),(cx+dx,.58,cz-.20),.014,'walnut')
    turn(active[n0:],cx,cz,yaw)

def _garden_table():
    cyl('Table top',(0,.74,0),.58,.05,'oak')
    torus('Table rim',(0,.72,0),.57,.018,'oak_light')
    for i in range(4):
        a=i*math.pi/2+math.pi/4
        rod('Table leg',(math.sin(a)*.42,0,math.cos(a)*.42),(math.sin(a)*.30,.72,math.cos(a)*.30),.034,'walnut')
    torus('Leg stretcher',(0,.26,0),.34,.014,'walnut')
    cyl('Parasol base',(0,.05,0),(.26),.10,'graphite')
    ell('Base weight',(0,.14,0),(.20,.05,.20),'granite')
    rod('Parasol pole',(0,.10,0),(0,2.18,0),.028,'oak')
    cyl('Canopy hub',(0,2.16,0),.06,.10,'oak_light')
    wings=[]
    for i in range(6):
        a=i*math.pi/3
        w=box('Canopy wing',(math.sin(a)*.40,1.96,math.cos(a)*.40),(.54,.04,.84),'coral',.01)
        tilt(w,-.16,0,a); wings.append(w)
        ell('Canopy scallop',(math.sin(a)*.78,1.90,math.cos(a)*.78),(.12,.04,.12),'coral',12,8)
    tint(merge('Tint',wings,'coral'))
    torus('Canopy rib ring',(0,2.06,0),.30,.014,'oak_light')
    rod('Parasol finial',(0,2.18,0),(0,2.28,0),.022,'gold')
    for i in range(4):
        a=i*math.pi/2
        _garden_chair(math.sin(a)*.78,math.cos(a)*.78,a+math.pi)

# ================================================================ Outdoor living
def _screen_head():
    tint(box('Housing bezel',(0,.99,-.01),(1.40,.54,.10),'coral',.02))
    box('Screen panel',(0,.99,.045),(1.22,.44,.03),'screen',.006)
    box('Weather seal',(0,.99,.036),(1.30,.50,.02),'black',.004)
    hood=box('Weather hood',(0,1.37,-.03),(1.42,.06,.26),'dark',.02); tilt(hood,-.12)
    box('Housing shell',(0,.99,-.08),(1.36,.50,.09),'dark',.02)
    for s in (-1,1):rod('Screen brace',(s*.66,.99,-.13),(s*.66,.99,-.04),.012,'graphite')

def _outdoor_tv_classic():
    _screen_head()
    cyl('Pedestal post',(0,.55,-.03),.07,1.10,'graphite')
    cyl('Pedestal base',(0,.03,-.03),.30,.06,'dark')
    torus('Pedestal trim',(0,.07,-.03),.27,.018,'steel')
    box('Cable box',(0,.20,-.10),(.16,.12,.12),'graphite',.02)

def _outdoor_tv_console():
    _screen_head()
    box('Console cabinet',(0,.26,-.02),(1.14,.46,.52),'graphite',.02)
    box('Console doors',(0,.26,.24),(.98,.30,.02),'slate',.01)
    for x in (-.30,.30):cyl('Console knob',(x,.28,.255),.018,.02,'gold',axis='Z')
    box('Console shelf',(0,.56,-.02),(1.04,.03,.40),'oak',.01)
    for s in (-1,1):rod('Shelf bracket',(s*.46,.53,.14),(s*.48,.56,.16),.014,'steel')
    for s in (-1,1):
        for t in (-1,1):box('Cabinet foot',(s*.48,.02,t*.18),(.08,.05,.08),'black',.01)

def _outdoor_tv_stand():
    _screen_head()
    for s in (-1,1):
        for t in (-1,1):rod('Stand leg',(s*.62,0,t*.26),(s*.14,1.10,-.06),.026,'graphite')
        rod('Stand brace',(s*.52,.34,-.15),(s*.36,.68,-.08),.018,'graphite')
    rod('Stand spreader',(-.58,.38,-.15),(.58,.38,-.15),.020,'graphite')
    rod('Stand mid rail',(-.40,.72,-.09),(.40,.72,-.09),.018,'graphite')
    box('Stand collar',(0,.82,-.05),(.34,.16,.18),'graphite',.02)
    box('Stand ballast',(0,.05,-.02),(.82,.08,.32),'granite',.02)

def _swing_seat(y=.46,width=1.56,cushion='coral',back=True):
    box('Seat base',(0,y-.10,0),(width,.05,.52),'walnut',.02)
    seat=box('Seat cushion',(0,y,0),(width,.14,.52),cushion,.05)
    if back:
        b=box('Back cushion',(0,y+.26,-.25),(width,.36,.10),'linen',.05); tilt(b,.20)
        box('Back board',(0,y+.26,-.31),(width,.40,.04),'walnut',.02)
    for s in (-1,1):rod('Armrest',(s*width/2,y+.16,-.24),(s*width/2,y+.16,.24),.022,'walnut')
    return tint(seat)

def _outdoor_swing_a():
    for s in (-1,1):
        rod('Frame upright',(s*1.06,0,.68),(s*.98,1.66,.44),.032,'steel')
        rod('Frame upright',(s*1.06,0,-.68),(s*.98,1.66,-.44),.032,'steel')
        rod('Frame brace',(s*1.03,.40,.62),(s*1.00,1.34,-.40),.022,'steel')
    for z in (-.44,.44):rod('Top rail',(-.98,1.66,z),(.98,1.66,z),.030,'steel')
    ell('Curved canopy',(0,1.88,0),(1.04,.24,.44),'teal')
    ell('Canopy cap',(0,2.01,0),(.62,.10,.14),'teal_light')
    _swing_seat()
    for s in (-1,1):
        for z in (-.22,.22):rod('Glider arm',(s*.78,.50,z),(s*.80,1.02,z-.10),.020,'steel')
    rod('Glider pivot',(-.80,1.03,-.10),(.80,1.03,-.10),.020,'steel')

def _outdoor_swing_b():
    for s in (-1,1):
        for z in (-.64,.64):box('Pergola post',(s*1.02,.97,z),(.10,1.94,.10),'walnut',.01)
    for z in (-.64,.64):rod('Pergola beam',(-1.02,1.98,z),(1.02,1.98,z),.05,'walnut')
    for x in (-.66,-.22,.22,.66):box('Pergola slat',(x,2.04,0),(.11,.04,1.30),'walnut',.01)
    rod('Pergola tie',(-1.02,2.02,0),(1.02,2.02,0),.024,'walnut')
    for s in (-1,1):
        for z in (-.24,.24):rod('Swing chain',(s*.72,1.96,z),(s*.74,.60,z),.012,'steel')
    _swing_seat()
    box('Swing headboard',(0,.72,-.30),(1.54,.30,.06),'teal',.03)
    for s in (-1,1):box('Swing armrest',(s*.85,.52,0),(.05,.05,.54),'walnut',.02)

def _outdoor_swing_c():
    for s in (-1,1):
        rod('Frame upright',(s*1.08,0,.64),(s*1.00,1.94,.28),.030,'steel')
        rod('Frame upright',(s*1.08,0,-.64),(s*1.00,1.94,-.28),.030,'steel')
    rod('Top beam',(-1.00,1.96,0),(1.00,1.96,0),.040,'steel')
    ell('Frame canopy',(0,2.02,0),(1.00,.12,.36),'teal')
    for i in range(7):torus('Chain link',(0,1.86-i*.14,0),.042,.012,'steel',axis='Z' if i%2 else 'Y')
    cyl('Basket body',(0,.52,0),.44,.30,'mustard')
    torus('Basket rim',(0,.68,0),.44,.028,'steel')
    cyl('Basket floor',(0,.36,0),.42,.05,'graphite')
    for i in range(4):
        a=math.pi/4+i*math.pi/2
        rod('Basket sling',(math.sin(a)*.40,.80,math.cos(a)*.40),(math.sin(a)*.44,.66,math.cos(a)*.44),.012,'steel')
    tint(ell('Basket back cushion',(0,.62,-.22),(.34,.16,.12),'coral'))
    for s in (-1,1):rod('Basket strap',(s*.40,.70,-.10),(s*.34,.60,-.20),.014,'steel')

# ================================================================ Kids play
def _legs_a(cx,halfw,halfd,top,m='oak'):
    for s in (-1,1):
        rod('A-frame leg',(cx+s*halfw,0,halfd),(cx+s*halfw*.78,top,halfd*.38),.030,m)
        rod('A-frame leg',(cx+s*halfw,0,-halfd),(cx+s*halfw*.78,top,-halfd*.38),.030,m)
        rod('A-frame spreader',(cx+s*halfw,.60,halfd*.90),(cx+s*halfw,.60,-halfd*.90),.020,m)

def _swing_hang(cx,cz,yaw,bar_y,seat_y,width,colour,seats):
    n0=len(active)
    for dx in (-width/2+.03,width/2-.03):rod('Swing rope',(cx+dx,bar_y,cz),(cx+dx,seat_y+.02,cz),.011,'linen')
    seats.append(box('Swing seat',(cx,seat_y,cz),(width,.05,.26),colour,.03))
    rod('Swing top bar',(cx-width/2,bar_y-.02,cz),(cx+width/2,bar_y-.02,cz),.020,'steel')
    if yaw:turn(active[n0:],cx,cz,yaw)

def _baby_seat(cx,cz,yaw,bar_y,seat_y,colour,seats):
    n0=len(active)
    for dx in (-.16,.16):rod('Baby swing rope',(cx+dx,bar_y,cz),(cx+dx,seat_y+.04,cz),.011,'linen')
    seats.append(box('Baby swing seat',(cx,seat_y,cz),(.36,.05,.30),colour,.04))
    for s in (-1,1):seats.append(box('Baby swing side',(cx+s*.17,seat_y+.14,cz),(.05,.28,.34),colour,.03))
    box('Baby swing front',(cx,seat_y+.14,cz+.16),(.34,.24,.05),colour,.03)
    rod('Baby swing bar',(cx-.18,bar_y-.02,cz),(cx+.18,bar_y-.02,cz),.020,'steel')
    if yaw:turn(active[n0:],cx,cz,yaw)

def _kid_slide(cx,cz,yaw,top,width,length,out=.30,drop=None):
    """Chute descending toward +z from its top edge at (cx, cz, top)."""
    n0=len(active)
    drop=top-.16 if drop is None else drop
    chute=box('Slide chute',(cx,top-drop/2,cz+length/2),(width,.05,length),'coral',.02)
    tilt(chute,math.atan2(drop,length))
    run=box('Slide run-out',(cx,.13,cz+length+out/2),(width,.05,out),'coral',.02); tilt(run,.12)
    for s in (-1,1):rod('Slide rail',(cx+s*width/2,top,cz),(cx+s*width/2,.22,cz+length),.018,'sky')
    objs=active[n0:]
    if yaw:turn(objs,cx,cz,yaw)
    return [o for o in objs if o.name in ('Slide chute','Slide run-out')]

def _kid_ladder(cx,cz,yaw,top,halfw=.36,lean=.22):
    """A leaning ladder whose head lands at (cx, cz+lean)."""
    n0=len(active)
    for s in (-1,1):rod('Ladder rail',(cx+s*halfw,0,cz),(cx+s*halfw*.92,top,cz+lean),.022,'oak')
    rungs=max(2,int(top/.26))
    for i in range(rungs):
        y=.22+i*(top-.30)/max(1,rungs-1)
        rod('Ladder rung',(cx-halfw,y,cz+lean*y/top),(cx+halfw,y,cz+lean*y/top),.016,'oak')
    if yaw:turn(active[n0:],cx,cz,yaw)

def _tower(cx,cz,size,deck,railing=1.50):
    for sx in (-1,1):
        for sz in (-1,1):box('Tower post',(cx+sx*size/2,deck/2,cz+sz*size/2),(.09,deck,.09),'oak',.01)
    box('Tower platform',(cx,deck,cz),(size+.10,.06,size+.10),'oak_light',.02)
    for s in (-1,1):
        rod('Platform rail',(cx+s*(size/2+.04),railing,cz-(size/2+.04)),(cx+s*(size/2+.04),railing,cz+(size/2+.04)),.018,'oak')
        for t in (-1,1):rod('Rail post',(cx+s*(size/2+.04),deck,cz+t*(size/2+.04)),(cx+s*(size/2+.04),railing+.04,cz+t*(size/2+.04)),.016,'oak')
        rod('Platform rail',(cx-(size/2+.04),railing,cz+s*(size/2+.04)),(cx+(size/2+.04),railing,cz+s*(size/2+.04)),.018,'oak')

def _pitched_roof(cx,cz,span,depth,base,rise=.24,slope=.44):
    """Two sloping panels over a tower. Returns (panels, paint panel, apex y)."""
    panels=[]
    for s in (-1,1):
        p=box('Roof panel',(cx+s*span/4,base+rise,cz),(span/2+.14,.05,depth+.18),'teal',.02)
        tilt(p,0,s*slope,0); panels.append(p)
    box('Roof ridge',(cx,base+rise+.16,cz),(.10,.10,depth+.18),'oak',.01)
    for sz in (-1,1):rod('Roof beam',(cx-span/2-.10,base+.02,cz+sz*(depth/2+.09)),(cx+span/2+.10,base+.02,cz+sz*(depth/2+.09)),.020,'oak')
    paint=box('Roof paint panel',(cx,base+rise-.06,cz),(span+.18,.05,.14),'teal_light',.01)
    return panels, paint, base+rise+.20

def _climb_wall(cx,cz,yaw):
    n0=len(active)
    for s in (-1,1):rod('Wall stringer',(cx+s*.36,0,cz),(cx+s*.34,1.00,cz+.20),.020,'oak')
    for i in range(5):
        rod('Wall rung',(cx-.36,.22+i*.20,cz+i*.045),(cx+.36,.22+i*.20,cz+i*.045),.014,'oak')
        box('Climbing hold',(cx-.24+(i%3)*.24,.32+i*.20,cz+i*.045+.09),(.09,.05,.06),'coral',.01)
    if yaw:turn(active[n0:],cx,cz,yaw)

def _net(cx,cz,yaw,w,h,rows=4,cols=5):
    n0=len(active)
    for i in range(cols+1):rod('Net post',(cx-w/2+i*w/cols,0,cz),(cx-w/2+i*w/cols,h,cz),.012,'linen')
    for j in range(rows+1):rod('Net weave',(cx-w/2,j*h/rows,cz),(cx+w/2,j*h/rows,cz),.010,'linen')
    if yaw:turn(active[n0:],cx,cz,yaw)

def _kids_swing_a():
    _legs_a(0,1.22,.58,1.92)
    rod('Top beam',(-1.02,1.94,0),(1.02,1.94,0),.040,'oak')
    seats=[]
    for x in (-.74,.02):_swing_hang(x,0,0,1.92,.46,.42,'coral',seats)
    merge('Tint',seats,'coral')
    slide=_kid_slide(.68,.26,0,.96,.56,.62,.22)
    for dx in (-.18,.18):rod('Slide hanger',(.68+dx,1.92,.28),(.68+dx,.98,.30),.014,'steel')
    rod('Slide brace',(.68,.98,.30),(.68,1.24,-.36),.016,'steel')
    merge('Slide chute',slide,'coral')

def _kids_swing_b():
    arc=[(-1.28+i*.32,1.94*(1-((-1.28+i*.32)/1.28)**2)) for i in range(9)]
    for z in (-.74,.74):
        for i in range(8):rod('Curved frame',(arc[i][0],arc[i][1],z),(arc[i+1][0],arc[i+1][1],z),.030,'steel')
        for i in (2,4,6):rod('Frame pin',(arc[i][0],arc[i][1],-.74),(arc[i][0],arc[i][1],.74),.020,'steel')
    for s in (-1,1):rod('Frame footing',(s*1.28,.03,-.74),(s*1.28,.03,.74),.026,'steel')
    seats=[];_swing_hang(-.20,0,0,1.90,.48,.46,'coral',seats);merge('Tint',seats,'coral')
    _net(1.00,0,0,.56,1.20)
    rod('Net top bar',(.66,1.22,0),(1.26,1.22,0),.020,'steel')
    rod('Net stay',(.70,1.22,0),(.70,.03,0),.016,'steel')

def _kids_swing_c():
    _legs_a(0,1.26,.74,1.92)
    rod('Top beam',(-1.02,1.94,0),(1.02,1.94,0),.040,'oak')
    seats=[]
    for x in (-.78,-.32):_baby_seat(x,0,0,1.90,.58,'coral',seats)
    for dx in (-.18,.18):rod('Glider rope',(.62+dx,1.90,0),(.62+dx,.58,0),.011,'linen')
    seats.append(box('Glider seat',(.62,.52,0),(.54,.06,.34),'coral',.04))
    for s in (-1,1):seats.append(box('Glider side',(.62+s*.29,.64,0),(.05,.24,.36),'coral',.03))
    for x in (-.78,-.32,.62):rod('Swing top bar',(x-.20,1.88,0),(x+.20,1.88,0),.020,'steel')
    merge('Tint',seats,'coral')

def _sand_pit():
    planks=[]
    for s in (-1,1):
        planks.append(box('Timber edging',(0,.07,s*.85),(1.80,.14,.10),'oak',.01))
        planks.append(box('Timber edging',(s*.85,.07,0),(.10,.14,1.60),'oak',.01))
        for t in (-1,1):planks.append(box('Edging peg',(s*.78,.13,t*.78),(.07,.04,.07),'walnut',.01))
    merge('Tint',planks,'oak')
    box('Sand surface',(0,.06,0),(1.60,.10,1.60),'sand',0)
    seat=box('Corner seat',(-.52,.275,-.52),(.96,.06,.30),'oak_light',.02); tilt(seat,0,0,math.pi/4)
    for s in (-1,1):rod('Seat leg',(-.52+s*.38,0,-.52+s*.38),(-.52+s*.34,.27,-.52+s*.34),.018,'walnut')
    for s in (-1,1):
        for t2 in (-.62,.62):box('Cover frame post',(s*.72,.14,t2),(.05,.28,.05),'oak_light',.006)
        box('Cover frame post',(s*.72,.14,0),(.05,.28,.05),'oak_light',.006)
    for i in range(3):rod('Cover rail',(-.78,.26,.34+i*.24),(.78,.26,.34+i*.24),.022,'oak_light')
    for s in (-1,1):rod('Cover rail',(s*.78,.26,-.72),(s*.78,.26,.70),.022,'oak_light')
    cyl('Bucket',(.36,.16,.34),.11,.18,'coral',top=.14)
    torus('Bucket handle',(.36,.13,.34),.085,.010,'steel',axis='Z')
    rod('Spade shaft',(-.26,.16,.34),(-.02,.26,.48),.014,'gold')
    box('Spade blade',(-.34,.13,.28),(.16,.02,.20),'steel',.01)

def _kids_slide():
    for s in (-1,1):
        rod('Ladder rail',(s*.40,0,-.84),(s*.34,1.00,-.56),.024,'sky')
        rod('Slide handrail',(s*.36,1.02,-.48),(s*.36,1.20,-.48),.018,'sky')
        rod('Slide handrail',(s*.40,0,-.84),(s*.40,.60,-.84),.020,'sky')
    for i in range(4):rod('Ladder rung',(-.34,.24+i*.26,-.80+i*.06),(.34,.24+i*.26,-.80+i*.06),.016,'sky')
    box('Slide platform',(0,1.00,-.36),(.92,.06,.56),'oak',.02)
    rod('Handrail top',(-.36,1.20,-.48),(.36,1.20,-.48),.018,'sky')
    merge('Tint',_kid_slide(0,-.32,0,1.00,.72,1.10,.26),'coral')

def _climbing_frame_a():
    _tower(.72,.26,1.26,1.15,1.62)
    panels,paint,_=_pitched_roof(.72,.26,1.40,1.30,1.62)
    _kid_ladder(.72,-.60,0,1.12,.38,.42)
    slide=_kid_slide(.72,.78,0,1.15,.62,.58,.18)
    rod('Slide side rail',(.40,1.20,.70),(1.04,1.20,.70),.018,'sky')
    rod('Swing outrigger',(.40,1.80,.26),(-1.34,1.80,.26),.026,'oak')
    box('Swing post',(-1.34,.90,.26),(.10,1.80,.10),'oak',.01)
    rod('Swing brace',(.40,1.50,.26),(-1.34,1.34,.26),.018,'oak')
    seats=[];_swing_hang(-1.16,.26,0,1.78,.50,.40,'mustard',seats)
    merge('Tint',slide+[paint],'coral')

def _climbing_frame_b():
    _legs_a(0,1.36,.70,1.88)
    rod('Top beam',(-1.12,1.90,0),(1.12,1.90,0),.036,'oak')
    for s in (-1,1):rod('Monkey bar rail',(-.96,1.98,s*.32),(.96,1.98,s*.32),.020,'steel')
    for i in range(7):
        x=-.90+i*.30; y=2.02-.10*(x/.90)**2
        rod('Monkey bar',(x,y,-.32),(x,y,.32),.020,'steel')
    box('Climb platform',(-.40,.85,-.62),(.72,.06,.52),'oak_light',.02)
    for s in (-1,1):box('Platform post',(-.40+s*.34,.42,-.62),(.08,.85,.08),'oak',.01)
    for s in (-1,1):rod('Platform rail',(-.40+s*.36,1.20,-.88),(-.40+s*.36,1.20,-.36),.018,'oak')
    slide=_kid_slide(-.40,-.88,math.pi,.85,.60,.60,.18,drop=.69)
    _kid_ladder(-.76,-.62,0,.85,.26,.30)
    seats=[];_baby_seat(.86,0,0,1.88,.56,'sky',seats)
    merge('Tint',slide,'coral')
    box('Slide brace',(-.40,1.06,-.30),(.05,.60,.05),'steel',0)

def _climbing_frame_c():
    R=1.00
    for i in range(3):
        a=i*2*math.pi/3; a2=(i+1)*2*math.pi/3
        box('Tower post',(math.sin(a)*R,.55,math.cos(a)*R),(.09,1.10,.09),'oak',.01)
        rod('Platform rail',(math.sin(a)*R,1.44,math.cos(a)*R),(math.sin(a2)*R,1.44,math.cos(a2)*R),.018,'oak')
    cyl('Triangular platform',(0,1.10,0),R+.08,.06,'oak_light',seg=3)
    roof=cyl('Roof',(0,1.86,0),1.06,.30,'teal',top=.05,seg=3)
    band=cyl('Roof paint band',(0,1.72,0),1.02,.09,'teal_light',seg=3)
    tint(merge('Tint',[roof,band],'teal'))
    for i in range(3):
        a=i*2*math.pi/3
        rod('Roof strut',(math.sin(a)*.76,1.12,math.cos(a)*.76),(0,1.76,0),.018,'oak')
    _climb_wall(0,-.94,0)
    _net(-1.54,-.10,math.pi/2,.60,1.24)
    segs=[]
    for i in range(4):
        a=math.pi*.5+i*.95; r=.90-i*.05; y=.96-i*.24
        s=box('Spiral chute',(math.sin(a)*r,y,math.cos(a)*r),(.58,.05,.72),'coral',.02)
        tilt(s,.40,0,a); segs.append(s)
        rod('Spiral rail',(math.sin(a)*r-.28,y+.16,math.cos(a)*r),(math.sin(a)*r+.28,y+.16,math.cos(a)*r),.018,'sky')
    a=math.pi*.5+4*.95; r=.60
    segs.append(box('Spiral chute run-out',(math.sin(a)*r,.14,math.cos(a)*r),(.58,.05,.44),'coral',.02))
    merge('Spiral chute',segs,'coral')

def _climbing_frame_d():
    _tower(-.86,0,1.02,1.15,1.62)
    _tower(.86,0,1.02,1.15,1.62)
    box('Bridge deck',(0,1.15,0),(.76,.06,.86),'oak_light',.02)
    for s in (-1,1):
        rod('Bridge rail',(-.38,1.44,s*.43),(.38,1.44,s*.43),.018,'oak')
        for t in (-.32,0,.32):rod('Bridge post',(t,1.15,s*.43),(t,1.46,s*.43),.016,'oak')
    pa,ta,_=_pitched_roof(-.86,0,1.02,1.02,1.62)
    pb,tb,_=_pitched_roof(.86,0,1.02,1.02,1.62)
    left=_kid_slide(-.86,.58,0,1.15,.54,.62,.18)
    right=_kid_slide(.86,.58,0,1.15,.54,.62,.18)
    _kid_ladder(-.86,-.72,0,1.12,.30,.22)
    _kid_ladder(.86,-.72,0,1.12,.30,.22)
    tint(merge('Tint',left+right+pa,'coral'))

# ================================================================ Riding
def _bike_wheel(tag,c,R,tire=.030,spokes=9,knobs=0,sides=2):
    """sides=2 -> knobs straddle the tyre; sides=1 -> a single centre ridge."""
    torus(tag+' tyre',c,R,tire,'black',axis='X')
    torus(tag+' rim',c,R-tire-.004,.010,'steel',axis='X')
    cyl(tag+' hub',c,.032,.066,'graphite',axis='X')
    for i in range(spokes):
        a=i*2*math.pi/spokes
        rod(tag+' spoke',c,(c[0],c[1]+math.cos(a)*(R-tire-.014),c[2]+math.sin(a)*(R-tire-.014)),.005,'steel')
    rng=random.Random(len(tag)*7)
    for i in range(knobs):
        a=i*2*math.pi/knobs
        for off in ((-1,1) if sides==2 else (0,)):
            rad=R+tire*.55; pos=(c[0]+off*.018, c[1]+math.cos(a)*rad, c[2]+math.sin(a)*rad)
            ell(tag+' tyre knob',pos,(.013,.018,.013) if off else (.016,.018,.016),'black',8,6)

def _mudguard(c,R,tire,zside):
    """Three plates bowed over a wheel, the tail flicked toward zside (Godot front/back)."""
    for t in (-.44,0,.44):
        f=box('Mudguard',(0,c[1]+math.cos(t)*(R+tire+.045),c[2]+math.sin(t)*(R+tire+.045)),(.075,.025,.26),'steel',.01)
        tilt(f,t,0,0)
    tail=box('Mudguard tail',(0,c[1]+R*.70,c[2]+zside*(R*.78)),(.075,.025,.24),'steel',.01)
    tilt(tail,zside*.78,0,0)

def _bike_wheelset(R,tire,wb,spokes=9,knobs=0,mudguards=(0,0),sides=2):
    rear=(0,R+tire,-wb); front=(0,R+tire,wb)
    _bike_wheel('Rear wheel',rear,R,tire,spokes,knobs,sides)
    _bike_wheel('Front wheel',front,R,tire,spokes,knobs,sides)
    if mudguards[0]:_mudguard(rear,R,tire,-1)
    if mudguards[1]:_mudguard(front,R,tire,1)

def _bike_frame(points,colour,r=.016):
    return [rod('Frame tube',points[i],points[i+1],r,colour) for i in range(len(points)-1)]

def _bike_finish(bar_y,bar_z,bar_half,seat_y,seat_z,saddle_len,name='Handlebar'):
    rod('Seat post',(0,seat_y-.16,seat_z),(0,seat_y-.02,seat_z),.014,'steel')
    box('Saddle',(0,seat_y,seat_z),(.14,.05,saddle_len),'black',.03)
    rod('Stem',(0,bar_y-.20,bar_z),(0,bar_y,bar_z),.014,'steel')
    rod(name,(-bar_half,bar_y,bar_z),(bar_half,bar_y,bar_z),.014,'steel')
    for s in (-1,1):rod('Handle grip',(s*(bar_half-.06),bar_y,bar_z),(s*(bar_half+.02),bar_y,bar_z),.018,'black')

def _bike_cranks(bb,ring=.09,pedal_y=.20,pedal_z=.16,w=.09,drop=.50):
    cyl('Chainring',bb,ring,.014,'steel',axis='X')
    rod('Chain top',(0,bb[1]+.08,bb[2]-.06),(0,bb[1]+.10,-drop),.008,'graphite')
    rod('Chain bottom',(0,bb[1]-.06,bb[2]-.06),(0,bb[1]-.04,-drop),.008,'graphite')
    for s in (-1,1):
        rod('Crank arm',bb,(s*.02,pedal_y,pedal_z),.012,'steel')
        box('Pedal',(s*(w/2+.02),pedal_y-.02,pedal_z),(w,.02,.11),'black',.02)

def _bike_adult_a():
    n0=len(active)
    bb,st,hd=(0,.30,.02),(0,.82,-.24),(0,.98,.36)
    frame=_bike_frame([bb,st,hd,bb,(0,.37,-.50),(0,.37,.50)],'coral')
    frame.append(rod('Fork',hd,(0,.37,.50),.018,'coral'))
    tint(merge('Tint',frame,'coral'))
    _bike_wheelset(.34,.030,.50,spokes=10,mudguards=(1,1))
    _bike_finish(1.06,.32,.24,.90,-.24,.28)
    _bike_cranks(bb)
    box('Front basket',(0,.86,.48),(.32,.24,.28),'oak',.02)
    for i in range(3):rod('Basket slat',(-.15,.80+i*.06,.36),(.15,.80+i*.06,.36),.010,'oak_light')
    rod('Basket stay',(0,1.00,.40),(0,.86,.48),.012,'steel')
    cyl('Head lamp',(0,.96,.44),.035,.03,'glow',axis='Z')
    box('Rear rack',(0,.80,-.60),(.24,.03,.40),'graphite',.02)
    for s in (-1,1):rod('Rack stay',(s*.10,.80,-.72),(s*.10,.37,-.50),.010,'steel')

    turn(active[n0:],0,0,math.pi/2)
def _bike_adult_b():
    n0=len(active)
    bb,st,hd=(0,.32,.02),(0,.84,-.24),(0,1.00,.34)
    frame=_bike_frame([bb,st,hd,bb,(0,.39,-.50),(0,.39,.50)],'coral',.020)
    frame.append(rod('Fork crown',(-.07,.76,.42),(.07,.76,.42),.026,'coral'))
    tint(merge('Tint',frame,'coral'))
    _bike_wheelset(.34,.050,.50,spokes=9,knobs=8,mudguards=(1,1),sides=1)
    for s in (-1,1):
        rod('Suspension stanchion',(s*.06,1.00,.34),(s*.07,.76,.42),.022,'graphite')
        rod('Suspension slider',(s*.07,.76,.42),(s*.06,.42,.50),.018,'steel')
    _bike_finish(1.08,.30,.24,.92,-.24,.26)
    _bike_cranks(bb,pedal_y=.22,pedal_z=.16,w=.10)
    box('Bottle cage',(0,.52,.12),(.06,.14,.06),'sky',.02)

    turn(active[n0:],0,0,math.pi/2)
def _bike_adult_c():
    n0=len(active)
    bb,hd=(0,.28,.02),(0,.94,.32)
    frame=_bike_frame([bb,(0,.36,.14),(0,.50,.26),(0,.66,.32),hd],'coral')
    frame.append(rod('Seat tube',bb,(0,.80,-.26),.017,'coral'))
    frame.append(rod('Chain stay',bb,(0,.37,-.50),.015,'coral'))
    frame.append(rod('Seat stay',(0,.80,-.26),(0,.37,-.50),.015,'coral'))
    frame.append(rod('Fork',hd,(0,.37,.50),.018,'coral'))
    tint(merge('Tint',frame,'coral'))
    _bike_wheelset(.34,.030,.50,spokes=10,mudguards=(1,0))
    _bike_finish(1.04,.34,.24,.88,-.26,.28)
    for s in (-1,1):rod('Handle sweep',(s*.14,1.04,.34),(s*.20,1.04,.46),.014,'steel')
    _bike_cranks(bb)
    box('Rear rack',(0,.82,-.58),(.28,.03,.40),'graphite',.02)
    for s in (-1,1):rod('Rack stay',(s*.12,.82,-.72),(s*.10,.37,-.50),.010,'steel')
    box('Rack basket',(0,.88,-.58),(.26,.16,.34),'oak_light',.02)
    box('Skirt guard',(0,.44,-.48),(.05,.36,.32),'teal',.02)
    cyl('Head lamp',(0,.94,.42),.035,.03,'glow',axis='Z')

    turn(active[n0:],0,0,math.pi/2)
def _bike_adult_d():
    n0=len(active)
    bb,st,hd=(0,.30,.02),(0,.86,-.24),(0,1.00,.38)
    frame=_bike_frame([bb,st,hd,bb,(0,.35,-.50),(0,.35,.50)],'coral',.016)
    frame.append(rod('Fork',hd,(0,.35,.50),.016,'coral'))
    tint(merge('Tint',frame,'coral'))
    _bike_wheelset(.32,.026,.50,spokes=12)
    _bike_finish(1.06,.44,.20,.88,-.24,.26,'Drop bar top')
    for s in (-1,1):
        rod('Drop curve',(s*.20,1.06,.44),(s*.21,1.00,.52),.013,'steel')
        rod('Drop curve',(s*.21,1.00,.52),(s*.21,.86,.50),.013,'steel')
        rod('Handle grip',(s*.21,.86,.50),(s*.21,.80,.46),.016,'black')
    _bike_cranks(bb,ring=.10,pedal_y=.22,pedal_z=.16,w=.08)
    box('Saddle bag',(0,.80,-.34),(.12,.10,.16),'teal',.03)

    turn(active[n0:],0,0,math.pi/2)
def _kids_wheels(R,tire,wb,spokes=7):
    _bike_wheel('Rear wheel',(0,R+tire,-wb),R,tire,spokes)
    _bike_wheel('Front wheel',(0,R+tire,wb),R,tire,spokes)

def _bike_kids_a():
    n0=len(active)
    bb,st,hd=(0,.20,.01),(0,.56,-.16),(0,.62,.22)
    frame=_bike_frame([bb,st,hd,bb,(0,.20,-.34),(0,.20,.34)],'lime',.014)
    frame.append(rod('Fork',hd,(0,.20,.34),.014,'lime'))
    tint(merge('Tint',frame,'lime'))
    _kids_wheels(.175,.025,.34)
    rod('Seat post',st,(0,.60,-.16),.012,'steel')
    box('Saddle',(0,.62,-.16),(.11,.04,.20),'black',.03)
    rod('Stem',hd,(0,.66,.18),.012,'steel')
    rod('Handlebar',(-.15,.66,.18),(.15,.66,.18),.012,'steel')
    for s in (-1,1):
        rod('Handle grip',(s*.11,.66,.18),(s*.18,.66,.18),.016,'black')
        for i in range(4):
            f=box('Handlebar streamer',(s*.20,.60-i*.05,.20),(.012,.12,.02),['rose','sky','gold','lime'][i],0)
            tilt(f,0,0,s*.5)
    box('Grip pad',(0,.58,.04),(.07,.04,.14),'sky',.02)

    turn(active[n0:],0,0,math.pi/2)
def _bike_kids_b():
    n0=len(active)
    bb,st,hd=(0,.20,.01),(0,.58,-.16),(0,.64,.20)
    frame=_bike_frame([bb,st,hd,bb,(0,.20,-.34),(0,.20,.34)],'coral',.014)
    frame.append(rod('Fork',hd,(0,.20,.34),.014,'coral'))
    tint(merge('Tint',frame,'coral'))
    _kids_wheels(.175,.025,.34)
    rod('Seat post',st,(0,.62,-.16),.012,'steel')
    box('Saddle',(0,.64,-.16),(.13,.05,.21),'black',.03)
    rod('Stem',hd,(0,.68,.16),.012,'steel')
    rod('Handlebar',(-.16,.68,.16),(.16,.68,.16),.012,'steel')
    for s in (-1,1):rod('Handle grip',(s*.12,.68,.16),(s*.19,.68,.16),.016,'black')
    _bike_cranks(bb,ring=.05,pedal_y=.14,pedal_z=.10,w=.07,drop=.34)
    for s in (-1,1):
        rod('Stabiliser arm',(s*.05,.20,-.34),(s*.15,.15,-.36),.012,'steel')
        torus('Stabiliser wheel',(s*.17,.15,-.36),.075,.022,'black',axis='X')
    box('Number plate',(0,.70,.16),(.14,.10,.02),'white',.01)
    rod('Flag pole',(0,.34,-.42),(0,.74,-.42),.008,'steel')
    box('Safety flag',(0,.74,-.42),(.10,.10,.02),'rose',0)

    turn(active[n0:],0,0,math.pi/2)
def _bike_kids_c():
    n0=len(active)
    bb,st,hd=(0,.20,.01),(0,.58,-.15),(0,.66,.18)
    frame=_bike_frame([bb,st,hd,bb,(0,.20,-.34),(0,.20,.34)],'sky',.014)
    frame.append(rod('Fork',hd,(0,.20,.34),.014,'sky'))
    tint(merge('Tint',frame,'sky'))
    _kids_wheels(.175,.025,.34)
    rod('Seat post',st,(0,.62,-.15),.012,'steel')
    box('Saddle',(0,.64,-.15),(.12,.05,.20),'black',.03)
    rod('Stem',hd,(0,.70,.14),.012,'steel')
    rod('Handlebar',(-.17,.70,.14),(.17,.70,.14),.012,'steel')
    for s in (-1,1):rod('Handle grip',(s*.13,.70,.14),(s*.20,.70,.14),.016,'black')
    _bike_cranks(bb,ring=.05,pedal_y=.14,pedal_z=.10,w=.07,drop=.34)
    for s in (-1,1):box('Frame pad',(s*.02,.54,-.04),(.05,.06,.20),'mustard',.02)
    box('Bar pad',(0,.70,.14),(.26,.05,.05),'mustard',.02)
    box('Front basket',(0,.56,.38),(.24,.18,.22),'lime',.02)
    for i in range(3):rod('Basket slat',(-.11,.52+i*.05,.29),(.11,.52+i*.05,.29),.009,'gold')

    turn(active[n0:],0,0,math.pi/2)
def _bike_kids_d():
    n0=len(active)
    bb,st,hd=(0,.20,.01),(0,.54,-.14),(0,.58,.18)
    frame=_bike_frame([bb,st,hd,bb,(0,.20,-.32)],'mustard',.014)
    frame.append(rod('Seat stay',st,(0,.20,-.32),.012,'mustard'))
    frame.append(rod('Fork',hd,(0,.20,.32),.014,'mustard'))
    tint(merge('Tint',frame,'mustard'))
    _bike_wheel('Rear wheel',(0,.20,-.32),.175,.025,7)
    _bike_wheel('Front wheel',(0,.20,.32),.175,.025,7)
    for s in (-1,1):
        _bike_wheel('Trike wheel',(s*.16,.16,-.34),.095,.018,6)
        rod('Trike axle',(s*.08,.20,-.32),(s*.16,.16,-.34),.012,'steel')
    box('Rear basket',(0,.36,-.48),(.28,.20,.22),'lime',.02)
    for i in range(3):rod('Basket slat',(-.12,.30+i*.06,-.37),(.12,.30+i*.06,-.37),.009,'gold')
    for s in (-1,1):rod('Basket stay',(s*.11,.36,-.40),(s*.11,.46,-.32),.010,'steel')
    rod('Seat post',st,(0,.64,-.14),.012,'steel')
    box('Saddle',(0,.66,-.14),(.13,.06,.22),'black',.04)
    rod('Stem',hd,(0,.68,.12),.014,'steel')
    rod('Handlebar',(-.17,.68,.12),(.17,.68,.12),.012,'steel')
    for s in (-1,1):rod('Handle grip',(s*.13,.68,.12),(s*.20,.68,.12),.016,'black')
    _bike_cranks(bb,ring=.05,pedal_y=.14,pedal_z=.10,w=.07,drop=.34)

    turn(active[n0:],0,0,math.pi/2)
def _helmet(colour,hx=.13,hy=.10,hz=.10,peak=True,tail=False,seg=20):
    """Shell squashed so its helmet height (Godot y = Blender z) is a real 0.20 m."""
    tint(ell('Shell',(0,hz,0),(hx,hz,hy),colour,seg,12))
    for i in range(4):
        v=box('Vent',(-.045+i*.03,hz*1.85,-.04+i*.045),(.022,.04,.09),'graphite',0)
    for i in range(3):box('Vent slot',(-.05+i*.05,hz*1.30,hy*.55),(.03,.05,.06),'graphite',0)
    torus('Shell rim',(0,.012,0),hx*.96,.014,'graphite')
    if peak:
        p=box('Peak',(0,.038,hy+.035),(hx*1.5,.02,.075),'graphite',.02); tilt(p,-.18)
    if tail:ell('Aero tail',(0,hz*1.4,-hy-.025),(.085,.05,.035),'graphite',12,8)
    for s in (-1,1):
        rod('Chin strap',(s*hx*.78,hz*.55,.02),(s*hx*.4,.006,.09),.008,'graphite')
        rod('Chin strap',(s*hx*.78,hz*.55,-.09),(s*hx*.4,.006,.09),.008,'graphite')
    box('Strap buckle',(0,.010,.09),(.05,.025,.02),'steel',0)

def _helmet_a():_helmet('sky')
def _helmet_b():
    _helmet('lime',.125,.10,.105,tail=True)
    for s in (-1,1):box('Side scoop',(s*.125,.075,-.02),(.02,.05,.12),'graphite',0)
def _helmet_c():
    _helmet('rose',.122,.105,.10,seg=18)
    ell('Chin pad',(0,.048,.155),(.07,.05,.05),'plum',12,8)
    box('Buckle plate',(0,.070,.145),(.06,.04,.02),'gold',0)

# ================================================================ Ready-made garden
W,D=4.0,3.0
def _ready_kerb():
    planks=[]
    for s in (-1,1):
        planks.append(box('Border kerb',(0,.07,s*(D/2-.10)),(W,.14,.10),'oak',.01))
        planks.append(box('Border kerb',(s*(W/2-.10),.07,0),(.10,.14,D-.40),'oak',.01))
        for t in (-1,1):
            planks.append(box('Border kerb',(s*(W/2-.25),.07,t*(D/2-.10)),(.20,.14,.10),'oak',.01))
            planks.append(box('Kerb peg',(s*(W/2-.42),.07,t*(D/2-.30)),(.13,.13,.13),'walnut',.01))
    merge('Tint',planks,'oak')

def _ready_beds():
    ell('Shaped bed',(-1.30,.06,-.70),(.62,.06,.42),'soil',16,10)
    ell('Shaped bed',(.20,.06,.60),(.78,.06,.44),'soil',16,10)
    box('Kitchen bed',(1.25,.06,-.60),(1.10,.12,.70),'soil',.02)
    for i in range(2):box('Kitchen bed divider',(1.25,.13,-.78+i*.36),(1.10,.02,.04),'oak_light',0)

def _ready_planting(seed=7):
    rng=random.Random(seed)
    for i in range(5):
        a=i*1.7+rng.uniform(-.2,.2)
        px,py=math.sin(a)*(1.00+i*.20),math.cos(a)*(.55+i*.13)
        ell('Shrub',(px,.20,py),(.21,.22,.21),['pine','green','teal','moss','green'][i],12,8)
        ell('Shrub crown',(px,.34,py),(.14,.12,.14),'leaf_light',10,6)
    for i in range(3):foliage(-1.65+i*.26,.06,-1.05+i*.12,.55,4,['lime','blossom','rose'][i])
    for i in range(4):
        a=i*2.1
        ell('Flower clump',(.15+math.sin(a)*.55,.12,.70+math.cos(a)*.30),(.10,.08,.10),['blossom','rose','lime','gold'][i],10,6)
    for i in range(2):ell('Flower clump',(1.05+i*.30,.14,-.42),(.10,.08,.10),['rose','blossom'][i],10,6)

def _ready_lights():
    for x in (-1.62,1.70):
        rod('Path light post',(x,0,1.18),(x,.76,1.18),.020,'graphite')
        cyl('Path light shade',(x,.84,1.18),.075,.10,'dark',top=.03)
        ell('Path light glow',(x,.84,1.18),(.045,.04,.045),'glow',12,8)
        cyl('Path light base',(x,.02,1.18),.08,.04,'graphite')

def _ready_rocks():
    for i,(s,px,py) in enumerate([(.30,-1.58,-1.00),(.20,1.25,1.15),(.13,1.58,.70),(.24,-1.42,1.10),(.15,.75,-1.15)]):
        rock('Border rock',(px,s*.74,py),(s,s*.90,s*.74),'granite',1 if s<.2 else 2,seed=i+3)

def _ready_tree():
    rod('Tree trunk',(1.05,0,-1.02),(1.05,1.05,-1.02),.085,'bark')
    for i in range(3):
        a=i*2.2
        rod('Tree branch',(1.05,1.00,-1.02),(1.05+math.sin(a)*.34,1.52,-1.02+math.cos(a)*.26),.038,'bark')
    for i in range(5):
        a=i*2.399
        ell('Tree foliage',(1.05+math.sin(a)*.34,1.55+(i%3)*.14,-1.02+math.cos(a)*.28),(.34,.30,.32),['green','pine','moss'][i%3],14,10)

def _garden_ready_plain():
    _ready_kerb(); _ready_beds(); _ready_planting(); _ready_lights()
def _garden_ready_tree():
    _garden_ready_plain(); _ready_tree()
def _garden_ready_rocks():
    _garden_ready_plain(); _ready_rocks()
def _garden_ready_tree_rocks():
    _garden_ready_plain(); _ready_tree(); _ready_rocks()

catalog={
 'bbq_round':_bbq_round,'bbq_barrel':_bbq_barrel,'bbq_brick':_bbq_brick,
 'garden_table':_garden_table,
 'outdoor_tv_classic':_outdoor_tv_classic,'outdoor_tv_console':_outdoor_tv_console,'outdoor_tv_stand':_outdoor_tv_stand,
 'outdoor_swing_a':_outdoor_swing_a,'outdoor_swing_b':_outdoor_swing_b,'outdoor_swing_c':_outdoor_swing_c,
 'kids_swing_a':_kids_swing_a,'kids_swing_b':_kids_swing_b,'kids_swing_c':_kids_swing_c,
 'sand_pit':_sand_pit,'kids_slide':_kids_slide,
 'climbing_frame_a':_climbing_frame_a,'climbing_frame_b':_climbing_frame_b,
 'climbing_frame_c':_climbing_frame_c,'climbing_frame_d':_climbing_frame_d,
 'bike_adult_a':_bike_adult_a,'bike_adult_b':_bike_adult_b,'bike_adult_c':_bike_adult_c,'bike_adult_d':_bike_adult_d,
 'bike_kids_a':_bike_kids_a,'bike_kids_b':_bike_kids_b,'bike_kids_c':_bike_kids_c,'bike_kids_d':_bike_kids_d,
 'helmet_a':_helmet_a,'helmet_b':_helmet_b,'helmet_c':_helmet_c,
 'garden_ready_plain':_garden_ready_plain,'garden_ready_tree':_garden_ready_tree,
 'garden_ready_rocks':_garden_ready_rocks,'garden_ready_tree_rocks':_garden_ready_tree_rocks,
}
parser=argparse.ArgumentParser()
parser.add_argument('--only',choices=tuple(catalog))
parser.add_argument('--source-out',default='art/outdoor_garden/outdoor_garden.blend')
args=parser.parse_args(sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else [])
catalog={args.only:catalog[args.only]} if args.only else catalog
MODELS=ROOT/'assets/models'; MODELS.mkdir(parents=True,exist_ok=True)
(ROOT/args.source_out).parent.mkdir(parents=True,exist_ok=True)
for name in catalog:
    destination=MODELS/f'{name}.glb'
    if destination.exists():raise RuntimeError('Refusing to replace an existing garden model: '+str(destination))

def measure(objs):
    """Exact evaluated-geometry bounds. Blender +Z is up, so index 2 is height."""
    bpy.context.view_layer.update()
    dg=bpy.context.evaluated_depsgraph_get(); lo=[1e9]*3; hi=[-1e9]*3; who=[None]*6
    for o in objs:
        ev=o.evaluated_get(dg); m=ev.to_mesh()
        mx=ev.matrix_world
        for v in m.vertices:
            p=mx @ v.co
            for i in range(3):
                if p[i]<lo[i]:lo[i]=p[i]; who[i]=o.name
                if p[i]>hi[i]:hi[i]=p[i]; who[3+i]=o.name
        ev.to_mesh_clear()
    return (hi[0]-lo[0], hi[1]-lo[1], hi[2]-lo[2], lo[2], who)

for idx,(name,fn) in enumerate(catalog.items()):
    for o in list(bpy.data.objects):
        if o.name=='Tint' or o.name.startswith('Tint.'):o.name='tint_%d_%s'%(idx,o.name)
    active=[]; fn()
    tints=[o for o in bpy.data.objects if o.name=='Tint']
    if len(tints)!=1:raise RuntimeError('%s must contain exactly one mesh named Tint, found %d'%(name,len(tints)))
    if tints[0] not in active:raise RuntimeError('%s tint is not part of the exported node tree'%name)
    w,d,h,low,who=measure(active)
    if abs(low)>1e-4:
        # Sit the finished prop exactly on the ground plane: catalogue spawn points
        # expect the model root at ground contact.
        for o in active:o.location.z-=low
        w,d,h,low,who=measure(active)
    root=bpy.data.objects.new(name,None); bpy.context.collection.objects.link(root)
    for o in active:
        if o.parent is None:o.parent=root
    bpy.context.view_layer.update()
    bpy.ops.object.select_all(action='DESELECT'); root.select_set(True)
    for o in active:o.select_set(True)
    bpy.context.view_layer.objects.active=root
    bpy.ops.export_scene.gltf(filepath=str(MODELS/f'{name}.glb'),export_format='GLB',use_selection=True,export_apply=True,export_animations=False)
    print('DIMS %-24s w=%.3f d=%.3f h=%.3f ground=%+.3f parts=%d'%(name,w,d,h,low,len(active)))
    print('     EXT %s'%(' '.join('%s=%s'%(t,who[i]) for i,t in enumerate(('minX','minY','minZ','maxX','maxY','maxZ')))))
    root.location=((idx%6)*4,(idx//6)*4,0)
bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/args.source_out))
print('JUSTLIFE_OUTDOOR_GARDEN_COMPLETE', len(catalog))
