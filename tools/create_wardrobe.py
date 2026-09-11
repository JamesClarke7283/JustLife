"""Add JustLife's second wardrobe and hair set to the editable character sources and export the game models.

    blender -b --python tools/create_wardrobe.py -- --family all --export

Adds to each age family (adult, child, teen, elder), derived from that family's own accepted geometry:
  Outfit_Tee      plain crew tee from the casual shirt body, cuffs and hem (no collar, placket or buttons)
  Outfit_Hoodie   the cropped jacket shell with a soft down-hood cowl, kangaroo pocket and drawstrings
  Skin_Leg_continuous   leg skin beneath every bottom, so shorter bottoms expose real legs
  Bottom_Shorts   the shared trousers cut above the knee with a folded cuff on each leg
  Hair_Pony       the Bob cap with a swept tail and band
  Hair_Long       the Bob with locks lengthened and tapered to the shoulder blades
  Hair_Buzz       the Crop cap alone, drawn in tight
Existing objects are never modified; a rerun removes and rebuilds only these additions. Exports follow
tools/export_character_variant.py (zeroed morphs, rest pose, broad X scale 1.12, decimated live LOD).
"""
import bpy, bmesh, math, sys, argparse, pathlib, tempfile, os, hashlib, json
from mathutils import Vector
ROOT=pathlib.Path(__file__).resolve().parents[1]
parser=argparse.ArgumentParser()
parser.add_argument('--family',choices=['adult','child','teen','elder','all'],default='all')
parser.add_argument('--export',action='store_true')
parser.add_argument('--save',action='store_true',help='write the authored additions back into the editable sources (implied by --export)')
parser.add_argument('--preview-dir',type=pathlib.Path,default=None)
args=parser.parse_args(sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else [])
FAMILIES=['adult','child','teen','elder'] if args.family=='all' else [args.family]
GROUPS=['Root','Spine','Head','Arm_L','Forearm_L','Arm_R','Forearm_R','Leg_L','Shin_L','Leg_R','Shin_R']
NEW_PREFIXES=('Outfit_Tee','Outfit_Hoodie','Skin_Leg_continuous','Bottom_Shorts','Hair_Pony','Hair_Long','Hair_Buzz')
D=bpy.data

def link(o,parent):
    if o.name not in bpy.context.scene.collection.objects:bpy.context.scene.collection.objects.link(o)
    o.parent=parent
    # Meshes are authored in world metres; keep them there under pivots such as the Head.
    o.matrix_parent_inverse=parent.matrix_world.inverted()
def empty(name,parent):
    e=D.objects.new(name,None); link(e,parent); return e
def new_mesh_object(name,bm,material,parent):
    me=D.meshes.new(name); bm.to_mesh(me); bm.free(); me.materials.append(D.materials[material])
    o=D.objects.new(name,me); link(o,parent)
    for p in me.polygons:p.use_smooth=True
    return o
def ensure_groups(o):
    for g in GROUPS:
        if g not in o.vertex_groups:o.vertex_groups.new(name=g)
def skin_like(o,source,rig):
    ensure_groups(o)
    mod=o.modifiers.new('Weights','DATA_TRANSFER'); mod.object=source; mod.use_vert_data=True; mod.data_types_verts={'VGROUP_WEIGHTS'}; mod.vert_mapping='NEAREST'; mod.layers_vgroup_select_src='ALL'; mod.layers_vgroup_select_dst='NAME'
    with bpy.context.temp_override(object=o,active_object=o,selected_objects=[o]):bpy.ops.object.modifier_apply(modifier=mod.name)
    arm=o.modifiers.new('Soft skeletal deformation','ARMATURE'); arm.object=rig
def rigid_group(o,group,rig):
    ensure_groups(o); o.vertex_groups[group].add(list(range(len(o.data.vertices))),1.0,'REPLACE')
    arm=o.modifiers.new('Soft skeletal deformation','ARMATURE'); arm.object=rig
def duplicate(src,name,parent):
    o=src.copy(); o.data=src.data.copy(); o.name=name; o.data.name=name; link(o,parent); o.matrix_world=src.matrix_world.copy()
    for m in list(o.modifiers):
        if m.type!='ARMATURE':o.modifiers.remove(m)
    return o
