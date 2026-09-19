"""Original JustLife furniture. Run: blender -b --python tools/create_furniture.py."""
import bpy, math, random, pathlib, argparse, sys
from mathutils import Vector
ROOT = pathlib.Path(__file__).resolve().parents[1]
random.seed(23)
bpy.ops.wm.read_factory_settings(use_empty=True)
M = {}
def mat(name, hexcolor, rough=.65, metal=0):
    rgb=[int(hexcolor[i:i+2],16)/255 for i in (0,2,4)]
    linear=[v/12.92 if v<=.04045 else ((v+.055)/1.055)**2.4 for v in rgb]
    m=bpy.data.materials.new(name); m.diffuse_color=(*linear,1)
    m.use_nodes=True; p=m.node_tree.nodes.get('Principled BSDF'); p.inputs['Base Color'].default_value=m.diffuse_color
    p.inputs['Roughness'].default_value=rough; p.inputs['Metallic'].default_value=metal; M[name]=m; return m
for n,h in [('oak','AB7951'),('oak_light','D7AE7E'),('walnut','624435'),('cream','EFE9DA'),('white','FAF6EA'),('teal','417A71'),('teal_light','86ADA0'),('coral','C97C66'),('gold','C8A562'),('dark','263E3C'),('black','1D292B'),('green','48794B'),('leaf_light','749752'),('soil','42352D'),('blue','7CA4AA'),('screen','406C72'),('linen','DECFAF'),('book','B6B29C')]: mat(n,h)
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
def cyl(n,p,r,h,m,top=None):
    bpy.ops.mesh.primitive_cone_add(vertices=32,radius1=r,radius2=r if top is None else top,depth=h,location=xyz(p)); o=bpy.context.object
    bevel=o.modifiers.new('Rounded rims','BEVEL'); bevel.width=.012; bevel.segments=3
    for f in o.data.polygons:f.use_smooth=True
    return finish(o,n,m)
def rod(n,a,b,r,m):
    av,bv=Vector(xyz(a)),Vector(xyz(b)); d=bv-av
    bpy.ops.mesh.primitive_cylinder_add(vertices=12,radius=r,depth=d.length,location=(av+bv)/2); o=bpy.context.object; o.rotation_euler=d.to_track_quat('Z','Y').to_euler(); return finish(o,n,m)
def legs(w,d,h,m='oak'):
    for x in [-w/2+.10,w/2-.10]:
        for z in [-d/2+.10,d/2-.10]:box('Tapered leg',(x,h/2,z),(.065,h,.065),m,.012)
def plant_at(x,y,z,scale=1):
    cyl('Ceramic planter',(x,y+.20*scale,z),.18*scale,.4*scale,'coral',.23*scale)
    cyl('Potting soil',(x,y+.405*scale,z),.2*scale,.02*scale,'soil')
    for i in range(9):
        a=i*2.399; height=(.7+(i%3)*.15)*scale
        end=(x+math.sin(a)*.3*scale,y+height,z+math.cos(a)*.3*scale)
        rod('Leaf stem',(x,y+.4*scale,z),end,.012*scale,'green')
        leaf=ell('Satin leaf',end,(.12*scale,.22*scale,.045*scale),'green' if i%2 else 'leaf_light'); leaf.rotation_euler=(.5*math.sin(a),.45, a)
def sofa():
    legs(2.6,.95,.22,'walnut'); box('Sofa base',(0,.32,0),(2.6,.30,.94),'teal',.09)
    box('Upholstered back',(0,.77,-.37),(2.6,.75,.22),'teal',.11)
    for x in [-1.18,1.18]:box('Rounded arm',(x,.58,0),(.25,.59,1),'teal',.1)
    for x in [-.7,0,.7]:
        box('Seat cushion',(x,.55,.06),(.68,.22,.72),'teal_light',.08)
        box('Back cushion',(x,.86,-.26),(.69,.55,.19),'teal_light',.08)
    for x,m in [(-.84,'cream'),(.84,'coral')]:
        o=box('Linen scatter cushion',(x,.86,-.02),(.4,.4,.18),m,.10); o.rotation_euler[1]=.20
