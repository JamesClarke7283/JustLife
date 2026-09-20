"""Original JustLife furniture, second collection. Run: blender -b --python tools/create_furniture_v2.py.

Adds comfort, bathroom, activity, decor and outdoor furnishings that the first
collection lacked. Coordinates are Godot metres: x right, y up, z toward the
front of the furnishing. Seats face +z; standing activities happen at +z.
"""
import bpy, math, random, pathlib, argparse, sys
from mathutils import Vector
ROOT = pathlib.Path(__file__).resolve().parents[1]
random.seed(41)
bpy.ops.wm.read_factory_settings(use_empty=True)
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
for n,h in [('oak','AB7951'),('oak_light','D7AE7E'),('walnut','624435'),('cream','EFE9DA'),('white','FAF6EA'),('teal','417A71'),('teal_light','86ADA0'),('coral','C97C66'),('gold','C8A562'),('dark','263E3C'),('black','1D292B'),('green','48794B'),('leaf_light','749752'),('soil','42352D'),('blue','7CA4AA'),('screen','406C72'),('linen','DECFAF'),('book','B6B29C'),('water','B7D9DB'),('rust','9A5A44'),('brick','8C5A4A'),('mustard','D2A24B'),('plum','6E5470'),('sky','9EC1CF'),('rose','D9A0A0'),('graphite','4A4F55'),('ivory','F6F1E4')]: mat(n,h)
mat('flame','F2A93B',.9,0,6.0); mat('ember','E0602A',.9,0,2.5)
mat('mirror_glass','F2F7FA',.3,0,1.0); mat('brass','C8A562',.4,.35); mat('steel','B9BEC2',.35,.45)
M['gold'].node_tree.nodes.get('Principled BSDF').inputs['Metallic'].default_value=.65
active=[]
def xyz(p): return (p[0],-p[2],p[1])
def finish(o,n,m):
    o.name=n; o.data.materials.append(M[m]); active.append(o); return o
def box(n,p,s,m,bevel=.03):
    bpy.ops.mesh.primitive_cube_add(size=1,location=xyz(p)); o=bpy.context.object; o.dimensions=(s[0],s[2],s[1]); bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
    if bevel:
        mod=o.modifiers.new('Soft crafted edges','BEVEL'); mod.width=bevel; mod.segments=3
        mod=o.modifiers.new('Weighted corner normals','WEIGHTED_NORMAL')
    return finish(o,n,m)
def ell(n,p,s,m):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=20,ring_count=12,location=xyz(p)); o=bpy.context.object; o.scale=(s[0],s[2],s[1]); bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
    for f in o.data.polygons:f.use_smooth=True
    return finish(o,n,m)
def cyl(n,p,r,h,m,top=None,axis='Y'):
    bpy.ops.mesh.primitive_cone_add(vertices=32,radius1=r,radius2=r if top is None else top,depth=h,location=xyz(p)); o=bpy.context.object
    if axis=='X':o.rotation_euler=(0,math.pi/2,0)
    elif axis=='Z':o.rotation_euler=(math.pi/2,0,0)
    bevel=o.modifiers.new('Rounded rims','BEVEL'); bevel.width=.012; bevel.segments=3
    for f in o.data.polygons:f.use_smooth=True
    return finish(o,n,m)
def rod(n,a,b,r,m):
    av,bv=Vector(xyz(a)),Vector(xyz(b)); d=bv-av
    bpy.ops.mesh.primitive_cylinder_add(vertices=12,radius=r,depth=d.length,location=(av+bv)/2); o=bpy.context.object; o.rotation_euler=d.to_track_quat('Z','Y').to_euler(); return finish(o,n,m)
def torus(n,p,major,minor,m,axis='Y'):
    bpy.ops.mesh.primitive_torus_add(major_segments=36,minor_segments=10,major_radius=major,minor_radius=minor,location=xyz(p)); o=bpy.context.object
    if axis=='Z':o.rotation_euler=(math.pi/2,0,0)
    for f in o.data.polygons:f.use_smooth=True
    return finish(o,n,m)