def surface(fn,nu,nv,closed_u=False,closed_v=False):
    bm=bmesh.new(); verts=[[bm.verts.new(fn(i/(nu if closed_u else nu-1),j/(nv if closed_v else nv-1))) for j in range(nv)] for i in range(nu)]
    for i in range(nu if closed_u else nu-1):
        for j in range(nv if closed_v else nv-1):
            a=verts[i][j];b=verts[(i+1)%nu][j];c=verts[(i+1)%nu][(j+1)%nv];d=verts[i][(j+1)%nv]
            try:bm.faces.new((a,b,c,d))
            except ValueError:pass
    bmesh.ops.recalc_face_normals(bm,faces=bm.faces); return bm
def shrink(o,amount):
    bm=bmesh.new(); bm.from_mesh(o.data)
    for v in bm.verts:v.co-=v.normal*amount
    bm.to_mesh(o.data); bm.free()
def delete_where(o,pred):
    bm=bmesh.new(); bm.from_mesh(o.data); doomed=[v for v in bm.verts if pred(o.matrix_world@v.co)]; bmesh.ops.delete(bm,geom=doomed,context='VERTS'); bm.to_mesh(o.data); bm.free()
def world_points(o):return [o.matrix_world@v.co for v in o.data.vertices]
def bounds(o):
    pts=world_points(o); return Vector((min(p.x for p in pts),min(p.y for p in pts),min(p.z for p in pts))),Vector((max(p.x for p in pts),max(p.y for p in pts),max(p.z for p in pts)))
def remove_previous():
    for o in [o for o in D.objects if o.name.startswith(NEW_PREFIXES)]:
        data=o.data; D.objects.remove(o)
        if data is not None and data.users==0:
            (D.meshes if isinstance(data,bpy.types.Mesh) else D.curves).remove(data)