def bed():
    legs(1.85,2.25,.25,'walnut'); box('Oak frame',(0,.31,0),(1.88,.25,2.3),'oak',.055)
    box('Padded headboard',(0,.8,-1.06),(1.95,1.20,.14),'coral',.075)
    box('Mattress',(0,.51,0),(1.8,.26,2.13),'white',.12)
    box('Linen duvet',(0,.68,.3),(1.82,.16,1.53),'teal_light',.09)
    box('Turned duvet edge',(0,.74,-.34),(1.82,.11,.26),'cream',.05)
    for x in [-.46,.46]:box('Plump pillow',(x,.71,-.76),(.69,.18,.46),'white',.09)
    box('Woven runner',(0,.78,.82),(1.84,.055,.38),'linen',.025)
    for x in [-.8,-.6,-.4,-.2,0,.2,.4,.6,.8]:box('Runner stitch',(x,.811,.82),(.012,.008,.36),'cream',0)
def fridge():
    box('Refrigerator',(0,.94,0),(.87,1.88,.77),'cream',.07)
    box('Freezer door',(0,1.56,.406),(.81,.50,.07),'teal_light',.045)
    box('Fresh food door',(0,.65,.406),(.81,1.23,.07),'teal_light',.045)
    for y,h in [(1.56,.27),(.91,.45)]:rod('Brass handle',(-.29,y-h/2,.49),(-.29,y+h/2,.49),.023,'gold')
    box('Note',(0.13,1.4,.45),(.2,.18,.008),'cream',.002)
def counter():
    box('Cabinet',(0,.43,0),(1,.84,.72),'teal',.035); box('Stone countertop',(0,.90,0),(1.05,.10,.78),'cream',.025)
    for x in [-.25,.25]:
        box('Shaker door',(x,.46,.369),(.45,.67,.02),'teal_light',.015); rod('Cabinet pull',(x-.10,.65,.41),(x+.10,.65,.41),.012,'gold')
def stove():
    # A real hollow appliance. The external footprint and cooktop remain the
    # original dimensions used by navigation and supported meal placement.
    for x in [-.46,.46]:box('Enamel side',(x,.46,0),(.08,.90,.74),'cream',.024)
    box('Enamel back',(0,.46,-.335),(.85,.90,.07),'cream',.024)
    box('Lower plinth',(0,.23,0),(.86,.44,.73),'cream',.02)
    box('Warming drawer face',(0,.25,.38),(.84,.30,.035),'teal_light',.016)
    rod('Warming drawer pull',(-.25,.36,.43),(.25,.36,.43),.016,'gold')
    box('Control panel',(0,.837,.331),(.86,.145,.082),'cream',.02)
    box('Cavity roof',(0,.767,-.01),(.85,.04,.64),'black',.009)
    box('Cavity floor',(0,.49,-.01),(.85,.04,.64),'black',.009)
    box('Cavity back',(0,.625,-.29),(.85,.27,.025),'black',.009)
    for x in [-.412,.412]:box('Cavity lining',(x,.625,-.01),(.02,.27,.60),'dark',.006)
    for y in [.55,.65]:
        for x in [-.40,.40]:rod('Rack support',(x,y,-.23),(x,y,.27),.009,'gold')
    rack_carrier=bpy.data.objects.new('OvenRackCarrier',None);bpy.context.collection.objects.link(rack_carrier);active.append(rack_carrier)
    rack_parts=[]
    for z in [-.23,-.13,-.03,.07,.17,.27,.33]:rack_parts.append(rod('Rack wire',(-.393,.554,z),(.393,.554,z),.005,'gold'))
    for x in [-.393,.393]:rack_parts.append(rod('Rack frame',(x,.554,-.23),(x,.554,.34),.009,'gold'))
    rack_parts.append(rod('Rack front grip',(-.15,.554,.34),(.15,.554,.34),.010,'gold'))
    bpy.context.view_layer.update()
    for o in rack_parts:
        world=o.matrix_world.copy();o.parent=rack_carrier;o.matrix_world=world
    box('Cooktop',(0,.94,0),(1.02,.065,.77),'black',.02)
    for x in [-.25,.25]:
        for z in [-.20,.20]:
            cyl('Burner',(x,.98,z),.14,.015,'dark'); cyl('Burner ring',(x,.991,z),.095,.009,'black')
    pivot=bpy.data.objects.new('OvenDoor',None);bpy.context.collection.objects.link(pivot)
    pivot.location=xyz((0,.45,.385));active.append(pivot)
    door_parts=[]
    def door_box(n,p,s,m,bevel=.01):
        o=box(n,p,s,m,bevel);door_parts.append(o);return o
    # Inner panel sits behind the window; dark glass does not expose a false
    # empty cavity while closed. All door pieces share the lower hinge.
    door_box('Door inner enamel',(0,.6075,.385),(.87,.315,.056),'dark',.025)
    door_box('Oven window',(0,.605,.421),(.69,.205,.018),'black',.035)
    door_box('Glass reflection',(-.18,.605,.433),(.12,.145,.004),'screen',.01)
    for x in [-.405,.405]:door_box('Door edge',(x,.6075,.423),(.055,.305,.055),'cream',.012)
    for y in [.478,.738]:door_box('Door edge',(0,y,.423),(.81,.052,.055),'cream',.012)
    handle=rod('Oven handle',(-.36,.70,.482),(.36,.70,.482),.027,'gold');door_parts.append(handle)
    for x in [-.31,.31]:
        handle=rod('Handle mount',(x,.70,.422),(x,.70,.482),.019,'gold');door_parts.append(handle)
    bpy.context.view_layer.update()
    for o in door_parts:
        world=o.matrix_world.copy();o.parent=pivot;o.matrix_world=world
    # Exported reference nodes are authored in metres, not inferred bounds.
    for name,p,parent in [('OvenRack',(0,.565,.17),rack_carrier),('OvenRackGrip',(-.12,.554,.34),rack_carrier),('OvenHandleGrip',(0,.70,.49),pivot)]:
        o=bpy.data.objects.new(name,None);bpy.context.collection.objects.link(o);o.location=xyz(p);active.append(o)
        if parent:
            bpy.context.view_layer.update();world=o.matrix_world.copy();o.parent=parent;o.matrix_world=world
    for x in [-.3,-.1,.1,.3]:ell('Dial',(x,.85,.398),(.037,.037,.023),'dark')
    cyl('Sauce pot',(-.25,1.075,-.20),.14,.16,'coral'); cyl('Lid',(-.25,1.17,-.20),.15,.035,'cream'); ell('Pot grip',(-.25,1.205,-.2),(.04,.025,.04),'walnut')