def legs(w,d,h,m='oak',inset=.10,size=.065):
    for x in [-w/2+inset,w/2-inset]:
        for z in [-d/2+inset,d/2-inset]:box('Tapered leg',(x,h/2,z),(size,h,size),m,.012)
def foliage(x,y,z,scale=1,leaves=7,color='green'):
    for i in range(leaves):
        a=i*2.399; height=(.42+(i%3)*.12)*scale
        end=(x+math.sin(a)*.22*scale,y+height,z+math.cos(a)*.22*scale)
        rod('Leaf stem',(x,y,z),end,.010*scale,'green')
        leaf=ell('Satin leaf',end,(.10*scale,.17*scale,.04*scale),color if i%2 else 'leaf_light'); leaf.rotation_euler=(.5*math.sin(a),.45,a)

# ---------------------------------------------------------------- Comfort
def armchair():
    legs(.92,.86,.16,'walnut',.09)
    box('Armchair base',(0,.26,0),(.94,.24,.86),'mustard',.08)
    box('Seat cushion',(0,.45,.05),(.62,.16,.66),'linen',.08)
    box('Armchair back',(0,.66,-.35),(.94,.66,.18),'mustard',.10)
    box('Back cushion',(0,.68,-.24),(.62,.42,.14),'linen',.08)
    for x in [-.36,.36]:box('Rounded arm',(x,.48,.02),(.22,.44,.86),'mustard',.09)
def loveseat():
    legs(1.85,.92,.20,'walnut',.10)
    box('Loveseat base',(0,.30,0),(1.85,.26,.92),'plum',.09)
    box('Upholstered back',(0,.72,-.36),(1.85,.68,.22),'plum',.11)
    for x in [-.82,.82]:box('Rounded arm',(x,.55,0),(.22,.56,.96),'plum',.10)
    for x in [-.37,.37]:
        box('Seat cushion',(x,.52,.06),(.68,.20,.70),'rose',.08)
        box('Back cushion',(x,.84,-.25),(.69,.50,.18),'rose',.08)
    o=box('Linen scatter cushion',(0,.80,-.02),(.38,.38,.16),'cream',.10); o.rotation_euler[1]=.25
def stool():
    cyl('Stool seat',(0,.70,0),.20,.06,'oak_light')
    cyl('Seat pad',(0,.735,0),.17,.025,'teal')
    for i in range(4):
        a=i*math.pi/2+math.pi/4
        rod('Splayed leg',(math.sin(a)*.11,.66,math.cos(a)*.11),(math.sin(a)*.20,.02,math.cos(a)*.20),.016,'black')
    torus('Footrest ring',(0,.24,0),.19,.010,'black')

# ---------------------------------------------------------------- Bathroom
def bathtub():
    # A real open basin: floor slab, four walls and a rim frame, so the water and bubbles are visible.
    box('Tub floor',(0,.06,0),(1.70,.12,.84),'white',.05)
    for z in [-.37,.37]:box('Tub wall',(0,.30,z),(1.70,.58,.10),'white',.04)
    for x in [-.80,.80]:box('Tub end',(x,.30,0),(.10,.58,.84),'white',.04)
    box('Basin floor',(0,.125,0),(1.50,.015,.64),'ivory',.0)
    box('Bath water',(0,.44,0),(1.50,.02,.64),'water',.0)
    for z in [-.37,.37]:box('Tub rim',(0,.585,z),(1.72,.03,.12),'cream',.012)
    for x in [-.80,.80]:box('Tub rim',(x,.585,0),(.12,.03,.86),'cream',.012)
    for x in [-.60,.60]:box('Claw foot',(x,.05,.28),(.16,.10,.12),'brass',.02); box('Claw foot',(x,.05,-.28),(.16,.10,.12),'brass',.02)
    rod('Tap stem',(.72,.58,-.30),(.72,.86,-.30),.02,'brass'); rod('Spout',(.72,.86,-.30),(.55,.86,-.14),.02,'brass')
    for z in [-.40,-.20]:cyl('Tap handle',(.72,.70,z),.035,.03,'brass')
    ell('Soap',(-.55,.60,-.36),(.09,.03,.06),'rose')
    for i in range(6):
        a=i*1.7; ell('Bubble',(-.40+i*.16,.46,math.sin(a)*.18),(.05,.03,.05),'ivory')