def author(family):
    root=D.objects['Character']; rig=D.objects['LifeRig']; head=D.objects['Head']
    shirt=D.objects['Outfit_Casual_Shirt']; shell=D.objects['Outfit_Jacket_Shell']; trousers=D.objects['Bottom_Continuous_trousers']
    remove_previous()
    s_lo,s_hi=bounds(shirt); j_lo,j_hi=bounds(shell); scale=(s_hi.x-s_lo.x)/0.556   # adult shirt width is the reference
    # ---- Tee
    tee=empty('Outfit_Tee',root); duplicate(shirt,'Outfit_Tee_Shirt',tee)
    for n,suffix in [('Outfit_Casual_Top_Sleeve_cuff','Sleeve_cuff'),('Outfit_Casual_Top_Sleeve_cuff.001','Sleeve_cuff.001'),('Outfit_Casual_Top_Hem','Hem')]:duplicate(D.objects[n],'Outfit_Tee_'+suffix,tee)
    # ---- Hoodie
    hood=empty('Outfit_Hoodie',root); hshell=duplicate(shell,'Outfit_Hoodie_Shell',hood)
    for n,suffix in [('Outfit_Jacket_Cuff','Cuff'),('Outfit_Jacket_Cuff.001','Cuff.001'),('Outfit_Jacket_Waist_rib','Waist_rib')]:duplicate(D.objects[n],'Outfit_Hoodie_'+suffix,hood)
    neck=Vector((0,.015*scale,j_hi.z-.011))
    def cowl(u,v):
        # A hood lying down: a full soft roll behind the neck that thins toward the collarbones.
        a=(u-.5)*math.radians(200); b=v*math.tau; back=max(0.0,math.cos(a)); R=(.098+.026*back)*scale; r=(.028+.030*back*back)*scale
        return neck+Vector((math.sin(a)*(R+r*math.cos(b)),math.cos(a)*(R+r*math.cos(b))+.012*scale,r*math.sin(b)*1.1+(.012+.03*back)*scale-.025*scale*abs(math.sin(a))))
    c=new_mesh_object('Outfit_Hoodie_Hood',surface(cowl,28,14,False,True),'Top',hood); rigid_group(c,'Spine',rig)
    shell_pts=world_points(hshell); h=j_hi.z-j_lo.z
    def smooth_front_y(x0,z0,rad=.035*scale):
        near=[p.y for p in shell_pts if abs(p.x-x0)<rad and abs(p.z-z0)<rad and p.y<0]
        return (sum(near)/len(near)) if near else j_lo.y
    rib_lo,rib_hi=bounds(D.objects['Outfit_Jacket_Waist_rib'])
    def pocket(u,v):
        x=(-.125+.25*u)*scale; z=rib_hi.z+.012*scale+.105*scale*v; edge=1-.15*(1-math.sin(math.pi*u))
        return Vector((x*edge,smooth_front_y(x,z)-.013*scale,z))
    pk=new_mesh_object('Outfit_Hoodie_Pocket',surface(pocket,14,7),'Top',hood)
    bm=bmesh.new(); bm.from_mesh(pk.data); res=bmesh.ops.extrude_edge_only(bm,edges=[e for e in bm.edges if e.is_boundary])
    for v in [g for g in res['geom'] if isinstance(g,bmesh.types.BMVert)]:v.co.y+=.013*scale
    bmesh.ops.recalc_face_normals(bm,faces=bm.faces); bm.to_mesh(pk.data); bm.free()
    for f in pk.data.polygons:f.use_smooth=True
    skin_like(pk,hshell,rig)
    for i,x0 in enumerate((-.03*scale,.03*scale)):
        path=[]
        for k in range(9):
            z=j_hi.z-.06*scale-k*.017*scale; x=x0*(1+.25*k/8); path.append(Vector((x,smooth_front_y(x,z,.025*scale)-.006*scale,z)))
        def tube(u,v,path=path):
            idx=v*(len(path)-1); a=int(idx); b=min(a+1,len(path)-1); t=idx-a; cc=path[a].lerp(path[b],t); ang=u*math.tau; r=.0045*scale
            return cc+Vector((math.cos(ang)*r,-abs(math.sin(ang))*r*.6,math.sin(ang)*r))
        ds=new_mesh_object('Outfit_Hoodie_Drawstring'+('' if i==0 else '.001'),surface(tube,8,9,True,False),'Top_seam',hood); rigid_group(ds,'Spine',rig)
    # ---- Legs and shorts
    t_lo,t_hi=bounds(trousers); knee=float(root.get('knee_height',0.548*scale)) if 'knee_height' in root.keys() else 0.548*scale
    cut=knee+.07*scale
    legs=duplicate(trousers,'Skin_Leg_continuous',root); legs.data.materials.clear(); legs.data.materials.append(D.materials['Skin'])
    legs.shape_key_clear()   # bare legs need no cloth corrective, and this lets the live LOD decimate them
    shrink(legs,.013*scale); delete_where(legs,lambda p:p.z<t_lo.z-.005 or p.z>t_lo.z+(t_hi.z-t_lo.z)*.94)
    bm=bmesh.new(); bm.from_mesh(legs.data)
    for v in bm.verts:
        wz=(legs.matrix_world@v.co).z; bulge=.007*scale*math.exp(-((wz-knee)/(.055*scale))**2)   # a gentle kneecap
        v.co+=v.normal*bulge
    bm.to_mesh(legs.data); bm.free()
    shorts=duplicate(trousers,'Bottom_Shorts',root)
    bm=bmesh.new(); bm.from_mesh(shorts.data); inv=shorts.matrix_world.inverted()
    bmesh.ops.bisect_plane(bm,geom=bm.verts[:]+bm.edges[:]+bm.faces[:],plane_co=inv@Vector((0,0,cut)),plane_no=(inv.to_3x3()@Vector((0,0,1))).normalized(),clear_inner=True,clear_outer=False)
    bm.to_mesh(shorts.data); bm.free()
    pts=world_points(trousers)
    for side,sgn in (('L',1),('R',-1)):
        sel=[p for p in pts if cut-.015<=p.z<=cut+.015 and p.x*sgn>.02*scale]
        cc=sum(sel,Vector())/len(sel); rr=sum(((p-cc).xy.length for p in sel))/len(sel)
        def cuff(u,v,cc=cc,rr=rr):
            a=u*math.tau; b=v*math.tau; R=rr+.006*scale; r=.014*scale
            return Vector((cc.x+math.cos(a)*(R+r*math.cos(b)),cc.y+math.sin(a)*(R+r*math.cos(b)),cut+r*math.sin(b)))
        o=new_mesh_object('Bottom_Shorts_Cuff'+('' if side=='L' else '.001'),surface(cuff,36,10,True,True),'Bottom_seam',root); skin_like(o,trousers,rig)
    # ---- Hair
    def dup_group(prefix,newprefix):
        e=empty(newprefix,head); e.matrix_world=D.objects[prefix].matrix_world.copy(); made=[]
        for o in [x for x in D.objects if x.name.startswith(prefix+'_')]:
            made.append(duplicate(o,o.name.replace(prefix+'_',newprefix+'_',1),e))
        return e,made
    pony,pmade=dup_group('Hair_Bob','Hair_Pony')
    for o in pmade:
        if '_Lock' in o.name or '_Strand' in o.name:D.objects.remove(o)
    cap=D.objects['Hair_Pony_Cap']; cap_pts=world_points(cap); cz=(min(p.z for p in cap_pts)+max(p.z for p in cap_pts))*.5; hs=scale
    # The tail leaves the centre of the nape, emerging from just inside the cap, and hangs down the back.
    nape=max([p for p in cap_pts if p.z<cz+.01*hs and abs(p.x)<.02*hs],key=lambda p:p.y)
    base=Vector((0,nape.y-.012*hs,nape.z-.015*hs))
    def tail_axis(t):return base+Vector((0,.03*hs+.055*hs*t+.02*hs*math.sin(math.pi*t),-.31*hs*t))
    def tail(u,v):
        t=v; a=u*math.tau; r=.033*hs*(1-.6*t)*(1+.35*math.sin(math.pi*t))
        return tail_axis(t)+Vector((math.cos(a)*r,math.sin(a)*r*.85,0))
    new_mesh_object('Hair_Pony_Tail',surface(tail,16,14,True,False),'Hair',pony)
    ring=tail_axis(.09); axis=(tail_axis(.16)-tail_axis(.02)).normalized(); ex=Vector((1,0,0)); ey=axis.cross(ex).normalized()
    def band(u,v):
        a=u*math.tau;b=v*math.tau;R=.030*hs;r=.006*hs
        return ring+ex*(math.cos(a)*(R+r*math.cos(b)))+ey*(math.sin(a)*(R+r*math.cos(b)))+axis*(r*math.sin(b))
    new_mesh_object('Hair_Pony_Band',surface(band,24,8,True,True),'Jewelry',pony)
    longh,lmade=dup_group('Hair_Bob','Hair_Long')
    for o in lmade:
        if o.type!='MESH' or not ('_Lock' in o.name or '_Strand' in o.name):continue
        bm=bmesh.new(); bm.from_mesh(o.data); zs=[v.co.z for v in bm.verts]; top=max(zs); span=max(top-min(zs),1e-4)
        cx=sum(v.co.x for v in bm.verts)/len(bm.verts); cy=sum(v.co.y for v in bm.verts)/len(bm.verts)
        for v in bm.verts:
            f=(top-v.co.z)/span; v.co.z-=f*.12*hs; v.co.y+=f*.012*hs; v.co.x=cx+(v.co.x-cx)*(1-.45*f); v.co.y=cy+(v.co.y-cy)*(1-.45*f)
        bm.to_mesh(o.data); bm.free()
    # Long hair drapes as a full wrapped mass: it hugs the cap rim, draws in at
    # the neck, flares over the shoulder line, then settles against the back and
    # tapers to an irregular, lock-separated hem. Two thick front locks fall from
    # the swept cap sides, bow over the cheeks and taper to rounded tips.
    lcap=D.objects['Hair_Long_Cap']; lpts=world_points(lcap); centre=sum(lpts,Vector())/len(lpts)
    rear=[p for p in lpts if p.y>centre.y+.02*hs]; rim_z=min(p.z for p in rear); rim_r=max(((p-centre).xy.length for p in rear if p.z<rim_z+.03*hs))
    def wrap(u,v):
        a=(u-.5)*math.radians(300)                                   # face opening of 60 degrees at the front
        lock=math.sin(3*a+.9)                                        # three-lock phase, shared by every term
        lobes=1+.11*lock*v                                           # lock channels deepen toward the hem
        neck=.018*hs*math.exp(-(((v-.15)/.12)**2))                   # a light draw-in under the rim
        flare=.045*hs*math.exp(-(((v-.50)/.22)**2))                  # volume over the shoulder line
        R=(rim_r+.042*hs-neck+flare)*lobes
        taper=1-(.44+.09*lock)*v**1.4                                # narrow, late-biased per-lock taper
        ang=abs(math.atan2(math.sin(a),math.cos(a)))                 # 0 at the back centre, pi at the front
        hem=.225*hs+.05*hs*math.sin(min(ang,math.pi*.62))*(1+.45*lock)  # side curtains fall lowest, per lock
        jag=.05*hs*v*v*max(0.0,lock)                                 # leading lock edges fall lower
        z=rim_z+.02*hs-hem*v-jag
        settle=.04*hs*v*v*v                                          # the ends rest against the back
        return Vector((centre.x+math.sin(a)*R*taper,centre.y+math.cos(a)*R+settle,z))
    ws=new_mesh_object('Hair_Long_Back',surface(wrap,48,16),'Hair',longh)
    bm=bmesh.new(); bm.from_mesh(ws.data); res=bmesh.ops.extrude_edge_only(bm,edges=[e for e in bm.edges if e.is_boundary])
    for vtx in [g for g in res['geom'] if isinstance(g,bmesh.types.BMVert)]:vtx.co+=Vector((0,0,.010*hs))
    bmesh.ops.recalc_face_normals(bm,faces=bm.faces); bm.to_mesh(ws.data); bm.free()
    for f in ws.data.polygons:f.use_smooth=True
    front_rim=[p for p in lpts if p.y<centre.y+.005*hs]
    side_r=max((abs(p.x) for p in front_rim),default=0.0)
    z_top=max(p.z for p in lpts)
    for side,sgn in (('L',1),('R',-1)):
        crown=[p for p in lpts if abs(p.x)>.45*side_r and p.x*sgn>0 and p.z>centre.z+.12*(z_top-centre.z) and p.y<centre.y+.02*hs]
        if not crown:crown=sorted(front_rim,key=lambda p:-(p.z+.3*abs(p.x)))[6:]
        anchor=sum(crown,Vector())/len(crown)
        start=anchor+(centre-anchor)*.22
        end_z=rim_z-.205*hs
        def strand(u,v,start=start,end_z=end_z):
            t=v; q=u*math.tau
            bow=sgn*.005*hs*math.sin(math.pi*min(t*1.25,1.0))        # clears the cheek and ear
            back=.018*hs*t*t                                         # eases toward the body as it falls
            axis=start+Vector((bow,back,(end_z-start.z)*t))
            rr=.0035*hs+.013*hs*(1-t)**1.15
            return axis+Vector((math.cos(q)*rr*.66,math.sin(q)*rr,0))
        new_mesh_object('Hair_Long_Front'+('' if side=='L' else '.001'),surface(strand,14,22,True,True),'Hair',longh)
    buzz,bmade=dup_group('Hair_Crop','Hair_Buzz')
    for o in bmade:
        if not o.name.endswith('_Cap'):D.objects.remove(o)
    shrink(D.objects['Hair_Buzz_Cap'],.004*hs)
    # Hair pieces ride the Head pivot like the accepted styles; keep hide flags clear for export.
    for o in D.objects:
        if o.name.startswith(NEW_PREFIXES):o.hide_render=False;o.hide_viewport=False;o.hide_set(False)
    return dict(scale=round(scale,4),cut=round(cut,4),neck=[round(x,4) for x in neck])