def sink():
    counter(); box('Basin rim',(0,.963,0),(.73,.02,.51),'white',.08); box('Basin interior',(0,.976,.04),(.59,.016,.36),'blue',.08)
    rod('Tap stem',(.25,.96,-.22),(.25,1.24,-.22),.025,'gold'); rod('Tap spout',(.25,1.24,-.22),(.08,1.24,-.08),.025,'gold')
def toilet():
    ell('Pedestal',(0,.21,-.05),(.21,.24,.23),'white'); ell('Bowl',(0,.42,.10),(.31,.20,.40),'white')
    ell('Seat',(0,.57,.12),(.30,.045,.38),'cream'); ell('Seat opening',(0,.608,.13),(.20,.01,.26),'dark')
    box('Cistern',(0,.71,-.31),(.55,.60,.25),'white',.08); box('Cistern lid',(0,1.02,-.31),(.58,.06,.28),'cream',.025)
    cyl('Flush button',(0,1.055,-.31),.04,.01,'gold')
def shower():
    box('Shower tray',(0,.075,0),(1.25,.15,1.20),'white',.06); box('Shower floor',(0,.157,0),(1.08,.015,1.04),'blue',.04)
    for x in [-.58,.58]:
        rod('Brass frame',(x,.15,-.53),(x,2.20,-.53),.022,'gold')
    box('Tile back',(0,1.17,-.56),(1.20,2.08,.06),'teal_light',.02)
    for y in [.45,.8,1.15,1.5,1.85]:box('Tile joint',(0,y,-.523),(1.16,.009,.002),'white',0)
    rod('Rain shower riser',(.28,.9,-.48),(.28,2.04,-.48),.018,'gold'); rod('Rain shower arm',(.28,2.04,-.48),(.28,2.04,-.14),.018,'gold')
    cyl('Rain shower head',(.28,2.025,-.14),.13,.035,'gold'); ell('Control',(.28,1.0,-.455),(.07,.07,.03),'gold')
    for x in [-.58,.58]:rod('Open stall trim',(x,.15,.53),(x,2.2,.53),.012,'gold')
    rod('Top rail',(-.58,2.2,.53),(.58,2.2,.53),.015,'gold')