# ---------------------------------------------------------------- Activities
def mirror():
    # A round brass frame with the glass proud of its front face, so the glass is what the room sees.
    cyl('Mirror frame',(0,1.02,0),.36,.03,'brass',axis='Z')
    cyl('Mirror glass',(0,1.02,.021),.325,.012,'mirror_glass',axis='Z')
    for x in [-.22,.22]:rod('Stand upright',(x,.02,-.10),(x,1.15,-.06),.016,'brass')
    for x in [-.22,.22]:box('Stand foot',(x,.02,-.10),(.05,.04,.36),'brass',.01)
def piano():
    global box,cyl
    _b,_c=box,cyl
    box=lambda n,p,s,m,bevel=.03:_b(n,(p[0],p[1],p[2]-.22),s,m,bevel)
    cyl=lambda n,p,r,h,m,top=None,axis='Y':_c(n,(p[0],p[1],p[2]-.22),r,h,m,top,axis)
    box('Piano body',(0,.70,-.12),(1.50,1.24,.44),'walnut',.02)
    box('Piano lid',(0,1.33,-.12),(1.52,.04,.46),'walnut',.01)
    box('Music stand',(0,1.10,.10),(.70,.30,.02),'walnut',.006)
    box('Sheet music',(0,1.10,.115),(.42,.26,.004),'cream',0)
    box('Key bed',(0,.76,.18),(1.40,.06,.30),'walnut',.01)
    box('Fall board',(0,.86,.10),(1.42,.14,.04),'walnut',.01)
    white=21; width=1.24/white
    for i in range(white):
        x=-.62+width/2+i*width
        box('White key',(x,.795,.20),(width-.004,.02,.26),'ivory',0)
        if i%7 in (0,1,3,4,5):box('Black key',(x+width/2,.81,.15),(width*.55,.025,.15),'black',0)
    for x in [-.68,.68]:box('Piano leg',(x,.20,.28),(.09,.40,.09),'walnut',.01)
    for x in [-.22,.22]:cyl('Pedal',(x,.05,.30),.02,.03,'brass')
    box('Pedal lyre',(0,.20,.24),(.30,.30,.03),'walnut',.006)
    box('Piano bench',(0,.48,.62),(.86,.06,.34),'walnut',.02)
    box('Bench cushion',(0,.52,.62),(.80,.03,.30),'plum',.02)
    for x in [-.36,.36]:
        for z in [.50,.74]:box('Bench leg',(x,.23,z),(.05,.46,.05),'walnut',.006)
    box,cyl=_b,_c

def chess():
    box('Games table top',(0,.70,0),(.80,.05,.80),'oak',.02)
    rod('Pedestal',(0,.06,0),(0,.68,0),.045,'oak'); cyl('Pedestal foot',(0,.03,0),.24,.05,'oak')
    for r in range(8):
        for c in range(8):
            box('Board square',(-.28+c*.08,.727,-.28+r*.08),(.08,.006,.08),'cream' if (r+c)%2 else 'walnut',0)
    pieces=[('cream',(-.28,-.28)),('cream',(-.12,-.28)),('cream',(.20,-.20)),('cream',(.04,-.04)),('walnut',(.28,.28)),('walnut',(.12,.20)),('walnut',(-.20,.12)),('walnut',(-.04,.28))]
    for i,(m,(x,z)) in enumerate(pieces):
        cyl('Chess piece',(x,.76,z),.022,.06,m,.014); ell('Piece crown',(x,.80,z),(.02,.02,.02),m)
    for z in [-.62,.62]:
        cyl('Games stool seat',(0,.46,z),.19,.05,'oak_light'); cyl('Stool cushion',(0,.49,z),.16,.02,'teal')
        for i in range(3):
            a=i*2*math.pi/3
            rod('Stool leg',(math.sin(a)*.12,.44,z+math.cos(a)*.12),(math.sin(a)*.17,.02,z+math.cos(a)*.17),.016,'oak')