def descendants(node):
    yield node
    for child in node.children:yield from descendants(child)
def export_variant(blend,variant,out):
    width=1.12 if 'broad' in variant else 1.0; low=variant.endswith('_lod')
    bpy.ops.wm.open_mainfile(filepath=str(blend)); root=D.objects['Character']; root.scale.x=width
    for o in descendants(root):
        if o.type=='MESH' and o.data.shape_keys:
            for key in o.data.shape_keys.key_blocks:key.value=0
        if low:
            if o.type=='MESH' and o.data.shape_keys is None:
                mod=o.modifiers.new('Live camera reduction','DECIMATE');mod.ratio=.12 if o.name.endswith('_Cap') else (.38 if 'Leg' in o.name else .22)
                if o.modifiers.find('Soft skeletal deformation')>=0:
                    bpy.context.view_layer.objects.active=o;bpy.ops.object.modifier_move_up(modifier=mod.name)
            elif o.type=='CURVE':o.data.resolution_u=2;o.data.bevel_resolution=1
    for bone in D.objects['LifeRig'].pose.bones:bone.rotation_euler=(0,0,0)
    bpy.ops.object.select_all(action='DESELECT')
    for o in descendants(root):o.select_set(True)
    bpy.context.view_layer.objects.active=root;bpy.context.view_layer.update();bpy.context.evaluated_depsgraph_get().update()
    out.mkdir(parents=True,exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='.export-',dir=out) as folder:
        path=pathlib.Path(folder)/(variant+'.glb')
        bpy.ops.export_scene.gltf(filepath=str(path),export_format='GLB',use_selection=True,export_apply=True,export_yup=True,export_animations=False,export_morph=True,export_skins=True,export_extras=True,export_cameras=False,export_lights=False)
        os.replace(path,out/path.name)
    return hashlib.sha256((out/(variant+'.glb')).read_bytes()).hexdigest()