def table():
    legs(1.8,.85,.43); box('Coffee table top',(0,.48,0),(1.85,.09,.90),'oak_light',.1)
    box('Art book',(-.3,.55,0),(.38,.045,.27),'coral',.005); box('Pages',(-.3,.557,0),(.35,.025,.28),'white',.002)
    cyl('Ceramic cup',(.38,.61,.05),.065,.16,'cream')
def dining():
    legs(1.5,1.0,.76); box('Dining top',(0,.80,0),(1.6,.09,1.12),'oak_light',.12)
    cyl('Fruit bowl',(0,.9,0),.20,.1,'cream',.25)
    for x,z,m in [(-.08,0,'coral'),(.09,.03,'gold'),(0,-.09,'leaf_light')]:ell('Fruit',(x,.99,z),(.09,.09,.09),m)
def chair():
    legs(.52,.55,.44); box('Chair seat',(0,.47,0),(.57,.1,.59),'cream',.08)
    rod('Back support',(-.22,.43,-.22),(-.22,.98,-.26),.026,'oak'); rod('Back support',(.22,.43,-.22),(.22,.98,-.26),.026,'oak')
    box('Chair back',(0,.87,-.25),(.53,.32,.08),'oak_light',.08)
def desk():
    legs(1.55,.70,.77); box('Writing surface',(0,.82,0),(1.65,.1,.77),'oak_light',.035)
    box('Laptop base',(0,.889,.08),(.49,.035,.31),'dark',.014)
    o=box('Laptop display',(0,1.06,-.07),(.49,.32,.025),'dark',.013); o.rotation_euler[0]=-.14
    box('Screen content',(0,1.06,-.048),(.44,.26,.006),'screen',.003)
    for i,w in enumerate([.24,.33,.18]):box('Onscreen line',(-.035,1.13-i*.045,-.042),(w,.008,.002),'teal_light',0)
    cyl('Pen pot',(.56,.95,-.13),.07,.19,'coral')
    for i in range(3):rod('Pencil',(.54+i*.025,.94,-.13),(.54+i*.025,1.13,-.13),.006,'gold')
def bookshelf():
    for x in [-.64,.64]:box('Bookcase upright',(x,.93,0),(.09,1.86,.39),'oak',.014)
    box('Bookcase back',(0,.93,-.18),(1.29,1.86,.045),'oak_light',.01)
    for y in [.06,.49,.93,1.36,1.8]:box('Shelf',(0,y,0),(1.32,.07,.42),'oak',.012)
    for j,y in enumerate([.31,.74,1.18,1.61]):
        for i in range(10):
            x=-.51+i*.105; h=random.uniform(.20,.32); o=box('Book',(x,y-.13+h/2,0),(.07,h,.24),['coral','teal','cream','blue','book'][(i+j)%5],.003)
            if i==9:o.rotation_euler[1]=-.16
            box('Book spine band',(x,y-.12+h*.7,.125),(.053,.016,.002),'gold',0)
def easel():
    for x in [-.36,.36]:rod('Easel leg',(x,0,.2),(x*.35,1.78,-.15),.028,'oak')
    rod('Back leg',(0,0,-.6),(0,1.55,-.1),.025,'oak'); box('Canvas support',(0,.73,.03),(.88,.065,.13),'oak',.01)
    box('Stretched canvas',(0,1.21,-.04),(.79,.91,.055),'cream',.008)
    # Original abstract sunset painting built from simple meshes.
    box('Painted blue field',(0,1.17,-.002),(.70,.35,.004),'blue',0)
    ell('Painted sun',(.18,1.4,.004),(.13,.13,.003),'coral')
    ell('Painted landscape',(-.17,1.10,.01),(.23,.18,.004),'teal')
    box('Painted foreground',(0,.87,.015),(.70,.12,.005),'teal',0)