def treadmill():
    box('Treadmill deck',(0,.09,.15),(.82,.12,1.62),'graphite',.03)
    box('Running belt',(0,.152,.15),(.62,.01,1.52),'black',.004)
    for i in range(10):box('Belt tread',(0,.158,-.55+i*.155),(.60,.002,.03),'graphite',0)
    for x in [-.36,.36]:
        rod('Frame upright',(x,.10,-.60),(x,1.15,-.70),.024,'steel')
        rod('Hand rail',(x,1.15,-.70),(x,1.05,-.05),.02,'steel')
    box('Console',(0,1.28,-.72),(.72,.28,.10),'graphite',.02)
    o=box('Console screen',(0,1.30,-.665),(.42,.16,.006),'screen',0)
    box('Screen graph',(0,1.30,-.661),(.30,.05,.002),'teal_light',0)
    for x in [-.28,.28]:cyl('Console button',(x,1.27,-.664),.02,.006,'coral',axis='Z')
def yoga_mat():
    box('Yoga mat',(0,.012,0),(.66,.022,1.82),'plum',.010)
    cyl('Rolled end',(0,.04,-.88),.04,.64,'plum',axis='X')
    box('Mat stripe',(0,.024,0),(.04,.002,1.70),'rose',0)
def stereo():
    legs(.88,.40,.10,'black',.06,.04)
    box('Stereo cabinet',(0,.50,0),(.90,.80,.40),'walnut',.02)
    box('Record deck',(0,.92,0),(.92,.04,.42),'walnut',.01)
    cyl('Turntable platter',(-.18,.945,0),.16,.01,'black'); cyl('Vinyl record',(-.18,.952,0),.15,.004,'graphite'); cyl('Record label',(-.18,.956,0),.05,.003,'coral')
    rod('Tone arm',(.12,.97,-.12),(-.08,.96,.04),.008,'steel'); cyl('Arm pivot',(.12,.955,-.12),.025,.03,'steel')
    for x in [-.22,.22]:
        box('Speaker grille',(x,.44,.205),(.34,.62,.012),'linen',.004)
        cyl('Woofer',(x,.30,.212),.11,.01,'black',axis='Z'); cyl('Tweeter',(x,.62,.212),.05,.01,'black',axis='Z')
    for i in range(3):cyl('Volume knob',(.26+i*.08,.86,.21),.02,.02,'brass',axis='Z')
def toybox():
    box('Toy chest',(0,.24,0),(.82,.46,.52),'sky',.02)
    box('Chest lid',(0,.49,-.04),(.84,.05,.44),'coral',.015)
    for x in [-.20,.20]:box('Lid stripe',(x,.52,-.04),(.06,.006,.40),'cream',0)
    box('Chest trim',(0,.03,0),(.84,.06,.54),'cream',.01)
    ell('Ball',(-.22,.57,.02),(.10,.10,.10),'mustard'); ell('Ball stripe',(-.22,.57,.02),(.102,.03,.102),'coral')
    for i,(x,z,m) in enumerate([(.10,-.06,'teal'),(.20,.10,'rose'),(.30,-.08,'sky')]):box('Wooden block',(x,.55+i*.0,z),(.09,.09,.09),m,.008)
    box('Toy train body',(.02,.55,.14),(.22,.10,.08),'coral',.01); cyl('Train funnel',(.09,.62,.14),.02,.05,'black')
    for x in [-.05,.06]:cyl('Train wheel',(x,.51,.185),.025,.02,'black',axis='Z'); cyl('Train wheel',(x,.51,.095),.025,.02,'black',axis='Z')
def wardrobe():
    box('Wardrobe carcass',(0,1.0,0),(1.20,2.0,.58),'oak',.015)
    box('Cornice',(0,2.02,0),(1.24,.05,.62),'walnut',.008)
    box('Plinth',(0,.04,0),(1.22,.08,.60),'walnut',.008)
    for x in [-.29,.29]:
        box('Wardrobe door',(x,1.04,.30),(.55,1.82,.03),'oak_light',.01)
        box('Door panel',(x,1.30,.318),(.40,.95,.006),'oak',.004)
        box('Door panel',(x,.55,.318),(.40,.45,.006),'oak',.004)
    for x in [-.06,.06]:rod('Door handle',(x,.92,.34),(x,1.14,.34),.012,'brass')