report={}
for family in FAMILIES:
    blend=ROOT/'art'/('characters.blend' if family=='adult' else f'characters_{family}.blend')
    bpy.ops.wm.open_mainfile(filepath=str(blend))
    facts=author(family)
    if args.export or args.save:bpy.ops.wm.save_as_mainfile(filepath=str(blend))
    report[family]={'source':str(blend.relative_to(ROOT)),'facts':facts,'objects':len(D.objects)}
    if args.preview_dir:
        scene=bpy.context.scene; scene.camera=D.objects['Character_Portrait']; scene.render.engine='BLENDER_EEVEE'; scene.render.resolution_x=600; scene.render.resolution_y=900
        for o in D.objects:
            if o.type in ('MESH','CURVE','EMPTY'):o.hide_render=False
        offs=('Outfit_Casual','Outfit_Jacket','Outfit_Cardigan','Outfit_Tee','Outfit_Hoodie','Bottom_Continuous','Bottom_Cuff','Bottom_Shorts','Hair_Bob','Hair_Crop','Hair_Curls','Hair_Long','Hair_Pony','Hair_Buzz')
        for name,on in [('tee_shorts_pony',('Outfit_Tee','Bottom_Shorts','Hair_Pony')),('hoodie_trousers_long',('Outfit_Hoodie','Bottom_Continuous','Bottom_Cuff','Hair_Long')),('casual_shorts_buzz',('Outfit_Casual','Bottom_Shorts','Hair_Buzz'))]:
            for o in D.objects:
                if o.name.startswith(offs):o.hide_render=True
                if o.name.startswith(on):o.hide_render=False
            args.preview_dir.mkdir(parents=True,exist_ok=True); scene.render.filepath=str(args.preview_dir/f'{family}_{name}.png'); bpy.ops.render.render(write_still=True)
            # A matching rear view, orbiting the portrait camera half a turn around the character.
            cam=scene.camera; saved=cam.matrix_world.copy(); loc=cam.matrix_world.translation.copy(); target=Vector((0,0,loc.z*.62))
            cam.matrix_world.translation=Vector((-loc.x,-loc.y,loc.z)); cam.rotation_euler=(target-cam.matrix_world.translation).to_track_quat('-Z','Y').to_euler()
            scene.render.filepath=str(args.preview_dir/f'{family}_{name}_rear.png'); bpy.ops.render.render(write_still=True); cam.matrix_world=saved
    if args.export:
        base='character' if family=='adult' else f'character_{family}'
        hashes={}
        for variant in [base,base+'_broad',base+'_lod',base+'_broad_lod']:
            hashes[variant+'.glb']=export_variant(blend,variant,ROOT/'assets/models')
        report[family]['exports']=hashes
print('JUSTLIFE_WARDROBE_REPORT '+json.dumps(report))