def tv():
    legs(1.9,.4,.17); box('Media cabinet',(0,.37,0),(2,.4,.48),'oak',.035)
    for x in [-.49,.49]:box('Media door',(x,.36,.25),(.93,.3,.035),'oak_light',.02)
    box('Television',(0,1.04,-.08),(1.45,.88,.065),'black',.04); box('Television screen',(0,1.04,-.041),(1.34,.77,.006),'screen',.018)
    box('Abstract screen horizon',(0,.85,-.035),(1.32,.24,.003),'teal',0); ell('Screen sun',(.3,1.24,-.03),(.15,.15,.002),'gold')
    for x in [-.46,.46]:rod('TV stand',(x,.61,.07),(x*.8,.73,-.07),.02,'black')
def lamp():
    cyl('Lamp foot',(0,.045,0),.25,.07,'gold'); rod('Lamp stem',(0,.08,0),(0,1.48,0),.027,'gold')
    cyl('Woven lampshade',(0,1.53,0),.34,.37,'cream',.23)
    for i in range(24):
        a=i*math.tau/24; rod('Shade weave',(.34*math.sin(a),1.35,.34*math.cos(a)),(.23*math.sin(a),1.715,.23*math.cos(a)),.004,'linen')
def nightstand():
    legs(.53,.47,.14); box('Bedside cabinet',(0,.36,0),(.58,.45,.51),'oak_light',.025)
    box('Bedside drawer',(0,.38,.266),(.49,.19,.025),'cream',.015); ell('Drawer knob',(0,.38,.298),(.03,.03,.03),'gold')
    cyl('Bedside lamp base',(0,.62,0),.11,.04,'gold'); ell('Bedside lamp',(0,.78,0),(.14,.16,.14),'cream')
def rug():
    box('Woven rug',(0,.014,0),(3.4,.025,2.2),'linen',.018)
    for x in [-1.57,1.57]:box('Rug border',(x,.029,0),(.04,.003,2.05),'coral',0)
    for z in [-.98,.98]:box('Rug border',(0,.03,z),(3.1,.003,.04),'coral',0)
    for i in range(28):
        x=-1.55+i*.115
        for z in [-1.14,1.14]:box('Woven fringe',(x,.015,z),(.015,.016,.12),'cream',.003)
def plant():plant_at(0,0,0,1.25)
def painting():
    box('Oak picture frame',(0,1,0),(1.20,.9,.055),'oak',.015); box('Canvas',(0,1,.032),(1.08,.78,.015),'cream',0)
    ell('Sun',(.23,1.14,.045),(.18,.18,.004),'coral'); ell('Hill',(-.22,.9,.052),(.30,.21,.004),'teal'); box('Low field',(0,.7,.06),(1.07,.17,.004),'blue',0)

def bench():
    for x in [-.78,.78]:
        rod('Cast iron leg',(x,.05,-.22),(x,.5,-.22),.036,'teal')
        rod('Cast iron leg',(x,.05,.24),(x,.5,.24),.036,'teal')
        rod('Back support',(x,.43,-.27),(x,1,-.27),.025,'teal')
        rod('Bench arm',(x,.73,-.26),(x,.73,.3),.029,'teal')
        rod('Arm upright',(x,.48,.28),(x,.72,.28),.025,'teal')
    for z in [-.23,-.08,.07,.22]:box('Seat slat',(0,.49,z),(2,.065,.12),'oak_light',.025)
    for y in [.71,.89]:box('Back slat',(0,y,-.29),(2,.14,.055),'oak_light',.025)

catalog={'bench':bench,'sofa':sofa,'bed':bed,'fridge':fridge,'counter':counter,'stove':stove,'sink':sink,'toilet':toilet,'shower':shower,'table':table,'dining':dining,'chair':chair,'desk':desk,'bookshelf':bookshelf,'easel':easel,'tv':tv,'lamp':lamp,'nightstand':nightstand,'rug':rug,'plant':plant,'painting':painting}
parser=argparse.ArgumentParser()
parser.add_argument('--only',choices=tuple(catalog))
parser.add_argument('--source-out',default='art/furniture.blend')
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
    root.location=((idx%5)*4,(idx//5)*4,0)
bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/args.source_out))
print('JUSTLIFE_FURNITURE_COMPLETE', len(catalog))