def garden_bed():
    for z in [-.40,.40]:box('Planter side',(0,.20,z),(1.60,.40,.05),'walnut',.008)
    for x in [-.78,.78]:box('Planter end',(x,.20,0),(.05,.40,.86),'walnut',.008)
    for x in [-.78,.78]:
        for z in [-.40,.40]:box('Corner post',(x,.23,z),(.08,.46,.08),'walnut',.008)
    box('Bed soil',(0,.36,0),(1.52,.04,.78),'soil',.01)
    for i in range(3):
        for j in range(2):
            x=-.50+i*.50; z=-.20+j*.40
            foliage(x,.37,z,.9 if (i+j)%2 else .75,7,'green' if j else 'leaf_light')
            if (i+j)%2:ell('Ripe tomato',(x+.10,.52,z+.05),(.045,.045,.045),'coral')
    cyl('Watering can',(.66,.46,-.30),.08,.16,'teal'); rod('Can spout',(.72,.50,-.30),(.84,.60,-.30),.012,'teal'); torus('Can handle',(.66,.56,-.30),.06,.008,'teal',axis='Z')
def computer():
    legs(1.35,.68,.77)
    box('Desk top',(0,.82,0),(1.42,.09,.74),'oak_light',.03)
    box('Monitor stand',(0,.89,-.18),(.24,.05,.16),'black',.01); rod('Monitor neck',(0,.90,-.20),(0,1.06,-.22),.02,'black')
    o=box('Monitor',(0,1.20,-.20),(.66,.40,.03),'black',.01)
    box('Monitor screen',(0,1.20,-.183),(.60,.34,.004),'screen',0)
    for i,w in enumerate([.34,.26,.42,.20]):box('Window line',(-.10+i*.02,1.30-i*.05,-.180),(w,.012,.002),'teal_light',0)
    box('Keyboard',(0,.874,.10),(.44,.018,.16),'ivory',.006)
    for r in range(4):
        for c in range(12):box('Key cap',(-.19+c*.035,.885,.045+r*.036),(.028,.006,.028),'cream',0)
    box('Mouse',(.32,.878,.12),(.06,.03,.10),'ivory',.01)
    box('Tower',(.52,.30,-.08),(.20,.50,.46),'graphite',.01); cyl('Power light',(.52,.50,.152),.008,.004,'teal_light',axis='Z')
    cyl('Mug',(-.52,.92,.14),.045,.10,'coral')

# ---------------------------------------------------------------- Decor
def wall_clock():
    cyl('Clock case',(0,1.65,0),.22,.05,'walnut',axis='Z')
    cyl('Clock face',(0,1.65,.028),.19,.006,'ivory',axis='Z')
    for i in range(12):
        a=i*math.pi/6; box('Hour mark',(math.sin(a)*.16,1.65+math.cos(a)*.16,.033),(.012,.03,.002),'black',0); 
    rod('Hour hand',(0,1.65,.036),(.06,1.75,.036),.006,'black'); rod('Minute hand',(0,1.65,.036),(-.12,1.71,.036),.005,'black'); cyl('Hand pin',(0,1.65,.038),.012,.006,'brass',axis='Z')
def shelf():
    box('Floating shelf',(0,1.40,0),(.90,.04,.24),'oak',.008)
    for x in [-.36,.36]:box('Shelf bracket',(x,1.34,-.08),(.03,.08,.06),'brass',.004)
    for i in range(5):
        h=random.uniform(.16,.24); box('Shelf book',(-.34+i*.055,1.42+h/2,-.02),(.045,h,.17),['coral','teal','plum','mustard','book'][i],.003)
    cyl('Small planter',(.22,1.47,0),.07,.10,'cream',.055); foliage(.22,1.52,0,.45,5,'green')
    ell('Ceramic bowl',(.02,1.44,.02),(.08,.04,.08),'teal_light')
def side_table():
    cyl('Table top',(0,.53,0),.26,.04,'oak_light')
    for i in range(3):
        a=i*2*math.pi/3
        rod('Splayed leg',(math.sin(a)*.10,.50,math.cos(a)*.10),(math.sin(a)*.20,.02,math.cos(a)*.20),.02,'oak')
    cyl('Stoneware vase',(0,.62,0),.06,.14,'teal',.04)
    for i in range(3):
        a=i*2.1; rod('Dried stem',(0,.68,0),(math.sin(a)*.08,.90+i*.03,math.cos(a)*.08),.005,'gold')
        ell('Seed head',(math.sin(a)*.08,.91+i*.03,math.cos(a)*.08),(.03,.05,.03),'linen')
def fireplace():
    # The breast is built around an open firebox so the logs and flames show from the room.
    for x in [-.55,.55]:box('Chimney breast',(x,.70,-.12),(.30,1.40,.30),'brick',.01)
    box('Chimney lintel',(0,1.12,-.12),(.82,.56,.30),'brick',.01)
    box('Firebox back',(0,.42,-.255),(.82,.84,.03),'black',0)
    box('Firebox floor',(0,.10,-.12),(.82,.04,.30),'graphite',.004)
    box('Mantel shelf',(0,1.24,0),(1.48,.06,.36),'walnut',.01)
    box('Hearth stone',(0,.02,.22),(1.40,.04,.48),'graphite',.008)
    for i in range(3):
        o=rod('Log',(-.24+i*.12,.16,-.20+i*.04),(.22-i*.10,.18+i*.06,-.02),.05,'walnut')
    ell('Flame',(0,.42,-.10),(.20,.34,.10),'flame'); ell('Flame',(-.14,.34,-.08),(.12,.22,.08),'ember'); ell('Flame',(.13,.36,-.09),(.11,.24,.08),'ember')
    cyl('Glow core',(0,.32,-.10),.10,.08,'flame',axis='Z')
    for x in [-.60,.60]:box('Pilaster',(x,.60,.05),(.14,1.20,.16),'cream',.01)
    cyl('Candle',(-.48,1.31,.02),.02,.10,'ivory'); ell('Candle flame',(-.48,1.38,.02),(.012,.02,.012),'flame')
    box('Picture frame',(.30,1.42,-.24),(.32,.28,.02),'oak',.006); box('Picture',(.30,1.42,-.228),(.26,.22,.004),'sky',0)

catalog={'armchair':armchair,'loveseat':loveseat,'stool':stool,'bathtub':bathtub,'mirror':mirror,'piano':piano,'chess':chess,'treadmill':treadmill,'yoga_mat':yoga_mat,'stereo':stereo,'toybox':toybox,'wardrobe':wardrobe,'garden_bed':garden_bed,'computer':computer,'wall_clock':wall_clock,'shelf':shelf,'side_table':side_table,'fireplace':fireplace}
parser=argparse.ArgumentParser()
parser.add_argument('--only',choices=tuple(catalog))
parser.add_argument('--source-out',default='art/furniture_v2.blend')
args=parser.parse_args(sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else [])
if args.only:catalog={args.only:catalog[args.only]}
for idx,(name,fn) in enumerate(catalog.items()):
    active=[]; fn()
    root=bpy.data.objects.new(name,None); bpy.context.collection.objects.link(root)
    for o in active:
        if o.parent is None:o.parent=root
    bpy.ops.object.select_all(action='DESELECT'); root.select_set(True)
    for o in active:o.select_set(True)
    bpy.context.view_layer.objects.active=root
    bpy.ops.export_scene.gltf(filepath=str(ROOT/'assets/models'/f'{name}.glb'),export_format='GLB',use_selection=True,export_apply=True,export_animations=False)
    root.location=((idx%6)*4,(idx//6)*4,0)
bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/args.source_out))
print('JUSTLIFE_FURNITURE_V2_COMPLETE', len(catalog))
